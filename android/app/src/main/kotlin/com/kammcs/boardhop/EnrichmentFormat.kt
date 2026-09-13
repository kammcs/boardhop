package com.kammcs.boardhop

/**
 * Every pure function the Android enrichment path needs, and every English
 * string it can show (research/14 §4.1; R2.6).
 *
 * It is deliberately free of Android and of the network: given decoded JSON
 * values it returns the line to display. That keeps the one part with real
 * logic — HTML stripping, mention rendering, branch shortening, the timeline
 * failure summary, the notification id — readable and reviewable without a
 * device, and is where JVM unit tests would go if this module ever wires JUnit
 * up (it does not today; see the R2.6 report).
 *
 * **No content ever reaches a log from here.** Callers log the verb, the
 * artifact, the HTTP status and `enriched|fallback`, nothing else.
 */
object EnrichmentFormat {

    /** research/14 §4.1: at most 1,000 characters of comment in the big text. */
    const val MAX_BODY = 1000

    /** The one separator the notification bodies use. */
    const val SEP = " · "

    /** The arrow between a pull request's source and target branch. */
    const val BRANCH_ARROW = " → "

    /** The separator between a stage/job and the task that failed. */
    const val PATH_ARROW = " › "

    // ---------------------------------------------------------------- ids

    /**
     * Dart's `String.hashCode`, reproduced exactly.
     *
     * The Dart VM hashes a string with Jenkins' one-at-a-time over its UTF-16
     * code units and finalises to **30** bits, mapping zero to one
     * (`runtime/vm/hash.h`, `String::Hash`). `PushPointer.notificationId` in
     * `lib/features/notifications/push_pointer.dart` is that value masked with
     * `0x7fffffff`, so a notification this service posts and one the Dart
     * foreground path posts for the same collapse key share an id and replace
     * each other in the shade instead of stacking.
     *
     * Verified against the Dart VM for `contoso.pr.8336.t4821` (472433266),
     * `puremedia.build.20163` (929721395) and `a` (170824770).
     */
    fun dartStringHash(value: String): Int {
        var hash = 0
        for (c in value) {
            hash += c.code
            hash += hash shl 10
            hash = hash xor (hash ushr 6)
        }
        hash += hash shl 3
        hash = hash xor (hash ushr 11)
        hash += hash shl 15
        hash = hash and 0x3fffffff
        return if (hash == 0) 1 else hash
    }

    /**
     * The notification id for one pointer, matching `PushPointer.notificationId`.
     *
     * The relay always sends `collapseKey` in the FCM data map
     * (`relay/lib/src/gateway/fcm.dart`), so the first branch is the live one.
     * The second differs from Dart on purpose: Dart's fallback is
     * `Object.hash(...)`, whose seed is an identity hash and is therefore not
     * reproducible off-VM, so the same three parts are hashed as the string
     * that is also the notification **tag**. Unreachable for a relay pointer.
     */
    fun notificationId(collapseKey: String?, org: String, artifactType: String, artifactId: String): Int {
        val key = collapseKey?.takeIf { it.isNotEmpty() } ?: "$org.$artifactType.$artifactId"
        return dartStringHash(key) and 0x7fffffff
    }

    /** The id of a group's summary notification; never collides with a member. */
    fun summaryId(groupKey: String): Int = dartStringHash("summary:$groupKey") and 0x7fffffff

    // -------------------------------------------------------------- html

    private val MENTION = Regex(
        """<a\b[^>]*data-vss-mention[^>]*>(.*?)</a>""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
    )
    private val BLOCK_END = Regex(
        """</(p|div|li|ul|ol|tr|h[1-6]|blockquote|pre)\s*>|<br\s*/?>""",
        RegexOption.IGNORE_CASE,
    )
    private val TAG = Regex("""<[^>]*>""")
    private val MANY_NEWLINES = Regex("""\n{3,}""")
    private val SPACES = Regex("""[ \t ]{2,}""")

    /**
     * Server-rendered comment HTML as the plain text a notification can show.
     *
     * `data-vss-mention` anchors become `@Name` (Azure DevOps renders the
     * display name inside the anchor, sometimes already with the `@`), block
     * ends become newlines, every other tag goes, entities are decoded.
     */
    fun plainText(html: String?): String {
        if (html.isNullOrEmpty()) return ""
        var text = MENTION.replace(html) { match ->
            val name = decodeEntities(TAG.replace(match.groupValues[1], "")).trim()
            when {
                name.isEmpty() -> ""
                name.startsWith("@") -> name
                else -> "@$name"
            }
        }
        text = BLOCK_END.replace(text, "\n")
        text = TAG.replace(text, "")
        text = decodeEntities(text)
        text = text.replace("\r\n", "\n").replace('\r', '\n')
        text = MANY_NEWLINES.replace(text, "\n\n")
        text = SPACES.replace(text, " ")
        return text.trim()
    }

    private val NUMERIC = Regex("""&#(x?)([0-9a-fA-F]+);""")

    fun decodeEntities(value: String): String {
        if (!value.contains('&')) return value
        var text = NUMERIC.replace(value) { match ->
            val radix = if (match.groupValues[1].isEmpty()) 10 else 16
            val code = match.groupValues[2].toIntOrNull(radix)
            if (code == null || code < 0 || code > 0x10ffff) match.value else String(Character.toChars(code))
        }
        for ((entity, replacement) in ENTITIES) text = text.replace(entity, replacement)
        return text
    }

    private val ENTITIES = listOf(
        "&nbsp;" to " ",
        "&lt;" to "<",
        "&gt;" to ">",
        "&quot;" to "\"",
        "&apos;" to "'",
        "&hellip;" to "…",
        "&mdash;" to "—",
        "&ndash;" to "–",
        // Last: an escaped ampersand must not re-open another entity.
        "&amp;" to "&",
    )

    /** Cuts a body to [MAX_BODY] on a word boundary where there is one. */
    fun clamp(value: String, max: Int = MAX_BODY): String {
        if (value.length <= max) return value
        val cut = value.substring(0, max - 1)
        val space = cut.lastIndexOf(' ')
        return (if (space > max / 2) cut.substring(0, space) else cut).trimEnd() + "…"
    }

    // ------------------------------------------------------------ pieces

    /** `refs/heads/feature/x` → `feature/x`; anything else unchanged. */
    fun shortBranch(ref: String?): String? {
        val value = ref?.trim().orEmpty()
        if (value.isEmpty()) return null
        return value.removePrefix("refs/heads/")
    }

    /** Joins the non-empty parts with [SEP]. */
    fun join(vararg parts: String?): String? {
        val kept = parts.mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }
        return if (kept.isEmpty()) null else kept.joinToString(SEP)
    }

    // ------------------------------------------------------------- bodies

    /**
     * work item `assigned`/`stateChanged`/…: the fallback line plus the type
     * and the state — "Ada Example assigned you · User Story · Active".
     */
    fun workItemBody(fallbackBody: String?, type: String?, state: String?): String? =
        join(fallbackBody, type, state)

    /**
     * PR `reviewRequested`/`voted`/…: the fallback line plus the repository and
     * the branches — "Ada Example asked you to review !8334 · boardhop ·
     * feature/x → main".
     *
     * The vote label is **not** appended: the relay's fallback line already
     * carries it (`verbPhrase` → `_votePhrase`), so repeating it would read
     * twice. See the R2.6 report.
     */
    fun pullRequestBody(fallbackBody: String?, repository: String?, source: String?, target: String?): String? {
        val from = shortBranch(source)
        val to = shortBranch(target)
        val branches = if (from != null && to != null) from + BRANCH_ARROW + to else from ?: to
        return join(fallbackBody, repository, branches)
    }

    /** A file thread's sub-text: `lib/main.dart:38`. */
    fun threadLocation(filePath: String?, line: Int?): String? {
        val path = filePath?.trim()?.removePrefix("/")?.takeIf { it.isNotEmpty() } ?: return null
        return if (line != null && line > 0) "$path:$line" else path
    }

    /**
     * A failed run: "Deploy › Run tests: 3 tests failed", from the first failed
     * task record's path and its first issue message.
     */
    fun buildFailureBody(fallbackBody: String?, path: String?, issue: String?): String? {
        val where = path?.trim()?.takeIf(String::isNotEmpty)
        val what = issue?.trim()?.takeIf(String::isNotEmpty)?.lineSequence()?.firstOrNull()?.trim()
        val detail = when {
            where != null && what != null -> "$where: $what"
            where != null -> where
            else -> what
        }
        return join(fallbackBody, detail)
    }

    /** A run that finished well: "…· Succeeded in 1m 20s". */
    fun buildSuccessBody(fallbackBody: String?, durationMillis: Long?): String? =
        join(fallbackBody, durationMillis?.let { "Succeeded in ${durationLabel(it)}" })

    /** `90s` → `1m 30s`; `3720s` → `1h 2m`. */
    fun durationLabel(millis: Long): String {
        val seconds = (millis / 1000).coerceAtLeast(0)
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val rest = seconds % 60
        return when {
            hours > 0 -> "${hours}h ${minutes}m"
            minutes > 0 -> "${minutes}m ${rest}s"
            else -> "${rest}s"
        }
    }

    /** An approval: the pipeline author's instructions and the run name. */
    fun approvalBody(fallbackBody: String?, instructions: String?, runName: String?): String? =
        join(fallbackBody, plainText(instructions).takeIf { it.isNotEmpty() }, runName)
}
