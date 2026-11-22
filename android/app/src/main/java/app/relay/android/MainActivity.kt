package app.relay.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import app.relay.android.ui.AppViewModel
import app.relay.android.ui.RelayApp
import app.relay.android.ui.RelayTheme

class MainActivity : ComponentActivity() {
    private val viewModel: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        setContent { RelayTheme { RelayApp(viewModel) } }
    }

    override fun onResume() {
        super.onResume()
        viewModel.onForeground()
        (application as RelayApplication).updates.resumeInstaller(this)
    }
}
