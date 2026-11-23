package app.relay.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.CloudDone
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.SystemUpdate
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.BuildConfig
import app.relay.android.data.DiskState

@Composable fun SettingsScreen(vm: AppViewModel, session: DiskState) {
    val updates by vm.updates.state.collectAsStateWithLifecycle()
    val signingOut by vm.busySigningOut.collectAsStateWithLifecycle()
    var confirmForget by remember { mutableStateOf(false) }
    val user = session.user

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Ajustes", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.enter(0))

        Panel(Modifier.fillMaxWidth().enter(1), padding = 20.dp) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                InitialBadge(user?.displayName ?: "?", Relay.violet, size = 52.dp)
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(user?.displayName.orEmpty(), style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(user?.email.orEmpty(), style = MaterialTheme.typography.bodyMedium, color = Relay.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }

        SectionLabel("Conexión", Modifier.padding(top = 8.dp))
        Panel(Modifier.fillMaxWidth().enter(2)) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Line(Icons.Outlined.Dns, "Servidor", session.server.trimEnd('/'))
                Line(Icons.Outlined.Shield, "Cloudflare Access",
                    if (session.cloudflareAccess != null) "Service Token configurado" else "Sin Service Token",
                    tint = if (session.cloudflareAccess != null) Relay.cyan else Relay.muted)
                session.summary?.let {
                    val minutes = ((System.currentTimeMillis() - it.fetchedAt) / 60_000).coerceAtLeast(0)
                    Line(Icons.Outlined.CloudDone, "Última sincronización", if (minutes < 1) "Hace un momento" else "Hace $minutes min")
                }
            }
        }

        SectionLabel("Aplicación", Modifier.padding(top = 8.dp))
        Panel(Modifier.fillMaxWidth().enter(3)) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Line(Icons.Outlined.Info, "Versión", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
                OutlinedButton(onClick = vm::checkUpdates, enabled = !updates.checking && updates.progress == null, modifier = Modifier.fillMaxWidth()) {
                    if (updates.checking) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Relay.violet)
                    else Icon(Icons.Outlined.SystemUpdate, null, tint = Relay.violet)
                    Spacer(Modifier.width(10.dp))
                    Text("Buscar actualizaciones", color = Relay.text)
                }
            }
        }

        SectionLabel("Sesión", Modifier.padding(top = 8.dp))
        Panel(Modifier.fillMaxWidth().enter(4)) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(onClick = vm::signOut, enabled = !signingOut, modifier = Modifier.fillMaxWidth()) {
                    if (signingOut) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Relay.text)
                    else Icon(Icons.AutoMirrored.Outlined.Logout, null, tint = Relay.text)
                    Spacer(Modifier.width(10.dp))
                    Text("Cerrar sesión", color = Relay.text)
                }
                TextButton(onClick = { confirmForget = true }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Outlined.DeleteOutline, null, tint = Relay.danger)
                    Spacer(Modifier.width(10.dp))
                    Text("Olvidar en este móvil", color = Relay.danger)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
    }

    if (confirmForget) AlertDialog(
        onDismissRequest = { confirmForget = false },
        title = { Text("¿Olvidar la sesión?") },
        text = { Text("Se borrarán la sesión, las credenciales guardadas y los datos locales de este móvil sin avisar al servidor. Para revocarla, usa Cerrar sesión o revisa los dispositivos en Relay web.") },
        confirmButton = { TextButton(onClick = { confirmForget = false; vm.forget() }) { Text("Olvidar", color = Relay.danger) } },
        dismissButton = { TextButton(onClick = { confirmForget = false }) { Text("Cancelar") } },
        containerColor = Relay.surface,
    )
}

@Composable private fun Line(icon: ImageVector, label: String, value: String, tint: Color = Relay.muted) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = Relay.muted)
            Text(value, style = MaterialTheme.typography.bodyMedium, color = Relay.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}
