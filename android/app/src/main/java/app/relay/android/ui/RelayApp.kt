package app.relay.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.material.icons.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.data.DiskState
import app.relay.android.data.Transaction

enum class Tab(val label: String, val icon: ImageVector) {
    Home("Resumen", Icons.Outlined.Dashboard),
    Movements("Movimientos", Icons.Outlined.ReceiptLong),
    Reports("Informe", Icons.Outlined.Insights),
    Settings("Ajustes", Icons.Outlined.Settings),
}

@Composable fun RelayApp(vm: AppViewModel) {
    val session by vm.session.collectAsStateWithLifecycle()
    val phase = when { session == null -> 0; session?.signedIn != true -> 1; else -> 2 }
    Box(Modifier.fillMaxSize().relayBackdrop()) {
        AnimatedContent(phase, transitionSpec = { fadeIn(tween(Relay.BASE)) togetherWith fadeOut(tween(Relay.FAST)) }, label = "phase") { current ->
            val state = session
            when {
                current == 0 || state == null -> Splash()
                current == 1 || !state.signedIn -> LoginScreen(vm, state)
                else -> {
                    val context = LocalContext.current
                    val logos = remember(state.server, state.user?.id) { LogoLoader(state, context.applicationContext, vm::logo) }
                    CompositionLocalProvider(LocalLogos provides logos) { Shell(vm, state) }
                }
            }
        }
    }
}

@Composable private fun Splash() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { RelayLogo(size = 84.dp, breathe = true) }
}

@Composable private fun Shell(vm: AppViewModel, session: DiskState) {
    var tab by rememberSaveable { mutableStateOf(Tab.Home) }
    var accountId by rememberSaveable { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<Transaction?>(null) }
    val notice by vm.notice.collectAsStateWithLifecycle()
    val editor by vm.editor.collectAsStateWithLifecycle()
    val account = accountId?.let { id -> session.summary?.accounts?.find { it.id == id } }
    LaunchedEffect(Unit) { vm.onForeground() }

    BackHandler(enabled = account != null) { accountId = null }
    BackHandler(enabled = account == null && tab != Tab.Home) { tab = Tab.Home }

    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f)) {
            AnimatedContent(
                targetState = account?.id ?: tab.name,
                transitionSpec = {
                    if (account != null && targetState == account.id) {
                        (slideInHorizontally(tween(320, easing = Relay.easeOut)) { it / 3 } + fadeIn(tween(Relay.BASE))) togetherWith fadeOut(tween(Relay.FAST))
                    } else if (initialState.length > 12) {
                        fadeIn(tween(Relay.BASE)) togetherWith (slideOutHorizontally(tween(Relay.BASE)) { it / 3 } + fadeOut(tween(Relay.FAST)))
                    } else {
                        (fadeIn(tween(Relay.BASE)) + scaleIn(tween(Relay.BASE), initialScale = 0.98f)) togetherWith fadeOut(tween(Relay.FAST))
                    }
                },
                label = "screen",
            ) { key ->
                when {
                    account != null && key == account.id -> AccountScreen(account, vm.accountMovements, onBack = { accountId = null }, onTransaction = { detail = it })
                    key == Tab.Movements.name -> MovementsScreen(vm.movements, session.summary?.accounts, session.preferences.defaultAccountId,
                        onDefault = vm::setDefaultAccount) { detail = it }
                    key == Tab.Reports.name -> ReportsScreen(vm, session) { detail = it }
                    key == Tab.Settings.name -> SettingsScreen(vm, session)
                    else -> HomeScreen(vm, session, onAccount = { accountId = it.id }, onSeeAll = { tab = Tab.Movements }, onTransaction = { detail = it })
                }
            }
        }
        if (account == null) BottomBar(tab) { tab = it }
    }

    detail?.let { selected ->
        TransactionSheet(selected, onEdit = { detail = null; vm.editTransaction(selected) }, onDismiss = { detail = null })
    }
    editor.transaction?.let { transaction -> TransactionEditor(transaction, editor, vm) }
    UpdatePrompt(vm.updates)
    notice?.let { message ->
        AlertDialog(
            onDismissRequest = vm::dismissNotice, containerColor = Relay.surface,
            title = { Text("Relay") }, text = { Text(message) },
            confirmButton = { TextButton(onClick = vm::dismissNotice) { Text("Aceptar") } },
        )
    }
}

@Composable private fun BottomBar(selected: Tab, onSelect: (Tab) -> Unit) {
    val shape = RoundedCornerShape(24.dp)
    Row(
        Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp)
            .clip(shape).background(Relay.surface.copy(alpha = 0.94f)).border(1.dp, Relay.border, shape).padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Tab.entries.forEach { tab ->
            val active = tab == selected
            val weight by animateFloatAsState(if (active) 2.2f else 1f, tween(Relay.BASE, easing = Relay.easeOut), label = "tab")
            val source = remember { MutableInteractionSource() }
            Row(
                Modifier.weight(weight).height(48.dp).clip(RoundedCornerShape(18.dp))
                    .then(if (active) Modifier.background(Relay.gradient) else Modifier)
                    .clickable(source, null) { onSelect(tab) }.pressScale(source),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(tab.icon, tab.label, tint = if (active) Color.White else Relay.muted, modifier = Modifier.size(22.dp))
                if (active) {
                    Spacer(Modifier.size(8.dp))
                    Text(tab.label, color = Color.White, style = MaterialTheme.typography.labelLarge, maxLines = 1)
                }
            }
        }
    }
}
