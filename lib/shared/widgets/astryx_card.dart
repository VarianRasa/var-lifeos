/// Astryx Design System Card components: AstryxCard, AstryxClickableCard, AstryxSelectableCard.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';

/// Base Card container matching Astryx design tokens (`Card`).
class AstryxCard extends StatelessWidget {
  const AstryxCard({
    required this.child,
    this.title,
    this.subtitle,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    return Card(
      margin: margin,
      color: semantic.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        side: BorderSide(color: semantic.border),
      ),
      child: Padding(
        padding: padding,
        child: _CardContent(title: title, subtitle: subtitle, child: child),
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.child,
    required this.title,
    required this.subtitle,
  });

  final Widget child;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
        ],
        child,
      ],
    );
  }
}

/// Clickable card with hover and tap interactions (`ClickableCard`).
class AstryxClickableCard extends StatelessWidget {
  const AstryxClickableCard({
    required this.child,
    required this.onTap,
    this.title,
    this.subtitle,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? title;
  final String? subtitle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppDesignTokens.of(context);

    final semantic = AppSemanticColors.of(context);
    final radius = BorderRadius.circular(tokens.radiusContainer);

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Card(
          clipBehavior: Clip.antiAlias,
          color: semantic.card,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: semantic.border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: padding,
              child: _CardContent(
                title: title,
                subtitle: subtitle,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selectable Card widget (`SelectableCard`).
class AstryxSelectableCard extends StatelessWidget {
  const AstryxSelectableCard({
    required this.child,
    required this.selected,
    required this.onSelected,
    this.title,
    this.subtitle,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final String? title;
  final String? subtitle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    final borderColor = selected ? semantic.accent : semantic.border;
    final borderWidth = selected ? 2.0 : 1.0;

    final radius = BorderRadius.circular(tokens.radiusContainer);

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: Card(
          clipBehavior: Clip.antiAlias,
          color: selected
              ? semantic.accentMuted.withValues(alpha: 0.1)
              : semantic.card,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: borderColor, width: borderWidth),
          ),
          child: InkWell(
            onTap: () => onSelected(!selected),
            borderRadius: radius,
            child: Padding(
              padding: padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null) ...[
                          Text(
                            title!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 12),
                        ],
                        child,
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? semantic.accent : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? semantic.accent
                            : semantic.borderStrong,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check, size: 12, color: semantic.onAccent)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
