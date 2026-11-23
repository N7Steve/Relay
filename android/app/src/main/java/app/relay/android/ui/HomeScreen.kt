package app.relay.android.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.data.Account
import app.relay.android.data.BalanceSheet
import app.relay.android.data.DiskState
import app.relay.android.data.Transaction
import app.relay.android.data.formatMoney
import java.math.BigDecimal
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun HomeScreen(
    vm: AppViewModel,
    session: DiskState,
    onAccount: (Account) -> Unit,
    onSeeAll: () -> Unit,
    onTransaction: (Transaction) -> Unit,
) {
    val summaryState by vm.summary.collectAsStateWithLifecycle()
    val recent by vm.recent.state.collectAsStateWithLifecycle()
    val worthLoading by vm.netWorthLoading.collectAsStateWithLifecycle()
    val summary = session.summary
    LaunchedEffect(Unit) { if (recent.page == 0 && !recent.loading) vm.recent.open(null) }

    PullToRefreshBox(isRefreshing = summaryState.loading && summary != null, onRefresh = vm::refreshSummary, modifier = Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 24.dp)) {
            item(key = "greeting") { Greeting(session, Modifier.statusBarsPadding().padding(top = 20.dp, bottom = 18.dp).enter(0)) }
            summaryState.error?.let { error -> item(key = "error") { ErrorBanner(error, Modifier.padding(bottom = 14.dp), vm::refreshSummary) } }
            item(key = "net-worth") {
                when {
                    summary?.balanceSheet != null -> NetWorthCard(summary.balanceSheet, Modifier.enter(1))
                    summary != null -> Panel(Modifier.fillMaxWidth()) {
                        Text(summary.balanceSheetError ?: "No se pudo calcular el patrimonio.", color = Relay.muted, style = MaterialTheme.typography.bodyMedium)
                    }
                    else -> NetWorthSkeleton()
                }
            }

            summary?.let {
                item(key = "net-worth-history") {
                    NetWorthWidget(it.netWorthHistory, session.preferences.netWorthRange, worthLoading, vm::selectNetWorthRange)
                }
                item(key = "monthly-flow") { CashFlowWidget(it.cashFlow, it.monthStartDay) }
                item(key = "spending-categories") { ExpensesWidget(it.cashFlow, it.monthStartDay) }
            }

            if (summary != null) {
                val visible = summary.accounts.filterNot { it.status == "disabled" }
                val (liabilities, assets) = visible.partition { it.isLiability }
                accountSection("Activos", assets, onAccount)
                accountSection("Pasivos", liabilities, onAccount)
                if (visible.isEmpty()) item(key = "no-accounts") {
                    EmptyState("Aún no hay cuentas", "Crea o conecta tus cuentas desde Relay en la web.")
                }
            } else {
                items(4) { Skeleton(Modifier.fillMaxWidth().padding(top = 14.dp), height = 56.dp) }
            }

            item(key = "recent-label") {
                SectionLabel("Últimos movimientos", Modifier.padding(top = 26.dp, bottom = 4.dp), action = "Ver todos" to onSeeAll)
            }
            if (recent.items.isEmpty() && recent.loading) items(3) { Skeleton(Modifier.fillMaxWidth().padding(top = 10.dp), height = 52.dp) }
            recent.error?.let { item(key = "recent-error") { ErrorBanner(it, onRetry = vm.recent::retry) } }
            items(recent.items.take(6), key = { "recent-${it.id}" }) { TransactionRow(it, { onTransaction(it) }) }
            if (recent.items.isEmpty() && recent.page > 0 && recent.error == null) item(key = "recent-empty") {
                Text("Todavía no hay movimientos.", color = Relay.muted, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(12.dp))
            }
        }
    }
}

@Composable private fun Greeting(session: DiskState, modifier: Modifier) {
    val hour = LocalTime.now().hour
    val salute = when (hour) { in 6..13 -> "Buenos días"; in 14..20 -> "Buenas tardes"; else -> "Buenas noches" }
    val name = session.user?.firstName?.takeIf { it.isNotBlank() }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", Locale.forLanguageTag("es-ES"))).replaceFirstChar { it.uppercase() },
                style = MaterialTheme.typography.labelLarge, color = Relay.muted)
            Text(if (name != null) "$salute, $name" else salute, style = MaterialTheme.typography.headlineMedium, color = Relay.text,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        RelayLogo(size = 36.dp)
    }
}

@Composable private fun NetWorthCard(sheet: BalanceSheet, modifier: Modifier = Modifier) {
    val progress = remember(sheet) { Animatable(0f) }
    LaunchedEffect(sheet) { progress.animateTo(1f, tween(900, easing = Relay.easeOut)) }
    val net = sheet.netWorth.decimal
    val shown = net.multiply(BigDecimal(progress.value.toDouble()))
    val assets = sheet.assets.decimal
    val liabilities = sheet.liabilities.decimal
    val total = assets + liabilities
    val share = if (total.signum() > 0) assets.divide(total, 4, java.math.RoundingMode.HALF_UP).toFloat() else 1f

    Box(
        modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Relay.gradient).drawBehind {
            drawCircle(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.18f), Color.Transparent),
                center = Offset(size.width * 0.95f, 0f), radius = size.width * 0.7f))
            drawCircle(Brush.radialGradient(listOf(Relay.cyan.copy(alpha = 0.25f), Color.Transparent),
                center = Offset(0f, size.height), radius = size.width * 0.6f))
        }.padding(22.dp),
    ) {
        Column {
            Text("PATRIMONIO NETO", style = eyebrow, color = Color.White.copy(alpha = 0.75f))
            Spacer(Modifier.height(8.dp))
            Text(formatMoney(shown, sheet.currency), style = MaterialTheme.typography.displaySmall.merge(tabular), color = Color.White, maxLines = 1)
            Spacer(Modifier.height(20.dp))
            Box(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.18f))) {
                Box(Modifier.fillMaxWidth(share * progress.value).height(8.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.9f)))
            }
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Figure("Activos", formatMoney(assets, sheet.currency), Color.White.copy(alpha = 0.9f))
                Figure("Pasivos", formatMoney(liabilities, sheet.currency), Color.White.copy(alpha = 0.55f), alignEnd = true)
            }
        }
    }
}

@Composable private fun Figure(label: String, value: String, dot: Color, alignEnd: Boolean = false) {
    Column(horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(RoundedCornerShape(50)).background(dot))
            Spacer(Modifier.width(6.dp))
            Text(label, style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.75f))
        }
        Text(value, style = MaterialTheme.typography.titleMedium.merge(tabular).copy(fontWeight = FontWeight.SemiBold), color = Color.White)
    }
}

@Composable private fun NetWorthSkeleton() {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Relay.gradient).padding(22.dp)) {
        Column {
            Text("PATRIMONIO NETO", style = eyebrow, color = Color.White.copy(alpha = 0.75f))
            Spacer(Modifier.height(12.dp))
            Box(Modifier.width(180.dp).height(34.dp).clip(RoundedCornerShape(10.dp)).background(Color.White.copy(alpha = 0.2f)))
            Spacer(Modifier.height(48.dp))
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.accountSection(title: String, accounts: List<Account>, onAccount: (Account) -> Unit) {
    if (accounts.isEmpty()) return
    val totals = accounts.groupBy { it.currency }.map { (currency, rows) -> formatMoney(rows.sumOf { it.balanceCents }, currency) }
    item(key = "section-$title") {
        SectionLabel(title, Modifier.padding(top = 26.dp, bottom = 10.dp), trailing = totals.joinToString(" · "))
    }
    accounts.groupBy { it.accountType }.entries.sortedBy { typeOrder(it.key) }.forEach { (type, rows) ->
        item(key = "group-$title-$type") {
            Panel(Modifier.fillMaxWidth().padding(bottom = 10.dp).enter(typeOrder(type)), padding = 6.dp) {
                Column {
                    Text(accountTypeName(type), style = MaterialTheme.typography.labelLarge, color = Relay.muted,
                        modifier = Modifier.padding(start = 10.dp, top = 8.dp, bottom = 2.dp))
                    rows.forEach { account -> AccountRow(account) { onAccount(account) } }
                }
            }
        }
    }
}

private fun typeOrder(type: String?) = listOf("depository", "investment", "crypto", "property", "vehicle", "other_asset",
    "credit_card", "loan", "other_liability").indexOf(type).let { if (it < 0) 99 else it }

@Composable fun AccountRow(account: Account, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AccountBadge(account)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(account.name, style = MaterialTheme.typography.bodyLarge, color = Relay.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            account.institutionName?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = Relay.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.width(10.dp))
        Text(formatMoney(account.balanceCents, account.currency), style = MaterialTheme.typography.bodyLarge.merge(tabular).copy(fontWeight = FontWeight.Medium),
            color = if (account.isLiability) Relay.secondary else Relay.text)
    }
}
