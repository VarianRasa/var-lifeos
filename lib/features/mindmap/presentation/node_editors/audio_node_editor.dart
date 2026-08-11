library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../../domain/node_type_payloads.dart';
import '../../domain/offline_audio_transcription.dart';
import 'audio_recording_storage.dart';
import 'productivity_node_editors.dart';

final class PickAudioFileAction {
  PickAudioFileAction(this.existing);
  final AudioPayload existing;
  final Completer<AudioPayload?> result = Completer<AudioPayload?>();
}

final class ImportRecordedAudioAction {
  ImportRecordedAudioAction(this.bytes, this.existing);
  final Uint8List bytes;
  final AudioPayload existing;
  final Completer<AudioPayload?> result = Completer<AudioPayload?>();
}

final class TranscribeAudioAction {
  TranscribeAudioAction(this.payload);
  final AudioPayload payload;
  final Completer<AudioPayload?> result = Completer<AudioPayload?>();
}

final class LoadAudioAttachmentAction {
  LoadAudioAttachmentAction(this.attachmentId);
  final String attachmentId;
  final Completer<Uint8List?> result = Completer<Uint8List?>();
}

final class DeleteAudioVoiceNoteAction {
  DeleteAudioVoiceNoteAction(this.payload);
  final AudioPayload payload;
  final Completer<AudioPayload?> result = Completer<AudioPayload?>();
}

final class AudioNodeEditor extends StatefulWidget {
  const AudioNodeEditor({
    required this.context,
    required this.payload,
    super.key,
  });
  final NodeEditContext context;
  final AudioPayload payload;

  @override
  State<AudioNodeEditor> createState() => _AudioNodeEditorState();
}

final class _AudioNodeEditorState extends State<AudioNodeEditor> {
  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  final BytesBuilder _recordedBytes = BytesBuilder(copy: false);
  late final TextEditingController _urlController;
  late final FocusNode _urlFocusNode;
  late AudioPayload _draft;
  StreamSubscription<Uint8List>? _recordSubscription;
  Timer? _recordTimer;
  var _recording = false;
  var _recordPaused = false;
  var _recordedSeconds = 0;
  var _busy = false;
  String? _error;
  String? _recordingPath;
  Uint8List? _loadedAttachmentBytes;
  String? _loadedSourceKey;
  String? _playbackSourcePath;

  @override
  void initState() {
    super.initState();
    _draft = widget.payload;
    _urlController = TextEditingController(text: widget.payload.remoteUrl);
    _urlFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant AudioNodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_urlFocusNode.hasFocus) return;
    _draft = widget.payload;
    if (_urlController.text != widget.payload.remoteUrl) {
      _urlController.value = TextEditingValue(
        text: widget.payload.remoteUrl,
        selection: TextSelection.collapsed(
          offset: widget.payload.remoteUrl.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    unawaited(_recordSubscription?.cancel());
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    final playbackSourcePath = _playbackSourcePath;
    if (playbackSourcePath != null) {
      unawaited(deleteAudioPlaybackSource(playbackSourcePath));
    }
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  void _emit(AudioPayload payload) {
    setState(() => _draft = payload);
    widget.context.onDraftChanged(payload);
  }

  Future<void> _pickFile() async {
    final callback = widget.context.onKnowledgeAction;
    if (callback == null) return;
    final action = PickAudioFileAction(_draft);
    await callback(action);
    final payload = await action.result.future;
    if (payload != null && mounted) _emit(payload);
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Microphone permission is required.');
      return;
    }
    try {
      const config = RecordConfig(encoder: AudioEncoder.wav);
      if (audioRecordingUsesStream) {
        final stream = await _recorder.startStream(config);
        _recordSubscription = stream.listen(_recordedBytes.add);
      } else {
        final path = await createAudioRecordingPath();
        _recordingPath = path;
        await _recorder.start(config, path: path);
      }
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_recordPaused && mounted) {
          setState(() => _recordedSeconds += 1);
          if (_recordedSeconds >= 600) unawaited(_stopRecording());
        }
      });
      setState(() {
        _recording = true;
        _recordPaused = false;
        _recordedSeconds = 0;
        _error = null;
      });
    } on Object catch (error) {
      setState(() => _error = 'Unable to start recording: $error');
    }
  }

  Future<void> _togglePause() async {
    if (_recordPaused) {
      await _recorder.resume();
    } else {
      await _recorder.pause();
    }
    if (mounted) setState(() => _recordPaused = !_recordPaused);
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final stoppedPath = await _recorder.stop();
    await _recordSubscription?.cancel();
    _recordSubscription = null;
    Uint8List bytes;
    if (audioRecordingUsesStream) {
      bytes = _recordedBytes.takeBytes();
    } else {
      final path = stoppedPath ?? _recordingPath;
      bytes = path == null ? Uint8List(0) : await readAudioRecording(path);
      if (path != null) await deleteAudioRecording(path);
      _recordingPath = null;
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _recordPaused = false;
      });
    }
    if (bytes.isEmpty || widget.context.onKnowledgeAction == null) return;
    final action = ImportRecordedAudioAction(bytes, _draft);
    await widget.context.onKnowledgeAction!(action);
    final payload = await action.result.future;
    if (payload != null && mounted) _emit(payload);
  }

  Future<void> _loadAndToggle() async {
    try {
      final sourceKey = _draft.sourceType == AudioSourceType.url
          ? 'url:${_draft.remoteUrl}'
          : 'attachment:${_draft.attachmentId}';
      if (_loadedSourceKey != sourceKey) {
        final playbackSourcePath = _playbackSourcePath;
        if (playbackSourcePath != null) {
          await deleteAudioPlaybackSource(playbackSourcePath);
          _playbackSourcePath = null;
        }
        if (_draft.sourceType == AudioSourceType.url) {
          await _player.setUrl(_draft.remoteUrl);
        } else {
          var bytes = widget.context.attachmentBytes ?? _loadedAttachmentBytes;
          if (bytes == null &&
              _draft.attachmentId.isNotEmpty &&
              widget.context.onKnowledgeAction != null) {
            final action = LoadAudioAttachmentAction(_draft.attachmentId);
            await widget.context.onKnowledgeAction!(action);
            bytes = await action.result.future;
            _loadedAttachmentBytes = bytes;
          }
          if (bytes == null) {
            setState(() => _error = 'Stored audio could not be loaded.');
            return;
          }
          final mimeType = _draft.mimeType.isEmpty
              ? 'audio/mpeg'
              : _draft.mimeType;
          final playbackSourcePath = await createAudioPlaybackSource(
            bytes,
            mimeType,
          );
          _playbackSourcePath = playbackSourcePath;
          await _player.setFilePath(playbackSourcePath);
        }
        _loadedSourceKey = sourceKey;
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        unawaited(_player.play());
      }
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to play audio: $error');
      }
    }
  }

  Future<void> _deleteVoiceNote() async {
    final callback = widget.context.onKnowledgeAction;
    if (callback == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete voice note?'),
        content: const Text(
          'Audio recording will be removed. Transcript text will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final action = DeleteAudioVoiceNoteAction(_draft);
    await callback(action);
    final payload = await action.result.future;
    if (!mounted || payload == null) return;
    await _player.stop();
    _loadedAttachmentBytes = null;
    _loadedSourceKey = null;
    _emit(payload);
  }

  Future<void> _transcribe() async {
    final callback = widget.context.onKnowledgeAction;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (callback != null) {
      final action = TranscribeAudioAction(_draft);
      await callback(action);
      final payload = await action.result.future;
      if (mounted) setState(() => _busy = false);
      if (payload != null) {
        _emit(payload);
        return;
      }
    }

    // Offline transcription engine fallback
    const engine = OfflineAudioTranscriptionEngine();
    final result = await engine.transcribeOffline(
      bytes: _loadedAttachmentBytes ?? const [],
      fileName: 'voice_note.m4a',
    );

    if (!mounted) return;
    setState(() => _busy = false);
    _emit(
      _draft.copyWith(
        transcriptText: result.text,
        transcriptSegments: [
          for (final seg in result.segments)
            AudioTranscriptSegment(
              id: seg.id,
              startMilliseconds: seg.startMilliseconds,
              endMilliseconds: seg.endMilliseconds,
              text: seg.text,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = _draft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('audio-record-action'),
              onPressed: _recording ? null : _startRecording,
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Record'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('audio-choose-file-action'),
              onPressed: _recording ? null : _pickFile,
              icon: const Icon(Icons.audio_file_rounded),
              label: const Text('Choose file'),
            ),
          ],
        ),
        if (_recording) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.fiber_manual_record,
                color: Theme.of(context).colorScheme.error,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '${_durationLabel(Duration(seconds: _recordedSeconds))} / 10:00',
              ),
              const Spacer(),
              IconButton(
                onPressed: _togglePause,
                icon: Icon(
                  _recordPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
                tooltip: _recordPaused ? 'Resume recording' : 'Pause recording',
              ),
              IconButton(
                onPressed: _stopRecording,
                icon: const Icon(Icons.stop_rounded),
                tooltip: 'Stop recording',
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey('audio-online-url-field'),
          controller: _urlController,
          focusNode: _urlFocusNode,
          decoration: const InputDecoration(
            labelText: 'Online audio URL (HTTPS)',
            prefixIcon: Icon(Icons.link_rounded),
          ),
          keyboardType: TextInputType.url,
          onChanged: (value) => _emit(
            payload.copyWith(
              sourceType: value.trim().isEmpty
                  ? AudioSourceType.none
                  : AudioSourceType.url,
              remoteUrl: value,
              attachmentId: '',
              fileName: '',
              mimeType: '',
              sizeBytes: 0,
            ),
          ),
        ),
        if (payload.sourceType != AudioSourceType.none) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('audio-play-action'),
                        onPressed: _loadAndToggle,
                        icon: Icon(
                          _player.playing
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                        ),
                        iconSize: 38,
                      ),
                      Expanded(
                        child: Text(
                          payload.fileName.isNotEmpty
                              ? payload.fileName
                              : payload.remoteUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      StreamBuilder<Duration?>(
                        stream: _player.durationStream,
                        builder: (context, snapshot) => Text(
                          _durationLabel(
                            snapshot.data ??
                                Duration(
                                  milliseconds: payload.durationMilliseconds,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, snapshot) {
                      final duration =
                          _player.duration ??
                          Duration(milliseconds: payload.durationMilliseconds);
                      final max = duration.inMilliseconds <= 0
                          ? 1.0
                          : duration.inMilliseconds.toDouble();
                      final value = (snapshot.data ?? Duration.zero)
                          .inMilliseconds
                          .clamp(0, max.toInt())
                          .toDouble();
                      return Slider(
                        value: value,
                        max: max,
                        onChanged: (next) =>
                            _player.seek(Duration(milliseconds: next.round())),
                      );
                    },
                  ),
                  Row(
                    children: [
                      const Text('Speed'),
                      const SizedBox(width: 8),
                      DropdownButton<double>(
                        value: _player.speed,
                        items: const [0.75, 1.0, 1.25, 1.5, 2.0]
                            .map(
                              (speed) => DropdownMenuItem(
                                value: speed,
                                child: Text('${speed}x'),
                              ),
                            )
                            .toList(),
                        onChanged: (speed) {
                          if (speed != null) unawaited(_player.setSpeed(speed));
                          setState(() {});
                        },
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _busy ? null : _transcribe,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: const Text('AI transcript'),
                      ),
                    ],
                  ),
                  IconButton(
                    key: const ValueKey('audio-delete-action'),
                    tooltip: 'Delete voice note',
                    onPressed: _deleteVoiceNote,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('audio-transcript-field'),
          initialValue: payload.transcriptText.isNotEmpty
              ? payload.transcriptText
              : payload.audioTranscript,
          decoration: const InputDecoration(
            labelText: 'Transcript',
            alignLabelWithHint: true,
          ),
          minLines: 3,
          maxLines: 8,
          onChanged: (value) => _emit(
            payload.copyWith(
              transcriptText: value,
              transcriptSegments: const <AudioTranscriptSegment>[],
            ),
          ),
        ),
        if (payload.transcriptSegments.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final segment in payload.transcriptSegments.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(
                _durationLabel(
                  Duration(milliseconds: segment.startMilliseconds),
                ),
              ),
              title: Text(
                segment.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _player.seek(
                Duration(milliseconds: segment.startMilliseconds),
              ),
            ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

String _durationLabel(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
