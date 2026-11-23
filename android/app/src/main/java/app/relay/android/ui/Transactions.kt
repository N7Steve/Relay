package app.relay.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Notes
import androidx.compose.material.icons.outlined.Sell
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import app.relay.android.data.NamedRef
import app.relay.android.data.TagRef
import app.relay.android.data.Transaction
import app.relay.android.data.formatMoney
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.flow.distinctUntilChanged

private val dayFormat = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", Locale.forLanguageTag("es-ES"))
private val dayYearFormat = DateTimeFormatter.ofPattern("d 'de' MMMM 'de' yyyy", Locale.forLanguageTag("es-ES"))

private val numericFormat = DateTimeFormatter.ofPattern("dd/MM/yyyy")
private val shortFormat = DateTimeFormatter.ofPattern("d MMM", Locale.forLanguageTag("es-ES"))
private val shortYearFormat = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("es-ES"))
private val longFormat = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM 'de' yyyy", Locale.forLanguageTag("es-ES"))

/** 2026-11-23 -> 23/11/2026. */
fun numericDate(date: String): String = runCatching { LocalDate.parse(date).format(numericFormat) }.getOrDefault(date)

/** 2026-11-23 -> "23 nov"; other years keep the year. */
fun shortDate(date: String, today: LocalDate = LocalDate.now()): String {
    val day = runCatching { LocalDate.parse(date) }.getOrNull() ?: return date
    return day.format(if (day.year == today.year) shortFormat else shortYearFormat).replace(".", "")
}

/** The full date once, with "Hoy"/"Ayer" in front when it applies. */
fun longDate(date: String, today: LocalDate = LocalDate.now()): String {
    val day = runCatching { LocalDate.parse(date) }.getOrNull() ?: return date
    val full = day.format(longFormat).replaceFirstChar { it.uppercase() }
    return when (day) {
        today -> "Hoy · $full"
        today.minusDays(1) -> "Ayer · $full"
        else -> full
    }
}

fun dayLabel(date: String, today: LocalDate = LocalDate.now()): String {
    val day = runCatching { LocalDate.parse(date) }.getOrNull() ?: return date
    return when {
        day == today -> "Hoy"
        day == today.minusDays(1) -> "Ayer"
        day.year == today.year -> day.format(dayFormat).replaceFirstChar { it.uppercase() }
        else -> day.format(dayYearFormat)
    }
}

/**
 * One movement in a list. Lists without day headers pass [showDate]; a list already filtered
 * to one category hides that category through [showCategory].
 */
@Composable fun TransactionRow(
    transaction: Transaction,
    onClick: () -> Unit,
    showAccount: Boolean = true,
    showCategory: Boolean = true,
    showDate: Boolean = false,
) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TransactionBadge(transaction, 40.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(transaction.name.ifBlank { "Sin descripción" }, style = MaterialTheme.typography.bodyLarge, color = Relay.text,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            val detail = listOfNotNull(
                shortDate(transaction.date).takeIf { showDate },
                (transaction.category?.name ?: if (transaction.transfer != null) "Transferencia" else "Sin categoría").takeIf { showCategory },
                transaction.account?.name?.takeIf { showAccount },
            ).joinToString(" · ")
            if (detail.isNotEmpty()) {
                Text(detail, style = MaterialTheme.typography.bodySmall, color = Relay.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.width(12.dp))
        Text(
            formatMoney(transaction.signedAmountCents, transaction.currency, signed = true),
            style = MaterialTheme.typography.bodyLarge.merge(tabular).copy(fontWeight = FontWeight.Medium),
            color = if (transaction.isIncome) Relay.income else Relay.text,
        )
    }
}

@Composable internal fun TransactionBadge(transaction: Transaction, size: Dp) {
    val tone = transactionTone(transaction)
    val merchant = transaction.merchant
    LogoBadge(merchant?.let { logoSource(it.logoUrl, "/merchants/${it.id}/logo") }, size) {
        val icon = transactionIcon(transaction)
        when {
            merchant != null -> InitialBadge(merchant.name, tone, size = size)
            icon != null -> IconBadge(icon, tone, size = size)
            transaction.category != null -> IconBadge(categoryIcon(transaction.category.icon), tone, size = size)
            else -> InitialBadge(transaction.name, tone, size = size)
        }
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

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable fun TransactionSheet(transaction: Transaction, onEdit: () -> Unit, onDismiss: () -> Unit) {
    val kind = when {
        transaction.transfer != null -> "Transferencia"
        transaction.isIncome -> "Ingreso"
        else -> "Gasto"
    }
    val kindTone = when {
        transaction.transfer != null -> Relay.cyan
        transaction.isIncome -> Relay.income
        else -> Relay.magenta
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Relay.surface, contentColor = Relay.text) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp).navigationBarsPadding(),
        ) {
            // Who and when, then the amount: the logo is a cue, not the headline.
            Row(verticalAlignment = Alignment.CenterVertically) {
                TransactionBadge(transaction, 44.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(transaction.name.ifBlank { "Sin descripción" }, style = MaterialTheme.typography.titleMedium,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(longDate(transaction.date), style = MaterialTheme.typography.bodySmall, color = Relay.muted, maxLines = 1)
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    formatMoney(transaction.signedAmountCents, transaction.currency, signed = true),
                    style = MaterialTheme.typography.displaySmall.merge(tabular),
                    color = if (transaction.isIncome) Relay.income else Relay.text,
                    maxLines = 1, modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(12.dp))
                Pill(kind, kindTone)
            }

            Spacer(Modifier.height(18.dp))
            val account = transaction.account
            val category = transaction.category
            val merchant = transaction.merchant
            val tiles = buildList<@Composable (Modifier) -> Unit> {
                add { modifier ->
                    InfoTile("Cuenta", account?.name ?: "—", modifier) {
                        IconBadge(accountIcon(account?.accountType), accountTone(account?.accountType), size = 24.dp)
                    }
                }
                add { modifier ->
                    InfoTile("Categoría", category?.name ?: "Sin categoría", modifier, muted = category == null) {
                        IconBadge(categoryIcon(category?.icon), if (category == null) Relay.muted else categoryTone(category.color), size = 24.dp)
                    }
                }
                add { modifier ->
                    InfoTile("Comercio", merchant?.name ?: "Sin comercio", modifier, muted = merchant == null) {
                        if (merchant == null) IconBadge(Icons.Outlined.Storefront, Relay.muted, size = 24.dp)
                        else MerchantBadge(merchant, 24.dp)
                    }
                }
                transaction.transfer?.let { transfer ->
                    add { modifier ->
                        InfoTile("Otra cuenta", transfer.otherAccount?.name ?: "Otra cuenta", modifier) {
                            IconBadge(Icons.Outlined.SwapHoriz, Relay.cyan, size = 24.dp)
                        }
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                tiles.chunked(2).forEach { pair ->
                    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        pair.forEach { tile -> tile(Modifier.weight(1f).fillMaxHeight()) }
                    }
                }
                if (transaction.tags.isNotEmpty()) DetailSection(Icons.Outlined.Sell, "Etiquetas") {
                    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        transaction.tags.forEach { TagChip(it) }
                    }
                }
                transaction.notes?.takeIf { it.isNotBlank() }?.let { notes ->
                    DetailSection(Icons.Outlined.Notes, "Notas") {
                        Text(notes, style = MaterialTheme.typography.bodyMedium, color = Relay.text)
                    }
                }
            }

            if (transaction.editableFields.isNotEmpty()) {
                Spacer(Modifier.height(20.dp))
                GradientButton(onClick = onEdit, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Outlined.Edit, null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Editar movimiento", color = Color.White)
                }
            }
        }
    }
}

private val tileShape = RoundedCornerShape(16.dp)

private fun Modifier.tile() = clip(tileShape).background(Relay.surface2.copy(alpha = 0.55f)).border(1.dp, Relay.border, tileShape)

/** A labelled fact of the movement, sized to sit two per row. */
@Composable private fun InfoTile(label: String, value: String, modifier: Modifier, muted: Boolean = false, leading: @Composable () -> Unit) {
    Column(modifier.tile().padding(12.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = Relay.muted)
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            leading()
            Spacer(Modifier.width(8.dp))
            Text(value, style = MaterialTheme.typography.bodyMedium, color = if (muted) Relay.muted else Relay.text,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable private fun DetailSection(icon: ImageVector, label: String, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().tile().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = Relay.muted, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(label, style = MaterialTheme.typography.labelMedium, color = Relay.muted)
        }
        Spacer(Modifier.height(8.dp))
        content()
    }
}

@Composable private fun Pill(text: String, tone: Color) {
    Text(text, style = MaterialTheme.typography.labelMedium, color = tone, maxLines = 1,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(tone.copy(alpha = 0.14f)).padding(horizontal = 12.dp, vertical = 5.dp))
}

/** A merchant's logo, or its initial in a stable tone while there is none. */
@Composable internal fun MerchantBadge(merchant: NamedRef, size: Dp) {
    LogoBadge(logoSource(merchant.logoUrl, "/merchants/${merchant.id}/logo"), size) {
        InitialBadge(merchant.name, chartPalette[Math.floorMod(merchant.name.lowercase().hashCode(), chartPalette.size)], size = size)
    }
}

/** Tag in its Relay colour; shared by the detail and the editor. */
@Composable fun TagChip(tag: TagRef, modifier: Modifier = Modifier) {
    val color = categoryTone(tag.color)
    Row(
        modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.16f)).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(6.dp))
        Text(tag.name, style = MaterialTheme.typography.labelMedium, color = Relay.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
