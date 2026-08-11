/// Astryx Design System Avatar and Avatar Group components.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class AstryxAvatar extends StatelessWidget {
  const AstryxAvatar({
    this.imageUrl,
    this.name,
    this.size = 32.0,
    this.backgroundColor,
    super.key,
  });

  final String? imageUrl;
  final String? name;
  final double size;
  final Color? backgroundColor;

  String get _initials {
    if (name == null || name!.trim().isEmpty) return '?';
    final parts = name!.trim().split(' ');
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);

    final bg = backgroundColor ?? semantic.surfaceRaised;
    final fg = semantic.textPrimary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: semantic.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildInitials(fg),
            )
          : _buildInitials(fg),
    );
  }

  Widget _buildInitials(Color fg) {
    return Center(
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class AstryxAvatarGroup extends StatelessWidget {
  const AstryxAvatarGroup({
    required this.avatars,
    this.maxVisible = 3,
    this.size = 32.0,
    super.key,
  });

  final List<AstryxAvatar> avatars;
  final int maxVisible;
  final double size;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);

    final visibleCount = avatars.length > maxVisible
        ? maxVisible
        : avatars.length;
    final overflow = avatars.length - visibleCount;

    final overlapOffset = size * 0.65;

    return SizedBox(
      height: size,
      width:
          visibleCount * overlapOffset +
          (overflow > 0 ? overlapOffset : size * 0.35),
      child: Stack(
        children: [
          for (int i = 0; i < visibleCount; i++)
            Positioned(left: i * overlapOffset, child: avatars[i]),
          if (overflow > 0)
            Positioned(
              left: visibleCount * overlapOffset,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: semantic.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: semantic.border, width: 1),
                ),
                child: Center(
                  child: Text(
                    '+$overflow',
                    style: TextStyle(
                      fontSize: size * 0.35,
                      fontWeight: FontWeight.w600,
                      color: semantic.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
