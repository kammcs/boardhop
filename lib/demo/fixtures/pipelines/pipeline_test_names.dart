// Test names from the repository, for the demo `flutter test` log.
const demoTestNames = <(String, String)>[
  (
    'test/startup_failure_test.dart',
    'a startup failure shows its message instead of a splash',
  ),
  ('test/core/routes_test.dart', 'a comment anchor and a tab travel together'),
  (
    'test/core/plain_text_test.dart',
    'a mention anchor becomes @Name, with no doubled @',
  ),
  (
    'test/core/router_test.dart',
    'the standalone work item route is matched outside the tab shell',
  ),
  ('test/core/wiki_link_test.dart', 'anything that is not a wiki URL is null'),
  (
    'test/core/wiki_link_test.dart',
    'a relative .attachments path names the same file',
  ),
  (
    'test/core/display_cutout_test.dart',
    'a platform with no display channel answers unknown',
  ),
  (
    'test/core/launch_redirect_test.dart',
    'the launch resolves once per auth state change',
  ),
  (
    'test/core/mention_test.dart',
    'a version:2.0 anchor is a person and is not tappable',
  ),
  (
    'test/core/ado_client_test.dart',
    'maps 401 with insufficient_claims to ClaimsChallengeException ',
  ),
  ('test/features/pr_detail_actions_test.dart', 'an active pull request'),
  (
    'test/features/child_type_test.dart',
    'a type on no backlog falls back to the task level',
  ),
  ('test/features/project_picker_test.dart', 'Activity carries the unread dot'),
  (
    'test/features/task_card_sheet_test.dart',
    'skips the current column and the unreachable ones',
  ),
  (
    'test/features/diff_prefs_test.dart',
    'an empty account writes nothing rather than a shared key',
  ),
  ('test/features/wiki_prefs_test.dart', 'start empty'),
  (
    'test/features/wiki_tree_page_test.dart',
    'the tree starts collapsed with no last path',
  ),
  (
    'test/features/wiki_tree_page_test.dart',
    'the tree keeps a pane and the page sits beside it (K6)',
  ),
  (
    'test/features/glass_navigation_rail_test.dart',
    'is sized to its destinations and reports taps',
  ),
  (
    'test/features/diff_probe_test.dart',
    'classic Myers example ABCABBA → CBABAC',
  ),
  ('test/features/wiki_markdown_test.dart', 'a flow list and quoted values'),
  (
    'test/features/wiki_markdown_test.dart',
    'a pipe table is captured whole for the wiki table builder',
  ),
  (
    'test/features/wiki_markdown_test.dart',
    'the find count is case-insensitive and non-overlapping',
  ),
  ('test/features/wiki_markdown_test.dart', 'it draws in dark too'),
  (
    'test/features/sprint_header_test.dart',
    'tiles, sparkline, verdict and dates',
  ),
  (
    'test/features/work_item_form_edit_test.dart',
    'a title and priority change patch those two fields only',
  ),
  (
    'test/features/launch_resolver_test.dart',
    'an organization with no projects is skipped',
  ),
  (
    'test/features/work_item_detail_fields_test.dart',
    'an emptied HTML field counts as empty, an image does not',
  ),
  (
    'test/features/mention_markdown_image_test.dart',
    'a failure to open is shown as a snackbar',
  ),
  (
    'test/features/board_new_item_test.dart',
    'a column that does not map the type has no state',
  ),
  (
    'test/features/mention_field_test.dart',
    'Escape closes the list and leaves the text alone',
  ),
  (
    'test/features/mention_field_test.dart',
    'names the hand-typed word, and clears when it is picked',
  ),
  ('test/features/attachments_section_test.dart', 'it is the documented 60 MB'),
  (
    'test/features/attachments_section_test.dart',
    'a failed commit tells the user to Save',
  ),
  ('test/features/dashboard_cards_test.dart', 'a refusal is inline'),
  (
    'test/features/dashboard_cards_test.dart',
    'hides a widget whose typed settings do not parse',
  ),
  (
    'test/features/push_prefs_section_test.dart',
    'shows a row for every preference of research/14 §6',
  ),
  (
    'test/features/thread_card_edit_delete_like_test.dart',
    'a refused edit keeps the editor open with the text in it',
  ),
  (
    'test/features/pipelines_approval_anchor_test.dart',
    '?tab=approvals&approval={id} opens the tab on that approval',
  ),
  (
    'test/features/pull_request_tile_test.dart',
    'a required reviewer is told so',
  ),
  (
    'test/features/work_item_form_test.dart',
    'an empty title blocks Create locally',
  ),
  (
    'test/features/comment_composer_attachments_test.dart',
    'is there with a source, left of Send',
  ),
  (
    'test/features/comment_composer_attachments_test.dart',
    'an inserted image becomes a chip',
  ),
  (
    'test/features/push_feed_insert_test.dart',
    'what happens to a pull request of mine is prMine',
  ),
  (
    'test/features/push_feed_insert_test.dart',
    'a fetched copy of the same key wins over the pushed one',
  ),
  (
    'test/features/mention_controller_test.dart',
    'never opens inside an e-mail address',
  ),
  (
    'test/features/mention_controller_test.dart',
    'backspacing the last character of the run breaks it',
  ),
  ('test/features/diagnostics_gate_test.dart', 'a store build has no bug icon'),
  (
    'test/features/dashboard_page_test.dart',
    'pull-to-refresh refetches and asks every card to reload',
  ),
  (
    'test/features/drag_session_test.dart',
    'the band starts below the header, not at the top',
  ),
  (
    'test/features/push_background_test.dart',
    'round-trips through the pointer',
  ),
  (
    'test/features/mention_suggestions_test.dart',
    'the suggestion carries the ranges for its display name',
  ),
  ('test/features/sprint_page_test.dart', 'choosing a tab remembers it'),
  ('test/features/sprint_page_test.dart', 'and neither does the phone board'),
  (
    'test/features/sprint_page_test.dart',
    'Move to another sprint patches the iteration path (S3)',
  ),
  (
    'test/features/pr_merge_box_test.dart',
    'the sheet opens on the options the service remembered',
  ),
  (
    'test/features/pending_attachments_test.dart',
    'no remover at all leaves the chips without a delete button',
  ),
  (
    'test/features/dashboard_chart_cards_test.dart',
    'a team with no sprints says so instead of a chart',
  ),
  (
    'test/features/dashboard_chart_cards_test.dart',
    'every chart kind and every built-in has a card',
  ),
  (
    'test/features/search_page_test.dart',
    'nothing is sent under three characters',
  ),
  ('test/features/search_page_test.dart', 'only the named kind is searched'),
  (
    'test/features/search_page_test.dart',
    'the See-all list pages as it is scrolled',
  ),
  ('test/features/wiki_page_view_test.dart', 'the overflow offers Open on web'),
  (
    'test/features/pr_reviewers_section_test.dart',
    'the creator cannot decline their own pull request (HTTP 500)',
  ),
  ('test/features/push_account_mirror_test.dart', 'no organization, no call'),
  (
    'test/features/glass_shell_layout_test.dart',
    'the keyboard covers the bar, and shortens the page above it',
  ),
  (
    'test/features/links_section_test.dart',
    'the same link is never added twice',
  ),
  (
    'test/features/push_registrar_test.dart',
    'a relay that answers nonsense is not remembered',
  ),
  (
    'test/features/wiki_page_picker_test.dart',
    'inserts the picked page at the caret and posts it',
  ),
  (
    'test/features/walkthrough_findings_test.dart',
    'the column follows the text scale, capped at 2x',
  ),
  ('test/features/diff_side_by_side_test.dart', 'a phone opens unified'),
  (
    'test/features/thread_card_test.dart',
    'a posted reply takes the keyboard with it',
  ),
  (
    'test/features/story_chip_strip_test.dart',
    'All, Unparented first, then the stories',
  ),
  (
    'test/features/push_registration_timing_test.dart',
    'answers at once when the Runner already holds a token',
  ),
  (
    'test/features/sprint_burndown_chart_test.dart',
    'non-working days are banded',
  ),
  (
    'test/features/diff_left_side_threads_test.dart',
    'a file-level thread renders above the first hunk (R9)',
  ),
  (
    'test/features/taskboard_grid_test.dart',
    'draws sticky column headers, row headers and cells',
  ),
  (
    'test/features/diff_nav_test.dart',
    'at the last file both ends read Back to files',
  ),
  (
    'test/features/diff_nav_test.dart',
    'n and p step comments, switching the mode with them',
  ),
  (
    'test/features/comment_attachment_render_test.dart',
    'an html comment with no text falls back to renderedText',
  ),
  (
    'test/features/mention_sources_test.dart',
    'a work item lists its commenters newest first, then the people ',
  ),
  (
    'test/features/push_pointer_test.dart',
    'a missing project and title are tolerated',
  ),
  ('test/features/push_pointer_test.dart', 'thread on a pull request'),
  (
    'test/features/push_pointer_test.dart',
    'the group is the artifact family in that organization',
  ),
  (
    'test/features/pull_requests/diff_model_test.dart',
    'a change at the very first row starts at index 0',
  ),
  (
    'test/features/attachment_links_test.dart',
    'a name with no extension, and a dotfile',
  ),
  ('test/data/git_history_test.dart', 'GitCompare keeps counts and files only'),
  (
    'test/data/work_item_repository_test.dart',
    'is cached and the second call makes no request',
  ),
  (
    'test/data/work_item_repository_test.dart',
    'the artifact url is built the way the service stores it',
  ),
  (
    'test/data/git_repository_test.dart',
    'parses a listing child and a single item with metadata',
  ),
  (
    'test/data/pull_request_repository_test.dart',
    'setAutoComplete names the signed-in identity',
  ),
  (
    'test/data/pull_request_repository_test.dart',
    'leftSide anchors on the original side',
  ),
  (
    'test/data/search_models_test.dart',
    'a tag that straddles the marker cannot swallow the match',
  ),
  (
    'test/data/search_models_test.dart',
    'no facets at all is empty, and round trips',
  ),
  (
    'test/data/work_item_form_ops_test.dart',
    'removals are indices from the fresh read, highest first',
  ),
  ('test/data/work_item_form_ops_test.dart', 'the title search escapes quotes'),
  (
    'test/data/push_prefs_test.dart',
    'a value outside its list falls back rather than throwing',
  ),
  (
    'test/data/work_item_form_layout_test.dart',
    'a page with no labeled group keeps one anonymous group',
  ),
  (
    'test/data/work_item_form_spec_test.dart',
    'comes from the xmlForm and keeps the type',
  ),
  (
    'test/data/work_item_form_spec_test.dart',
    'custom fields group together, backlog field names are honoured',
  ),
  ('test/data/dashboard_layout_test.dart', 'a 1120 dp tablet gets six'),
  (
    'test/data/dashboard_layout_test.dart',
    'two three-wide charts share a row when nothing precedes them',
  ),
  (
    'test/data/people_repository_test.dart',
    'reads vssps identities and caches the answer',
  ),
  (
    'test/data/activity_test.dart',
    'merge drops duplicates and sorts newest first',
  ),
  ('test/data/search_repository_test.dart', 'is cached like the other kinds'),
  (
    'test/data/search_repository_test.dart',
    'the cached matcher runs without a call',
  ),
  (
    'test/data/analytics_repository_test.dart',
    'falls back to the team GUID when Analytics knows nothing',
  ),
  (
    'test/data/analytics_repository_test.dart',
    'an empty window has no averages at all',
  ),
  (
    'test/data/viewed_files_store_test.dart',
    'a new blob for the same path clears the mark',
  ),
  (
    'test/data/sprint_repository_test.dart',
    'guards the scheduling fields by the org field list',
  ),
  (
    'test/data/sprint_repository_test.dart',
    'move sends the state patch and then the column call',
  ),
  (
    'test/data/wiki_models_test.dart',
    'siblings come out in .order order, not the service\\',
  ),
  ('test/data/wiki_models_test.dart', 'a code wiki\\'),
  ('test/data/mention_recents_test.dart', 'only the last five are kept'),
  (
    'test/data/wiki_repository_test.dart',
    'caches the joined tree and serves it back with the ids',
  ),
  (
    'test/data/wiki_repository_test.dart',
    'is cached, and a file with no history is null',
  ),
  (
    'test/data/pipeline_models_test.dart',
    'flattens the Phase wrapper and sorts siblings by order',
  ),
  (
    'test/data/sprint_models_test.dart',
    'a Completed column is the done column',
  ),
  (
    'test/data/sprint_models_test.dart',
    'a sprint the service still calls current can have ended (S12)',
  ),
  ('test/data/dashboard_models_test.dart', 'an unknown scope does not throw'),
  (
    'test/data/dashboard_models_test.dart',
    'Build History: the definition id is a string, or comes off the uri',
  ),
  ('test/data/identity_avatar_test.dart', 'an explicit descriptor still wins'),
  (
    'test/data/dashboard_repository_test.dart',
    'asks the org-level Favorites API for dashboards',
  ),
  ('test/data/work_item_models_test.dart', 'parses columns, fields and types'),
  (
    'test/data/work_item_models_test.dart',
    'keeps the Person targets the service stamped',
  ),
  (
    'test/data/pull_request_models_test.dart',
    'reads required, flagged, declined and the teams voted for',
  ),
  (
    'test/data/pull_request_models_test.dart',
    'no merge-strategy policy allows all four',
  ),
];
