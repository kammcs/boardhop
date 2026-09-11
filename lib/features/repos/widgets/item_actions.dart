import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/git_repository.dart';
import '../../shared/account_scope.dart';

/// Icon for a tree entry, by extension. Plain and few, like the web.
IconData itemIcon(GitItem item) {
  if (item.isFolder) return Icons.folder;
  return switch (item.extension) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'svg' ||
    'ico' => Icons.image_outlined,
    'md' || 'markdown' || 'txt' || 'rst' || 'adoc' => Icons.article_outlined,
    'json' ||
    'yaml' ||
    'yml' ||
    'xml' ||
    'toml' ||
    'ini' ||
    'csproj' ||
    'props' ||
    'plist' ||
    'config' => Icons.data_object,
    'zip' ||
    'gz' ||
    'tar' ||
    '7z' ||
    'jar' ||
    'nupkg' => Icons.folder_zip_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'sh' || 'ps1' || 'bat' || 'cmd' => Icons.terminal,
    'lock' => Icons.lock_outline,
    '' => Icons.insert_drive_file_outlined,
    _ => Icons.code,
  };
}

/// Shared "…" actions for files and folders: history, copy path, copy
/// link, open in browser. Also the long-press menu on tree rows.
Future<void> showItemActions(
  BuildContext context, {
  required String org,
  required String project,
  required GitRepository repo,
  required String ref,
  required String path,
  required bool isFolder,
}) {
  final normalized = RepoPaths.normalize(path);
  final webUrl = isFolder
      ? RepoWebUrls.folder(repo, normalized, ref)
      : RepoWebUrls.file(repo, normalized, ref);
  final base =
      '${projectRoute(context, org, project)}'
      '/repos/${Uri.encodeComponent(repo.name)}';
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              isFolder ? Icons.folder : Icons.insert_drive_file_outlined,
            ),
            title: Text(
              normalized == '/' ? repo.name : normalized,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            onTap: () {
              Navigator.of(sheet).pop();
              router.push(
                '$base/commits?ref=${Uri.encodeQueryComponent(ref)}'
                '&path=${Uri.encodeQueryComponent(normalized)}',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_copy),
            title: const Text('Copy path'),
            onTap: () async {
              Navigator.of(sheet).pop();
              await Clipboard.setData(ClipboardData(text: normalized));
              messenger.showSnackBar(
                const SnackBar(content: Text('Path copied.')),
              );
            },
          ),
          if (webUrl != null) ...[
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              onTap: () async {
                Navigator.of(sheet).pop();
                await Clipboard.setData(ClipboardData(text: webUrl));
                messenger.showSnackBar(
                  const SnackBar(content: Text('Link copied.')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open in browser'),
              onTap: () {
                Navigator.of(sheet).pop();
                launchUrl(
                  Uri.parse(webUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
