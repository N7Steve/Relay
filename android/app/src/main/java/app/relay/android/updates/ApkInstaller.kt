package app.relay.android.updates

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import androidx.core.net.toUri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

class ApkInstaller(private val context: Context) {
    @Suppress("DEPRECATION")
    fun verify(file: File, release: AndroidRelease) {
        release.validate()
        check(file.isFile && file.length() == release.size) { "La actualización ya no está disponible. Descárgala de nuevo." }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { source ->
            val buffer = ByteArray(32 * 1024)
            while (true) { val n = source.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        check(digest.digest().hex() == release.sha256) { "La APK no supera la verificación de integridad." }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val manager = context.packageManager
        val archive = requireNotNull(manager.getPackageArchiveInfo(file.absolutePath, flags)) { "No se pudo verificar la APK." }
        val installed = manager.getPackageInfo(context.packageName, flags)
        val archiveVersion = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val installedVersion = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        check(archive.packageName == context.packageName && archiveVersion == release.versionCode.toLong() && archiveVersion > installedVersion &&
            archive.applicationInfo!!.minSdkVersion <= Build.VERSION.SDK_INT) { "La APK no es una actualización compatible de Relay." }
        fun signers(info: PackageInfo): Set<String> =
            (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures).orEmpty()
                .map { MessageDigest.getInstance("SHA-256").digest(it.toByteArray()).hex() }.toSet()
        val current = signers(installed)
        check(current.isNotEmpty() && signers(archive) == current) {
            "La actualización está firmada con otra clave. No puede sustituir esta instalación de Relay."
        }
    }

    /** Returns false only when the user must first authorize this installation source. */
    fun launch(activity: Activity, file: File): Boolean {
        if (!context.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, "package:${context.packageName}".toUri()))
            return false
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        return true
    }
}
