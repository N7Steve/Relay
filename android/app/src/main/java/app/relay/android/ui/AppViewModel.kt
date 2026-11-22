package app.relay.android.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.relay.android.RelayApplication
import app.relay.android.data.ApiException
import app.relay.android.data.DiskState
import app.relay.android.data.SessionExpiredException
import app.relay.android.data.Transaction
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class LoginState(val busy: Boolean = false, val mfaRequired: Boolean = false, val error: String? = null)

data class SummaryState(val loading: Boolean = false, val error: String? = null)

data class FeedState(
    val accountId: String? = null,
    val query: String = "",
    val items: List<Transaction> = emptyList(),
    val page: Int = 0,
    val totalPages: Int = 1,
    val totalCount: Int = 0,
    val loading: Boolean = false,
    val refreshing: Boolean = false,
    val error: String? = null,
) {
    val canLoadMore get() = page < totalPages && !loading && error == null
}

/** Paged transaction list with search; one instance per screen that lists movements. */
class Feed(private val scope: kotlinx.coroutines.CoroutineScope, private val load: suspend (Int, String, String?) -> app.relay.android.data.TransactionsPage,
           private val onError: (Throwable) -> String) {
    private val mutable = MutableStateFlow(FeedState())
    val state: StateFlow<FeedState> = mutable.asStateFlow()
    private var job: Job? = null

    fun open(accountId: String?) {
        if (mutable.value.accountId == accountId && mutable.value.page > 0) return
        job?.cancel()
        mutable.value = FeedState(accountId = accountId)
        loadPage(1, replace = true)
    }

    fun search(query: String) {
        if (query == mutable.value.query) return
        job?.cancel()
        mutable.update { it.copy(query = query, error = null) }
        job = scope.launch {
            delay(350)
            fetch(1, replace = true, refreshing = false)
        }
    }

    fun refresh() {
        job?.cancel()
        mutable.update { it.copy(refreshing = true, error = null) }
        job = scope.launch { fetch(1, replace = true, refreshing = true) }
    }

    fun loadMore() {
        val state = mutable.value
        if (!state.canLoadMore || job?.isActive == true) return
        loadPage(state.page + 1, replace = false)
    }

    fun retry() {
        mutable.update { it.copy(error = null) }
        loadPage(if (mutable.value.items.isEmpty()) 1 else mutable.value.page + 1, replace = mutable.value.items.isEmpty())
    }

    fun clear() { job?.cancel(); mutable.value = FeedState() }

    private fun loadPage(page: Int, replace: Boolean) {
        job = scope.launch { fetch(page, replace, refreshing = false) }
    }

    private suspend fun fetch(page: Int, replace: Boolean, refreshing: Boolean) {
        val request = mutable.value
        mutable.update { it.copy(loading = true, refreshing = refreshing) }
        try {
            val result = load(page, request.query, request.accountId)
            mutable.update {
                if (it.query != request.query || it.accountId != request.accountId) return@update it
                it.copy(
                    items = if (replace) result.transactions else (it.items + result.transactions).distinctBy { t -> t.id },
                    page = page, totalPages = result.pagination.totalPages, totalCount = result.pagination.totalCount,
                    loading = false, refreshing = false, error = null,
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            mutable.update { it.copy(loading = false, refreshing = false, error = onError(error)) }
        }
    }
}

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as RelayApplication
    private val repository = app.repository
    val updates = app.updates
    val session: StateFlow<DiskState?> = repository.state

    private val loginState = MutableStateFlow(LoginState())
    val login = loginState.asStateFlow()
    private val summaryState = MutableStateFlow(SummaryState())
    val summary = summaryState.asStateFlow()
    private val noticeState = MutableStateFlow<String?>(null)
    val notice = noticeState.asStateFlow()
    private val signingOut = MutableStateFlow(false)
    val busySigningOut = signingOut.asStateFlow()

    val movements = Feed(viewModelScope, { page, query, account -> repository.transactions(page, query, account) }, ::describe)
    val accountMovements = Feed(viewModelScope, { page, query, account -> repository.transactions(page, query, account) }, ::describe)
    val recent = Feed(viewModelScope, { page, _, _ -> repository.transactions(page, perPage = 6) }, ::describe)

    init {
        viewModelScope.launch {
            app.ready.await()
            repository.state.collect { state ->
                val user = state?.user
                updates.account(if (state?.signedIn == true && user != null) state.server + ":" + user.id else "")
            }
        }
    }

    /** Called from onResume: refresh data and look for an update without blocking the UI. */
    fun onForeground() {
        viewModelScope.launch {
            app.ready.await()
            if (repository.state.value?.signedIn == true) {
                refreshSummary()
                updates.check()
            }
        }
    }

    fun signIn(server: String, email: String, password: String, otp: String, clientId: String, clientSecret: String) {
        if (loginState.value.busy) return
        loginState.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            try {
                repository.login(server, email, password, otp, clientId, clientSecret)
                loginState.value = LoginState()
                movements.clear(); accountMovements.clear(); recent.clear()
                refreshSummary()
                updates.check()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                val mfa = error is ApiException && error.mfaRequired
                loginState.update {
                    it.copy(busy = false, mfaRequired = mfa || it.mfaRequired,
                        error = if (mfa && otp.isNotBlank()) "El código de verificación no es correcto o ha caducado." else describe(error))
                }
            }
        }
    }

    fun refreshSummary() {
        if (summaryState.value.loading) return
        summaryState.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            try {
                repository.loadSummary()
                summaryState.value = SummaryState()
                recent.refresh()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                summaryState.value = SummaryState(error = describe(error))
            }
        }
    }

    fun signOut() {
        if (signingOut.value) return
        signingOut.value = true
        viewModelScope.launch {
            try {
                repository.logout()
                resetScreens()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                noticeState.value = "No se pudo cerrar la sesión en el servidor: ${describe(error)} Puedes reintentarlo u olvidarla solo en este móvil."
            } finally {
                signingOut.value = false
            }
        }
    }

    fun forget() {
        viewModelScope.launch { repository.forget(); resetScreens() }
    }

    fun dismissNotice() { noticeState.value = null }
    fun checkUpdates() = updates.check(manual = true)

    private fun resetScreens() {
        loginState.value = LoginState()
        summaryState.value = SummaryState()
        movements.clear(); accountMovements.clear(); recent.clear()
    }

    private fun describe(error: Throwable): String = when (error) {
        is SessionExpiredException -> error.message!!
        is ApiException -> error.message ?: "Error del servidor."
        // SerializationException is an IllegalArgumentException: keep it first.
        is kotlinx.serialization.SerializationException -> "El servidor respondió con datos inesperados. ¿Es una instalación de Relay?"
        is IllegalArgumentException, is IllegalStateException -> error.message ?: "Datos no válidos."
        is javax.net.ssl.SSLException -> "No se pudo establecer una conexión segura con el servidor. Revisa su certificado HTTPS."
        is java.net.UnknownHostException -> "No se encuentra el servidor. Revisa la dirección y tu conexión."
        is java.io.IOException -> "No se pudo conectar con el servidor. Revisa tu conexión."
        else -> error.message ?: "Error inesperado."
    }
}
