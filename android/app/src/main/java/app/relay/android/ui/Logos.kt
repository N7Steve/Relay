package app.relay.android.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.produceState
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.relay.android.data.Account
import app.relay.android.data.DiskState
import app.relay.android.data.RelayApi
import app.relay.android.data.cloudflareAccess
import app.relay.android.data.serverUrl
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Request

internal val LocalLogos = staticCompositionLocalOf<LogoLoader?> { null }

/** Separate in-memory cache per session. Only signed local storage URLs need Cloudflare credentials. */
internal class LogoLoader(state: DiskState) {
    private val origin = serverUrl(state.server)
    private val localAccess = DiskState(cloudflareAccess = state.cloudflareAccess)
    private val client = RelayApi.defaultClient()
    private val cache = LruCache<String, Bitmap>(64)

    fun cached(path: String?): Bitmap? = path?.let(cache::get)

    suspend fun load(path: String): Bitmap? = withContext(Dispatchers.IO) {
        cache.get(path)?.let { return@withContext it }
        val url = if (path.startsWith("/rails/active_storage/")) origin.resolve(path) else path.toHttpUrlOrNull()
        if (url == null || !url.isHttps || url.username.isNotEmpty() || url.password.isNotEmpty()) return@withContext null
        val request = Request.Builder().url(url).header("Accept", "image/*")
        if (url.host == origin.host && url.port == origin.port && url.encodedPath.startsWith("/rails/active_storage/")) {
            request.cloudflareAccess(localAccess)
        }
        try {
            client.newCall(request.build()).execute().use { response ->
                val body = response.body ?: return@use null
                val maxBytes = 1024L * 1024
                if (!response.isSuccessful || body.source().request(maxBytes + 1)) return@use null
                val bytes = body.source().readByteArray()
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth !in 1..4096 || bounds.outHeight !in 1..4096) return@use null
                val sample = (maxOf(bounds.outWidth, bounds.outHeight) / 128).coerceAtLeast(1)
                val options = BitmapFactory.Options().apply { inSampleSize = Integer.highestOneBit(sample) }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.also { cache.put(path, it) }
            }
        } catch (_: IOException) {
            null
        }
    }
}

@Composable internal fun LogoBadge(url: String?, size: Dp, fallback: @Composable () -> Unit) {
    val loader = LocalLogos.current
    val bitmap by key(loader, url) {
        produceState(loader?.cached(url)) { value = url?.let { loader?.load(it) } }
    }
    val logo = bitmap
    if (logo == null) {
        fallback()
    } else {
        Box(
            Modifier.size(size).clip(RoundedCornerShape(12.dp)).background(Relay.text),
            contentAlignment = Alignment.Center,
        ) {
            Image(logo.asImageBitmap(), contentDescription = null,
                modifier = Modifier.size(size).padding(3.dp), contentScale = ContentScale.Fit)
        }
    }
}

@Composable internal fun AccountBadge(account: Account, size: Dp = 40.dp) {
    LogoBadge(account.logoUrl, size) { IconBadge(accountIcon(account.accountType), accountTone(account.accountType), size = size) }
}
