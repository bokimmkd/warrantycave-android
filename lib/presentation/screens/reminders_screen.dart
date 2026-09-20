import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
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
              context.l10n.text('reminders'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: caveNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(context.l10n.text('localAlerts')),
            const SizedBox(height: 18),
            Card(
              child: Column(
                children: [
                  _Switch(
                    title: context.l10n.text('days60'),
                    value: s.reminder60,
                    onChanged: (v) =>
                        app.updateSettings(s.copyWith(reminder60: v)),
                  ),
                  _Switch(
                    title: context.l10n.text('days30'),
                    value: s.reminder30,
                    onChanged: (v) =>
                        app.updateSettings(s.copyWith(reminder30: v)),
                  ),
                  _Switch(
                    title: context.l10n.text('days7'),
                    value: s.reminder7,
                    onChanged: (v) =>
                        app.updateSettings(s.copyWith(reminder7: v)),
                  ),
                  _Switch(
                    title: context.l10n.text('expiryDay'),
                    value: s.reminderExpiry,
                    onChanged: (v) =>
                        app.updateSettings(s.copyWith(reminderExpiry: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: context.l10n.text('enableNotifications'),
              icon: Icons.notifications_active_outlined,
              onPressed: () async {
                final ok = await app.requestNotificationPermission();
                if (context.mounted) {
                  if (ok) {
                    AppSnackbars.success(
                      context,
                      context.l10n.text('reminderEnabled'),
                    );
                  } else {
                    AppSnackbars.error(
                      context,
                      context.l10n.text('notificationNeeded'),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(Icons.lock_clock_outlined, color: caveBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.format('monitored', {
                          'count': app.items.length,
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, color: caveNavy),
    ),
    subtitle: Text(context.l10n.text('expiryReminder')),
    value: value,
    onChanged: onChanged,
  );
}
