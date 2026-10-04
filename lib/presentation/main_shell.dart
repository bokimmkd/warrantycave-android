import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../domain/models.dart';
import '../data/ad_service.dart';
import '../l10n/app_localizations.dart';
import 'app_controller.dart';
import 'screens/add_warranty_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/items_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/upgrade_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'play_update_widgets.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _shortcuts = MethodChannel('com.warrantycave.app/shortcuts');
  String? _pendingShortcut;
  int index = 0;
  WarrantyStatus? itemStatusFilter;
  @override
  void initState() {
    super.initState();
    _shortcuts.setMethodCallHandler((call) async {
      if (call.method == 'openShortcut' && mounted) {
        setState(() => _pendingShortcut = call.arguments as String?);
      }
    });
    _loadInitialShortcut();
  }

  Future<void> _loadInitialShortcut() async {
    try {
      final shortcut = await _shortcuts.invokeMethod<String>('getInitialShortcut');
      if (mounted && shortcut != null) setState(() => _pendingShortcut = shortcut);
    } on MissingPluginException {
      // Other platforms do not expose Android launcher shortcuts.
    }
  }

  @override
  void dispose() {
    _shortcuts.setMethodCallHandler(null);
    super.dispose();
  }

  void _applyShortcut() {
    if (!mounted || _pendingShortcut == null) return;
    final shortcut = _pendingShortcut;
    _pendingShortcut = null;
    if (shortcut == 'add') {
      _openAdd();
    } else if (shortcut == 'items') {
      _openItems();
    } else if (shortcut == 'reminders') {
      setState(() => index = 3);
    } else if (shortcut == 'expiring') {
      _openItems(WarrantyStatus.expiringSoon);
    }
  }

  void _openItems([WarrantyStatus? status]) => setState(() {
    itemStatusFilter = status;
    index = 1;
  });

  void _selectMainTab(int value) {
    if (value == 2) {
      _openAdd();
      return;
    }
    setState(() => index = value);
  }

  void _returnToTab(int value) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (value == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAdd());
    } else if (mounted) {
      setState(() => index = value);
    }
  }

  Future<void> _openAdd() async {
    final controller = context.read<AppController>();
    if (!controller.canAdd) {
      await _showUpgradeSheet();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddWarrantyScreen(onSelectTab: _returnToTab),
      ),
    );
  }

  Future<void> _showUpgradeSheet() =>
      AppBottomSheets.show<void>(
        context,
        title: context.l10n.text('upgradePlan'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: AppColors.softBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium_outlined,
                color: caveTeal,
                size: 31,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.text('freeLimitReached'),
              textAlign: TextAlign.center,
              style: AppTypography.muted.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: context.l10n.text('viewPlans'),
              icon: Icons.workspace_premium_outlined,
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UpgradeScreen(onSelectTab: _returnToTab),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('maybeLater')),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    if (app.loading)
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(),
              const SizedBox(height: 22),
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: caveTeal,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.text('openingCave'),
                style: AppTypography.muted.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    if (!app.settings.onboardingComplete) {
      return const WelcomeScreen();
    }
    if (app.accountEnabled && (!app.signedIn || !app.emailVerified)) {
      return const AuthScreen();
    }
    if (_pendingShortcut != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyShortcut());
    }
    final pages = [
      HomeScreen(
        onAdd: _openAdd,
        onSeeAll: () => _openItems(),
        onStatusSelected: _openItems,
        onSelectTab: _returnToTab,
      ),
      ItemsScreen(initialStatus: itemStatusFilter, onSelectTab: _returnToTab),
      const SizedBox(),
      const RemindersScreen(),
      SettingsScreen(onSelectTab: _returnToTab),
    ];
    return Scaffold(
      body: PlayUpdateHost(child: IndexedStack(index: index == 2 ? 0 : index, children: pages)),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scaffold reserves this space outside the scrollable body. Hide it
          // while typing so the keyboard cannot crowd the content or ad.
          if (app.effectivePlan.hasAds && MediaQuery.viewInsetsOf(context).bottom == 0)
            const SafeArea(top: false, bottom: false,
              child: Center(child: FreeBannerAd())),
          AppBottomNavigation(
            selectedIndex: index == 2 ? 0 : index,
            onSelected: _selectMainTab,
          ),
        ],
      ),
    );
  }
}

