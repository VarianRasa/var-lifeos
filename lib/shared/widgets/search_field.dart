/// A consistent app-bar search field used across Calendar, Insights, Graph,
/// and Workspaces pages.
///
/// Renders an inline [TextField] with search icon, hint text, and a clear
/// button. The width adapts to the available space.
library;

import 'package:flutter/material.dart';

class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search...',
    this.desktopWidth = 240,
    this.mobileWidth = 160,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final double desktopWidth;
  final double mobileWidth;

  @override
  Widget build(BuildContext context) {
    final query = controller.text;
    final theme = Theme.of(context);
    return SizedBox(
      width: MediaQuery.sizeOf(context).width >= 840
          ? desktopWidth
          : mobileWidth,
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: query.isNotEmpty ? theme.colorScheme.primary : null,
          ),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          isDense: true,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
