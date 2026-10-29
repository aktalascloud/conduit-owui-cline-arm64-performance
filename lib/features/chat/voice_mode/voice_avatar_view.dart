import 'dart:async';
import 'dart:convert';

import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'chat_voice_mode_controller.dart';
import 'voice_avatar_policy.dart';

/// A local graphics viewport only. Chat, audio, permissions and API auth remain
/// native. The isolated document receives model bytes and numeric signals only.
class VoiceAvatarView extends ConsumerWidget {
  const VoiceAvatarView({super.key, required this.snapshot});
  final ChatVoiceModeSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = voiceAvatarFileId(ref.watch(selectedModelProvider));
    if (id == null) return const SizedBox.shrink();
    final api = ref.watch(apiServiceProvider);
    if (api == null) return const SizedBox.shrink();
    return _AvatarViewport(
      key: ValueKey((api, id)),
      api: api,
      fileId: id,
      snapshot: snapshot,
    );
  }
}

class _AvatarViewport extends StatefulWidget {
  const _AvatarViewport({
    super.key,
    required this.api,
    required this.fileId,
    required this.snapshot,
  });
  final ApiService api;
  final String fileId;
  final ChatVoiceModeSnapshot snapshot;

  @override
  State<_AvatarViewport> createState() => _AvatarViewportState();
}

class _AvatarViewportState extends State<_AvatarViewport>
    with WidgetsBindingObserver {
  final _cancel = CancelToken();
  late final Future<String> _html;
  InAppWebViewController? _controller;
  bool _loaded = false, _failed = false, _initializing = false;
  bool _foreground = true;
  bool _initialDocument = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _html = rootBundle.loadString('assets/voice_avatar/viewer.html');
  }

  @override
  void didUpdateWidget(covariant _AvatarViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_sync());
  }

  Future<void> _sync() async {
    if (!_loaded || !mounted) return;
    final s = widget.snapshot;
    final signals = voiceAvatarSignals(
      speaking: s.phase == ChatVoiceModePhase.speaking,
      intensity: s.intensity,
      active: _foreground && s.isActive && !s.isCollapsed,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    try {
      await _controller?.evaluateJavascript(
        source: 'window.conduitAvatar?.signal(${jsonEncode(signals)});',
      );
    } catch (_) {
      /* A disposed platform view has no live graphics state. */
    }
  }

  Future<void> _load(InAppWebViewController controller) async {
    if (_initializing || _loaded || !mounted) return;
    _initializing = true;
    try {
      final data = await widget.api.getFileContent(
        widget.fileId,
        maxBytes: voiceAvatarMaxBytes,
        authSnapshot: widget.api.captureAuthSnapshot(),
        cancelToken: _cancel,
      );
      if (!mounted) return;
      // Never send the API client, token, cookies or resource URLs to JS.
      if (data.length > ((voiceAvatarMaxBytes + 2) ~/ 3) * 4 ||
          !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(data)) {
        throw const FormatException('Invalid avatar data');
      }
      for (var start = 0; start < data.length; start += 131072) {
        if (!mounted || _cancel.isCancelled) return;
        final end = (start + 131072).clamp(0, data.length);
        await controller.evaluateJavascript(
          source:
              'window.conduitAvatar.append(${jsonEncode(data.substring(start, end))});',
        );
      }
      // Android's asynchronous-result helper uses a Native Messaging bridge.
      // Keep that bridge disabled and read a bounded graphics-only result.
      await controller.evaluateJavascript(
        source: 'window.avatarLoadResult=null; void window.conduitAvatar.load().then(r=>window.avatarLoadResult=r);',
      );
      dynamic value;
      for (var attempt = 0; attempt < 200 && mounted; attempt++) {
        value = await controller.evaluateJavascript(
          source: 'window.avatarLoadResult',
        );
        if (value is String) {
          value = jsonDecode(value);
        }
        if (value is Map) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) return;
      if (value is! Map || value['ok'] != true) {
        throw const FormatException('Avatar renderer unavailable');
      }
      setState(() => _loaded = true);
      await _sync();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel.cancel('Avatar view closed');
    unawaited(
      _controller
          ?.evaluateJavascript(source: 'window.conduitAvatar?.dispose();')
          .then<void>((_) {}, onError: (Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          l10n.voiceAvatarUnavailable,
          style: TextStyle(color: context.conduitTheme.textSecondary),
        ),
      );
    }
    // Keep native call controls visible with a keyboard or a short viewport.
    final room =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final height = (room * .27).clamp(96.0, 230.0);
    return SizedBox(
      height: height,
      child: Semantics(
        label: l10n.voiceAvatar,
        image: true,
        child: FutureBuilder<String>(
          future: _html,
          builder: (context, html) {
            if (html.hasError) return Text(l10n.voiceAvatarUnavailable);
            if (!html.hasData) return const SizedBox.shrink();
            return IgnorePointer(
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: html.data!,
                  baseUrl: WebUri('$voiceAvatarOrigin/'),
                ),
                initialSettings: voiceAvatarWebViewSettings(),
                onWebViewCreated: (c) => _controller = c,
                onLoadStop: (c, _) {
                  _initialDocument = false;
                  unawaited(_load(c));
                },
                shouldOverrideUrlLoading: (_, action) async {
                  if (_initialDocument &&
                      action.isForMainFrame == true &&
                      action.request.url?.toString() == '$voiceAvatarOrigin/') {
                    _initialDocument = false;
                    return NavigationActionPolicy.ALLOW;
                  }
                  return NavigationActionPolicy.CANCEL;
                },
                shouldInterceptRequest: (_, request) async =>
                    voiceAvatarResourceAllowed(request.url.uriValue)
                    ? null
                    : WebResourceResponse(
                        statusCode: 403,
                        reasonPhrase: 'Blocked',
                        contentType: 'text/plain',
                        data: Uint8List(0),
                      ),
                onCreateWindow: (_, _) async => false,
                onPermissionRequest: (_, _) async =>
                    PermissionResponse(action: PermissionResponseAction.DENY),
                onShowFileChooser: (_, _) async => ShowFileChooserResponse(
                  handledByClient: true,
                  filePaths: null,
                ),
                onReceivedError: (_, _, _) {
                  if (mounted) setState(() => _failed = true);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

InAppWebViewSettings voiceAvatarWebViewSettings() => InAppWebViewSettings(
  javaScriptEnabled: true,
  transparentBackground: true,
  javaScriptCanOpenWindowsAutomatically: false,
  supportMultipleWindows: false,
  useShouldOverrideUrlLoading: true,
  useShouldInterceptRequest: true,
  useOnShowFileChooser: true,
  incognito: true,
  cacheEnabled: false,
  domStorageEnabled: false,
  databaseEnabled: false,
  sharedCookiesEnabled: false,
  thirdPartyCookiesEnabled: false,
  allowContentAccess: false,
  allowFileAccess: false,
  allowFileAccessFromFileURLs: false,
  allowUniversalAccessFromFileURLs: false,
  blockNetworkLoads: true,
  geolocationEnabled: false,
  mediaPlaybackRequiresUserGesture: true,
  allowsInlineMediaPlayback: false,
  allowsAirPlayForMediaPlayback: false,
  allowsPictureInPictureMediaPlayback: false,
  disableContextMenu: true,
  allowsLinkPreview: false,
  isInspectable: false,
  javaScriptBridgeEnabled: false,
);
