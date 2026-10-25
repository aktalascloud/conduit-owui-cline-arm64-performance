import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../models/cline_remote_profile.dart';

enum ClineConnectionFailure { hostKey, authentication, network, localPort }

final class ClineConnectionException implements Exception {
  const ClineConnectionException(this.failure);
  final ClineConnectionFailure failure;

  @override
  String toString() => 'Cline connection: ${failure.name}';
}

/// One pinned SSH connection, forwarding only the Cline dashboard.
final class ClineSshTunnel {
  ClineSshTunnel._(this.profile);

  final ClineRemoteProfile profile;
  SSHClient? _client;
  ServerSocket? _listener;
  final Set<Socket> _sockets = {};
  final Set<SSHForwardChannel> _channels = {};
  final Completer<void> _closed = Completer<void>();
  bool _closing = false;

  Future<void> get closed => _closed.future;
  Uri get url => profile.dashboardUrl(_listener!.port);

  static Future<ClineSshTunnel> connect(
    ClineRemoteProfile profile, {
    int? localPort,
  }) async {
    final tunnel = ClineSshTunnel._(profile);
    var hostKeyMismatch = false;
    try {
      final socket = await SSHSocket.connect(
        profile.host.replaceAll(RegExp(r'^\[|\]$'), ''),
        profile.sshPort,
        timeout: const Duration(seconds: 15),
      );
      final client = SSHClient(
        socket,
        username: 'cline',
        onPasswordRequest: () => profile.sshPassword,
        onVerifyHostKey: (type, fingerprint) {
          final matches =
              type == 'ssh-ed25519' &&
              utf8.decode(fingerprint) == profile.hostKeyFingerprint;
          hostKeyMismatch = !matches;
          return matches;
        },
        handshakeTimeout: const Duration(seconds: 15),
        authTimeout: const Duration(seconds: 15),
        keepAliveInterval: const Duration(seconds: 20),
      );
      tunnel._client = client;
      await client.authenticated.timeout(const Duration(seconds: 20));
      client.done.then(
        (_) => unawaited(tunnel.close()),
        onError: (Object _, StackTrace _) => unawaited(tunnel.close()),
      );
      try {
        tunnel._listener = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          localPort ?? profile.dashboardPort,
          shared: false,
        );
      } on SocketException {
        throw const ClineConnectionException(ClineConnectionFailure.localPort);
      }
      if (client.isClosed) {
        throw const ClineConnectionException(ClineConnectionFailure.network);
      }
      tunnel._listener!.listen(
        (socket) => unawaited(tunnel._forward(socket)),
        onError: (Object _, StackTrace _) => unawaited(tunnel.close()),
      );
      return tunnel;
    } catch (error) {
      await tunnel.close();
      if (hostKeyMismatch) {
        throw const ClineConnectionException(ClineConnectionFailure.hostKey);
      }
      if (error is ClineConnectionException) rethrow;
      if (error is SSHAuthFailError || error is SSHAuthAbortError) {
        throw const ClineConnectionException(
          ClineConnectionFailure.authentication,
        );
      }
      throw const ClineConnectionException(ClineConnectionFailure.network);
    }
  }

  Future<void> _forward(Socket socket) async {
    if (_closing || _sockets.length >= 32) {
      socket.destroy();
      return;
    }
    _sockets.add(socket);
    SSHForwardChannel? channel;
    try {
      channel = await _client!
          .forwardLocal('127.0.0.1', profile.dashboardPort)
          .timeout(const Duration(seconds: 15));
      if (_closing) return;
      _channels.add(channel);
      await Future.wait([
        channel.stream.cast<List<int>>().pipe(socket),
        socket.cast<List<int>>().pipe(channel.sink),
      ], eagerError: true);
    } catch (_) {
      // Do not log URLs, credentials, or agent traffic; the WebView reports a
      // closed transport. Never replay a possibly accepted agent command.
    } finally {
      _sockets.remove(socket);
      if (channel != null) {
        _channels.remove(channel);
        channel.destroy();
      }
      socket.destroy();
    }
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _listener?.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    for (final channel in _channels.toList()) {
      channel.destroy();
    }
    _sockets.clear();
    _channels.clear();
    _client?.close();
    if (!_closed.isCompleted) _closed.complete();
  }
}
