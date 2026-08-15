/// A consistent app-bar search field used across Calendar, Insights, Graph,
/// and Workspaces pages.
///
/// Renders an inline [TextField] with search icon, hint text, and a clear
/// button. The width adapts to the available space.
library;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search...',
    this.desktopWidth = 240,
    this.mobileWidth = 160,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final double desktopWidth;
  final double mobileWidth;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final query = controller.text;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final preferredWidth = availableWidth > LayoutConstants.mobileBreakpoint
            ? desktopWidth
            : mobileWidth;
        final width = preferredWidth.clamp(0.0, availableWidth).toDouble();
        return SizedBox(
          width: width,
          height: 44,
          child: TextField(
            focusNode: focusNode,
            controller: controller,
            style: theme.textTheme.bodyMedium,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: query.isNotEmpty
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Clear search',
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}
