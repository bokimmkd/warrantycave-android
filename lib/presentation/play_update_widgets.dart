import 'dart:async';
import 'package:flutter/material.dart';
import '../data/play_updates.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

class PlayUpdateHost extends StatefulWidget {
  const PlayUpdateHost({super.key, required this.child, this.updates});
  final Widget child;
  final PlayUpdates? updates;
  @override
  State<PlayUpdateHost> createState() => _PlayUpdateHostState();
}

class _PlayUpdateHostState extends State<PlayUpdateHost> {
  late final PlayUpdates updates;
  DialogRoute<void>? _dialog;
  String? _shown;
  bool _scheduled = false;
  @override
  void initState() { super.initState(); updates = widget.updates ?? PlayUpdates(); updates.addListener(_changed); unawaited(updates.initialize()); }
  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _syncOffer();
    });
  }
  void _close() {
    final dialog = _dialog; _dialog = null; _shown = null;
    if (dialog != null && dialog.isActive) dialog.navigator?.removeRoute(dialog);
  }
  void _syncOffer() {
    final state = updates.state;
    final key = state.offer == null ? null : '${state.version}:${state.offer}:${state.installFailed}';
    if (key == _shown) return;
    _close();
    if (key == null) return;
    _shown = key;
    final ready = state.offer == 'ready';
    final dialog = DialogRoute<void>(context: context, barrierDismissible: false, builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return PopScope(canPop: false, child: AlertDialog(
        icon: const Icon(Icons.system_update_alt_rounded, color: caveTeal, size: 30),
        title: Text(l10n.text(ready ? 'playReadyTitle' : 'playOfferTitle')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.text(ready ? 'playReadyBody' : 'playOfferBody')),
          if (state.installFailed) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(l10n.text('playInstallFailed'), style: TextStyle(color: Theme.of(dialogContext).colorScheme.error))),
        ]),
        actions: [
          TextButton(onPressed: () => unawaited(updates.action('later')), child: Text(l10n.text('playLater'))),
          FilledButton(onPressed: () => unawaited(updates.action(ready ? 'restart' : state.offer == 'store' ? 'store' : 'update')),
            child: Text(l10n.text(ready ? 'playRestart' : 'playUpdate'))),
        ],
      ));
    });
    _dialog = dialog;
    unawaited(Navigator.of(context).push(dialog));
  }
  @override
  void dispose() { _close(); updates.removeListener(_changed); if (widget.updates == null) updates.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(children: [
    if (updates.state.showProgress) SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: PlayUpdateProgress(state: updates.state))),
    Expanded(child: widget.child),
  ]);
}

class PlayUpdateProgress extends StatelessWidget {
  const PlayUpdateProgress({super.key, required this.state});
  final PlayUpdateState state;
  @override
  Widget build(BuildContext context) {
    final installing = state.stage == 'installing';
    final downloading = state.stage == 'downloading';
    final fraction = downloading ? state.fraction : null;
    final colors = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Icon(Icons.system_update_alt_rounded, size: 18, color: colors.onPrimaryContainer),
          const SizedBox(width: 8), Expanded(child: Text(context.l10n.text(installing ? 'playInstalling' : downloading ? 'playDownloading' : 'playWaiting'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.onPrimaryContainer))),
          if (fraction != null) Text('${(fraction * 100).floor()}%', style: TextStyle(fontSize: 12, color: colors.onPrimaryContainer)),
        ]),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: fraction, minHeight: 3, borderRadius: BorderRadius.circular(3)),
      ]));
  }
}
