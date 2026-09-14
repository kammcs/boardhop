import 'package:flutter/material.dart';

import '../../../core/http/ado_exceptions.dart';
import '../../../core/util/format.dart';
import '../../../theme/theme.dart';
import '../../work_items/form/controls/attachment_picker.dart';
import '../../work_items/form/controls/attachments_section.dart'
    show AttachmentInfo, AttachmentSource;
import 'attachment_links.dart';

/// One file a composer is holding: picked into memory, not uploaded yet.
///
/// Nothing is sent until Send (decision T3), so the whole life of an
/// attachment before that is these three values — the picked bytes, whether
/// its upload is in flight, and the service's own words when it refused.
@immutable
class PendingAttachment {
  const PendingAttachment({
    required this.picked,
    this.uploading = false,
    this.error,
  });

  final PickedAttachment picked;
  final bool uploading;

  /// The failure shown on the chip, verbatim from the service (T2).
  final String? error;

  String get name => picked.name;
  bool get isImage => AttachmentInfo.isImageNamed(picked.name);

  PendingAttachment copyWith({bool? uploading, String? error}) =>
      PendingAttachment(
        picked: picked,
        uploading: uploading ?? this.uploading,
        error: error,
      );
}

/// The strip of chips above a comment field (decision T7).
///
/// The same `Wrap` of `InputChip`s the form's tag sheet uses, so a file
/// waiting to be sent reads like every other removable thing in the app.
/// It wraps rather than scrolls, which is what keeps it whole at xxxL text.
class PendingAttachmentsBar extends StatelessWidget {
  const PendingAttachmentsBar({
    super.key,
    required this.attachments,
    this.onRemove,
  });

  final List<PendingAttachment> attachments;

  /// Null while the composer is busy: a file already on its way up cannot
  /// be taken back.
  final void Function(PendingAttachment attachment)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final a in attachments)
            _Chip(
              attachment: a,
              scheme: scheme,
              onRemove: a.uploading || onRemove == null
                  ? null
                  : () => onRemove!(a),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.attachment, required this.scheme, this.onRemove});

  final PendingAttachment attachment;
  final ColorScheme scheme;
  final VoidCallback? onRemove;

  /// 24 pt, the avatar slot's own size: an image previews itself from the
  /// bytes already in memory, so nothing is fetched to draw a chip.
  static const double _avatar = 24;

  Widget _leading() {
    if (attachment.uploading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (attachment.error != null) {
      return Icon(
        Icons.error_outline,
        size: 18,
        color: scheme.onErrorContainer,
      );
    }
    final bytes = attachment.picked.bytes;
    if (attachment.isImage && bytes != null) {
      return ClipRRect(
        borderRadius: Radii.chip,
        child: Image.memory(
          bytes,
          width: _avatar,
          height: _avatar,
          fit: BoxFit.cover,
          // A file named `.png` that is not one must still draw a chip.
          errorBuilder: (context, error, stack) =>
              Icon(AttachmentInfo.iconFor(attachment.name), size: 18),
        ),
      );
    }
    return Icon(AttachmentInfo.iconFor(attachment.name), size: 18);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = attachment.error;
    final chip = InputChip(
      avatar: _leading(),
      // Never a fixed width: the name ellipsises inside whatever the row
      // leaves it and the size stays readable at any text scale.
      label: Text(
        '${attachment.name} · ${formatBytes(attachment.picked.size)}',
        overflow: TextOverflow.ellipsis,
        style: failed == null
            ? null
            : theme.textTheme.labelMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
      ),
      backgroundColor: failed == null ? null : scheme.errorContainer,
      deleteIconColor: failed == null ? null : scheme.onErrorContainer,
      onDeleted: onRemove,
      // Only where there is a button to name: a chip whose upload is in
      // flight has no delete affordance at all.
      deleteButtonTooltipMessage: onRemove == null
          ? null
          : 'Remove ${attachment.name}',
    );
    if (failed == null) return chip;
    return Tooltip(message: failed, child: chip);
  }
}

/// The pending-file half of a comment composer, shared by all three
/// (decision T1): the work item Discussion box, a pull request thread reply
/// and the diff-line composer.
///
/// A mixin rather than a widget because the state belongs to the composer —
/// Send has to upload before it posts, and a failed upload has to leave the
/// text where it was — while everything above is the same three steps
/// everywhere: pick into a chip, upload each chip on Send, append one
/// Markdown line per upload (T8).
mixin ComposerAttachments<T extends StatefulWidget> on State<T> {
  final List<PendingAttachment> pending = [];

  /// The oversize message, shown under the chips rather than as a chip:
  /// a file the service will not take never becomes pending at all.
  String? attachmentError;

  /// Where an upload goes. Null — or a source with no `upload` — means this
  /// host cannot attach, and no button is drawn.
  AttachmentSource? get attachmentSource;

  /// Injected by the tests so a widget test never opens a platform picker.
  Future<PickedAttachment?> Function(AttachmentPickSource) get attachmentPick;

  /// Whether the host's last request could not reach the service (T6).
  bool get attachmentsOffline;

  /// What the host does with a comment whose files could not go but whose
  /// text still can: the work item queue takes the text and says which
  /// files were dropped. Null everywhere else, and then a failed upload
  /// posts nothing at all.
  void Function(int files)? get onAttachmentsDropped => null;

  bool get canAttach => attachmentSource?.upload != null;

  bool get uploadingAttachments => pending.any((a) => a.uploading);

  /// The button that opens the picker. Only drawn behind [canAttach];
  /// disabled — with the reason in its tooltip — while offline or while
  /// the composer is busy (T6).
  Widget attachButton({required bool busy}) {
    final blocked = busy || attachmentsOffline;
    return IconButton(
      tooltip: attachmentsOffline
          ? 'Attachments need a connection'
          : 'Attach a file',
      icon: const Icon(Icons.attach_file),
      onPressed: blocked ? null : pickIntoComposer,
    );
  }

  /// The chips plus, when the last pick was too big, the reason it is not
  /// among them.
  Widget attachmentsBar({required bool busy}) {
    if (pending.isEmpty && attachmentError == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PendingAttachmentsBar(
          attachments: pending,
          onRemove: busy ? null : removeAttachment,
        ),
        if (attachmentError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: Text(
              attachmentError!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  /// What the Android keyboard's image button inserts becomes a chip
  /// (decision T10). Null on every other platform and for text content.
  ContentInsertionConfiguration? get contentInsertion {
    if (!canAttach || attachmentsOffline) return null;
    return ContentInsertionConfiguration(
      allowedMimeTypes: keyboardImageMimeTypes,
      onContentInserted: insertKeyboardContent,
    );
  }

  void insertKeyboardContent(KeyboardInsertedContent content) {
    final data = content.data;
    // `data` is null when the platform handed over a URI the app would have
    // to fetch itself; there is nothing to attach then.
    if (data == null) return;
    addPicked(
      PickedAttachment(
        name: keyboardFileName(content.mimeType),
        size: data.length,
        bytes: data,
      ),
    );
  }

  /// The picker sheet, then the platform picker, then a chip. One file at a
  /// time; the strip accumulates (T7).
  Future<void> pickIntoComposer() async {
    final source = await showAttachmentSourceSheet(context);
    if (source == null || !mounted) return;
    final picked = await attachmentPick(source);
    if (picked == null || !mounted) return;
    addPicked(picked);
  }

  void addPicked(PickedAttachment picked) {
    if (picked.isTooLarge) {
      // Inline, in the error colour, exactly as the form reports it — and
      // no chip, because there is nothing that could be sent.
      setState(
        () => attachmentError = attachmentTooLargeMessage(
          picked.name,
          picked.size,
        ),
      );
      return;
    }
    setState(() {
      attachmentError = null;
      pending.add(PendingAttachment(picked: picked));
    });
  }

  void removeAttachment(PendingAttachment attachment) => setState(() {
    pending.remove(attachment);
    attachmentError = null;
  });

  void clearAttachments() => setState(() {
    pending.clear();
    attachmentError = null;
  });

  /// Uploads every chip in order and answers the body to post: the wire
  /// text with one `![name](url)` / `[name](url)` line per file (T8).
  ///
  /// Answers null when nothing should be posted — a failed upload keeps the
  /// text and the chips and paints the one that failed (T3). The exception
  /// is a host that queues offline: there the files are dropped, the host
  /// is told how many, and the text alone goes on to be queued (T6).
  Future<String?> bodyWithAttachments(String text) async {
    final upload = attachmentSource?.upload;
    if (pending.isEmpty || upload == null) return text;
    final links = <String>[];
    for (var i = 0; i < pending.length; i++) {
      final attachment = pending[i];
      final bytes = attachment.picked.bytes;
      if (bytes == null) continue;
      setState(() => pending[i] = attachment.copyWith(uploading: true));
      try {
        final ref = await upload(attachment.picked.name, bytes);
        links.add(
          attachmentMarkdown(
            // The label stays the name the user picked even where the
            // store needed a uniquified one in the URL.
            name: attachment.picked.name,
            url: ref.url,
            isImage: attachment.isImage,
          ),
        );
        if (!mounted) return null;
        setState(() => pending[i] = attachment.copyWith(uploading: false));
      } on AdoNetworkException catch (e) {
        if (!mounted) return null;
        final dropped = onAttachmentsDropped;
        // Nothing reached the service and nothing will until the connection
        // is back. Where the text can still be queued, it is — with the
        // count, so the host can say what did not go.
        if (dropped != null && text.isNotEmpty) {
          final count = pending.length;
          clearAttachments();
          dropped(count);
          return text;
        }
        setState(
          () => pending[i] = attachment.copyWith(
            uploading: false,
            error: e.message,
          ),
        );
        return null;
      } on AdoException catch (e) {
        if (!mounted) return null;
        setState(
          () => pending[i] = attachment.copyWith(
            uploading: false,
            error: e.message,
          ),
        );
        return null;
      }
    }
    return [text, ...links].where((s) => s.isNotEmpty).join('\n\n');
  }
}
