package com.kammcs.boardhop

import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.firebase.messaging.FlutterFirebaseTokenLiveData

/**
 * The Android half of the push channel; `ios/Runner/AppDelegate.swift` answers
 * the same channel name with the same two methods, and
 * `lib/features/notifications/push_service.dart` is the Dart side.
 *
 * Why this exists rather than `firebase_messaging`'s own API (research/06, R1
 * notes): `AndroidManifest.xml` opts this app into FCM's
 * Firebase-Installations registration, because the legacy path answers "FCM
 * Registration failed!" on current Play services (verified on the Pixel 10 Pro
 * emulator, Play services 26.33, 2026-09-13). Under that flag the SDK refuses
 * `getToken()`/`deleteToken()` and wants `register()`/`unregister()`, neither of
 * which the Flutter plugin exposes, and `register()` reports the token only
 * through `onNewToken`.
 */
class MainActivity : FlutterActivity() {
    private var pushChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kammcs.boardhop/push")
        pushChannel = channel

        // The plugin's service posts every onNewToken here, and observeForever
        // also replays the value already held — so a token minted before the
        // Dart side was listening is not lost. The plugin does forward this to
        // its own Dart stream, but that forwarding was not arriving on the
        // emulator, and the token is the one thing push cannot do without.
        FlutterFirebaseTokenLiveData.getInstance().observeForever { token ->
            // Length only: a device token never reaches a log.
            Log.i("BoardhopPush", "token observed (chars=" + (token?.length ?: 0) + ")")
            if (!token.isNullOrEmpty()) channel.invokeMethod("onToken", token)
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Returns null: the token follows on the "onToken" call above.
                "register" ->
                    FirebaseMessaging.getInstance().register()
                        .addOnSuccessListener {
                            Log.i("BoardhopPush", "register() ok")
                            result.success(null)
                        }
                        .addOnFailureListener { e ->
                            result.error("register_failed", e.message, null)
                        }
                "unregister" ->
                    FirebaseMessaging.getInstance().unregister()
                        .addOnSuccessListener { result.success(null) }
                        .addOnFailureListener { e ->
                            result.error("unregister_failed", e.message, null)
                        }
                else -> result.notImplemented()
            }
        }
    }
}
