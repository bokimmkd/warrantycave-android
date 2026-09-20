import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import 'upgrade_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.onSelectTab, super.key});
  final ValueChanged<int> onSelectTab;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  Future<void> open(String value) async {
    final uri = Uri.parse(value);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted)
      AppSnackbars.error(context, context.l10n.text('linkOpenFailed'));
  }

  Future<void> editProfile(AppController app) async {
    final s = app.settings;
    final firstName = TextEditingController(text: s.firstName);
    final lastName = TextEditingController(text: s.lastName);
    final email = TextEditingController(text: app.accountEmail);
    final phone = TextEditingController(text: s.phone);
    var currency = s.defaultCurrency;
    await AppBottomSheets.show<void>(
      context,
      title: context.l10n.text('profile'),
      child: StatefulBuilder(
        builder: (sheetContext, update) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: firstName,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('firstName'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: lastName,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('lastName'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: email,
              readOnly: app.signedIn,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: context.l10n.text('email'),
                helperText: app.signedIn
                    ? context.l10n.text('managedByAccount')
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: context.l10n.text('phone'),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.text('defaultCurrency').toUpperCase(),
                style: AppTypography.label,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: supportedCurrencies
                  .map(
                    (value) => ChoiceChip(
                      label: Text(value),
                      selected: currency == value,
                      onSelected: (_) => update(() => currency = value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: context.l10n.text('saveChanges'),
              icon: Icons.save_outlined,
              onPressed: () async {
                await app.updateSettings(
                  s.copyWith(
                    firstName: firstName.text.trim(),
                    lastName: lastName.text.trim(),
                    email: app.signedIn ? app.accountEmail : email.text.trim(),
                    phone: phone.text.trim(),
                    defaultCurrency: currency,
                  ),
                );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                if (mounted)
                  AppSnackbars.success(
                    context,
                    context.l10n.text('profileSaved'),
                  );
              },
            ),
          ],
        ),
      ),
    );
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    phone.dispose();
  }

  Future<void> logout(AppController app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('signOutQuestion')),
        content: Text(context.l10n.text('signOutInfo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.text('signOut')),
          ),
        ],
      ),
    );
    if (confirmed == true) await app.signOut();
  }

  Future<void> deleteAccount(AppController app) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('deleteAccountQuestion')),
        content: Text(context.l10n.text('deleteAccountInfo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.text('continueLabel')),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final password = TextEditingController();
    final second = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('confirmDeletion')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.text('cannotUndo')),
            if (app.usesPassword) ...[
              const SizedBox(height: 14),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('currentPassword'),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.text('keepAccount')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.text('deletePermanently')),
          ),
        ],
      ),
    );
    try {
      if (second == true) await app.deleteAccount(password: password.text);
    } catch (_) {
      if (mounted)
        AppSnackbars.error(context, context.l10n.text('deleteAccountFailed'));
    } finally {
      password.dispose();
    }
  }

  Future<void> redeemFounderCode(AppController app) async {
    final code = TextEditingController();
    final submitted = await AppBottomSheets.show<String>(
      context,
      title: context.l10n.text('redeemFounderCode'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: context.l10n.text('enterFounderCode'),
              prefixIcon: const Icon(Icons.redeem_rounded),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: context.l10n.text('apply'),
            icon: Icons.check_rounded,
            onPressed: () {
              final value = code.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
          ),
        ],
      ),
    );
    code.dispose();
    if (submitted == null || !mounted) return;
    try {
      await app.redeemFounderCode(submitted);
      if (mounted) {
        AppSnackbars.success(
          context,
          context.l10n.text('founderCodeActivated'),
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackbars.error(context, context.l10n.text('founderCodeFailed'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppController>();
    final s = app.settings;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: app.refreshCloud,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              context.l10n.text('settings'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: caveNavy,
              ),
            ),
            const SizedBox(height: 18),
            _Label(context.l10n.text('account')),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(18),
                leading: const CircleAvatar(
                  backgroundColor: AppColors.softBlue,
                  child: Icon(Icons.person_outline, color: caveBlue),
                ),
                title: Text(
                  [
                        s.firstName,
                        s.lastName,
                      ].where((e) => e.isNotEmpty).join(' ').isEmpty
                      ? context.l10n.text('profile')
                      : [
                          s.firstName,
                          s.lastName,
                        ].where((e) => e.isNotEmpty).join(' '),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: caveNavy,
                  ),
                ),
                subtitle: Text(
                  s.email.isEmpty
                      ? context.l10n.format('profileSummary', {
                          'currency': s.defaultCurrency,
                        })
                      : context.l10n.format('emailDefault', {
                          'email': s.email,
                          'currency': s.defaultCurrency,
                        }),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => editProfile(app),
              ),
            ),
            if (app.signedIn) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.cloud_done_outlined,
                        color: caveTeal,
                      ),
                      title: Text(context.l10n.text('connectedAccount')),
                      subtitle: Text(
                        app.cloudSyncing
                            ? context.l10n.format('syncingAccount', {
                                'email': app.accountEmail,
                              })
                            : app.cloudError == null
                            ? app.lastCloudSync == null
                                  ? context.l10n.format(
                                      'cloudConnectedAccount',
                                      {'email': app.accountEmail},
                                    )
                                  : context.l10n.format('lastSyncedAccount', {
                                      'email': app.accountEmail,
                                      'time': DateFormat.jm().format(
                                        app.lastCloudSync!,
                                      ),
                                    })
                            : context.l10n.format('syncRetryAccount', {
                                'email': app.accountEmail,
                              }),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout_outlined),
                      title: Text(context.l10n.text('signOut')),
                      onTap: () => logout(app),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.delete_forever_outlined,
                        color: Colors.redAccent,
                      ),
                      title: Text(
                        context.l10n.text('deleteAccount'),
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () => deleteAccount(app),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(18),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE2F7F4),
                  child: Icon(
                    Icons.workspace_premium_outlined,
                    color: caveTeal,
                  ),
                ),
                title: Text(
                  context.l10n.format('planName', {'plan': s.plan.label}),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: caveNavy,
                  ),
                ),
                subtitle: Text(
                  context.l10n.format('planUsage', {
                    'count': app.items.length,
                    'limit': s.plan.itemLimit,
                    'storage': context.l10n.text(
                      s.plan.hasCloud ? 'cloudSync' : 'localStorage',
                    ),
                  }),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        UpgradeScreen(onSelectTab: widget.onSelectTab),
                  ),
                ),
              ),
            ),
            if (app.signedIn && app.emailVerified) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.auto_awesome_rounded,
                        color: caveTeal,
                      ),
                      title: Text(context.l10n.text('smartScanPack')),
                      subtitle: Text(
                        context.l10n.format('smartScanCreditsRemaining', {
                          'count': s.smartScanCredits,
                        }),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.redeem_rounded,
                        color: caveBlue,
                      ),
                      title: Text(context.l10n.text('redeemFounderCode')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => redeemFounderCode(app),
                    ),
                  ],
                ),
              ),
            ],
            if (app.signedIn && s.referralCode.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.card_giftcard_rounded,
                    color: caveTeal,
                  ),
                  title: Text(context.l10n.text('inviteFriends')),
                  subtitle: Text(
                    context.l10n.format('referralReward', {
                      'code': s.referralCode,
                    }),
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: context.l10n.text('shareReferral'),
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text: context.l10n.format('referralShare', {
                          'link': ReferralPolicy.linkForCode(s.referralCode),
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _Label(context.l10n.text('warrantyPreferences')),
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(context.l10n.text('expiryThreshold')),
                    subtitle: Text(
                      context.l10n.format('daysBeforeExpiry', {
                        'days': s.expiringThresholdDays,
                      }),
                    ),
                    trailing: DropdownButton<int>(
                      value: s.expiringThresholdDays,
                      items: [30, 45, 60, 90]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v')),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null)
                          app.updateSettings(
                            s.copyWith(expiringThresholdDays: v),
                          );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      app.signedIn
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                    ),
                    title: Text(context.l10n.text('cloudBackup')),
                    subtitle: Text(
                      app.signedIn
                          ? s.plan.hasCloud
                                ? context.l10n.text('syncSecurely')
                                : context.l10n.text('upgradeForBackup')
                          : context.l10n.text('signInForBackup'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _Label(context.l10n.text('language')),
            Card(
              child: ListTile(
                leading: const Icon(Icons.translate_rounded, color: caveBlue),
                title: Text(context.l10n.text('language')),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: s.languageCode,
                    items: appLanguages
                        .map(
                          (language) => DropdownMenuItem(
                            value: language.code,
                            child: Text(language.nativeName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        app.updateSettings(s.copyWith(languageCode: value));
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _Label(context.l10n.text('legalSupport')),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(context.l10n.text('privacyPolicy')),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => open('https://warrantycave.com/privacy'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(context.l10n.text('terms')),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => open('https://warrantycave.com/terms'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: Text(context.l10n.text('support')),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => open('mailto:support@warrantycave.com'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.language_outlined),
                    title: Text(context.l10n.text('website')),
                    subtitle: const Text('warrantycave.com'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => open('https://warrantycave.com'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Center(
              child: Text(
                'WarrantyCave 1.0.5\nScan. Store. Relax.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: caveBlue,
      ),
    ),
  );
}
