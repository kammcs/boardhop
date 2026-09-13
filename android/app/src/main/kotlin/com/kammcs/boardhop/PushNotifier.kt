package com.kammcs.boardhop

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/**
 * Posts the notification for one pushed pointer (research/14 §4.1, D7).
 *
 * The shape, whether the body was enriched or not:
 *
 * * channel `activity`, the same one the polled notifications use, so both
 *   look alike and share the user's per-channel settings;
 * * title = the relay's `fallbackTitle` (the artifact line — metadata, and the
 *   same words in both versions), text = the enriched body when there is one,
 *   else `fallbackBody`; sub-text = the enriched location (`file.js:38`) or
 *   `fallbackSubtitle`;
 * * `BigTextStyle` so a comment is readable in full, capped at
 *   [EnrichmentFormat.MAX_BODY];
 * * **private**, with a public version that is the fallback line: a locked
 *   phone shows "Javier Perez replied on !8261 · ServiceDelivery" and the
 *   comment text only appears after unlock. The channel is deliberately left
 *   at `VISIBILITY_NO_OVERRIDE` so this per-notification choice is the one
 *   that applies;
 * * tag = the relay's collapse key and id = [EnrichmentFormat.notificationId],
 *   which is Dart's `PushPointer.notificationId`, so a foreground post and a
 *   background post of the same event replace each other;
 * * grouped by `{org}.{family}`, with a summary once three or more of that
 *   group are showing;
 * * tapping launches `MainActivity` with the pointer as JSON in
 *   [EXTRA_POINTER]; `MainActivity` hands it to Dart on the
 *   `com.kammcs.boardhop/push` channel as `onOpened`, which is the same entry
 *   `PushCoordinator` already routes from.
 */
object PushNotifier {

    /** The pointer `data` map as JSON, on the launch intent. */
    const val EXTRA_POINTER = "com.kammcs.boardhop.push.pointer"

    private const val CHANNEL_ID = "activity"
    private const val CHANNEL_NAME = "Activity"
    private const val CHANNEL_DESCRIPTION = "Pull requests waiting for you, work item changes and builds"

    /** research/14 §4.1: the summary appears once the group has three members. */
    private const val SUMMARY_AT = 3

    fun post(context: Context, pointer: PointerData, enrichment: PushEnricher.Enrichment?) {
        val title = pointer.fallbackTitle ?: "Boardhop"
        val fallbackBody = pointer.fallbackBody.orEmpty()
        val body = enrichment?.body?.takeIf { it.isNotEmpty() } ?: fallbackBody
        val subText = enrichment?.subText ?: pointer.fallbackSubtitle

        ensureChannel(context)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSubText(subText)
            .setAutoCancel(true)
            .setGroup(pointer.groupKey)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion(context, title, fallbackBody, pointer.fallbackSubtitle))
            .setContentIntent(contentIntent(context, pointer))
            .setCategory(NotificationCompat.CATEGORY_SOCIAL)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        pointer.sentAt?.let { builder.setWhen(it).setShowWhen(true) }

        val manager = NotificationManagerCompat.from(context)
        try {
            manager.notify(pointer.tag, pointer.notificationId, builder.build())
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted: nothing to do, and nothing lost.
            Log.d(PushEnricher.TAG, "post refused: no notification permission")
            return
        }
        maybePostSummary(context, pointer)
    }

    private fun publicVersion(context: Context, title: String, body: String, subText: String?) =
        NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setSubText(subText)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

    private fun contentIntent(context: Context, pointer: PointerData): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_POINTER, JSONObject(pointer.data as Map<*, *>).toString())
        }
        return PendingIntent.getActivity(
            context,
            pointer.notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * A group summary once three of a group are showing, so a busy
     * organization collapses into one row instead of filling the shade.
     */
    private fun maybePostSummary(context: Context, pointer: PointerData) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val members = try {
            manager.activeNotifications.count { active ->
                active.notification.group == pointer.groupKey &&
                    (active.notification.flags and android.app.Notification.FLAG_GROUP_SUMMARY) == 0
            }
        } catch (_: Exception) {
            return
        }
        if (members < SUMMARY_AT) return
        val summary = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(pointer.org)
            .setContentText(summaryText(members))
            .setSubText(pointer.fallbackSubtitle)
            .setGroup(pointer.groupKey)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        try {
            NotificationManagerCompat.from(context)
                .notify(pointer.groupKey, EnrichmentFormat.summaryId(pointer.groupKey), summary)
        } catch (_: SecurityException) {
            // As above.
        }
    }

    /** The only user-visible string this file composes. */
    private fun summaryText(count: Int) = "$count updates"

    /**
     * The app creates this channel at startup (`NotificationService`); this is
     * for the case where a push arrives before that has happened on a fresh
     * process. Creating an existing channel is a no-op, and the lock-screen
     * visibility is deliberately not set: left at `VISIBILITY_NO_OVERRIDE`, the
     * per-notification `setVisibility(PRIVATE)` above is what applies.
     */
    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = CHANNEL_DESCRIPTION
            },
        )
    }
}
