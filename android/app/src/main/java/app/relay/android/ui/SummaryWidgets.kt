package app.relay.android.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.relay.android.data.CashFlow
import app.relay.android.data.NetWorthHistory
import app.relay.android.data.NetWorthRange
import app.relay.android.data.reportingMonthName
import app.relay.android.data.formatMoney
import java.math.BigDecimal
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val spanish = Locale.forLanguageTag("es-ES")
private val shortDate = DateTimeFormatter.ofPattern("d MMM", spanish)
private val shortDateYear = DateTimeFormatter.ofPattern("d MMM yyyy", spanish)
private val monthYear = DateTimeFormatter.ofPattern("MMMM yyyy", spanish)

private fun NetWorthRange.description() = when (this) {
    NetWorthRange.Month -> "Últimos 30 días"
    NetWorthRange.Quarter -> "Últimos 3 meses"
    NetWorthRange.Half -> "Últimos 6 meses"
    NetWorthRange.Year -> "Último año"
    NetWorthRange.TwoYears -> "Últimos 2 años"
}

@Composable internal fun NetWorthWidget(history: NetWorthHistory?, selected: NetWorthRange, loading: Boolean, onRange: (NetWorthRange) -> Unit) {
    SummaryWidget("Evolución del patrimonio", selected.description()) {
        RangeSelector(selected, loading, onRange)
        val points = history?.points.orEmpty()
        when {
            history == null -> WidgetMessage("No se pudo cargar la evolución.")
            points.size < 2 -> WidgetMessage("Todavía no hay suficiente historial de saldos.")
            else -> {
                val first = points.first()
                val last = points.last()
                val delta = last.value.decimal - first.value.decimal
                Text(
                    formatMoney(delta, history.currency, signed = true),
                    color = when (delta.signum()) { 1 -> Relay.income; -1 -> Relay.danger; else -> Relay.text },
                    style = MaterialTheme.typography.titleLarge.merge(tabular),
                )
                WorthChart(points.map { it.value.decimal })
                val from = LocalDate.parse(first.date)
                val to = LocalDate.parse(last.date)
                val axis = if (from.year == to.year) shortDate else shortDateYear
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(from.format(axis), color = Relay.muted, style = MaterialTheme.typography.labelMedium)
                    Text(to.format(axis), color = Relay.muted, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

@Composable private fun RangeSelector(selected: NetWorthRange, loading: Boolean, onRange: (NetWorthRange) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Relay.surface2.copy(alpha = 0.7f)).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        NetWorthRange.entries.forEach { range ->
            val active = range == selected
            Box(
                Modifier.weight(1f).height(32.dp).clip(RoundedCornerShape(10.dp))
                    .then(if (active) Modifier.background(Relay.gradient) else Modifier)
                    .clickable(enabled = !active) { onRange(range) },
                contentAlignment = Alignment.Center,
            ) {
                if (active && loading) CircularProgressIndicator(Modifier.size(14.dp), color = Color.White, strokeWidth = 2.dp)
                else Text(range.label, style = MaterialTheme.typography.labelLarge, color = if (active) Color.White else Relay.muted)
            }
        }
    }
}

@Composable internal fun WorthChart(values: List<BigDecimal>) {
    val min = values.min().toDouble()
    val span = values.max().toDouble() - min
    Canvas(Modifier.fillMaxWidth().height(100.dp)) {
        val margin = 5.dp.toPx()
        val width = size.width - 2 * margin
        val height = size.height - 2 * margin
        val line = Path()
        values.forEachIndexed { index, value ->
            val x = margin + width * index / values.lastIndex
            val share = if (span > 0) ((value.toDouble() - min) / span).toFloat() else 0.5f
            val y = margin + height * (1 - share)
            if (index == 0) line.moveTo(x, y) else line.lineTo(x, y)
        }
        val fill = Path().apply {
            addPath(line)
            lineTo(size.width - margin, size.height)
            lineTo(margin, size.height)
            close()
        }
        listOf(0f, 0.5f, 1f).forEach { fraction ->
            val y = margin + height * fraction
            drawLine(Relay.border, Offset(margin, y), Offset(size.width - margin, y))
        }
        drawPath(fill, Brush.verticalGradient(listOf(Relay.cyan.copy(alpha = 0.25f), Color.Transparent)))
        drawPath(line, Relay.cyan, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round))
    }
}

@Composable internal fun CashFlowWidget(flow: CashFlow?, monthStartDay: Int) {
    SummaryWidget("Flujo de fondos", flow?.periodLabel(monthStartDay)) {
        if (flow == null) {
            WidgetMessage("No se pudo cargar el flujo del mes.")
        } else {
            val income = flow.income.toBigDecimal()
            val spending = flow.spending.toBigDecimal()
            val net = flow.netSavings.toBigDecimal()
            val max = maxOf(income.abs(), spending.abs())
            MoneyBar("Ingresos", income, max, flow.currency, Relay.income)
            MoneyBar("Gastos", spending, max, flow.currency, Relay.magenta)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Saldo del mes", modifier = Modifier.weight(1f), color = Relay.text, style = MaterialTheme.typography.titleMedium)
                Text(formatMoney(net, flow.currency, signed = true), style = MaterialTheme.typography.titleMedium.merge(tabular),
                    color = if (net.signum() < 0) Relay.danger else Relay.text)
            }
        }
    }
}

@Composable internal fun ExpensesWidget(flow: CashFlow?, monthStartDay: Int) {
    val rows = remember(flow) {
        flow?.sankey?.expenseCategories().orEmpty().mapIndexed { index, node ->
            node to (node.color?.let(::parseHex) ?: chartPalette[index % chartPalette.size])
        }
    }
    var expanded by rememberSaveable(flow?.period?.startDate ?: flow?.month) { mutableStateOf(false) }
    SummaryWidget("Gastos netos por categoría", flow?.periodLabel(monthStartDay)) {
        when {
            flow == null -> WidgetMessage("No se pudieron cargar las categorías del mes.")
            rows.isEmpty() -> WidgetMessage("Este mes todavía no hay gastos por categoría.")
            else -> {
                ShareBar(rows.map { (node, color) -> node.value.toBigDecimal() to color })
                val max = rows.first().first.value.toBigDecimal()
                (if (expanded) rows else rows.take(5)).forEach { (row, color) ->
                    MoneyBar(row.name, row.value.toBigDecimal(), max, flow.currency, color, dot = true)
                }
                if (rows.size > 5) TextButton(onClick = { expanded = !expanded }) {
                    Text(if (expanded) "Ver menos" else "Ver todas las categorías")
                }
            }
        }
    }
}

@Composable private fun SummaryWidget(title: String, subtitle: String?, content: @Composable () -> Unit) {
    Panel(Modifier.fillMaxWidth().padding(top = 12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, color = Relay.text, style = MaterialTheme.typography.titleMedium)
                subtitle?.let { Text(it, color = Relay.muted, style = MaterialTheme.typography.labelMedium) }
            }
            content()
        }
    }
}

@Composable private fun WidgetMessage(message: String) {
    Text(message, color = Relay.muted, style = MaterialTheme.typography.bodyMedium)
}

/** Each category's share of the period's spending, in its own colour. */
@Composable private fun ShareBar(parts: List<Pair<BigDecimal, Color>>) {
    val visible = parts.filter { it.first.signum() > 0 }
    if (visible.isEmpty()) return
    val total = visible.sumOf { it.first }.toDouble()
    Row(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(50)), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        visible.forEach { (value, color) ->
            Box(Modifier.weight((value.toDouble() / total).toFloat().coerceAtLeast(0.005f)).fillMaxHeight().background(color))
        }
    }
}

@Composable private fun MoneyBar(label: String, amount: BigDecimal, max: BigDecimal, currency: String, color: Color, dot: Boolean = false) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (dot) Box(Modifier.size(10.dp).clip(CircleShape).background(color))
            Text(label, Modifier.weight(1f), color = Relay.secondary, style = MaterialTheme.typography.bodyMedium,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(formatMoney(amount, currency), color = Relay.text, style = MaterialTheme.typography.bodyMedium.merge(tabular))
        }
        val fraction = if (max.signum() == 0) 0f else (amount.abs().toDouble() / max.toDouble()).toFloat().coerceIn(0f, 1f)
        Box(Modifier.fillMaxWidth().height(5.dp).clip(RoundedCornerShape(50)).background(Relay.surface3)) {
            Box(Modifier.fillMaxWidth(fraction).height(5.dp).background(color))
        }
    }
}

/** "Noviembre 2026", plus the exact dates when the family starts its months on another day. */
private fun CashFlow.periodLabel(startDay: Int): String? = runCatching {
    val range = period ?: return@runCatching month?.let { LocalDate.parse(it).format(monthYear).replaceFirstChar(Char::uppercase) }
    val start = LocalDate.parse(range.startDate)
    val end = LocalDate.parse(range.endDate)
    val name = reportingMonthName(start, startDay).format(monthYear).replaceFirstChar(Char::uppercase)
    if (start.dayOfMonth == 1) name else "$name · ${start.format(shortDate)} – ${end.format(shortDate)}"
}.getOrNull()
