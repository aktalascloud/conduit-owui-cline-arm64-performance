import 'dart:convert';

import 'package:test/test.dart';
import 'package:conduit_core/features/cline/models/cline_remote_profile.dart';

void main() {
  Map<String, Object> fixture() => {
    'schema': 1,
    'host': 'host.example',
    'sshPort': 2222,
    'username': 'cline',
    'sshPassword': 'synthetic-test-password-not-a-real-credential',
    'roomSecret': 'different-synthetic-room-not-a-real-credential',
    'hostKeyFingerprint': 'SHA256:${'A' * 43}',
    'dashboardPort': 11280,
  };

  test('private profile round trips and pins the loopback dashboard', () {
    final profile = ClineRemoteProfile.decode(jsonEncode(fixture()));
    expect(
      ClineRemoteProfile.decode(jsonEncode(profile.toJson())).host,
      'host.example',
    );
    final url = profile.dashboardUrl(11280);
    expect(url.host, '127.0.0.1');
    expect(url.queryParameters['roomSecret'], profile.roomSecret);
  });

  test('missing pin, weak secrets, arbitrary username and invalid ports fail closed', () {
    for (final change in [
      {'hostKeyFingerprint': ''},
      {'sshPassword': 'short'},
      {'username': 'root'},
      {'sshPort': 0},
      {'dashboardPort': 70000},
      {'host': 'https://host.example'},
      {'host': 'host.example/path'},
      {'host': 'host.example@another.example'},
    ]) {
      expect(
        () => ClineRemoteProfile.decode(jsonEncode({...fixture(), ...change})),
        throwsFormatException,
      );
    }
  });

  test(
    'foreign origins, alternate ports and credential-bearing URLs are blocked',
    () {
      final root = Uri.parse('http://127.0.0.1:11280/');
      expect(
        clineDashboardNavigationAllowed(root.resolve('/chat'), root),
        isTrue,
      );
      for (final url in [
        'https://example.com',
        'http://127.0.0.1:80/',
        'file:///tmp/test',
        'javascript:alert(1)',
        'http://user@127.0.0.1:11280/',
      ]) {
        expect(clineDashboardNavigationAllowed(Uri.parse(url), root), isFalse);
      }
    },
  );

  test('oversized or unversioned connection documents are rejected', () {
    expect(() => ClineRemoteProfile.decode('x' * 17000), throwsFormatException);
    final json = fixture()..remove('schema');
    expect(
      () => ClineRemoteProfile.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });
}
