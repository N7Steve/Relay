package app.relay.android.data

import java.io.IOException
import java.time.Duration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

open class ApiException(val status: Int, message: String, val mfaRequired: Boolean = false) : IOException(message)
class SessionExpiredException : ApiException(401, "La sesión ha caducado. Vuelve a entrar.")

/** Accepts only a bare HTTPS origin such as https://relay.example.com. */
fun serverUrl(input: String): HttpUrl {
    val trimmed = input.trim().let { if (it.contains("://")) it else "https://$it" }
    val url = runCatching { trimmed.toHttpUrl() }.getOrElse { throw IllegalArgumentException("La dirección del servidor no es válida.") }
    require(url.isHttps) { "El servidor debe utilizar HTTPS con un certificado válido." }
    require(url.username.isEmpty() && url.password.isEmpty() && url.query == null && url.fragment == null) {
        "Escribe solo la dirección del servidor, sin credenciales ni parámetros."
    }
    require(url.encodedPath == "/") { "Escribe la dirección base de Relay, sin /api ni otras rutas." }
    return url
}

/**
 * HTTPS transport for the Relay API. Never follows redirects (a Cloudflare Access
 * login page must not receive credentials) and never retries writes on its own.
 */
class RelayApi(private val client: OkHttpClient = defaultClient()) {
    val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    suspend fun request(
        state: DiskState,
        path: String,
        method: String = "GET",
        body: JsonObject? = null,
        query: List<Pair<String, String>> = emptyList(),
        bearer: String? = null,
    ): String = withContext(Dispatchers.IO) {
        val url = serverUrl(state.server).newBuilder().encodedPath("/api/v1$path").apply {
            query.forEach { (key, value) -> addQueryParameter(key, value) }
        }.build()
        val request = Request.Builder().url(url).header("Accept", "application/json").cloudflareAccess(state)
        bearer?.let { request.header("Authorization", "Bearer $it") }
        val payload = body?.toString()?.toRequestBody("application/json".toMediaType())
        request.method(method, payload ?: if (method == "GET") null else "{}".toRequestBody("application/json".toMediaType()))
        client.newCall(request.build()).execute().use { response ->
            val text = response.body?.string().orEmpty()
            if (!response.isSuccessful) throw failure(response, text, path)
            text
        }
    }

    private fun failure(response: Response, text: String, path: String): ApiException {
        if (response.isRedirect) {
            val location = response.header("Location").orEmpty()
            return ApiException(response.code, if ("cloudflareaccess.com" in location || "cdn-cgi/access" in location)
                "Cloudflare Access ha pedido iniciar sesión. Revisa el Client ID y el Client Secret del Service Token."
            else "El servidor ha intentado redirigir la petición. Revisa la dirección de Relay.")
        }
        val error = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull()
        if (error == null && response.header("cf-ray") != null && response.code in listOf(401, 403)) {
            return ApiException(response.code, "Cloudflare ha bloqueado la petición. Revisa el Service Token de Cloudflare Access.")
        }
        val serverMessage = error?.get("message")?.jsonPrimitive?.contentOrNull ?: error?.get("error")?.jsonPrimitive?.contentOrNull
        val mfa = error?.get("mfa_required")?.jsonPrimitive?.booleanOrNull == true
        val message = when (response.code) {
            401 -> when {
                path != "/auth/login" -> "La sesión ha caducado. Vuelve a entrar."
                mfa -> "Introduce el código de verificación de tu aplicación de autenticación."
                serverMessage?.contains("deactivated") == true -> "Esta cuenta está desactivada. Contacta con un administrador."
                else -> "Email o contraseña incorrectos."
            }
            403 -> "El servidor ha rechazado la operación por falta de permisos."
            404 -> "El servidor no ofrece esta función. Actualiza Relay en tu servidor."
            429 -> "Demasiadas peticiones. Espera un momento y vuelve a intentarlo."
            422 -> serverMessage ?: "El servidor no pudo procesar la petición."
            in 500..599 -> "El servidor no pudo completar la operación (HTTP ${response.code})."
            else -> serverMessage ?: "Respuesta inesperada del servidor (HTTP ${response.code})."
        }
        return ApiException(response.code, message, mfaRequired = mfa)
    }

    companion object {
        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(Duration.ofSeconds(15)).readTimeout(Duration.ofSeconds(30))
            .callTimeout(Duration.ofSeconds(45))
            .retryOnConnectionFailure(false).followRedirects(false).followSslRedirects(false).build()
    }
}

fun fields(vararg values: Pair<String, JsonElement>): JsonObject = JsonObject(mapOf(*values))
fun value(text: String): JsonPrimitive = JsonPrimitive(text)

/** Applied only to requests built from this state's HTTPS server; redirects stay disabled. */
internal fun Request.Builder.cloudflareAccess(state: DiskState): Request.Builder = apply {
    state.cloudflareAccess?.let {
        header("CF-Access-Client-Id", it.clientId)
        header("CF-Access-Client-Secret", it.clientSecret)
    }
}
