package com.naokisawai.assetchecker

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth の BiometricPrompt は FragmentActivity を必要とするため、
// FlutterActivity ではなく FlutterFragmentActivity を継承する。
class MainActivity : FlutterFragmentActivity() {

    private companion object {
        const val CHANNEL = "jp.privacyasset/screen_guard"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        applyGuard(call.arguments as? Boolean ?: true)
                        // Android はスクリーンショット防止まで対応できる。
                        result.success(true)
                    }
                    // Android では FLAG_SECURE / setRecentsScreenshotEnabled が
                    // タスク切り替え時の遮蔽も兼ねるので、個別の設定は不要。
                    "setObscureOnSwitch" -> result.success(true)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * FLAG_SECURE はスクリーンショットと「最近のタスク」のプレビューを同時に封じる。
     * ユーザーがスクリーンショットを許可した場合でも、タスク切り替え時の遮蔽だけは
     * 残したいので、API 33 以降では setRecentsScreenshotEnabled(false) を併用する。
     */
    private fun applyGuard(blockScreenshot: Boolean) {
        runOnUiThread {
            if (blockScreenshot) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                setRecentsScreenshotEnabled(false)
            }
        }
    }
}
