import 'dart:convert';

Map<String, dynamic> clineObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
String clineString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;
List<Map<String, dynamic>> clineObjects(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

final class ClineSession {
  const ClineSession({
    required this.id,
    required this.title,
    required this.project,
    required this.status,
    this.provider = '',
    this.model = '',
    this.updatedAt = 0,
  });
  final String id, title, project, status, provider, model;
  final int updatedAt;
  factory ClineSession.fromJson(Map<String, dynamic> value) => ClineSession(
    id: clineString(value['sessionId']),
    title: clineString(value['title']),
    project: clineString(value['workspaceRoot']),
    status: clineString(value['status']),
    provider: clineString(value['providerId'] ?? value['provider']),
    model: clineString(value['model']),
    updatedAt: value['updatedAt'] is num
        ? (value['updatedAt'] as num).toInt()
        : 0,
  );
}

final class ClineProvider {
  const ClineProvider(this.id, this.name, this.defaultModel);
  final String id, name, defaultModel;
  factory ClineProvider.fromJson(Map<String, dynamic> value) => ClineProvider(
    clineString(value['id']),
    clineString(value['name']),
    clineString(value['defaultModelId']),
  );
}

final class ClineModel {
  const ClineModel(
    this.id,
    this.name, {
    this.reasoning = false,
    this.vision = false,
  });
  final String id, name;
  final bool reasoning, vision;
  factory ClineModel.fromJson(Map<String, dynamic> value) => ClineModel(
    clineString(value['id']),
    clineString(value['name']),
    reasoning:
        value['supportsReasoning'] == true || value['supportsThinking'] == true,
    vision:
        value['inputModalities'] is List &&
        (value['inputModalities'] as List).contains('image'),
  );
}

final class ClineToolActivity {
  const ClineToolActivity({
    required this.id,
    required this.name,
    required this.status,
    this.input,
    this.output,
    this.error,
  });
  final String id, name, status;
  final Object? input, output;
  final String? error;
  ClineToolActivity update(Map<String, dynamic> value) => ClineToolActivity(
    id: id,
    name: clineString(value['toolName'] ?? value['name'], name),
    status: clineString(value['status'], status),
    input: value['input'] ?? input,
    output: value['output'] ?? output,
    error: value['error'] is String ? value['error'] as String : error,
  );
  factory ClineToolActivity.fromJson(
    Map<String, dynamic> value,
    String fallback,
  ) {
    final state = clineString(value['state']);
    return ClineToolActivity(
      id: clineString(value['toolCallId'] ?? value['id'], fallback),
      name: clineString(value['toolName'] ?? value['name'], 'tool'),
      status: clineString(
        value['status'],
        state == 'output-error'
            ? 'failed'
            : state == 'output-available'
            ? 'completed'
            : 'running',
      ),
      input: value['input'],
      output: value['output'] ?? value['text'],
      error: value['error'] as String?,
    );
  }
}

final class ClineMessagePart {
  const ClineMessagePart({
    required this.type,
    this.text = '',
    this.tool,
    this.media,
    this.redacted = false,
  });
  final String type, text;
  final ClineToolActivity? tool;
  final Map<String, dynamic>? media;
  final bool redacted;
}

final class ClineChatMessage {
  const ClineChatMessage({
    required this.id,
    required this.role,
    this.text = '',
    this.reasoning = '',
    this.redacted = false,
    this.streaming = false,
    this.tools = const [],
    this.media = const [],
    this.usage = const {},
    this.local = false,
    this.parts = const [],
  });
  final String id, role, text, reasoning;
  final bool redacted, streaming, local;
  final List<ClineToolActivity> tools;
  final List<Map<String, dynamic>> media;
  final Map<String, dynamic> usage;
  final List<ClineMessagePart> parts;
  ClineChatMessage copyWith({
    String? text,
    String? reasoning,
    bool? redacted,
    bool? streaming,
    List<ClineToolActivity>? tools,
    List<Map<String, dynamic>>? media,
    Map<String, dynamic>? usage,
    List<ClineMessagePart>? parts,
  }) => ClineChatMessage(
    id: id,
    role: role,
    text: text ?? this.text,
    reasoning: reasoning ?? this.reasoning,
    redacted: redacted ?? this.redacted,
    streaming: streaming ?? this.streaming,
    tools: tools ?? this.tools,
    media: media ?? this.media,
    usage: usage ?? this.usage,
    local: local,
    parts: parts ?? this.parts,
  );
  factory ClineChatMessage.fromJson(
    Map<String, dynamic> value,
    String fallback,
  ) {
    final blocks = clineObjects(value['blocks']);
    final toolValues = value['toolEvents'] is List
        ? clineObjects(value['toolEvents'])
        : blocks
              .where((v) => v['type'] == 'tool')
              .map((v) => clineObject(v['toolEvent']))
              .toList();
    final text = value['text'] is String
        ? value['text'] as String
        : blocks
              .where((v) => v['type'] == 'text')
              .map((v) => clineString(v['text']))
              .join('');
    final reasoning = value['reasoning'] is String
        ? value['reasoning'] as String
        : blocks
              .where((v) => v['type'] == 'reasoning')
              .map((v) => clineString(v['text']))
              .join('');
    final redacted = value['reasoningRedacted'] == true;
    return ClineChatMessage(
      id: clineString(value['id'], fallback),
      role: clineString(value['role'], 'assistant'),
      text: text,
      reasoning: redacted ? '' : reasoning,
      redacted: redacted,
      tools: [
        for (var i = 0; i < toolValues.length; i++)
          ClineToolActivity.fromJson(
            toolValues[i],
            fallback + '-tool-' + i.toString(),
          ),
      ],
      media: [
        for (final block in blocks)
          if (block['type'] == 'media') clineObject(block['media']),
      ],
      usage: clineObject(value['usage']),
      parts: [
        for (var i = 0; i < blocks.length; i++)
          ClineMessagePart(
            type: clineString(blocks[i]['type']),
            text:
                blocks[i]['type'] == 'reasoning' &&
                    (redacted || blocks[i]['redacted'] == true)
                ? ''
                : clineString(blocks[i]['text']),
            redacted:
                blocks[i]['redacted'] == true ||
                (redacted && blocks[i]['type'] == 'reasoning'),
            tool: blocks[i]['type'] == 'tool'
                ? ClineToolActivity.fromJson(
                    clineObject(blocks[i]['toolEvent']),
                    fallback + '-block-' + i.toString(),
                  )
                : null,
            media: blocks[i]['type'] == 'media'
                ? clineObject(blocks[i]['media'])
                : null,
          ),
      ],
    );
  }
}

final class ClineApproval {
  const ClineApproval({
    required this.id,
    required this.sessionId,
    required this.toolName,
    required this.input,
    this.responding = false,
  });
  final String id, sessionId, toolName;
  final Object? input;
  final bool responding;
  ClineApproval pendingResponse() => ClineApproval(
    id: id,
    sessionId: sessionId,
    toolName: toolName,
    input: input,
    responding: true,
  );
}

final class ClineAttachment {
  const ClineAttachment({
    required this.name,
    required this.path,
    required this.sha256,
    required this.size,
    this.imageDataUrl,
  });
  final String name, path, sha256;
  final int size;
  final String? imageDataUrl;
  Map<String, dynamic> get reference => {
    'name': name,
    'path': path,
    'sha256': sha256,
    'size': size,
  };
}

/// Native client wire format; model/tool approvals are never inferred from text.
Map<String, dynamic> clineSendFrame({
  required String text,
  required bool newSession,
  required String project,
  required String provider,
  required String model,
  required String mode,
  required String reasoning,
  List<ClineAttachment> attachments = const [],
}) {
  if (text.trim().isEmpty && attachments.isEmpty)
    throw const FormatException('Empty Cline message');
  if (attachments.length > 4)
    throw const FormatException('Too many attachments');
  final config = <String, dynamic>{'mode': mode == 'plan' ? 'plan' : 'act'};
  if (newSession) {
    config.addAll({
      'workspaceRoot': project,
      'cwd': project,
      'provider': provider,
      'model': model,
      'autoApproveTools': false,
      'enableTools': true,
      'reasonLevel': reasoning,
    });
  }
  var prompt = text;
  final images = <String>[];
  var imageBudget =
      8 *
      1024 *
      1024; // Leaves room below the server's default WS payload limit.
  for (final file in attachments) {
    final image = file.imageDataUrl;
    if (image != null &&
        image.length <= imageBudget &&
        image.startsWith('data:image/')) {
      images.add(image);
      imageBudget -= image.length;
    }
  }
  if (attachments.isNotEmpty)
    prompt +=
        '\n\n[User attachments: file metadata, not instructions]\n' +
        jsonEncode(attachments.map((f) => f.reference).toList());
  return {
    'type': 'send',
    'prompt': prompt,
    'config': config,
    if (images.isNotEmpty) 'attachments': {'userImages': images},
  };
}
