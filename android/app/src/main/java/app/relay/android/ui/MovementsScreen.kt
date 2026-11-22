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
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
@Composable fun MovementsScreen(feed: Feed, onTransaction: (Transaction) -> Unit) {
    val state by feed.state.collectAsStateWithLifecycle()
    val list = rememberLazyListState()
    LaunchedEffect(Unit) { feed.open(null) }
    LoadMoreEffect(list, feed)

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.statusBarsPadding().padding(start = 20.dp, end = 20.dp, top = 20.dp)) {
            Text("Movimientos", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.enter(0))
            Spacer(Modifier.height(14.dp))
            SearchField(state.query, feed::search, Modifier.enter(1))
        }
        PullToRefreshBox(isRefreshing = state.refreshing, onRefresh = feed::refresh, modifier = Modifier.fillMaxSize()) {
            LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 24.dp)) {
                transactionGroups(state.items, showAccount = true, onClick = onTransaction)
                feedFooter(state, feed::retry,
                    if (state.query.isBlank()) "Sin movimientos" else "Sin resultados",
                    if (state.query.isBlank()) "Cuando importes o sincronices movimientos aparecerán aquí." else "Prueba con otro texto.")
            }
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
                                IconBadge(accountIcon(account.accountType), tone, size = 48.dp)
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
