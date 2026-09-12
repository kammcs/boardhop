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

  bool get isCamera => this == AttachmentPickSource.camera;
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

/// A readable name for a picked photo.
///
/// `image_picker` copies the file into the app's cache and names it after
/// the platform's own id — "19.png" from the Android photo picker, a
/// timestamped temp name from the camera — so a name that carries no
/// meaning is replaced by one that does, keeping the extension.
String photoFileName(String pickedName, {bool camera = false, DateTime? now}) {
  final extension = p.extension(pickedName).isEmpty
      ? '.jpg'
      : p.extension(pickedName);
  final stem = p.basenameWithoutExtension(pickedName);
  final meaningful = stem.length > 3 && !RegExp(r'^[0-9_-]+$').hasMatch(stem);
  if (meaningful) return pickedName;
  final stamp = DateFormat('yyyyMMdd-HHmmss')
      .format((now ?? DateTime.now()).toLocal());
  return '${camera ? 'photo' : 'image'}-$stamp$extension';
}

/// The "Add" sheet: camera, photo library or any file.
Future<AttachmentPickSource?> showAttachmentSourceSheet(BuildContext context) =>
    showModalBottomSheet<AttachmentPickSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.sm,
              ),
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
        ),
      ),
    );

/// Runs the platform picker. Returns null when the user backed out.
///
/// The size is read before the bytes, so a file over the cap is reported
/// without loading 60 MB into memory.
Future<PickedAttachment?> pickAttachment(AttachmentPickSource source) async {
  switch (source) {
    case AttachmentPickSource.camera:
    case AttachmentPickSource.library:
      final image = await ImagePicker().pickImage(
        source: source == AttachmentPickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
      if (image == null) return null;
      final size = await image.length();
      return PickedAttachment(
        name: photoFileName(image.name, camera: source.isCamera),
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
