import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../application/yt_music_service.dart';
import '../domain/yt_music_track.dart';

class YtMusicPlaylistDialog extends StatefulWidget {
  const YtMusicPlaylistDialog({
    required this.service,
    required this.activeTrackId,
    required this.onSelectTrack,
    super.key,
  });

  final YtMusicService service;
  final String? activeTrackId;
  final ValueChanged<YtMusicTrack?> onSelectTrack;

  @override
  State<YtMusicPlaylistDialog> createState() => _YtMusicPlaylistDialogState();
}

class _YtMusicPlaylistDialogState extends State<YtMusicPlaylistDialog> {
  List<YtMusicTrack> _tracks = [];
  bool _isLoading = true;
  String? _selectedId;

  final _titleController = TextEditingController();
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedId = widget.activeTrackId;
    _load();
  }

  Future<void> _load() async {
    final list = await widget.service.loadTracks();
    setState(() {
      _tracks = list;
      _isLoading = false;
    });
  }

  Future<void> _addTrack() async {
    final title = _titleController.text.trim();
    final url = _urlController.text.trim();
    if (title.isEmpty || url.isEmpty) return;

    final newTrack = YtMusicTrack(
      id: 'track-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      url: url,
    );

    final updated = [..._tracks, newTrack];
    await widget.service.saveTracks(updated);
    _titleController.clear();
    _urlController.clear();
    setState(() => _tracks = updated);
  }

  Future<void> _deleteTrack(String id) async {
    final updated = _tracks.where((t) => t.id != id).toList();
    await widget.service.saveTracks(updated);
    if (_selectedId == id) {
      _selectedId = null;
      widget.onSelectTrack(null);
    }
    setState(() => _tracks = updated);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.music_note, color: semantic.danger),
          const SizedBox(width: 8),
          const Text('Playlist YouTube Music'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tambah Lagu / Playlist YT Music',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Judul Lagu/Playlist',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _urlController,
                              decoration: const InputDecoration(
                                labelText:
                                    'Link YT Music (https://music.youtube.com/...)',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _addTrack,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Simpan'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_tracks.isEmpty)
                      const Text('Belum ada lagu tersimpan.')
                    else
                      Column(
                        children: _tracks.map((t) {
                          final isSelected = t.id == _selectedId;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              t.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.open_in_new, size: 16),
                                  onPressed: () =>
                                      widget.service.launchTrack(t.url),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                  ),
                                  onPressed: () => _deleteTrack(t.id),
                                ),
                              ],
                            ),
                            onTap: () {
                              setState(() => _selectedId = t.id);
                              widget.service.setActiveTrackId(t.id);
                              widget.onSelectTrack(t);
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
