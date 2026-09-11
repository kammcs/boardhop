import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/avatar_store.dart';
import '../../../data/models/work_item.dart';

/// The square Azure DevOps draws for an organization or a project: a
/// slightly rounded block in the color the web uses for that name, with the
/// picture when one is set and the initials otherwise. The initials are
/// painted first so the tile never flashes empty; the picture, when
/// [source] names one, replaces them once the [AvatarStore] has it.
class AdoTile extends StatefulWidget {
  const AdoTile({
    super.key,
    required this.name,
    required this.color,
    required this.initials,
    this.source,
    this.size = 40,
  });

  final String name;
  final Color color;
  final String initials;
  final AvatarSource? source;
  final double size;

  @override
  State<AdoTile> createState() => _AdoTileState();
}

class _AdoTileState extends State<AdoTile> {
  Uint8List? _bytes;
  AvatarSource? _source;

  AvatarStore? get _store {
    try {
      return context.read<AvatarStore>();
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(AdoTile old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _resolve();
  }

  void _resolve() {
    final source = widget.source;
    if (source == _source) return;
    _source = source;
    _bytes = null;
    final store = _store;
    if (source == null || store == null) return;
    final hit = store.cached(source);
    if (hit != null) {
      _bytes = hit;
      return;
    }
    store.load(source).then((bytes) {
      if (mounted && _source == source && bytes != null) {
        setState(() => _bytes = bytes);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final size = widget.size;
    return Semantics(
      label: widget.name,
      image: bytes != null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.1),
        child: SizedBox(
          width: size,
          height: size,
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
              : ColoredBox(
                  color: widget.color,
                  child: Center(
                    child: ExcludeSemantics(
                      child: Text(
                        widget.initials,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: size * 0.4,
                          fontWeight: FontWeight.w500,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
