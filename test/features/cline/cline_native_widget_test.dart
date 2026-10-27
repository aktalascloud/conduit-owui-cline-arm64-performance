import 'dart:async';
import 'dart:convert';

import 'package:conduit/features/cline/views/cline_workspace_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/theme/color_tokens.dart' show contrastRatio;
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/features/navigation/widgets/sidebar_tab_registry.dart';
import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';
import 'package:conduit/shared/widgets/markdown/streaming_markdown_widget.dart';
import 'package:conduit_core/features/cline/providers/cline_backend_providers.dart';
import 'package:conduit_core/features/cline/services/cline_native_client.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';
import 'package:conduit_core/providers/app_providers.dart' show openWebUiAccountAvailableProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Wire implements ClineWireTransport {
  final incoming = StreamController<String>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  void receive(Map<String, dynamic> frame) => incoming.add(jsonEncode(frame));
  @override
  Stream<String> get frames => incoming.stream;
  @override
  void send(String frame) =>
      sent.add(jsonDecode(frame) as Map<String, dynamic>);
  @override
  Future<void> close() async {
    if (!incoming.isClosed) unawaited(incoming.close());
  }
}

class _Client extends ClineBackendClientController {
  _Client(this.client);
  final ClineNativeClient client;
  @override
  ClineNativeClient? build() => client;
}

class _Preferred extends PreferredBackendController {
  @override
  PreferredBackend build() => PreferredBackend.cline;
  @override
  Future<void> set(PreferredBackend backend) async => state = backend;
}

Future<void> _mount(
  WidgetTester tester,
  _Wire wire,
  ClineNativeClient client, {
  double scale = 1,
  ThemeData? theme,
  ValueNotifier<bool>? active,
  double width = 400,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  wire.receive({
    'type': 'defaults',
    'defaults': {
      'provider': 'local',
      'model': 'test-model',
      'workspaceRoot': r'C:\Project',
    },
  });
  wire.receive({
    'type': 'providers',
    'providers': [
      {'id': 'local', 'name': 'Local', 'enabled': true},
    ],
  });
  wire.receive({
    'type': 'models',
    'providerId': 'local',
    'models': [
      {'id': 'test-model', 'name': 'Test model', 'operation': 'language'},
    ],
  });
  wire.receive({
    'type': 'sessions',
    'sessions': [
      {
        'sessionId': 'existing',
        'title': 'Saved session',
        'workspaceRoot': r'C:\Project',
        'status': 'completed',
      },
    ],
  });
  wire.receive({'type': 'hub_state', 'connected': true});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clineBackendClientProvider.overrideWith(() => _Client(client)),
        preferredBackendProvider.overrideWith(_Preferred.new),
        openWebUiAccountAvailableProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        theme: theme ?? ThemeData(platform: TargetPlatform.android),
        localizationsDelegates: conduitLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: active == null
            ? const ClineWorkspacePage()
            : ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (_, visible, _) => Stack(
                  children: [
                    Offstage(
                      offstage: !visible,
                      child: ClineWorkspacePage(
                        embedded: true,
                        active: visible,
                      ),
                    ),
                    if (!visible) const Scaffold(body: Text('OWUI')),
                  ],
                ),
              ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 80));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => client.close());
  });
}

Future<void> _unmount(WidgetTester tester, ClineNativeClient client) async {
  await tester.pumpWidget(const SizedBox.shrink());

  await tester.runAsync(() => client.close());
}

void main() {
  test(
    'Cline is the fourth primary destination without hiding optional tabs',
    () {
      final tabs = visibleSidebarTabIds(
        const SidebarTabAvailability(
          hermesOnly: false,
          hasOpenWebUi: true,
          hermesEnabled: false,
          notesEnabled: true,
          terminalEnabled: true,
          channelsEnabled: false,
        ),
      );
      expect(tabs, [
        SidebarTabId.chats,
        SidebarTabId.notes,
        SidebarTabId.terminal,
        SidebarTabId.cline,
      ]);
      expect(
        sidebarTabDescriptor(SidebarTabId.cline).materialIcon,
        Icons.code_outlined,
      );
    },
  );

  test(
    'switching the primary backend preserves the parallel SSH client',
    () async {
      final wire = _Wire();
      final client = ClineNativeClient(wire, project: r'C:\Project');
      final container = ProviderContainer(
        overrides: [preferredBackendProvider.overrideWith(_Preferred.new)],
      );
      container.read(clineBackendClientProvider.notifier).adopt(client);
      await container
          .read(preferredBackendProvider.notifier)
          .set(PreferredBackend.owui);
      expect(container.read(clineBackendClientProvider), same(client));
      expect(
        wire.sent.where((m) => m['type'] == 'send' || m['type'] == 'approval'),
        isEmpty,
      );
      container.read(clineBackendClientProvider.notifier).disconnect();
      expect(container.read(clineBackendClientProvider), isNull);
      container.dispose();
      await client.close();
    },
  );

  testWidgets(
    'sidebar round trip preserves draft, client and approval without replay',
    (tester) async {
      final wire = _Wire();
      final client = ClineNativeClient(wire, project: r'C:\Project');
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await _mount(
        tester,
        wire,
        client,
        active: active,
        width: 320,
        scale: 1.4,
        theme: AppTheme.dark(TweakcnThemes.all.first),
      );
      await tester.enterText(
        find.byKey(const Key('cline-native-input')),
        'Unsent private draft',
      );
      final before = wire.sent.length;
      active.value = false;
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('OWUI'), findsOneWidget);
      active.value = true;
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('cline-native-input')))
            .controller!
            .text,
        'Unsent private draft',
      );
      expect(wire.sent.length, before);
      expect(find.byKey(const Key('cline-model-picker')), findsOneWidget);
      expect(find.byKey(const Key('cline-project-picker')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final palette in TweakcnThemes.all) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Cline mode contrast and input stay readable: ${palette.id} $brightness',
        (tester) async {
          final wire = _Wire();
          final client = ClineNativeClient(wire, project: r'C:\Project');
          final theme = brightness == Brightness.dark
              ? AppTheme.dark(palette)
              : AppTheme.light(palette);
          await _mount(tester, wire, client, theme: theme);
          final chip = tester.widget<ChoiceChip>(
            find.byKey(const ValueKey('cline-mode-act')),
          );
          expect(chip.selected, isTrue);
          expect(
            contrastRatio(chip.labelStyle!.color!, chip.selectedColor!),
            greaterThanOrEqualTo(4.5),
          );
          final input = tester.widget<TextField>(
            find.byKey(const Key('cline-native-input')),
          );
          expect(input.decoration!.focusedBorder, InputBorder.none);
          expect(input.decoration!.enabledBorder, InputBorder.none);
          await tester.tap(find.byKey(const ValueKey('cline-mode-plan')));
          await tester.pump(const Duration(milliseconds: 80));
          expect(client.state.mode, 'plan');
          expect(wire.sent.where((frame) => frame['type'] == 'send'), isEmpty);
          expect(tester.takeException(), isNull);
          await _unmount(tester, client);
        },
      );
    }
  }

  testWidgets(
    'native Cline composer renders streamed Markdown using Conduit widgets',
    (tester) async {
      final wire = _Wire();
      final client = ClineNativeClient(wire, project: r'C:\Project');

      await _mount(tester, wire, client);

      await tester.enterText(
        find.byKey(const Key('cline-native-input')),
        'Тест',
      );

      await tester.pump();

      await tester.tap(find.byKey(const Key('cline-native-send')));
      await tester.pump();
      expect(wire.sent.where((f) => f['type'] == 'send'), hasLength(1));
      wire.receive({'type': 'assistant_delta', 'text': '**Native answer**'});
      wire.receive({'type': 'turn_done', 'finishReason': 'stop'});
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(StreamingMarkdownWidget), findsWidgets);
      expect(find.byKey(const Key('cline-native-input')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _unmount(tester, client);
    },
  );
  testWidgets(
    'native approval requires an explicit tap and carries the exact denial',
    (tester) async {
      final wire = _Wire();
      final client = ClineNativeClient(wire, project: r'C:\Project');
      await _mount(tester, wire, client);
      await tester.enterText(
        find.byKey(const Key('cline-native-input')),
        'Work',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('cline-native-send')));
      wire.receive({'type': 'session_started', 'sessionId': 'own'});
      wire.receive({
        'type': 'approval_request',
        'approvalId': 'request-1',
        'sessionId': 'own',
        'toolName': 'run_commands',
        'input': {'command': 'echo synthetic'},
      });
      await tester.pump(const Duration(milliseconds: 80));
      expect(wire.sent.where((f) => f['type'] == 'approval_response'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('cline-deny-request-1')));
      await tester.pump();
      expect(
        wire.sent
            .where((f) => f['type'] == 'approval_response')
            .single['approved'],
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await _unmount(tester, client);
    },
  );
  testWidgets('native Cline session list stays within a phone viewport', (
    tester,
  ) async {
    final wire = _Wire();
    final client = ClineNativeClient(wire, project: r'C:\Project');
    await _mount(tester, wire, client, scale: 1.6);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Saved session'), findsOneWidget);
    expect(find.text('Проекты на ПК'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester, client);
  });
  testWidgets(
    'native approvals and composer fit with a keyboard and large text',
    (tester) async {
      final wire = _Wire();
      final client = ClineNativeClient(wire, project: r'C:\Project');
      await _mount(tester, wire, client, scale: 2.0);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      wire.receive({'type': 'session_started', 'sessionId': 'own'});
      wire.receive({
        'type': 'approval_request',
        'approvalId': 'large',
        'sessionId': 'own',
        'toolName': 'editor',
        'input': {'patch': 'Synthetic patch\n' * 20},
      });
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('cline-deny-large')), findsOneWidget);
      expect(find.byKey(const Key('cline-native-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester, client);
    },
  );
}
