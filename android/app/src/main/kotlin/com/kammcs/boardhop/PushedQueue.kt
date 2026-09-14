package com.kammcs.boardhop

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * The pointers this process posted while Dart was not listening, waiting for
 * Dart to take them (research/14 §4.2; the fix for the double notification
 * found on the Pixel 10 on 2026-09-14).
 *
 * When `BoardhopMessagingService` posts a notification in the background,
 * Dart never hears about the pointer unless the notification is tapped, so
 * the Activity feed's own poll finds the same artifact a little later and
 * posts a second notification for it, with the feed row's coarser route. The
 * queue closes that gap: `PushNotifier.post` appends the pointer here, and
 * `MainActivity` answers `drainPushed` on the push channel with everything
 * queued, which `PushCoordinator` inserts into the feed and marks as notified
 * before the poll can announce it again.
 *
 * Metadata only (the relay's pointer: ids, verb, actor name, artifact title
 * line); never the enriched body. A private preferences file rather than
 * `FlutterSharedPreferences`, whose list encoding is the plugin's own.
 */
object PushedQueue {

    private const val FILE = "boardhop_push"
    private const val KEY = "pending"

    /** Enough for a night of pushes; older entries fall off the front. */
    private const val MAX = 50

    private val lock = Any()

    fun append(context: Context, pointer: Map<String, String>) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            val array = try {
                JSONArray(prefs.getString(KEY, null) ?: "[]")
            } catch (_: Exception) {
                JSONArray()
            }
            array.put(JSONObject(pointer as Map<*, *>))
            val trimmed = if (array.length() > MAX) {
                JSONArray().also { out -> for (i in array.length() - MAX until array.length()) out.put(array.get(i)) }
            } else {
                array
            }
            prefs.edit().putString(KEY, trimmed.toString()).apply()
        }
    }

    /** Everything queued, and the queue emptied, in one step. */
    fun drain(context: Context): List<Map<String, String>> = synchronized(lock) {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        prefs.edit().remove(KEY).apply()
        try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { i ->
                val json = array.optJSONObject(i) ?: return@mapNotNull null
                buildMap {
                    for (key in json.keys()) {
                        val value = json.optString(key, "")
                        if (value.isNotEmpty()) put(key, value)
                    }
                }.takeIf { it.isNotEmpty() }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
