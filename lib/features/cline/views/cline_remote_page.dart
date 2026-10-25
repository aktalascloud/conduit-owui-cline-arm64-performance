import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit_core/features/cline/models/cline_remote_profile.dart';
import 'package:conduit_core/features/cline/services/cline_ssh_tunnel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:conduit_core/features/cline/services/cline_native_client.dart';
import 'package:conduit_core/features/cline/providers/cline_backend_providers.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';

import '../../../shared/services/navigation_service.dart';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';

const clineProfileStorageKey = 'conduit.cline.remote.profile.v1';

class ClineRemotePage extends ConsumerStatefulWidget {
  const ClineRemotePage({super.key});

  @override
  ConsumerState<ClineRemotePage> createState() => _ClineRemotePageState();
}

class _ClineRemotePageState extends ConsumerState<ClineRemotePage> {
  final _storage = const FlutterSecureStorage();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '2222');
  final _password = TextEditingController();
  final _fingerprint = TextEditingController();
  final _room = TextEditingController();
  final _project = TextEditingController();
  var _dashboardPort = 11280;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final source = await _storage.read(key: clineProfileStorageKey);
      if (source != null && mounted) _fill(ClineRemoteProfile.decode(source));
    } catch (_) {
      // A missing/locked key store never falls back to plaintext settings.
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.clineStorageError,
        );
      }
    }
  }

  void _fill(ClineRemoteProfile profile) {
    _host.text = profile.host;
    _port.text = '${profile.sshPort}';
    _password.text = profile.sshPassword;
    _fingerprint.text = profile.hostKeyFingerprint;
    _room.text = profile.roomSecret;
    _project.text = profile.projectPath;
    _dashboardPort = profile.dashboardPort;
    setState(() => _error = null);
  }

  Future<void> _import() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null || !mounted) return;
      if (file.path == null) {
        throw const FormatException('Invalid connection document');
      }
      final bytes = await File(file.path!)
          .openRead(0, ClineRemoteProfile.maximumJsonBytes + 1)
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (buffer, chunk) => buffer..add(chunk),
          );
      if (bytes.length > ClineRemoteProfile.maximumJsonBytes) {
        throw const FormatException('Connection document is too large');
      }
      final source = utf8.decode(bytes.takeBytes());
      final profile = ClineRemoteProfile.decode(source);
      if (mounted) _fill(profile);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.clineInvalidProfile,
        );
      }
    }
  }

  Future<void> _connect() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    ClineSshTunnel? tunnel;
    ClineNativeClient? native;
    var adopted = false;
    try {
      final profile = ClineRemoteProfile.decode(
        jsonEncode({
          'schema': 1,
          'host': _host.text.trim(),
          'sshPort': int.parse(_port.text.trim()),
          'username': 'cline',
          'sshPassword': _password.text,
          'hostKeyFingerprint': _fingerprint.text.trim(),
          'roomSecret': _room.text,
          'dashboardPort': _dashboardPort,
          'projectPath': _project.text.trim(),
        }),
      );
      tunnel = await ClineSshTunnel.connect(profile, localPort: 0);
      native = await ClineNativeClient.connect(tunnel);
      // Successful pin verification precedes storing a connection.
      await _storage.write(
        key: clineProfileStorageKey,
        value: jsonEncode(profile.toJson()),
      );
      if (!mounted) return;
      await ref
          .read(preferredBackendProvider.notifier)
          .set(PreferredBackend.cline);
      if (!mounted) return;
      ref.read(clineBackendClientProvider.notifier).adopt(native);
      adopted = true;
      context.go(Routes.clineWorkspace);
    } on ClineConnectionException catch (failure) {
      if (mounted) {
        setState(
          () => _error = switch (failure.failure) {
            ClineConnectionFailure.hostKey => l10n.clineHostKeyMismatch,
            ClineConnectionFailure.authentication =>
              l10n.clineAuthenticationFailed,
            ClineConnectionFailure.localPort => l10n.clineLocalPortBusy,
            ClineConnectionFailure.network => l10n.clineNetworkError,
          },
        );
      }
    } on ClineNativeException {
      if (mounted) setState(() => _error = l10n.clineNativeConnectFailed);
    } on FormatException {
      if (mounted) setState(() => _error = l10n.clineInvalidProfile);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.clineStorageError);
    } finally {
      if (!adopted) {
        await native?.close();
        await tunnel?.close();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null) {
        throw const FormatException('No connection document');
      }
      final profile = ClineRemoteProfile.decode(data!.text!);
      if (mounted) _fill(profile);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.clineInvalidProfile,
        );
      }
    }
  }

  Future<void> _forget() async {
    try {
      await _storage.delete(key: clineProfileStorageKey);
      ref.read(clineBackendClientProvider.notifier).disconnect();
      if (ref.read(preferredBackendProvider) == PreferredBackend.cline) {
        await ref
            .read(preferredBackendProvider.notifier)
            .set(PreferredBackend.unset);
      }
      for (final controller in [
        _host,
        _password,
        _fingerprint,
        _room,
        _project,
      ]) {
        controller.clear();
      }
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.clineStorageError,
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _host,
      _port,
      _password,
      _fingerprint,
      _room,
      _project,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      obscureText: secret,
      enabled: !_busy,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(clineBackendClientProvider);
    final otherBusy =
        ref.watch(clineBackendStateProvider).value?.busy ??
        current?.state.busy ??
        false;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.clineRemoteTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(l10n.clineRemoteDescription),
          if (current?.state.connected == true)
            TextButton(
              onPressed: () => context.go(Routes.clineWorkspace),
              child: Text(l10n.clineReturnToChat),
            ),
          if (otherBusy) Text(l10n.clineWaitForTurn),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(l10n.clineImportConnection),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _busy ? null : _paste,
            icon: const Icon(Icons.content_paste),
            label: Text(l10n.clinePasteConnection),
          ),
          _field(_host, l10n.clineHost),
          _field(_port, l10n.clineSshPort),
          _field(_password, l10n.clineAccessSecret, secret: true),
          _field(_fingerprint, l10n.clineHostKey),
          _field(_room, l10n.clineDashboardSecret, secret: true),
          _field(_project, l10n.clineProjectPath),
          Text(l10n.clineProjectHint),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: _busy || otherBusy ? null : _connect,
            child: Text(_busy ? l10n.connecting : l10n.clineConnect),
          ),
          TextButton(
            onPressed: _busy || otherBusy ? null : _forget,
            child: Text(l10n.clineForgetConnection),
          ),
        ],
      ),
    );
  }
}
