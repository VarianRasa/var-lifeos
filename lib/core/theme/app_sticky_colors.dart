import 'package:flutter/material.dart';

enum StickyColorOption {
  yellow(background: Color(0xFFFEF08A), text: Color(0xFF713F12)),
  blue(background: Color(0xFFBAE6FD), text: Color(0xFF0C4A6E)),
  green(background: Color(0xFFBBF7D0), text: Color(0xFF14532D)),
  pink(background: Color(0xFFFBCFE8), text: Color(0xFF831843)),
  purple(background: Color(0xFFE9D5FF), text: Color(0xFF581C87)),
  orange(background: Color(0xFFFFEDD5), text: Color(0xFF7C2D12));

  final Color background;
  final Color text;

  const StickyColorOption({required this.background, required this.text});

  static StickyColorOption fromName(String? name) {
    return values.firstWhere((e) => e.name == name, orElse: () => yellow);
  }
}
