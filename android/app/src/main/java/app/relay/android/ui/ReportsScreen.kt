package app.relay.android.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material.icons.outlined.Today
import androidx.compose.material.icons.outlined.TrendingDown
import androidx.compose.material.icons.outlined.TrendingUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.data.ActivityReport
import app.relay.android.data.CashFlow
import app.relay.android.data.CashFlowNode
import app.relay.android.data.DiskState
import app.relay.android.data.FlowCategory
import app.relay.android.data.SpendingTrend
import app.relay.android.data.Transaction
import app.relay.android.data.formatMoney
import app.relay.android.data.reportingMonthName
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.distinctUntilChanged

private val spanish = Locale.forLanguageTag("es-ES")
private val monthTitle = DateTimeFormatter.ofPattern("MMMM yyyy", spanish)
private val monthShort = DateTimeFormatter.ofPattern("MMM", spanish)
private val dayMonth = DateTimeFormatter.ofPattern("d MMM", spanish)
private val dayMonthYear = DateTimeFormatter.ofPattern("d MMM yyyy", spanish)

private fun monthName(start: LocalDate, startDay: Int) =
    reportingMonthName(start, startDay).format(monthTitle).replaceFirstChar { it.uppercase() }

private fun rangeLabel(start: LocalDate) = "${start.format(dayMonth)} – ${ReportState.end(start).format(dayMonthYear)}"

private fun percent(value: BigDecimal) = String.format(spanish, "%.1f %%", value.abs())

/** Categories to list when a report row is opened; a parent includes its subcategories. */
private data class CategorySelection(val name: String, val color: Color, val icon: String?, val total: BigDecimal,
    val categoryIds: List<String>, val start: LocalDate, val categoryId: String?)

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun ReportsScreen(vm: AppViewModel, session: DiskState, onTransaction: (Transaction) -> Unit) {
    val reports = vm.reports
    val state by reports.state.collectAsStateWithLifecycle()
    val startDay = session.summary?.monthStartDay ?: 1
    LaunchedEffect(startDay) { reports.open(startDay) }
    // Category icons are not part of the cash flow graph; they come from the family's categories.
    val icons by produceState(emptyMap<String, String?>()) {
        value = try {
            vm.categories().associate { it.id to it.icon }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            emptyMap()
        }
    }
    var opened by remember { mutableStateOf<CategorySelection?>(null) }
    val currency = session.summary?.balanceSheet?.currency ?: state.activity.values.firstOrNull()?.currency ?: "EUR"

    PullToRefreshBox(isRefreshing = state.refreshing, onRefresh = reports::refresh, modifier = Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxSize().swipeMonths(reports::previous, reports::next).verticalScroll(rememberScrollState())
                .statusBarsPadding().padding(horizontal = 20.dp).padding(top = 20.dp, bottom = 24.dp),
        ) {
            Row(Modifier.fillMaxWidth().enter(0), verticalAlignment = Alignment.CenterVertically) {
                Text("Informe", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f))
                // Lives in the title row so appearing never pushes the report down.
                AnimatedVisibility(state.month != null && !state.isCurrent, enter = fadeIn(tween(Relay.BASE)) + scaleIn(tween(Relay.BASE), 0.85f),
                    exit = fadeOut(tween(Relay.FAST)) + scaleOut(tween(Relay.FAST), 0.85f)) {
                    TodayChip(reports::goToCurrent)
                }
            }
            Spacer(Modifier.height(14.dp))
            MonthSwitcher(state, startDay, reports::previous, reports::next)
            state.month?.let { month ->
                ReportBody(state, month, startDay, icons, currency, reports::select, reports::extendTrend, reports::retry) { opened = it }
            }
        }
    }

    opened?.let { selection ->
        CategoryMovementsSheet(selection, startDay, currency, vm, onDismiss = { opened = null }) { transaction ->
            opened = null
            onTransaction(transaction)
        }
    }
}

/** A deliberate horizontal swipe moves one month; vertical scrolling is unaffected. */
@Composable private fun Modifier.swipeMonths(onPrevious: () -> Unit, onNext: () -> Unit): Modifier {
    val previous by rememberUpdatedState(onPrevious)
    val next by rememberUpdatedState(onNext)
    return pointerInput(Unit) {
        var total = 0f
        val threshold = 96.dp.toPx()
        detectHorizontalDragGestures(
            onDragStart = { total = 0f },
            onDragEnd = {
                if (total > threshold) previous() else if (total < -threshold) next()
                total = 0f
            },
            onDragCancel = { total = 0f },
        ) { _, amount -> total += amount }
    }
}

@Composable private fun TodayChip(onClick: () -> Unit) {
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(Relay.blue.copy(alpha = 0.14f)).clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.Today, null, tint = Relay.blue, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        Text("Mes actual", style = MaterialTheme.typography.labelLarge, color = Relay.blue)
    }
}

/** Only the month name slides, in the direction of travel; the arrows and the page stay put. */
@Composable private fun MonthSwitcher(state: ReportState, startDay: Int, onPrevious: () -> Unit, onNext: () -> Unit) {
    val month = state.month
    Panel(Modifier.fillMaxWidth().enter(1), padding = 6.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onPrevious, enabled = month != null) {
                Icon(Icons.Outlined.ChevronLeft, "Mes anterior", tint = Relay.text)
            }
            AnimatedContent(
                targetState = month,
                modifier = Modifier.weight(1f).clipToBounds(),
                transitionSpec = {
                    val forward = compareValues(targetState, initialState) > 0
                    val motion = tween<IntOffset>(300, easing = Relay.easeOut)
                    (slideInHorizontally(motion) { if (forward) it else -it } togetherWith
                        slideOutHorizontally(motion) { if (forward) -it else it }) using SizeTransform(clip = true)
                },
                label = "report-month",
            ) { shown ->
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(shown?.let { monthName(it, startDay) } ?: "…", style = MaterialTheme.typography.titleMedium, color = Relay.text)
                    Text(shown?.let(::rangeLabel) ?: " ", style = MaterialTheme.typography.labelMedium.merge(tabular), color = Relay.muted)
                }
            }
            IconButton(onClick = onNext, enabled = state.canGoNext) {
                Icon(Icons.Outlined.ChevronRight, "Mes siguiente", tint = if (state.canGoNext) Relay.text else Relay.border)
            }
        }
    }
}

/** Holds the last value shown so a month that is still loading keeps the page in place. */
private class LastShown<T> { var value: T? = null }

@Composable private fun <T> shownWhileLoading(value: T?, pending: Boolean): T? {
    val last = remember { LastShown<T>() }
    if (value != null) last.value = value
    return value ?: last.value.takeIf { pending }
}

/** Figures from the previous month stay visible but dimmed until the new month arrives. */
@Composable private fun Modifier.stale(stale: Boolean): Modifier {
    val alpha by animateFloatAsState(if (stale) 0.4f else 1f, tween(Relay.BASE), label = "stale")
    return graphicsLayer { this.alpha = alpha }
}

@Composable private fun ReportBody(
    state: ReportState,
    month: LocalDate,
    startDay: Int,
    icons: Map<String, String?>,
    currency: String,
    onSelect: (LocalDate) -> Unit,
    onOlder: () -> Unit,
    onRetry: () -> Unit,
    onCategory: (CategorySelection) -> Unit,
) {
    val pending = state.loading && state.month == month
    val activity = shownWhileLoading(state.activity[month], pending)
    val spending = shownWhileLoading(state.spending[month], pending)
    val flow = shownWhileLoading(state.flows[month], pending)
    Column(Modifier.fillMaxWidth().padding(top = 12.dp).animateContentSize(tween(Relay.BASE, easing = Relay.easeOut)),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        when {
            state.error != null && state.month == month && state.activity[month] == null -> ErrorBanner(state.error, onRetry = onRetry)
            activity != null -> Box(Modifier.stale(state.activity[month] == null)) { SavingsHero(activity) }
            else -> HeroSkeleton()
        }
        TrendCard(state, month, startDay, currency, onSelect, onOlder)
        Box(Modifier.stale(spending != null && state.spending[month] == null)) { SpendingCard(spending, pending, month, startDay) }
        Box(Modifier.stale(flow != null && state.flows[month] == null)) { CategoriesCard(flow, pending, month, icons, onCategory) }
        Box(Modifier.stale(flow != null && state.flows[month] == null)) { TransfersCard(flow, activity) }
    }
}

@Composable private fun HeroSkeleton() {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Relay.gradient).padding(22.dp)) {
        Column {
            Text("AHORRO NETO", style = eyebrow, color = Color.White.copy(alpha = 0.75f))
            Spacer(Modifier.height(12.dp))
            Box(Modifier.width(180.dp).height(34.dp).clip(RoundedCornerShape(10.dp)).background(Color.White.copy(alpha = 0.2f)))
            Spacer(Modifier.height(64.dp))
        }
    }
}

/** Net savings over income and spending, each compared with the previous month as on the web. */
@Composable private fun SavingsHero(report: ActivityReport) {
    val income = report.current.income.decimal
    val expenses = report.current.expenses.decimal
    val net = report.netSavings.decimal
    val rate = if (income.signum() > 0) net.multiply(BigDecimal(100)).divide(income, 1, RoundingMode.HALF_UP) else null
    val investment = report.current.investmentReturn?.decimal?.takeIf { it.signum() != 0 }
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Relay.gradient).drawBehind {
            drawCircle(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.18f), Color.Transparent),
                center = Offset(size.width * 0.95f, 0f), radius = size.width * 0.7f))
            drawCircle(Brush.radialGradient(listOf(Relay.cyan.copy(alpha = 0.25f), Color.Transparent),
                center = Offset(0f, size.height), radius = size.width * 0.6f))
        }.padding(22.dp),
    ) {
        Column {
            Text("AHORRO NETO", style = eyebrow, color = Color.White.copy(alpha = 0.75f))
            Spacer(Modifier.height(6.dp))
            Text(formatMoney(net, report.currency, signed = true), style = MaterialTheme.typography.displaySmall.merge(tabular),
                color = Color.White, maxLines = 1)
            rate?.let {
                Spacer(Modifier.height(8.dp))
                Text("Tasa de ahorro ${String.format(spanish, "%.1f %%", it)}", style = MaterialTheme.typography.labelMedium,
                    color = Color.White, modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.16f))
                        .padding(horizontal = 10.dp, vertical = 4.dp))
            }
            Spacer(Modifier.height(18.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                HeroFigure("Ingresos", formatMoney(income, report.currency),
                    change(report.previous.income.decimal, report.incomeChangePercent, higherIsBetter = true), Modifier.weight(1f))
                HeroFigure("Gastos", formatMoney(expenses, report.currency),
                    change(report.previous.expenses.decimal, report.expenseChangePercent, higherIsBetter = false), Modifier.weight(1f), alignEnd = true)
            }
            // Market movements are neither income nor spending, so they sit apart from both.
            investment?.let {
                val up = it.signum() > 0
                val tint = if (up) Color(0xFFB9F6D9) else Color(0xFFFFC9C9)
                Spacer(Modifier.height(14.dp))
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = 0.12f))
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(if (up) Icons.Outlined.TrendingUp else Icons.Outlined.TrendingDown, null, tint = tint, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Rendimiento de inversiones", style = MaterialTheme.typography.labelMedium, color = Color.White)
                        Text("Aparte de ingresos y gastos", style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.7f))
                    }
                    Text(formatMoney(it, report.currency, signed = true), style = MaterialTheme.typography.titleSmall.merge(tabular),
                        color = tint, maxLines = 1)
                }
            }
        }
    }
}

private data class Change(val text: String, val good: Boolean)

private fun change(previous: BigDecimal, percentText: String?, higherIsBetter: Boolean): Change? {
    if (previous.signum() == 0) return null
    val value = percentText?.toBigDecimalOrNull() ?: return null
    if (value.signum() == 0) return Change("= que el mes anterior", true)
    val up = value.signum() > 0
    return Change("${if (up) "↑" else "↓"} ${percent(value)} vs mes anterior", up == higherIsBetter)
}

@Composable private fun HeroFigure(label: String, value: String, change: Change?, modifier: Modifier, alignEnd: Boolean = false) {
    Column(modifier, horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.75f))
        Text(value, style = MaterialTheme.typography.titleMedium.merge(tabular).copy(fontWeight = FontWeight.SemiBold), color = Color.White,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        change?.let {
            Text(it.text, style = MaterialTheme.typography.labelSmall,
                color = if (it.good) Color(0xFFB9F6D9) else Color(0xFFFFC9C9), maxLines = 1)
        }
    }
}

@Composable private fun ReportCard(title: String, subtitle: String?, content: @Composable () -> Unit) {
    Panel(Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, color = Relay.text, style = MaterialTheme.typography.titleMedium)
                subtitle?.let { Text(it, color = Relay.muted, style = MaterialTheme.typography.labelMedium) }
            }
            content()
        }
    }
}

@Composable private fun CardMessage(text: String) = Text(text, color = Relay.muted, style = MaterialTheme.typography.bodyMedium)

private val trendTop = 8.dp
private val trendBars = 120.dp

/**
 * Income and spending per month, the latest on the right. The months sit close together and the row scrolls
 * like any list: dragging to the left edge loads earlier months. Tapping a month opens it.
 */
@Composable private fun TrendCard(
    state: ReportState,
    month: LocalDate,
    startDay: Int,
    currency: String,
    onSelect: (LocalDate) -> Unit,
    onOlder: () -> Unit,
) {
    val months = state.trendMonths
    val max = months.mapNotNull { state.activity[it] }.flatMap { listOf(it.current.income.decimal, it.current.expenses.decimal) }
        .maxOrNull()?.takeIf { it.signum() > 0 }
    val older by rememberUpdatedState(onOlder)
    val list = rememberLazyListState(initialFirstVisibleItemIndex = months.indexOf(month).coerceAtLeast(0))
    // Keep the selected month in view when it changes from the arrows or a swipe.
    LaunchedEffect(month) {
        val index = state.trendMonths.indexOf(month)
        if (index < 0) return@LaunchedEffect
        val layout = list.layoutInfo
        val item = layout.visibleItemsInfo.firstOrNull { it.index == index }
        if (item == null || item.offset < 0 || item.offset + item.size > layout.viewportEndOffset) {
            list.animateScrollToItem((index - 2).coerceAtLeast(0))
        }
    }
    LaunchedEffect(list) {
        snapshotFlow { list.layoutInfo.visibleItemsInfo.firstOrNull()?.index == 0 }
            .distinctUntilChanged()
            .collect { atStart -> if (atStart) older() }
    }
    val selected = state.activity[month]
    ReportCard("Tendencia", "Ingresos y gastos por mes · desliza para ver meses anteriores") {
        val grid = Relay.border.copy(alpha = 0.6f)
        LazyRow(
            state = list,
            modifier = Modifier.fillMaxWidth().drawBehind {
                // A light grid behind the bars: the scale stays readable while the months scroll.
                listOf(0f, 0.5f, 1f).forEach { fraction ->
                    val y = (trendTop + trendBars * fraction).toPx()
                    drawLine(grid, Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx(),
                        pathEffect = if (fraction < 1f) PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())) else null)
                }
            },
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            items(months, key = { it.toString() }) { start ->
                TrendMonth(start, state.activity[start], max, start == month, startDay,
                    showYear = start == months.first() || reportingMonthName(start, startDay).monthValue == 1) { onSelect(start) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Legend(selected?.let { "Ingresos ${formatMoney(it.current.income.decimal, currency)}" } ?: "Ingresos", Relay.income)
            Legend(selected?.let { "Gastos ${formatMoney(it.current.expenses.decimal, currency)}" } ?: "Gastos", Relay.magenta)
        }
        // Averages of the selected month and the five before it.
        val window = (5 downTo 0).mapNotNull { state.activity[month.minusMonths(it.toLong())] }
        if (window.size > 1) {
            val count = BigDecimal(window.size)
            val spending = window.sumOf { it.current.expenses.decimal }.divide(count, 2, RoundingMode.HALF_UP)
            val savings = window.sumOf { it.netSavings.decimal }.divide(count, 2, RoundingMode.HALF_UP)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Average("Gasto medio · 6 meses", formatMoney(spending, currency), Relay.text, Modifier.weight(1f))
                Average("Ahorro medio · 6 meses", formatMoney(savings, currency, signed = true),
                    if (savings.signum() < 0) Relay.danger else Relay.income, Modifier.weight(1f))
            }
        }
    }
}

/** One month of the trend: its two bars side by side, the month underneath and the year when it changes. */
@Composable private fun TrendMonth(
    start: LocalDate,
    report: ActivityReport?,
    max: BigDecimal?,
    selected: Boolean,
    startDay: Int,
    showYear: Boolean,
    onClick: () -> Unit,
) {
    val name = reportingMonthName(start, startDay)
    Column(
        Modifier.width(46.dp).clip(RoundedCornerShape(12.dp))
            .then(if (selected) Modifier.background(Relay.surface2.copy(alpha = 0.8f)) else Modifier)
            .clickable(enabled = !selected && report != null, onClick = onClick)
            .padding(top = trendTop, bottom = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.height(trendBars), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom) {
            val alpha = if (selected) 1f else 0.5f
            TrendBar(report?.current?.income?.decimal, max, Relay.income.copy(alpha = alpha))
            TrendBar(report?.current?.expenses?.decimal, max, Relay.magenta.copy(alpha = alpha))
        }
        Spacer(Modifier.height(6.dp))
        Text(name.format(monthShort).trimEnd('.'), style = MaterialTheme.typography.labelSmall,
            color = if (selected) Relay.text else Relay.muted, fontWeight = if (selected) FontWeight.SemiBold else null, maxLines = 1)
        Text(if (showYear) name.year.toString() else " ", style = MaterialTheme.typography.labelSmall.merge(tabular),
            color = Relay.subtle, maxLines = 1)
    }
}

@Composable private fun TrendBar(value: BigDecimal?, max: BigDecimal?, color: Color) {
    val target = if (value == null || max == null) 0f else (value.toDouble() / max.toDouble()).toFloat().coerceIn(0f, 1f)
    val fraction by animateFloatAsState(target, tween(600, easing = Relay.easeOut), label = "bar")
    Box(Modifier.width(14.dp).fillMaxHeight(fraction.coerceAtLeast(0.015f))
        .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp)).background(if (value == null) Relay.surface3 else color))
}

@Composable private fun Legend(label: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(6.dp))
        Text(label, style = MaterialTheme.typography.labelMedium, color = Relay.muted)
    }
}

@Composable private fun Average(label: String, value: String, color: Color, modifier: Modifier) {
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(Relay.surface2.copy(alpha = 0.6f)).padding(horizontal = 12.dp, vertical = 8.dp)) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = Relay.muted)
        Text(value, style = MaterialTheme.typography.bodyMedium.merge(tabular), color = color, maxLines = 1)
    }
}

/** Spending accumulated day by day against the previous month, as the web dashboard chart. */
@Composable private fun SpendingCard(trend: SpendingTrend?, pending: Boolean, month: LocalDate, startDay: Int) {
    ReportCard("Gasto", "Acumulado frente al mes anterior") {
        when {
            trend == null && pending -> Skeleton(Modifier.fillMaxWidth(), height = 150.dp)
            trend == null -> CardMessage("No se pudo cargar la evolución del gasto.")
            trend.current.isEmpty() -> CardMessage("No hay gastos en este mes.")
            else -> {
                val total = trend.currentTotal.toBigDecimalOrNull() ?: BigDecimal.ZERO
                val comparison = trend.comparisonTotal.toBigDecimalOrNull() ?: BigDecimal.ZERO
                val delta = trend.delta.toBigDecimalOrNull() ?: BigDecimal.ZERO
                val tone = when (delta.signum()) { 1 -> Relay.danger; -1 -> Relay.income; else -> Relay.muted }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                    Column(Modifier.weight(1f)) {
                        Text(formatMoney(total, trend.currency), style = MaterialTheme.typography.titleLarge.merge(tabular), color = Relay.text)
                        Text(
                            when (delta.signum()) {
                                0 -> "Igual que el mes anterior"
                                1 -> "${formatMoney(delta, trend.currency)} más que el mes anterior"
                                else -> "${formatMoney(delta.abs(), trend.currency)} menos que el mes anterior"
                            },
                            style = MaterialTheme.typography.labelMedium, color = tone,
                        )
                    }
                    if (comparison.signum() > 0 && delta.signum() != 0) Text(
                        "${if (delta.signum() > 0) "↑" else "↓"} ${percent(delta.multiply(BigDecimal(100)).divide(comparison, 1, RoundingMode.HALF_UP))}",
                        style = MaterialTheme.typography.labelLarge.merge(tabular), color = tone,
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(tone.copy(alpha = 0.14f)).padding(horizontal = 10.dp, vertical = 4.dp),
                    )
                }
                val days = (ReportState.end(month).toEpochDay() - month.toEpochDay() + 1).toInt()
                SpendingChart(trend.current.map { it.decimal }, trend.previous.map { it.decimal }, days, trend)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Legend(monthName(month, startDay).substringBefore(' '), Relay.magenta)
                    Spacer(Modifier.width(14.dp))
                    Legend("Mes anterior", Relay.muted)
                    Spacer(Modifier.weight(1f))
                    Text("${month.format(dayMonth)} – ${ReportState.end(month).format(dayMonth)}",
                        style = MaterialTheme.typography.labelSmall.merge(tabular), color = Relay.subtle)
                }
            }
        }
    }
}

/** Two cumulative curves on the selected month's axis; the current one is revealed from the left. */
@Composable private fun SpendingChart(current: List<BigDecimal>, previous: List<BigDecimal>, days: Int, key: Any) {
    val reveal = remember(key) { Animatable(0f) }
    LaunchedEffect(key) { reveal.animateTo(1f, tween(750, easing = Relay.easeOut)) }
    val axis = maxOf(days, previous.size, current.size, 2)
    val max = (current + previous).maxOfOrNull { it.toDouble() }?.takeIf { it > 0 } ?: 1.0
    Canvas(Modifier.fillMaxWidth().height(140.dp)) {
        val margin = 6.dp.toPx()
        val width = size.width - 2 * margin
        val height = size.height - 2 * margin
        fun point(index: Int, value: BigDecimal) =
            Offset(margin + width * index / (axis - 1), margin + height * (1 - (value.toDouble() / max).toFloat()))
        fun path(values: List<BigDecimal>) = Path().apply {
            values.forEachIndexed { index, value -> point(index, value).let { if (index == 0) moveTo(it.x, it.y) else lineTo(it.x, it.y) } }
        }
        listOf(0f, 0.5f, 1f).forEach { fraction ->
            val y = margin + height * fraction
            drawLine(Relay.border, Offset(margin, y), Offset(size.width - margin, y))
        }
        if (previous.size > 1) drawPath(path(previous), Relay.muted.copy(alpha = 0.8f),
            style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(8.dp.toPx(), 6.dp.toPx()))))
        if (current.isEmpty()) return@Canvas
        val line = path(current)
        val last = point(current.lastIndex, current.last())
        val fill = Path().apply {
            addPath(line)
            lineTo(last.x, size.height - margin)
            lineTo(margin, size.height - margin)
            close()
        }
        clipRect(right = margin + (last.x - margin) * reveal.value + 6.dp.toPx()) {
            drawPath(fill, Brush.verticalGradient(listOf(Relay.magenta.copy(alpha = 0.28f), Color.Transparent)))
            drawPath(line, Brush.horizontalGradient(listOf(Relay.violet, Relay.magenta)), style = Stroke(2.75.dp.toPx(), cap = StrokeCap.Round))
        }
        if (reveal.value > 0.98f) {
            drawCircle(Relay.magenta.copy(alpha = 0.25f), 7.dp.toPx(), last)
            drawCircle(Relay.magenta, 3.5.dp.toPx(), last)
        }
    }
}

private fun nodeColor(node: CashFlowNode, index: Int) = node.color?.let(::parseHex) ?: chartPalette[index % chartPalette.size]

@Composable private fun CategoriesCard(
    flow: CashFlow?,
    pending: Boolean,
    month: LocalDate,
    icons: Map<String, String?>,
    onCategory: (CategorySelection) -> Unit,
) {
    var kind by rememberSaveable { mutableStateOf("expense") }
    ReportCard("Por categoría", "Netas de devoluciones, como en Relay web") {
        KindToggle(kind) { kind = it }
        val categories = remember(flow, kind) { flow?.sankey?.categories(kind).orEmpty() }
        when {
            flow == null && pending -> Skeleton(Modifier.fillMaxWidth(), height = 160.dp)
            flow == null -> CardMessage("No se pudieron cargar las categorías.")
            categories.isEmpty() -> CardMessage(if (kind == "expense") "No hay gastos en este mes." else "No hay ingresos en este mes.")
            else -> {
                val colors = categories.mapIndexed { index, category -> nodeColor(category.node, index) }
                val total = categories.sumOf { it.node.value.toBigDecimal() }
                Donut(categories.map { it.node.value.toBigDecimal() }.zip(colors), total, flow.currency,
                    if (kind == "expense") "Gastos" else "Ingresos")
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    categories.forEachIndexed { index, category ->
                        CategoryReportRow(category, colors[index], icons, total, flow.currency, month, onCategory)
                    }
                }
            }
        }
    }
}

/**
 * Money that is neither income nor spending, kept apart as on the web report: transfers to or from accounts outside
 * the finances (mortgage or robo-advisor contributions, for example) and the market movement of managed portfolios.
 */
@Composable private fun TransfersCard(flow: CashFlow?, activity: ActivityReport?) {
    val transfers = remember(flow) { flow?.sankey?.boundaryTransfers().orEmpty() }
    val valuation = activity?.current?.investmentReturn?.decimal?.takeIf { it.signum() != 0 }
    if (flow == null || (transfers.isEmpty() && valuation == null)) return
    ReportCard("Transferencias y valoraciones", "No cuentan como ingresos ni como gastos") {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            transfers.forEach { transfer ->
                val outflow = transfer.node.kind == "expense"
                val amount = transfer.node.value.toBigDecimal()
                MoneyFlowRow(Icons.Outlined.SwapHoriz, Relay.cyan, transfer.node.name,
                    if (outflow) "Salida hacia cuentas fuera de tus finanzas" else "Entrada desde cuentas fuera de tus finanzas",
                    formatMoney(if (outflow) amount.negate() else amount, flow.currency, signed = true), Relay.text)
            }
            valuation?.let {
                val up = it.signum() > 0
                MoneyFlowRow(if (up) Icons.Outlined.TrendingUp else Icons.Outlined.TrendingDown, if (up) Relay.income else Relay.danger,
                    "Valoraciones", "Rendimiento de carteras gestionadas", formatMoney(it, activity.currency, signed = true),
                    if (up) Relay.income else Relay.danger)
            }
        }
    }
}

@Composable private fun MoneyFlowRow(icon: ImageVector, tone: Color, title: String, detail: String, amount: String, amountTone: Color) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconBadge(icon, tone, size = 40.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = Relay.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = Relay.muted, maxLines = 2)
        }
        Spacer(Modifier.width(12.dp))
        Text(amount, style = MaterialTheme.typography.bodyLarge.merge(tabular).copy(fontWeight = FontWeight.Medium), color = amountTone,
            maxLines = 1)
    }
}

@Composable private fun KindToggle(kind: String, onChange: (String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Relay.surface2.copy(alpha = 0.7f)).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        listOf("expense" to "Gastos", "income" to "Ingresos").forEach { (value, label) ->
            val active = value == kind
            Box(
                Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(10.dp))
                    .then(if (active) Modifier.background(Relay.gradient) else Modifier)
                    .clickable(enabled = !active) { onChange(value) },
                contentAlignment = Alignment.Center,
            ) { Text(label, style = MaterialTheme.typography.labelLarge, color = if (active) Color.White else Relay.muted) }
        }
    }
}

@Composable private fun Donut(parts: List<Pair<BigDecimal, Color>>, total: BigDecimal, currency: String, label: String) {
    val progress by animateFloatAsState(1f, tween(700, easing = Relay.easeOut), label = "donut")
    Box(Modifier.fillMaxWidth().height(180.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(170.dp)) {
            val stroke = 22.dp.toPx()
            val inset = stroke / 2
            val arc = Size(size.width - stroke, size.height - stroke)
            val sum = total.toDouble().takeIf { it > 0 } ?: return@Canvas
            val gap = if (parts.size > 1) 1.5f else 0f
            var angle = -90f
            parts.forEach { (value, color) ->
                val sweep = (value.toDouble() / sum * 360f).toFloat() * progress
                if (sweep > gap) {
                    drawArc(color, angle + gap / 2, sweep - gap, useCenter = false, topLeft = Offset(inset, inset), size = arc,
                        style = Stroke(stroke, cap = StrokeCap.Butt))
                }
                angle += sweep
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = Relay.muted)
            Text(formatMoney(total, currency), style = MaterialTheme.typography.titleMedium.merge(tabular), color = Relay.text,
                textAlign = TextAlign.Center)
        }
    }
}

/**
 * One category: name and amount on a line, its share as a bar underneath. Tapping the row lists its
 * movements; the chevron unfolds the subcategories with their share of this category.
 */
@Composable private fun CategoryReportRow(
    category: FlowCategory,
    color: Color,
    icons: Map<String, String?>,
    total: BigDecimal,
    currency: String,
    month: LocalDate,
    onCategory: (CategorySelection) -> Unit,
) {
    var expanded by rememberSaveable(category.node.name, month.toString()) { mutableStateOf(false) }
    val node = category.node
    val amount = node.value.toBigDecimal()
    val share = if (total.signum() > 0) amount.multiply(BigDecimal(100)).divide(total, 1, RoundingMode.HALF_UP) else BigDecimal.ZERO
    val icon = node.categoryId?.let(icons::get)
    val ids = listOfNotNull(node.categoryId) + category.children.mapNotNull { it.categoryId }
    val rotation by animateFloatAsState(if (expanded) 180f else 0f, tween(Relay.BASE, easing = Relay.easeOut), label = "chevron")
    val background by animateColorAsState(if (expanded) Relay.surface2.copy(alpha = 0.5f) else Relay.surface2.copy(alpha = 0f),
        tween(Relay.BASE), label = "row")
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(background)) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                .clickable(enabled = ids.isNotEmpty()) { onCategory(CategorySelection(node.name, color, icon, amount, ids, month, node.categoryId)) }
                .padding(start = 8.dp, end = 4.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconBadge(categoryIcon(icon), color, size = 40.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(node.name, style = MaterialTheme.typography.bodyLarge, color = Relay.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(8.dp))
                    Text(formatMoney(amount, currency), style = MaterialTheme.typography.bodyLarge.merge(tabular).copy(fontWeight = FontWeight.Medium),
                        color = Relay.text, maxLines = 1)
                }
                Spacer(Modifier.height(7.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ShareBar(share, color, Modifier.weight(1f))
                    Text(percent(share), style = MaterialTheme.typography.labelSmall.merge(tabular), color = Relay.muted, textAlign = TextAlign.End,
                        modifier = Modifier.widthIn(min = 48.dp))
                }
            }
            // The slot is kept on every row so amounts and bars line up.
            Box(
                Modifier.padding(start = 2.dp).size(34.dp).clip(CircleShape)
                    .then(if (category.children.isNotEmpty()) Modifier.clickable { expanded = !expanded } else Modifier),
                contentAlignment = Alignment.Center,
            ) {
                if (category.children.isNotEmpty()) Icon(Icons.Outlined.ExpandMore,
                    if (expanded) "Ocultar subcategorías" else "Ver subcategorías", tint = Relay.secondary, modifier = Modifier.rotate(rotation))
            }
        }
        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(tween(Relay.BASE + 60, easing = Relay.easeOut)) + fadeIn(tween(Relay.BASE)),
            exit = shrinkVertically(tween(Relay.BASE, easing = Relay.easeOut)) + fadeOut(tween(Relay.FAST)),
        ) {
            Column(Modifier.fillMaxWidth().padding(start = 52.dp, end = 40.dp, bottom = 8.dp)) {
                category.children.forEach { child ->
                    val childIcon = child.categoryId?.let(icons::get)
                    val childAmount = child.value.toBigDecimal()
                    val childColor = child.color?.let(::parseHex) ?: color
                    val childShare = if (amount.signum() > 0) childAmount.multiply(BigDecimal(100)).divide(amount, 1, RoundingMode.HALF_UP) else BigDecimal.ZERO
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                            .clickable(enabled = child.categoryId != null) {
                                onCategory(CategorySelection(child.name, childColor, childIcon, childAmount, listOfNotNull(child.categoryId), month, child.categoryId))
                            }
                            .padding(horizontal = 8.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconBadge(categoryIcon(childIcon), childColor, size = 28.dp)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(child.name, style = MaterialTheme.typography.bodyMedium, color = Relay.secondary, maxLines = 1,
                                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                Spacer(Modifier.width(8.dp))
                                Text(formatMoney(childAmount, currency), style = MaterialTheme.typography.bodyMedium.merge(tabular), color = Relay.text)
                            }
                            Spacer(Modifier.height(5.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                ShareBar(childShare, childColor, Modifier.weight(1f), height = 3.dp)
                                Text(percent(childShare), style = MaterialTheme.typography.labelSmall.merge(tabular), color = Relay.subtle,
                                    textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 44.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

/** A share of 0–100 % as a rounded bar that grows into place. */
@Composable private fun ShareBar(share: BigDecimal, color: Color, modifier: Modifier, height: Dp = 5.dp) {
    val fraction by animateFloatAsState((share.toFloat() / 100f).coerceIn(0f, 1f), tween(600, easing = Relay.easeOut), label = "share")
    Box(modifier.height(height).clip(RoundedCornerShape(50)).background(Relay.surface3.copy(alpha = 0.8f))) {
        Box(Modifier.fillMaxWidth(fraction.coerceAtLeast(0.01f)).fillMaxHeight().clip(RoundedCornerShape(50)).background(color))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun CategoryMovementsSheet(
    selection: CategorySelection,
    startDay: Int,
    currency: String,
    vm: AppViewModel,
    onDismiss: () -> Unit,
    onTransaction: (Transaction) -> Unit,
) {
    var attempt by remember { mutableStateOf(0) }
    val result by produceState<Result<List<Transaction>>?>(null, selection, attempt) {
        value = null
        value = try {
            Result.success(vm.categoryTransactions(selection.categoryIds, selection.start, ReportState.end(selection.start)))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Result.failure(error)
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Relay.surface, contentColor = Relay.text) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 16.dp)) {
            // A heading for the sheet, centred and set apart, so it never reads as the first movement.
            Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                IconBadge(categoryIcon(selection.icon), selection.color, size = 48.dp)
                Spacer(Modifier.height(10.dp))
                Text(selection.name, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center, maxLines = 2,
                    overflow = TextOverflow.Ellipsis)
                Text(monthName(selection.start, startDay), style = MaterialTheme.typography.labelMedium, color = Relay.muted)
                Spacer(Modifier.height(6.dp))
                Text(formatMoney(selection.total, currency), style = MaterialTheme.typography.headlineSmall.merge(tabular), color = Relay.text)
            }
            Spacer(Modifier.height(16.dp))
            HorizontalDivider(color = Relay.border, modifier = Modifier.padding(horizontal = 16.dp))
            val movements = result?.getOrNull().orEmpty()
            // Only what adds up to the category's total is listed as such; the rest comes after, set apart.
            val (counted, apart) = movements.partition { it.countsInCategoryTotals }
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp).padding(horizontal = 16.dp)) {
                if (counted.isNotEmpty()) item(key = "counted") { SheetSection("Movimientos", counted.size) }
                items(counted, key = { it.id }) { movement ->
                    TransactionRow(movement, { onTransaction(movement) }, showDate = true,
                        showCategory = selection.categoryId == null || movement.category?.id != selection.categoryId)
                }
                if (apart.isNotEmpty()) item(key = "apart") {
                    SheetSection("No cuentan en el total", apart.size, "Transferencias, aportaciones y movimientos excluidos de informes.")
                }
                items(apart, key = { it.id }) { movement ->
                    TransactionRow(movement, { onTransaction(movement) }, showDate = true)
                }
                item(key = "status") {
                    when {
                        result == null -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(26.dp), color = Relay.violet, strokeWidth = 2.5.dp)
                        }
                        result?.isFailure == true -> ErrorBanner(vm.describe(result!!.exceptionOrNull()!!), Modifier.padding(vertical = 8.dp)) { attempt++ }
                        movements.isEmpty() -> CardMessage("No hay movimientos en esta categoría este mes.")
                        else -> Spacer(Modifier.height(8.dp))
                    }
                }
            }
        }
    }
}

/** A labelled group inside the category sheet, e.g. "MOVIMIENTOS · 12". */
@Composable private fun SheetSection(title: String, count: Int, note: String? = null) {
    Column(Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp, top = 16.dp, bottom = 4.dp)) {
        Text("${title.uppercase(spanish)} · $count", style = eyebrow, color = Relay.muted)
        note?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Relay.subtle) }
    }
}
