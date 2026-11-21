import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/privacy_policy.dart';
import '../providers/locale_provider.dart';
import '../theme/app_tokens.dart';

/// The DyadeSpace privacy policy, in the app's three
/// languages. Deliberately uses NO auth state: it must render
/// without sign-in, both from the sign-in screen and from the
/// public /privacy route (the store listings link to it, and
/// it states the in-app account-deletion path). The language
/// switcher at the top works signed-out too — localeProvider
/// is per-device, not per-account.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(localeProvider);
    final sections = privacyPolicySections(lang);

    return Scaffold(
      appBar: AppBar(title: Text(s.privacyPolicy)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'en', label: Text('EN')),
              ButtonSegment<String>(value: 'fr', label: Text('FR')),
              ButtonSegment<String>(value: 'es', label: Text('ES')),
            ],
            selected: {lang},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              ref.read(localeProvider.notifier).state = selection.first;
              saveLanguage(selection.first);
            },
          ),
          const SizedBox(height: 20),
          for (final section in sections) ...[
            Text(
              section.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              section.body,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            privacyPolicyUpdated(lang),
            style: TextStyle(
              fontSize: 13,
              color: tokens.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
