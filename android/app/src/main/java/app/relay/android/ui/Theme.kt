package app.relay.android.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** The web "Relay" dark palette (theme-relay.css): logo hues over indigo-tinted greys. */
object Relay {
    val bg = Color(0xFF080A1A)
    val surface = Color(0xFF161935)
    val surface2 = Color(0xFF232749)
    val surface3 = Color(0xFF343960)
    val border = Color(0xFFB0B4D4).copy(alpha = 0.14f)
    val borderStrong = Color(0xFFB0B4D4).copy(alpha = 0.24f)
    val text = Color(0xFFEFF0F8)
    val secondary = Color(0xFFB0B4D4)
    val muted = Color(0xFF8D92B8)
    val subtle = Color(0xFF6A6F98)

    val cyan = Color(0xFF3FD0F5)
    val blue = Color(0xFF4C78FF)
    val violet = Color(0xFF8A5CFF)
    val magenta = Color(0xFFC95CF0)

    val income = Color(0xFF34D399)
    val danger = Color(0xFFF87171)
    val warning = Color(0xFFFBBF24)

    /** --relay-gradient: blue to violet, darkened slightly for white text. */
    val gradient = Brush.linearGradient(listOf(Color(0xFF3E66E0), Color(0xFF7448E6)), start = Offset.Zero, end = Offset.Infinite)
    /** The logo sweep used for accents and the brand name. */
    val logoGradient = Brush.linearGradient(listOf(violet, blue, cyan), start = Offset.Zero, end = Offset.Infinite)

    val easeOut = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)
    const val FAST = 140
    const val BASE = 240
}

/** Small uppercase label for sections. */
val eyebrow = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 11.sp, letterSpacing = 0.12.em)

/** Monetary values use tabular figures so columns line up. */
val tabular = TextStyle(fontFeatureSettings = "tnum")

private val base = Typography()
private val type = Typography(
    displayLarge = base.displayLarge.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.02).em),
    displayMedium = base.displayMedium.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.02).em),
    displaySmall = base.displaySmall.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.015).em),
    headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.01).em),
    headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.01).em),
    headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
    titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
    titleMedium = base.titleMedium.copy(fontWeight = FontWeight.Medium),
    titleSmall = base.titleSmall.copy(fontWeight = FontWeight.Medium),
    bodyLarge = base.bodyLarge,
    bodyMedium = base.bodyMedium,
    bodySmall = base.bodySmall,
    labelLarge = base.labelLarge.copy(fontWeight = FontWeight.Medium),
    labelMedium = base.labelMedium,
    labelSmall = base.labelSmall,
)

@Composable fun RelayTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Relay.violet, onPrimary = Color.White,
            secondary = Relay.blue, onSecondary = Color.White,
            tertiary = Relay.cyan, onTertiary = Relay.bg,
            background = Relay.bg, onBackground = Relay.text,
            surface = Relay.surface, onSurface = Relay.text,
            surfaceContainerLowest = Relay.bg, surfaceContainerLow = Relay.surface, surfaceContainer = Relay.surface,
            surfaceContainerHigh = Relay.surface2, surfaceContainerHighest = Relay.surface2,
            surfaceVariant = Relay.surface2, onSurfaceVariant = Relay.muted,
            primaryContainer = Relay.violet.copy(alpha = 0.18f), onPrimaryContainer = Color(0xFFD9CCFF),
            secondaryContainer = Relay.blue.copy(alpha = 0.18f), onSecondaryContainer = Color(0xFFC9D6FF),
            outline = Relay.borderStrong, outlineVariant = Relay.border,
            error = Relay.danger, onError = Relay.bg,
        ),
        typography = type,
        shapes = Shapes(
            small = RoundedCornerShape(10.dp), medium = RoundedCornerShape(14.dp), large = RoundedCornerShape(20.dp),
            extraLarge = RoundedCornerShape(28.dp),
        ),
        content = content,
    )
}
