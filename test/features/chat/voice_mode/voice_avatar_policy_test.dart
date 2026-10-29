import 'package:conduit/features/chat/voice_mode/voice_avatar_policy.dart';
import 'package:conduit/features/chat/voice_mode/voice_avatar_view.dart';
import 'package:conduit_core/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '97abe420-cbc2-4f30-a00c-7940119d7d4f';
  test('uses the selected model avatar, never a provider URL', () {
    final model = Model.fromJson({
      'id': 'test',
      'name': 'test',
      'info': {
        'meta': {
          'voice_avatar': {'file_id': id},
        },
      },
    });
    expect(voiceAvatarFileId(model), id);
    expect(voiceAvatarFileId(null), isNull);
    expect(
      voiceAvatarFileId(
        Model.fromJson({
          'id': 'test',
          'meta': {
            'voice_avatar': {'file_id': 'https://evil.invalid/model.vrm'},
          },
        }),
      ),
      isNull,
    );
    expect(
      voiceAvatarFileId(
        Model.fromJson({
          'id': 'test',
          'meta': {
            'voice_avatar': {'file_id': '../private/key'},
          },
        }),
      ),
      isNull,
    );
  });
  test('only assistant speech opens the mouth; levels are bounded', () {
    Map<String, Object> signal(bool speaking, int intensity, bool active) =>
        voiceAvatarSignals(
          speaking: speaking,
          intensity: intensity,
          active: active,
          reducedMotion: true,
        );
    expect(signal(false, 10, true)['level'], 0);
    expect(signal(true, 10, false)['level'], 0);
    expect(signal(true, 99, true)['level'], 1);
    expect(signal(true, -1, true)['level'], 0);
    expect(signal(true, 5, true)['level'], .5);
    expect(signal(true, 5, true)['reducedMotion'], isTrue);
  });
  test(
    'viewport cannot access network, files, storage or Native Messaging',
    () {
      for (final u in [
        'https://example.com/model.vrm',
        'http://127.0.0.1:8080/',
        'file:///private/key',
        'content://key',
        'javascript:alert(1)',
        'data:text/html,hi',
      ]) {
        expect(voiceAvatarResourceAllowed(Uri.parse(u)), isFalse);
      }
      expect(
        voiceAvatarResourceAllowed(Uri.parse('blob:$voiceAvatarOrigin/123')),
        isTrue,
      );
      final s = voiceAvatarWebViewSettings();
      expect(s.blockNetworkLoads, isTrue);
      expect(s.allowFileAccess, isFalse);
      expect(s.allowContentAccess, isFalse);
      expect(s.javaScriptBridgeEnabled, isFalse);
      expect(s.sharedCookiesEnabled, isFalse);
      expect(s.domStorageEnabled, isFalse);
      expect(s.geolocationEnabled, isFalse);
    },
  );
}
