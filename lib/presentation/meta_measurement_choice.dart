import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/meta_install_measurement.dart';
import '../l10n/app_localizations.dart';

class MetaMeasurementChoice extends StatefulWidget {
  const MetaMeasurementChoice({super.key});
  @override
  State<MetaMeasurementChoice> createState() => _MetaMeasurementChoiceState();
}

class _MetaMeasurementChoiceState extends State<MetaMeasurementChoice> {
  bool _enabled = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await MetaInstallMeasurement.enabled();
    if (mounted) setState(() { _enabled = enabled; _busy = false; });
  }

  Future<void> _change(bool value) async {
    if (_busy) return;
    if (value) {
      final allowed = await showDialog<bool>(context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.text('metaMeasurementTitle')),
          content: SingleChildScrollView(child: Text(context.l10n.text('metaMeasurementConsent'))),
          actions: [
            TextButton(onPressed: () => launchUrl(Uri.parse('https://warrantycave.com/privacy'),
              mode: LaunchMode.externalApplication),
              child: Text(context.l10n.text('privacyPolicy'))),
            TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('metaNotNow'))),
            FilledButton(onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.text('metaAllow'))),
          ],
        ));
      if (allowed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await MetaInstallMeasurement.setEnabled(value);
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('metaMeasurementRetry'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    secondary: const Icon(Icons.insights_outlined),
    title: Text(context.l10n.text('metaMeasurementTitle')),
    subtitle: Text(context.l10n.text('metaMeasurementHint')),
    value: _enabled,
    onChanged: _busy ? null : _change,
  );
}
