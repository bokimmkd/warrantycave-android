import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({required this.onSelectTab, super.key});
  final ValueChanged<int> onSelectTab;

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  PlanTier? selected;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    selected ??= app.settings.plan;
    final chosen = selected!;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('upgradePlan'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          const Icon(Icons.shield_rounded, size: 62, color: caveTeal),
          const SizedBox(height: 14),
          Text(
            context.l10n.text('freeForever'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: caveNavy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.text('unlockCloud'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 24),
          _PlanCard(
            tier: PlanTier.free,
            price: '\$0 forever',
            features: [
              context.l10n.text('upTo10'),
              context.l10n.text('localStorage'),
              context.l10n.text('manualEntry'),
              context.l10n.text('localReminders'),
              context.l10n.text('includesAds'),
            ],
            selected: chosen == PlanTier.free,
            current: app.settings.plan == PlanTier.free,
            onTap: () => setState(() => selected = PlanTier.free),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            tier: PlanTier.basic,
            price: app.billingPrice(PlanTier.basic),
            features: [
              context.l10n.text('upTo15'),
              context.l10n.text('cloudSync'),
              context.l10n.text('barcodeScanner'),
              context.l10n.text('allReminders'),
              context.l10n.text('claimPacks'),
            ],
            recommended: true,
            selected: chosen == PlanTier.basic,
            current: app.settings.plan == PlanTier.basic,
            onTap: () => setState(() => selected = PlanTier.basic),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            tier: PlanTier.plus,
            price: app.billingPrice(PlanTier.plus),
            features: [
              context.l10n.text('upTo50'),
              context.l10n.text('cloudSync'),
              context.l10n.text('barcodeScanner'),
              context.l10n.text('allReminders'),
              context.l10n.text('claimPacks'),
            ],
            selected: chosen == PlanTier.plus,
            current: app.settings.plan == PlanTier.plus,
            onTap: () => setState(() => selected = PlanTier.plus),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.text('securePurchase'),
            textAlign: TextAlign.center,
            style: AppTypography.muted,
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: chosen == app.settings.plan
                ? context.l10n.text('currentPlan')
                : context.l10n.format('continueWith', {
                    'plan': _tierLabel(context, chosen),
                    'price': app.billingPrice(chosen),
                  }),
            onPressed:
                chosen == app.settings.plan ||
                    chosen == PlanTier.free ||
                    app.billingBusy
                ? null
                : () async {
                    try {
                      await app.purchasePlan(chosen);
                    } catch (_) {
                      if (context.mounted) {
                        AppSnackbars.error(
                          context,
                          app.billingError ??
                              context.l10n.text('purchaseUnavailable'),
                        );
                      }
                    }
                  },
            icon: chosen == app.settings.plan
                ? Icons.check_circle_outline
                : Icons.arrow_forward_rounded,
          ),
          const SizedBox(height: 10),
          OutlineButton(
            label: app.billingBusy
                ? context.l10n.text('restoringPurchases')
                : context.l10n.text('restorePurchases'),
            onPressed: app.billingBusy
                ? null
                : () async {
                    if (!app.signedIn || !app.emailVerified) {
                      AppSnackbars.error(
                        context,
                        context.l10n.text('purchaseRequiresAccount'),
                      );
                      return;
                    }
                    try {
                      await app.restorePurchases();
                    } catch (_) {
                      if (context.mounted) {
                        AppSnackbars.error(
                          context,
                          app.billingError ??
                              context.l10n.text('purchaseUnavailable'),
                        );
                      }
                    }
                  },
            icon: Icons.restore_rounded,
          ),
          const SizedBox(height: 10),
          OutlineButton(
            label: context.l10n.text('notNow'),
            onPressed: () => Navigator.maybePop(context),
            icon: Icons.close,
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavigation(
        selectedIndex: 4,
        onSelected: widget.onSelectTab,
      ),
    );
  }

  String _tierLabel(BuildContext context, PlanTier tier) =>
      context.l10n.text(switch (tier) {
        PlanTier.free => 'free',
        PlanTier.basic => 'basic',
        PlanTier.plus => 'plus',
      });
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.tier,
    required this.price,
    required this.features,
    required this.selected,
    required this.current,
    required this.onTap,
    this.recommended = false,
  });
  final PlanTier tier;
  final String price;
  final List<String> features;
  final bool selected;
  final bool current;
  final VoidCallback onTap;
  final bool recommended;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? caveTeal
              : recommended
              ? const Color(0xFF78D8D1)
              : const Color(0xFFE0EAF2),
          width: selected
              ? 3
              : recommended
              ? 2
              : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recommended)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: caveTeal,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  context.l10n.text('mostPopular'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (recommended) const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.text(switch (tier) {
                      PlanTier.free => 'free',
                      PlanTier.basic => 'basic',
                      PlanTier.plus => 'plus',
                    }),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: caveNavy,
                    ),
                  ),
                ),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: caveBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? caveTeal : AppColors.border,
                ),
              ],
            ),
            if (current) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.text('currentPlanCaps'),
                style: TextStyle(
                  color: caveTeal,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...features.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 17, color: caveTeal),
                    const SizedBox(width: 8),
                    Text(e),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
