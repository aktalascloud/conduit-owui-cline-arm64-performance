import 'dart:convert';

/// A device-private connection. Store its JSON only in secure storage.
final class ClineRemoteProfile {
  const ClineRemoteProfile({
    required this.host,
    required this.sshPassword,
    required this.hostKeyFingerprint,
    required this.roomSecret,
    this.name = 'Cline Desktop',
    this.sshPort = 2222,
    this.dashboardPort = 11280,
    this.projectPath = '',
  });

  final String name;
  final String host;
  final int sshPort;
  final int dashboardPort;
  final String sshPassword;
  final String hostKeyFingerprint;
  final String roomSecret;
  final String projectPath;

  static const maximumJsonBytes = 16384;

  factory ClineRemoteProfile.decode(String source) {
    if (source.length > maximumJsonBytes || utf8.encode(source).length > maximumJsonBytes) {
      throw const FormatException('Connection profile is too large');
    }
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> || value['schema'] != 1) {
      throw const FormatException('Unsupported connection profile');
    }
    if ((value['username'] ?? 'cline') != 'cline') {
      throw const FormatException('Use the dedicated Cline tunnel account');
    }
    String string(String key) {
      final item = value[key];
      if (item is! String) {
        throw const FormatException('Missing connection field');
      }
      return item;
    }

    int port(String key, int fallback) {
      final item = value[key] ?? fallback;
      if (item is! int || item < 1024 || item > 65535) {
        throw const FormatException('Invalid connection port');
      }
      return item;
    }

    final name = value['name'] ?? 'Cline Desktop';
    final host = string('host').trim();
    final password = string('sshPassword');
    final roomSecret = string('roomSecret');
    final fingerprint = string('hostKeyFingerprint').trim();
    final project = value['projectPath'] ?? '';
    if (project is! String ||
        project.length > 1024 ||
        project.contains('\u0000') ||
        (project.isNotEmpty &&
            !project.startsWith('/') &&
            !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(project))) {
      throw const FormatException('Use an absolute project folder on the PC');
    }
    if (name is! String ||
        name.length > 100 ||
        host.isEmpty ||
        host.length > 253 ||
        !RegExp(r'^[a-zA-Z0-9.:[\]-]+$').hasMatch(host) ||
        host.contains('..') ||
        password.length < 32 ||
        password.length > 256 ||
        roomSecret.length < 32 ||
        roomSecret.length > 256 ||
        password == roomSecret ||
        !RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(fingerprint)) {
      throw const FormatException('Invalid connection profile');
    }
    return ClineRemoteProfile(
      name: name,
      host: host,
      sshPort: port('sshPort', 2222),
      dashboardPort: port('dashboardPort', 11280),
      sshPassword: password,
      hostKeyFingerprint: fingerprint,
      roomSecret: roomSecret,
      projectPath: project,
    );
  }

  Map<String, Object> toJson() => {
    'schema': 1,
    'name': name,
    'host': host,
    'sshPort': sshPort,
    'dashboardPort': dashboardPort,
    'username': 'cline',
    'sshPassword': sshPassword,
    'hostKeyFingerprint': hostKeyFingerprint,
    'roomSecret': roomSecret,
    'projectPath': projectPath,
  };

  /// HTTP is confined to device loopback; SSH encrypts the network leg.
  Uri dashboardUrl(int localPort) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: localPort,
    path: '/',
    queryParameters: {'roomSecret': roomSecret},
  );
}

bool clineDashboardNavigationAllowed(Uri target, Uri origin) =>
    target.scheme == origin.scheme &&
    target.host == origin.host &&
    target.port == origin.port &&
    target.userInfo.isEmpty;
