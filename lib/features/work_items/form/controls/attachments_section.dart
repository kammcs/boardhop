import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/util/format.dart';
import '../../../../data/models/work_item.dart';
import '../../../../data/models/work_item_form.dart';
import '../../../../theme/theme.dart';
import '../work_item_form_state.dart';
import 'attachment_picker.dart';

/// One row of the Attachments page, read off an `AttachedFile` relation
/// (spike w17): the name from `attributes.name`, the size from
/// `attributes.resourceSize` and the guid from the URL.
@immutable
class AttachmentInfo {
  const AttachmentInfo({
    required this.relation,
    required this.name,
    required this.url,
    this.id,
    this.size,
    this.comment,
  });

  factory AttachmentInfo.of(WorkItemRelation relation) {
    final id = relation.attachmentId;
    final url = relation.url;
    // The name lives in the attributes; the upload also puts it on the URL
    // as `?fileName=`, which is the fallback.
    final fromUrl = Uri.tryParse(url)?.queryParameters['fileName'];
    return AttachmentInfo(
      relation: relation,
      name: relation.name ?? (fromUrl?.isNotEmpty ?? false ? fromUrl! : 'File'),
      url: url,
      id: id,
      size: relation.resourceSize,
      comment: relation.comment,
    );
  }

  final WorkItemRelation relation;
  final String name;
  final String url;

  /// The attachment guid, which keys the byte cache.
  final String? id;
  final int? size;
  final String? comment;

  String get extension => p.extension(name).replaceFirst('.', '').toLowerCase();

  static const _imageExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
  };

  bool get isImage => _imageExtensions.contains(extension);

  /// A glyph for the kind of file, the same idea as the repo browser's.
  IconData get icon => switch (extension) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'zip' || 'gz' || '7z' || 'rar' => Icons.folder_zip_outlined,
    'txt' || 'md' || 'log' => Icons.description_outlined,
    'csv' || 'xls' || 'xlsx' => Icons.table_chart_outlined,
    'doc' || 'docx' => Icons.article_outlined,
    'mp4' || 'mov' || 'webm' => Icons.movie_outlined,
    'json' || 'xml' || 'yml' || 'yaml' => Icons.data_object_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// What the Attachments page needs, kept apart from the repositories so the
/// section can be built in a widget test.
class AttachmentSource {
  const AttachmentSource({
    required this.bytes,
    required this.upload,
    this.commit,
    this.headers = const {},
  });

  /// An attachment's bytes with the bearer token (spike w17).
  final Future<Uint8List> Function(String url) bytes;

  final Future<AttachmentRef> Function(String fileName, Uint8List bytes) upload;

  /// Edit mode: writes the pending relation change straight away, because
  /// an attachment on an existing item is not worth holding until Save
  /// (research/11 §4.3). Null on a new item, where it rides in the create
  /// patch instead. Answers false when the write failed.
  final Future<bool> Function()? commit;

  /// `Authorization` for the HTML renderer's embedded images.
  final Map<String, String> headers;
}

/// The Attachments panel: the item's files as image thumbnails and named
/// rows, with an add sheet (camera, library, any file) and a per-row
/// remove.
class AttachmentsSection extends StatefulWidget {
  const AttachmentsSection({
    super.key,
    required this.state,
    this.source,
    this.enabled = true,
  });

  final WorkItemFormState state;
  final AttachmentSource? source;
  final bool enabled;

  @override
  State<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<AttachmentsSection> {
  bool _busy = false;
  String? _message;

  Future<void> _add() async {
    final source = widget.source;
    if (source == null) return;
    final from = await showAttachmentSourceSheet(context);
    if (from == null || !mounted) return;
    PickedAttachment? picked;
    try {
      picked = await pickAttachment(from);
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not read the file: $e');
      return;
    }
    if (picked == null || !mounted) return;
    if (picked.isTooLarge) {
      setState(
        () => _message = attachmentTooLargeMessage(picked!.name, picked.size),
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final uploaded = await source.upload(picked.name, picked.bytes!);
      if (!mounted) return;
      widget.state.addRelation(
        WorkItemRelation(
          rel: WorkItemRelation.attachedFileRel,
          url: uploaded.url,
          attributes: {
            if (uploaded.fileName != null) 'name': uploaded.fileName,
            'resourceSize': picked.size,
          },
        ),
      );
      // On an existing item the relation is written at once, so an upload
      // is never left orphaned by a form the user then closes.
      final commit = source.commit;
      if (commit != null && !await commit()) {
        if (mounted) {
          setState(
            () => _message =
                'The file was uploaded but not attached yet; '
                'Save to attach it.',
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AttachmentInfo info) async {
    widget.state.removeRelation(info.relation);
    final commit = widget.source?.commit;
    if (commit == null) return;
    setState(() => _busy = true);
    try {
      if (!await commit() && mounted) {
        setState(() => _message = 'Save to remove it on the server.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(AttachmentInfo info) async {
    final source = widget.source;
    if (source == null) return;
    if (info.isImage) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => AttachmentViewer(info: info, source: source),
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await source.bytes(info.url);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, info.name));
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      // No `open_filex`: the share sheet is one dependency fewer and lets
      // the user hand the file to whatever app they have.
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], title: info.name),
      );
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not open the file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final source = widget.source;
    return AnimatedBuilder(
      animation: widget.state,
      // The list is read inside the builder: the notifier is what tells the
      // section a file was added or dropped.
      builder: (context, _) {
        final files = [
          for (final relation in widget.state.attachmentRelations)
            AttachmentInfo.of(relation),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (files.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Text(
                  'No attachments yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final info in files)
              AttachmentRow(
                key: ValueKey(info.relation.key),
                info: info,
                source: source,
                onOpen: source == null ? null : () => _open(info),
                onRemove: widget.enabled ? () => _remove(info) : null,
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 16, color: scheme.error),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        _message!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: OutlinedButton.icon(
                  onPressed: widget.enabled && source != null && !_busy
                      ? _add
                      : null,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Add'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One attachment: an image thumbnail or a type glyph, the name, the size,
/// and a remove button.
class AttachmentRow extends StatelessWidget {
  const AttachmentRow({
    super.key,
    required this.info,
    this.source,
    this.onOpen,
    this.onRemove,
  });

  final AttachmentInfo info;
  final AttachmentSource? source;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = [
      if (info.size != null) formatBytes(info.size),
      if (info.comment != null) info.comment!,
    ].join(' · ');
    return InkWell(
      onTap: onOpen,
      borderRadius: Radii.chip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: info.isImage && source != null
                  ? ClipRRect(
                      borderRadius: Radii.chip,
                      child: AttachmentImage(
                        info: info,
                        source: source!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: Radii.chip,
                      ),
                      child: Icon(info.icon, color: scheme.onSurfaceVariant),
                    ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.name,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove attachment',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

/// An attachment image fetched with the bearer token: `Image.network`
/// cannot reach it (spike w17 got the sign-in page instead of the PNG).
///
/// Bytes are kept by attachment id in a small in-memory map and in the
/// app's cache directory, so a thumbnail survives a rebuild and a restart.
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.info,
    required this.source,
    this.fit = BoxFit.contain,
    this.zoomable = false,
  });

  final AttachmentInfo info;
  final AttachmentSource source;
  final BoxFit fit;

  /// Pinch and pan (the full-screen viewer).
  final bool zoomable;

  /// Where the bytes are cached on disk. Null when the platform has no
  /// cache directory (a widget test).
  static Future<Directory?> cacheDirectory() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'attachments'));
      if (!dir.existsSync()) await dir.create(recursive: true);
      return dir;
    } catch (e) {
      debugPrint('attachment cache directory unavailable: $e');
      return null;
    }
  }

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  static final _memory = <String, Uint8List>{};
  static const _memoryLimit = 24;

  Uint8List? _bytes;
  String? _error;

  String get _key => widget.info.id ?? widget.info.url;

  @override
  void initState() {
    super.initState();
    _bytes = _memory[_key];
    if (_bytes == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(AttachmentImage old) {
    super.didUpdateWidget(old);
    if (old.info.url != widget.info.url) {
      _bytes = _memory[_key];
      _error = null;
      if (_bytes == null) _load();
    }
  }

  File? _file(Directory dir) {
    final id = widget.info.id;
    return id == null || id.isEmpty ? null : File(p.join(dir.path, id));
  }

  Future<void> _load() async {
    final dir = await AttachmentImage.cacheDirectory();
    final file = dir == null ? null : _file(dir);
    if (file != null && file.existsSync()) {
      try {
        final cached = await file.readAsBytes();
        _remember(cached);
        if (mounted) setState(() => _bytes = cached);
        return;
      } catch (_) {
        // Fall through to the network.
      }
    }
    try {
      final bytes = await widget.source.bytes(widget.info.url);
      _remember(bytes);
      if (file != null) {
        try {
          await file.writeAsBytes(bytes);
        } catch (_) {
          // A cache write failure is not worth telling the user about.
        }
      }
      if (mounted) setState(() => _bytes = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _remember(Uint8List bytes) {
    if (_memory.length >= _memoryLimit) _memory.remove(_memory.keys.first);
    _memory[_key] = bytes;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = _bytes;
    if (bytes != null) {
      final image = Image.memory(
        bytes,
        fit: widget.fit,
        semanticLabel: widget.info.name,
        errorBuilder: (_, _, _) =>
            Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
      );
      if (!widget.zoomable) return image;
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 8,
        child: Center(child: image),
      );
    }
    if (_error != null) {
      return Tooltip(
        message: _error!,
        child: Icon(Icons.broken_image_outlined, color: scheme.error),
      );
    }
    return Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.outline),
      ),
    );
  }
}

/// One image full screen, pinch to zoom.
class AttachmentViewer extends StatelessWidget {
  const AttachmentViewer({super.key, required this.info, required this.source});

  final AttachmentInfo info;
  final AttachmentSource source;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(info.name, overflow: TextOverflow.ellipsis),
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: AttachmentImage(info: info, source: source, zoomable: true),
    ),
  );
}
