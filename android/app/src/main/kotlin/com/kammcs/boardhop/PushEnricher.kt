package com.kammcs.boardhop

import android.net.Uri
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

/**
 * The Android half of research/14 §4.1: one or two GETs with **the user's own
 * token**, inside an 8 s budget, turning the relay's pointer line into a
 * notification that says what actually happened.
 *
 * Nothing here is retried and nothing here is cached: a failure of any kind —
 * offline, 401, 404, malformed JSON, the deadline — returns null and the
 * caller posts the relay's fallback line, which is always delivered.
 *
 * **Logging rule (hard):** the verb, the artifact, the HTTP status and
 * `enriched|fallback`. Never a token, a title, a comment or a response body.
 */
class PushEnricher(private val http: AdoRest) {

    /** What one successful enrichment replaces in the notification. */
    data class Enrichment(val body: String, val subText: String? = null)

    /**
     * Enriches [pointer] or returns null. [deadline] is an
     * `SystemClock.elapsedRealtime()` value; every call checks it first.
     */
    fun enrich(pointer: PointerData, token: String, deadline: Long): Enrichment? = try {
        when (pointer.family) {
            Family.WORK_ITEM -> workItem(pointer, token, deadline)
            Family.WORK_ITEM_COMMENT -> workItemComment(pointer, token, deadline)
            Family.PULL_REQUEST -> pullRequest(pointer, token, deadline)
            Family.PULL_REQUEST_COMMENT -> pullRequestComment(pointer, token, deadline)
            Family.BUILD -> build(pointer, token, deadline)
            Family.APPROVAL -> approval(pointer, token, deadline)
            Family.NONE -> null
        }
    } catch (e: Exception) {
        // Never let enrichment take the notification with it.
        Log.d(TAG, "enrich failed verb=${pointer.verb} artifact=${pointer.artifactType} reason=${e.javaClass.simpleName}")
        null
    }

    // ------------------------------------------------------------ work items

    private fun workItem(p: PointerData, token: String, deadline: Long): Enrichment? {
        val item = http.get(workItemUrl(p), token, deadline) ?: return null
        val fields = item.optJSONObject("fields") ?: return null
        val body = EnrichmentFormat.workItemBody(
            p.fallbackBody,
            fields.optStringOrNull("System.WorkItemType"),
            fields.optStringOrNull("System.State"),
        ) ?: return null
        return Enrichment(body)
    }

    private fun workItemComment(p: PointerData, token: String, deadline: Long): Enrichment? {
        if (p.project.isEmpty()) return null
        val url = "${orgBase(p.org)}/${Uri.encode(p.project)}/_apis/wit/workItems/${Uri.encode(p.artifactId)}/comments" +
            "?api-version=7.1-preview.4&\$expand=renderedText&order=desc&\$top=50"
        val json = http.get(url, token, deadline) ?: return null
        val comments = json.optJSONArray("comments") ?: return null
        val wanted = p.anchorId("comment")
        val chosen = pick(comments) { it.optStringOrNull("id") == wanted }
            ?: comments.optJSONObject(0)
            ?: return null
        val text = EnrichmentFormat.plainText(
            chosen.optStringOrNull("renderedText") ?: chosen.optStringOrNull("text"),
        )
        if (text.isEmpty()) return null
        return Enrichment(EnrichmentFormat.clamp(text))
    }

    private fun workItemUrl(p: PointerData) =
        "${orgBase(p.org)}/_apis/wit/workitems/${Uri.encode(p.artifactId)}?api-version=7.1"

    // --------------------------------------------------------- pull requests

    private fun pullRequest(p: PointerData, token: String, deadline: Long): Enrichment? {
        val pr = http.get(pullRequestUrl(p), token, deadline) ?: return null
        val body = EnrichmentFormat.pullRequestBody(
            p.fallbackBody,
            pr.optJSONObject("repository")?.optStringOrNull("name"),
            pr.optStringOrNull("sourceRefName"),
            pr.optStringOrNull("targetRefName"),
        ) ?: return null
        return Enrichment(body)
    }

    private fun pullRequestComment(p: PointerData, token: String, deadline: Long): Enrichment? {
        val threadId = p.anchorId("thread") ?: return null
        val pr = http.get(pullRequestUrl(p), token, deadline) ?: return null
        val repository = pr.optJSONObject("repository") ?: return null
        val repositoryId = repository.optStringOrNull("id") ?: return null
        val project = repository.optJSONObject("project")?.optStringOrNull("id")
            ?: p.project.takeIf { it.isNotEmpty() }
            ?: return null
        val url = "${orgBase(p.org)}/${Uri.encode(project)}/_apis/git/repositories/${Uri.encode(repositoryId)}" +
            "/pullRequests/${Uri.encode(p.artifactId)}/threads/${Uri.encode(threadId)}?api-version=7.1"
        val thread = http.get(url, token, deadline) ?: return null
        val comments = thread.optJSONArray("comments") ?: return null
        val byActor = p.actorId?.let { actor ->
            pickLast(comments) { it.optJSONObject("author")?.optStringOrNull("id") == actor }
        }
        val chosen = byActor ?: pickLast(comments) { it.optStringOrNull("commentType") != "system" } ?: return null
        val text = EnrichmentFormat.plainText(chosen.optStringOrNull("content"))
        if (text.isEmpty()) return null
        val context = thread.optJSONObject("threadContext")
        val location = EnrichmentFormat.threadLocation(
            context?.optStringOrNull("filePath"),
            context?.optJSONObject("rightFileStart")?.optIntOrNull("line")
                ?: context?.optJSONObject("leftFileStart")?.optIntOrNull("line"),
        )
        return Enrichment(EnrichmentFormat.clamp(text), subText = location)
    }

    private fun pullRequestUrl(p: PointerData) =
        "${orgBase(p.org)}/_apis/git/pullrequests/${Uri.encode(p.artifactId)}?api-version=7.1"

    // ---------------------------------------------------------------- builds

    private fun build(p: PointerData, token: String, deadline: Long): Enrichment? {
        if (p.project.isEmpty()) return null
        val base = "${orgBase(p.org)}/${Uri.encode(p.project)}/_apis/build/builds/${Uri.encode(p.artifactId)}"
        val run = http.get("$base?api-version=7.1", token, deadline) ?: return null
        val result = run.optStringOrNull("result")?.lowercase(Locale.ROOT)
        if (result == "succeeded") {
            val duration = durationOf(run.optStringOrNull("startTime"), run.optStringOrNull("finishTime"))
            return EnrichmentFormat.buildSuccessBody(p.fallbackBody, duration)?.let { Enrichment(it) }
        }
        val timeline = http.get("$base/timeline?api-version=7.1", token, deadline) ?: return null
        val records = timeline.optJSONArray("records") ?: return null
        val failure = firstFailure(records) ?: return null
        val body = EnrichmentFormat.buildFailureBody(p.fallbackBody, failure.first, failure.second) ?: return null
        return Enrichment(body)
    }

    /**
     * The first failed **task** record, as `("Deploy › Run tests", "3 tests
     * failed")`: its path through the parent records and its first issue's
     * message. Ordered by the record's `order` within its parent, then by
     * `startTime`, which is how the web console reads a timeline.
     */
    private fun firstFailure(records: JSONArray): Pair<String, String?>? {
        val byId = HashMap<String, JSONObject>(records.length())
        for (i in 0 until records.length()) {
            val record = records.optJSONObject(i) ?: continue
            record.optStringOrNull("id")?.let { byId[it] = record }
        }
        val failed = (0 until records.length())
            .mapNotNull { records.optJSONObject(it) }
            .filter { it.optStringOrNull("result")?.lowercase(Locale.ROOT) == "failed" }
            .filter { it.optStringOrNull("type").equals("Task", ignoreCase = true) }
            .sortedWith(compareBy({ it.optStringOrNull("startTime") ?: "" }, { it.optIntOrNull("order") ?: 0 }))
            .firstOrNull() ?: return null

        val names = ArrayList<String>(3)
        var node: JSONObject? = failed
        var hops = 0
        while (node != null && hops < 6) {
            node.optStringOrNull("name")?.let { names.add(0, it) }
            node = node.optStringOrNull("parentId")?.let { byId[it] }
            hops++
        }
        val path = names.takeLast(2).joinToString(EnrichmentFormat.PATH_ARROW)
        val issue = failed.optJSONArray("issues")?.optJSONObject(0)?.optStringOrNull("message")
        return path to issue
    }

    // ------------------------------------------------------------- approvals

    private fun approval(p: PointerData, token: String, deadline: Long): Enrichment? {
        if (p.project.isEmpty()) return null
        val url = "${orgBase(p.org)}/${Uri.encode(p.project)}/_apis/pipelines/approvals/${Uri.encode(p.artifactId)}" +
            "?\$expand=steps&api-version=7.1-preview.1"
        val json = http.get(url, token, deadline) ?: return null
        val runName = json.optJSONObject("pipeline")?.optJSONObject("owner")?.optStringOrNull("name")
        val body = EnrichmentFormat.approvalBody(
            p.fallbackBody,
            json.optStringOrNull("instructions"),
            runName,
        ) ?: return null
        return Enrichment(body)
    }

    // ----------------------------------------------------------------- utils

    private fun durationOf(start: String?, finish: String?): Long? {
        val from = parseIso(start) ?: return null
        val to = parseIso(finish) ?: return null
        val millis = to - from
        return if (millis >= 0) millis else null
    }

    private fun pick(array: JSONArray, test: (JSONObject) -> Boolean): JSONObject? {
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            if (test(item)) return item
        }
        return null
    }

    private fun pickLast(array: JSONArray, test: (JSONObject) -> Boolean): JSONObject? {
        for (i in array.length() - 1 downTo 0) {
            val item = array.optJSONObject(i) ?: continue
            if (test(item)) return item
        }
        return null
    }

    companion object {
        const val TAG = "BoardhopPush"

        /** research/14 §4.1: the service caps its own work at 8 s. */
        const val BUDGET_MILLIS = 8_000L

        fun orgBase(org: String) = "https://dev.azure.com/${Uri.encode(org)}"

        /** ISO-8601 with an optional fractional part, as Azure DevOps writes it. */
        fun parseIso(value: String?): Long? {
            if (value.isNullOrEmpty()) return null
            return try {
                val trimmed = value.replace(Regex("""\.\d+"""), "")
                val format = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
                format.timeZone = java.util.TimeZone.getTimeZone("UTC")
                format.parse(trimmed)?.time
            } catch (_: Exception) {
                null
            }
        }
    }
}

/** `optString` that answers null instead of `""` or the string `"null"`. */
fun JSONObject.optStringOrNull(key: String): String? {
    if (isNull(key)) return null
    val value = optString(key, "")
    return value.takeIf { it.isNotEmpty() }
}

fun JSONObject.optIntOrNull(key: String): Int? = if (isNull(key)) null else optInt(key, 0).takeIf { has(key) }

/** Which fetch a pointer's verb asks for (research/14 §4.1's rows). */
enum class Family { WORK_ITEM, WORK_ITEM_COMMENT, PULL_REQUEST, PULL_REQUEST_COMMENT, BUILD, APPROVAL, NONE }

/**
 * The pointer as it arrives in the FCM `data` map, which is the same contract
 * as `lib/features/notifications/push_pointer.dart` and
 * `relay/lib/src/gateway/pointer.dart`. Strings only: FCM carries nothing else.
 */
data class PointerData(val data: Map<String, String>) {
    val org get() = str("org").orEmpty()
    val project get() = str("project").orEmpty()
    val artifactType get() = str("artifactType").orEmpty()
    val artifactId get() = str("artifactId").orEmpty()
    val eventType get() = str("eventType").orEmpty()
    val verb get() = str("verb")
    val actorId get() = str("actorId")
    val anchor get() = str("anchor")
    val collapseKey get() = str("collapseKey")
    val fallbackTitle get() = str("fallbackTitle")
    val fallbackBody get() = str("fallbackBody")
    val fallbackSubtitle get() = str("fallbackSubtitle")
    val sentAt get() = PushEnricher.parseIso(str("sentAt"))

    /** True when the required three fields are there (`PushPointer.tryFrom`). */
    val isPointer get() = org.isNotEmpty() && artifactType.isNotEmpty() && artifactId.isNotEmpty()

    /** research/14 §4.1: older than ten minutes → no fetch, fallback line. */
    fun isStaleAt(nowMillis: Long): Boolean {
        val sent = sentAt ?: return false
        return nowMillis - sent > 10 * 60 * 1000L
    }

    /** `comment:42` → `42` when [kind] matches. */
    fun anchorId(kind: String): String? {
        val value = anchor ?: return null
        val prefix = "$kind:"
        return if (value.startsWith(prefix)) value.substring(prefix.length).takeIf { it.isNotEmpty() } else null
    }

    val shortFamily: String
        get() = when (artifactType) {
            "workItem" -> "wi"
            "pullRequest" -> "pr"
            "build" -> "build"
            "approval" -> "approval"
            else -> "other"
        }

    /** `PushPointer.groupKey`: one group per artifact family per organization. */
    val groupKey get() = "$org.$shortFamily"

    /** `PushPointer.tag`. */
    val tag get() = collapseKey ?: "$org.$artifactType.$artifactId"

    val notificationId get() = EnrichmentFormat.notificationId(collapseKey, org, artifactType, artifactId)

    val family: Family
        get() = when (artifactType) {
            "workItem" -> when (verb) {
                "commented", "replied", "mentioned" -> Family.WORK_ITEM_COMMENT
                "assigned", "reassigned", "stateChanged", "edited", "created" -> Family.WORK_ITEM
                else -> Family.NONE
            }
            "pullRequest" -> when (verb) {
                "commented", "replied", "mentioned" -> Family.PULL_REQUEST_COMMENT
                "reviewRequested", "voted", "prCompleted", "prAbandoned", "prPublished", "pushed", "mergeFailed" ->
                    Family.PULL_REQUEST
                else -> Family.NONE
            }
            "build" -> when (verb) {
                "buildFailed", "buildPartial", "buildCanceled", "buildSucceeded", "buildFixed" -> Family.BUILD
                else -> Family.NONE
            }
            "approval" -> when (verb) {
                "approvalPending", "approvalCompleted" -> Family.APPROVAL
                else -> Family.NONE
            }
            else -> Family.NONE
        }

    private fun str(key: String) = data[key]?.takeIf { it.isNotEmpty() }
}

/**
 * The smallest possible Azure DevOps read: a GET with the user's bearer token,
 * a 5 s per-call timeout and no retry, mirroring `lib/core/http/ado_client.dart`
 * (same `Accept` and `X-TFS-FedAuthRedirect: Suppress`, so a sign-in redirect
 * comes back as a 401 rather than as HTML).
 */
open class AdoRest(private val perCallMillis: Int = 5_000) {

    /** Null on any non-2xx, any parse failure, or once [deadline] has passed. */
    open fun get(url: String, token: String, deadline: Long): JSONObject? {
        val remaining = deadline - android.os.SystemClock.elapsedRealtime()
        if (remaining <= 0) {
            Log.d(PushEnricher.TAG, "fetch skipped: past the deadline")
            return null
        }
        val timeout = minOf(perCallMillis.toLong(), remaining).toInt()
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = timeout
                readTimeout = timeout
                instanceFollowRedirects = false
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("X-TFS-FedAuthRedirect", "Suppress")
            }
            val status = connection.responseCode
            if (status !in 200..299) {
                Log.d(PushEnricher.TAG, "fetch http=$status")
                return null
            }
            val text = connection.inputStream.bufferedReader().use(BufferedReader::readText)
            Log.d(PushEnricher.TAG, "fetch http=$status bytes=${text.length}")
            JSONObject(text)
        } catch (e: Exception) {
            Log.d(PushEnricher.TAG, "fetch failed: ${e.javaClass.simpleName}")
            null
        } finally {
            connection?.disconnect()
        }
    }
}
