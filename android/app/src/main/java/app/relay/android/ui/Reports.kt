package app.relay.android.ui

import app.relay.android.data.ActivityReport
import app.relay.android.data.CashFlow
import app.relay.android.data.SpendingTrend
import app.relay.android.data.RelayRepository
import app.relay.android.data.SessionExpiredException
import app.relay.android.data.reportingMonthStart
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** Months are the family's reporting months: each key is the period's first day. */
data class ReportState(
    val startDay: Int = 0,
    val month: LocalDate? = null,
    val current: LocalDate? = null,
    val activity: Map<LocalDate, ActivityReport> = emptyMap(),
    val flows: Map<LocalDate, CashFlow> = emptyMap(),
    val spending: Map<LocalDate, SpendingTrend> = emptyMap(),
    /** Oldest month drawn in the trend; the trend always runs up to [current]. */
    val trendFrom: LocalDate? = null,
    val loading: Boolean = false,
    val refreshing: Boolean = false,
    val error: String? = null,
) {
    val canGoNext get() = month != null && current != null && month < current
    val isCurrent get() = month != null && month == current

    /** Months of the scrollable trend, oldest first. */
    val trendMonths: List<LocalDate> get() {
        val from = trendFrom ?: return emptyList()
        val to = current ?: return emptyList()
        return generateSequence(from) { it.plusMonths(1) }.takeWhile { it <= to }.toList()
    }

    /** More months can be added to the left of the trend. */
    val canExtendTrend get() = trendFrom != null && current != null && trendFrom > current.minusMonths(TREND_LIMIT - 1L)

    companion object {
        /** Months shown when the report opens, how many each scroll to the left adds, and the furthest back. */
        const val TREND_SPAN = 12
        const val TREND_STEP = 6
        const val TREND_LIMIT = 120

        fun end(start: LocalDate): LocalDate = start.plusMonths(1).minusDays(1)
    }
}

/**
 * The monthly report: headline figures, a scrollable monthly trend, spending against the previous month and
 * categories. Results are kept per month, so stepping back one month only loads that month. The selected month
 * loads first; the rest of the trend fills in afterwards.
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
    private var trend = SupervisorJob(scope.coroutineContext[Job])
    private val requested = mutableSetOf<LocalDate>()

    /** Opens on the current month, again whenever the family's start day changes. */
    fun open(startDay: Int) {
        val state = mutable.value
        if (state.startDay == startDay && state.month != null) return
        job?.cancel()
        resetTrend()
        val current = reportingMonthStart(today(), startDay)
        mutable.value = ReportState(startDay = startDay, month = current, current = current,
            trendFrom = current.minusMonths(ReportState.TREND_SPAN - 1L))
        load(current, refreshing = false)
    }

    /** The trend was scrolled to its oldest month: add earlier ones. */
    fun extendTrend() {
        val state = mutable.value
        if (!state.canExtendTrend) return
        val limit = state.current!!.minusMonths(ReportState.TREND_LIMIT - 1L)
        mutable.update { it.copy(trendFrom = maxOf(limit, state.trendFrom!!.minusMonths(ReportState.TREND_STEP.toLong()))) }
        loadTrend()
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
        mutable.update {
            it.copy(month = month, trendFrom = it.trendFrom?.let { from -> minOf(from, month) } ?: month,
                loading = false, refreshing = false, error = null)
        }
        load(month, refreshing = false)
    }

    fun refresh() {
        val month = mutable.value.month ?: return
        job?.cancel()
        resetTrend()
        val current = reportingMonthStart(today(), mutable.value.startDay)
        mutable.update { it.copy(current = current, activity = emptyMap(), flows = emptyMap(), spending = emptyMap(), error = null) }
        load(month, refreshing = true)
    }

    fun retry() { mutable.value.month?.let { month -> mutable.update { it.copy(error = null) }; load(month, refreshing = false) } }

    /** A movement changed: drop cached figures and reload the visible month if the report was opened. */
    fun invalidate() { if (mutable.value.month != null) refresh() }

    fun clear() { job?.cancel(); resetTrend(); mutable.value = ReportState() }

    private fun load(month: LocalDate, refreshing: Boolean) {
        val cached = mutable.value
        val end = ReportState.end(month)
        if (month in cached.activity && month in cached.flows && month in cached.spending) {
            mutable.update { it.copy(loading = false, refreshing = false) }
            loadTrend()
            return
        }
        mutable.update { it.copy(loading = true, refreshing = refreshing) }
        job = scope.launch {
            try {
                coroutineScope {
                    val activity = listOf(month).filter { it !in cached.activity }.map { start ->
                        start to async { attempt { repository.activityReport(start, ReportState.end(start)) } }
                    }
                    val flow = if (month in cached.flows) null else async { attempt { repository.cashFlow(month, end) } }
                    // The current month's curve stops today; the previous month is drawn in full.
                    val spending = if (month in cached.spending) null else async {
                        attempt { repository.spendingTrend(month, minOf(end, today())) }
                    }
                    val loaded = activity.map { (start, result) -> start to result.await() }
                    val flowResult = flow?.await()
                    val spendingResult = spending?.await()
                    val failure = loaded.firstOrNull { it.first == month }?.second?.exceptionOrNull()
                    mutable.update { state ->
                        state.copy(
                            activity = state.activity + loaded.mapNotNull { (start, result) -> result.getOrNull()?.let { start to it } },
                            flows = flowResult?.getOrNull()?.let { state.flows + (month to it) } ?: state.flows,
                            spending = spendingResult?.getOrNull()?.let { state.spending + (month to it) } ?: state.spending,
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
            loadTrend()
        }
    }

    private fun resetTrend() {
        trend.cancel()
        trend = SupervisorJob(scope.coroutineContext[Job])
        requested.clear()
    }

    /** Loads the trend's missing months, newest first and a few at a time; a month that fails stays empty. */
    private fun loadTrend() {
        val state = mutable.value
        val missing = state.trendMonths.asReversed().filter { it != state.month && it !in state.activity && it !in requested }
        if (missing.isEmpty()) return
        requested += missing
        scope.launch(trend) {
            try {
                coroutineScope {
                    val gate = Semaphore(TREND_PARALLEL)
                    missing.forEach { start ->
                        launch {
                            gate.withPermit { attempt { repository.activityReport(start, ReportState.end(start)) } }
                                .onSuccess { report -> mutable.update { it.copy(activity = it.activity + (start to report)) } }
                                .onFailure { requested -= start }
                        }
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // An expired session ends the selected month's load; the trend just stays incomplete.
            }
        }
    }

    private companion object {
        const val TREND_PARALLEL = 3
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
