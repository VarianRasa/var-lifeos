import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/theme/app_sticky_colors.dart';

void main() {
  test('StickyColorOption maps colors and defaults correctly', () {
    final yellow = StickyColorOption.fromName('yellow');
    expect(yellow.background, const Color(0xFFFEF08A));
    expect(yellow.text, const Color(0xFF713F12));

    final blue = StickyColorOption.fromName('blue');
    expect(blue.background, const Color(0xFFBAE6FD));

    final fallback = StickyColorOption.fromName('unknown');
    expect(fallback, StickyColorOption.yellow);
  });
}
