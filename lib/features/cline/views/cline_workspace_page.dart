import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/features/cline/models/cline_native_models.dart';
import 'package:conduit_core/features/cline/models/cline_remote_profile.dart';
import 'package:conduit_core/features/cline/providers/cline_backend_providers.dart';
import 'package:conduit_core/features/cline/services/cline_native_client.dart';
import 'package:conduit_core/features/cline/services/cline_ssh_tunnel.dart';
import 'package:conduit_core/features/cline/services/cline_attachment_upload.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/services/navigation_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/theme/color_tokens.dart' show withMinContrast;

import 'package:conduit_core/providers/app_providers.dart'
    show openWebUiAccountAvailableProvider;
import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';
import 'package:conduit_core/features/navigation/providers/sidebar_active_tab_provider.dart';

import '../../../shared/widgets/markdown/streaming_markdown_widget.dart';
import 'cline_remote_page.dart';

/// Native Conduit chat, sessions and projects over the typed Cline transport.
class ClineWorkspacePage extends ConsumerStatefulWidget {
  const ClineWorkspacePage({
    super.key,
    this.embedded = false,
    this.active = true,
  });
  final bool embedded;
  final bool active;
  @override
  ConsumerState<ClineWorkspacePage> createState() => _ClineWorkspacePageState();
}

/// Ephemeral UI memory, scoped to this app/provider container; never sent to OWUI.
class ClineWorkspaceMemory {
  final drafts = <String, String>{};
  final files = <String, List<ClineAttachment>>{};
  final offsets = <String, double>{};
}

final clineWorkspaceMemoryProvider = Provider((ref) => ClineWorkspaceMemory());

class _ClineWorkspacePageState extends ConsumerState<ClineWorkspacePage> {
  final _storage = const FlutterSecureStorage();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();
  late final ClineWorkspaceMemory _memory;
  late final Map<String, String> _drafts;
  late final Map<String, List<ClineAttachment>> _files;
  String _draftKey = '';
  String? _connectError;
  bool _connecting = false, _uploading = false;
  int _generation = 0;
  String? _lastScope;
  bool _followOutput = true;
  int? _lastRender;

  @override
  void initState() {
    super.initState();
    _memory = ref.read(clineWorkspaceMemoryProvider);
    _drafts = _memory.drafts;
    _files = _memory.files;
    _scroll.addListener(() {
      if (_scroll.hasClients && _draftKey.isNotEmpty) {
        _memory.offsets[_draftKey] = _scroll.offset;
      }
      if (_scroll.hasClients &&
          _scroll.position.userScrollDirection != ScrollDirection.idle)
        _followOutput = _scroll.position.extentAfter < 120;
    });
    if (widget.active) unawaited(_ensureConnected());
  }

  @override
  void didUpdateWidget(ClineWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_connecting) {
      unawaited(_ensureConnected());
    }
  }

  void _settings() => context.push(
    widget.embedded ? '${Routes.clineRemote}?embedded=1' : Routes.clineRemote,
  );

  Future<void> _openOwui() async {
    ref.read(sidebarActiveTabProvider.notifier).set(SidebarTabId.chats);
    await ref
        .read(preferredBackendProvider.notifier)
        .set(PreferredBackend.owui);
    if (mounted) context.go(Routes.chat);
  }

  @override
  void dispose() {
    _generation++;
    if (_draftKey.isNotEmpty) _drafts[_draftKey] = _input.text;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _key(ClineNativeClient client, ClineNativeState s) =>
      client.identity + ':' + (s.sessionId ?? 'new:' + s.project);
  void _bindDraft(ClineNativeClient client, ClineNativeState s) {
    final key = _key(client, s);
    if (_draftKey == key) return;
    if (_draftKey.isNotEmpty) _drafts[_draftKey] = _input.text;
    if (s.sessionId == client.createdSessionId &&
        _draftKey ==
            client.identity + ':new:' + (client.createdProject ?? '')) {
      _drafts[key] ??= _drafts[_draftKey] ?? '';
      if (_files[_draftKey]?.isNotEmpty ?? false)
        _files.putIfAbsent(key, () => []).addAll(_files.remove(_draftKey)!);
    }
    _draftKey = key;
    _input.text = _drafts[key] ?? '';
  }

  Future<void> _ensureConnected({bool reconnect = false}) async {
    final epoch = ++_generation;
    if (!reconnect && ref.read(clineBackendClientProvider) != null) return;
    final old = ref.read(clineBackendClientProvider);
    final restore = old?.state.sessionId;
    final uncertain = old?.state.uncertainPrompt;
    if (reconnect) {
      ref.read(clineBackendClientProvider.notifier).disconnect();
      await old?.close();
    }
    if (mounted)
      setState(() {
        _connecting = true;
        _connectError = null;
      });
    ClineSshTunnel? tunnel;
    ClineNativeClient? native;
    try {
      final source = await _storage.read(key: clineProfileStorageKey);
      if (source == null) {
        if (mounted && !widget.embedded) context.go(Routes.clineRemote);
        return;
      }
      final profile = ClineRemoteProfile.decode(source);
      String? last;
      try {
        last = await _storage.read(
          key: 'conduit.cline.last-session.' + profile.hostKeyFingerprint,
        );
      } catch (_) {
        // Restoring history is optional; a storage error must not close a live client.
      }
      tunnel = await ClineSshTunnel.connect(profile, localPort: 0);
      native = await ClineNativeClient.connect(tunnel);
      if (!mounted ||
          epoch != _generation ||
          (!widget.embedded &&
              ref.read(preferredBackendProvider) != PreferredBackend.cline)) {
        await native.close();
        return;
      }
      native.retainUncertainPrompt(uncertain);
      ref.read(clineBackendClientProvider.notifier).adopt(native);
      if (restore != null && native.state.sessions.any((s) => s.id == restore))
        native.openSession(restore);
      else {
        if (mounted &&
            last != null &&
            native.state.sessions.any((s) => s.id == last))
          native.openSession(last);
      }
      native = null;
      tunnel = null;
    } catch (_) {
      await native?.close();
      await tunnel?.close();
      if (mounted)
        setState(
          () =>
              _connectError = AppLocalizations.of(context)!
                  .clineNativeConnectFailed,
        );
    } finally {
      if (mounted && epoch == _generation) setState(() => _connecting = false);
    }
  }

  void _notice(Object error) {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    final code = error is ClineNativeException ? error.code : '';
    final text = switch (code) {
      'busy' => l.clineWaitForTurn,
      'existingContext' => l.clineExistingContext,
      'payload' => l.clinePayloadLimit,
      'fileChanged' => l.clineFileChanged,
      _ => l.clineNetworkError,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(ClineNativeClient client, String id) async {
    try {
      client.openSession(id);
      final profileText = await _storage.read(key: clineProfileStorageKey);
      if (profileText != null) {
        final p = ClineRemoteProfile.decode(profileText);
        await _storage.write(
          key: 'conduit.cline.last-session.' + p.hostKeyFingerprint,
          value: id,
        );
      }
    } catch (e) {
      _notice(e);
    }
  }

  void _newChat(ClineNativeClient client, {String? project}) {
    try {
      client.newChat(project: project);
    } catch (e) {
      _notice(e);
    }
  }

  Future<void> _project(ClineNativeClient client, ClineNativeState s) async {
    final l = AppLocalizations.of(context)!;
    final input = TextEditingController(text: s.project);
    final path = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.clineProjects),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final project in s.projects)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(project, maxLines: 2),
                    onTap: () => Navigator.pop(dialog, project),
                  ),
                TextField(
                  controller: input,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l.clineProjectPath),
                ),
                const SizedBox(height: 8),
                Text(l.clineProjectHint),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, input.text.trim()),
            child: Text(l.clineUseProject),
          ),
        ],
      ),
    );
    input.dispose();
    if (path == null || !mounted) return;
    if (!(RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
            path.startsWith('/') ||
            path.startsWith(r'\\')) ||
        path.contains('\n') ||
        path.contains('\x00')) {
      _notice(const ClineNativeException('existingContext'));
      return;
    }
    _newChat(client, project: path);
  }

  Future<void> _models(ClineNativeClient client, ClineNativeState s) async {
    final l = AppLocalizations.of(context)!;
    if (s.sessionId != null) {
      _notice(const ClineNativeException('existingContext'));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .65,
          child: StreamBuilder<ClineNativeState>(
            stream: client.changes,
            initialData: client.state,
            builder: (context, value) {
              final state = value.data!;
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l.clineModels,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  for (final provider in state.providers)
                    ExpansionTile(
                      title: Text(provider.name),
                      initiallyExpanded: provider.id == state.provider,
                      onExpansionChanged: (open) {
                        if (open && !state.models.containsKey(provider.id)) {
                          try {
                            client.requestModels(provider.id);
                          } catch (e) {
                            _notice(e);
                          }
                        }
                      },
                      children: [
                        for (final model
                            in state.models[provider.id] ??
                                const <ClineModel>[])
                          ListTile(
                            title: Text(
                              model.name.isEmpty ? model.id : model.name,
                            ),
                            subtitle: Text(model.id),
                            leading: Icon(
                              state.provider == provider.id &&
                                      state.model == model.id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            onTap: () {
                              try {
                                client.configure(
                                  provider: provider.id,
                                  model: model.id,
                                );
                                Navigator.pop(sheet);
                              } catch (e) {
                                _notice(e);
                              }
                            },
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _upload(ClineNativeClient client, ClineNativeState state) async {
    final owner = _key(client, state);
    final l = AppLocalizations.of(context)!;
    if ((_files[owner]?.length ?? 0) >= 4) return;
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
      if (selected == null) return;
      if (selected.path == null) throw const FormatException('No local file');
      final attachment = await uploadClineAttachment(
        client,
        File(selected.path!),
        selected.name,
      );
      if (!mounted) return;
      _files.putIfAbsent(owner, () => []).add(attachment);
      setState(() {});
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.clineUploadFailed)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _modeChip(
    ClineNativeClient client,
    ClineNativeState state,
    String mode,
  ) {
    final palette = context.conduitTheme;
    final selected = state.mode == mode;
    final fill = selected
        ? Color.alphaBlend(
            palette.textPrimary.withValues(alpha: 0.08),
            palette.cardBackground,
          )
        : palette.cardBackground;
    final foreground = withMinContrast(palette.textPrimary, fill, 4.5);
    final l = AppLocalizations.of(context)!;
    return ChoiceChip(
      key: ValueKey('cline-mode-' + mode),
      label: Text(mode == 'plan' ? l.clinePlan : l.clineAct),
      avatar: Icon(
        mode == 'plan' ? Icons.account_tree_outlined : Icons.bolt_outlined,
        size: 16,
        color: foreground,
      ),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: foreground,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      backgroundColor: fill,
      selectedColor: fill,
      checkmarkColor: foreground,
      showCheckmark: false,
      side: BorderSide(
        color: selected
            ? palette.textPrimary.withValues(alpha: 0.35)
            : palette.cardBorder,
      ),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      selected: selected,
      onSelected: state.busy
          ? null
          : (_) {
              try {
                client.configure(mode: mode);
              } catch (error) {
                _notice(error);
              }
            },
    );
  }

  void _send(ClineNativeClient client, ClineNativeState state) {
    final files = _files[_draftKey] ?? [];
    if (_input.text.trim().isEmpty && files.isEmpty) return;
    try {
      client.sendMessage(_input.text, attachments: files);
      _drafts[_draftKey] = '';
      _input.clear();
      _files[_draftKey] = [];
      setState(() {});
      _jumpToEnd();
    } catch (e) {
      _notice(e);
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients)
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
    });
  }

  Future<void> _disconnect(ClineNativeState? state) async {
    final l = AppLocalizations.of(context)!;
    if (state?.busy == true) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(l.clineDisconnect),
          content: Text(l.clineDisconnectWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(l.clineDisconnect),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    ref.read(clineBackendClientProvider.notifier).disconnect();
    if (widget.embedded) return;
    await ref
        .read(preferredBackendProvider.notifier)
        .set(PreferredBackend.unset);
    if (mounted) context.go(Routes.backendChooser);
  }

  Future<void> _sessionMenu(
    ClineNativeClient client,
    ClineSession session,
    String action,
  ) async {
    final l = AppLocalizations.of(context)!;
    try {
      if (action == 'rename') {
        final field = TextEditingController(text: session.title);
        final title = await showDialog<String>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(l.clineRename),
            content: TextField(
              controller: field,
              maxLength: 200,
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, field.text),
                child: Text(l.clineRename),
              ),
            ],
          ),
        );
        field.dispose();
        if (title != null) client.renameSession(session.id, title);
      } else if (action == 'delete') {
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(l.clineDeleteSession),
            content: Text(l.clineDeleteWarning),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(l.clineDeleteSession),
              ),
            ],
          ),
        );
        if (yes == true) client.deleteSession(session.id);
      }
    } catch (error) {
      _notice(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.conduitTheme;
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final foreground = withMinContrast(
      palette.textPrimary,
      palette.cardBackground,
      4.5,
    );
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: palette.surfaceBackground,
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: palette.surfaceBackground,
          foregroundColor: palette.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            backgroundColor: palette.cardBackground,
            side: BorderSide(color: palette.cardBorder),
            shape: shape,
            minimumSize: const Size(48, 44),
          ),
        ),
        cardTheme: theme.cardTheme.copyWith(
          color: palette.cardBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: palette.cardBorder),
          ),
        ),
      ),
      child: Builder(builder: _buildWorkspace),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final client = ref.watch(clineBackendClientProvider);
    if (client == null)
      return Scaffold(
        appBar: AppBar(title: const Text('Cline')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_connecting) const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  _connectError ??
                      (_connecting ? l.connecting : l.clineConnectionSettings),
                  textAlign: TextAlign.center,
                ),
                if (!_connecting)
                  FilledButton(
                    onPressed: () => _ensureConnected(reconnect: true),
                    child: Text(l.retry),
                  ),
                TextButton(
                  onPressed: _settings,
                  child: Text(l.clineConnectionSettings),
                ),
                if (!widget.embedded)
                  TextButton(
                    onPressed: () => _disconnect(null),
                    child: Text(l.clineOtherBackends),
                  ),
              ],
            ),
          ),
        ),
      );
    return StreamBuilder<ClineNativeState>(
      stream: client.changes,
      initialData: client.state,
      builder: (context, event) {
        final state = event.data ?? client.state;
        _bindDraft(client, state);
        final selected = state.sessions
            .where((s) => s.id == state.sessionId)
            .firstOrNull;
        final title = selected?.title ?? l.clineNewChat;
        final last = state.messages.lastOrNull;
        final signature = Object.hash(
          state.messages.length,
          last?.id,
          last?.text.length,
          last?.reasoning.length,
          last == null
              ? 0
              : Object.hashAll(
                  last.tools.map((t) => Object.hash(t.status, t.output)),
                ),
        );
        if (_lastRender != signature) {
          _lastRender = signature;
          if (_followOutput && widget.active)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scroll.hasClients)
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
            });
        }

        if (_lastScope != state.sessionId) {
          _lastScope = state.sessionId;
          final offset = _memory.offsets[_draftKey];
          if (offset == null) {
            _jumpToEnd();
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scroll.hasClients) {
                _scroll.jumpTo(
                  offset.clamp(0, _scroll.position.maxScrollExtent),
                );
              }
            });
          }
        }
        return Scaffold(
          key: _scaffold,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: Text(
              title.isEmpty ? 'Cline' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (!widget.embedded &&
                  ref.watch(openWebUiAccountAvailableProvider))
                IconButton(
                  tooltip: 'Open WebUI',
                  onPressed: _openOwui,
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
              IconButton(
                tooltip: l.clineNewChat,
                onPressed: state.busy ? null : () => _newChat(client),
                icon: const Icon(Icons.edit_square),
              ),
              PopupMenuButton<String>(
                onSelected: (choice) {
                  if (choice == 'settings') _settings();
                  if (choice == 'accounts') context.push(Routes.accounts);
                  if (choice == 'disconnect') unawaited(_disconnect(state));
                  if (choice == 'fork') {
                    try {
                      client.forkSession();
                    } catch (e) {
                      _notice(e);
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (state.sessionId != null && !state.busy)
                    PopupMenuItem(
                      value: 'fork',
                      child: Text(l.clineForkSession),
                    ),
                  PopupMenuItem(
                    value: 'accounts',
                    child: Text(l.clineOtherBackends),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Text(l.clineConnectionSettings),
                  ),
                  PopupMenuItem(
                    value: 'disconnect',
                    child: Text(l.clineDisconnect),
                  ),
                ],
              ),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      l.clineSessions,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(l.clineNewChat),
                    onTap: state.busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            _newChat(client);
                          },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(l.clineProjects),
                    subtitle: Text(state.project, maxLines: 2),
                    onTap: state.busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            unawaited(_project(client, state));
                          },
                  ),
                  const Divider(),
                  Expanded(
                    child: state.sessions.isEmpty
                        ? Center(child: Text(l.clineNoSessions))
                        : ListView.builder(
                            itemCount: state.sessions.length,
                            itemBuilder: (context, index) {
                              final session = state.sessions[index];
                              return ListTile(
                                key: ValueKey('cline-session-' + session.id),
                                selected: session.id == state.sessionId,
                                leading: const Icon(Icons.chat_bubble_outline),
                                title: Text(
                                  session.title.isEmpty
                                      ? l.clineNewChat
                                      : session.title,
                                  maxLines: 2,
                                ),
                                subtitle: Text(
                                  session.project,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing:
                                    {
                                      'running',
                                      'starting',
                                    }.contains(session.status)
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : PopupMenuButton<String>(
                                        onSelected: (value) => _sessionMenu(
                                          client,
                                          session,
                                          value,
                                        ),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'rename',
                                            child: Text(l.clineRename),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(l.clineDeleteSession),
                                          ),
                                        ],
                                      ),
                                onTap: state.busy
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        unawaited(_open(client, session.id));
                                      },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          body: LayoutBuilder(
            builder: (context, viewport) => Column(
              children: [
                if (!state.connected ||
                    state.error != null ||
                    state.uncertainPrompt != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: viewport.maxHeight * .24,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (!state.connected)
                            MaterialBanner(
                              content: Text(l.clineDisconnected),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      _ensureConnected(reconnect: true),
                                  child: Text(l.retry),
                                ),
                              ],
                            ),
                          if (state.error != null)
                            MaterialBanner(
                              content: Text(_errorText(l, state.error!)),
                              actions: [
                                TextButton(
                                  onPressed: client.clearError,
                                  child: Text(l.clineDismiss),
                                ),
                              ],
                            ),
                          if (state.uncertainPrompt != null)
                            MaterialBanner(
                              content: Text(l.clineUncertainResult),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    _input.text = state.uncertainPrompt!;
                                    client.clearUncertainPrompt();
                                  },
                                  child: Text(l.clineRestoreDraft),
                                ),
                                TextButton(
                                  onPressed: client.clearUncertainPrompt,
                                  child: Text(l.clineHistoryChecked),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (state.loadingHistory) const LinearProgressIndicator(),
                Expanded(
                  child: state.messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              l.clineNativeWelcome,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: state.messages.length,
                          itemBuilder: (context, index) => _ClineMessage(
                            message: state.messages[index],
                            model: state.model,
                          ),
                        ),
                ),
                if (state.approvals.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: viewport.maxHeight * .30,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final approval in state.approvals)
                            _approval(client, approval, l),
                        ],
                      ),
                    ),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: viewport.maxHeight * .45,
                  ),
                  child: SingleChildScrollView(
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    key: const Key('cline-project-picker'),
                                    onPressed: state.busy
                                        ? null
                                        : () => _project(client, state),
                                    icon: const Icon(
                                      Icons.folder_outlined,
                                      size: 17,
                                    ),
                                    label: Text(
                                      state.project,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: OutlinedButton.icon(
                                    key: const Key('cline-model-picker'),
                                    icon: const Icon(
                                      Icons.smart_toy_outlined,
                                      size: 17,
                                    ),
                                    onPressed: state.busy
                                        ? null
                                        : () => _models(client, state),
                                    label: Text(
                                      state.model.isEmpty
                                          ? l.clineModels
                                          : state.model,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (final mode in ['plan', 'act'])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: _modeChip(client, state, mode),
                                  ),
                                if (state.sessionId == null &&
                                    (state.models[state.provider]?.any(
                                          (m) =>
                                              m.id == state.model &&
                                              m.reasoning,
                                        ) ??
                                        false))
                                  DropdownButton<String>(
                                    value: state.reasoning,
                                    underline: const SizedBox.shrink(),
                                    onChanged: state.busy
                                        ? null
                                        : (value) {
                                            if (value != null)
                                              client.configure(
                                                reasoning: value,
                                              );
                                          },
                                    items: [
                                      for (final level in [
                                        'none',
                                        'low',
                                        'medium',
                                        'high',
                                      ])
                                        DropdownMenuItem(
                                          value: level,
                                          child: Text(_reasonLabel(l, level)),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                            if (state.status.isNotEmpty)
                              Text(
                                _clineStatus(l, state.status),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (state.mode.isEmpty)
                              Text(
                                l.clineChooseMode,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if ((_files[_draftKey]?.isNotEmpty ?? false))
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 6,
                                  children: [
                                    for (final file in _files[_draftKey]!)
                                      InputChip(
                                        label: Text(file.name),
                                        avatar: Icon(
                                          file.imageDataUrl != null
                                              ? Icons.image_outlined
                                              : Icons.description_outlined,
                                          size: 18,
                                        ),
                                        onDeleted: () {
                                          setState(
                                            () =>
                                                _files[_draftKey]!.remove(file),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            if (_uploading) const LinearProgressIndicator(),
                            Container(
                              decoration: BoxDecoration(
                                color: context.conduitTheme.inputBackground,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  IconButton(
                                    key: const Key('cline-native-attach'),
                                    tooltip: l.clineUploadFile,
                                    onPressed: !state.connected || _uploading
                                        ? null
                                        : () => _upload(client, state),
                                    icon: const Icon(Icons.add),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      key: const Key('cline-native-input'),
                                      controller: _input,
                                      minLines: 1,
                                      maxLines: 6,
                                      enabled: state.connected,
                                      style: AppTypography.chatMessageStyle,
                                      decoration: InputDecoration(
                                        hintText: l.clineMessageHint,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        filled: false,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 6,
                                            ),
                                      ),
                                      onChanged: (_) => setState(() {
                                        _drafts[_draftKey] = _input.text;
                                      }),
                                    ),
                                  ),
                                  if (state.busy)
                                    IconButton.filled(
                                      key: const Key('cline-native-stop'),
                                      tooltip: l.clineStop,
                                      onPressed: () {
                                        try {
                                          client.abort();
                                        } catch (e) {
                                          _notice(e);
                                        }
                                      },
                                      icon: const Icon(Icons.stop),
                                    )
                                  else
                                    IconButton.filled(
                                      key: const Key('cline-native-send'),
                                      tooltip: l.clineSend,
                                      onPressed:
                                          state.canSend &&
                                              !_uploading &&
                                              (_input.text.trim().isNotEmpty ||
                                                  (_files[_draftKey]
                                                          ?.isNotEmpty ??
                                                      false))
                                          ? () => _send(client, state)
                                          : null,
                                      icon: const Icon(Icons.arrow_upward),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _approval(
    ClineNativeClient client,
    ClineApproval approval,
    AppLocalizations l,
  ) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.clineApprovalRequired,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(approval.toolName),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 110),
            child: SingleChildScrollView(
              child: SelectableText(_preview(approval.input)),
            ),
          ),
          TextButton(
            onPressed: () =>
                _showClineDetails(context, approval.toolName, approval.input),
            child: Text(l.clineInspect),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              OutlinedButton(
                key: ValueKey('cline-deny-' + approval.id),
                onPressed: approval.responding
                    ? null
                    : () {
                        try {
                          client.approve(approval.id, false);
                        } catch (e) {
                          _notice(e);
                        }
                      },
                child: Text(l.clineDeny),
              ),
              FilledButton(
                key: ValueKey('cline-allow-' + approval.id),
                onPressed: approval.responding
                    ? null
                    : () {
                        try {
                          client.approve(approval.id, true);
                        } catch (e) {
                          _notice(e);
                        }
                      },
                child: Text(l.clineAllowOnce),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _preview(Object? value) {
  final text = value is String
      ? value
      : const JsonEncoder.withIndent('  ').convert(value);
  return text.length > 16000 ? text.substring(0, 16000) + '\n…' : text;
}

String _errorText(AppLocalizations l, String value) => switch (value) {
  'offline' || 'connection' => l.clineNetworkError,
  'payload' => l.clinePayloadLimit,
  'protocol' => l.clineProtocolError,
  _ => value,
};
String _reasonLabel(AppLocalizations l, String value) => switch (value) {
  'none' => l.clineReasonNone,
  'low' => l.clineReasonLow,
  'high' => l.clineReasonHigh,
  _ => l.clineReasonMedium,
};
String _clineStatus(AppLocalizations l, String value) => switch (value) {
  'running' || 'starting' => l.clineToolRunning,
  'stop' || 'completed' || 'Cline Hub is ready.' => l.clineToolCompleted,
  'failed' || 'error' => l.clineToolFailed,
  _ => value,
};

Future<void> _openClineLink(BuildContext context, String text) async {
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty) {
    await Clipboard.setData(ClipboardData(text: text));
    return;
  }
  final l = AppLocalizations.of(context)!;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.clineExternalLink),
      content: SelectableText(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(l.clineOpenLink),
        ),
      ],
    ),
  );
  if (accepted == true)
    await launchUrl(uri, mode: LaunchMode.externalApplication);
}

void _showClineDetails(BuildContext context, String title, Object? value) {
  final text = value is String
      ? value
      : const JsonEncoder.withIndent('  ').convert(value);
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _ClineDetailsPage(title: title, text: text),
    ),
  );
}

class _ClineDetailsPage extends StatelessWidget {
  _ClineDetailsPage({required this.title, required this.text})
    : lines = _lines(text);
  final String title, text;
  final List<String> lines;
  static List<String> _lines(String text) {
    final result = <String>[];
    for (final line in text.split('\n')) {
      if (line.isEmpty) {
        result.add('');
        continue;
      }
      var start = 0;
      while (start < line.length) {
        var end = (start + 4000).clamp(0, line.length);
        if (end < line.length &&
            line.codeUnitAt(end - 1) >= 0xd800 &&
            line.codeUnitAt(end - 1) <= 0xdbff)
          end--;
        result.add(line.substring(start, end));
        start = end;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        IconButton(
          tooltip: AppLocalizations.of(context)!.clineCopy,
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
          icon: const Icon(Icons.copy),
        ),
      ],
    ),
    body: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      itemBuilder: (_, i) => SelectableText(
        lines[i],
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    ),
  );
}

class _ClineMessage extends StatelessWidget {
  const _ClineMessage({required this.message, required this.model});
  final ClineChatMessage message;
  final String model;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final user = message.role == 'user';
    final parts = message.parts.isNotEmpty
        ? message.parts
        : [
            if (message.reasoning.isNotEmpty || message.redacted)
              ClineMessagePart(
                type: 'reasoning',
                text: message.reasoning,
                redacted: message.redacted,
              ),
            if (message.text.isNotEmpty)
              ClineMessagePart(type: 'text', text: message.text),
            for (final tool in message.tools)
              ClineMessagePart(type: 'tool', tool: tool),
            for (final media in message.media)
              ClineMessagePart(type: 'media', media: media),
          ];
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('cline-message-' + message.id),
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 900),
        decoration: user
            ? BoxDecoration(
                color: context.conduitTheme.inputBackground,
                borderRadius: BorderRadius.circular(18),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!user)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  model.isEmpty ? 'Cline' : model,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            for (var i = 0; i < parts.length; i++)
              _part(context, l, parts[i], i),
            if (message.streaming)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (message.usage.isNotEmpty)
              Text(
                [
                  if (message.usage['inputTokens'] != null)
                    '↑ ' + message.usage['inputTokens'].toString(),
                  if (message.usage['outputTokens'] != null)
                    '↓ ' + message.usage['outputTokens'].toString(),
                ].join('  '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: l.clineCopy,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: message.text)),
                icon: const Icon(Icons.copy_outlined, size: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _part(
    BuildContext context,
    AppLocalizations l,
    ClineMessagePart part,
    int index,
  ) {
    if (part.type == 'reasoning')
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(l.clineReasoning),
        children: [
          if (part.redacted)
            Text(l.clineReasoningHidden)
          else
            _markdown(context, part.text, index),
        ],
      );
    if (part.type == 'tool' && part.tool != null) {
      final tool = part.tool!;
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: Icon(
          tool.status == 'running'
              ? Icons.pending_outlined
              : tool.status == 'failed'
              ? Icons.error_outline
              : Icons.check_circle_outline,
        ),
        title: Text(tool.name),
        subtitle: Text(
          tool.status == 'running'
              ? l.clineToolRunning
              : tool.status == 'failed'
              ? l.clineToolFailed
              : l.clineToolCompleted,
        ),
        children: [
          if (tool.input != null) SelectableText(_preview(tool.input)),
          if (tool.output != null) SelectableText(_preview(tool.output)),
          if (tool.error != null) SelectableText(tool.error!),
          TextButton(
            onPressed: () => _showClineDetails(context, tool.name, {
              'input': tool.input,
              'output': tool.output,
              'error': tool.error,
            }),
            child: Text(l.clineInspect),
          ),
        ],
      );
    }
    if (part.type == 'media' && part.media != null)
      return _media(context, l, part.media!);
    return _markdown(context, part.text, index);
  }

  Widget _markdown(BuildContext context, String text, int index) =>
      StreamingMarkdownWidget(
        key: ValueKey(message.id + '-part-' + index.toString()),
        content: text,
        isStreaming: message.streaming,
        stateScopeId: 'cline-' + message.id + '-' + index.toString(),
        enableStreamingTextFade: false,
        onTapLink: (url, title) => _openClineLink(context, url),
        imageBuilderOverride: (uri, title, alt) =>
            _safeImage(uri.toString(), alt),
      );
  Widget _safeImage(String url, String? alt) {
    final match = RegExp(
      r'^data:image/(?:png|jpeg|webp|gif);base64,([A-Za-z0-9+/=]+)$',
    ).firstMatch(url);
    if (match != null && url.length <= 8 * 1024 * 1024) {
      try {
        return Image.memory(
          base64Decode(match.group(1)!),
          fit: BoxFit.contain,
          cacheWidth: 1280,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        );
      } catch (_) {}
    }
    return Text(alt ?? url, maxLines: 3, overflow: TextOverflow.ellipsis);
  }

  Widget _media(
    BuildContext context,
    AppLocalizations l,
    Map<String, dynamic> media,
  ) {
    final url = clineString(media['url'] ?? media['dataUrl']);
    if (url.startsWith('data:image/'))
      return _safeImage(url, clineString(media['name']));
    final name = clineString(
      media['name'] ?? media['filename'],
      l.clineAttachment,
    );
    return ActionChip(
      avatar: const Icon(Icons.description_outlined, size: 18),
      label: Text(name),
      onPressed: () => Clipboard.setData(
        ClipboardData(text: clineString(media['path'] ?? media['url'])),
      ),
    );
  }
}
