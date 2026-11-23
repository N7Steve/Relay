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
    private val today: () -> LocalDate = LocalDate::now,
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

    suspend fun login(
        server: String,
        email: String,
        password: String,
        otp: String,
        clientId: String,
        clientSecret: String,
        rememberCredentials: Boolean = false,
    ) {
        val origin = serverUrl(server).toString()
        val current = mutable.value ?: DiskState()
        val access = CloudflareAccess.fromInput(clientId, clientSecret)
        val deviceId = current.deviceId.ifEmpty { UUID.randomUUID().toString() }
        val cleanEmail = email.trim()
        val draft = DiskState(server = origin, deviceId = deviceId, cloudflareAccess = access)
        val body = fields(
            "email" to value(cleanEmail),
            "password" to value(password),
            "device" to deviceFields(deviceId),
        ).let { if (otp.isNotBlank()) JsonObject(it + ("otp_code" to value(otp.filter(Char::isDigit)))) else it }
        val response = api.json.decodeFromString<TokenResponse>(api.request(draft, "/auth/login", "POST", body))
        val user = requireNotNull(response.user) { "El servidor no devolvió el usuario." }
        val saved = if (rememberCredentials) SavedCredentials(origin, cleanEmail, password, access) else null
        save { draft.copy(tokens = response.tokens(clock()), user = user, savedCredentials = saved) }
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
    ): String = withAuth { state, token -> api.request(state, path, method, body, query, bearer = token) }

    /** Stored image behind the API; null when the server has none (or predates the endpoint). */
    suspend fun download(path: String, maxBytes: Long): ByteArray? = withAuth { state, token -> api.download(state, path, token, maxBytes) }

    private suspend fun <T> withAuth(call: suspend (DiskState, String) -> T): T {
        val state = fresh()
        return try {
            call(state, state.tokens!!.accessToken)
        } catch (error: ApiException) {
            if (error.status != 401 || error is SessionExpiredException) throw error
            val renewed = refresh(state.tokens!!.accessToken)
            try {
                call(renewed, renewed.tokens!!.accessToken)
            } catch (again: ApiException) {
                if (again.status == 401) { expire(); throw SessionExpiredException() }
                throw again
            }
        }
    }

    suspend fun loadSummary(): Summary = coroutineScope {
        val range = mutable.value?.preferences?.netWorthRange ?: NetWorthRange.Month
        val end = today()
        val accounts = async { allAccounts() }
        val sheet = async {
            runCatching { api.json.decodeFromString<BalanceSheet>(authorized("/balance_sheet")) }
        }
        val startDay = async {
            optionalReport { api.json.decodeFromString<FamilySettings>(authorized("/family_settings")).monthStartDay }
                ?: mutable.value?.summary?.monthStartDay ?: 1
        }
        val cashFlow = async { optionalReport { this@RelayRepository.cashFlow(reportingMonthStart(end, startDay.await()), end) } }
        val history = async { optionalReport { netWorthSeries(range, end) } }
        val sheetResult = sheet.await()
        sheetResult.exceptionOrNull()?.let { if (it is SessionExpiredException || (it is ApiException && it.status != 422)) throw it }
        // 422: Relay refuses to total amounts it cannot convert to the family currency.
        val sheetError = sheetResult.exceptionOrNull()?.let { "Faltan tipos de cambio para calcular el patrimonio en tu moneda principal." }
        val summary = Summary(accounts.await(), sheetResult.getOrNull(), sheetError, clock(), cashFlow.await(), history.await(),
            range, startDay.await())
        save { if (it.signedIn) it.copy(summary = summary) else it }
        summary
    }

    /** Remembers the range and replaces only the cached net worth series. */
    suspend fun loadNetWorth(range: NetWorthRange): NetWorthHistory {
        save { it.copy(preferences = it.preferences.copy(netWorthRange = range)) }
        val history = netWorthSeries(range, today())
        save { state -> state.copy(summary = state.summary?.copy(netWorthHistory = history, netWorthRange = range)) }
        return history
    }

    private suspend fun netWorthSeries(range: NetWorthRange, end: LocalDate): NetWorthHistory =
        netWorthBetween(end.minusDays(range.days - 1), end)

    suspend fun netWorthBetween(start: LocalDate, end: LocalDate): NetWorthHistory =
        api.json.decodeFromString(authorized("/actions/get_net_worth_series", method = "POST", body = period(start, end)))

    /** Category flows (sankey) for any period, e.g. a past month of the report. */
    suspend fun cashFlow(start: LocalDate, end: LocalDate): CashFlow =
        api.json.decodeFromString<CashFlowGraph>(authorized("/cash_flow", listOf(
            "view" to "sankey", "start_date" to start.toString(), "end_date" to end.toString(),
        ))).cashFlow()

    suspend fun activityReport(start: LocalDate, end: LocalDate): ActivityReport =
        api.json.decodeFromString(authorized("/actions/get_activity_report", method = "POST", body = period(start, end)))

    suspend fun spendingTrend(start: LocalDate, end: LocalDate): SpendingTrend =
        api.json.decodeFromString(authorized("/actions/get_spending_trend", method = "POST", body = period(start, end)))

    private fun period(start: LocalDate, end: LocalDate) = fields("arguments" to fields(
        "start_date" to value(start.toString()),
        "end_date" to value(end.toString()),
    ))

    /** Movements of some categories in a period, newest first (at most 100 per category). */
    suspend fun categoryTransactions(categoryIds: List<String>, start: LocalDate, end: LocalDate): List<Transaction> = coroutineScope {
        categoryIds.distinct().map { id ->
            async {
                api.json.decodeFromString<TransactionsPage>(authorized("/transactions", listOf(
                    "page" to "1", "per_page" to "100", "category_id" to id,
                    "start_date" to start.toString(), "end_date" to end.toString(),
                ))).transactions
            }
        }.flatMap { it.await() }.distinctBy { it.id }.sortedWith(compareByDescending<Transaction> { it.date }.thenBy { it.name })
    }

    suspend fun setDefaultAccount(accountId: String?) {
        save { it.copy(preferences = it.preferences.copy(defaultAccountId = accountId)) }
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

    suspend fun categories(): List<CategoryOption> {
        val categories = mutableListOf<CategoryOption>()
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

    /** The signed-in user's personal tags, alphabetically. */
    suspend fun tags(): List<TagRef> = api.json.decodeFromString(authorized("/tags"))

    /** [draft] carries an external_id so a retried submission never records the movement twice. */
    suspend fun createTransaction(draft: JsonObject): Transaction =
        api.json.decodeFromString(authorized("/transactions", method = "POST", body = fields("transaction" to draft)))

    suspend fun updateTransaction(id: String, changes: JsonObject): Transaction =
        api.json.decodeFromString(authorized("/transactions/$id", method = "PATCH", body = fields("transaction" to changes)))

    /** Revokes the device tokens on the server, keeping remembered login credentials if enabled. */
    suspend fun logout() {
        val state = mutable.value?.takeIf { it.signedIn } ?: return forget()
        api.request(state, "/auth/logout", "POST", fields("refresh_token" to value(state.tokens!!.refreshToken)))
        save { DiskState(server = it.server, deviceId = it.deviceId, savedCredentials = it.savedCredentials) }
    }

    /** Local sign-out: clears session, cache and saved credentials; keeps only server and device id. */
    suspend fun forget() {
        save { DiskState(server = it.server, deviceId = it.deviceId) }
    }

    /** Session expired or revoked: keep Service Token and remembered credentials so signing in again is quick. */
    private suspend fun expire() {
        save {
            DiskState(
                server = it.server,
                deviceId = it.deviceId,
                cloudflareAccess = it.cloudflareAccess,
                savedCredentials = it.savedCredentials,
            )
        }
    }
}
