import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../../core/util/format.dart';
import '../../../../data/repositories/work_item_form_repository.dart';
import '../../../../theme/theme.dart';

/// Where an attachment comes from (research/11 §4.3).
enum AttachmentPickSource {
  camera('Take photo', Icons.photo_camera_outlined),
  library('Choose from library', Icons.photo_library_outlined),
  file('Choose file', Icons.attach_file_outlined);

  const AttachmentPickSource(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A file the user picked, with its bytes — unless it is over the cap, in
/// which case it is never read into memory.
@immutable
class PickedAttachment {
  const PickedAttachment({required this.name, required this.size, this.bytes});

  final String name;
  final int size;

  /// Null when [size] is over [WorkItemFormRepository.maxAttachmentBytes].
  final Uint8List? bytes;

  bool get isTooLarge => bytes == null;
}

/// What the form says about a file Azure DevOps will not take: the simple
/// upload stops at 60 MB and the chunked protocol is unspecified
/// (research/01 §2.5).
String attachmentTooLargeMessage(String name, int size) =>
    '$name is ${formatBytes(size)}. Azure DevOps accepts attachments up to '
    '${formatBytes(WorkItemFormRepository.maxAttachmentBytes)}.';

/// A readable name for a picked photo: `photo-20260912-121503.jpg`.
///
/// `image_picker` copies the file into the app's cache under a name of its
/// own — `image_picker_<uuid>.jpg` on iOS, `19.png` from the Android photo
/// picker — and that name is what the attachment list and the Azure DevOps
/// web then show, so every camera and library pick is renamed after the
/// moment it was taken, keeping its extension. A file chosen through the
/// file picker keeps the name it has (iOS walkthrough).
///
/// [jpeg] forces `.jpg`, which the **camera** path needs: passing any
/// sizing to `image_picker` re-encodes the capture as JPEG whatever the
/// source format was (decision T5), and a `.png` name on JPEG bytes is what
/// the web would then show and what a download would save.
String photoFileName(String pickedName, {DateTime? now, bool jpeg = false}) {
  final extension = jpeg ? '.jpg' : p.extension(pickedName);
  final stamp = DateFormat('yyyyMMdd-HHmmss')
      .format((now ?? DateTime.now()).toLocal());
  return 'photo-$stamp${extension.isEmpty ? '.jpg' : extension}';
}

/// A name for an image the **Android keyboard** handed the field —
/// `keyboard-20260914-183012.png` (decision T10).
///
/// Gboard's image button delivers bytes and a MIME type, never a file name,
/// so the extension comes off the MIME type and the name off the clock, the
/// same shape [photoFileName] gives a camera pick.
String keyboardFileName(String mimeType, {DateTime? now}) {
  final subtype = mimeType.split('/').last.split(';').first.trim();
  final stamp = DateFormat('yyyyMMdd-HHmmss')
      .format((now ?? DateTime.now()).toLocal());
  return 'keyboard-$stamp.${subtype.isEmpty ? 'png' : subtype}';
}

/// What `contentInsertionConfiguration` accepts from the keyboard: the
/// image types Azure DevOps renders inline, which is also Flutter's own
/// default list (`editable_text.dart`).
const keyboardImageMimeTypes = <String>[
  'image/png',
  'image/bmp',
  'image/jpg',
  'image/tiff',
  'image/gif',
  'image/jpeg',
  'image/webp',
];

/// Where to take the file from: camera, photo library or any file.
///
/// A phone opens the bottom sheet; from medium up it is the centered dialog
/// the form's other pickers use, rather than a sheet pinned to the screen
/// edge behind the tablet's own dialog (iPad walkthrough).
Future<AttachmentPickSource?> showAttachmentSourceSheet(BuildContext context) {
  if (!context.breakpoint.isCompact) {
    return showDialog<AttachmentPickSource>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: _sourceList(context),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<AttachmentPickSource>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SafeArea(top: false, child: _sourceList(context)),
  );
}

Widget _sourceList(BuildContext context) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
      child: Text(
        'Add attachment',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
    for (final source in AttachmentPickSource.values)
      ListTile(
        leading: Icon(source.icon),
        title: Text(source.label),
        onTap: () => Navigator.of(context).pop(source),
      ),
    const SizedBox(height: Spacing.sm),
  ],
);

/// Runs the platform picker. Returns null when the user backed out.
///
/// The size is read before the bytes, so a file over the cap is reported
/// without loading 60 MB into memory.
Future<PickedAttachment?> pickAttachment(AttachmentPickSource source) async {
  switch (source) {
    case AttachmentPickSource.camera:
    case AttachmentPickSource.library:
      final camera = source == AttachmentPickSource.camera;
      // Decision T5: the camera only. A 12 MP capture is 4-6 MB for no
      // benefit in a comment, while a library pick is usually a screenshot
      // where legibility matters and re-encoding is a trap (Android makes
      // `imageQuality` a no-op on an image with alpha but re-encodes an
      // alpha-free PNG as JPEG the moment any sizing is passed). The
      // 60 MB guard below stays the real boundary, never this.
      final image = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: camera ? 2048 : null,
        maxHeight: camera ? 2048 : null,
        imageQuality: camera ? 85 : null,
      );
      if (image == null) return null;
      final size = await image.length();
      return PickedAttachment(
        name: photoFileName(image.name, jpeg: camera),
        size: size,
        bytes: size > WorkItemFormRepository.maxAttachmentBytes
            ? null
            : await image.readAsBytes(),
      );
    case AttachmentPickSource.file:
      final result = await FilePicker.platform.pickFiles();
      final file = result?.files.firstOrNull;
      if (file == null) return null;
      final path = file.path;
      final size = file.size;
      if (size > WorkItemFormRepository.maxAttachmentBytes) {
        return PickedAttachment(name: file.name, size: size);
      }
      final bytes =
          file.bytes ?? (path == null ? null : await File(path).readAsBytes());
      if (bytes == null) return null;
      return PickedAttachment(name: file.name, size: size, bytes: bytes);
  }
}
