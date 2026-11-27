package app.relay.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.EventRepeat
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.data.Account
import app.relay.android.data.LoanBonus
import app.relay.android.data.LoanDetail
import app.relay.android.data.LoanInstalment
import app.relay.android.data.LoanListItem
import app.relay.android.data.LoanPayment
import app.relay.android.data.LoanRevision
import app.relay.android.data.LoanSchedule
import app.relay.android.data.LoanSummary
import app.relay.android.data.Money
import app.relay.android.data.decimalOrZero
import app.relay.android.data.formatMoney
import app.relay.android.data.formatRate
import app.relay.android.data.formatTerm
import app.relay.android.data.loanSubtypeName
import java.math.BigDecimal
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val spanish = Locale.forLanguageTag("es-ES")
private val longDate = DateTimeFormatter.ofPattern("d MMM yyyy", spanish)

private fun dateText(iso: String?): String? = iso?.let { runCatching { LocalDate.parse(it).format(longDate) }.getOrNull() }
private fun Money.text() = formatMoney(decimal, currency)
private fun percentText(ratio: Double) = String.format(spanish, "%.1f %%", ratio * 100)

/** Principal, interest and insurance keep one colour each across the section. */
private val principalTone = Relay.cyan
private val interestTone = Relay.magenta
private val insuranceTone = Relay.warning

/**
 * Read-only view of the user's loans. With a single loan the section opens on it; with several, on the list.
 * Every figure comes from Relay's loan engine; nothing is computed here beyond presentation.
 */
@Composable fun LoansScreen(vm: AppViewModel) {
    val loans = vm.loans
    val state by loans.state.collectAsStateWithLifecycle()
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { loans.open() }
    val list = state.list
    val many = (list?.size ?: 0) > 1
    // A loan no longer listed (closed, or no longer shared) returns to the list.
    val shownId = selectedId?.takeIf { id -> list == null || list.any { it.account.id == id } } ?: list?.singleOrNull()?.account?.id
    BackHandler(enabled = selectedId != null && many) { selectedId = null }

    AnimatedContent(
        targetState = shownId,
        transitionSpec = {
            if (targetState != null && initialState == null) {
                (slideInHorizontally(tween(320, easing = Relay.easeOut)) { it / 3 } + fadeIn(tween(Relay.BASE))) togetherWith fadeOut(tween(Relay.FAST))
            } else {
                fadeIn(tween(Relay.BASE)) togetherWith (slideOutHorizontally(tween(Relay.BASE)) { it / 3 } + fadeOut(tween(Relay.FAST)))
            }
        },
        label = "loan",
    ) { id ->
        if (id == null) LoanList(state, loans) { selectedId = it }
        else LoanDetailScreen(id, state, loans, onBack = if (many) ({ selectedId = null }) else null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun LoanList(state: LoansState, loans: Loans, onOpen: (String) -> Unit) {
    val list = state.list
    PullToRefreshBox(isRefreshing = state.refreshing, onRefresh = { loans.refresh() }, modifier = Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 96.dp)) {
            item(key = "title") {
                Text("Préstamos", style = MaterialTheme.typography.headlineMedium,
                    modifier = Modifier.statusBarsPadding().padding(top = 20.dp, bottom = 14.dp).enter(0))
            }
            state.error?.let { error -> item(key = "error") { ErrorBanner(error, Modifier.padding(bottom = 12.dp), loans::retry) } }
            when {
                list == null -> if (state.error == null) items(2) { Skeleton(Modifier.fillMaxWidth().padding(bottom = 12.dp), height = 150.dp) }
                list.isEmpty() -> item(key = "empty") {
                    EmptyState("No hay préstamos", "Las hipotecas y préstamos que tengas en Relay aparecerán aquí.")
                }
                else -> itemsIndexed(list, key = { _, item -> item.account.id }) { index, item ->
                    LoanCard(item, Modifier.padding(bottom = 12.dp).enter(index + 1)) { onOpen(item.account.id) }
                }
            }
        }
    }
}

@Composable private fun LoanCard(item: LoanListItem, modifier: Modifier, onClick: () -> Unit) {
    val summary = item.summary
    Panel(modifier.fillMaxWidth(), onClick = onClick, padding = 18.dp) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AccountBadge(item.account, size = 44.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(item.account.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(loanSubtitle(item.account), style = MaterialTheme.typography.bodySmall, color = Relay.muted, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                }
                Icon(Icons.Outlined.ChevronRight, null, tint = Relay.muted)
            }
            Spacer(Modifier.height(16.dp))
            Text("DEUDA PENDIENTE", style = eyebrow, color = Relay.muted)
            Text(summary.currentDebt.text(), style = MaterialTheme.typography.headlineSmall.merge(tabular), color = Relay.text)
            summary.repaidRatio?.let { ratio ->
                Spacer(Modifier.height(10.dp))
                ProgressBar(ratio.toFloat(), Relay.logoGradient, Relay.surface3)
                Spacer(Modifier.height(6.dp))
                Text("${percentText(ratio)} amortizado de ${summary.originalPrincipal.text()}", style = MaterialTheme.typography.labelMedium,
                    color = Relay.muted)
            }
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                summary.payment?.let { payment ->
                    MiniFigure("Próxima cuota", payment.text(), dateText(summary.nextPaymentDate), Modifier.weight(1f))
                }
                MiniFigure("Tipo actual", formatRate(summary.currentRate), null, Modifier.weight(1f))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun LoanDetailScreen(id: String, state: LoansState, loans: Loans, onBack: (() -> Unit)?) {
    val detail = state.details[id]
    // Also when the cached figures are dropped by a refresh while this loan is on screen.
    LaunchedEffect(id, detail == null) { if (detail == null) loans.openDetail(id) }
    val item = state.list?.find { it.account.id == id }
    val account = detail?.account ?: item?.account
    val summary = detail?.summary ?: item?.summary
    val loadingDetail = id in state.loadingDetails
    val detailError = state.detailErrors[id]
    var showPaid by rememberSaveable(id) { mutableStateOf(false) }
    var shown by rememberSaveable(id) { mutableIntStateOf(SCHEDULE_PAGE) }

    PullToRefreshBox(
        isRefreshing = detail != null && (state.refreshing || loadingDetail),
        onRefresh = { loans.refresh(id) },
        modifier = Modifier.fillMaxSize(),
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 96.dp)) {
            item(key = "header") { DetailHeader(account, onBack) }
            item(key = "debt") {
                if (summary != null) DebtCard(summary, Modifier.enter(1)) else Skeleton(Modifier.fillMaxWidth(), height = 190.dp)
            }
            (detailError ?: state.error.takeIf { summary == null })?.let { error ->
                item(key = "error") {
                    ErrorBanner(error, Modifier.padding(top = 12.dp)) {
                        if (state.list == null) loans.retry()
                        loans.retryDetail(id)
                    }
                }
            }
            if (detail == null) {
                if (detailError == null) items(3) { Skeleton(Modifier.fillMaxWidth().padding(top = 12.dp), height = 120.dp) }
            } else {
                detail.currentInstalment?.let { instalment -> item(key = "instalment") { InstalmentCard(instalment, Modifier.enter(2)) } }
                item(key = "rate") { RateCard(detail, Modifier.enter(3)) }
                item(key = "terms") { TermsCard(detail, Modifier.enter(4)) }
                if (detail.rate.bonuses.isNotEmpty()) item(key = "bonuses") { BonusesCard(detail.rate.bonuses, Modifier.enter(5)) }
                if (detail.rate.revisions.isNotEmpty()) item(key = "revisions") { RevisionsCard(detail.rate.revisions, Modifier.enter(6)) }
                detail.schedule?.let { schedule ->
                    scheduleSection(schedule, showPaid, shown,
                        onShowPaid = { paid -> showPaid = paid; shown = SCHEDULE_PAGE },
                        onMore = { shown += SCHEDULE_PAGE * 2 })
                }
            }
        }
    }
}

private const val SCHEDULE_PAGE = 12

@Composable private fun DetailHeader(account: Account?, onBack: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().statusBarsPadding().padding(top = if (onBack != null) 8.dp else 20.dp, bottom = 14.dp).enter(0),
        verticalAlignment = Alignment.CenterVertically) {
        onBack?.let {
            IconButton(onClick = it) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "Volver", tint = Relay.text) }
            Spacer(Modifier.width(4.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(account?.name ?: "Préstamo", style = MaterialTheme.typography.headlineMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            account?.let { Text(loanSubtitle(it), style = MaterialTheme.typography.bodyMedium, color = Relay.muted, maxLines = 1) }
        }
        account?.let { Spacer(Modifier.width(12.dp)); AccountBadge(it, size = 44.dp) }
    }
}

private fun loanSubtitle(account: Account) =
    listOfNotNull(loanSubtypeName(account.subtype), account.institutionName?.takeIf { it.isNotBlank() }).joinToString(" · ")

/** The debt, how much of the loan is repaid, and what the instalments paid so far have done. */
@Composable private fun DebtCard(summary: LoanSummary, modifier: Modifier = Modifier) {
    val progress = remember(summary) { Animatable(0f) }
    LaunchedEffect(summary) { progress.animateTo(1f, tween(900, easing = Relay.easeOut)) }
    val debt = summary.currentDebt.decimal
    val ratio = summary.repaidRatio?.toFloat()

    Box(
        modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Relay.gradient).drawBehind {
            drawCircle(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.18f), Color.Transparent),
                center = Offset(size.width * 0.95f, 0f), radius = size.width * 0.7f))
            drawCircle(Brush.radialGradient(listOf(Relay.cyan.copy(alpha = 0.25f), Color.Transparent),
                center = Offset(0f, size.height), radius = size.width * 0.6f))
        }.padding(22.dp),
    ) {
        Column {
            Text("DEUDA PENDIENTE", style = eyebrow, color = Color.White.copy(alpha = 0.75f))
            Spacer(Modifier.height(8.dp))
            Text(formatMoney(debt.multiply(BigDecimal(progress.value.toDouble())), summary.currentDebt.currency),
                style = MaterialTheme.typography.displaySmall.merge(tabular), color = Color.White, maxLines = 1)
            if (ratio != null) {
                Spacer(Modifier.height(18.dp))
                ProgressBar(ratio * progress.value, androidx.compose.ui.graphics.SolidColor(Color.White.copy(alpha = 0.92f)),
                    Color.White.copy(alpha = 0.18f))
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth()) {
                    Text("${percentText(ratio.toDouble())} amortizado", style = MaterialTheme.typography.labelLarge, color = Color.White,
                        modifier = Modifier.weight(1f))
                    Text("Prestado ${summary.originalPrincipal.text()}", style = MaterialTheme.typography.labelMedium.merge(tabular),
                        color = Color.White.copy(alpha = 0.75f))
                }
            } else {
                Spacer(Modifier.height(6.dp))
                Text("Prestado ${summary.originalPrincipal.text()}", style = MaterialTheme.typography.labelMedium.merge(tabular),
                    color = Color.White.copy(alpha = 0.75f))
            }
            if (summary.principalRepaid != null && summary.interestPaid != null) {
                Spacer(Modifier.height(16.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    HeroFigure("Capital devuelto", summary.principalRepaid.text(), Relay.cyan)
                    HeroFigure("Intereses pagados", summary.interestPaid.text(), Relay.magenta, alignEnd = true)
                }
            }
        }
    }
}

@Composable private fun HeroFigure(label: String, value: String, dot: Color, alignEnd: Boolean = false) {
    Column(horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(dot))
            Spacer(Modifier.width(6.dp))
            Text(label, style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.75f))
        }
        Text(value, style = MaterialTheme.typography.titleMedium.merge(tabular).copy(fontWeight = FontWeight.SemiBold), color = Color.White)
    }
}

@Composable private fun ProgressBar(fraction: Float, fill: Brush, track: Color) {
    Box(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50)).background(track)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).fillMaxHeight().clip(RoundedCornerShape(50)).background(fill))
    }
}

/** Card with a title and an optional subtitle, as the summary widgets. */
@Composable private fun LoanSection(title: String, subtitle: String?, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Panel(modifier.fillMaxWidth().padding(top = 12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, color = Relay.text, style = MaterialTheme.typography.titleMedium)
                subtitle?.let { Text(it, color = Relay.muted, style = MaterialTheme.typography.labelMedium) }
            }
            content()
        }
    }
}

/** The instalment due next, split into the principal it repays, the interest it pays and any insurance. */
@Composable private fun InstalmentCard(instalment: LoanInstalment, modifier: Modifier = Modifier) {
    val progress = remember(instalment) { Animatable(0f) }
    LaunchedEffect(instalment) { progress.animateTo(1f, tween(700, easing = Relay.easeOut)) }
    val insurance = instalment.insurance?.takeIf { it.decimal.signum() > 0 }
    val parts = listOfNotNull(
        Triple("Capital", instalment.principal, principalTone) to instalment.ratios.principal,
        Triple("Intereses", instalment.interest, interestTone) to instalment.ratios.interest,
        insurance?.let { Triple("Seguro", it, insuranceTone) to instalment.ratios.insurance },
    )
    LoanSection("Cuota actual", listOfNotNull("Cuota nº ${instalment.number}", dateText(instalment.date)).joinToString(" · "), modifier) {
        Text(instalment.total.text(), style = MaterialTheme.typography.headlineMedium.merge(tabular), color = Relay.text)
        Row(Modifier.fillMaxWidth().height(12.dp).clip(RoundedCornerShape(50)).background(Relay.surface3),
            horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            parts.filter { it.second > 0 }.forEach { (part, ratio) ->
                Box(Modifier.weight((ratio * progress.value).toFloat().coerceAtLeast(0.001f)).fillMaxHeight().background(part.third))
            }
            val rest = 1f - progress.value
            if (rest > 0.001f) Spacer(Modifier.weight(rest))
        }
        parts.forEach { (part, ratio) ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(10.dp).clip(CircleShape).background(part.third))
                Spacer(Modifier.width(10.dp))
                Text(part.first, style = MaterialTheme.typography.bodyMedium, color = Relay.secondary, modifier = Modifier.weight(1f))
                Text(percentText(ratio), style = MaterialTheme.typography.labelMedium.merge(tabular), color = Relay.muted)
                Spacer(Modifier.width(12.dp))
                Text(part.second.text(), style = MaterialTheme.typography.bodyMedium.merge(tabular), color = Relay.text)
            }
        }
    }
}

/** What the rate is made of today and, when it is revised next, the estimated rate and instalment. */
@Composable private fun RateCard(detail: LoanDetail, modifier: Modifier = Modifier) {
    val rate = detail.rate
    val kinds = rate.periods.map { it.rateKind }.toSet()
    val type = when {
        kinds.size > 1 -> "Mixto"
        kinds.singleOrNull() == "variable" || (kinds.isEmpty() && detail.summary.rateType != null && detail.summary.rateType != "fixed") -> "Variable"
        else -> "Fijo"
    }
    LoanSection("Tipo de interés", type, modifier) {
        Text(formatRate(rate.currentRate ?: detail.summary.currentRate), style = MaterialTheme.typography.headlineMedium.merge(tabular),
            color = Relay.text)
        rate.current?.let { current ->
            Text(current.compositionText(), style = MaterialTheme.typography.bodyMedium, color = Relay.muted)
        }
        rate.nextRevision?.let { upcoming -> NextRevision(upcoming, rate.currentRate, detail.summary.payment) }
        if (rate.periods.isNotEmpty()) {
            HorizontalDivider(color = Relay.border)
            Text("TRAMOS", style = eyebrow, color = Relay.muted)
            rate.periods.forEach { period ->
                Row(Modifier.fillMaxWidth()) {
                    Text("Desde ${dateText(period.startsOn) ?: period.startsOn}", style = MaterialTheme.typography.bodyMedium,
                        color = Relay.secondary, modifier = Modifier.width(132.dp))
                    Text(period.termsText(), style = MaterialTheme.typography.bodyMedium, color = Relay.text, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable private fun NextRevision(upcoming: LoanRevision, currentRate: String?, payment: Money?) {
    val from = currentRate.decimalOrZero()
    val to = upcoming.rate.decimalOrZero()
    val tone = when { currentRate == null -> Relay.text; to > from -> Relay.danger; to < from -> Relay.income; else -> Relay.text }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Relay.surface2.copy(alpha = 0.7f)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.EventRepeat, null, tint = Relay.blue, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("PRÓXIMA REVISIÓN", style = eyebrow, color = Relay.muted, modifier = Modifier.weight(1f))
            Text(dateText(upcoming.effectiveOn) ?: upcoming.effectiveOn, style = MaterialTheme.typography.labelLarge, color = Relay.text)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(formatRate(currentRate), style = MaterialTheme.typography.titleMedium.merge(tabular), color = Relay.secondary)
            Icon(Icons.AutoMirrored.Outlined.ArrowForward, null, tint = Relay.muted, modifier = Modifier.padding(horizontal = 8.dp).size(18.dp))
            Text(formatRate(upcoming.rate), style = MaterialTheme.typography.titleLarge.merge(tabular), color = tone)
            Spacer(Modifier.width(8.dp))
            Text("estimado", style = MaterialTheme.typography.labelMedium, color = Relay.muted)
        }
        Text(upcoming.compositionText(), style = MaterialTheme.typography.bodySmall, color = Relay.muted)
        upcoming.newPayment?.let { newPayment ->
            val delta = payment?.let { newPayment.decimal - it.decimal }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Nueva cuota estimada", style = MaterialTheme.typography.bodyMedium, color = Relay.secondary)
                    dateText(upcoming.newPaymentDate)?.let { Text("Desde el $it", style = MaterialTheme.typography.labelMedium, color = Relay.muted) }
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(newPayment.text(), style = MaterialTheme.typography.titleMedium.merge(tabular), color = Relay.text)
                    if (delta != null && delta.signum() != 0) {
                        Text("${formatMoney(delta, newPayment.currency, signed = true)} al mes", style = MaterialTheme.typography.labelMedium.merge(tabular),
                            color = if (delta.signum() > 0) Relay.danger else Relay.income)
                    }
                }
            }
        }
        Text(
            if (upcoming.variable) "Estimación con el último valor publicado del índice y las bonificaciones activas hoy."
            else "Se aplican las bonificaciones activas en la fecha de revisión.",
            style = MaterialTheme.typography.labelSmall, color = Relay.subtle,
        )
    }
}

@Composable private fun TermsCard(detail: LoanDetail, modifier: Modifier = Modifier) {
    val summary = detail.summary
    val schedule = detail.schedule
    val projected = schedule?.projectedPayoffDate?.takeIf { it != schedule.payoffDate }
    val rows = listOfNotNull(
        formatTerm(summary.termMonths)?.let { "Plazo" to it },
        formatTerm(summary.remainingMonths)?.let { "Quedan" to it },
        dateText(summary.startDate)?.let { "Inicio" to it },
        dateText(summary.payoffDate)?.let { "Última cuota" to it },
        dateText(projected)?.let { "Fin previsto" to it },
        schedule?.totalInterest?.let { "Intereses totales" to it.text() },
        summary.totalCost?.let { "Coste total" to it.text() },
    )
    if (rows.isEmpty()) return
    LoanSection("Condiciones", null, modifier) {
        rows.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                pair.forEach { (label, value) -> MiniFigure(label, value, null, Modifier.weight(1f)) }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
        if (projected != null) {
            Text("El fin previsto parte de la deuda actual pagando las cuotas del contrato.", style = MaterialTheme.typography.labelSmall,
                color = Relay.subtle)
        }
    }
}

@Composable private fun MiniFigure(label: String, value: String, caption: String?, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = Relay.muted, maxLines = 1)
        Text(value, style = MaterialTheme.typography.titleSmall.merge(tabular), color = Relay.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        caption?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = Relay.subtle, maxLines = 1) }
    }
}

@Composable private fun BonusesCard(bonuses: List<LoanBonus>, modifier: Modifier = Modifier) {
    val active = bonuses.filter { it.active }.sumOf { it.points.decimalOrZero() }
    LoanSection("Bonificaciones", "Rebajan ${formatRate(active.toPlainString())} el tipo", modifier) {
        bonuses.forEach { bonus ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(bonus.name, style = MaterialTheme.typography.bodyMedium, color = if (bonus.active) Relay.text else Relay.muted,
                        textDecoration = if (bonus.active) null else TextDecoration.LineThrough)
                    val caption = listOfNotNull(
                        "Inactiva".takeUnless { bonus.active },
                        bonus.annualCost?.takeIf { it.decimal.signum() > 0 }?.let { "Coste ${it.text()} al año" },
                    ).joinToString(" · ")
                    if (caption.isNotEmpty()) Text(caption, style = MaterialTheme.typography.labelMedium, color = Relay.muted)
                }
                Text("−${formatRate(bonus.points)}", style = MaterialTheme.typography.bodyMedium.merge(tabular),
                    color = if (bonus.active) Relay.income else Relay.muted)
            }
        }
    }
}

@Composable private fun RevisionsCard(revisions: List<LoanRevision>, modifier: Modifier = Modifier) {
    LoanSection("Revisiones", "Historial y próxima revisión", modifier) {
        revisions.asReversed().forEachIndexed { index, revision ->
            if (index > 0) HorizontalDivider(color = Relay.border)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(dateText(revision.effectiveOn) ?: revision.effectiveOn, style = MaterialTheme.typography.bodyMedium, color = Relay.text)
                    Text(revision.compositionText(), style = MaterialTheme.typography.labelMedium, color = Relay.muted)
                }
                Spacer(Modifier.width(10.dp))
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(formatRate(revision.rate), style = MaterialTheme.typography.titleSmall.merge(tabular), color = Relay.text)
                    StatusPill(revision)
                }
            }
        }
    }
}

@Composable private fun StatusPill(revision: LoanRevision) {
    val tone = when (revision.status) {
        "projected" -> Relay.secondary
        "pending" -> Relay.warning
        "confirmed" -> Relay.income
        else -> Relay.blue
    }
    Text(revision.statusLabel, style = MaterialTheme.typography.labelSmall, color = tone, maxLines = 1,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(tone.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 3.dp))
}

/** The amortization table: instalments still ahead first, the paid ones on request, a page at a time. */
private fun LazyListScope.scheduleSection(
    schedule: LoanSchedule,
    showPaid: Boolean,
    shown: Int,
    onShowPaid: (Boolean) -> Unit,
    onMore: () -> Unit,
) {
    val upcoming = schedule.upcoming
    val paid = schedule.paid
    val rows = if (showPaid) paid else upcoming
    val visible = rows.take(shown)
    item(key = "schedule-label") {
        SectionLabel("Cuadro de amortización", Modifier.padding(top = 26.dp, bottom = 10.dp),
            trailing = "${upcoming.size} de ${schedule.payments.size} pendientes")
    }
    item(key = "schedule-switch") {
        Column {
            ScheduleSwitch(showPaid, upcoming.size, paid.size, onShowPaid)
            Row(Modifier.padding(start = 4.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                LegendDot("Capital", principalTone)
                Spacer(Modifier.width(14.dp))
                LegendDot("Intereses", interestTone)
            }
        }
    }
    if (visible.isEmpty()) {
        item(key = "schedule-empty") {
            Text(if (showPaid) "Todavía no se ha pagado ninguna cuota." else "No quedan cuotas pendientes.",
                style = MaterialTheme.typography.bodyMedium, color = Relay.muted, modifier = Modifier.padding(12.dp))
        }
    }
    itemsIndexed(visible, key = { _, payment -> "payment-${payment.number}" }) { index, payment ->
        PaymentRow(payment, schedule.currency, next = !showPaid && index == 0, shape = rowShape(index, visible.size))
    }
    if (rows.size > visible.size) {
        item(key = "schedule-more") {
            TextButton(onClick = onMore, modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) {
                Text("Ver más cuotas (${rows.size - visible.size})", color = Relay.blue)
            }
        }
    }
}

@Composable private fun LegendDot(label: String, tone: Color) {
    Box(Modifier.size(8.dp).clip(CircleShape).background(tone))
    Spacer(Modifier.width(6.dp))
    Text(label, style = MaterialTheme.typography.labelMedium, color = Relay.muted)
}

private fun rowShape(index: Int, count: Int): Shape {
    val radius = 20.dp
    return when {
        count == 1 -> RoundedCornerShape(radius)
        index == 0 -> RoundedCornerShape(topStart = radius, topEnd = radius)
        index == count - 1 -> RoundedCornerShape(bottomStart = radius, bottomEnd = radius)
        else -> RoundedCornerShape(0.dp)
    }
}

@Composable private fun ScheduleSwitch(showPaid: Boolean, upcoming: Int, paid: Int, onShowPaid: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(bottom = 10.dp).clip(RoundedCornerShape(12.dp)).background(Relay.surface2.copy(alpha = 0.7f)).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        listOf(false to "Pendientes ($upcoming)", true to "Pagadas ($paid)").forEach { (value, label) ->
            val active = value == showPaid
            Box(
                Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(10.dp))
                    .then(if (active) Modifier.background(Relay.gradient) else Modifier)
                    .clickable(enabled = !active) { onShowPaid(value) },
                contentAlignment = Alignment.Center,
            ) { Text(label, style = MaterialTheme.typography.labelLarge, color = if (active) Color.White else Relay.muted) }
        }
    }
}

@Composable private fun PaymentRow(payment: LoanPayment, currency: String, next: Boolean, shape: Shape) {
    val prepayment = payment.prepayment.decimalOrZero()
    Column(
        Modifier.fillMaxWidth().clip(shape).background(if (next) Relay.surface2.copy(alpha = 0.9f) else Relay.surface.copy(alpha = 0.86f))
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("${payment.number}", style = MaterialTheme.typography.labelMedium.merge(tabular), color = Relay.muted,
                modifier = Modifier.width(36.dp))
            Text(dateText(payment.date) ?: payment.date, style = MaterialTheme.typography.bodyMedium, color = Relay.text, modifier = Modifier.weight(1f))
            if (next) {
                Text("Próxima", style = MaterialTheme.typography.labelSmall, color = Relay.blue,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Relay.blue.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 3.dp))
                Spacer(Modifier.width(8.dp))
            }
            Text(formatMoney(payment.payment.decimalOrZero(), currency), style = MaterialTheme.typography.bodyLarge.merge(tabular)
                .copy(fontWeight = FontWeight.Medium), color = if (payment.past) Relay.secondary else Relay.text)
        }
        Spacer(Modifier.height(4.dp))
        Row(Modifier.padding(start = 36.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(principalTone))
            Spacer(Modifier.width(4.dp))
            Text(formatMoney(payment.principal.decimalOrZero(), currency), style = MaterialTheme.typography.labelMedium.merge(tabular), color = Relay.muted)
            Spacer(Modifier.width(10.dp))
            Box(Modifier.size(6.dp).clip(CircleShape).background(interestTone))
            Spacer(Modifier.width(4.dp))
            Text(formatMoney(payment.interest.decimalOrZero(), currency), style = MaterialTheme.typography.labelMedium.merge(tabular), color = Relay.muted)
            Spacer(Modifier.weight(1f))
            Text("Pendiente ${formatMoney(payment.endingBalance.decimalOrZero(), currency)}", style = MaterialTheme.typography.labelMedium.merge(tabular),
                color = Relay.subtle, maxLines = 1)
        }
        if (prepayment.signum() > 0) {
            Text("Amortización anticipada ${formatMoney(prepayment, currency)}", style = MaterialTheme.typography.labelMedium, color = Relay.income,
                modifier = Modifier.padding(start = 36.dp, top = 2.dp))
        }
    }
}
