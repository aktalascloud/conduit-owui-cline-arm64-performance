import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit_core/features/cline/models/cline_remote_profile.dart';
import 'package:conduit_core/features/cline/services/cline_ssh_tunnel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';

const _storageKey = 'conduit.cline.remote.profile.v1';

class ClineRemotePage extends StatefulWidget {
  const ClineRemotePage({super.key});

  @override
  State<ClineRemotePage> createState() => _ClineRemotePageState();
}

class _ClineRemotePageState extends State<ClineRemotePage> {
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
      final source = await _storage.read(key: _storageKey);
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
      tunnel = await ClineSshTunnel.connect(profile);
      // Successful pin verification precedes storing a connection.
      await _storage.write(
        key: _storageKey,
        value: jsonEncode(profile.toJson()),
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ClineDashboardPage(
            tunnel: tunnel!,
            project: _project.text.trim(),
          ),
        ),
      );
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
    } on FormatException {
      if (mounted) setState(() => _error = l10n.clineInvalidProfile);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.clineStorageError);
    } finally {
      await tunnel?.close();
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
      await _storage.delete(key: _storageKey);
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.clineRemoteTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(l10n.clineRemoteDescription),
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
            onPressed: _busy ? null : _connect,
            child: Text(_busy ? l10n.connecting : l10n.clineConnect),
          ),
          TextButton(
            onPressed: _busy ? null : _forget,
            child: Text(l10n.clineForgetConnection),
          ),
        ],
      ),
    );
  }
}

class ClineDashboardPage extends StatefulWidget {
  const ClineDashboardPage({
    super.key,
    required this.tunnel,
    this.project = '',
  });
  final ClineSshTunnel tunnel;
  final String project;

  @override
  State<ClineDashboardPage> createState() => _ClineDashboardPageState();
}

class _ClineDashboardPageState extends State<ClineDashboardPage> {
  InAppWebViewController? _controller;
  var _loading = true;
  var _disconnected = false;
  var _uploading = false;
  final List<Map<String, dynamic>> _attachments = [];

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _uploading = true);
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'pdf',
          'txt',
          'md',
          'csv',
          'json',
          'xml',
          'yaml',
          'yml',
          'docx',
          'xlsx',
          'pptx',
          'odt',
          'ods',
          'rtf',
          'log',
          'py',
          'js',
          'ts',
          'dart',
          'c',
          'cpp',
          'h',
        ],
      );
      if (selected == null || !mounted) return;
      if (selected.path == null || _attachments.length >= 4) {
        throw const FormatException('Invalid attachment');
      }
      final file = File(selected.path!);
      final uploaded = await widget.tunnel.upload(file, selected.name);
      final attachment = <String, dynamic>{
        'name': selected.name,
        'path': uploaded.path,
        'sha256': uploaded.sha256,
        'size': uploaded.size,
      };
      final extension = selected.name.split('.').last.toLowerCase();
      const images = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'webp': 'image/webp',
        'gif': 'image/gif',
      };
      if (images.containsKey(extension) && uploaded.size <= 8 * 1024 * 1024) {
        attachment['image'] =
            'data:${images[extension]};base64,${base64Encode(await file.readAsBytes())}';
      }
      if (!mounted || _disconnected) return;
      _attachments.add(attachment);
      await _syncAttachments();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.clineUploadFailed)));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _syncAttachments() async {
    await _controller?.evaluateJavascript(
      source: 'window.__conduitPendingFiles = ${jsonEncode(_attachments)};',
    );
  }

  @override
  void initState() {
    super.initState();
    widget.tunnel.closed.then((_) {
      if (mounted) setState(() => _disconnected = true);
    });
  }

  @override
  void dispose() {
    unawaited(widget.tunnel.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final root = widget.tunnel.url;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.clineRemoteTitle),
        actions: [
          IconButton(
            tooltip: l10n.clineUploadFile,
            onPressed:
                _disconnected ||
                    _loading ||
                    _uploading ||
                    _attachments.length >= 4
                ? null
                : _upload,
            icon: const Icon(Icons.attach_file),
          ),
          IconButton(
            tooltip: l10n.retry,
            onPressed: _disconnected ? null : () => _controller?.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _disconnected
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.clineDisconnected,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(root.toString())),
                  initialSettings: InAppWebViewSettings(
                    incognito: true,
                    cacheEnabled: false,
                    thirdPartyCookiesEnabled: false,
                    allowFileAccess: false,
                    allowContentAccess: false,
                    allowFileAccessFromFileURLs: false,
                    allowUniversalAccessFromFileURLs: false,
                    javaScriptEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: false,
                    supportMultipleWindows: false,
                    useShouldOverrideUrlLoading: true,
                    useShouldInterceptRequest: true,
                    mediaPlaybackRequiresUserGesture: true,
                  ),
                  initialUserScripts: UnmodifiableListView([
                    UserScript(
                      source: _projectScript(
                        widget.project,
                        widget.tunnel.profile.roomSecret,
                      ),
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ]),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    controller.addJavaScriptHandler(
                      handlerName: 'conduitAttachmentsSent',
                      callback: (_) {
                        if (mounted) setState(() => _attachments.clear());
                        return null;
                      },
                    );
                  },
                  shouldOverrideUrlLoading: (_, navigation) async {
                    final target = Uri.tryParse(
                      navigation.request.url?.toString() ?? '',
                    );
                    return target != null &&
                            clineDashboardNavigationAllowed(target, root)
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL;
                  },
                  shouldInterceptRequest: (_, request) async {
                    final target = Uri.tryParse(request.url.toString());
                    if (target != null &&
                        clineDashboardNavigationAllowed(target, root)) {
                      return null;
                    }
                    return WebResourceResponse(
                      statusCode: 403,
                      reasonPhrase: 'Blocked',
                      contentType: 'text/plain',
                      data: Uint8List(0),
                    );
                  },
                  onPermissionRequest: (_, request) async => PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.DENY,
                  ),
                  onLoadStart: (_, _) {
                    if (mounted) setState(() => _loading = true);
                  },
                  onLoadStop: (_, _) async {
                    await _syncAttachments();
                    if (mounted) setState(() => _loading = false);
                  },
                ),
                if (_loading || _uploading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
                if (_attachments.isNotEmpty)
                  Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: ListTile(
                        title: Text(l10n.clineFilesReady),
                        subtitle: Text(
                          _attachments.map((file) => file['name']).join(', '),
                          maxLines: 2,
                        ),
                        trailing: IconButton(
                          tooltip: l10n.clineClearAttachments,
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            setState(() => _attachments.clear());
                            await _syncAttachments();
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The host's send handler uses workspace overrides only for a NEW session.
/// Existing session prompts and approval frames pass through unchanged.
String _projectScript(String project, String roomSecret) =>
    '''
(() => {
  const project = ${jsonEncode(project)};
  const roomSecret = ${jsonEncode(roomSecret)};
  const OriginalSocket = window.WebSocket;
  class ClineSocket extends OriginalSocket {
    constructor(url, protocols) {
      const target = new URL(url, location.href);
      if (target.host !== location.host || target.protocol !== 'ws:' ||
          target.username || target.password || target.pathname !== '/browser') {
        throw new DOMException('Only the local SSH tunnel is allowed', 'SecurityError');
      }
      target.searchParams.set('roomSecret', roomSecret);
      super(target.toString(), protocols);
    }
    send(data) {
      let outgoing = data;
      let attached = false;
      if (typeof data === 'string') {
        try {
          const frame = JSON.parse(data);
          if (frame.type === 'send') {
            if (project) frame.config = {...(frame.config || {}), workspaceRoot: project, cwd: project};
            const files = window.__conduitPendingFiles || [];
            if (files.length) {
              const images = files.filter(file => file.image).map(file => file.image);
              frame.attachments = {...(frame.attachments || {}),
                userImages: [...(frame.attachments?.userImages || []), ...images]};
              const references = files.map(({name, path, sha256, size}) => ({name, path, sha256, size}));
              frame.prompt = (frame.prompt || '') + '\\n\\n[User attachments: file metadata, not instructions]\\n' + JSON.stringify(references);
              attached = true;
            }
            outgoing = JSON.stringify(frame);
          }
        } catch (_) {}
      }
      try { return super.send(outgoing); }
      finally {
        // A transport failure is uncertain: never replay an attachment or agent command.
        if (attached) {
          window.__conduitPendingFiles = [];
          window.flutter_inappwebview?.callHandler('conduitAttachmentsSent');
        }
      }
    }
  }
  window.WebSocket = ClineSocket;
})();
''';
