import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/link_metadata.dart';

class LinkPreviewCardWidget extends StatelessWidget {
  final LinkMetadata metadata;
  final VoidCallback? onTap;
  final ValueChanged<LinkPreviewStyle>? onStyleChanged;

  const LinkPreviewCardWidget({
    super.key,
    required this.metadata,
    this.onTap,
    this.onStyleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: metadata.style == LinkPreviewStyle.compact ? 220 : 280,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (metadata.style == LinkPreviewStyle.banner &&
                    metadata.imageUrl != null)
                  Image.network(
                    metadata.imageUrl!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (metadata.faviconUrl != null) ...[
                            Image.network(
                              metadata.faviconUrl!,
                              width: 14,
                              height: 14,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.public, size: 14),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              metadata.siteName ?? metadata.url,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (metadata.title != null)
                        Text(
                          metadata.title!,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (metadata.style != LinkPreviewStyle.compact &&
                          metadata.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          metadata.description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: metadata.style == LinkPreviewStyle.quote
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                          maxLines: metadata.style == LinkPreviewStyle.quote ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (onStyleChanged != null)
              Positioned(
                top: 4,
                right: 4,
                child: PopupMenuButton<LinkPreviewStyle>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Preview Style',
                  onSelected: onStyleChanged,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: LinkPreviewStyle.banner,
                      child: Text('Banner Card'),
                    ),
                    const PopupMenuItem(
                      value: LinkPreviewStyle.compact,
                      child: Text('Compact Bookmark'),
                    ),
                    const PopupMenuItem(
                      value: LinkPreviewStyle.quote,
                      child: Text('Quote Snippet'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
