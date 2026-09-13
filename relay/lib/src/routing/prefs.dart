import 'verb.dart';

/// One person's push preferences for one organization (research/14 §6).
///
/// R2.2 only consumes this interface; R2.3 adds the `prefs` table and the
/// `GET/PUT /v1/prefs` routes that fill it. Keeping the engine behind the
/// interface is what lets that happen without touching a rule.
abstract interface class UserPrefs {
  /// Whether this person wants to hear about [verb] at all.
  ///
  /// [isMention] is true when the person was named in the text, which the
  /// "mentions only" settings let through and nothing else does.
  /// [artifactKey] is `wi.15545` / `pr.8334` / `build.20163` for the muted
  /// artifact list; null when there is nothing to mute.
  bool allows(Verb verb, {required bool isMention, String? artifactKey});

  /// True when the person's quiet hours cover [nowUtc]. [tzOffsetMinutes] is
  /// the device's offset east of UTC, sent with the heartbeat; null when the
  /// relay has never been told one, in which case a window is evaluated in UTC.
  ///
  /// Approvals are exempt by default, so the engine asks this only for the
  /// verbs that are not approvals.
  bool quietHoursSuppress(DateTime nowUtc, int? tzOffsetMinutes);
}

/// The defaults of research/14 §6 and decisions D2 and D3: everything on
/// except `workItems.anyChangeOnMine` (→ [Verb.edited]),
/// `pullRequests.pushes` (→ [Verb.pushed]) and plain build successes
/// (→ [Verb.buildSucceeded]; failures and "fixed" are on). Quiet hours off.
class DefaultPrefs implements UserPrefs {
  const DefaultPrefs();

  /// The three verbs a brand-new registration does **not** hear about.
  static const offByDefault = <Verb>{Verb.edited, Verb.pushed, Verb.buildSucceeded};

  @override
  bool allows(Verb verb, {required bool isMention, String? artifactKey}) {
    // A mention is the one thing every "on / mentions only" setting keeps.
    if (isMention) return true;
    return !offByDefault.contains(verb);
  }

  @override
  bool quietHoursSuppress(DateTime nowUtc, int? tzOffsetMinutes) => false;
}

/// Where the engine gets a person's preferences. R2.3 backs this with the
/// `prefs` table keyed by `(org, userId)`; until then everybody is on the
/// defaults.
abstract interface class PrefsSource {
  UserPrefs prefsFor(String org, String userId);

  /// Minutes east of UTC for this person's device, for quiet hours. Null when
  /// no device has reported one.
  int? timeZoneOffsetMinutes(String org, String userId);
}

class DefaultPrefsSource implements PrefsSource {
  const DefaultPrefsSource();

  static const _prefs = DefaultPrefs();

  @override
  UserPrefs prefsFor(String org, String userId) => _prefs;

  @override
  int? timeZoneOffsetMinutes(String org, String userId) => null;
}
