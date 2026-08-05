import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ColorSwatchCardWidget extends StatelessWidget {
  final String hexColor;
  final String label;
  final List<String> palette;
  final VoidCallback? onTap;

  const ColorSwatchCardWidget({
    super.key,
    required this.hexColor,
    this.label = 'Color Swatch',
    this.palette = const [],
    this.onTap,
  });

  Color _parseColor(String hex) {
    final buffer = StringBuffer();
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) buffer.write('ff');
    buffer.write(clean);
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = _parseColor(hexColor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 100,
              width: double.infinity,
              color: primaryColor,
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        hexColor.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                          fontFamily: 'monospace',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Copy HEX',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: hexColor));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied $hexColor'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  if (palette.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: palette
                          .take(5)
                          .map(
                            (c) => Container(
                              margin: const EdgeInsets.only(right: 4),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: _parseColor(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                  width: 1,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
