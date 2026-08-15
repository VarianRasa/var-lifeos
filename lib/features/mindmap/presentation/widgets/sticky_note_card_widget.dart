import 'package:flutter/material.dart';
import '../../../../core/theme/app_sticky_colors.dart';

class StickyNoteCardWidget extends StatelessWidget {
  final String title;
  final String body;
  final StickyColorOption colorOption;
  final ValueChanged<StickyColorOption>? onColorChanged;

  const StickyNoteCardWidget({
    super.key,
    required this.title,
    required this.body,
    required this.colorOption,
    this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      constraints: const BoxConstraints(minHeight: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorOption.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.push_pin_outlined,
                size: 16,
                color: colorOption.text.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.isEmpty ? 'Note' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorOption.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (onColorChanged != null)
                PopupMenuButton<StickyColorOption>(
                  icon: Icon(
                    Icons.palette_outlined,
                    size: 16,
                    color: colorOption.text.withValues(alpha: 0.7),
                  ),
                  onSelected: onColorChanged,
                  itemBuilder: (context) => [
                    for (final opt in StickyColorOption.values)
                      PopupMenuItem(
                        value: opt,
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: opt.background,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(opt.name),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              body.isEmpty ? 'No details' : body,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorOption.text.withValues(alpha: 0.9),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
