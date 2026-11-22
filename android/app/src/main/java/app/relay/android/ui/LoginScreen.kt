package app.relay.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.relay.android.data.DiskState

@Composable fun LoginScreen(vm: AppViewModel, session: DiskState) {
    val state by vm.login.collectAsStateWithLifecycle()
    var server by rememberSaveable { mutableStateOf(session.server.trimEnd('/')) }
    var email by rememberSaveable { mutableStateOf(session.user?.email.orEmpty()) }
    var password by rememberSaveable { mutableStateOf("") }
    var otp by rememberSaveable { mutableStateOf("") }
    var showPassword by rememberSaveable { mutableStateOf(false) }
    var clientId by rememberSaveable { mutableStateOf(session.cloudflareAccess?.clientId.orEmpty()) }
    var clientSecret by rememberSaveable { mutableStateOf(session.cloudflareAccess?.clientSecret.orEmpty()) }
    var accessOpen by rememberSaveable { mutableStateOf(session.cloudflareAccess != null) }
    val submit = { vm.signIn(server, email, password, otp, clientId, clientSecret) }
    val ready = server.isNotBlank() && email.isNotBlank() && password.isNotEmpty() && (!state.mfaRequired || otp.length >= 6)

    Box(Modifier.fillMaxSize().relayBackdrop(1.4f).systemBarsPadding().imePadding(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 460.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            RelayLogo(size = 76.dp, breathe = true, modifier = Modifier.enter(0))
            Spacer(Modifier.height(20.dp))
            Text("Relay", modifier = Modifier.enter(1), style = MaterialTheme.typography.displaySmall.copy(brush = Relay.logoGradient))
            Spacer(Modifier.height(6.dp))
            Text("Tus finanzas, en tu propio servidor", modifier = Modifier.enter(2), color = Relay.muted,
                style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
            Spacer(Modifier.height(32.dp))

            Panel(Modifier.fillMaxWidth().enter(3), padding = 20.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Field(server, { server = it; if (it.trimEnd('/') != session.server.trimEnd('/')) { clientId = ""; clientSecret = "" } },
                        "Servidor", "https://relay.tudominio.com", KeyboardType.Uri)
                    Field(email, { email = it }, "Email", "tu@email.com", KeyboardType.Email)
                    Field(password, { password = it }, "Contraseña", null, KeyboardType.Password,
                        hidden = !showPassword, imeAction = if (state.mfaRequired) ImeAction.Next else ImeAction.Done,
                        onDone = { if (ready) submit() },
                        trailing = {
                            IconButton(onClick = { showPassword = !showPassword }) {
                                Icon(if (showPassword) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                                    if (showPassword) "Ocultar contraseña" else "Mostrar contraseña", tint = Relay.muted)
                            }
                        })
                    AnimatedVisibility(state.mfaRequired, enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically()) {
                        Field(otp, { otp = it.filter(Char::isDigit).take(8) }, "Código de verificación", "123456", KeyboardType.NumberPassword,
                            onDone = { if (ready) submit() })
                    }

                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Shield, null, tint = if (clientId.isNotBlank()) Relay.cyan else Relay.muted, modifier = Modifier.size(18.dp))
                        TextButton(onClick = { accessOpen = !accessOpen }, modifier = Modifier.weight(1f)) {
                            Text("Cloudflare Access", color = Relay.secondary, modifier = Modifier.weight(1f))
                            Icon(if (accessOpen) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null, tint = Relay.muted)
                        }
                    }
                    AnimatedVisibility(accessOpen, enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically()) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("Solo si tu servidor está protegido con Cloudflare Access: usa un Service Token con política Service Auth.",
                                style = MaterialTheme.typography.bodySmall, color = Relay.muted)
                            Field(clientId, { clientId = it.trim() }, "Client ID", null, KeyboardType.Ascii)
                            Field(clientSecret, { clientSecret = it.trim() }, "Client Secret", null, KeyboardType.Password, hidden = true)
                        }
                    }

                    state.error?.let { ErrorBanner(it) }
                    GradientButton(onClick = submit, enabled = ready, busy = state.busy, modifier = Modifier.fillMaxWidth()) {
                        Text(if (state.mfaRequired) "Verificar y entrar" else "Entrar", color = Color.White,
                            style = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 16.sp))
                    }
                }
            }
            Spacer(Modifier.height(20.dp))
            Text("La sesión y las credenciales se guardan cifradas en este dispositivo.", modifier = Modifier.enter(5),
                style = MaterialTheme.typography.bodySmall, color = Relay.subtle, textAlign = TextAlign.Center)
        }
    }
}

@Composable private fun Field(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    placeholder: String?,
    keyboard: KeyboardType,
    hidden: Boolean = false,
    imeAction: ImeAction = ImeAction.Next,
    onDone: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    OutlinedTextField(
        value = value, onValueChange = onChange, singleLine = true, modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        placeholder = placeholder?.let { { Text(it, color = Relay.subtle) } },
        visualTransformation = if (hidden) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard, imeAction = if (onDone != null && imeAction == ImeAction.Next) ImeAction.Done else imeAction, autoCorrectEnabled = false),
        keyboardActions = KeyboardActions(onDone = { onDone?.invoke() }),
        trailingIcon = trailing,
        shape = MaterialTheme.shapes.medium,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Relay.violet, unfocusedBorderColor = Relay.borderStrong,
            focusedLabelColor = Relay.violet, unfocusedLabelColor = Relay.muted, cursorColor = Relay.violet,
            focusedContainerColor = Relay.bg.copy(alpha = 0.4f), unfocusedContainerColor = Relay.bg.copy(alpha = 0.4f),
        ),
    )
}
