import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/focus_audio_player_service.dart';
import '../domain/focus_audio_track.dart';

class FocusMusicPlaylistDialog extends ConsumerStatefulWidget {
  const FocusMusicPlaylistDialog({super.key});

  @override
  ConsumerState<FocusMusicPlaylistDialog> createState() =>
      _FocusMusicPlaylistDialogState();
}

class _FocusMusicPlaylistDialogState
    extends ConsumerState<FocusMusicPlaylistDialog> {
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _artistController = TextEditingController();
  final _playlistUrlController = TextEditingController();
  final _searchController = TextEditingController();

  bool _isImportingPlaylist = false;
  bool _isSearching = false;
  List<FocusAudioTrack> _searchResults = [];
  String? _searchError;

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _artistController.dispose();
    _playlistUrlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _addTrack() {
    final title = _titleController.text.trim();
    final url = _urlController.text.trim();

    if (title.isEmpty || url.isEmpty) return;

    final isYt = FocusAudioPlayerNotifier.isYoutubeUrl(url);
    final defaultArtist = isYt ? 'YouTube Music' : 'Custom Stream';
    final artist = _artistController.text.trim().isEmpty
        ? defaultArtist
        : _artistController.text.trim();

    final newTrack = FocusAudioTrack(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      artist: artist,
      audioUrl: url,
      isPreset: false,
      category: isYt ? 'YT Music' : 'Custom',
    );

    ref.read(focusAudioPlayerServiceProvider.notifier).addCustomTrack(newTrack);
    _titleController.clear();
    _urlController.clear();
    _artistController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lagu berhasil ditambahkan ke playlist!')),
    );
  }

  Future<void> _importPlaylist() async {
    final url = _playlistUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isImportingPlaylist = true;
    });

    try {
      final count = await ref
          .read(focusAudioPlayerServiceProvider.notifier)
          .importYoutubePlaylist(url);
      _playlistUrlController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Berhasil mengimpor $count lagu dari playlist YouTube!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengimpor playlist: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImportingPlaylist = false;
        });
      }
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await ref
          .read(focusAudioPlayerServiceProvider.notifier)
          .searchYoutube(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = 'Gagal mencari musik: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final audioState = ref.watch(focusAudioPlayerServiceProvider);
    final notifier = ref.read(focusAudioPlayerServiceProvider.notifier);

    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.library_music, color: semantic.accent),
                const SizedBox(width: 8),
                const Text('Musik Fokus & YouTube API'),
              ],
            ),
            const SizedBox(height: 12),
            TabBar(
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(
                  icon: Icon(Icons.queue_music, size: 18),
                  text: 'Playlist Saya',
                ),
                Tab(icon: Icon(Icons.search, size: 18), text: 'Cari YT Music'),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 440,
          child: TabBarView(
            children: [
              // Tab 1: Playlist & Manual/Playlist Link Import
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    // Import YouTube Playlist Card
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Import Playlist YouTube / YT Music',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _playlistUrlController,
                                    decoration: const InputDecoration(
                                      labelText: 'Link Playlist YouTube Music',
                                      hintText:
                                          'https://music.youtube.com/playlist?list=...',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: _isImportingPlaylist
                                      ? null
                                      : _importPlaylist,
                                  icon: _isImportingPlaylist
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: semantic.onAccent,
                                          ),
                                        )
                                      : const Icon(Icons.download, size: 16),
                                  label: Text(
                                    _isImportingPlaylist
                                        ? 'Mengimpor...'
                                        : 'Import',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Manual Stream Addition Card
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tambah Single Audio Stream / Link Lagu',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Judul Lagu/Stream',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _artistController,
                              decoration: const InputDecoration(
                                labelText: 'Artis / Sumber (Opsional)',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _urlController,
                              decoration: const InputDecoration(
                                labelText:
                                    'Direct MP3/Stream URL atau Link YT Video',
                                hintText:
                                    'https://youtu.be/... atau https://...mp3',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _addTrack,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Tambah Stream'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Daftar Audio Focus (${audioState.tracks.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (audioState.tracks.isEmpty)
                      const Text('Belum ada lagu tersimpan.')
                    else
                      Column(
                        children: audioState.tracks.map((track) {
                          final isSelected =
                              track.id == audioState.currentTrack?.id;
                          final isYt = FocusAudioPlayerNotifier.isYoutubeUrl(
                            track.audioUrl,
                          );
                          final isPlaying = isSelected && audioState.isPlaying;

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isSelected
                                  ? Icons.play_circle_filled
                                  : (isYt
                                        ? Icons.music_note
                                        : Icons.music_note_outlined),
                              color: isSelected
                                  ? (isYt ? semantic.danger : semantic.accent)
                                  : null,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: isSelected
                                  ? const TextStyle(fontWeight: FontWeight.bold)
                                  : null,
                            ),
                            subtitle: Text(
                              isYt
                                  ? '${track.artist} • In-App YouTube Audio'
                                  : '${track.artist} • ${track.category}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!track.isPreset)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    onPressed: () =>
                                        notifier.deleteTrack(track.id),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    if (isSelected) {
                                      notifier.togglePlayPause();
                                    } else {
                                      notifier.selectTrack(track);
                                      notifier.playTrack(track);
                                    }
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              notifier.selectTrack(track);
                              notifier.playTrack(track);
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),

              // Tab 2: Cari YT Music API In-App
              Column(
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Cari Lagu / Lofi / Focus Music',
                            hintText: 'Misal: Lofi Hip Hop Study, Piano Focus',
                            isDense: true,
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: (_) => _performSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _isSearching ? null : _performSearch,
                        child: _isSearching
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: semantic.onAccent,
                                ),
                              )
                            : const Text('Cari'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isSearching)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_searchError != null)
                    Expanded(
                      child: Center(
                        child: Text(
                          _searchError!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    )
                  else if (_searchResults.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Ketik kata kunci untuk mencari lagu YouTube Music.',
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final track = _searchResults[index];
                          final isInPlaylist = audioState.tracks.any(
                            (t) => t.audioUrl == track.audioUrl,
                          );

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.music_note,
                              color: semantic.danger,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                isInPlaylist
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: isInPlaylist
                                    ? semantic.success
                                    : semantic.accent,
                              ),
                              tooltip: isInPlaylist
                                  ? 'Tersimpan'
                                  : 'Tambah ke Playlist',
                              onPressed: isInPlaylist
                                  ? null
                                  : () {
                                      notifier.addCustomTrack(track);
                                      setState(() {});
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '"${track.title}" ditambahkan ke playlist!',
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}
