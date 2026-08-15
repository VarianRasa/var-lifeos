/// Astryx Design System Code & CodeBlock components.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';

/// Inline code snippet widget (<Code>).
class AstryxCode extends StatelessWidget {
  const AstryxCode({required this.code, super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: semantic.surfaceRaised,
        borderRadius: BorderRadius.circular(tokens.radiusInner),
        border: Border.all(color: semantic.border, width: 1),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: semantic.accent,
        ),
      ),
    );
  }
}

/// Multiline code block with header and copy button (`CodeBlock`).
class AstryxCodeBlock extends StatefulWidget {
  const AstryxCodeBlock({
    required this.code,
    this.filename,
    this.language,
    this.showLineNumbers = false,
    super.key,
  });

  final String code;
  final String? filename;
  final String? language;
  final bool showLineNumbers;

  @override
  State<AstryxCodeBlock> createState() => _AstryxCodeBlockState();
}

class _AstryxCodeBlockState extends State<AstryxCodeBlock> {
  bool _copied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final lines = widget.code.split('\n');

    return Container(
      decoration: BoxDecoration(
        color: semantic.surfaceSunken,
        borderRadius: BorderRadius.circular(tokens.radiusElement),
        border: Border.all(color: semantic.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          if (widget.filename != null || widget.language != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: semantic.surfaceRaised,
                border: Border(bottom: BorderSide(color: semantic.border)),
              ),
              child: Row(
                children: [
                  if (widget.filename != null)
                    Text(
                      widget.filename!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: semantic.textPrimary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  if (widget.filename != null && widget.language != null)
                    Text(
                      ' — ',
                      style: TextStyle(
                        fontSize: 12,
                        color: semantic.textDisabled,
                      ),
                    ),
                  if (widget.language != null)
                    Text(
                      widget.language!,
                      style: TextStyle(
                        fontSize: 12,
                        color: semantic.textSecondary,
                      ),
                    ),
                  const Spacer(),
                  InkWell(
                    onTap: _copyToClipboard,
                    borderRadius: BorderRadius.circular(tokens.radiusInner),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 14,
                            color: _copied
                                ? semantic.success
                                : semantic.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'Copied' : 'Copy',
                            style: TextStyle(
                              fontSize: 12,
                              color: _copied
                                  ? semantic.success
                                  : semantic.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Code content
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showLineNumbers) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (int i = 1; i <= lines.length; i++)
                          Text(
                            '$i',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: semantic.textDisabled,
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in lines)
                        Text(
                          line.isEmpty ? ' ' : line,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: semantic.textPrimary,
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
