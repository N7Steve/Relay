package app.relay.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.House
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.data.DiskState
import app.relay.android.data.Transaction

enum class Tab(val label: String, val icon: ImageVector) {
    Home("Resumen", Icons.Outlined.Dashboard),
    Movements("Movimientos", Icons.Outlined.ReceiptLong),
    Reports("Informe", Icons.Outlined.Insights),
    /** Shown only while the user has a loan account. */
    Loans("Préstamos", Icons.Outlined.House),
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
    val creator by vm.creator.collectAsStateWithLifecycle()
    val movementsFeed by vm.movements.state.collectAsStateWithLifecycle()
    val accounts = session.summary?.accounts.orEmpty()
    val canCreate = remember(accounts) { creatableAccounts(accounts).isNotEmpty() }
    val account = accountId?.let { id -> session.summary?.accounts?.find { it.id == id } }
    // The loans section appears once the cached summary lists a loan; net worth stays the server's figure.
    val hasLoans = remember(accounts) { accounts.any { it.accountType == "loan" && it.status !in setOf("disabled", "pending_deletion") } }
    val tabs = remember(hasLoans) { Tab.entries.filter { it != Tab.Loans || hasLoans } }
    LaunchedEffect(Unit) { vm.onForeground() }
    LaunchedEffect(tabs) { if (tab !in tabs) tab = Tab.Home }

    BackHandler(enabled = account != null) { accountId = null }
    BackHandler(enabled = account == null && tab != Tab.Home) { tab = Tab.Home }

    Box(Modifier.fillMaxSize()) {
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
                        key == Tab.Loans.name -> LoansScreen(vm)
                        key == Tab.Settings.name -> SettingsScreen(vm, session)
                        else -> HomeScreen(vm, session, onAccount = { accountId = it.id }, onSeeAll = { tab = Tab.Movements }, onTransaction = { detail = it })
                    }
                }
            }
            if (account == null) BottomBar(tabs, tab) { tab = it }
        }

        // New movement: from the summary, the movements list (its selected account) or a day-to-day account.
        val createFor = when {
            account != null -> account.id.takeIf { account.writable && account.accountType in setOf("depository", "credit_card") }
            tab == Tab.Movements -> movementsFeed.accountId ?: ""
            tab == Tab.Home -> ""
            else -> null
        }
        Box(Modifier.fillMaxSize().navigationBarsPadding().padding(end = 20.dp, bottom = if (account == null) 84.dp else 20.dp),
            contentAlignment = Alignment.BottomEnd) {
            AnimatedVisibility(canCreate && createFor != null && !creator.open,
                enter = fadeIn(tween(Relay.BASE)) + scaleIn(tween(Relay.BASE), 0.6f), exit = fadeOut(tween(Relay.FAST)) + scaleOut(tween(Relay.FAST), 0.6f)) {
                CreateButton { vm.startCreate(createFor?.ifEmpty { null }) }
            }
        }
    }

    detail?.let { selected ->
        TransactionSheet(selected, onEdit = { detail = null; vm.editTransaction(selected) }, onDismiss = { detail = null })
    }
    editor.transaction?.let { transaction -> TransactionEditor(transaction, editor, vm) }
    if (creator.open) TransactionCreator(creator, accounts, session.preferences.defaultAccountId, vm)
    UpdatePrompt(vm.updates)
    notice?.let { message ->
        AlertDialog(
            onDismissRequest = vm::dismissNotice, containerColor = Relay.surface,
            title = { Text("Relay") }, text = { Text(message) },
            confirmButton = { TextButton(onClick = vm::dismissNotice) { Text("Aceptar") } },
        )
    }
}

@Composable private fun CreateButton(onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    Box(
        Modifier.pressScale(source, 0.92f).shadow(10.dp, CircleShape, spotColor = Relay.violet).size(58.dp).clip(CircleShape)
            .background(Relay.gradient).clickable(source, null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Outlined.Add, "Nuevo movimiento", tint = Color.White, modifier = Modifier.size(28.dp)) }
}

@Composable private fun BottomBar(tabs: List<Tab>, selected: Tab, onSelect: (Tab) -> Unit) {
    val shape = RoundedCornerShape(24.dp)
    Row(
        Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp)
            .clip(shape).background(Relay.surface.copy(alpha = 0.94f)).border(1.dp, Relay.border, shape).padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        // A fifth destination narrows the others, so the selected one widens a little more to keep its label.
        val activeWeight = if (tabs.size > 4) 2.6f else 2.2f
        tabs.forEach { tab ->
            val active = tab == selected
            val weight by animateFloatAsState(if (active) activeWeight else 1f, tween(Relay.BASE, easing = Relay.easeOut), label = "tab")
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
                    Text(tab.label, color = Color.White, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
