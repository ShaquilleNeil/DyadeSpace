import 'package:flutter_test/flutter_test.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/widgets/member_tile.dart';

/// Regression test for the role dropdown on WorkerProfileScreen:
/// every role must map to its label, so the dropdown can never
/// show a blank or wrong value.
void main() {
  test('roleLabel maps every role in English', () {
    const s = AppStrings('en');
    expect(roleLabel(s, UserRole.admin), 'Admin');
    expect(roleLabel(s, UserRole.manager), 'Manager');
    expect(roleLabel(s, UserRole.worker), 'Worker');
    expect(roleLabel(s, UserRole.delivery), 'Delivery');
  });

  test('roleLabel maps every role in French', () {
    const s = AppStrings('fr');
    expect(roleLabel(s, UserRole.admin), 'Admin');
    expect(roleLabel(s, UserRole.manager), 'Gestionnaire');
    expect(roleLabel(s, UserRole.worker), 'Ouvrier');
    expect(roleLabel(s, UserRole.delivery), 'Livreur');
  });

  test('roleLabel falls back to English for an unknown locale', () {
    const s = AppStrings('xx');
    expect(roleLabel(s, UserRole.admin), 'Admin');
    expect(roleLabel(s, UserRole.delivery), 'Delivery');
  });
}
