import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Two distinct actions share a row; their confirmation flows stay in Settings.
class AccountActions extends StatelessWidget {
  const AccountActions({required this.onSignOut, required this.onDelete, super.key});
  final VoidCallback onSignOut;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _Action(
      label: context.l10n.text('signOut'), icon: Icons.logout_rounded,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onTap: onSignOut,
    )),
    SizedBox(height: 28, child: VerticalDivider(width: 1,
      color: Theme.of(context).colorScheme.outlineVariant)),
    Expanded(child: _Action(
      label: context.l10n.text('deleteAccount'), icon: Icons.delete_forever_rounded,
      color: Theme.of(context).colorScheme.error, onTap: onDelete,
    )),
  ]);
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.icon, required this.color,
    required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(button: true,
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 52),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 20, color: color), const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 13,
              fontWeight: FontWeight.w600))),
          ])),
      )),
  );
}
