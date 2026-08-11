/// Astryx Design System Segmented Control component.
library;

import 'package:flutter/material.dart';

class AstryxSegmentOption<T> {
  const AstryxSegmentOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class AstryxSegmentedControl<T> extends StatelessWidget {
  AstryxSegmentedControl({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  }) : assert(options.isNotEmpty),
       assert(_hasUniqueValues(options)),
       assert(_selectedAppearsOnce(options, selected));

  final List<AstryxSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final control = SegmentedButton<T>(
          segments: [
            for (final option in options)
              ButtonSegment<T>(
                value: option.value,
                label: Text(option.label),
                icon: option.icon == null ? null : Icon(option.icon),
              ),
          ],
          selected: <T>{selected},
          onSelectionChanged: (values) => onChanged(values.single),
          showSelectedIcon: false,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(44, 44)),
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
          ),
        );
        if (!constraints.hasBoundedWidth) return control;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: control,
        );
      },
    );
  }

  static bool _hasUniqueValues<T>(List<AstryxSegmentOption<T>> options) {
    return options.map((option) => option.value).toSet().length ==
        options.length;
  }

  static bool _selectedAppearsOnce<T>(
    List<AstryxSegmentOption<T>> options,
    T selected,
  ) {
    return options.where((option) => option.value == selected).length == 1;
  }
}
