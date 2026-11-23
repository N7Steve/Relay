package app.relay.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.data.Account
import app.relay.android.data.Transaction
import app.relay.android.data.formatMoney

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MovementsScreen(
    feed: Feed,
    accounts: List<Account>?,
    defaultAccountId: String?,
    onDefault: (String?) -> Unit,
    onTransaction: (Transaction) -> Unit,
) {
    val state by feed.state.collectAsStateWithLifecycle()
    val list = rememberLazyListState()
    // Day-to-day accounts only; investments and other assets open from Resumen.
    val cash = remember(accounts) { accounts?.filter { it.accountType == "depository" && it.status != "disabled" } }
    LaunchedEffect(cash) {
        val fresh = state.page == 0 && !state.loading && state.error == null
        val requested = if (fresh) defaultAccountId else state.accountId
        feed.open(requested?.takeUnless { id -> cash != null && cash.none { it.id == id } })
    }
    LaunchedEffect(state.accountId, state.query) { list.scrollToItem(0) }
    LoadMoreEffect(list, feed)

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.statusBarsPadding().padding(start = 20.dp, end = 20.dp, top = 20.dp)) {
            Text("Movimientos", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.enter(0))
            Spacer(Modifier.height(14.dp))
            AccountSelect(cash.orEmpty(), state.accountId, defaultAccountId, feed::open, onDefault)
            Spacer(Modifier.height(8.dp))
            SearchField(state.query, feed::search, Modifier.enter(1))
        }
        PullToRefreshBox(isRefreshing = state.refreshing, onRefresh = feed::refresh, modifier = Modifier.fillMaxSize()) {
            LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 24.dp)) {
                transactionGroups(state.items, showAccount = state.accountId == null, onClick = onTransaction)
                feedFooter(state, feed::retry,
                    if (state.query.isBlank()) "Sin movimientos" else "Sin resultados",
                    if (state.query.isBlank()) "Cuando importes o sincronices movimientos aparecerán aquí." else "Prueba con otro texto.")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun AccountSelect(
    accounts: List<Account>,
    selectedId: String?,
    defaultId: String?,
    onSelect: (String?) -> Unit,
    onDefault: (String?) -> Unit,
) {
    val selected = accounts.find { it.id == selectedId }
    var expanded by remember { mutableStateOf(false) }
    val validDefault = defaultId?.takeIf { id -> accounts.any { it.id == id } }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selected?.name ?: "Todas las cuentas", onValueChange = {}, readOnly = true, singleLine = true,
            label = { Text(if (selectedId == validDefault) "Cuenta · predeterminada" else "Cuenta") },
            leadingIcon = selected?.let { account -> { AccountBadge(account, 30.dp) } },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = Relay.surface2) {
            accounts.forEach { account ->
                DropdownMenuItem(
                    text = { AccountOptionLabel(account.name, account.id == validDefault) },
                    leadingIcon = { AccountBadge(account, 30.dp) },
                    trailingIcon = { AccountOptionActions(account.id == selectedId, account.id == validDefault) { onDefault(account.id) } },
                    onClick = { onSelect(account.id); expanded = false },
                )
            }
            if (accounts.isNotEmpty()) HorizontalDivider(color = Relay.border)
            DropdownMenuItem(
                text = { AccountOptionLabel("Todas las cuentas", validDefault == null) },
                trailingIcon = { AccountOptionActions(selectedId == null, validDefault == null) { onDefault(null) } },
                onClick = { onSelect(null); expanded = false },
            )
            Text("Las inversiones y otros activos se abren desde Resumen.", style = MaterialTheme.typography.labelSmall,
                color = Relay.subtle, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        }
    }
}

@Composable private fun AccountOptionLabel(name: String, isDefault: Boolean) {
    Column {
        Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (isDefault) Text("Predeterminada", style = MaterialTheme.typography.labelSmall, color = Relay.warning)
    }
}

/** Check for the current choice plus a star that makes the row the default. */
@Composable private fun AccountOptionActions(selected: Boolean, isDefault: Boolean, onDefault: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (selected) Icon(Icons.Outlined.Check, "Seleccionada", tint = Relay.text)
        IconButton(onClick = onDefault, enabled = !isDefault) {
            Icon(if (isDefault) Icons.Filled.Star else Icons.Outlined.StarBorder,
                if (isDefault) "Cuenta predeterminada" else "Usar como predeterminada",
                tint = if (isDefault) Relay.warning else Relay.muted)
        }
    }
}

@Composable fun SearchField(query: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    TextField(
        value = query, onValueChange = onChange, singleLine = true,
        modifier = modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
        placeholder = { Text("Buscar por nombre o notas", color = Relay.subtle) },
        leadingIcon = { Icon(Icons.Outlined.Search, null, tint = Relay.muted) },
        trailingIcon = { if (query.isNotEmpty()) IconButton(onClick = { onChange("") }) { Icon(Icons.Outlined.Close, "Borrar búsqueda", tint = Relay.muted) } },
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Relay.surface, unfocusedContainerColor = Relay.surface,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, cursorColor = Relay.violet,
        ),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun AccountScreen(account: Account, feed: Feed, onBack: () -> Unit, onTransaction: (Transaction) -> Unit) {
    val state by feed.state.collectAsStateWithLifecycle()
    val list = rememberLazyListState()
    LaunchedEffect(account.id) { feed.open(account.id) }
    LoadMoreEffect(list, feed)
    val tone = accountTone(account.accountType)

    PullToRefreshBox(isRefreshing = state.refreshing, onRefresh = feed::refresh, modifier = Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 24.dp)) {
            item(key = "header") {
                Column(Modifier.statusBarsPadding().padding(top = 8.dp)) {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "Volver", tint = Relay.text) }
                    Panel(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp).enter(0), padding = 20.dp) {
                        Column {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                AccountBadge(account, size = 48.dp)
                                Spacer(Modifier.width(14.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(account.name, style = MaterialTheme.typography.titleLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    Text(listOfNotNull(accountTypeName(account.accountType), account.institutionName?.takeIf { it.isNotBlank() }).joinToString(" · "),
                                        style = MaterialTheme.typography.bodyMedium, color = Relay.muted)
                                }
                            }
                            Spacer(Modifier.height(18.dp))
                            Text(if (account.isLiability) "SALDO PENDIENTE" else "SALDO", style = eyebrow, color = Relay.muted)
                            Text(formatMoney(account.balanceCents, account.currency),
                                style = MaterialTheme.typography.displaySmall.merge(tabular).copy(fontWeight = FontWeight.SemiBold),
                                color = Relay.text)
                            Spacer(Modifier.height(4.dp))
                            Row(Modifier.clip(RoundedCornerShape(50)).background(tone.copy(alpha = 0.14f)).padding(horizontal = 10.dp, vertical = 4.dp),
                                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(account.currency, style = MaterialTheme.typography.labelMedium, color = tone)
                                if (state.totalCount > 0) Text("· ${state.totalCount} movimientos", style = MaterialTheme.typography.labelMedium, color = tone)
                            }
                        }
                    }
                }
            }
            transactionGroups(state.items, showAccount = false, onClick = onTransaction)
            feedFooter(state, feed::retry, "Sin movimientos", "Esta cuenta todavía no tiene movimientos.")
        }
    }
}
