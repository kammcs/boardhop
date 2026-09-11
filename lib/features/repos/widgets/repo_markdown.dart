import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/git_repository.dart';
import '../../shared/account_scope.dart';
import 'repo_image.dart';

/// Markdown from a repository (README, any `.md` file): repository-relative
/// images load through the Items API and repository-relative links open the
/// target file or folder in the app; absolute links go to the browser.
class RepoMarkdown extends StatelessWidget {
  const RepoMarkdown({
    super.key,
    required this.data,
    required this.org,
    required this.project,
    required this.repo,
    required this.ref,
    required this.path,
  });

  final String data;
  final String org;
  final String project;
  final GitRepository repo;
  final String ref;

  /// Path of the Markdown file itself; relative links resolve from its
  /// folder.
  final String path;

  static const _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'svg',
  };

  void _openLink(BuildContext context, String href) {
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    final target = RepoPaths.resolve(path, href);
    if (target == null) return;
    final base =
        '${projectRoute(context, org, project)}'
        '/repos/${Uri.encodeComponent(repo.name)}';
    final q =
        'ref=${Uri.encodeQueryComponent(ref)}'
        '&path=${Uri.encodeQueryComponent(target)}';
    // A link without an extension is most likely a folder.
    final leaf = RepoPaths.segments(target).lastOrNull ?? '';
    final isFile = leaf.contains('.');
    context.push('$base/${isFile ? 'file' : 'code'}?$q');
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: true,
      onTapLink: (text, href, title) {
        if (href != null) _openLink(context, href);
      },
      imageBuilder: (uri, title, alt) {
        if (uri.hasScheme) return Image.network(uri.toString());
        final target = RepoPaths.resolve(path, uri.toString());
        if (target == null) return const SizedBox.shrink();
        final ext = target.split('.').last.toLowerCase();
        if (!_imageExtensions.contains(ext)) return const SizedBox.shrink();
        return RepoImage(
          org: org,
          project: project,
          repoId: repo.id,
          ref: ref,
          path: target,
          alt: alt,
        );
      },
    );
  }
}
