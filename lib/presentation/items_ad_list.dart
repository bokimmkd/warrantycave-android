import 'dart:async';

import 'package:flutter/material.dart';

import '../data/inline_banner.dart';

/// Native ad views are cached outside the lazy list. Only completed ads become
/// rows, and never while a pointer or scrolling gesture is in progress.
class ItemsAdList extends StatefulWidget {
  const ItemsAdList({super.key, required this.itemIds,
    required this.itemBuilder, required this.adsEnabled, this.active = true,
    this.bannerFactory = createInlineBanner});

  final List<String> itemIds;
  final IndexedWidgetBuilder itemBuilder;
  final bool adsEnabled;
  final bool active;
  final InlineBannerFactory bannerFactory;

  @override
  State<ItemsAdList> createState() => _ItemsAdListState();
}

class _Slot {
  _Slot(this.banner);
  final InlineBanner banner;
  Size? size;
  bool failed = false;
}

class _ItemsAdListState extends State<ItemsAdList> {
  static const _maxHeight = 250;
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _cardKeys = <String, GlobalKey>{};
  final _slots = <int, _Slot>{};
  final _shown = <int>{};
  final _pointers = <int>{};
  int _width = 0;
  int _generation = 0;
  bool _scheduled = false;
  bool _scrolling = false;

  @override
  void didUpdateWidget(covariant ItemsAdList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.adsEnabled && oldWidget.adsEnabled) _clearAds();
    if (widget.active && !oldWidget.active) {
      // Retry failed slots once on the next visit, never on a redraw.
      for (final number in _slots.keys.toList()) {
        if (_slots[number]!.failed) {
          _slots.remove(number)!.banner.dispose();
        }
      }
    }
    _cardKeys.removeWhere((id, _) => !widget.itemIds.contains(id));
  }

  void _clearAds() {
    _generation++;
    for (final slot in _slots.values) { slot.banner.dispose(); }
    _slots.clear();
    _shown.clear();
  }

  bool get _busy => _pointers.isNotEmpty || _scrolling ||
      (_scroll.hasClients && _scroll.position.isScrollingNotifier.value);

  void _schedule(int width) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (_width != width) {
        _clearAds();
        _width = width;
        setState(() {});
      }
      if (!widget.adsEnabled || !widget.active || width <= 0) return;
      final count = widget.itemIds.length ~/ 4;
      for (var number = 1; number <= count; number++) {
        if (_slots.containsKey(number)) continue;
        final slot = _Slot(widget.bannerFactory(width, _maxHeight));
        _slots[number] = slot;
        unawaited(_load(number, slot, _generation));
      }
      _publish();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _load(int number, _Slot slot, int generation) async {
    Size? size;
    try { size = await slot.banner.load(); } catch (_) { size = null; }
    if (!mounted || generation != _generation || _slots[number] != slot) return;
    if (size == null || size.height <= 0 || size.height > _maxHeight ||
        size.width <= 0 || size.width > _width) {
      slot.failed = true;
      slot.banner.dispose();
    } else {
      slot.size = size;
      _publish();
    }
  }

  void _publish() {
    if (!mounted || _busy || !widget.adsEnabled || !widget.active) return;
    final ready = _slots.entries.where((entry) =>
      entry.key * 4 <= widget.itemIds.length && entry.value.size != null &&
      !_shown.contains(entry.key)).map((entry) => entry.key).toList();
    if (ready.isEmpty) return;

    // Preserve the first visible warranty when a newly loaded row is inserted
    // above it. Pointer/ballistic scrolling gates also protect tap targets.
    final viewport = _viewportKey.currentContext?.findRenderObject();
    GlobalKey? anchor;
    double? oldY;
    if (viewport is RenderBox && viewport.hasSize) {
      final top = viewport.localToGlobal(Offset.zero).dy;
      final bottom = top + viewport.size.height;
      for (final id in widget.itemIds) {
        final key = _cardKeys[id];
        final box = key?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y + box.size.height > top && y < bottom) {
          anchor = key; oldY = y; break;
        }
      }
    }
    setState(() => _shown.addAll(ready));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _busy || !_scroll.hasClients || oldY == null) return;
      final box = anchor?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final delta = box.localToGlobal(Offset.zero).dy - oldY!;
      if (delta.abs() > 0.5) {
        _scroll.jumpTo((_scroll.offset + delta).clamp(
          _scroll.position.minScrollExtent, _scroll.position.maxScrollExtent));
      }
    });
  }

  @override
  void dispose() {
    _clearAds();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = (constraints.maxWidth - 40).floor();
    _schedule(width);
    final rows = <(String, int, bool)>[];
    for (var i = 0; i < widget.itemIds.length; i++) {
      rows.add(('item:${widget.itemIds[i]}', i, false));
      final number = (i + 1) ~/ 4;
      if ((i + 1) % 4 == 0 && width == _width && widget.adsEnabled && widget.active &&
          _shown.contains(number) && _slots[number]?.size != null) {
        rows.add(('ad:$number', number, true));
      }
    }
    final indices = {for (var i = 0; i < rows.length; i++) rows[i].$1: i};
    return Listener(
      onPointerDown: (event) => _pointers.add(event.pointer),
      onPointerUp: (event) { _pointers.remove(event.pointer); _schedule(_width); },
      onPointerCancel: (event) { _pointers.remove(event.pointer); _schedule(_width); },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0) return false;
          if (notification is ScrollStartNotification) _scrolling = true;
          if (notification is ScrollEndNotification) {
            _scrolling = false; _schedule(_width);
          }
          return false;
        },
        child: ListView.builder(
          key: _viewportKey,
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemCount: rows.length,
          findChildIndexCallback: (key) => key is ValueKey<String> ? indices[key.value] : null,
          itemBuilder: (context, index) {
            final (id, number, isAd) = rows[index];
            if (isAd) {
              final slot = _slots[number]!;
              return Padding(key: ValueKey(id),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Advertisement', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      SizedBox(width: slot.size!.width, height: slot.size!.height,
                        child: slot.banner.buildAd()),
                    ]),
                  ),
                ),
              );
            }
            final itemId = widget.itemIds[number];
            return Padding(key: ValueKey(id),
              padding: const EdgeInsets.only(bottom: 8),
              child: KeyedSubtree(key: _cardKeys.putIfAbsent(itemId, GlobalKey.new),
                child: widget.itemBuilder(context, number)),
            );
          },
        ),
      ),
    );
  });
}
