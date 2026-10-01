import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

/// Shared tab heading. Actions retain 48dp targets and wrap on narrow screens.
class CaveHeader extends StatelessWidget {
  const CaveHeader({
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.brand = false,
    super.key,
  });
  final String title, subtitle;
  final List<Widget> actions;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [caveBlue, skyBlue]),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.receipt_long_rounded,
              size: 21, color: Colors.white),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (brand)
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Warranty', style: TextStyle(color: scheme.onSurface)),
                    TextSpan(text: 'Cave', style: TextStyle(color: scheme.secondary)),
                  ]),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                )
              else
                Text(title, style: TextStyle(
                  fontSize: 22, height: 1.15, fontWeight: FontWeight.w800,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? scheme.onSurface : caveNavy,
                )),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(
                fontSize: 12, height: 1.25, fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? scheme.secondary : const Color(0xFF087F75),
              )),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(14) > 18;
      if (actions.isEmpty) return heading;
      if (stacked) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading,
          Align(alignment: Alignment.centerRight,
            child: Wrap(children: actions)),
        ]);
      }
      return Row(children: [Expanded(child: heading), ...actions]);
    });
  }
}

/// Search is hidden until requested; closing it also clears the active query.
class CompactSearchField extends StatelessWidget {
  const CompactSearchField({required this.controller,
    required this.onChanged, required this.onClose, super.key});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        prefixIcon: const Icon(Icons.search, size: 21),
        hintText: context.l10n.text('searchWarranties'),
        suffixIcon: IconButton(
          tooltip: context.l10n.text('clearSearch'),
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ),
    ),
  );
}
