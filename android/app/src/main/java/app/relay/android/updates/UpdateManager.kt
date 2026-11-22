package app.relay.android.updates

import android.app.Activity
import android.content.Context
import android.os.Build
import app.relay.android.BuildConfig
import app.relay.android.data.ApiException
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class UpdateState(
    val checking: Boolean = false,
    val release: AndroidRelease? = null,
    val progress: Float? = null,
    val ready: Boolean = false,
    val prompt: Boolean = false,
    val message: String? = null,
)

/** Checks on start and every 15 minutes in the foreground; installs only after the user confirms. */
class UpdateManager(private val context: Context, private val client: UpdateClient) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutable = MutableStateFlow(UpdateState())
    val state = mutable.asStateFlow()
    private val installer = ApkInstaller(context)
    @Volatile private var account = ""
    private var checkedAt = 0L
    private var dismissedVersion = 0
    private var job: Job? = null
    private var waitingForPermission = false
    private val apk = File(context.cacheDir, "updates/relay.apk")

    /** Resets everything when the signed-in account changes. */
    fun account(key: String) {
        if (key == account) return
        job?.cancel()
        account = key; checkedAt = 0; dismissedVersion = 0; waitingForPermission = false
        mutable.value = UpdateState()
        apk.delete()
    }

    fun check(manual: Boolean = false) {
        if (account.isEmpty() || job?.isActive == true || (!manual && System.currentTimeMillis() - checkedAt < 15 * 60_000)) return
        val key = account
        mutable.value = mutable.value.copy(checking = true, message = null)
        job = scope.launch {
            try {
                val response = client.check()
                if (key != account) return@launch
                checkedAt = System.currentTimeMillis()
                val release = response.release?.takeIf { it.versionCode > BuildConfig.VERSION_CODE && it.minSdk <= Build.VERSION.SDK_INT }
                mutable.value = UpdateState(
                    release = release,
                    prompt = release != null && (manual || dismissedVersion != release.versionCode),
                    message = when {
                        !manual -> null
                        !response.enabled -> "Tu servidor todavía no incluye una versión de Relay para Android."
                        response.release != null && response.release.minSdk > Build.VERSION.SDK_INT -> "La nueva versión requiere una versión de Android más reciente."
                        release == null -> "Ya tienes la última versión de Relay (${BuildConfig.VERSION_NAME})."
                        else -> null
                    },
                )
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                mutable.value = mutable.value.copy(message = if (manual) {
                    if (error is ApiException && error.status == 404) "Actualiza primero Relay en tu servidor para habilitar las actualizaciones."
                    else "No se pudo consultar la actualización. Inténtalo de nuevo más tarde."
                } else null)
            } finally {
                if (key == account) mutable.value = mutable.value.copy(checking = false)
            }
        }
    }

    fun dismiss() {
        dismissedVersion = mutable.value.release?.versionCode ?: 0
        mutable.value = mutable.value.copy(prompt = false, message = null)
    }

    fun download() {
        if (job?.isActive == true || account.isEmpty()) return
        val release = mutable.value.release ?: return
        val key = account
        mutable.value = mutable.value.copy(progress = 0f, message = null)
        job = scope.launch {
            try {
                client.download(release, apk) { progress -> if (key == account) mutable.value = mutable.value.copy(progress = progress) }
                withContext(Dispatchers.IO) { installer.verify(apk, release) }
                ensureActive()
                if (key == account) mutable.value = mutable.value.copy(ready = true, progress = null, prompt = true)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                apk.delete()
                mutable.value = mutable.value.copy(progress = null, ready = false, message = error.message ?: "No se pudo descargar la actualización.")
            }
        }
    }

    fun install(activity: Activity) {
        val release = mutable.value.release ?: return
        if (!mutable.value.ready) return
        val key = account
        scope.launch {
            var verified = false
            try {
                withContext(Dispatchers.IO) { installer.verify(apk, release) }
                if (key != account || activity.isFinishing || activity.isDestroyed) return@launch
                verified = true
                waitingForPermission = !installer.launch(activity, apk)
            } catch (error: Exception) {
                if (!verified) apk.delete()
                mutable.value = mutable.value.copy(ready = verified, message = error.message ?: "No se pudo abrir el instalador de Android.")
            }
        }
    }

    fun resumeInstaller(activity: Activity) {
        if (!waitingForPermission) return
        waitingForPermission = false
        if (context.packageManager.canRequestPackageInstalls()) install(activity)
        else mutable.value = mutable.value.copy(message = "Android necesita que autorices a Relay a instalar su actualización. Puedes reintentarlo con Instalar.")
    }
}
