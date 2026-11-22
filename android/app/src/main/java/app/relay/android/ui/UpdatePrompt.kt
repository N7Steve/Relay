package app.relay.android.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.updates.UpdateManager

@Composable fun UpdatePrompt(manager: UpdateManager) {
    val state by manager.state.collectAsStateWithLifecycle()
    val activity = LocalContext.current.activity()
    val release = state.release
    if (!state.prompt && state.message == null) return
    AlertDialog(
        onDismissRequest = { if (state.progress == null) manager.dismiss() },
        containerColor = Relay.surface,
        title = { Text(if (release != null) "Relay ${release.versionName}" else "Actualizaciones de Relay") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(state.message ?: if (state.ready) "La actualización está verificada. Android te pedirá confirmar la instalación; tu sesión se conservará."
                    else "Hay una nueva versión de Relay. Puedes descargarla e instalarla conservando tu sesión.")
                state.progress?.let { progress ->
                    LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth(), color = Relay.violet, trackColor = Relay.surface2)
                    Text("Descargando · ${(progress * 100).toInt()} %")
                }
                if (release != null && !state.ready && state.progress == null) Text("%.1f MB".format(release.size / 1048576.0), color = Relay.muted)
            }
        },
        confirmButton = {
            if (release != null) TextButton(
                onClick = { if (state.ready && activity != null) manager.install(activity) else manager.download() },
                enabled = state.progress == null,
            ) { Text(if (state.ready) "Instalar" else "Descargar") }
            else TextButton(onClick = manager::dismiss) { Text("Aceptar") }
        },
        dismissButton = { if (release != null) TextButton(onClick = manager::dismiss, enabled = state.progress == null) { Text("Más tarde") } },
    )
}

private fun Context.activity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.activity()
    else -> null
}
