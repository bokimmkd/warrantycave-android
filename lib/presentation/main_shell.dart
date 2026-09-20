import 'package:flutter/material.dart';
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

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  WarrantyStatus? itemStatusFilter;
  @override
  void initState() {
    super.initState();
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
    final action = await AppBottomSheets.show<String>(
      context,
      title: context.l10n.text('addAWarranty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AddChoice(
            icon: Icons.document_scanner_outlined,
            title: context.l10n.text('smartScan'),
            subtitle: context.l10n.text('scanDocument'),
            onTap: () => Navigator.pop(context, 'scan'),
          ),
          const SizedBox(height: 10),
          _AddChoice(
            icon: Icons.edit_note_rounded,
            title: context.l10n.text('addManually'),
            subtitle: context.l10n.text('enterDetails'),
            onTap: () => Navigator.pop(context, 'manual'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'scan') {
      if (!controller.signedIn ||
          !controller.emailVerified ||
          controller.settings.smartScanCredits < 1) {
        await _showUpgradeSheet(smartScan: true);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddWarrantyScreen(
            onSelectTab: _returnToTab,
            startSmartScan: true,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddWarrantyScreen(onSelectTab: _returnToTab),
      ),
    );
  }

  Future<void> _showUpgradeSheet({bool smartScan = false}) =>
      AppBottomSheets.show<void>(
        context,
        title: smartScan
            ? context.l10n.text('smartScanPack')
            : context.l10n.text('upgradePlan'),
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
              child: Icon(
                smartScan
                    ? Icons.document_scanner_outlined
                    : Icons.workspace_premium_outlined,
                color: caveTeal,
                size: 31,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              smartScan
                  ? context.l10n.text('scanPackInfo')
                  : context.l10n.text('freeLimitReached'),
              textAlign: TextAlign.center,
              style: AppTypography.muted,
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: smartScan
                  ? context.l10n.text('viewScanPack')
                  : context.l10n.text('viewPlans'),
              icon: smartScan
                  ? Icons.document_scanner_outlined
                  : Icons.workspace_premium_outlined,
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
                style: AppTypography.muted,
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
      body: IndexedStack(index: index == 2 ? 0 : index, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (app.settings.plan.hasAds) const Center(child: FreeBannerAd()),
          AppBottomNavigation(
            selectedIndex: index == 2 ? 0 : index,
            onSelected: _selectMainTab,
          ),
        ],
      ),
    );
  }
}

class _AddChoice extends StatelessWidget {
  const _AddChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCards(
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.softBlue,
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Icon(icon, color: caveBlue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.subtitle),
              const SizedBox(height: 3),
              Text(subtitle, style: AppTypography.muted),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: caveBlue),
      ],
    ),
  );
}
