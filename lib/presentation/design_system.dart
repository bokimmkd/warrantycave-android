import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF0F2D4C);
  static const caveBlue = Color(0xFF0F4C81);
  static const teal = Color(0xFF14B8A6);
  static const sky = Color(0xFF60A5FA);
  static const background = Color(0xFFF3F8FC);
  static const surface = Colors.white;
  static const softBlue = Color(0xFFEAF4FB);
  static const border = Color(0xFFD9E6F0);
  static const textMuted = Color(0xFF607789);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFE05260);
  static const success = Color(0xFF0FAF9D);
}

abstract final class AppTypography {
  static const display = TextStyle(
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w900,
    color: AppColors.navy,
  );
  static const title = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.navy,
  );
  static const subtitle = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: AppColors.navy,
  );
  static const body = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: AppColors.navy,
  );
  static const muted = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: AppColors.textMuted,
  );
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: .4,
    color: AppColors.caveBlue,
  );
  static const button = TextStyle(fontSize: 15, fontWeight: FontWeight.w800);
}

abstract final class AppSpacing {
  static const xxs = 4.0,
      xs = 8.0,
      sm = 12.0,
      md = 16.0,
      lg = 20.0,
      xl = 24.0,
      xxl = 32.0;
}

abstract final class AppRadius {
  static const small = 10.0,
      medium = 14.0,
      large = 20.0,
      sheet = 28.0,
      pill = 999.0;
}

abstract final class AppShadows {
  static const card = [
    BoxShadow(color: Color(0x100F2D4C), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const floating = [
    BoxShadow(color: Color(0x2614B8A6), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

class AppCards extends StatelessWidget {
  const AppCards({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.color = AppColors.surface,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.large),
      border: Border.all(color: AppColors.border.withValues(alpha: .8)),
      boxShadow: AppShadows.card,
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

abstract final class AppInputFields {
  static InputDecoration decoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? helper,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    helperText: helper,
    filled: true,
    fillColor: AppColors.surface,
    labelStyle: const TextStyle(color: AppColors.textMuted),
    floatingLabelStyle: const TextStyle(
      color: AppColors.caveBlue,
      fontWeight: FontWeight.w700,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: const BorderSide(color: AppColors.teal, width: 1.8),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: const BorderSide(color: AppColors.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: const BorderSide(color: AppColors.danger, width: 1.8),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.loading = false,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading, expand;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: expand ? double.infinity : null,
    height: 52,
    child: FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
          : Icon(icon ?? Icons.arrow_forward_rounded),
      label: Text(
        loading ? 'Please wait…' : label,
        style: AppTypography.button,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.caveBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.caveBlue.withValues(alpha: .45),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
    ),
  );
}

class LoadingButton extends PrimaryButton {
  const LoadingButton({
    required super.label,
    required super.onPressed,
    required super.loading,
    super.key,
    super.icon,
    super.expand,
  });
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward_rounded),
      label: Text(label, style: AppTypography.button),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.softBlue,
        foregroundColor: AppColors.navy,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
    ),
  );
}

class OutlineButton extends StatelessWidget {
  const OutlineButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward_rounded),
      label: Text(label, style: AppTypography.button),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.caveBlue,
        side: const BorderSide(color: AppColors.border, width: 1.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
    ),
  );
}

class DangerButton extends StatelessWidget {
  const DangerButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon = Icons.delete_outline,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, style: AppTypography.button),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.danger,
        backgroundColor: AppColors.danger.withValues(alpha: .05),
        side: BorderSide(color: AppColors.danger.withValues(alpha: .35)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
    ),
  );
}

class BrandedIconButton extends StatelessWidget {
  const BrandedIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    super.key,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  @override
  Widget build(BuildContext context) => Semantics(
    label: tooltip,
    button: true,
    child: IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.softBlue,
        foregroundColor: AppColors.caveBlue,
      ),
      icon: Icon(icon),
    ),
  );
}

abstract final class AppButtons {
  static Widget primary(
    String label,
    VoidCallback? onPressed, {
    IconData? icon,
    bool loading = false,
  }) => PrimaryButton(
    label: label,
    onPressed: onPressed,
    icon: icon,
    loading: loading,
  );
  static Widget secondary(
    String label,
    VoidCallback? onPressed, {
    IconData? icon,
  }) => SecondaryButton(label: label, onPressed: onPressed, icon: icon);
  static Widget outline(
    String label,
    VoidCallback? onPressed, {
    IconData? icon,
  }) => OutlineButton(label: label, onPressed: onPressed, icon: icon);
  static Widget danger(
    String label,
    VoidCallback? onPressed, {
    IconData icon = Icons.delete_outline,
  }) => DangerButton(label: label, onPressed: onPressed, icon: icon);
  static Widget icon(IconData icon, VoidCallback? onPressed, String tooltip) =>
      BrandedIconButton(icon: icon, onPressed: onPressed, tooltip: tooltip);
}

enum AppMessageType { success, error, info }

abstract final class AppSnackbars {
  static void show(
    BuildContext context,
    String message, {
    AppMessageType type = AppMessageType.info,
  }) {
    final (color, icon) = switch (type) {
      AppMessageType.success => (AppColors.success, Icons.check_circle_rounded),
      AppMessageType.error => (AppColors.danger, Icons.error_rounded),
      AppMessageType.info => (AppColors.caveBlue, Icons.info_rounded),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          margin: const EdgeInsets.all(AppSpacing.md),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  static void success(BuildContext context, String message) =>
      show(context, message, type: AppMessageType.success);
  static void error(BuildContext context, String message) =>
      show(context, message, type: AppMessageType.error);
}

abstract final class AppDialogs {
  static Future<void> message(
    BuildContext context, {
    required String title,
    required String message,
    String buttonLabel = 'Done',
    IconData icon = Icons.check_circle_outline_rounded,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: AppCards(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFE2F7F4),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.teal, size: 31),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.title,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.muted,
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: buttonLabel,
              icon: Icons.check_rounded,
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        ),
      ),
    ),
  );

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    IconData icon = Icons.help_outline_rounded,
    bool danger = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: AppCards(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: (danger ? AppColors.danger : AppColors.teal)
                        .withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: danger ? AppColors.danger : AppColors.teal,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.title,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.muted,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlineButton(
                        label: cancelLabel,
                        onPressed: () => Navigator.pop(dialogContext, false),
                        icon: Icons.close,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: danger
                          ? DangerButton(
                              label: confirmLabel,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                            )
                          : PrimaryButton(
                              label: confirmLabel,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              expand: false,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

abstract final class AppBottomSheets {
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
  }) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Container(
        margin: const EdgeInsets.only(top: 40),
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTypography.title),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    ),
  );
}

class AppEmptyStates extends StatelessWidget {
  const AppEmptyStates({
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.inventory_2_outlined,
  });
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;
  @override
  Widget build(BuildContext context) => AppCards(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.softBlue,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 32, color: AppColors.sky),
        ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: AppTypography.title),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: AppTypography.muted),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          PrimaryButton(
            label: actionLabel!,
            onPressed: onAction,
            icon: Icons.add,
          ),
        ],
      ],
    ),
  );
}

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    required this.label,
    required this.color,
    required this.icon,
    super.key,
  });
  final String label;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Status: $label',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    ),
  );
}
