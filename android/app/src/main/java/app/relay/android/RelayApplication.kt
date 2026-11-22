package app.relay.android

import android.app.Application
import app.relay.android.auth.SecureStore
import app.relay.android.data.DeviceInfo
import app.relay.android.data.RelayRepository
import app.relay.android.updates.UpdateClient
import app.relay.android.updates.UpdateManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async

class RelayApplication : Application() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val repository by lazy { RelayRepository(SecureStore(this), DeviceInfo.current(BuildConfig.VERSION_NAME)) }
    val ready by lazy { scope.async { repository.initialize() } }
    val updates by lazy { UpdateManager(this, UpdateClient(repository)) }
    override fun onCreate() { super.onCreate(); ready.start() }
}
