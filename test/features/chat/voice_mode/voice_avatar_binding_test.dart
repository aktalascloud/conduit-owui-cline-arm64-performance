import 'dart:async';

import 'package:conduit/features/chat/voice_mode/voice_avatar_binding.dart';
import 'package:conduit_core/ports/app_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lifecycle implements AppLifecyclePort {
  final events = StreamController<AppLifecyclePhase>.broadcast(sync: true);
  @override
  AppLifecyclePhase? current = AppLifecyclePhase.resumed;
  @override
  Stream<AppLifecyclePhase> get changes => events.stream;
  void set(AppLifecyclePhase value) {
    current = value;
    events.add(value);
  }
}

void main() {
  test(
    'fresh model card replaces old avatar and respects explicit removal',
    () async {
      final lifecycle = _Lifecycle();
      var id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      var revision = 1;
      final updates = <VoiceAvatarBinding?>[];
      final subscription = watchVoiceAvatarBindings(
        () async => {
          'updated_at': revision,
          'meta': {
            'voice_avatar': id.isEmpty ? null : {'file_id': id},
          },
        },
        lifecycle: lifecycle,
        interval: const Duration(days: 1),
      ).listen(updates.add);
      await Future<void>.delayed(Duration.zero);
      expect(updates.last?.fileId, id);
      id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      revision++;
      lifecycle.set(AppLifecyclePhase.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(updates.last?.fileId, id);
      id = '';
      revision++;
      lifecycle.set(AppLifecyclePhase.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(updates.last, isNull);
      await subscription.cancel();
      await lifecycle.events.close();
    },
  );

  test(
    'background pauses metadata checks and cancellation stops polling',
    () async {
      final lifecycle = _Lifecycle()..set(AppLifecyclePhase.paused);
      var calls = 0;
      final subscription = watchVoiceAvatarBindings(
        () async {
          calls++;
          return {};
        },
        lifecycle: lifecycle,
        interval: const Duration(milliseconds: 5),
      ).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(calls, 0);
      lifecycle.set(AppLifecyclePhase.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      await subscription.cancel();
      final stoppedAt = calls;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(calls, stoppedAt);
      await lifecycle.events.close();
    },
  );
}
