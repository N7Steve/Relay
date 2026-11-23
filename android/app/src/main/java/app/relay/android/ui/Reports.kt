package app.relay.android.ui

import app.relay.android.data.ActivityReport
import app.relay.android.data.CashFlow
import app.relay.android.data.NetWorthHistory
import app.relay.android.data.RelayRepository
import app.relay.android.data.SessionExpiredException
import app.relay.android.data.reportingMonthStart
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Months are the family's reporting months: each key is the period's first day. */
data class ReportState(
    val startDay: Int = 0,
    val month: LocalDate? = null,
    val current: LocalDate? = null,
    val activity: Map<LocalDate, ActivityReport> = emptyMap(),
    val flows: Map<LocalDate, CashFlow> = emptyMap(),
    val worth: Map<LocalDate, NetWorthHistory> = emptyMap(),
    val loading: Boolean = false,
    val refreshing: Boolean = false,
    val error: String? = null,
) {
    val canGoNext get() = month != null && current != null && month < current
    val isCurrent get() = month != null && month == current

    /** The selected month and the five before it, oldest first. */
    val trendMonths get() = month?.let { selected -> (5 downTo 0).map { selected.minusMonths(it.toLong()) } }.orEmpty()

    companion object {
        fun end(start: LocalDate): LocalDate = start.plusMonths(1).minusDays(1)
    }
}

/**
 * The monthly report: headline figures, a six-month trend, net worth and categories.
 * Results are kept per month, so stepping back one month only loads that month.
 */
class Reports(
    private val scope: CoroutineScope,
    private val repository: RelayRepository,
    private val describe: (Throwable) -> String,
    private val today: () -> LocalDate = LocalDate::now,
) {
    private val mutable = MutableStateFlow(ReportState())
    val state: StateFlow<ReportState> = mutable.asStateFlow()
    private var job: Job? = null

    /** Opens on the current month, again whenever the family's start day changes. */
    fun open(startDay: Int) {
        val state = mutable.value
        if (state.startDay == startDay && state.month != null) return
        job?.cancel()
        val current = reportingMonthStart(today(), startDay)
        mutable.value = ReportState(startDay = startDay, month = current, current = current)
        load(current, refreshing = false)
    }

    fun previous() { mutable.value.month?.let { select(it.minusMonths(1)) } }

    fun next() {
        val state = mutable.value
        if (state.canGoNext) select(state.month!!.plusMonths(1))
    }

    fun goToCurrent() { mutable.value.current?.let(::select) }

    fun select(month: LocalDate) {
        val state = mutable.value
        if (state.startDay == 0 || month == state.month || (state.current != null && month > state.current)) return
        job?.cancel()
        mutable.update { it.copy(month = month, loading = false, refreshing = false, error = null) }
        load(month, refreshing = false)
    }

    fun refresh() {
        val month = mutable.value.month ?: return
        job?.cancel()
        val current = reportingMonthStart(today(), mutable.value.startDay)
        mutable.update { it.copy(current = current, activity = emptyMap(), flows = emptyMap(), worth = emptyMap(), error = null) }
        load(month, refreshing = true)
    }

    fun retry() { mutable.value.month?.let { month -> mutable.update { it.copy(error = null) }; load(month, refreshing = false) } }

    /** A movement changed: drop cached figures and reload the visible month if the report was opened. */
    fun invalidate() { if (mutable.value.month != null) refresh() }

    fun clear() { job?.cancel(); mutable.value = ReportState() }

    private fun load(month: LocalDate, refreshing: Boolean) {
        val cached = mutable.value
        val months = cached.copy(month = month).trendMonths
        val end = ReportState.end(month)
        if (months.all { it in cached.activity } && month in cached.flows && month in cached.worth) {
            mutable.update { it.copy(loading = false, refreshing = false) }
            return
        }
        mutable.update { it.copy(loading = true, refreshing = refreshing) }
        job = scope.launch {
            try {
                coroutineScope {
                    val activity = months.filter { it !in cached.activity }.map { start ->
                        start to async { attempt { repository.activityReport(start, ReportState.end(start)) } }
                    }
                    val flow = if (month in cached.flows) null else async { attempt { repository.cashFlow(month, end) } }
                    val worth = if (month in cached.worth) null else async {
                        attempt { repository.netWorthBetween(month, minOf(end, today())) }
                    }
                    val loaded = activity.map { (start, result) -> start to result.await() }
                    val flowResult = flow?.await()
                    val worthResult = worth?.await()
                    val failure = loaded.firstOrNull { it.first == month }?.second?.exceptionOrNull()
                    mutable.update { state ->
                        state.copy(
                            activity = state.activity + loaded.mapNotNull { (start, result) -> result.getOrNull()?.let { start to it } },
                            flows = flowResult?.getOrNull()?.let { state.flows + (month to it) } ?: state.flows,
                            worth = worthResult?.getOrNull()?.let { state.worth + (month to it) } ?: state.worth,
                            loading = if (state.month == month) false else state.loading,
                            refreshing = if (state.month == month) false else state.refreshing,
                            error = if (state.month == month) failure?.let(describe) else state.error,
                        )
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                mutable.update { it.copy(loading = false, refreshing = false, error = describe(error)) }
            }
        }
    }

    /** One part failing must not hide the others; an expired session still ends the load. */
    private suspend fun <T> attempt(block: suspend () -> T): Result<T> = try {
        Result.success(block())
    } catch (error: CancellationException) {
        throw error
    } catch (error: SessionExpiredException) {
        throw error
    } catch (error: Exception) {
        Result.failure(error)
    }
}
