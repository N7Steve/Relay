package app.relay.android.data

import android.os.Build
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject

interface StateStore {
    fun read(): DiskState
    fun write(state: DiskState)
}

data class DeviceInfo(val name: String, val osVersion: String, val appVersion: String) {
    companion object {
        fun current(appVersion: String) = DeviceInfo(
            name = listOf(Build.MANUFACTURER, Build.MODEL).filterNot { it.isNullOrBlank() }.joinToString(" ").ifBlank { "Android" },
            osVersion = Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT.toString(),
            appVersion = appVersion,
        )
    }
}

/**
 * Owns the encrypted session: login with optional MFA, token refresh and
 * revocation, plus the cached summary shown while a refresh is in flight.
 */
class RelayRepository(
    private val store: StateStore,
    private val device: DeviceInfo,
    private val api: RelayApi = RelayApi(),
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val mutable = MutableStateFlow<DiskState?>(null)
    /** null until the encrypted state has been read. */
    val state: StateFlow<DiskState?> = mutable.asStateFlow()
    private val writes = Mutex()
    private val refreshing = Mutex()

    suspend fun initialize() = writes.withLock {
        if (mutable.value != null) return@withLock
        mutable.value = runCatching { store.read() }.getOrElse { DiskState() }
    }

    private suspend fun save(transform: (DiskState) -> DiskState): DiskState = writes.withLock {
        val next = transform(mutable.value ?: DiskState())
        store.write(next)
        mutable.value = next
        next
    }

    suspend fun login(server: String, email: String, password: String, otp: String, clientId: String, clientSecret: String) {
        val origin = serverUrl(server).toString()
        val current = mutable.value ?: DiskState()
        val access = CloudflareAccess.fromInput(clientId, clientSecret)
        val deviceId = current.deviceId.ifEmpty { UUID.randomUUID().toString() }
        val draft = DiskState(server = origin, deviceId = deviceId, cloudflareAccess = access)
        val body = fields(
            "email" to value(email.trim()),
            "password" to value(password),
            "device" to deviceFields(deviceId),
        ).let { if (otp.isNotBlank()) JsonObject(it + ("otp_code" to value(otp.filter(Char::isDigit)))) else it }
        val response = api.json.decodeFromString<TokenResponse>(api.request(draft, "/auth/login", "POST", body))
        val user = requireNotNull(response.user) { "El servidor no devolvió el usuario." }
        save { draft.copy(tokens = response.tokens(clock()), user = user) }
    }

    private fun deviceFields(deviceId: String) = fields(
        "device_id" to value(deviceId),
        "device_name" to value(device.name),
        "device_type" to value("android"),
        "os_version" to value(device.osVersion),
        "app_version" to value(device.appVersion),
    )

    /** Signed-in state whose access token is valid for at least another minute. */
    suspend fun fresh(): DiskState {
        val state = mutable.value?.takeIf { it.signedIn } ?: throw SessionExpiredException()
        return if (state.tokens!!.expiresAt - clock() > 60_000) state else refresh(state.tokens.accessToken)
    }

    private suspend fun refresh(expiredAccessToken: String): DiskState = refreshing.withLock {
        val state = mutable.value?.takeIf { it.signedIn } ?: throw SessionExpiredException()
        // Another caller already refreshed while this one waited.
        if (state.tokens!!.accessToken != expiredAccessToken && state.tokens.expiresAt - clock() > 60_000) return state
        val body = fields("refresh_token" to value(state.tokens.refreshToken), "device" to deviceFields(state.deviceId))
        val response = try {
            api.json.decodeFromString<TokenResponse>(api.request(state, "/auth/refresh", "POST", body))
        } catch (error: ApiException) {
            if (error.status == 401) { expire(); throw SessionExpiredException() }
            throw error
        }
        save { it.copy(tokens = response.tokens(clock())) }
    }

    /** Authenticated request that refreshes once when the access token is rejected. */
    suspend fun authorized(
        path: String,
        query: List<Pair<String, String>> = emptyList(),
        method: String = "GET",
        body: JsonObject? = null,
    ): String {
        val state = fresh()
        return try {
            api.request(state, path, method, body, query, bearer = state.tokens!!.accessToken)
        } catch (error: ApiException) {
            if (error.status != 401 || error is SessionExpiredException) throw error
            val renewed = refresh(state.tokens!!.accessToken)
            try {
                api.request(renewed, path, method, body, query, bearer = renewed.tokens!!.accessToken)
            } catch (again: ApiException) {
                if (again.status == 401) { expire(); throw SessionExpiredException() }
                throw again
            }
        }
    }

    suspend fun loadSummary(): Summary = coroutineScope {
        val accounts = async { allAccounts() }
        val sheet = async {
            runCatching { api.json.decodeFromString<BalanceSheet>(authorized("/balance_sheet")) }
        }
        val cashFlow = async {
            optionalReport { api.json.decodeFromString<CashFlow>(authorized("/cash_flow", listOf("include" to "sankey"))) }
        }
        val history = async {
            val end = cashFlow.await()?.asOf?.let(LocalDate::parse) ?: LocalDate.now()
            optionalReport {
                api.json.decodeFromString<NetWorthHistory>(authorized(
                    "/actions/get_net_worth_series", method = "POST",
                    body = fields("arguments" to fields(
                        "start_date" to value(end.minusDays(29).toString()),
                        "end_date" to value(end.toString()),
                    )),
                ))
            }
        }
        val sheetResult = sheet.await()
        sheetResult.exceptionOrNull()?.let { if (it is SessionExpiredException || (it is ApiException && it.status != 422)) throw it }
        // 422: Relay refuses to total amounts it cannot convert to the family currency.
        val sheetError = sheetResult.exceptionOrNull()?.let { "Faltan tipos de cambio para calcular el patrimonio en tu moneda principal." }
        val summary = Summary(accounts.await(), sheetResult.getOrNull(), sheetError, clock(), cashFlow.await(), history.await())
        save { if (it.signedIn) it.copy(summary = summary) else it }
        summary
    }

    private suspend fun <T> optionalReport(load: suspend () -> T): T? = try {
        load()
    } catch (error: CancellationException) {
        throw error
    } catch (error: SessionExpiredException) {
        throw error
    } catch (_: java.io.IOException) {
        null
    } catch (_: kotlinx.serialization.SerializationException) {
        null
    }

    private suspend fun allAccounts(): List<Account> {
        val accounts = mutableListOf<Account>()
        var page = 1
        do {
            val result = api.json.decodeFromString<AccountsPage>(authorized(
                "/accounts", listOf("page" to "$page", "per_page" to "100", "include_disabled" to "true"),
            ))
            accounts += result.accounts.filterNot { it.status == "pending_deletion" }
            page++
        } while (page <= result.pagination.totalPages)
        return accounts
    }

    suspend fun transactions(page: Int, search: String = "", accountId: String? = null, perPage: Int = 40): TransactionsPage {
        val query = buildList {
            add("page" to "$page"); add("per_page" to "$perPage")
            if (search.isNotBlank()) add("search" to search.trim())
            accountId?.let { add("account_id" to it) }
        }
        return api.json.decodeFromString(authorized("/transactions", query))
    }

    suspend fun categories(): List<NamedRef> {
        val categories = mutableListOf<NamedRef>()
        var page = 1
        do {
            val result = api.json.decodeFromString<CategoriesPage>(
                authorized("/categories", listOf("page" to "$page", "per_page" to "100")),
            )
            categories += result.categories
            page++
        } while (page <= result.pagination.totalPages)
        return categories
    }

    suspend fun merchants(): List<NamedRef> = api.json.decodeFromString(authorized("/merchants"))

    suspend fun updateTransaction(id: String, changes: JsonObject): Transaction =
        api.json.decodeFromString(authorized("/transactions/$id", method = "PATCH", body = fields("transaction" to changes)))

    /** Revokes the device tokens on the server, then forgets them locally. */
    suspend fun logout() {
        val state = mutable.value?.takeIf { it.signedIn } ?: return forget()
        api.request(state, "/auth/logout", "POST", fields("refresh_token" to value(state.tokens!!.refreshToken)))
        forget()
    }

    /** Local sign-out: keeps only the server address and device identifier. */
    suspend fun forget() {
        save { DiskState(server = it.server, deviceId = it.deviceId) }
    }

    /** Session expired or revoked: the Service Token stays so signing in again is quick. */
    private suspend fun expire() {
        save { DiskState(server = it.server, deviceId = it.deviceId, cloudflareAccess = it.cloudflareAccess) }
    }
}
