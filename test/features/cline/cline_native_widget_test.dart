import 'dart:async';
import 'dart:convert';

import 'package:conduit/features/cline/views/cline_workspace_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/theme/color_tokens.dart' show contrastRatio;
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/widgets/markdown/streaming_markdown_widget.dart';
import 'package:conduit_core/features/cline/providers/cline_backend_providers.dart';
import 'package:conduit_core/features/cline/services/cline_native_client.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';
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
}

Future<void> _mount(
  WidgetTester tester,
  _Wire wire,
  ClineNativeClient client, {
  double scale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(400, 900);
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
        home: const ClineWorkspacePage(),
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
