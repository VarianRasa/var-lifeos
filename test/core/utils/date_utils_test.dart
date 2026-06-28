import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/utils/date_utils.dart';

void main() {
  test('visibleDaysForMonth returns a Monday-first six-week grid', () {
    final days = visibleDaysForMonth(DateTime(2026, 5, 19));

    expect(days, hasLength(42));
    expect(days.first, DateTime(2026, 4, 27));
    expect(days[4], DateTime(2026, 5));
    expect(days.last, DateTime(2026, 6, 7));
  });
}
