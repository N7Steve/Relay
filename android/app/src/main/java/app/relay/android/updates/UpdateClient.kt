package app.relay.android.updates

import app.relay.android.data.RelayApi
import app.relay.android.data.RelayRepository
import app.relay.android.data.cloudflareAccess
import app.relay.android.data.serverUrl
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import okhttp3.OkHttpClient
import okhttp3.Request

const val APPLICATION_ID = "app.relay.android"

@Serializable data class AndroidRelease(
    @SerialName("version_code") val versionCode: Int,
    @SerialName("version_name") val versionName: String,
    @SerialName("application_id") val applicationId: String,
    @SerialName("min_sdk") val minSdk: Int,
    val size: Long,
    val sha256: String,
    val commit: String,
) {
    fun validate() {
        require(versionCode in 1..2_100_000_000 && versionName.length in 1..64 && applicationId == APPLICATION_ID &&
            minSdk in 26..100 && size in 1..157_286_400 && sha256.matches(Regex("[a-f0-9]{64}")) &&
            commit.matches(Regex("[a-f0-9]{40}"))) { "El servidor entregó una actualización no válida." }
    }
}

@Serializable data class UpdateResponse(val enabled: Boolean, val release: AndroidRelease? = null)

/** The APK is bundled with the server image and only served to a signed-in device. */
class UpdateClient(
    private val repository: RelayRepository,
    private val api: RelayApi = RelayApi(),
    private val client: OkHttpClient = RelayApi.defaultClient(),
) {
    suspend fun check(): UpdateResponse {
        val result = api.json.decodeFromString<UpdateResponse>(repository.authorized("/android/updates/latest"))
        result.release?.validate()
        return result
    }

    suspend fun download(release: AndroidRelease, destination: File, progress: (Float) -> Unit) = withContext(Dispatchers.IO) {
        release.validate()
        val state = repository.fresh()
        val url = serverUrl(state.server).newBuilder().encodedPath("/api/v1/android/updates/${release.versionCode}/apk").build()
        val request = Request.Builder().url(url)
            .header("Accept", "application/vnd.android.package-archive")
            .header("Authorization", "Bearer ${state.tokens!!.accessToken}")
            .cloudflareAccess(state).build()
        val downloading = destination.resolveSibling(destination.name + ".${java.util.UUID.randomUUID()}.part")
        destination.parentFile?.mkdirs()
        destination.delete()
        try {
            client.newBuilder().callTimeout(5, TimeUnit.MINUTES).build().newCall(request).execute().use { response ->
                check(response.isSuccessful) {
                    if (response.code == 401) "La sesión ha caducado. Vuelve a entrar y reintenta la descarga."
                    else "No se pudo descargar la actualización (HTTP ${response.code})."
                }
                val body = requireNotNull(response.body) { "La descarga llegó vacía." }
                val digest = MessageDigest.getInstance("SHA-256")
                var count = 0L
                body.byteStream().use { source ->
                    downloading.outputStream().use { output ->
                        val buffer = ByteArray(32 * 1024)
                        while (true) {
                            coroutineContext.ensureActive()
                            val length = source.read(buffer)
                            if (length < 0) break
                            count += length
                            check(count <= release.size) { "La descarga supera el tamaño anunciado." }
                            digest.update(buffer, 0, length)
                            output.write(buffer, 0, length)
                            progress(count.toFloat() / release.size)
                        }
                    }
                }
                check(count == release.size && digest.digest().hex() == release.sha256) {
                    "La descarga está incompleta o no supera la verificación de integridad. Vuelve a descargarla."
                }
                coroutineContext.ensureActive()
                check(downloading.renameTo(destination)) { "No se pudo guardar la actualización verificada." }
            }
        } finally {
            downloading.delete()
        }
    }
}

internal fun ByteArray.hex() = joinToString("") { "%02x".format(it.toInt() and 255) }
