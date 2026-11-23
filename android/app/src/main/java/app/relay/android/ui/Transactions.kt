package app.relay.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
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
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Info
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import app.relay.android.data.AccountRef
import app.relay.android.data.MemberRef
import app.relay.android.data.MovementType
import app.relay.android.data.NamedRef
import app.relay.android.data.TagRef
import app.relay.android.data.Transaction
import app.relay.android.data.formatMoney
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.flow.distinctUntilChanged

private val dayFormat = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", Locale.forLanguageTag("es-ES"))
private val dayYearFormat = DateTimeFormatter.ofPattern("d 'de' MMMM 'de' yyyy", Locale.forLanguageTag("es-ES"))

private val numericFormat = DateTimeFormatter.ofPattern("dd/MM/yyyy")
private val shortFormat = DateTimeFormatter.ofPattern("d MMM", Locale.forLanguageTag("es-ES"))
private val shortYearFormat = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("es-ES"))
private val longFormat = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM 'de' yyyy", Locale.forLanguageTag("es-ES"))
private val stampFormat = DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm", Locale.forLanguageTag("es-ES"))

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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(transaction.name.ifBlank { "Sin descripción" }, style = MaterialTheme.typography.bodyLarge, color = Relay.text,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (transaction.sharedExpense) SharedMark(Modifier.padding(start = 6.dp))
            }
            val type = transaction.type
            val detail = listOfNotNull(
                shortDate(transaction.date).takeIf { showDate },
                (if (type.ordinary) transaction.category?.name ?: "Sin categoría" else transaction.category?.name ?: type.label).takeIf { showCategory },
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
            color = amountTone(transaction),
        )
    }
}

/** Valuations read as a gain or a loss; other inflows in green. */
private fun amountTone(transaction: Transaction): Color = when {
    transaction.type == MovementType.Valuation -> if (transaction.isIncome) Relay.income else Relay.danger
    transaction.isIncome -> Relay.income
    else -> Relay.text
}

/** The web's "users" mark for a movement shared with a partner. */
@Composable fun SharedMark(modifier: Modifier = Modifier, size: Dp = 15.dp) {
    Icon(Icons.Outlined.Group, "Gasto compartido", tint = Relay.secondary, modifier = modifier.size(size))
}

/**
 * The merchant's logo when there is one; otherwise the category's icon in its colour, as on the web.
 * Portfolio operations and transfers show what they are, never a merchant.
 */
@Composable internal fun TransactionBadge(transaction: Transaction, size: Dp) {
    val tone = transactionTone(transaction)
    // Another member's transfer (e.g. into a shared account) shows who made it, apart from the user's own.
    transaction.counterpartyOwner?.takeIf { !transaction.type.ordinary }?.let { return MemberBadge(it, size) }
    transactionIcon(transaction)?.takeIf { !transaction.type.ordinary }?.let { return IconBadge(it, tone, size = size) }
    val merchant = transaction.merchant
    LogoBadge(merchant?.let { logoSource(it.logoUrl, "/merchants/${it.id}/logo") }, size) {
        val category = transaction.category
        IconBadge(categoryIcon(category?.icon ?: UNCATEGORIZED_ICON), if (category == null) Relay.muted else tone, size = size)
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
@Composable fun TransactionSheet(transaction: Transaction, onEdit: () -> Unit, onDismiss: () -> Unit) {
    val type = transaction.type
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Relay.surface, contentColor = Relay.text) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp).navigationBarsPadding(),
        ) {
            // Who and when, then the amount: the logo is a cue, not the headline.
            Row(verticalAlignment = Alignment.CenterVertically) {
                TransactionBadge(transaction, 44.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(transaction.name.ifBlank { "Sin descripción" }, style = MaterialTheme.typography.titleMedium,
                            maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        if (transaction.sharedExpense) SharedMark(Modifier.padding(start = 8.dp), size = 18.dp)
                    }
                    Text(longDate(transaction.date), style = MaterialTheme.typography.bodySmall, color = Relay.muted, maxLines = 1)
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    formatMoney(transaction.signedAmountCents, transaction.currency, signed = true),
                    style = MaterialTheme.typography.displaySmall.merge(tabular),
                    color = amountTone(transaction),
                    maxLines = 1, modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(12.dp))
                Pill(typeLabel(transaction), typeTone(transaction))
            }

            Spacer(Modifier.height(18.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when (type) {
                    MovementType.Valuation -> ValuationDetail(transaction)
                    MovementType.Contribution, MovementType.Withdrawal, MovementType.Transfer -> TransferDetail(transaction)
                    MovementType.Expense, MovementType.Income -> OrdinaryDetail(transaction)
                }
                MoreInfo(transaction)
            }

            if (transaction.editableFields.isNotEmpty()) {
                Spacer(Modifier.height(20.dp))
                GradientButton(onClick = onEdit, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Outlined.Edit, null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(if (transaction.editableFields == listOf("notes")) "Editar notas" else "Editar movimiento", color = Color.White)
                }
            }
        }
    }
}

private fun typeLabel(transaction: Transaction) = when (transaction.type) {
    MovementType.Valuation -> if (transaction.isIncome) "Valoración ↑" else "Valoración ↓"
    else -> transaction.type.label
}

private fun typeTone(transaction: Transaction): Color = when (transaction.type) {
    MovementType.Valuation -> if (transaction.isIncome) Relay.income else Relay.danger
    MovementType.Contribution, MovementType.Withdrawal, MovementType.Transfer -> Relay.cyan
    MovementType.Income -> Relay.income
    MovementType.Expense -> Relay.magenta
}

/** Ordinary income or spending: always the same four facts, empty ones included. */
@OptIn(ExperimentalLayoutApi::class)
@Composable private fun OrdinaryDetail(transaction: Transaction) {
    val category = transaction.category
    val merchant = transaction.merchant
    TileRow(
        { modifier -> AccountTile("Cuenta", transaction.account, modifier) },
        { modifier ->
            InfoTile("Categoría", category?.name ?: "Sin categoría", modifier, muted = category == null) {
                IconBadge(categoryIcon(category?.icon), if (category == null) Relay.muted else categoryTone(category.color), size = 24.dp)
            }
        },
    )
    TileRow(
        { modifier ->
            InfoTile("Comercio", merchant?.name ?: "Sin comercio", modifier, muted = merchant == null) {
                if (merchant == null) IconBadge(Icons.Outlined.Storefront, Relay.muted, size = 24.dp) else MerchantBadge(merchant, 24.dp)
            }
        },
        { modifier ->
            Column(modifier.tile().padding(12.dp)) {
                Text("Etiquetas", style = MaterialTheme.typography.labelMedium, color = Relay.muted)
                Spacer(Modifier.height(8.dp))
                if (transaction.tags.isEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconBadge(Icons.Outlined.Sell, Relay.muted, size = 24.dp)
                        Spacer(Modifier.width(8.dp))
                        Text("Sin etiquetas", style = MaterialTheme.typography.bodyMedium, color = Relay.muted)
                    }
                } else {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        transaction.tags.forEach { TagChip(it) }
                    }
                }
            }
        },
    )
}

/** A portfolio valuation: which account moved and in which direction; nothing to classify. */
@Composable private fun ValuationDetail(transaction: Transaction) {
    val up = transaction.isIncome
    TileRow(
        { modifier -> AccountTile("Cartera", transaction.account, modifier) },
        { modifier ->
            InfoTile("Variación", if (up) "Subida de valor" else "Bajada de valor", modifier) {
                IconBadge(transactionIcon(transaction)!!, if (up) Relay.income else Relay.danger, size = 24.dp)
            }
        },
    )
    Note("Actualiza el valor de la cartera. En los informes aparece en Valoraciones, no como ingreso ni como gasto.")
}

/** Money moving between accounts: origin and destination first, classification only for ordinary transfers. */
@OptIn(ExperimentalLayoutApi::class)
@Composable private fun TransferDetail(transaction: Transaction) {
    val other = transaction.transfer?.otherAccount
    val outflow = transaction.signedAmountCents < 0
    val from = if (outflow) transaction.account else other
    val to = if (outflow) other else transaction.account
    // Another member's account the user cannot open still says whose it is.
    val member = transaction.counterpartyOwner?.takeIf { other == null }
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), verticalAlignment = Alignment.CenterVertically) {
        if (outflow) AccountTile("Desde", from, Modifier.weight(1f).fillMaxHeight())
        else MemberAccountTile("Desde", from, member, Modifier.weight(1f).fillMaxHeight())
        Icon(Icons.AutoMirrored.Outlined.ArrowForward, null, tint = Relay.cyan, modifier = Modifier.padding(horizontal = 6.dp).size(18.dp))
        if (outflow) MemberAccountTile("Hacia", to, member, Modifier.weight(1f).fillMaxHeight())
        else AccountTile("Hacia", to, Modifier.weight(1f).fillMaxHeight())
    }
    val category = transaction.category
    if (transaction.nativeOperation == null && (category != null || "category_id" in transaction.editableFields)) {
        InfoTile("Categoría", category?.name ?: "Sin categoría", Modifier.fillMaxWidth(), muted = category == null) {
            IconBadge(categoryIcon(category?.icon), if (category == null) Relay.muted else categoryTone(category.color), size = 24.dp)
        }
    }
    if (transaction.tags.isNotEmpty()) DetailSection(Icons.Outlined.Sell, "Etiquetas") {
        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            transaction.tags.forEach { TagChip(it) }
        }
    }
    when (transaction.type) {
        MovementType.Contribution -> Note("Una aportación mueve dinero a tu inversión: no es un gasto ni cambia tu ahorro.")
        MovementType.Withdrawal -> Note("Una retirada devuelve dinero de tu inversión: no es un ingreso.")
        else -> Unit
    }
}

/** Notes and the remaining attributes, folded away until asked for. */
@Composable private fun MoreInfo(transaction: Transaction) {
    var open by rememberSaveable(transaction.id) { mutableStateOf(false) }
    val rotation by animateFloatAsState(if (open) 180f else 0f, tween(Relay.BASE, easing = Relay.easeOut), label = "more")
    val ordinary = transaction.type.ordinary
    val facts = buildList {
        add("Fecha" to numericDate(transaction.date))
        if (ordinary) add("Gasto compartido" to if (transaction.sharedExpense) "Sí, se reparte a medias" else "No")
        kindLabel(transaction.kind)?.let { add("Naturaleza" to it) }
        if (transaction.excluded) add("Informes" to "Excluido de informes y presupuestos")
        add("Origen" to sourceLabel(transaction.source))
        stamp(transaction.createdAt)?.let { add("Registrado" to it) }
    }
    Column(Modifier.fillMaxWidth().tile()) {
        Row(
            Modifier.fillMaxWidth().clickable { open = !open }.padding(horizontal = 12.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Info, null, tint = Relay.muted, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text("Más información", style = MaterialTheme.typography.labelLarge, color = Relay.secondary, modifier = Modifier.weight(1f))
            if (!transaction.notes.isNullOrBlank() && !open) {
                Icon(Icons.Outlined.Notes, "Tiene notas", tint = Relay.muted, modifier = Modifier.padding(end = 6.dp).size(16.dp))
            }
            Icon(Icons.Outlined.ExpandMore, if (open) "Ocultar" else "Mostrar", tint = Relay.muted, modifier = Modifier.rotate(rotation))
        }
        AnimatedVisibility(
            visible = open,
            enter = expandVertically(tween(Relay.BASE + 60, easing = Relay.easeOut)) + fadeIn(tween(Relay.BASE)),
            exit = shrinkVertically(tween(Relay.BASE, easing = Relay.easeOut)) + fadeOut(tween(Relay.FAST)),
        ) {
            Column(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Column {
                    Text("Notas", style = MaterialTheme.typography.labelMedium, color = Relay.muted)
                    Text(transaction.notes?.takeIf { it.isNotBlank() } ?: "Sin notas", style = MaterialTheme.typography.bodyMedium,
                        color = if (transaction.notes.isNullOrBlank()) Relay.muted else Relay.text)
                }
                facts.forEach { (label, value) ->
                    Row(verticalAlignment = Alignment.Top) {
                        Text(label, style = MaterialTheme.typography.labelMedium, color = Relay.muted, modifier = Modifier.width(128.dp))
                        Text(value, style = MaterialTheme.typography.bodyMedium, color = Relay.text, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

private fun kindLabel(kind: String?): String? = when (kind) {
    "funds_movement" -> "Movimiento entre cuentas"
    "cc_payment" -> "Pago de tarjeta"
    "loan_payment" -> "Pago de préstamo"
    "investment_contribution" -> "Aportación a inversión"
    "transfer_to_excluded" -> "Salida fuera de tus finanzas"
    "transfer_from_excluded" -> "Entrada desde fuera de tus finanzas"
    "investment_value_adjustment" -> "Ajuste de valor de cartera"
    else -> null
}

private fun sourceLabel(source: String?): String = when (source) {
    null, "", "manual", "web" -> "Manual"
    "relay-android" -> "App Android"
    "api" -> "API"
    "enable_banking" -> "Banco (Enable Banking)"
    "csv", "import" -> "Importación"
    else -> source.replace('_', ' ').replaceFirstChar { it.uppercase() }
}

private fun stamp(value: String?): String? = value?.let {
    runCatching { OffsetDateTime.parse(it).atZoneSameInstant(ZoneId.systemDefault()).format(stampFormat) }.getOrNull()
}

@Composable private fun TileRow(vararg tiles: @Composable (Modifier) -> Unit) {
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        tiles.forEach { tile -> tile(Modifier.weight(1f).fillMaxHeight()) }
    }
}

@Composable private fun AccountTile(label: String, account: AccountRef?, modifier: Modifier) {
    InfoTile(label, account?.name ?: "Otra cuenta", modifier, muted = account == null) {
        IconBadge(accountIcon(account?.accountType), accountTone(account?.accountType), size = 24.dp)
    }
}

@Composable private fun MemberAccountTile(label: String, account: AccountRef?, member: MemberRef?, modifier: Modifier) {
    if (member == null) return AccountTile(label, account, modifier)
    InfoTile(label, "Cuenta de ${member.name}", modifier) { MemberBadge(member, 24.dp) }
}

@Composable private fun Note(text: String) {
    Row(Modifier.fillMaxWidth().clip(tileShape).background(Relay.cyan.copy(alpha = 0.08f)).padding(12.dp), verticalAlignment = Alignment.Top) {
        Icon(Icons.Outlined.Info, null, tint = Relay.cyan, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = Relay.secondary)
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

/** A member's profile picture, or their initials in a stable tone while there is none. */
@Composable internal fun MemberBadge(member: MemberRef, size: Dp) {
    val source = member.avatarKey?.let { LogoSource("member:${member.id}:$it", "/users/${member.id}/avatar") }
    LogoBadge(source, size) {
        InitialBadge(member.initials?.takeIf { it.isNotBlank() }?.take(1) ?: member.name, chartPalette[Math.floorMod(member.id.hashCode(), chartPalette.size)],
            size = size)
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
