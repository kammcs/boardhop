import '../../demo_world.dart';

/// One discussion comment of the invented backlog.
class DemoComment {
  const DemoComment(this.author, this.hoursAgo, this.html);

  final DemoPerson author;
  final num hoursAgo;

  /// The body as the web stores it (`format: html`), with `{@name}` where a
  /// person is mentioned; [DemoWorkContent.renderMentions] turns those into
  /// the `data-vss-mention` anchors the service writes.
  final String html;
}

/// The words on the work items: descriptions, acceptance criteria, repro
/// steps and discussions. Rich for the items the screenshots open (1234,
/// 1231), short and plausible for the rest.
abstract final class DemoWorkContent {
  static const _people = {
    'kelly': DemoWorld.kelly,
    'priya': DemoWorld.priya,
    'marcus': DemoWorld.marcus,
    'sofia': DemoWorld.sofia,
    'jonah': DemoWorld.jonah,
    'aiko': DemoWorld.aiko,
  };

  /// `{@kelly}` → the anchor the web writes for a person mention.
  static String renderMentions(String html) =>
      html.replaceAllMapped(RegExp(r'\{@(\w+)\}'), (m) {
        final person = _people[m.group(1)];
        if (person == null) return m.group(0)!;
        return mentionAnchor(person);
      });

  static String mentionAnchor(DemoPerson person) =>
      '<a href="#" data-vss-mention="version:2.0,${person.id}">'
      '@${person.name}</a>';

  /// The people a stored body mentions, in order.
  static List<DemoPerson> mentionedIn(String html) => [
    for (final m in RegExp(r'\{@(\w+)\}').allMatches(html))
      ?_people[m.group(1)],
  ];

  static const descriptions = <int, String>{
    1234:
        '<div>As a team lead on a phone or a tablet, I want the sprint '
        "taskboard to show each person's remaining work against their "
        'capacity, so I can rebalance tasks during stand-up without opening '
        'the web.</div><div><br></div>'
        '<div><b>Scope</b></div><ul>'
        '<li>Story rows with their tasks in <i>To Do</i>, <i>In Progress</i> '
        'and <i>Done</i></li>'
        '<li>Remaining Work rolled up per story and per person</li>'
        "<li>A capacity bar per person from the team's capacity settings, "
        'less personal and team days off</li>'
        '<li>Drag a task between columns; tap it to change the remaining '
        'hours</li></ul>'
        '<div><b>Layout</b></div>'
        '<div>iPad and phones in landscape show the whole grid with the story '
        'column pinned. A phone in portrait shows one story at a time, picked '
        'from a chip strip under the sprint header.</div>',
    1231:
        '<div>Boards with a split column (<i>In Progress: Doing / Done</i>) '
        'should accept a card dropped on either half, the way the web does. '
        'Today a card can only land in <i>Doing</i> and has to be moved '
        'again.</div><div><br></div>'
        '<div><b>Notes</b></div><ul>'
        '<li>Each half is its own drop target with its own highlight</li>'
        '<li>Moving into <i>Done</i> writes the Kanban <code>Column.Done</code> '
        'field only; the state stays mapped to the column</li>'
        '<li>Long-press starts the drag on phones; tablets drag '
        'immediately</li>'
        '<li>Lanes keep their card when a filter is on</li></ul>',
    1238:
        '<div>On an iPad in landscape, show the base and the change side by '
        'side with synchronized scrolling, instead of the unified diff.</div>',
    1241:
        '<div>A pipeline waiting on an environment approval sends a push. '
        'The notification carries <b>Approve</b> and <b>Reject</b> actions '
        'that act through the Checks API without opening the app.</div>',
    1243:
        '<div>Two dashboard tiles: the sprint burndown with an ideal line, '
        'and velocity over the last six sprints.</div>',
    1236:
        '<div>Every list, board and page refreshes with pull to refresh; no '
        'refresh buttons anywhere.</div>',
    1246:
        '<div>Boards and work items open from the last copy read, with a '
        'banner saying how old it is, when the phone is offline.</div>',
    1248:
        '<div>Typing <code>@</code> in a comment offers the people on the '
        'item first, then recent people, then the team.</div>',
    1257:
        '<div>Replace the solid navigation rail on iPad with floating liquid '
        'glass controls.</div>',
    1180:
        '<div>Everything a team needs from Azure DevOps on a phone: boards, '
        'sprints, pull requests, pipelines and notifications.</div>',
    1184:
        '<div>Kanban boards, sprint backlogs and the taskboard, with drag and '
        'drop and offline reading.</div>',
  };

  static const acceptanceCriteria = <int, String>{
    1234:
        '<ul><li>The capacity bar turns amber at 90% and red above 100% of '
        'the hours available for the rest of the sprint</li>'
        '<li>Personal and team days off reduce the available hours</li>'
        '<li>Moving a task to <i>Done</i> clears its Remaining Work</li>'
        '<li>A story row shows the sum of its open tasks</li>'
        '<li>The sprint opens offline from the cached copy</li></ul>',
    1231:
        '<ul><li>A card dropped on the Done half lands in Done without a '
        'second move</li><li>VoiceOver and TalkBack announce the column and '
        'the half</li><li>No card changes lane when a lane filter is on</li>'
        '</ul>',
    1238:
        '<ul><li>Both panes scroll together</li><li>Comments can be added '
        'from either side</li></ul>',
    1243: '<ul><li>Burndown matches the web within one item per day</li></ul>',
  };

  static const reproSteps = <int, String>{
    1252:
        '<ol><li>Open a sprint that ends today</li><li>Open the Burndown '
        'tab</li></ol><div><b>Expected:</b> the chart runs to the last working '
        'day.</div><div><b>Actual:</b> the last day is missing, so the line '
        'never reaches zero.</div>',
    1255:
        '<ol><li>Sign in on an iPhone and turn on notifications</li><li>Wait '
        'for APNs to rotate the device token (or reinstall)</li><li>Trigger a '
        'pull request comment</li></ol><div><b>Actual:</b> no push arrives '
        'until the app is opened again.</div>',
    1283:
        '<ol><li>Set the largest accessibility text size</li><li>Open any '
        'pull request diff</li></ol><div>The line numbers drift out of line '
        'with the code.</div>',
    1286:
        '<div>Tag chips on board cards are barely readable in dark mode.</div>',
  };

  static const comments = <int, List<DemoComment>>{
    1234: [
      DemoComment(
        DemoWorld.sofia,
        70,
        '<div>Landscape grid is in: the story column stays pinned while the '
        'three state columns scroll. Screenshots are on the pull request.'
        '</div>',
      ),
      DemoComment(
        DemoWorld.marcus,
        46,
        '<div>{@kelly} should the bar count team days off as well, or only '
        "the person's own?</div>",
      ),
      DemoComment(
        DemoWorld.kelly,
        26,
        '<div>Both, the web does. {@sofia} can you check the bar turns amber '
        'past 90%?</div>',
      ),
      DemoComment(
        DemoWorld.sofia,
        3,
        '<div>Checked on the iPad Pro: amber at 90%, red past 100%, and it '
        'reads well in dark mode too.</div>',
      ),
    ],
    1231: [
      DemoComment(
        DemoWorld.priya,
        96,
        '<div>Drop targets now hit-test the Doing and Done halves separately, '
        'so a card can land straight in Done.</div>',
      ),
      DemoComment(
        DemoWorld.jonah,
        50,
        '<div>Tried it on the Pixel Tablet with a lane filter on. No card '
        'jumped lanes.</div>',
      ),
      DemoComment(
        DemoWorld.kelly,
        5,
        '<div>Looks ready for review. {@aiko} could you give it a pass on '
        'the iPhone with VoiceOver?</div>',
      ),
      DemoComment(
        DemoWorld.aiko,
        1.1,
        '<div>VoiceOver reads "Moved to In Progress, Done". Works for me.'
        '</div>',
      ),
    ],
    1238: [
      DemoComment(
        DemoWorld.marcus,
        30,
        '<div>Word-level highlighting is done; scrolling sync is next.</div>',
      ),
    ],
    1241: [
      DemoComment(
        DemoWorld.jonah,
        20,
        '<div>{@aiko} the relay needs a new push category for approvals. I '
        'added <code>pipeline-approval</code> on my branch.</div>',
      ),
      DemoComment(
        DemoWorld.aiko,
        7,
        '<div>Deployed to the relay. Actions show on the lock screen now.'
        '</div>',
      ),
    ],
    1252: [
      DemoComment(
        DemoWorld.sofia,
        6,
        '<div>The day range was half-open. Fix is on the pull request.</div>',
      ),
    ],
    1255: [
      DemoComment(
        DemoWorld.aiko,
        26,
        '<div>Reproduced on a fresh install. {@kelly} this one blocks the '
        'TestFlight build.</div>',
      ),
    ],
  };

  static String description(DemoWorkItem w) =>
      descriptions[w.id] ??
      switch (w.type) {
        'Task' => '<div>${_escape(w.title)}.</div>',
        'Bug' => '',
        _ =>
          '<div>${_escape(w.title)}, on iOS and Android, on phones and '
              'tablets.</div>',
      };

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
