package com.kammcs.boardhop

import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import io.flutter.plugins.firebase.messaging.FlutterFirebaseTokenLiveData

/**
 * Stands in for `firebase_messaging`'s own messaging service (which the
 * manifest removes) to add one thing: `onRegistered`.
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
 * Posting into the plugin's own `FlutterFirebaseTokenLiveData` keeps both
 * readers working: the plugin's `onTokenRefresh` stream and the observer in
 * `MainActivity`.
 *
 * Everything else — message delivery, background isolates — is inherited
 * untouched.
 */
class BoardhopMessagingService : FlutterFirebaseMessagingService() {
    override fun onRegistered(token: String) {
        super.onRegistered(token)
        FlutterFirebaseTokenLiveData.getInstance().postToken(token)
    }
}
