package app.relay.android.ui

import app.relay.android.data.LoanDetail
import app.relay.android.data.LoanListItem
import app.relay.android.data.RelayRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class LoansState(
    /** null until the list has loaded once. */
    val list: List<LoanListItem>? = null,
    val details: Map<String, LoanDetail> = emptyMap(),
    val loading: Boolean = false,
    val refreshing: Boolean = false,
    val error: String? = null,
    val loadingDetails: Set<String> = emptySet(),
    val detailErrors: Map<String, String> = emptyMap(),
    val fetchedAt: Long = 0,
)

/**
 * The loans section: the list of loans and each loan's detail, fetched when the section opens and kept in memory
 * while the app runs. Figures move at most once a day (an instalment, a revision), so an open section older than
 * [STALE_AFTER] reloads quietly; pulling down always does.
 */
class Loans(
    private val scope: CoroutineScope,
    private val repository: RelayRepository,
    private val describe: (Throwable) -> String,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val mutable = MutableStateFlow(LoansState())
    val state: StateFlow<LoansState> = mutable.asStateFlow()
    private var listJob: Job? = null
    private val detailJobs = mutableMapOf<String, Job>()

    fun open() {
        val state = mutable.value
        if (listJob?.isActive == true) return
        if (state.list != null && clock() - state.fetchedAt < STALE_AFTER) return
        if (state.list != null) mutable.update { it.copy(details = emptyMap()) }
        loadList(refreshing = state.list != null)
    }

    fun openDetail(accountId: String) {
        val state = mutable.value
        if (accountId in state.details || detailJobs[accountId]?.isActive == true) return
        loadDetail(accountId)
    }

    /** Pull to refresh: the list, and the loan on screen if there is one. */
    fun refresh(accountId: String? = null) {
        // The loan on screen keeps its figures until the new ones arrive; the others reload when opened.
        mutable.update { state -> state.copy(details = state.details.filterKeys { it == accountId }) }
        loadList(refreshing = true)
        accountId?.let(::loadDetail)
    }

    fun retry() { mutable.update { it.copy(error = null) }; loadList(refreshing = false) }

    fun retryDetail(accountId: String) = loadDetail(accountId)

    fun clear() {
        listJob?.cancel()
        detailJobs.values.forEach(Job::cancel)
        detailJobs.clear()
        mutable.value = LoansState()
    }

    private fun loadList(refreshing: Boolean) {
        listJob?.cancel()
        mutable.update { it.copy(loading = true, refreshing = refreshing, error = null) }
        listJob = scope.launch {
            try {
                val loans = repository.loans().loans
                mutable.update { state ->
                    val ids = loans.map { it.account.id }.toSet()
                    state.copy(list = loans, details = state.details.filterKeys { it in ids }, loading = false, refreshing = false,
                        error = null, fetchedAt = clock())
                }
                // With a single loan the section opens straight on its detail.
                loans.singleOrNull()?.let { openDetail(it.account.id) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                mutable.update { it.copy(loading = false, refreshing = false, error = describe(error)) }
            }
        }
    }

    private fun loadDetail(accountId: String) {
        detailJobs[accountId]?.cancel()
        mutable.update { it.copy(loadingDetails = it.loadingDetails + accountId, detailErrors = it.detailErrors - accountId) }
        detailJobs[accountId] = scope.launch {
            try {
                val detail = repository.loan(accountId)
                mutable.update {
                    it.copy(details = it.details + (accountId to detail), loadingDetails = it.loadingDetails - accountId)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                mutable.update {
                    it.copy(loadingDetails = it.loadingDetails - accountId, detailErrors = it.detailErrors + (accountId to describe(error)))
                }
            }
        }
    }

    private companion object {
        const val STALE_AFTER = 10 * 60 * 1000L
    }
}
