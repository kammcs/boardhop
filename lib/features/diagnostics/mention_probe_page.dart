import 'package:flutter/material.dart' hide Durations;

import '../../core/http/ado_exceptions.dart';
import '../../data/models/work_item.dart';
import '../../theme/theme.dart';
import '../shared/mention/mention_controller.dart';
import '../shared/mention/mention_field.dart';
import '../shared/mention/mention_hint.dart';
import '../shared/mention/mention_source.dart';
import '../../core/text/mention.dart';

/// Phase M-B's probe: the mention picker driven by canned data, so the whole
/// widget can be looked at on a simulator before any composer is wired to it.
///
/// Debug and profile builds only (`AppConfig.diagnosticsEnabled`), like every
/// other probe. Nothing here touches the network and no name or GUID is real.
class MentionProbePage extends StatefulWidget {
  const MentionProbePage({super.key});

  @override
  State<MentionProbePage> createState() => _MentionProbePageState();
}

class _MentionProbePageState extends State<MentionProbePage> {
  static const _participants = [
    IdentityRef(
      displayName: 'Ada Lovelace',
      uniqueName: 'ada@example.com',
      id: '11111111-1111-4111-8111-111111111111',
    ),
    IdentityRef(
      displayName: 'Grace Hopper',
      uniqueName: 'grace@example.com',
      id: '22222222-2222-4222-8222-222222222222',
    ),
  ];

  static const _recents = [
    IdentityRef(
      displayName: 'Kelly Kamm',
      uniqueName: 'kelly@example.com',
      id: '33333333-3333-4333-8333-333333333333',
    ),
  ];

  static const _members = [
    IdentityRef(
      displayName: 'Alan Turing',
      uniqueName: 'alan@example.com',
      id: '44444444-4444-4444-8444-444444444444',
    ),
    IdentityRef(
      displayName: 'Katherine Johnson',
      uniqueName: 'katherine@example.com',
      id: '55555555-5555-4555-8555-555555555555',
    ),
    IdentityRef(
      displayName: 'Barbara Liskov',
      uniqueName: 'barbara@example.com',
      id: '66666666-6666-4666-8666-666666666666',
    ),
  ];

  /// Directory hits carry no identity id, the way `graph/subjectquery`
  /// answers (r3 §3): picking one goes through [MentionSource.resolve].
  static const _directory = [
    IdentityRef(
      displayName: 'Radia Perlman',
      uniqueName: 'radia@contoso.com',
      descriptor: 'aad.example1',
    ),
    IdentityRef(
      displayName: 'Margaret Hamilton',
      uniqueName: 'margaret@contoso.com',
      descriptor: 'aad.example2',
    ),
  ];

  static const _workItems = [
    ArtifactSuggestion(
      MentionKind.workItem,
      '15545',
      'Mentions: the composer picker',
      typeName: 'Task',
      state: 'Active',
    ),
    ArtifactSuggestion(
      MentionKind.workItem,
      '15546',
      'Comment box loses the caret after a pick',
      typeName: 'Bug',
      state: 'New',
    ),
    ArtifactSuggestion(
      MentionKind.workItem,
      '15547',
      'Notification relay: mention routing',
      typeName: 'User Story',
      state: 'Resolved',
    ),
    ArtifactSuggestion(
      MentionKind.workItem,
      '15548',
      'An unknown type draws the neutral tile',
      typeName: 'Widget',
      state: 'New',
    ),
  ];

  static const _pullRequests = [
    ArtifactSuggestion(
      MentionKind.pullRequest,
      '8334',
      'Mentions in the work item discussion',
      state: 'Active',
    ),
    ArtifactSuggestion(
      MentionKind.pullRequest,
      '8336',
      'Diff view: anchored thread composer',
      state: 'Active',
    ),
  ];

  final _controller = MentionController();

  /// Flipped from the app bar to exercise the offline and failure paths
  /// without turning Wi-Fi off.
  bool _searchFails = false;
  bool _resolveFails = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MentionSource get _source => MentionSource(
    participants: () async => _participants,
    participantReason: 'On this item',
    recents: () async => _recents,
    members: () async => _members,
    search: (query) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_searchFails) {
        throw const AdoNetworkException('No connection to dev.azure.com.');
      }
      final lower = query.toLowerCase();
      return [
        for (final person in _directory)
          if (person.displayName.toLowerCase().contains(lower) ||
              (person.uniqueName ?? '').toLowerCase().contains(lower))
            person,
      ];
    },
    resolve: (person) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (_resolveFails) {
        throw const AdoNotFoundException('That person is not in this project.');
      }
      return IdentityRef(
        displayName: person.displayName,
        uniqueName: person.uniqueName,
        descriptor: person.descriptor,
        id: '77777777-7777-4777-8777-777777777777',
      );
    },
    workItems: (query) async {
      final lower = query.toLowerCase();
      return [
        for (final item in _workItems)
          if (item.id.startsWith(query) ||
              item.title.toLowerCase().contains(lower))
            item,
      ];
    },
    pullRequests: (query) async {
      final lower = query.toLowerCase();
      return [
        for (final item in _pullRequests)
          if (item.id.startsWith(query) ||
              item.title.toLowerCase().contains(lower))
            item,
      ];
    },
    me: _recents.first,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mention probe (M-B)'),
        actions: [
          IconButton(
            tooltip: _searchFails ? 'Search fails: on' : 'Search fails: off',
            isSelected: _searchFails,
            icon: const Icon(Icons.wifi_off),
            onPressed: () => setState(() => _searchFails = !_searchFails),
          ),
          IconButton(
            tooltip: _resolveFails ? 'Resolve fails: on' : 'Resolve fails: off',
            isSelected: _resolveFails,
            icon: const Icon(Icons.person_off_outlined),
            onPressed: () => setState(() => _resolveFails = !_resolveFails),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: Spacing.page,
          children: [
            Text(
              'Type @ for people, # for work items, ! for pull requests. '
              'Participants first, then recents, then the team, then the '
              'directory (from two characters, 400 ms behind). A directory '
              'hit carries no identity id until it is picked.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.lg),
            MentionField(
              controller: _controller,
              source: _source,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Add a comment (Markdown)',
              ),
            ),
            MentionHint(controller: _controller),
            const SizedBox(height: Spacing.lg),
            Text('Wire form', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _controller.toWire(MentionWire.markdown),
                    style: BoardhopTheme.codeStyle(context),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    '${_controller.tokens.length} token(s): '
                    '${_controller.tokens.map((t) => t.label).join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xxl),
          ],
        ),
      ),
    );
  }
}
