package com.kammcs.boardhop

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.firebase.messaging.FlutterFirebaseTokenLiveData
import org.json.JSONObject
import java.util.concurrent.Executors

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
 *
 * R2.6 adds two more methods:
 *
 * * **`launchPointer`** — a notification `PushNotifier` posted carries the
 *   pointer as JSON in its launch intent, because it is the app's own
 *   notification and not one FCM drew, so `getInitialMessage()` knows nothing
 *   about it. Dart asks for it once at startup; while the app is running the
 *   same intent arrives through `onNewIntent` and is pushed straight over as
 *   `onOpened`, which is the entry `PushCoordinator` already routes from.
 * * **`debugEnrich`** — debug builds only: runs the enrichment path against a
 *   pointer map handed over from the Diagnostics page, so the fetch and the
 *   notification shape can be checked against real artifacts without waiting
 *   for a real event.
 */
class MainActivity : FlutterActivity() {
    private var pushChannel: MethodChannel? = null
    private var pendingPointer: Map<String, String>? = null
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kammcs.boardhop/push")
        pushChannel = channel

        pendingPointer = pointerFrom(intent)

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
                // The pointer of the notification that started the app, once.
                "launchPointer" -> {
                    val pointer = pendingPointer
                    pendingPointer = null
                    result.success(pointer)
                }
                // Pointers the messaging service posted while Dart was not
                // running (R2.6 gap): the feed rows and the notified marks.
                "drainPushed" -> result.success(PushedQueue.drain(applicationContext))
                "debugEnrich" -> debugEnrich(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val pointer = pointerFrom(intent) ?: return
        val channel = pushChannel
        if (channel == null) {
            pendingPointer = pointer
            return
        }
        channel.invokeMethod("onOpened", pointer)
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    /** The pointer `PushNotifier` put on its content intent, if this is one. */
    private fun pointerFrom(intent: Intent?): Map<String, String>? {
        val raw = intent?.getStringExtra(PushNotifier.EXTRA_POINTER) ?: return null
        return try {
            val json = JSONObject(raw)
            buildMap {
                for (key in json.keys()) {
                    val value = json.optString(key, "")
                    if (value.isNotEmpty()) put(key, value)
                }
            }.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Debug builds only (`FLAG_DEBUGGABLE`, so no `BuildConfig` is needed):
     * runs the R2.6 enrichment against the pointer map in [arguments] and
     * posts the result, answering `enriched`, `fallback` or `skipped`.
     */
    private fun debugEnrich(arguments: Any?, result: MethodChannel.Result) {
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
            result.error("debug_only", "debugEnrich is a debug build hook", null)
            return
        }
        val map = arguments as? Map<*, *>
        if (map == null) {
            result.error("bad_arguments", "debugEnrich wants the pointer data map", null)
            return
        }
        val data = buildMap<String, String> {
            for ((key, value) in map) {
                if (key is String && value is String && value.isNotEmpty()) put(key, value)
            }
        }
        val pointer = PointerData(data)
        if (!pointer.isPointer) {
            result.error("bad_pointer", "org, artifactType and artifactId are required", null)
            return
        }
        val context = applicationContext
        worker.execute {
            val outcome = try {
                BoardhopMessagingService.handle(context, pointer)
            } catch (e: Exception) {
                "failed: ${e.javaClass.simpleName}"
            }
            runOnUiThread { result.success(outcome) }
        }
    }
}
