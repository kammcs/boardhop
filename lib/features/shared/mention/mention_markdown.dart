import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/text/mention.dart';
import '../attachments/attachment_links.dart';
import '../attachments/inline_attachments.dart';
import 'mention_style.dart';

/// A Markdown body that draws mentions: `@<guid>` as the person's name,
/// `#123` and `!456` as tappable references (research/16 M9 and M10).
///
/// A pull request comment is stored verbatim, so unlike a work item comment
/// there is no server-rendered form to lean on: the GUID has to be resolved
/// and the references linked here. [names] carries what the host already
/// knows (a pull request's author, reviewers and comment authors cover most
/// of it for free); a GUID nobody answers for reads `@someone`, never the
/// raw GUID.
class MentionMarkdown extends StatelessWidget {
  const MentionMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.names = const {},
    this.onOpen,
    this.attachments,
  });

  final String data;
  final bool selectable;

  /// Lower-cased identity GUID → display name.
  final Map<String, String> names;

  /// Tapping `#123` or `!456`. Null leaves them styled but inert.
  final void Function(MentionKind kind, String id)? onOpen;

  /// The bearer token for the attachment images in this body and the way to
  /// open one (research/17 §4). Null renders an image through the plain
  /// network loader, which cannot reach an Azure DevOps attachment — so a
  /// host that shows comments should always pass this.
  final InlineAttachments? attachments;

  @override
  Widget build(BuildContext context) {
    return MentionScope(
      names: names,
      child: MarkdownBody(
        data: data,
        selectable: selectable,
        // Every link, ours included, wears the mention style: the stock
        // sheet hard-codes `Colors.blue`, which DESIGN §3 does not allow.
        styleSheet: MarkdownStyleSheet(a: mentionTextStyle(context)),
        inlineSyntaxes: [MentionSyntax()],
        builders: {MentionSyntax.personTag: MentionPersonBuilder()},
        // Without this an attachment image is an empty `SizedBox`: the
        // package's default builder is a bare `Image.network` with a silent
        // error builder, and the fetch needs the bearer token
        // (research/17 §1, bug (b)).
        imageBuilder: (uri, title, alt) => InlineMarkdownImage(
          url: uri.toString(),
          alt: alt,
          attachments: attachments,
        ),
        onTapLink: (text, href, title) {
          final target = MentionHref.parse(href);
          if (target != null) {
            onOpen?.call(target.$1, target.$2);
            return;
          }
          // A file in a comment is an ordinary Markdown link, and a browser
          // could not authenticate it — it opens through the share sheet
          // instead (decision T9). Every other link stays as it was.
          if (isAttachmentUrl(href)) {
            openInlineAttachment(context, href!, attachments);
          }
        },
      ),
    );
  }
}

/// The resolved display names available to the [MentionPersonBuilder]s below.
///
/// An inherited widget rather than a constructor argument because
/// `MarkdownBody` builds its children once, in `didChangeDependencies`, and
/// rebuilds them only when its data or style sheet changes: a name that
/// arrives from the network afterwards would otherwise never be drawn. The
/// builder reads this from the `MarkdownBody`'s own context, so a new map
/// re-parses the body exactly once.
class MentionScope extends InheritedWidget {
  const MentionScope({super.key, required this.names, required super.child});

  final Map<String, String> names;

  static MentionScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MentionScope>();

  /// The name behind a GUID, or null when nobody has answered for it.
  static String? nameOf(BuildContext context, String guid) =>
      of(context)?.names[Mentions.identityId(guid)];

  @override
  bool updateShouldNotify(MentionScope old) => !mapEquals(old.names, names);
}

/// The link a reference is given, so the tap comes back with the kind and
/// the id rather than a URL somebody has to parse twice.
abstract final class MentionHref {
  static const scheme = 'boardhop-mention';

  static String of(MentionKind kind, String id) => '$scheme:${kind.name}/$id';

  static (MentionKind, String)? parse(String? href) {
    if (href == null || !href.startsWith('$scheme:')) return null;
    final rest = href.substring(scheme.length + 1).split('/');
    if (rest.length != 2) return null;
    for (final kind in MentionKind.values) {
      if (kind.name == rest.first) return (kind, rest.last);
    }
    return null;
  }
}

/// `@<guid>`, `#123` and `!456` inside a Markdown body.
///
/// The patterns are [Mentions]' own, so "a mention" means the same thing in
/// the composer, on the read side and in the relay. A person becomes an
/// element the [MentionPersonBuilder] draws (there is no person page, so it
/// must not be a link, M9); a reference becomes an ordinary Markdown link
/// with a [MentionHref], which is what makes `flutter_markdown_plus` manage
/// the tap recogniser's lifetime for us.
class MentionSyntax extends md.InlineSyntax {
  MentionSyntax() : super(_pattern);

  /// The element tag a person mention is parsed into.
  static const personTag = 'boardhopMention';

  /// The attribute carrying the lower-cased identity GUID.
  static const guidAttribute = 'guid';

  static final _pattern =
      '${Mentions.personAngle.pattern}'
      '|${Mentions.workItemRef.pattern}'
      '|${Mentions.pullRequestRef.pattern}';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final guid = match[1];
    if (guid != null) {
      parser.addNode(
        md.Element.empty(personTag)
          ..attributes[guidAttribute] = Mentions.identityId(guid),
      );
      return true;
    }
    final workItem = match[2];
    final id = workItem ?? match[3]!;
    final kind = workItem != null
        ? MentionKind.workItem
        : MentionKind.pullRequest;
    parser.addNode(
      md.Element.text('a', match[0]!)
        ..attributes['href'] = MentionHref.of(kind, id),
    );
    return true;
  }
}

/// Draws a person mention as a styled, untappable `@Name` run.
///
/// Returning a `Text.rich` rather than a widget of its own is deliberate:
/// `flutter_markdown_plus` merges adjacent text widgets into one rich text,
/// so the run flows and wraps with the sentence around it instead of
/// becoming an island in a `Wrap`.
class MentionPersonBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final guid = element.attributes[MentionSyntax.guidAttribute] ?? '';
    final style = (parentStyle ?? const TextStyle()).merge(
      mentionTextStyle(context),
    );
    return Text.rich(
      TextSpan(
        text: Mentions.personLabel(MentionScope.nameOf(context, guid)),
        style: style,
      ),
    );
  }
}
