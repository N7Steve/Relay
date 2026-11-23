package app.relay.android.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.DirectionsCar
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.RequestQuote
import androidx.compose.material.icons.outlined.Savings
import androidx.compose.material.icons.outlined.ShowChart
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material.icons.outlined.TrendingDown
import androidx.compose.material.icons.outlined.TrendingUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.relay.android.R
import app.relay.android.data.MovementType
import app.relay.android.data.Transaction
import kotlinx.coroutines.delay

/** Page background: the flat base plus the web's --relay-glow (blue, violet, magenta). */
fun Modifier.relayBackdrop(strength: Float = 1f): Modifier = drawBehind {
    drawRect(Relay.bg)
    drawRect(Brush.radialGradient(listOf(Relay.blue.copy(alpha = 0.16f * strength), Color.Transparent),
        center = Offset(-size.width * 0.1f, -size.height * 0.05f), radius = size.maxDimension * 0.8f))
    drawRect(Brush.radialGradient(listOf(Relay.violet.copy(alpha = 0.12f * strength), Color.Transparent),
        center = Offset(size.width * 1.1f, 0f), radius = size.maxDimension * 0.6f))
    drawRect(Brush.radialGradient(listOf(Relay.magenta.copy(alpha = 0.07f * strength), Color.Transparent),
        center = Offset(size.width * 0.9f, size.height * 1.1f), radius = size.maxDimension * 0.6f))
}

@Composable fun RelayLogo(modifier: Modifier = Modifier, size: Dp = 40.dp, breathe: Boolean = false) {
    val scale = if (breathe) rememberInfiniteTransition("logo").animateFloat(0.96f, 1.04f,
        infiniteRepeatable(tween(2600), RepeatMode.Reverse), "pulse").value else 1f
    Image(painterResource(R.drawable.relay_logo), contentDescription = "Relay", modifier = modifier.size(size).scale(scale))
}

/** Presses sink slightly and spring back. */
@Composable fun Modifier.pressScale(source: MutableInteractionSource, pressed: Float = 0.97f): Modifier {
    val down by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (down) pressed else 1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium), label = "press")
    return scale(scale)
}

/** Fades and lifts content in, delayed by its position in a list. */
@Composable fun Modifier.enter(index: Int = 0): Modifier {
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        delay((index.coerceAtMost(10) * 40).toLong())
        progress.animateTo(1f, tween(380, easing = Relay.easeOut))
    }
    return graphicsLayer {
        alpha = progress.value
        translationY = (1f - progress.value) * 18.dp.toPx()
    }
}

@Composable fun GradientButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    busy: Boolean = false,
    content: @Composable RowScope.() -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    val alpha by animateFloatAsState(if (enabled) 1f else 0.4f, tween(Relay.BASE), label = "enabled")
    Row(
        modifier.pressScale(source).graphicsLayer { this.alpha = alpha }.clip(RoundedCornerShape(14.dp))
            .background(Relay.gradient)
            .clickable(source, indication = null, enabled = enabled && !busy, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 15.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        if (busy) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
        else content()
    }
}

/** Container surface: --color-container with the subtle border of the web cards. */
@Composable fun Panel(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, padding: Dp = 16.dp, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    val source = remember { MutableInteractionSource() }
    Box(
        modifier.then(if (onClick != null) Modifier.pressScale(source, 0.985f) else Modifier)
            .clip(shape).background(Relay.surface.copy(alpha = 0.86f)).border(1.dp, Relay.border, shape)
            .then(if (onClick != null) Modifier.clickable(source, null, onClick = onClick) else Modifier)
            .padding(padding),
    ) { content() }
}

@Composable fun SectionLabel(text: String, modifier: Modifier = Modifier, trailing: String? = null, action: Pair<String, () -> Unit>? = null) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(Relay.logoGradient))
        Spacer(Modifier.width(10.dp))
        Text(text.uppercase(), style = eyebrow, color = Relay.muted, modifier = Modifier.weight(1f), maxLines = 1)
        trailing?.let { Text(it, style = MaterialTheme.typography.labelMedium.merge(tabular), color = Relay.subtle) }
        action?.let { (label, onClick) ->
            TextButton(onClick = onClick, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp)) {
                Text(label, color = Relay.blue, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable fun ErrorBanner(message: String, modifier: Modifier = Modifier, onRetry: (() -> Unit)? = null) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier.fillMaxWidth().clip(shape).background(Relay.danger.copy(alpha = 0.10f)).border(1.dp, Relay.danger.copy(alpha = 0.3f), shape)
            .padding(start = 14.dp, end = 6.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.ErrorOutline, null, tint = Relay.danger, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Text(message, style = MaterialTheme.typography.bodyMedium, color = Relay.text, modifier = Modifier.weight(1f))
        onRetry?.let { TextButton(onClick = it) { Text("Reintentar", color = Relay.danger) } }
    }
}

/** The one avatar shape of the app: logos, initials and category icons all share it. */
fun badgeShape(size: Dp): Shape = RoundedCornerShape(size * 0.32f)

/** Rounded tinted square holding an icon, as in the web account and category avatars. */
@Composable fun IconBadge(icon: ImageVector, tint: Color, modifier: Modifier = Modifier, size: Dp = 40.dp) {
    Box(modifier.size(size).clip(badgeShape(size)).background(tint.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(size * 0.5f))
    }
}

@Composable fun InitialBadge(
    text: String,
    tint: Color,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
    shape: Shape = badgeShape(size),
) {
    Box(modifier.size(size).clip(shape).background(tint.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
        Text(text.trim().take(1).uppercase().ifEmpty { "·" }, color = tint, fontWeight = FontWeight.SemiBold, fontSize = (size.value * 0.4f).sp)
    }
}

fun accountIcon(type: String?): ImageVector = when (type) {
    "depository" -> Icons.Outlined.AccountBalance
    "credit_card" -> Icons.Outlined.CreditCard
    "investment" -> Icons.Outlined.ShowChart
    "crypto" -> Icons.Outlined.CurrencyBitcoin
    "property" -> Icons.Outlined.Home
    "vehicle" -> Icons.Outlined.DirectionsCar
    "loan" -> Icons.Outlined.RequestQuote
    "other_asset" -> Icons.Outlined.Inventory2
    "other_liability" -> Icons.Outlined.ReceiptLong
    else -> Icons.Outlined.AccountBalanceWallet
}

fun accountTone(type: String?): Color = when (type) {
    "depository" -> Relay.blue
    "credit_card" -> Relay.magenta
    "investment" -> Relay.cyan
    "crypto" -> Relay.warning
    "property", "vehicle", "other_asset" -> Relay.violet
    "loan", "other_liability" -> Relay.danger
    else -> Relay.secondary
}

fun accountTypeName(type: String?): String = when (type) {
    "depository" -> "Cuentas"
    "credit_card" -> "Tarjetas de crédito"
    "investment" -> "Inversiones"
    "crypto" -> "Criptomonedas"
    "property" -> "Inmuebles"
    "vehicle" -> "Vehículos"
    "loan" -> "Préstamos"
    "other_asset" -> "Otros activos"
    "other_liability" -> "Otras deudas"
    else -> "Otras"
}

/** Category colour from the API (#rrggbb); valuations read as gain or loss and transfers in cyan. */
fun transactionTone(transaction: Transaction): Color = when (transaction.type) {
    MovementType.Valuation -> if (transaction.isIncome) Relay.income else Relay.danger
    MovementType.Contribution, MovementType.Withdrawal -> Relay.cyan
    else -> transaction.category?.color?.let(::parseHex) ?: if (transaction.type == MovementType.Transfer) Relay.cyan else Relay.secondary
}

fun transactionIcon(transaction: Transaction): ImageVector? = when (transaction.type) {
    MovementType.Valuation -> if (transaction.isIncome) Icons.Outlined.TrendingUp else Icons.Outlined.TrendingDown
    MovementType.Contribution -> Icons.Outlined.Savings
    MovementType.Withdrawal -> Icons.Outlined.AccountBalanceWallet
    MovementType.Transfer -> Icons.Outlined.SwapHoriz
    else -> null
}

fun parseHex(value: String): Color? = runCatching {
    val hex = value.trim().removePrefix("#")
    require(hex.length == 6)
    Color(0xFF000000 or hex.toLong(16))
}.getOrNull()

@Composable fun Skeleton(modifier: Modifier = Modifier, height: Dp = 16.dp) {
    val alpha = rememberInfiniteTransition("skeleton").animateFloat(0.35f, 0.7f, infiniteRepeatable(tween(900), RepeatMode.Reverse), "alpha").value
    Box(modifier.height(height).clip(RoundedCornerShape(8.dp)).background(Relay.surface2.copy(alpha = alpha)))
}

@Composable fun EmptyState(title: String, body: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(vertical = 40.dp, horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        RelayLogo(size = 44.dp, modifier = Modifier.graphicsLayer { alpha = 0.6f })
        Spacer(Modifier.height(14.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, color = Relay.text)
        Spacer(Modifier.height(4.dp))
        Text(body, style = MaterialTheme.typography.bodyMedium, color = Relay.muted, maxLines = 3, overflow = TextOverflow.Ellipsis,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}
