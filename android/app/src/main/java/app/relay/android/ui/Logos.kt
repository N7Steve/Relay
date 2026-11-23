package app.relay.android.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.produceState
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.relay.android.data.Account
import app.relay.android.data.ApiException
import app.relay.android.data.DiskState
import app.relay.android.data.RelayApi
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Request

internal val LocalLogos = staticCompositionLocalOf<LogoLoader?> { null }

/** Where a logo comes from: a public HTTPS URL, or a stored image read through the API. */
internal data class LogoSource(val key: String, val apiPath: String?)

/** Logos stored in Relay (custom bank and merchant images) are only served to a web session. */
internal fun logoSource(url: String?, apiPath: String): LogoSource? = when {
    url.isNullOrBlank() -> null
    url.startsWith("/rails/active_storage/") -> LogoSource(url, apiPath)
    else -> LogoSource(url, null)
}

/**
 * Per-session logo cache: memory plus app-private disk files, so images survive restarts.
 * The cache key embeds Relay's signed blob path, which changes when a logo is replaced.
 */
internal class LogoLoader(state: DiskState, context: Context, private val download: suspend (String) -> ByteArray?) {
    private val root = File(context.cacheDir, DIRECTORY)
    private val folder = File(root, digest("${state.server}|${state.user?.id}").take(16))
    private val client = RelayApi.defaultClient()
    private val memory = LruCache<String, Bitmap>(96)
    private val missing = ConcurrentHashMap.newKeySet<String>()
    private val pruned = AtomicBoolean(false)

    fun cached(source: LogoSource?): Bitmap? = source?.let { memory.get(it.key) }

    suspend fun load(source: LogoSource): Bitmap? = withContext(Dispatchers.IO) {
        memory.get(source.key)?.let { return@withContext it }
        if (source.key in missing) return@withContext null
        if (pruned.compareAndSet(false, true)) prune()
        val file = File(folder, digest(source.key))
        val stored = runCatching { file.takeIf(File::isFile)?.readBytes() }.getOrNull()
        stored?.let(::decode)?.let { memory.put(source.key, it); return@withContext it }
        val bytes = try {
            if (source.apiPath != null) download(source.apiPath) else fetch(source.key)
        } catch (error: CancellationException) {
            throw error
        } catch (_: ApiException) {
            null
        } catch (_: IOException) {
            return@withContext null // Offline: try again on the next composition.
        }
        val bitmap = bytes?.let(::decode)
        if (bitmap == null) {
            missing += source.key
            return@withContext null
        }
        runCatching { folder.mkdirs(); file.writeBytes(bytes) }
        memory.put(source.key, bitmap)
        bitmap
    }

    private fun fetch(path: String): ByteArray? {
        val url = path.toHttpUrlOrNull()
        if (url == null || !url.isHttps || url.username.isNotEmpty() || url.password.isNotEmpty()) return null
        return client.newCall(Request.Builder().url(url).header("Accept", "image/*").build()).execute().use { response ->
            val body = response.body ?: return@use null
            if (!response.isSuccessful || body.source().request(MAX_BYTES + 1)) null else body.source().readByteArray()
        }
    }

    private fun decode(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth !in 1..4096 || bounds.outHeight !in 1..4096) return null
        val sample = (minOf(bounds.outWidth, bounds.outHeight) / 128).coerceAtLeast(1)
        val options = BitmapFactory.Options().apply { inSampleSize = Integer.highestOneBit(sample) }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    /** Drops other sessions' folders and keeps this one bounded. */
    private fun prune() = runCatching {
        root.listFiles()?.filter { it != folder }?.forEach { it.deleteRecursively() }
        val files = folder.listFiles()?.sortedByDescending { it.lastModified() } ?: return@runCatching
        files.drop(MAX_FILES).forEach { it.delete() }
    }

    companion object {
        private const val DIRECTORY = "logos"
        private const val MAX_BYTES = 1024L * 1024
        private const val MAX_FILES = 400

        fun clear(context: Context) { runCatching { File(context.cacheDir, DIRECTORY).deleteRecursively() } }

        private fun digest(text: String): String =
            MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}

/** A logo filling its shape edge to edge; [fallback] shows while it loads or when there is none. */
@Composable internal fun LogoBadge(source: LogoSource?, size: Dp, shape: Shape = CircleShape, fallback: @Composable () -> Unit) {
    val loader = LocalLogos.current
    val bitmap by key(loader, source) {
        produceState(loader?.cached(source)) { value = source?.let { loader?.load(it) } }
    }
    val logo = bitmap
    if (logo == null) {
        fallback()
    } else {
        Image(logo.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop,
            modifier = Modifier.size(size).clip(shape).background(Relay.text))
    }
}

@Composable internal fun AccountBadge(account: Account, size: Dp = 40.dp) {
    LogoBadge(logoSource(account.logoUrl, "/accounts/${account.id}/logo"), size, RoundedCornerShape(size * 0.32f)) {
        IconBadge(accountIcon(account.accountType), accountTone(account.accountType), size = size)
    }
}
