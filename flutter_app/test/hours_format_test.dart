import 'package:flutter_test/flutter_test.dart';

import 'package:dyadespace/utils/hours_format.dart';

void main() {
  test('zero hours is 0 min', () {
    expect(formatHoursMinutes(0), '0 min');
  });

  test('under an hour shows minutes only', () {
    expect(formatHoursMinutes(0.42), '25 min');
    expect(formatHoursMinutes(0.5), '30 min');
    expect(formatHoursMinutes(0.02), '1 min');
  });

  test('whole hours show no minutes', () {
    expect(formatHoursMinutes(1), '1 h');
    expect(formatHoursMinutes(2), '2 h');
  });

  test('hours and minutes', () {
    expect(formatHoursMinutes(7.53), '7 h 32 min');
    expect(formatHoursMinutes(7.99), '7 h 59 min');
    expect(formatHoursMinutes(1.25), '1 h 15 min');
  });
}
