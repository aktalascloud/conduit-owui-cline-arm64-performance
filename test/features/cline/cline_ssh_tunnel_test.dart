import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:conduit_core/features/cline/models/cline_remote_profile.dart';
import 'package:conduit_core/features/cline/services/cline_ssh_tunnel.dart';

void main() {
  late Process fixture;
  late ClineRemoteProfile profile;
  setUpAll(() async {
    fixture = await Process.start(
      Platform.environment['CONDUIT_SSH_TEST_PYTHON'] ?? 'python',
      ['-B', 'remote/ssh_test_fixture.py'],
    );
    final source = await fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 20));
    profile = ClineRemoteProfile.decode(source);
    fixture.stderr.drain<void>();
  });
  tearDownAll(() async {
    await fixture.stdin.close();
    try {
      await fixture.exitCode.timeout(const Duration(seconds: 10));
    } catch (_) {
      fixture.kill();
    }
  });
  test(
    'Dart pins the real Python SSH server and forwards HTTP bytes',
    () async {
      final tunnel = await ClineSshTunnel.connect(profile, localPort: 0);
      final http = HttpClient();
      try {
        final request = await http.getUrl(tunnel.url);
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(
          await response.transform(utf8.decoder).join(),
          'conduit-cline-encrypted-transport-ok',
        );
      } finally {
        http.close(force: true);
        await tunnel.close();
      }
    },
  );
  test('changed server key is rejected before authentication', () async {
    final changed = ClineRemoteProfile.decode(
      jsonEncode({
        ...profile.toJson(),
        'hostKeyFingerprint': 'SHA256:${'A' * 43}',
      }),
    );
    await expectLater(
      ClineSshTunnel.connect(changed, localPort: 0),
      throwsA(
        isA<ClineConnectionException>().having(
          (e) => e.failure,
          'failure',
          ClineConnectionFailure.hostKey,
        ),
      ),
    );
  });
  test(
    'real Dart upload verifies document bytes and digest over SSH',
    () async {
      final tunnel = await ClineSshTunnel.connect(profile, localPort: 0);
      final directory = await Directory.systemTemp.createTemp(
        'conduit-upload-test-',
      );
      try {
        final file = File('${directory.path}/example.txt');
        await file.writeAsString('synthetic encrypted document');
        final uploaded = await tunnel.upload(file, 'example.txt');
        expect(uploaded.size, await file.length());
        expect(uploaded.sha256, hasLength(64));
        final again = await tunnel.upload(file, 'example.txt');
        expect(again.path, uploaded.path);
        // The fixture shares this test machine's filesystem, never a real profile.
        expect(
          await File(uploaded.path).readAsBytes(),
          await file.readAsBytes(),
        );
      } finally {
        await tunnel.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test('wrong credentials do not start a local listener', () async {
    final changed = ClineRemoteProfile.decode(
      jsonEncode({
        ...profile.toJson(),
        'sshPassword': 'wrong-synthetic-password-not-a-real-credential',
      }),
    );
    await expectLater(
      ClineSshTunnel.connect(changed, localPort: 0),
      throwsA(
        isA<ClineConnectionException>().having(
          (e) => e.failure,
          'failure',
          ClineConnectionFailure.authentication,
        ),
      ),
    );
  });
}
