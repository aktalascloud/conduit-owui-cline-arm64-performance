import 'dart:async';
import 'dart:convert';

import 'package:conduit_core/features/cline/services/cline_native_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _Wire implements ClineWireTransport {
  final events = StreamController<String>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<String> get frames => events.stream;
  @override
  void send(String frame) => sent.add(jsonDecode(frame));
  @override
  Future<void> close() async {
    unawaited(events.close());
  }
}

void ready(_Wire wire, {bool chosen = true}) {
  for (final provider in [
    'different-provider',
    if (chosen) 'chosen-provider',
  ]) {
    wire.events.add(
      jsonEncode({
        'type': 'providers',
        'providers': [
          {'id': 'different-provider', 'enabled': true},
          if (chosen) {'id': 'chosen-provider', 'enabled': true},
        ],
      }),
    );
    wire.events.add(
      jsonEncode({
        'type': 'models',
        'providerId': provider,
        'models': [
          {
            'id': provider == 'chosen-provider'
                ? 'chosen-model'
                : 'different-model',
            'operation': 'language',
          },
        ],
      }),
    );
  }
  wire.events.add(jsonEncode({'type': 'hub_state', 'connected': true}));
}

void main() {
  test('reconnect restores explicit new-chat selection without sending or clearing uncertainty', () async {
    final oldWire = _Wire();
    final old = ClineNativeClient(
      oldWire,
      project: 'initial',
      identity: 'account-a',
    );
    ready(oldWire);
    old.configure(
      provider: 'chosen-provider',
      model: 'chosen-model',
      project: 'chosen-project',
      reasoning: 'high',
    );
    final choice = ClineDraftSelection.capture(old)!;
    final wire = _Wire();
    final restored = ClineNativeClient(
      wire,
      project: 'different-default',
      identity: 'account-a',
    );
    ready(wire);
    restored.configure(
      provider: 'different-provider',
      model: 'different-model',
    );
    restored.retainUncertainPrompt('Uncertain fixture, never replay');
    expect(choice.restore(restored), isTrue);
    expect(restored.state.project, 'chosen-project');
    expect(restored.state.provider, 'chosen-provider');
    expect(restored.state.model, 'chosen-model');
    expect(restored.state.reasoning, 'high');
    expect(restored.state.mode, 'act');
    expect(restored.state.uncertainPrompt, 'Uncertain fixture, never replay');
    expect(wire.sent.where((frame) => frame['type'] == 'send'), isEmpty);
    await old.close();
    await restored.close();
  });
  test(
    'another account never receives the previous draft configuration',
    () async {
      final old = ClineNativeClient(
        _Wire(),
        project: 'private-project',
        identity: 'account-a',
      );
      final other = ClineNativeClient(
        _Wire(),
        project: 'other-project',
        identity: 'account-b',
      );
      expect(ClineDraftSelection.capture(old)!.restore(other), isFalse);
      expect(other.state.project, 'other-project');
      await old.close();
      await other.close();
    },
  );
  test(
    'a removed provider stays explicit and blocks sends until a valid choice',
    () async {
      final oldWire = _Wire();
      final old = ClineNativeClient(
        oldWire,
        project: 'chosen-project',
        identity: 'account-a',
      );
      ready(oldWire);
      old.configure(provider: 'chosen-provider', model: 'chosen-model');
      final wire = _Wire();
      final restored = ClineNativeClient(
        wire,
        project: 'different-default',
        identity: 'account-a',
      );
      ready(wire, chosen: false);
      expect(ClineDraftSelection.capture(old)!.restore(restored), isTrue);
      expect(restored.state.project, 'chosen-project');
      expect(restored.state.provider, 'chosen-provider');
      expect(restored.state.model, 'chosen-model');
      expect(restored.state.error, 'selectionUnavailable');
      expect(restored.state.canSend, isFalse);
      restored.clearError();
      expect(restored.state.canSend, isFalse);
      expect(wire.sent.where((f) => f['type'] == 'send'), isEmpty);
      restored.configure(
        provider: 'different-provider',
        model: 'different-model',
      );
      expect(restored.state.error, isNull);
      expect(restored.state.canSend, isTrue);
      await old.close();
      await restored.close();
    },
  );
}
