import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/play_updates.dart';
import '../data/usage_analytics.dart';
import '../l10n/app_localizations.dart';
import 'app_controller.dart';

final engagementRouteObserver = RouteObserver<ModalRoute<void>>();

Future<bool?> showUsageConsent(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.l10n.text('usageMeasurementTitle')),
    content: SingleChildScrollView(
      child: Text(context.l10n.text('usageMeasurementConsent')),
    ),
    actions: [
      TextButton(
        onPressed: () => launchUrl(
          Uri.parse('https://warrantycave.com/privacy'),
          mode: LaunchMode.externalApplication,
        ),
        child: Text(context.l10n.text('privacyPolicy')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(context.l10n.text('metaNotNow')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(context.l10n.text('metaAllow')),
      ),
    ],
  ),
);

/// Uses route, lifecycle, pointer-idle and update state rather than polling.
class ReleaseEngagementHost extends StatefulWidget {
  const ReleaseEngagementHost({
    super.key,
    required this.child,
    required this.mainReady,
    required this.updates,
  });
  final Widget child;
  final bool mainReady;
  final PlayUpdates updates;
  @override
  State<ReleaseEngagementHost> createState() => _ReleaseEngagementHostState();
}

class _ReleaseEngagementHostState extends State<ReleaseEngagementHost>
    with WidgetsBindingObserver, RouteAware {
  Timer? _idle;
  AppController? _app;
  UsageAnalytics? _analytics;
  ModalRoute<void>? _route;
  bool _busy = false, _offeredChoice = false, _scrolling = false;
  int _interaction = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.updates.addListener(_schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppController>();
    if (_app != app) {
      _app?.removeListener(_schedule);
      _analytics?.removeListener(_schedule);
      _app = app;
      _analytics = app.analytics;
      app.addListener(_schedule);
      _analytics?.addListener(_schedule);
    }
    final route = ModalRoute.of(context);
    if (route != _route) {
      engagementRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) engagementRouteObserver.subscribe(this, route);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(ReleaseEngagementHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didPopNext() => _schedule();
  @override
  void didPushNext() {
    _interaction++;
    _idle?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _interaction++;
    _idle?.cancel();
    if (state == AppLifecycleState.resumed) _schedule();
  }

  bool get _safe =>
      mounted &&
      !_scrolling &&
      _route?.isCurrent == true &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      MediaQuery.viewInsetsOf(context).bottom == 0 &&
      !(_app?.loading ?? true) &&
      !(_app?.cloudSyncing ?? true) &&
      !(_app?.billingBusy ?? true) &&
      !(_app?.smartScanBusy ?? true) &&
      (!widget.mainReady ||
          (widget.updates.initialized &&
              widget.updates.state.offer == null &&
              !widget.updates.state.showProgress));
  void _schedule() {
    _idle?.cancel();
    if (!mounted || _busy || (_app?.analytics == null && _app?.reviews == null))
      return;
    _idle = Timer(const Duration(milliseconds: 900), _run);
  }

  Future<void> _run() async {
    if (!_safe || _busy) return;
    final app = _app!;
    _busy = true;
    var choiceShown = false;
    try {
      final analytics = _analytics;
      if (analytics != null && !analytics.hasChoice && !_offeredChoice) {
        _offeredChoice = true;
        choiceShown = true;
        final choice = await showUsageConsent(context);
        if (mounted) await analytics.setEnabled(choice == true);
      } else if (widget.mainReady &&
          app.deferredServicesReady &&
          app.signedIn &&
          app.emailVerified) {
        final interaction = _interaction;
        await app.reviews?.request(
          app.items.length,
          () => _safe && interaction == _interaction,
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('metaMeasurementRetry'))),
        );
    } finally {
      _busy = false;
      if (choiceShown && mounted) _schedule();
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    engagementRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    widget.updates.removeListener(_schedule);
    _app?.removeListener(_schedule);
    _analytics?.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          _scrolling = notification.direction != ScrollDirection.idle;
          _interaction++;
          _idle?.cancel();
          if (!_scrolling) _schedule();
          return false;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            _interaction++;
            _idle?.cancel();
          },
          onPointerUp: (_) => _schedule(),
          onPointerCancel: (_) => _schedule(),
          child: widget.child,
        ),
      );
}

class UsageMeasurementChoice extends StatelessWidget {
  const UsageMeasurementChoice({super.key});
  @override
  Widget build(BuildContext context) {
    final analytics = context.read<AppController>().analytics;
    if (analytics == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: analytics,
      builder: (context, _) => SwitchListTile(
        dense: true,
        secondary: const Icon(Icons.analytics_outlined),
        title: Text(context.l10n.text('usageMeasurementTitle')),
        subtitle: Text(context.l10n.text('usageMeasurementHint')),
        value: analytics.enabled,
        onChanged: (enabled) async {
          if (enabled && await showUsageConsent(context) != true) return;
          try {
            await analytics.setEnabled(enabled);
          } catch (_) {
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.text('metaMeasurementRetry')),
                ),
              );
          }
        },
      ),
    );
  }
}
