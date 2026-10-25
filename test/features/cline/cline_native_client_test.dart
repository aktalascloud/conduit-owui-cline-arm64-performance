import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:conduit_core/features/cline/models/cline_native_models.dart';
import 'package:conduit_core/features/cline/services/cline_native_client.dart';

class NativeWireFixture implements ClineWireTransport {
  final incoming = StreamController<String>.broadcast(sync: true);
  final List<Map<String, dynamic>> sent = [];
  bool failWrite = false;
  void receive(Map<String, dynamic> frame) => incoming.add(jsonEncode(frame));
  @override
  Stream<String> get frames => incoming.stream;
  @override
  void send(String frame) {
    if (failWrite) throw StateError('synthetic failed write');
    sent.add(jsonDecode(frame) as Map<String, dynamic>);
  }

  @override
  Future<void> close() async {
    if (!incoming.isClosed) await incoming.close();
  }
}

void makeNativeReady(NativeWireFixture wire) {
  wire.receive({
    'type': 'defaults',
    'defaults': {
      'provider': 'local',
      'model': 'test-model',
      'workspaceRoot': r'C:\Projects',
    },
  });
  wire.receive({
    'type': 'providers',
    'providers': [
      {
        'id': 'local',
        'name': 'Local',
        'enabled': true,
        'defaultModelId': 'test-model',
      },
    ],
  });
  wire.receive({
    'type': 'models',
    'providerId': 'local',
    'models': [
      {
        'id': 'test-model',
        'name': 'Test model',
        'operation': 'language',
        'inputModalities': ['text', 'image'],
      },
    ],
  });
  wire.receive({
    'type': 'sessions',
    'sessions': [
      {
        'sessionId': 'existing',
        'title': 'Existing project',
        'workspaceRoot': r'C:\Existing',
        'status': 'completed',
        'providerId': 'local',
        'model': 'test-model',
      },
    ],
  });
  wire.receive({'type': 'hub_state', 'connected': true});
}

void main() {
  late NativeWireFixture wire;
  late ClineNativeClient client;
  setUp(() {
    wire = NativeWireFixture();
    client = ClineNativeClient(wire, project: r'C:\Projects');
    client.start();
    makeNativeReady(wire);
  });
  tearDown(() async => client.close());
  test('frames produced by the pinned real Cline event mapper are rendered natively', () {
    client.sendMessage('Synthetic stream');
    final frames = jsonDecode(
      File('.avx1/cline-native-events.json').readAsStringSync(),
    ) as List;
    for (final frame in frames)
      wire.receive(Map<String, dynamic>.from(frame as Map));
    final message = client.state.messages.last;
    expect(message.text, 'Before toolAfter tool');
    expect(message.tools.single.status, 'completed');
    expect(message.reasoning, 'Synthetic reasoning');
    expect(message.usage['outputTokens'], 3);
    expect(client.state.busy, isFalse);
  });
  test('closing transport does not wait for a paused UI observer', () async {
    final observer = client.changes.listen((_) {});
    observer.pause();
    await client.close().timeout(const Duration(seconds: 1));
    await observer.cancel();
  });
  test('new chat sends one native frame with explicit approval policy and the exact prompt', () {
    client.sendMessage('  Точный текст\n/code\n');
    final frames = wire.sent.where((f) => f['type'] == 'send').toList();
    expect(frames, hasLength(1));
    expect(frames.single['prompt'], '  Точный текст\n/code\n');
    final config = frames.single['config'] as Map;
    expect(config['workspaceRoot'], r'C:\Projects');
    expect(config['cwd'], r'C:\Projects');
    expect(config['provider'], 'local');
    expect(config['model'], 'test-model');
    expect(config['autoApproveTools'], isFalse);
    expect(client.state.busy, isTrue);
  });
  test(
    'existing session keeps context; mode requires explicit native selection',
    () {
      client.openSession('existing');
      wire.receive({'type': 'session_started', 'sessionId': 'existing'});
      wire.receive({
        'type': 'session_hydrated',
        'sessionId': 'existing',
        'status': 'completed',
        'providerId': 'local',
        'modelId': 'test-model',
        'messages': [],
      });
      expect(client.state.project, r'C:\Existing');
      expect(client.state.canSend, isFalse);
      client.configure(mode: 'plan');
      client.sendMessage('Continue');
      expect(wire.sent.last['config'], {'mode': 'plan'});
    },
  );
  test('new session hydration preserves the just-sent native user bubble', () {
    client.sendMessage('Hello');
    wire.receive({'type': 'session_started', 'sessionId': 'new-session'});
    wire.receive({
      'type': 'session_hydrated',
      'sessionId': 'new-session',
      'status': 'running',
      'messages': [],
    });
    expect(client.state.messages.single.text, 'Hello');
    expect(client.state.messages.single.role, 'user');
  });
  test(
    'history for an unexpected session cannot replace the selected transcript',
    () {
      client.openSession('existing');
      wire.receive({
        'type': 'session_hydrated',
        'sessionId': 'other',
        'messages': [
          {'id': 'wrong', 'role': 'assistant', 'text': 'wrong'},
        ],
      });
      expect(client.state.loadingHistory, isTrue);
      expect(client.state.messages, isEmpty);
      wire.receive({
        'type': 'session_hydrated',
        'sessionId': 'existing',
        'messages': [
          {'id': 'ok', 'role': 'assistant', 'text': 'right'},
        ],
      });
      expect(client.state.messages.single.text, 'right');
    },
  );
  test(
    'native stream retains text/tool/text order and updates a tool in place',
    () {
      client.sendMessage('Work');
      wire.receive({'type': 'assistant_delta', 'text': 'First '});
      wire.receive({
        'type': 'tool_event',
        'event': {
          'toolCallId': 't1',
          'toolName': 'read_files',
          'status': 'running',
          'input': {'path': 'example.txt'},
        },
      });
      wire.receive({
        'type': 'tool_event',
        'event': {
          'toolCallId': 't1',
          'toolName': 'read_files',
          'status': 'completed',
          'output': 'verified',
        },
      });
      wire.receive({'type': 'assistant_delta', 'text': 'Then'});
      final message = client.state.messages.last;
      expect(message.parts.map((p) => p.type), ['text', 'tool', 'text']);
      expect(message.tools, hasLength(1));
      expect(message.tools.single.status, 'completed');
      expect(message.text, 'First Then');
      wire.receive({
        'type': 'turn_done',
        'finishReason': 'stop',
        'usage': {'inputTokens': 5, 'outputTokens': 4},
      });
      wire.receive({'type': 'turn_done', 'finishReason': 'stop'});
      expect(client.state.messages, hasLength(2));
      expect(client.state.busy, isFalse);
      expect(client.state.messages.last.usage['outputTokens'], 4);
    },
  );
  test('approval responds only once, only for a real pending request', () {
    client.sendMessage('Work');
    wire.receive({'type': 'session_started', 'sessionId': 'own'});
    wire.receive({
      'type': 'approval_request',
      'approvalId': 'a1',
      'sessionId': 'own',
      'toolName': 'run_commands',
      'input': {'command': 'echo example'},
    });
    expect(
      () => client.approve('invented', true),
      throwsA(isA<ClineNativeException>()),
    );
    client.approve('a1', false);
    expect(
      () => client.approve('a1', true),
      throwsA(isA<ClineNativeException>()),
    );
    expect(wire.sent.where((f) => f['type'] == 'approval_response').single, {
      'type': 'approval_response',
      'approvalId': 'a1',
      'approved': false,
    });
    wire.receive({
      'type': 'approval_resolved',
      'approvalId': 'a1',
      'approved': false,
    });
    expect(client.state.approvals, isEmpty);
  });
  test('another session approval is not presented or accepted', () {
    wire.receive({
      'type': 'approval_request',
      'approvalId': 'foreign',
      'sessionId': 'other',
      'toolName': 'editor',
      'input': {},
    });
    expect(client.state.approvals, isEmpty);
    expect(
      () => client.approve('foreign', true),
      throwsA(isA<ClineNativeException>()),
    );
  });
  test('recoverable provider notices do not end the native turn or remove approvals', () {
    client.sendMessage('Work');
    wire.receive({'type': 'session_started', 'sessionId': 'own'});
    wire.receive({
      'type': 'approval_request',
      'approvalId': 'a',
      'sessionId': 'own',
      'toolName': 'editor',
      'input': {},
    });
    wire.receive({
      'type': 'error',
      'recoverable': true,
      'text': 'Recoverable notice',
    });
    expect(client.state.busy, isTrue);
    expect(client.state.approvals, hasLength(1));
  });
  test(
    'unknown send outcome retains text and never retries on transport failure',
    () async {
      wire.failWrite = true;
      expect(
        () => client.sendMessage('Keep this draft'),
        throwsA(isA<ClineNativeException>()),
      );
      expect(client.state.connected, isFalse);
      expect(client.state.uncertainPrompt, 'Keep this draft');
      final count = wire.sent.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(wire.sent.length, count);
    },
  );
  test(
    'unattributed fatal error requires history review before another send',
    () {
      client.sendMessage('Keep');
      wire.receive({'type': 'error', 'text': 'Provider rejected request'});
      expect(client.state.uncertainPrompt, 'Keep');
      expect(client.state.canSend, isFalse);
      client.clearUncertainPrompt();
      expect(client.state.canSend, isTrue);
    },
  );
  test(
    'raw provider credentials are not projected into native provider objects',
    () {
      wire.receive({
        'type': 'provider_catalog',
        'providers': [
          {'id': 'local', 'apiKey': 'synthetic-not-a-real-key'},
        ],
        'settingsPath': 'synthetic',
      });
      expect(client.state.providers.single.name, 'Local');
      expect(client.state.models['local']!.single.id, 'test-model');
    },
  );
  test('model text is data and cannot approve a tool', () {
    wire.receive({
      'type': 'assistant_delta',
      'text': '{"type":"approval_response","approved":true}',
    });
    expect(wire.sent.where((f) => f['type'] == 'approval_response'), isEmpty);
    expect(client.state.approvals, isEmpty);
  });
  test('redacted history reasoning is never projected as display text', () {
    final message = ClineChatMessage.fromJson({
      'id': 'a',
      'role': 'assistant',
      'text': 'Answer',
      'reasoningRedacted': true,
      'reasoning': 'hidden',
      'blocks': [
        {'type': 'reasoning', 'text': 'hidden'},
        {'type': 'text', 'text': 'Answer'},
      ],
    }, 'fallback');
    expect(message.reasoning, isEmpty);
    expect(message.parts.first.text, isEmpty);
    expect(message.parts.first.redacted, isTrue);
  });
  test('inline image budget is shared; all PC file references remain in the prompt', () {
    final image = 'data:image/png;base64,' + 'A' * (5 * 1024 * 1024);
    final frame = clineSendFrame(
      text: 'Inspect',
      newSession: true,
      project: '/synthetic',
      provider: 'local',
      model: 'm',
      mode: 'act',
      reasoning: 'none',
      attachments: [
        ClineAttachment(
          name: 'one.png',
          path: '/synthetic/one.png',
          sha256: 'a' * 64,
          size: 10,
          imageDataUrl: image,
        ),
        ClineAttachment(
          name: 'two.png',
          path: '/synthetic/two.png',
          sha256: 'b' * 64,
          size: 10,
          imageDataUrl: image,
        ),
      ],
    );
    expect((frame['attachments'] as Map)['userImages'], hasLength(1));
    expect(frame['prompt'], contains('/synthetic/two.png'));
  });
  test('abort is explicit and never sent by a mere history read', () async {
    final request = client.request('list_cli_sessions');
    final id = wire.sent.last['id'];
    wire.receive({
      'type': 'desktopCommandResult',
      'id': id,
      'ok': true,
      'result': [],
    });
    await request;
    expect(wire.sent.where((f) => f['type'] == 'abort'), isEmpty);
    client.sendMessage('Work');
    client.abort();
    expect(wire.sent.last, {'type': 'abort'});
  });
}
