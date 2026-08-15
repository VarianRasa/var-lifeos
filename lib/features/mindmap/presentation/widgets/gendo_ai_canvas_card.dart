import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/application/gendo_ai_service.dart';
import 'package:var_app/features/mindmap/application/live_gendo_ai_service.dart';
import 'package:var_app/features/mindmap/domain/gendo_ai_node.dart';

class GendoAiCanvasCard extends StatefulWidget {
  const GendoAiCanvasCard({
    required this.data,
    required this.onChanged,
    this.client,
    this.onDelete,
    super.key,
  });

  final GendoAiNodeData data;
  final ValueChanged<GendoAiNodeData> onChanged;
  final GendoAiClient? client;
  final VoidCallback? onDelete;

  @override
  State<GendoAiCanvasCard> createState() => _GendoAiCanvasCardState();
}

class _GendoAiCanvasCardState extends State<GendoAiCanvasCard> {
  late TextEditingController _promptController;
  late TextEditingController _negativePromptController;
  bool _isGenerating = false;
  int _tabIndex = 0; // 0 = Output Render, 1 = Source Input

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.data.prompt);
    _negativePromptController = TextEditingController(
      text: widget.data.negativePrompt,
    );
  }

  @override
  void didUpdateWidget(covariant GendoAiCanvasCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.prompt != widget.data.prompt &&
        _promptController.text != widget.data.prompt) {
      _promptController.text = widget.data.prompt;
    }
    if (oldWidget.data.negativePrompt != widget.data.negativePrompt &&
        _negativePromptController.text != widget.data.negativePrompt) {
      _negativePromptController.text = widget.data.negativePrompt;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    super.dispose();
  }

  void _onPromptChanged(String val) {
    widget.onChanged(widget.data.copyWith(prompt: val));
  }

  void _onNegativePromptChanged(String val) {
    widget.onChanged(widget.data.copyWith(negativePrompt: val));
  }

  void _onStyleSelected(GendoAiStylePreset style) {
    widget.onChanged(widget.data.copyWith(selectedStyle: style));
  }

  void _onStrengthChanged(double val) {
    widget.onChanged(widget.data.copyWith(strength: val));
  }

  Future<void> _handleGenerate() async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);

    try {
      final client = widget.client ?? LiveGendoAiService();
      final updatedData = await client.generateRender(
        widget.data,
        promptOverride: _promptController.text,
        styleOverride: widget.data.selectedStyle,
        strengthOverride: widget.data.strength,
      );
      widget.onChanged(updatedData);
      if (mounted) {
        setState(() => _tabIndex = 0);
      }
    } catch (_) {
      // Keep state intact on failure
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _onIterationSelected(int index) {
    final client = widget.client ?? LiveGendoAiService();
    final updatedData = client.selectIteration(widget.data, index);
    widget.onChanged(updatedData);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeIter = widget.data.activeIteration;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 420,
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2F2F3B), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(theme),

            // Preview & Tabs
            _buildPreviewArea(theme, activeIter),

            // Prompt inputs
            _buildPromptInputs(theme),

            // Style preset selector
            _buildStylePresetSelector(theme),

            // Controls & Strength
            _buildActionControls(theme),

            // Iteration History Tray
            if (widget.data.iterations.isNotEmpty)
              _buildIterationHistory(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final status =
        widget.data.activeIteration?.status ?? GendoAiRenderStatus.idle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF14141A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
        border: Border(bottom: BorderSide(color: Color(0xFF282834))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Gendo AI Studio',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          _buildStatusBadge(status),
          const Spacer(),
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.close, size: 15, color: Colors.white70),
              onPressed: widget.onDelete,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 14,
              tooltip: 'Delete Node',
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(GendoAiRenderStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case GendoAiRenderStatus.generating:
        bg = const Color(0xFF3B82F6).withValues(alpha: 0.2);
        fg = const Color(0xFF60A5FA);
        label = 'Rendering...';
        break;
      case GendoAiRenderStatus.completed:
        bg = const Color(0xFF10B981).withValues(alpha: 0.2);
        fg = const Color(0xFF34D399);
        label = 'Ready';
        break;
      case GendoAiRenderStatus.failed:
        bg = const Color(0xFFEF4444).withValues(alpha: 0.2);
        fg = const Color(0xFFF87171);
        label = 'Failed';
        break;
      case GendoAiRenderStatus.idle:
        bg = Colors.white.withValues(alpha: 0.05);
        fg = Colors.white60;
        label = 'Idle';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildPreviewArea(
    ThemeData theme,
    GendoAiRenderIteration? activeIter,
  ) {
    return Column(
      children: [
        // Tabs
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          color: const Color(0xFF16161D),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  title: 'AI Output Render',
                  isSelected: _tabIndex == 0,
                  onTap: () => setState(() => _tabIndex = 0),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildTabButton(
                  title: 'Source Input / Sketch',
                  isSelected: _tabIndex == 1,
                  onTap: () => setState(() => _tabIndex = 1),
                ),
              ),
            ],
          ),
        ),
        // Image Viewport
        Container(
          height: 140,
          width: double.infinity,
          color: const Color(0xFF101014),
          child: _isGenerating
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Generating render...',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : _tabIndex == 0
              ? _buildOutputPreview(activeIter)
              : _buildSourcePreview(),
        ),
      ],
    );
  }

  Widget _buildTabButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2A2A36) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _buildOutputPreview(GendoAiRenderIteration? activeIter) {
    if (activeIter == null || activeIter.outputImageUrl.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 28,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 4),
            Text(
              'No renders generated yet.\nEnter a prompt and hit Generate.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return Image.network(
      activeIter.outputImageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            activeIter.outputImageUrl,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildSourcePreview() {
    final source = widget.data.sourceImageUrl;
    if (source == null || source.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.draw_outlined,
              size: 28,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 4),
            Text(
              'No source sketch linked.\nConnect a sketch node or reference.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return Image.network(
      source,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            source,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptInputs(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _promptController,
            onChanged: _onPromptChanged,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Prompt: e.g. Modern concrete pavilion...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
              filled: true,
              fillColor: const Color(0xFF131318),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF2A2A36)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF2A2A36)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF6366F1)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _negativePromptController,
            onChanged: _onNegativePromptChanged,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Negative prompt: blurry, artifacts, low resolution...',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 10),
              filled: true,
              fillColor: const Color(0xFF131318),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF2A2A36)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF2A2A36)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF6366F1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStylePresetSelector(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STYLE PRESETS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: GendoAiStylePreset.values.map((preset) {
              final isSelected = widget.data.selectedStyle == preset;
              return InkWell(
                onTap: () => _onStyleSelected(preset),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFF171720),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF6366F1)
                          : const Color(0xFF2A2A36),
                    ),
                  ),
                  child: Text(
                    preset.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionControls(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Strength: ${(widget.data.strength * 100).toInt()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF6366F1),
                    thumbColor: const Color(0xFF818CF8),
                    overlayColor: const Color(
                      0xFF6366F1,
                    ).withValues(alpha: 0.2),
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                  ),
                  child: Slider(
                    value: widget.data.strength,
                    min: 0.0,
                    max: 1.0,
                    onChanged: _onStrengthChanged,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _handleGenerate,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bolt, size: 14, color: Colors.white),
              label: Text(
                _isGenerating ? 'Rendering...' : 'Generate Render',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIterationHistory(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF131319),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
        border: Border(top: BorderSide(color: Color(0xFF252530))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ITERATION HISTORY',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.data.iterations.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final isSelected = widget.data.activeIterationIndex == index;

                return InkWell(
                  onTap: () => _onIterationSelected(index),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E28),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF818CF8)
                            : const Color(0xFF2E2E3C),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
