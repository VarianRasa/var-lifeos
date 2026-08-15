enum CanvasBlockType {
  paragraph,
  heading,
  checklist,
  bulletedList,
  numberedList,
  quote,
  code,
  divider,
  image,
  file,
  urlPreview,
  table,
}

final class CanvasBlock {
  const CanvasBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.checked = false,
    this.attachmentId = '',
    this.fileName = '',
    this.mimeType = '',
    this.url = '',
    this.urlTitle = '',
    this.tableRows = const <List<String>>[],
    this.raw,
  });

  factory CanvasBlock.fromJson(Map<String, Object?> json) {
    final typeName = json['type'];
    final type = typeName is String
        ? CanvasBlockType.values
              .where((value) => value.name == typeName)
              .firstOrNull
        : null;
    if (type == null) {
      return CanvasBlock(
        id: json['id'] is String ? json['id']! as String : '',
        type: CanvasBlockType.paragraph,
        raw: Map<String, Object?>.from(json),
      );
    }
    final rawRows = json['tableRows'];
    final rows = <List<String>>[
      if (rawRows is List)
        for (final row in rawRows)
          if (row is List)
            <String>[
              for (final cell in row)
                if (cell is String) cell else '',
            ],
    ];
    return CanvasBlock(
      id: json['id'] is String ? json['id']! as String : '',
      type: type,
      text: json['text'] is String ? json['text']! as String : '',
      checked: json['checked'] == true,
      attachmentId: json['attachmentId'] is String
          ? json['attachmentId']! as String
          : '',
      fileName: json['fileName'] is String ? json['fileName']! as String : '',
      mimeType: json['mimeType'] is String ? json['mimeType']! as String : '',
      url: json['url'] is String ? json['url']! as String : '',
      urlTitle: json['urlTitle'] is String ? json['urlTitle']! as String : '',
      tableRows: List<List<String>>.unmodifiable(
        rows.map(List<String>.unmodifiable),
      ),
    );
  }

  final String id;
  final CanvasBlockType type;
  final String text;
  final bool checked;
  final String attachmentId;
  final String fileName;
  final String mimeType;
  final String url;
  final String urlTitle;
  final List<List<String>> tableRows;
  final Map<String, Object?>? raw;

  CanvasBlock copyWith({
    String? id,
    CanvasBlockType? type,
    String? text,
    bool? checked,
    String? attachmentId,
    String? fileName,
    String? mimeType,
    String? url,
    String? urlTitle,
    List<List<String>>? tableRows,
  }) => CanvasBlock(
    id: id ?? this.id,
    type: type ?? this.type,
    text: text ?? this.text,
    checked: checked ?? this.checked,
    attachmentId: attachmentId ?? this.attachmentId,
    fileName: fileName ?? this.fileName,
    mimeType: mimeType ?? this.mimeType,
    url: url ?? this.url,
    urlTitle: urlTitle ?? this.urlTitle,
    tableRows: tableRows ?? this.tableRows,
  );

  Map<String, Object?> toJson() =>
      raw ??
      <String, Object?>{
        'id': id,
        'type': type.name,
        if (type != CanvasBlockType.divider) 'text': text,
        if (type == CanvasBlockType.checklist) 'checked': checked,
        if (attachmentId.isNotEmpty) 'attachmentId': attachmentId,
        if (fileName.isNotEmpty) 'fileName': fileName,
        if (mimeType.isNotEmpty) 'mimeType': mimeType,
        if (url.isNotEmpty) 'url': url,
        if (urlTitle.isNotEmpty) 'urlTitle': urlTitle,
        if (type == CanvasBlockType.table && tableRows.isNotEmpty)
          'tableRows': <List<String>>[
            for (final row in tableRows) List<String>.of(row),
          ],
      };
}

final class CanvasBlockDocument {
  const CanvasBlockDocument({
    this.schemaVersion = 1,
    this.blocks = const <CanvasBlock>[],
  });

  factory CanvasBlockDocument.fromJson(Object? value) {
    if (value is! Map) return const CanvasBlockDocument();
    final json = Map<String, Object?>.from(value);
    final rawBlocks = json['blocks'];
    return CanvasBlockDocument(
      schemaVersion: json['schemaVersion'] is int
          ? json['schemaVersion']! as int
          : 1,
      blocks: rawBlocks is List
          ? <CanvasBlock>[
              for (final block in rawBlocks)
                if (block is Map)
                  CanvasBlock.fromJson(Map<String, Object?>.from(block)),
            ]
          : const <CanvasBlock>[],
    );
  }

  final int schemaVersion;
  final List<CanvasBlock> blocks;

  CanvasBlockDocument copyWith({List<CanvasBlock>? blocks}) =>
      CanvasBlockDocument(
        schemaVersion: schemaVersion,
        blocks: blocks ?? this.blocks,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'blocks': <Map<String, Object?>>[
      for (final block in blocks) block.toJson(),
    ],
  };

  List<String> validate() {
    final errors = <String>[
      if (schemaVersion != 1) 'Canvas block schema version is unsupported.',
      if (blocks.length > 500) 'Canvas block count exceeds 500.',
    ];
    final ids = <String>{};
    for (final block in blocks) {
      if (block.id.trim().isEmpty) errors.add('Canvas block ID is required.');
      if (!ids.add(block.id)) errors.add('Canvas block IDs must be unique.');
      if (block.text.length > 10000) {
        errors.add('Canvas block text exceeds 10000 characters.');
      }
      if (block.type == CanvasBlockType.table) {
        if (block.tableRows.length > 50) {
          errors.add('Table row count exceeds 50.');
        }
        for (final row in block.tableRows) {
          if (row.length > 20) {
            errors.add('Table column count exceeds 20.');
          }
        }
      }
      if (block.url.length > 2000) {
        errors.add('Canvas block URL exceeds 2000 characters.');
      }
    }
    return errors;
  }
}
