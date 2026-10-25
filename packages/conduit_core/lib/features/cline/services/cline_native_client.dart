import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/cline_native_models.dart';
import 'cline_ssh_tunnel.dart';

abstract interface class ClineWireTransport {
  Stream<String> get frames;
  void send(String frame);
  Future<void> close();
}

final class ClineWebSocketTransport implements ClineWireTransport {
  ClineWebSocketTransport(this.socket);
  final WebSocket socket;
  @override
  Stream<String> get frames => socket.map(
    (value) => value is String ? value : utf8.decode(value as List<int>),
  );
  @override
  void send(String frame) => socket.add(frame);
  @override
  Future<void> close() async {
    await socket.close();
  }
}

final class ClineNativeState {
  const ClineNativeState({
    required this.connected,
    required this.hubConnected,
    required this.busy,
    required this.loadingHistory,
    required this.sessionId,
    required this.project,
    required this.provider,
    required this.model,
    required this.mode,
    required this.reasoning,
    required this.sessions,
    required this.providers,
    required this.models,
    required this.messages,
    required this.approvals,
    this.status = '',
    this.error,
    this.uncertainPrompt,
  });
  final bool connected, hubConnected, busy, loadingHistory;
  final String? sessionId, error, uncertainPrompt;
  final String project, provider, model, mode, reasoning, status;
  final List<ClineSession> sessions;
  final List<ClineProvider> providers;
  final Map<String, List<ClineModel>> models;
  final List<ClineChatMessage> messages;
  final List<ClineApproval> approvals;
  bool get canSend =>
      connected &&
      hubConnected &&
      !busy &&
      !loadingHistory &&
      uncertainPrompt == null &&
      {'act', 'plan'}.contains(mode) &&
      (sessionId != null || (provider.isNotEmpty && model.isNotEmpty));
  List<String> get projects =>
      ({project, ...sessions.map((s) => s.project)}..remove('')).toList()
        ..sort();
}

/// Typed Cline JSON client. It never renders HTML or replays a user command.
final class ClineNativeClient {
  ClineNativeClient(
    this._transport, {
    required String project,
    this.identity = 'test',
    Future<void> Function()? onClose,
    Future<ClineUploadedFile> Function(File file, String name)? upload,
  }) : _project = project,
       _onClose = onClose,
       _upload = upload {
    _ready.future.ignore();
    _subscription = _transport.frames.listen(
      _receive,
      onDone: _disconnected,
      onError: (Object _, StackTrace _) => _disconnected(),
    );
  }
  final ClineWireTransport _transport;
  final String identity;
  String? createdSessionId, createdProject;
  final Future<void> Function()? _onClose;
  final Future<ClineUploadedFile> Function(File file, String name)? _upload;
  late final StreamSubscription<String> _subscription;
  final _changes = StreamController<ClineNativeState>.broadcast();
  Future<void>? _ownerClosed;
  final _ready = Completer<void>();
  final Map<String, Completer<Object?>> _requests = {};
  Timer? _notification;
  bool _connected = true,
      _hubConnected = false,
      _busy = false,
      _loadingHistory = false,
      _closed = false;
  bool _newTurn = false, _resetting = false;
  String? _sessionId,
      _awaitedSession,
      _assistantId,
      _error,
      _pendingPrompt,
      _uncertainPrompt;
  String _project,
      _provider = '',
      _model = '',
      _mode = 'act',
      _reasoning = 'medium',
      _status = '';
  var _sequence = 0;
  List<ClineSession> _sessions = [];
  List<ClineProvider> _providers = [];
  final Map<String, List<ClineModel>> _models = {};
  List<ClineChatMessage> _messages = [];
  final Map<String, ClineApproval> _approvals = {};

  Stream<ClineNativeState> get changes => _changes.stream;
  Future<void> get ready => _ready.future;
  ClineNativeState get state => ClineNativeState(
    connected: _connected,
    hubConnected: _hubConnected,
    busy: _busy,
    loadingHistory: _loadingHistory || _resetting,
    sessionId: _sessionId,
    project: _project,
    provider: _provider,
    model: _model,
    mode: _mode,
    reasoning: _reasoning,
    status: _status,
    error: _error,
    uncertainPrompt: _uncertainPrompt,
    sessions: List.unmodifiable(_sessions),
    providers: List.unmodifiable(_providers),
    models: Map.unmodifiable(_models),
    messages: List.unmodifiable(_messages),
    approvals: List.unmodifiable(_approvals.values),
  );

  static Future<ClineNativeClient> connect(ClineSshTunnel tunnel) async {
    ClineNativeClient? client;
    try {
      final origin = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: tunnel.profile.dashboardPort,
      );
      final address = Uri(
        scheme: 'ws',
        host: tunnel.url.host,
        port: tunnel.url.port,
        path: '/browser',
        queryParameters: {'roomSecret': tunnel.profile.roomSecret},
      );
      final socket = await WebSocket.connect(
        address.toString(),
        headers: {
          'Origin': origin.toString().replaceFirst(RegExp(r'/$'), ''),
          'Host': '127.0.0.1:' + tunnel.profile.dashboardPort.toString(),
        },
      ).timeout(const Duration(seconds: 20));
      socket.pingInterval = const Duration(seconds: 20);
      client = ClineNativeClient(
        ClineWebSocketTransport(socket),
        project: tunnel.profile.projectPath,
        identity: tunnel.profile.hostKeyFingerprint,
        onClose: tunnel.close,
        upload: tunnel.upload,
      );
      tunnel.closed.then((_) => client?._disconnected());
      client.start();
      await client.ready.timeout(const Duration(seconds: 25));
      return client;
    } catch (_) {
      await client?.close();
      await tunnel.close();
      // Exception URLs can contain the room token. Never propagate or log them.
      throw const ClineNativeException('connection');
    }
  }

  void start() => _send({'type': 'ready'});
  void _send(Map<String, dynamic> frame) {
    if (!_connected || _closed) throw const ClineNativeException('offline');
    final encoded = jsonEncode(frame);
    if (utf8.encode(encoded).length > 12 * 1024 * 1024)
      throw const ClineNativeException('payload');
    try {
      _transport.send(encoded);
    } catch (_) {
      _disconnected();
      throw const ClineNativeException('uncertain');
    }
  }

  void _notify({bool immediate = false}) {
    if (_closed || _changes.isClosed) return;
    if (immediate) {
      _notification?.cancel();
      _notification = null;
      _changes.add(state);
      return;
    }
    _notification ??= Timer(const Duration(milliseconds: 33), () {
      _notification = null;
      if (!_closed && !_changes.isClosed) _changes.add(state);
    });
  }

  void _receive(String encoded) {
    if (_closed) return;
    if (encoded.length > 32 * 1024 * 1024) {
      _error = 'payload';
      _disconnected();
      return;
    }
    try {
      final frame = clineObject(jsonDecode(encoded));
      switch (frame['type']) {
        case 'hub_state':
          _hubConnected = frame['connected'] == true;
          if (_hubConnected && !_ready.isCompleted) _ready.complete();
        case 'defaults':
          final value = clineObject(frame['defaults']);
          if (_provider.isEmpty) _provider = clineString(value['provider']);
          if (_model.isEmpty) _model = clineString(value['model']);
          if (_project.isEmpty) _project = clineString(value['workspaceRoot']);
        case 'providers':
          _providers = clineObjects(frame['providers'])
              .where((p) => p['enabled'] == true)
              .map(ClineProvider.fromJson)
              .toList();
        case 'models':
          final id = clineString(frame['providerId']);
          _models[id] = List.unmodifiable(
            clineObjects(frame['models'])
                .where(
                  (m) => m['operation'] == null || m['operation'] == 'language',
                )
                .map(ClineModel.fromJson)
                .where((m) => m.id.isNotEmpty),
          );
        case 'sessions':
          _sessions =
              clineObjects(frame['sessions'])
                  .map(ClineSession.fromJson)
                  .where((s) => s.id.isNotEmpty)
                  .toList()
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        case 'session_started':
          final id = clineString(frame['sessionId']);
          if (_newTurn && _sessionId == null) {
            createdSessionId = id;
            createdProject = _project;
          }
          if (_awaitedSession == null || _awaitedSession == id) _sessionId = id;
        case 'session_hydrated':
          final id = clineString(frame['sessionId']);
          if (_awaitedSession != null && _awaitedSession != id) return;
          if (_sessionId != null && _sessionId != id && _awaitedSession == null)
            return;
          _sessionId = id;
          _awaitedSession = null;
          _loadingHistory = false;
          final values = clineObjects(frame['messages']);
          final optimistic = _messages
              .where((m) => m.local && m.role == 'user')
              .toList();
          _messages = [
            for (var i = 0; i < values.length; i++)
              ClineChatMessage.fromJson(values[i], 'history-' + i.toString()),
          ];
          if (_newTurn && _pendingPrompt != null && values.isEmpty)
            _messages.addAll(optimistic);
          _provider = clineString(frame['providerId'], _provider);
          _model = clineString(frame['modelId'], _model);
          final session = _sessions.where((s) => s.id == id).firstOrNull;
          if (session != null && session.project.isNotEmpty)
            _project = session.project;
          _busy =
              _pendingPrompt != null ||
              {'running', 'starting', 'stopping'}.contains(frame['status']);
          _assistantId = null;
        case 'assistant_delta':
          _appendText('text', clineString(frame['text']));
        case 'reasoning_delta':
          _appendText(
            'reasoning',
            clineString(frame['text']),
            redacted: frame['redacted'] == true,
          );
        case 'tool_event':
          final value = clineObject(frame['event']);
          if (value.isNotEmpty)
            _updateTool(value);
          else
            _status = clineString(frame['text']);
        case 'assistant_media':
          final media = clineObject(frame['media']);
          _updateAssistant(
            (m) => m.copyWith(
              media: [...m.media, media],
              parts: [
                ...m.parts,
                ClineMessagePart(type: 'media', media: media),
              ],
            ),
          );
        case 'approval_request':
          final id = clineString(frame['approvalId']);
          final session = clineString(frame['sessionId']);
          if (id.isNotEmpty && session == _sessionId) {
            _approvals[id] = ClineApproval(
              id: id,
              sessionId: session,
              toolName: clineString(frame['toolName']),
              input: frame['input'],
            );
            _busy = true;
          }
        case 'approval_resolved':
          _approvals.remove(clineString(frame['approvalId']));
        case 'status':
          _status = clineString(frame['text']);
          if ({'running', 'starting', 'stopping'}.contains(_status))
            _busy = true;
        case 'turn_done':
          _finish(usage: clineObject(frame['usage']));
          _status = clineString(frame['finishReason']);
        case 'error':
          _error = clineString(frame['text'], 'server');
          if (frame['recoverable'] != true &&
              _pendingPrompt != null &&
              _approvals.isEmpty) {
            _uncertainPrompt = _pendingPrompt;
            _finish();
          }
        case 'reset_done':
          _resetting = false;
          _sessionId = null;
          _awaitedSession = null;
          _assistantId = null;
          _messages = [];
          _approvals.clear();
        case 'fork_done':
          final id = clineString(frame['newSessionId']);
          if (id.isNotEmpty) openSession(id);
        case 'desktopCommandResult':
          final request = _requests.remove(clineString(frame['id']));
          if (request != null) {
            if (frame['ok'] == true)
              request.complete(frame['result']);
            else
              request.completeError(const ClineNativeException('request'));
          }
        // Catalog may contain credentials. Do not retain it, settings, raw frames, or unknown fields.
        case 'provider_catalog':
          break;
      }
      _notify();
    } catch (_) {
      _error = 'protocol';
      _notify(immediate: true);
    }
  }

  void _updateAssistant(ClineChatMessage Function(ClineChatMessage) transform) {
    var index = _assistantId == null
        ? -1
        : _messages.indexWhere((m) => m.id == _assistantId);
    if (index < 0) {
      _assistantId = 'stream-' + (++_sequence).toString();
      _messages.add(
        ClineChatMessage(id: _assistantId!, role: 'assistant', streaming: true),
      );
      index = _messages.length - 1;
    }
    _messages[index] = transform(_messages[index]);
  }

  void _appendText(String type, String text, {bool redacted = false}) {
    if (text.isEmpty && !redacted) return;
    _updateAssistant((message) {
      final parts = [...message.parts];
      if (parts.isNotEmpty && parts.last.type == type) {
        final last = parts.removeLast();
        parts.add(
          ClineMessagePart(
            type: type,
            text: redacted ? '' : last.text + text,
            redacted: last.redacted || redacted,
          ),
        );
      } else {
        parts.add(
          ClineMessagePart(
            type: type,
            text: redacted ? '' : text,
            redacted: redacted,
          ),
        );
      }
      return message.copyWith(
        text: type == 'text' ? message.text + text : null,
        reasoning: type == 'reasoning'
            ? (redacted ? '' : message.reasoning + text)
            : null,
        redacted: message.redacted || redacted,
        parts: parts,
      );
    });
    _busy = true;
  }

  void _updateTool(Map<String, dynamic> value) {
    _updateAssistant((message) {
      final tools = [...message.tools];
      final incoming = ClineToolActivity.fromJson(
        value,
        'tool-' + (++_sequence).toString(),
      );
      final index = tools.indexWhere((t) => t.id == incoming.id);
      final activity = index < 0 ? incoming : tools[index].update(value);
      if (index < 0)
        tools.add(activity);
      else
        tools[index] = activity;
      final parts = [...message.parts];
      final part = parts.indexWhere(
        (p) => p.type == 'tool' && p.tool?.id == activity.id,
      );
      if (part < 0)
        parts.add(ClineMessagePart(type: 'tool', tool: activity));
      else
        parts[part] = ClineMessagePart(type: 'tool', tool: activity);
      return message.copyWith(tools: tools, parts: parts);
    });
  }

  void _finish({Map<String, dynamic> usage = const {}}) {
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].streaming)
        _messages[i] = _messages[i].copyWith(
          streaming: false,
          usage: usage.isEmpty ? null : usage,
        );
    }
    _busy = false;
    _pendingPrompt = null;
    _newTurn = false;
    _assistantId = null;
    _approvals.clear();
  }

  void openSession(String id) {
    if (_busy || _loadingHistory || _resetting)
      throw const ClineNativeException('busy');
    _awaitedSession = id;
    _loadingHistory = true;
    _error = null;
    _assistantId = null;
    _mode = '';
    _send({'type': 'attachSession', 'sessionId': id});
    _notify(immediate: true);
  }

  void newChat({String? project}) {
    if (_busy || _loadingHistory || _resetting)
      throw const ClineNativeException('busy');
    if (project != null && project.trim().isNotEmpty) _project = project.trim();
    if (_mode.isEmpty) _mode = 'act';
    _resetting = true;
    _send({'type': 'reset'});
    _notify(immediate: true);
  }

  void configure({
    String? provider,
    String? model,
    String? project,
    String? mode,
    String? reasoning,
  }) {
    if (_busy || _loadingHistory || _resetting)
      throw const ClineNativeException('busy');
    if (_sessionId != null &&
        (provider != null ||
            model != null ||
            project != null ||
            reasoning != null))
      throw const ClineNativeException('existingContext');
    if (provider != null) {
      _provider = provider;
      if (!_models.containsKey(provider)) requestModels(provider);
    }
    if (model != null) _model = model;
    if (project != null) _project = project;
    if (mode != null) _mode = mode == 'plan' ? 'plan' : 'act';
    if (reasoning != null &&
        {'none', 'low', 'medium', 'high'}.contains(reasoning))
      _reasoning = reasoning;
    _notify(immediate: true);
  }

  void sendMessage(
    String text, {
    List<ClineAttachment> attachments = const [],
  }) {
    if (!state.canSend) throw const ClineNativeException('busy');
    final frame = clineSendFrame(
      text: text,
      newSession: _sessionId == null,
      project: _project,
      provider: _provider,
      model: _model,
      mode: _mode,
      reasoning:
          (_models[_provider]?.any((m) => m.id == _model && m.reasoning) ??
              false)
          ? _reasoning
          : 'none',
      attachments: attachments,
    );
    if (utf8.encode(jsonEncode(frame)).length > 12 * 1024 * 1024)
      throw const ClineNativeException('payload');
    _newTurn = _sessionId == null;
    _pendingPrompt = text;
    _uncertainPrompt = null;
    _busy = true;
    _error = null;
    _assistantId = null;
    _messages.add(
      ClineChatMessage(
        id: 'local-' + (++_sequence).toString(),
        role: 'user',
        text: text,
        local: true,
        media: [
          for (final a in attachments)
            {
              ...a.reference,
              if (a.imageDataUrl != null) 'url': a.imageDataUrl,
              'type': 'attachment',
            },
        ],
      ),
    );
    try {
      _send(frame);
    } catch (_) {
      _uncertainPrompt = text;
      _notify(immediate: true);
      rethrow;
    }
    _notify(immediate: true);
  }

  void requestModels(String provider) {
    if (_busy || !_providers.any((p) => p.id == provider))
      throw const ClineNativeException('busy');
    _send({'type': 'loadModels', 'providerId': provider});
  }

  void renameSession(String id, String title) {
    if (_busy || title.trim().isEmpty || title.length > 200)
      throw const ClineNativeException('busy');
    _send({
      'type': 'updateSessionMetadata',
      'sessionId': id,
      'metadata': {'title': title.trim()},
    });
  }

  void deleteSession(String id) {
    final session = _sessions.where((s) => s.id == id).firstOrNull;
    if (session == null ||
        {'running', 'starting', 'stopping'}.contains(session.status) ||
        (_sessionId == id && _busy))
      throw const ClineNativeException('busy');
    _send({'type': 'deleteSession', 'sessionId': id});
  }

  void forkSession() {
    if (_busy || _sessionId == null) throw const ClineNativeException('busy');
    _send({'type': 'forkSession'});
  }

  void approve(String id, bool approved) {
    final request = _approvals[id];
    if (request == null ||
        request.responding ||
        request.sessionId != _sessionId)
      throw const ClineNativeException('approval');
    _approvals[id] = request.pendingResponse();
    _send({
      'type': 'approval_response',
      'approvalId': id,
      'approved': approved,
    });
    _notify(immediate: true);
  }

  void abort() {
    if (_busy) _send({'type': 'abort'});
  }

  void clearError() {
    _error = null;
    _notify(immediate: true);
  }

  Future<ClineUploadedFile> upload(File file, String name) {
    if (!_connected || _upload == null)
      throw const ClineNativeException('offline');
    return _upload(file, name);
  }

  void clearUncertainPrompt() {
    _uncertainPrompt = null;
    _notify(immediate: true);
  }

  void retainUncertainPrompt(String? prompt) {
    _uncertainPrompt = prompt;
    _notify(immediate: true);
  }

  Future<Object?> request(String command, {Map<String, dynamic>? args}) async {
    if (!{
      'get_process_context',
      'list_cli_sessions',
      'search_sessions',
    }.contains(command))
      throw const ClineNativeException('request');
    final id = 'native-' + (++_sequence).toString();
    final result = Completer<Object?>();
    _requests[id] = result;
    try {
      _send({
        'type': 'desktopCommand',
        'id': id,
        'command': command,
        if (args != null) 'args': args,
      });
      return await result.future.timeout(const Duration(seconds: 20));
    } finally {
      _requests.remove(id);
    }
  }

  void _disconnected() {
    if (!_connected) return;
    _connected = false;
    _hubConnected = false;
    _uncertainPrompt = _pendingPrompt ?? _uncertainPrompt;
    _busy = false;
    _loadingHistory = false;
    _resetting = false;
    _error ??= 'offline';
    _approvals.clear();
    if (!_ready.isCompleted)
      _ready.completeError(const ClineNativeException('connection'));
    for (final result in _requests.values) {
      if (!result.isCompleted)
        result.completeError(const ClineNativeException('offline'));
    }
    _requests.clear();
    _notify(immediate: true);
    unawaited(_closeOwner());
  }

  Future<void> _closeOwner() => _ownerClosed ??=
      (_onClose?.call() ?? Future<void>.value()).catchError((Object _) {});

  Future<void> close() async {
    if (_closed) return;
    _disconnected();
    _closed = true;
    _notification?.cancel();
    await _subscription.cancel();
    try {
      await _transport.close();
    } catch (_) {
      /* Best-effort transport shutdown. */
    }
    await _closeOwner();
    // A paused UI observer must never hold the SSH connection open at disposal.
    unawaited(_changes.close());
  }
}

final class ClineNativeException implements Exception {
  const ClineNativeException(this.code);
  final String code;
  @override
  String toString() => 'Cline native: ' + code;
}
