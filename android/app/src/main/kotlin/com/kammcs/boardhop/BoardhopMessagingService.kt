package com.kammcs.boardhop

import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import io.flutter.plugins.firebase.messaging.FlutterFirebaseTokenLiveData

/**
 * Stands in for `firebase_messaging`'s own messaging service (which the
 * manifest removes) and adds two things: `onRegistered`, and **Android
 * enrichment** (R2.6, research/14 §4.1).
 *
 * ### onRegistered
 *
 * The app is opted into FCM's Firebase-Installations registration
 * (`firebase_messaging_installation_id_enabled`, see `AndroidManifest.xml` and
 * research/06 R1). Under that flag the SDK stops sending
 * `com.google.firebase.messaging.NEW_TOKEN` and sends
 * `…FCM_REGISTERED` / `…FCM_UNREGISTERED` instead, which
 * `FirebaseMessagingService` dispatches to `onRegistered` / `onUnregistered`.
 * The plugin only overrides `onNewToken`, so without this the token is minted,
 * logged by the SDK as "Invoking onNewToken", delivered to the service — and
 * then dropped, and Dart never learns it. Verified on the Pixel 10 Pro
 * emulator, 2026-09-13.
 *
 * ### Who posts what (the division R2.6 draws)
 *
 * `firebase_messaging` does **not** deliver messages through this service: its
 * `FlutterFirebaseMessagingReceiver` listens for the same
 * `com.google.android.c2dm.intent.RECEIVE` broadcast the SDK does, and from
 * there sends a foreground message to Dart's `onMessage` and a background one
 * to the Dart background isolate. Both that receiver and this service see
 * every message. So the division is by owner, not by suppressing `super`:
 *
 * * **Foreground** (`isApplicationForeground`, the same test the plugin's
 *   receiver makes, reproduced below): this service does nothing.
 *   `PushCoordinator` posts, refreshes the page it is on and writes the feed
 *   row, exactly as in R2.4.
 * * **Background or terminated, and the message is a pointer:** this service
 *   owns it. It fetches the artifact with the user's own token inside an 8 s
 *   budget and posts the enriched notification, or the relay's fallback line
 *   when anything at all goes wrong. `boardhopBackgroundMessage` in
 *   `lib/features/notifications/push_background.dart` skips Android pointers
 *   for exactly this reason, so the two never double up.
 * * **Anything that is not a pointer:** left alone; the Dart background
 *   handler still sees it.
 */
class BoardhopMessagingService : FlutterFirebaseMessagingService() {

    override fun onRegistered(token: String) {
        super.onRegistered(token)
        FlutterFirebaseTokenLiveData.getInstance().postToken(token)
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val pointer = PointerData(remoteMessage.data)
        if (!pointer.isPointer) {
            super.onMessageReceived(remoteMessage)
            return
        }
        if (isApplicationForeground(this)) {
            Log.d(PushEnricher.TAG, "pointer verb=${pointer.verb} artifact=${pointer.artifactType} → foreground (Dart posts)")
            return
        }
        handle(applicationContext, pointer)
    }

    companion object {

        /**
         * The background half, also used by the debug-only `debugEnrich` hook
         * in `MainActivity`. Blocks for at most
         * [PushEnricher.BUDGET_MILLIS]; call it off the main thread.
         *
         * Returns `"enriched"`, `"fallback"` or `"skipped"` — the same three
         * words the log line uses, and the only thing the debug hook reports.
         */
        fun handle(context: Context, pointer: PointerData, post: Boolean = true): String {
            if (!notificationsEnabled(context)) {
                Log.d(PushEnricher.TAG, "pointer verb=${pointer.verb} → skipped (notifications off)")
                return "skipped"
            }
            val deadline = SystemClock.elapsedRealtime() + PushEnricher.BUDGET_MILLIS
            var enrichment: PushEnricher.Enrichment? = null
            if (pointer.isStaleAt(System.currentTimeMillis())) {
                // research/14 §4.1: a pointer older than ten minutes is not
                // worth a fetch; the line still shows.
                Log.d(PushEnricher.TAG, "pointer verb=${pointer.verb} → fallback (stale)")
            } else if (pointer.family == Family.NONE) {
                Log.d(PushEnricher.TAG, "pointer verb=${pointer.verb} → fallback (nothing to fetch)")
            } else {
                val token = PushTokens.tokenFor(context, pointer.org, deadline)
                enrichment = token?.let { PushEnricher(AdoRest()).enrich(pointer, it, deadline) }
            }
            val outcome = if (enrichment != null) "enriched" else "fallback"
            Log.d(
                PushEnricher.TAG,
                "pointer verb=${pointer.verb} artifact=${pointer.artifactType}/${pointer.artifactId} → $outcome",
            )
            if (post) PushNotifier.post(context, pointer, enrichment)
            return outcome
        }

        /**
         * The user's opt-in, read straight out of the store `shared_preferences`
         * writes on Android: `NotificationService.enabledPrefKey` behind the
         * `flutter.` prefix the plugin adds.
         */
        private fun notificationsEnabled(context: Context): Boolean = try {
            context
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.notifications.activity", false)
        } catch (_: Exception) {
            false
        }

        /**
         * `FlutterFirebaseMessagingUtils.isApplicationForeground`, reproduced.
         *
         * It is package-private in the plugin, and the two paths must agree
         * exactly or a message is either shown twice or not at all: a locked
         * keyguard counts as background even when the activity is resumed.
         * (`ProcessLifecycleOwner` would need `androidx.lifecycle:lifecycle-process`,
         * a dependency this module does not have, and would disagree with the
         * plugin about the keyguard.)
         */
        fun isApplicationForeground(context: Context): Boolean {
            val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            if (keyguard != null && keyguard.isKeyguardLocked) return false
            val activity = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            val processes = activity.runningAppProcesses ?: return false
            val packageName = context.packageName
            return processes.any {
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                    it.processName == packageName
            }
        }
    }
}
