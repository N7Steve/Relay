package app.relay.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.Notes
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material.icons.outlined.Wallet
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.relay.android.data.Transaction
import app.relay.android.data.formatMoney
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.flow.distinctUntilChanged

private val dayFormat = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", Locale.forLanguageTag("es-ES"))
private val dayYearFormat = DateTimeFormatter.ofPattern("d 'de' MMMM 'de' yyyy", Locale.forLanguageTag("es-ES"))

fun dayLabel(date: String, today: LocalDate = LocalDate.now()): String {
    val day = runCatching { LocalDate.parse(date) }.getOrNull() ?: return date
    return when {
        day == today -> "Hoy"
        day == today.minusDays(1) -> "Ayer"
        day.year == today.year -> day.format(dayFormat).replaceFirstChar { it.uppercase() }
        else -> day.format(dayYearFormat)
    }
}

@Composable fun TransactionRow(transaction: Transaction, onClick: () -> Unit, showAccount: Boolean = true) {
    val tone = transactionTone(transaction)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val icon = transactionIcon(transaction)
        if (icon != null) IconBadge(icon, tone, size = 40.dp)
        else InitialBadge(transaction.category?.name ?: transaction.merchant?.name ?: transaction.name, tone)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(transaction.name.ifBlank { "Sin descripción" }, style = MaterialTheme.typography.bodyLarge, color = Relay.text,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            val detail = listOfNotNull(
                transaction.category?.name ?: if (transaction.transfer != null) "Transferencia" else "Sin categoría",
                transaction.account?.name?.takeIf { showAccount },
            ).joinToString(" · ")
            Text(detail, style = MaterialTheme.typography.bodySmall, color = Relay.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.width(12.dp))
        Text(
            formatMoney(transaction.signedAmountCents, transaction.currency, signed = true),
            style = MaterialTheme.typography.bodyLarge.merge(tabular).copy(fontWeight = FontWeight.Medium),
            color = if (transaction.isIncome) Relay.income else Relay.text,
        )
    }
}

/** Day headers plus rows; shared by Movimientos and the account detail. */
fun LazyListScope.transactionGroups(items: List<Transaction>, showAccount: Boolean, onClick: (Transaction) -> Unit) {
    items.groupBy { it.date }.forEach { (date, rows) ->
        item(key = "day-$date") {
            Text(dayLabel(date), style = eyebrow, color = Relay.muted,
                modifier = Modifier.fillMaxWidth().padding(start = 12.dp, top = 18.dp, bottom = 4.dp))
        }
        items(rows, key = { it.id }) { TransactionRow(it, { onClick(it) }, showAccount) }
    }
}

fun LazyListScope.feedFooter(state: FeedState, onRetry: () -> Unit, emptyTitle: String, emptyBody: String) {
    item(key = "footer") {
        when {
            state.error != null -> ErrorBanner(state.error, Modifier.padding(vertical = 12.dp), onRetry)
            state.loading && !state.refreshing -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.size(26.dp), color = Relay.violet, strokeWidth = 2.5.dp)
            }
            state.items.isEmpty() && state.page > 0 -> EmptyState(emptyTitle, emptyBody)
            state.items.isNotEmpty() && state.page >= state.totalPages -> Text(
                "${state.totalCount} movimientos", style = MaterialTheme.typography.labelMedium, color = Relay.subtle,
                modifier = Modifier.fillMaxWidth().padding(24.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}

/** Requests the next page when the list nears its end. */
@Composable fun LoadMoreEffect(listState: LazyListState, feed: Feed) {
    LaunchedEffect(listState, feed) {
        snapshotFlow {
            val info = listState.layoutInfo
            (info.visibleItemsInfo.lastOrNull()?.index ?: 0) >= info.totalItemsCount - 6
        }.distinctUntilChanged().collect { nearEnd -> if (nearEnd) feed.loadMore() }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun TransactionSheet(transaction: Transaction, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Relay.surface, contentColor = Relay.text) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp).navigationBarsPadding()) {
            val tone = transactionTone(transaction)
            Row(verticalAlignment = Alignment.CenterVertically) {
                val icon = transactionIcon(transaction)
                if (icon != null) IconBadge(icon, tone, size = 48.dp)
                else InitialBadge(transaction.category?.name ?: transaction.name, tone, size = 48.dp)
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(transaction.name.ifBlank { "Sin descripción" }, style = MaterialTheme.typography.titleLarge)
                    Text(dayLabel(transaction.date), style = MaterialTheme.typography.bodyMedium, color = Relay.muted)
                }
            }
            Spacer(Modifier.height(20.dp))
            Text(
                formatMoney(transaction.signedAmountCents, transaction.currency, signed = true),
                style = MaterialTheme.typography.displaySmall.merge(tabular),
                color = if (transaction.isIncome) Relay.income else Relay.text,
            )
            Spacer(Modifier.height(20.dp))
            HorizontalDivider(color = Relay.border)
            Detail(Icons.Outlined.Wallet, "Cuenta", transaction.account?.name)
            Detail(Icons.Outlined.Category, "Categoría", transaction.category?.name ?: "Sin categoría")
            Detail(Icons.Outlined.Storefront, "Comercio", transaction.merchant?.name)
            transaction.transfer?.let { Detail(Icons.Outlined.SwapHoriz, "Transferencia con", it.otherAccount?.name ?: "Otra cuenta") }
            Detail(Icons.Outlined.CalendarToday, "Fecha", transaction.date)
            if (transaction.tags.isNotEmpty()) {
                Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    transaction.tags.take(4).forEach { tag ->
                        val color = tag.color?.let(::parseHex) ?: Relay.secondary
                        Text(tag.name, style = MaterialTheme.typography.labelMedium, color = color,
                            modifier = Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.14f)).padding(horizontal = 10.dp, vertical = 4.dp))
                    }
                }
            }
            transaction.notes?.takeIf { it.isNotBlank() }?.let { Detail(Icons.Outlined.Notes, "Notas", it) }
        }
    }
}

@Composable private fun Detail(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String?) {
    if (value.isNullOrBlank()) return
    Row(Modifier.fillMaxWidth().padding(top = 14.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = Relay.muted, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(14.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, color = Relay.muted, modifier = Modifier.width(120.dp))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = Relay.text, modifier = Modifier.weight(1f))
    }
}
