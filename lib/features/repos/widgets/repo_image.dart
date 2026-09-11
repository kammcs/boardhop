import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/http/ado_exceptions.dart';
import '../../../data/repositories/repo_repository.dart';
import '../../../theme/theme.dart';

/// An image stored in a repository, fetched through the Items API with the
/// bearer token (plain `Image.network` cannot reach it). Bytes stay in a
/// small in-memory cache so a README re-render or a back navigation does
/// not download them twice.
class RepoImage extends StatefulWidget {
  const RepoImage({
    super.key,
    required this.org,
    required this.project,
    required this.repoId,
    required this.ref,
    required this.path,
    this.alt,
    this.fit = BoxFit.contain,
    this.zoomable = false,
  });

  final String org;
  final String project;
  final String repoId;
  final String ref;
  final String path;
  final String? alt;
  final BoxFit fit;

  /// Wraps the image in an [InteractiveViewer] (file viewer).
  final bool zoomable;

  @override
  State<RepoImage> createState() => _RepoImageState();
}

class _RepoImageState extends State<RepoImage> {
  static final _memory = <String, Uint8List>{};
  static const _memoryLimit = 24;

  Uint8List? _bytes;
  String? _error;

  String get _key => '${widget.repoId}:${widget.ref}:${widget.path}';

  @override
  void initState() {
    super.initState();
    _bytes = _memory[_key];
    if (_bytes == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(RepoImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.ref != widget.ref) {
      _bytes = _memory[_key];
      _error = null;
      if (_bytes == null) _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await context.read<RepoRepository>().fileBytes(
        widget.org,
        widget.project,
        widget.repoId,
        ref: widget.ref,
        path: widget.path,
      );
      if (_memory.length >= _memoryLimit) _memory.remove(_memory.keys.first);
      _memory[_key] = bytes;
      if (mounted) setState(() => _bytes = bytes);
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = _bytes;
    if (bytes != null) {
      final image = Image.memory(
        bytes,
        fit: widget.fit,
        semanticLabel: widget.alt,
        errorBuilder: (_, _, _) => _Placeholder(
          icon: Icons.broken_image_outlined,
          text: 'Could not decode ${widget.alt ?? widget.path}.',
        ),
      );
      if (!widget.zoomable) return image;
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 8,
        child: Center(child: image),
      );
    }
    if (_error != null) {
      return _Placeholder(
        icon: Icons.broken_image_outlined,
        text: _error!,
        color: scheme.error,
      );
    }
    return const _Placeholder(
      icon: Icons.image_outlined,
      text: 'Loading image…',
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: Radii.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
