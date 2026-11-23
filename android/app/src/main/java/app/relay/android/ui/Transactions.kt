package app.relay.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.RowScope
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
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.EventNote
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Notes
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Sell
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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

/** 2026-11-23 -> 23/11/2026. */
fun numericDate(date: String): String = runCatching { LocalDate.parse(date).format(numericFormat) }.getOrDefault(date)

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
    var more by rememberSaveable(transaction.id) { mutableStateOf(false) }
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
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            TransactionBadge(transaction, 64.dp)
            Spacer(Modifier.height(12.dp))
            Text(transaction.name.ifBlank { "Sin descripción" }, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center,
                maxLines = 3, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(4.dp))
            Text(
                formatMoney(transaction.signedAmountCents, transaction.currency, signed = true),
                style = MaterialTheme.typography.displaySmall.merge(tabular),
                color = if (transaction.isIncome) Relay.income else Relay.text,
            )
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Pill(kind, kindTone)
                Pill(numericDate(transaction.date), Relay.secondary, Icons.Outlined.CalendarToday)
            }

            Spacer(Modifier.height(20.dp))
            DetailCard {
                DetailRow(Icons.Outlined.Wallet, "Cuenta") { DetailValue(transaction.account?.name ?: "—") }
                DetailDivider()
                DetailRow(Icons.Outlined.Category, "Categoría") {
                    val category = transaction.category
                    if (category != null) {
                        IconBadge(categoryIcon(category.icon), categoryTone(category.color), size = 26.dp)
                        Spacer(Modifier.width(8.dp))
                        DetailValue(category.name, Modifier.weight(1f, fill = false))
                    } else {
                        DetailValue("Sin categoría", color = Relay.muted)
                    }
                }
                DetailDivider()
                DetailRow(Icons.Outlined.Storefront, "Comercio") {
                    DetailValue(transaction.merchant?.name ?: "Sin comercio", color = if (transaction.merchant == null) Relay.muted else Relay.text)
                }
                transaction.transfer?.let { transfer ->
                    DetailDivider()
                    DetailRow(Icons.Outlined.SwapHoriz, "Transferencia") { DetailValue(transfer.otherAccount?.name ?: "Otra cuenta") }
                }
                DetailDivider()
                DetailRow(Icons.Outlined.CalendarToday, "Fecha") { DetailValue(numericDate(transaction.date)) }
            }

            Spacer(Modifier.height(12.dp))
            DetailCard {
                Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Sell, null, tint = Relay.muted, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(12.dp))
                    Text("Etiquetas", style = MaterialTheme.typography.bodyMedium, color = Relay.muted)
                }
                if (transaction.tags.isEmpty()) {
                    Text("Sin etiquetas", style = MaterialTheme.typography.bodyMedium, color = Relay.subtle, modifier = Modifier.padding(bottom = 14.dp))
                } else {
                    FlowRow(Modifier.fillMaxWidth().padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        transaction.tags.forEach { TagChip(it) }
                    }
                }
            }

            Spacer(Modifier.height(12.dp))
            DetailCard {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { more = !more }.padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Outlined.Info, null, tint = Relay.muted, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(12.dp))
                    Text("Más información", style = MaterialTheme.typography.bodyMedium, color = Relay.muted, modifier = Modifier.weight(1f))
                    Icon(if (more) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, if (more) "Ocultar" else "Mostrar", tint = Relay.muted)
                }
                AnimatedVisibility(more) {
                    Column {
                        DetailDivider()
                        Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.Notes, null, tint = Relay.muted, modifier = Modifier.size(20.dp))
                                Spacer(Modifier.width(12.dp))
                                Text("Notas", style = MaterialTheme.typography.bodyMedium, color = Relay.muted)
                            }
                            Spacer(Modifier.height(6.dp))
                            val notes = transaction.notes?.takeIf { it.isNotBlank() }
                            Text(notes ?: "Sin notas", style = MaterialTheme.typography.bodyMedium, color = if (notes == null) Relay.subtle else Relay.text)
                        }
                        DetailDivider()
                        DetailRow(Icons.Outlined.Payments, "Moneda") { DetailValue(transaction.currency) }
                        DetailDivider()
                        DetailRow(Icons.Outlined.EventNote, "Día") { DetailValue(dayLabel(transaction.date)) }
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

/** Rounded group of detail rows inside the sheet. */
@Composable private fun DetailCard(content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(Relay.surface2.copy(alpha = 0.55f)).border(1.dp, Relay.border, shape)
            .padding(horizontal = 14.dp),
        content = content,
    )
}

@Composable private fun DetailDivider() = HorizontalDivider(color = Relay.border)

@Composable private fun DetailRow(icon: ImageVector, label: String, value: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Relay.muted, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(12.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, color = Relay.muted, modifier = Modifier.width(104.dp))
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically, content = value)
    }
}

@Composable private fun DetailValue(text: String, modifier: Modifier = Modifier, color: Color = Relay.text) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = color, textAlign = TextAlign.End,
        maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = modifier)
}

@Composable private fun Pill(text: String, tone: Color, icon: ImageVector? = null) {
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(tone.copy(alpha = 0.14f)).padding(horizontal = 12.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let {
            Icon(it, null, tint = tone, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(text, style = MaterialTheme.typography.labelMedium.merge(tabular), color = tone)
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
