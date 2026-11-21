import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import 'privacy_screen.dart';

/// Email sign-in. "Create account" only works with an invite
/// (see AuthService.signUpWithInvite) - the toggle just reveals
/// the name field and switches the submit action.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _name = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = ref.read(stringsProvider);
    // Sign-up validation, before any Auth call: a blank name
    // or a typo'd password must never create a locked-out
    // account (there is no password confirmation on the
    // server side to catch it).
    if (_creating) {
      if (_name.text.trim().isEmpty) {
        setState(() => _error = s.nameRequired);
        return;
      }
      if (_password.text != _confirmPassword.text) {
        setState(() => _error = s.passwordsDoNotMatch);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    try {
      if (_creating) {
        await auth.signUpWithInvite(
          email: _email.text,
          password: _password.text,
          name: _name.text.trim(),
        );
      } else {
        await auth.signIn(_email.text, _password.text);
      }
      // On success, currentUserProvider updates and app.dart
      // swaps this screen for the home shell automatically.
    } on FirebaseAuthException catch (e) {
      // Friendly, localised message for the Firebase code —
      // raw Firebase error text never goes on screen.
      if (mounted) setState(() => _error = s.authError(e.code));
    } catch (e) {
      if (mounted) {
        // AuthService throws StateErrors carrying short codes
        // ('no-invite', 'empty-name') — map each to its
        // localised message; anything else gets the generic
        // auth error, never raw text.
        final message = e is StateError
            ? switch (e.message) {
                'no-invite' => s.noInvite,
                'empty-name' => s.nameRequired,
                _ => s.authError(''),
              }
            : s.authError('');
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Forgot password?": sends the reset email for the typed
  /// address, or the invalid-email message when the field is
  /// empty. Firebase errors are mapped through authError, never
  /// shown raw.
  Future<void> _forgotPassword() async {
    final s = ref.read(stringsProvider);
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = s.authError('invalid-email'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).forgotPassword(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.resetEmailSent)),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = s.authError(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = s.authError(''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    // One-time notice after self-service account deletion: the
    // Settings screen arms it just before signing out. Show it
    // once as a snackbar, then clear it so it never repeats.
    final notice = ref.watch(deletedAccountNoticeProvider);
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(notice)),
        );
        ref.read(deletedAccountNoticeProvider.notifier).state = null;
      });
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                if (_creating)
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                        labelText: s.name,
                        border: const OutlineInputBorder()),
                  ),
                if (_creating) const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      labelText: s.email, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                      labelText: s.password,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        tooltip: _showPassword
                            ? s.hidePassword
                            : s.showPassword,
                        onPressed: () => setState(
                            () => _showPassword = !_showPassword),
                      )),
                ),
                // Sign-up only: confirm the password, so a typo
                // cannot lock the brand-new account out until a
                // reset. Shares the show/hide toggle above.
                if (_creating) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPassword,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                        labelText: s.confirmPassword,
                        border: const OutlineInputBorder()),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    child: Text(s.forgotPassword),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: Colors.red.shade800)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_creating ? s.createAccount : s.signIn),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _creating = !_creating;
                    _error = null;
                  }),
                  child: Text(_creating ? s.signIn : s.createAccount),
                ),
                const SizedBox(height: 8),
                Text(s.inviteOnly,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyScreen(),
                      ),
                    );
                  },
                  child: Text(s.privacyPolicy),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
