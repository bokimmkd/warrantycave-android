import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../l10n/app_localizations.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final referralCode = TextEditingController();
  bool createMode = false;
  bool busy = false;
  bool obscure = true;

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    referralCode.dispose();
    super.dispose();
  }

  String _message(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'email-already-in-use' => context.l10n.text('emailInUse'),
        'invalid-email' => context.l10n.text('invalidEmail'),
        'invalid-credential' ||
        'wrong-password' => context.l10n.text('invalidCredentials'),
        'weak-password' => context.l10n.text('weakPassword'),
        'user-not-found' => context.l10n.text('userNotFound'),
        'network-request-failed' => context.l10n.text('networkFailed'),
        _ => error.message ?? context.l10n.text('requestFailed'),
      };
    }
    return context.l10n.text('requestFailed');
  }

  Future<void> _submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      AppSnackbars.error(context, context.l10n.text('enterEmailPassword'));
      return;
    }
    if (createMode &&
        (firstName.text.trim().isEmpty || lastName.text.trim().isEmpty)) {
      AppSnackbars.error(context, context.l10n.text('enterName'));
      return;
    }
    if (createMode && password.text != confirmPassword.text) {
      AppSnackbars.error(context, context.l10n.text('passwordMismatch'));
      return;
    }
    setState(() => busy = true);
    try {
      final app = context.read<AppController>();
      if (createMode) {
        await app.createAccount(
          firstName: firstName.text,
          lastName: lastName.text,
          email: email.text,
          password: password.text,
          referralCode: referralCode.text,
        );
      } else {
        await app.signIn(email.text, password.text);
      }
    } catch (error) {
      if (mounted) AppSnackbars.error(context, _message(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (email.text.trim().isEmpty) {
      AppSnackbars.error(context, context.l10n.text('enterEmailFirst'));
      return;
    }
    try {
      await context.read<AppController>().sendPasswordReset(email.text);
      if (mounted) {
        AppSnackbars.success(context, context.l10n.text('resetSent'));
      }
    } catch (error) {
      if (mounted) AppSnackbars.error(context, _message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    if (app.signedIn && !app.emailVerified) return const _VerificationView();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          children: [
            const Center(child: BrandMark()),
            const SizedBox(height: 34),
            Text(
              createMode
                  ? context.l10n.text('createProfile')
                  : context.l10n.text('welcomeBack'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: caveNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              createMode
                  ? context.l10n.text('profileCopy')
                  : context.l10n.text('signInCopy'),
              textAlign: TextAlign.center,
              style: AppTypography.muted,
            ),
            const SizedBox(height: 26),
            if (createMode) ...[
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
              const SizedBox(height: 12),
            ],
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: context.l10n.text('email'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: context.l10n.text('password'),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (createMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassword,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: context.l10n.text('confirmPassword'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: referralCode,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: context.l10n.text('referralCode'),
                  helperText: context.l10n.text('referralHint'),
                  helperMaxLines: 2,
                ),
              ),
            ],
            if (!createMode)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : _forgotPassword,
                  child: Text(context.l10n.text('forgotPassword')),
                ),
              )
            else
              const SizedBox(height: 18),
            PrimaryButton(
              label: busy
                  ? context.l10n.text('pleaseWait')
                  : (createMode
                        ? context.l10n.text('createAccount')
                        : context.l10n.text('signIn')),
              icon: createMode ? Icons.person_add_alt_1 : Icons.login_rounded,
              onPressed: busy ? null : _submit,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: Text(context.l10n.text('googlePending')),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() => createMode = !createMode),
              child: Text(
                createMode
                    ? context.l10n.text('alreadyAccount')
                    : context.l10n.text('newCreateProfile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationView extends StatefulWidget {
  const _VerificationView();
  @override
  State<_VerificationView> createState() => _VerificationViewState();
}

class _VerificationViewState extends State<_VerificationView> {
  bool busy = false;

  Future<void> _check() async {
    setState(() => busy = true);
    final verified = await context.read<AppController>().checkVerification();
    if (mounted && !verified)
      AppSnackbars.error(context, context.l10n.text('emailNotVerified'));
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.mark_email_unread_outlined,
                size: 72,
                color: caveBlue,
              ),
              const SizedBox(height: 22),
              Text(
                context.l10n.text('verifyEmail'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: caveNavy,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We sent a verification link to ${app.accountEmail}. Open it, then come back here.',
                textAlign: TextAlign.center,
                style: AppTypography.muted,
              ),
              const SizedBox(height: 26),
              PrimaryButton(
                label: busy
                    ? context.l10n.text('pleaseWait')
                    : context.l10n.text('verifiedEmail'),
                icon: Icons.verified_outlined,
                onPressed: busy ? null : _check,
              ),
              TextButton(
                onPressed: () async {
                  await app.resendVerification();
                  if (context.mounted)
                    AppSnackbars.success(
                      context,
                      context.l10n.text('verificationSent'),
                    );
                },
                child: Text(context.l10n.text('resendEmail')),
              ),
              TextButton(
                onPressed: app.signOut,
                child: Text(context.l10n.text('differentAccount')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
