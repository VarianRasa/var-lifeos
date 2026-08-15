import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/node_type_payloads.dart';
import 'productivity_node_editors.dart';

class ResourceAssetPreview extends StatelessWidget {
  const ResourceAssetPreview({
    required this.asset,
    this.bytes,
    this.loading = false,
    this.error,
    this.compact = false,
    super.key,
  });

  final ResourceAsset asset;
  final Uint8List? bytes;
  final bool loading;
  final String? error;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 72.0 : 180.0;
    if (loading) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return _AssetFallback(
        key: const ValueKey<String>('resource-preview-unavailable'),
        asset: asset,
        icon: Icons.cloud_off_outlined,
        label: 'Unavailable',
        height: height,
      );
    }
    if (asset.isImage && bytes != null) {
      return SizedBox(
        key: const ValueKey<String>('resource-preview-image'),
        height: height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes!, fit: BoxFit.cover),
        ),
      );
    }
    if (asset.isImage && asset.isUrl) {
      return SizedBox(
        key: const ValueKey<String>('resource-preview-image'),
        height: height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            asset.location,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _AssetFallback(
              key: const ValueKey<String>('resource-preview-url'),
              asset: asset,
              icon: Icons.language_outlined,
              label: resourceUrlHost(asset.location),
              height: height,
            ),
          ),
        ),
      );
    }
    final type = resourceAssetTypeLabel(asset);
    final (key, icon) = switch (type) {
      'URL' => (
        const ValueKey<String>('resource-preview-url'),
        Icons.language_outlined,
      ),
      'Document' => (
        const ValueKey<String>('resource-preview-document'),
        Icons.description_outlined,
      ),
      'Audio' => (
        const ValueKey<String>('resource-preview-audio'),
        Icons.audio_file_outlined,
      ),
      'Video' => (
        const ValueKey<String>('resource-preview-video'),
        Icons.video_file_outlined,
      ),
      _ => (
        const ValueKey<String>('resource-preview-generic'),
        Icons.insert_drive_file_outlined,
      ),
    };
    return _AssetFallback(
      key: key,
      asset: asset,
      icon: icon,
      label: type == 'URL' ? resourceUrlHost(asset.location) : type,
      height: height,
    );
  }
}

class ResourceNodePreview extends StatelessWidget {
  const ResourceNodePreview({
    required this.payload,
    this.primaryBytes,
    this.primaryLoading = false,
    this.primaryError,
    this.compact = false,
    this.collapsed = false,
    super.key,
  });

  final ResourcePayload payload;
  final Uint8List? primaryBytes;
  final bool primaryLoading;
  final String? primaryError;
  final bool compact;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final primary = payload.primaryAsset;
        final allAssets = <ResourceAsset>[?primary, ...payload.relatedAssets];
        var activeFolderId = _resourceFolderIdForPath(
          payload,
          payload.folderPath,
        );
        if (activeFolderId.isEmpty && primary?.folderId.isNotEmpty == true) {
          activeFolderId = primary!.folderId;
        }
        if (activeFolderId.isEmpty) {
          for (final asset in allAssets) {
            if (asset.folderId.isNotEmpty) {
              activeFolderId = asset.folderId;
              break;
            }
          }
        }
        if (activeFolderId.isEmpty && payload.folders.isNotEmpty) {
          activeFolderId = payload.folders.first.id;
        }
        final folderAssets = activeFolderId.isEmpty
            ? allAssets
            : allAssets
                  .where((asset) => asset.folderId == activeFolderId)
                  .toList(growable: false);
        final activeFolderPath = payload.folderPathFor(activeFolderId);
        final visibleFolderPath = activeFolderPath.isEmpty
            ? payload.folderPath
            : activeFolderPath;
        final featured = collapsed
            ? (folderAssets.isEmpty ? null : folderAssets.first)
            : primary;
        final boundedHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : double.infinity;
        final dense = collapsed
            ? compact || boundedHeight < 150 || constraints.maxWidth < 240
            : compact;
        final showName = !collapsed || boundedHeight >= 104;
        final showFolder =
            visibleFolderPath.isNotEmpty &&
            (!collapsed || boundedHeight >= 132);
        final showMetadata = !collapsed || (!dense && boundedHeight >= 160);
        final showCollapsedFolder =
            collapsed && (payload.folders.isNotEmpty || allAssets.isNotEmpty);
        final preview = Column(
          key: ValueKey<String>(
            collapsed ? 'resource-collapsed-preview' : 'resource-node-preview',
          ),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showCollapsedFolder)
              _ResourceCollapsedFolderPreview(
                assets: folderAssets,
                folderPath: visibleFolderPath,
                primaryAssetId: primary?.id,
                primaryBytes: primaryBytes,
                primaryLoading: primaryLoading,
                primaryError: primaryError,
                dense: dense,
              )
            else if (featured == null)
              Container(
                height: dense ? 64 : 120,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: const Text('No asset selected'),
              )
            else
              ResourceAssetPreview(
                asset: featured,
                bytes: featured.id == primary?.id ? primaryBytes : null,
                loading: featured.id == primary?.id && primaryLoading,
                error: featured.id == primary?.id ? primaryError : null,
                compact: dense,
              ),
            if (!showCollapsedFolder && featured != null && showName) ...[
              const SizedBox(height: 8),
              Text(
                featured.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
            if (!showCollapsedFolder && showFolder) ...[
              const SizedBox(height: 4),
              Text(
                visibleFolderPath.join(' / '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            if (showMetadata) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (!showCollapsedFolder && featured != null)
                    Text(
                      resourceAssetTypeLabel(featured),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (!showCollapsedFolder && featured?.sizeBytes != null)
                    Text(
                      resourceFileSizeLabel(featured?.sizeBytes),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (allAssets.isNotEmpty)
                    Text(
                      '${allAssets.length} asset${allAssets.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  for (final tag in payload.tags.take(dense ? 2 : 4))
                    Text(
                      '#$tag',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ],
            if ((!collapsed || boundedHeight >= 230) &&
                !dense &&
                payload.description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                payload.description.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        );
        return collapsed ? IgnorePointer(child: preview) : preview;
      },
    );
  }
}

class _ResourceCollapsedFolderPreview extends StatelessWidget {
  const _ResourceCollapsedFolderPreview({
    required this.assets,
    required this.folderPath,
    required this.primaryAssetId,
    required this.primaryBytes,
    required this.primaryLoading,
    required this.primaryError,
    required this.dense,
  });

  final List<ResourceAsset> assets;
  final List<String> folderPath;
  final String? primaryAssetId;
  final Uint8List? primaryBytes;
  final bool primaryLoading;
  final String? primaryError;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (dense) return _buildDense(context);
    final visibleAssets = assets.take(2).toList(growable: false);
    final hiddenCount = assets.length - visibleAssets.length;
    return Container(
      key: const ValueKey<String>('resource-collapsed-folder-preview'),
      width: double.infinity,
      padding: EdgeInsets.all(dense ? 8 : 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_rounded, size: dense ? 17 : 19),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folderPath.isEmpty ? 'Unfiled' : folderPath.join(' / '),
                  key: const ValueKey<String>('resource-collapsed-folder-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${assets.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (visibleAssets.isEmpty)
            Text(
              'Folder is empty',
              key: const ValueKey<String>('resource-collapsed-folder-empty'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Row(
              children: [
                for (var index = 0; index < visibleAssets.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _ResourceCollapsedAssetTile(
                      asset: visibleAssets[index],
                      bytes: visibleAssets[index].id == primaryAssetId
                          ? primaryBytes
                          : null,
                      loading:
                          visibleAssets[index].id == primaryAssetId &&
                          primaryLoading,
                      error: visibleAssets[index].id == primaryAssetId
                          ? primaryError
                          : null,
                      dense: dense,
                    ),
                  ),
                ],
              ],
            ),
          if (hiddenCount > 0) ...[
            const SizedBox(height: 5),
            Text(
              '+$hiddenCount more',
              key: const ValueKey<String>('resource-collapsed-folder-more'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDense(BuildContext context) {
    final asset = assets.isEmpty ? null : assets.first;
    return Container(
      key: const ValueKey<String>('resource-collapsed-folder-preview'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, size: 18),
          const SizedBox(width: 7),
          Expanded(
            key: asset == null
                ? null
                : ValueKey<String>('resource-collapsed-asset-${asset.id}'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folderPath.isEmpty ? 'Unfiled' : folderPath.join(' / '),
                  key: const ValueKey<String>('resource-collapsed-folder-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  asset?.displayName ?? 'Folder is empty',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (asset != null) Icon(resourceAssetIcon(asset), size: 18),
          const SizedBox(width: 5),
          Text(
            '${assets.length}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _ResourceCollapsedAssetTile extends StatelessWidget {
  const _ResourceCollapsedAssetTile({
    required this.asset,
    required this.bytes,
    required this.loading,
    required this.error,
    required this.dense,
  });

  final ResourceAsset asset;
  final Uint8List? bytes;
  final bool loading;
  final String? error;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final height = dense ? 54.0 : 78.0;
    final thumbnail = _thumbnail(context, height);
    return Semantics(
      label: '${asset.displayName}, ${resourceAssetTypeLabel(asset)}',
      child: Container(
        key: ValueKey<String>('resource-collapsed-asset-${asset.id}'),
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
        ),
        child: thumbnail,
      ),
    );
  }

  Widget _thumbnail(BuildContext context, double height) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error == null && asset.isImage && bytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            bytes!,
            key: const ValueKey<String>('resource-preview-image'),
            fit: BoxFit.cover,
          ),
          _assetCaption(context),
        ],
      );
    }
    if (error == null && asset.isImage && asset.isUrl) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            asset.location,
            key: const ValueKey<String>('resource-preview-image'),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _assetDetails(context),
          ),
          _assetCaption(context),
        ],
      );
    }
    return _assetDetails(context);
  }

  Widget _assetDetails(BuildContext context) => Padding(
    padding: EdgeInsets.all(dense ? 7 : 9),
    child: Row(
      children: [
        Icon(
          error == null ? resourceAssetIcon(asset) : Icons.cloud_off_outlined,
          size: dense ? 20 : 25,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                asset.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (!dense)
                Text(
                  resourceAssetTypeLabel(asset),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _assetCaption(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      color: Colors.black54,
      child: Text(
        asset.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Colors.white),
      ),
    ),
  );
}

String _resourceFolderIdForPath(ResourcePayload payload, List<String> path) {
  if (path.isEmpty) return '';
  for (final folder in payload.folders) {
    final candidate = payload.folderPathFor(folder.id);
    if (candidate.length != path.length) continue;
    var matches = true;
    for (var index = 0; index < path.length; index++) {
      if (candidate[index].toLowerCase() != path[index].toLowerCase()) {
        matches = false;
        break;
      }
    }
    if (matches) return folder.id;
  }
  return '';
}

class ResourceNodeEditor extends StatefulWidget {
  const ResourceNodeEditor({
    required this.payload,
    required this.onChanged,
    this.primaryBytes,
    this.primaryLoading = false,
    this.primaryError,
    this.onChooseFile,
    this.onOpenAsset,
    this.folderSuggestions = const <List<String>>[],
    super.key,
  });

  final ResourcePayload payload;
  final ValueChanged<ResourcePayload> onChanged;
  final Uint8List? primaryBytes;
  final bool primaryLoading;
  final String? primaryError;
  final ResourceAssetAddCallback? onChooseFile;
  final ResourceAssetOpenCallback? onOpenAsset;
  final List<List<String>> folderSuggestions;

  @override
  State<ResourceNodeEditor> createState() => _ResourceNodeEditorState();
}

class _ResourceNodeEditorState extends State<ResourceNodeEditor> {
  String? _error;
  String _selectedFolderId = '';

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.payload.primaryAsset?.folderId ?? '';
  }

  @override
  void didUpdateWidget(covariant ResourceNodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedFolderId.isNotEmpty &&
        widget.payload.folderById(_selectedFolderId) == null) {
      _selectedFolderId = '';
    }
  }

  Future<void> _chooseFile({required bool related}) async {
    final callback = widget.onChooseFile;
    if (callback == null) return;
    try {
      final selected = await callback();
      if (!mounted || selected == null) return;
      final asset = selected.copyWith(folderId: _selectedFolderId);
      if (related) {
        widget.onChanged(
          widget.payload.copyWith(
            relatedAssets: <ResourceAsset>[
              ...widget.payload.relatedAssets,
              asset,
            ],
          ),
        );
      } else {
        widget.onChanged(
          widget.payload.copyWith(
            primaryAsset: asset,
            folderPath: widget.payload.folderPathFor(_selectedFolderId),
          ),
        );
      }
      setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _addUrl({required bool related}) async {
    var draft = '';
    String? localError;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(related ? 'Add related URL' : 'Set primary URL'),
          content: TextFormField(
            key: const ValueKey<String>('resource-url-dialog-field'),
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'HTTP or HTTPS URL',
              errorText: localError,
            ),
            onChanged: (value) => draft = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>('resource-url-dialog-save'),
              onPressed: () {
                final value = draft.trim();
                if (!_validHttpUrl(value)) {
                  setDialogState(
                    () => localError = 'Use an absolute HTTP or HTTPS URL.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    final asset = ResourceAsset(
      id: _nextAssetId(related ? 'related' : 'primary'),
      kind: 'url',
      label: resourceUrlHost(result),
      location: result,
      extension: _extensionFromLocation(result),
      folderId: _selectedFolderId,
    );
    if (related) {
      widget.onChanged(
        widget.payload.copyWith(
          relatedAssets: <ResourceAsset>[
            ...widget.payload.relatedAssets,
            asset,
          ],
        ),
      );
    } else {
      widget.onChanged(
        widget.payload.copyWith(
          primaryAsset: asset,
          folderPath: widget.payload.folderPathFor(_selectedFolderId),
        ),
      );
    }
  }

  Future<void> _editLabel(ResourceAsset asset) async {
    var draft = asset.label;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit asset label'),
        content: TextFormField(
          key: const ValueKey<String>('resource-label-dialog-field'),
          initialValue: asset.label,
          autofocus: true,
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('resource-label-dialog-save'),
            onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    _replaceAsset(asset, asset.copyWith(label: result));
  }

  Future<void> _open(ResourceAsset asset) async {
    try {
      await widget.onOpenAsset?.call(asset);
      if (mounted) setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _copy(ResourceAsset asset) async {
    final value = asset.location.isNotEmpty ? asset.location : asset.fileName;
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Resource location copied')));
  }

  void _replaceAsset(ResourceAsset oldAsset, ResourceAsset newAsset) {
    if (widget.payload.primaryAsset?.id == oldAsset.id) {
      widget.onChanged(
        widget.payload.copyWith(
          primaryAsset: newAsset,
          folderPath: widget.payload.folderPathFor(newAsset.folderId),
        ),
      );
      return;
    }
    widget.onChanged(
      widget.payload.copyWith(
        relatedAssets: <ResourceAsset>[
          for (final item in widget.payload.relatedAssets)
            item.id == oldAsset.id ? newAsset : item,
        ],
      ),
    );
  }

  void _moveAsset(ResourceAsset asset, String folderId) {
    _replaceAsset(asset, asset.copyWith(folderId: folderId));
  }

  void _removeAsset(ResourceAsset asset) {
    if (widget.payload.primaryAsset?.id == asset.id) {
      widget.onChanged(widget.payload.copyWith(clearPrimaryAsset: true));
      return;
    }
    widget.onChanged(
      widget.payload.copyWith(
        relatedAssets: widget.payload.relatedAssets
            .where((item) => item.id != asset.id)
            .toList(growable: false),
      ),
    );
  }

  Future<void> _editFolder({ResourceFolder? folder}) async {
    final parentId = folder?.parentId ?? _selectedFolderId;
    if (folder == null && widget.payload.folderDepth(parentId) >= 3) return;
    var draft = folder?.name ?? '';
    String? localError;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(folder == null ? 'Add folder' : 'Edit folder'),
          content: TextFormField(
            key: const ValueKey<String>('resource-folder-dialog-field'),
            initialValue: draft,
            autofocus: true,
            decoration: InputDecoration(errorText: localError),
            onChanged: (value) => draft = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>('resource-folder-dialog-save'),
              onPressed: () {
                final value = draft.trim();
                final duplicate = widget.payload.folders.any(
                  (item) =>
                      item.id != folder?.id &&
                      item.parentId == parentId &&
                      item.name.toLowerCase() == value.toLowerCase(),
                );
                if (value.isEmpty ||
                    value.contains('/') ||
                    value.contains('\\') ||
                    duplicate) {
                  setDialogState(
                    () => localError = duplicate
                        ? 'Folder name already exists here.'
                        : 'Use a folder name without / or \\.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    final folders = <ResourceFolder>[
      for (final item in widget.payload.folders)
        if (folder == null || item.id != folder.id)
          item
        else
          item.copyWith(name: result),
      if (folder == null)
        ResourceFolder(
          id: _nextFolderId(widget.payload.folders),
          name: result,
          parentId: parentId,
        ),
    ];
    final selectedFolderId = folder?.id ?? folders.last.id;
    final next = widget.payload.copyWith(
      folders: folders,
      folderPath: _folderPathFor(folders, selectedFolderId),
    );
    setState(() => _selectedFolderId = selectedFolderId);
    widget.onChanged(next);
  }

  void _removeFolder(ResourceFolder folder) {
    final folders = <ResourceFolder>[
      for (final item in widget.payload.folders)
        if (item.id != folder.id)
          item.parentId == folder.id
              ? item.copyWith(parentId: folder.parentId)
              : item,
    ];
    final primary = widget.payload.primaryAsset;
    final movedPrimary = primary?.folderId == folder.id
        ? primary?.copyWith(folderId: folder.parentId)
        : primary;
    final related = <ResourceAsset>[
      for (final asset in widget.payload.relatedAssets)
        asset.folderId == folder.id
            ? asset.copyWith(folderId: folder.parentId)
            : asset,
    ];
    final selectedFolderId = _selectedFolderId == folder.id
        ? folder.parentId
        : _selectedFolderId;
    final next = widget.payload.copyWith(
      primaryAsset: movedPrimary,
      relatedAssets: related,
      folders: folders,
      folderPath: _folderPathFor(folders, selectedFolderId),
    );
    setState(() => _selectedFolderId = selectedFolderId);
    widget.onChanged(next);
  }

  void _applyFolderSuggestion(List<String> suggestion) {
    var folders = List<ResourceFolder>.from(widget.payload.folders);
    var parentId = '';
    for (final segment in suggestion.take(3)) {
      final name = segment.trim();
      if (name.isEmpty) continue;
      ResourceFolder? existing;
      for (final folder in folders) {
        if (folder.parentId == parentId &&
            folder.name.toLowerCase() == name.toLowerCase()) {
          existing = folder;
          break;
        }
      }
      if (existing != null) {
        parentId = existing.id;
        continue;
      }
      final folder = ResourceFolder(
        id: _nextFolderId(folders),
        name: name,
        parentId: parentId,
      );
      folders = <ResourceFolder>[...folders, folder];
      parentId = folder.id;
    }
    if (parentId.isEmpty) return;
    final next = widget.payload.copyWith(
      folders: folders,
      folderPath: _folderPathFor(folders, parentId),
    );
    setState(() => _selectedFolderId = parentId);
    widget.onChanged(next);
  }

  Future<void> _editTag({int? index}) async {
    var draft = index == null ? '' : widget.payload.tags[index];
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(index == null ? 'Add tag' : 'Edit tag'),
        content: TextFormField(
          key: const ValueKey<String>('resource-tag-dialog-field'),
          initialValue: draft,
          autofocus: true,
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('resource-tag-dialog-save'),
            onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    final tags = List<String>.from(widget.payload.tags);
    if (index == null) {
      if (!tags.contains(result)) tags.add(result);
    } else {
      tags[index] = result;
    }
    widget.onChanged(widget.payload.copyWith(tags: tags));
  }

  void _removeTag(int index) {
    final tags = List<String>.from(widget.payload.tags)..removeAt(index);
    widget.onChanged(widget.payload.copyWith(tags: tags));
  }

  String _nextAssetId(String prefix) {
    final ids = <String>{
      if (widget.payload.primaryAsset case final asset?) asset.id,
      for (final asset in widget.payload.relatedAssets) asset.id,
    };
    var index = ids.length + 1;
    while (ids.contains('$prefix-$index')) {
      index++;
    }
    return '$prefix-$index';
  }

  String _nextFolderId(Iterable<ResourceFolder> folders) {
    final ids = <String>{for (final folder in folders) folder.id};
    var index = ids.length + 1;
    while (ids.contains('folder-$index')) {
      index++;
    }
    return 'folder-$index';
  }

  List<String> _folderPathFor(List<ResourceFolder> folders, String folderId) =>
      ResourcePayload(folders: folders).folderPathFor(folderId);

  int _assetCount(String folderId) {
    var count = widget.payload.primaryAsset?.folderId == folderId ? 1 : 0;
    count += widget.payload.relatedAssets
        .where((asset) => asset.folderId == folderId)
        .length;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.payload.primaryAsset;
    final visibleAssets = widget.payload.relatedAssets
        .where(
          (asset) =>
              _selectedFolderId.isEmpty || asset.folderId == _selectedFolderId,
        )
        .toList(growable: false);
    final selectedPath = widget.payload.folderPathFor(_selectedFolderId);
    final selectedLabel = selectedPath.isEmpty
        ? 'All assets'
        : selectedPath.join(' / ');
    final totalAssetCount =
        widget.payload.relatedAssets.length + (primary == null ? 0 : 1);
    return Column(
      key: const ValueKey<String>('knowledge-resource-editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Primary asset', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (primary == null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey<String>('resource-primary-choose-file'),
                onPressed: widget.onChooseFile == null
                    ? null
                    : () => _chooseFile(related: false),
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text('Choose file'),
              ),
              OutlinedButton.icon(
                key: const ValueKey<String>('resource-primary-paste-url'),
                onPressed: () => _addUrl(related: false),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Paste URL'),
              ),
            ],
          )
        else ...[
          ResourceAssetPreview(
            asset: primary,
            bytes: widget.primaryBytes,
            loading: widget.primaryLoading,
            error: widget.primaryError,
          ),
          if (widget.payload.folderPathFor(primary.folderId).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.payload.folderPathFor(primary.folderId).join(' / '),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          const SizedBox(height: 8),
          _AssetActions(
            asset: primary,
            prefix: 'resource-primary',
            folders: widget.payload.folders,
            onMove: (folderId) => _moveAsset(primary, folderId),
            onOpen: () => _open(primary),
            onCopy: () => _copy(primary),
            onEdit: () => _editLabel(primary),
            onRemove: () => _removeAsset(primary),
            onReplaceFile: widget.onChooseFile == null
                ? null
                : () => _chooseFile(related: false),
            onReplaceUrl: () => _addUrl(related: false),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Folders',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '$totalAssetCount assets',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              key: const ValueKey<String>('resource-folder-all'),
              label: Text('All ($totalAssetCount)'),
              selected: _selectedFolderId.isEmpty,
              onSelected: (_) => setState(() => _selectedFolderId = ''),
            ),
            for (final folder in widget.payload.folders)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChoiceChip(
                    key: ValueKey<String>('resource-folder-${folder.id}'),
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(
                      '${widget.payload.folderPathFor(folder.id).join(' / ')} '
                      '(${_assetCount(folder.id)})',
                    ),
                    selected: _selectedFolderId == folder.id,
                    onSelected: (_) =>
                        setState(() => _selectedFolderId = folder.id),
                  ),
                  PopupMenuButton<String>(
                    key: ValueKey<String>('resource-folder-menu-${folder.id}'),
                    tooltip: 'Folder actions',
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editFolder(folder: folder);
                      } else if (value == 'delete') {
                        _removeFolder(folder);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('Rename'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete folder'),
                      ),
                    ],
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  ),
                ],
              ),
            ActionChip(
              key: const ValueKey<String>('resource-folder-add'),
              avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: Text(
                _selectedFolderId.isEmpty ? 'Add folder' : 'Add subfolder',
              ),
              onPressed: widget.payload.folderDepth(_selectedFolderId) >= 3
                  ? null
                  : _editFolder,
            ),
          ],
        ),
        if (widget.folderSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final suggestion in widget.folderSuggestions.take(4))
                ActionChip(
                  label: Text(suggestion.join(' / ')),
                  onPressed: () => _applyFolderSuggestion(suggestion),
                ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(
          selectedLabel,
          key: const ValueKey<String>('resource-selected-folder-label'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 16),
        Text('Tags', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var index = 0; index < widget.payload.tags.length; index++)
              InputChip(
                key: ValueKey<String>('resource-tag-$index'),
                label: Text(widget.payload.tags[index]),
                onPressed: () => _editTag(index: index),
                onDeleted: () => _removeTag(index),
              ),
            ActionChip(
              key: const ValueKey<String>('resource-tag-add'),
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add tag'),
              onPressed: _editTag,
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey<String>('knowledge-resource-description-field'),
          initialValue: widget.payload.description,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Description'),
          onChanged: (value) =>
              widget.onChanged(widget.payload.copyWith(description: value)),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                selectedLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              key: const ValueKey<String>('resource-related-add-file'),
              tooltip: 'Add file to selected folder',
              onPressed: widget.onChooseFile == null
                  ? null
                  : () => _chooseFile(related: true),
              icon: const Icon(Icons.attach_file_rounded),
            ),
            IconButton(
              key: const ValueKey<String>('resource-related-add-url'),
              tooltip: 'Add URL to selected folder',
              onPressed: () => _addUrl(related: true),
              icon: const Icon(Icons.add_link_rounded),
            ),
          ],
        ),
        if (visibleAssets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _selectedFolderId.isEmpty
                  ? 'No related assets yet.'
                  : 'Folder is empty. Add a file or URL.',
              key: const ValueKey<String>('resource-folder-empty'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final asset in visibleAssets) ...[
          const SizedBox(height: 8),
          Card(
            key: ValueKey<String>('resource-related-${asset.id}'),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(resourceAssetIcon(asset), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          asset.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        resourceAssetTypeLabel(asset),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  if (widget.payload.folderPathFor(asset.folderId).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        widget.payload
                            .folderPathFor(asset.folderId)
                            .join(' / '),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  const SizedBox(height: 6),
                  _AssetActions(
                    asset: asset,
                    prefix: 'resource-related-${asset.id}',
                    folders: widget.payload.folders,
                    onMove: (folderId) => _moveAsset(asset, folderId),
                    onOpen: () => _open(asset),
                    onCopy: () => _copy(asset),
                    onEdit: () => _editLabel(asset),
                    onRemove: () => _removeAsset(asset),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_error case final message?) ...[
          const SizedBox(height: 8),
          Text(
            message,
            key: const ValueKey<String>('resource-editor-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _AssetActions extends StatelessWidget {
  const _AssetActions({
    required this.asset,
    required this.prefix,
    required this.onOpen,
    required this.onCopy,
    required this.onEdit,
    required this.onRemove,
    this.folders = const <ResourceFolder>[],
    this.onMove,
    this.onReplaceFile,
    this.onReplaceUrl,
  });

  final ResourceAsset asset;
  final String prefix;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final List<ResourceFolder> folders;
  final ValueChanged<String>? onMove;
  final VoidCallback? onReplaceFile;
  final VoidCallback? onReplaceUrl;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      IconButton(
        key: ValueKey<String>('$prefix-open'),
        tooltip: 'Open',
        onPressed: onOpen,
        icon: const Icon(Icons.open_in_new_rounded),
      ),
      IconButton(
        key: ValueKey<String>('$prefix-copy'),
        tooltip: 'Copy location',
        onPressed: onCopy,
        icon: const Icon(Icons.copy_rounded),
      ),
      IconButton(
        key: ValueKey<String>('$prefix-edit'),
        tooltip: 'Edit label',
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
      if (onMove != null)
        PopupMenuButton<String>(
          key: ValueKey<String>('$prefix-move'),
          tooltip: 'Move to folder',
          onSelected: onMove,
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: '',
              child: Row(
                children: [
                  Icon(
                    asset.folderId.isEmpty
                        ? Icons.check_rounded
                        : Icons.folder_off_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text('Unfiled'),
                ],
              ),
            ),
            for (final folder in folders)
              PopupMenuItem<String>(
                value: folder.id,
                child: Row(
                  children: [
                    Icon(
                      asset.folderId == folder.id
                          ? Icons.check_rounded
                          : Icons.folder_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(folder.name),
                  ],
                ),
              ),
          ],
          icon: const Icon(Icons.drive_file_move_outline),
        ),
      if (onReplaceFile != null)
        IconButton(
          key: ValueKey<String>('$prefix-replace-file'),
          tooltip: 'Replace with file',
          onPressed: onReplaceFile,
          icon: const Icon(Icons.attach_file_rounded),
        ),
      if (onReplaceUrl != null)
        IconButton(
          key: ValueKey<String>('$prefix-replace-url'),
          tooltip: 'Replace with URL',
          onPressed: onReplaceUrl,
          icon: const Icon(Icons.link_rounded),
        ),
      IconButton(
        key: ValueKey<String>('$prefix-remove'),
        tooltip: 'Remove',
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    ],
  );
}

class _AssetFallback extends StatelessWidget {
  const _AssetFallback({
    required this.asset,
    required this.icon,
    required this.label,
    required this.height,
    super.key,
  });

  final ResourceAsset asset;
  final IconData icon;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(icon, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                asset.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (asset.sizeBytes != null)
                Text(
                  resourceFileSizeLabel(asset.sizeBytes),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

String resourceAssetTypeLabel(ResourceAsset asset) {
  if (asset.isUrl && !asset.isImage) return 'URL';
  final mime = asset.mimeType;
  final extension = asset.extension;
  if (mime.startsWith('audio/') ||
      const <String>{'aac', 'm4a', 'mp3', 'ogg', 'wav'}.contains(extension)) {
    return 'Audio';
  }
  if (mime.startsWith('video/') ||
      const <String>{'mov', 'mp4', 'webm'}.contains(extension)) {
    return 'Video';
  }
  if (asset.isImage) return 'Image';
  if (mime == 'application/pdf' ||
      const <String>{
        'csv',
        'doc',
        'docx',
        'md',
        'pdf',
        'ppt',
        'pptx',
        'txt',
        'xls',
        'xlsx',
      }.contains(extension)) {
    return 'Document';
  }
  return 'File';
}

String resourceFileSizeLabel(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String resourceUrlHost(String location) {
  final uri = Uri.tryParse(location.trim());
  return uri == null || uri.host.isEmpty ? location.trim() : uri.host;
}

IconData resourceAssetIcon(ResourceAsset asset) =>
    switch (resourceAssetTypeLabel(asset)) {
      'URL' => Icons.language_outlined,
      'Image' => Icons.image_outlined,
      'Document' => Icons.description_outlined,
      'Audio' => Icons.audio_file_outlined,
      'Video' => Icons.video_file_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

bool _validHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

String _extensionFromLocation(String value) {
  final uri = Uri.tryParse(value);
  final path = uri?.path ?? value;
  final name = path.split('/').last;
  final index = name.lastIndexOf('.');
  return index <= 0 || index == name.length - 1
      ? ''
      : name.substring(index + 1).toLowerCase();
}
