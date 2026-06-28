import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/command/domain/command_date_parser.dart';

void main() {
  test('dateCommandFromQuery parses ISO date queries', () {
    final today = DateTime(2026, 6, 20);

    final command = dateCommandFromQuery('2026-07-04', today: today);

    expect(command?.date, DateTime(2026, 7, 4));
    expect(command?.label, 'Jump to 2026-07-04');
  });

  test('dateCommandFromQuery parses relative date aliases', () {
    final today = DateTime(2026, 6, 20);

    expect(
      dateCommandFromQuery('today', today: today)?.date,
      DateTime(2026, 6, 20),
    );
    expect(
      dateCommandFromQuery('tomorrow', today: today)?.date,
      DateTime(2026, 6, 21),
    );
    expect(
      dateCommandFromQuery('yesterday', today: today)?.date,
      DateTime(2026, 6, 19),
    );
    expect(
      dateCommandFromQuery('besok', today: today)?.date,
      DateTime(2026, 6, 21),
    );
    expect(
      dateCommandFromQuery('kemarin', today: today)?.date,
      DateTime(2026, 6, 19),
    );
  });

  test('dateCommandFromQuery ignores non-date queries', () {
    final today = DateTime(2026, 6, 20);

    expect(dateCommandFromQuery('launch task', today: today), isNull);
    expect(dateCommandFromQuery('2026-99-99', today: today), isNull);
    expect(dateCommandFromQuery('', today: today), isNull);
  });
}
