import 'package:conduit/features/chat/voice_mode/chat_voice_mode_overlay.dart';
import 'package:conduit/features/chat/voice_mode/chat_voice_mode_controller.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/providers/app_providers.dart';

void main() {
  testWidgets('avatar panel uses available height and compacts for the keyboard', (tester) async {
    tester.view.physicalSize=const Size(402,874);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = Model.fromJson({'id':'fixture','name':'Fixture','meta':{'voice_avatar':{'file_id':'97abe420-cbc2-4f30-a00c-7940119d7d4f'}}});
    final container=ProviderContainer(overrides:[
      selectedModelProvider.overrideWithValue(model),
      apiServiceProvider.overrideWithValue(null),
      chatVoiceModeControllerProvider.overrideWith(()=>_TestVoiceModeController(const ChatVoiceModeSnapshot(phase:ChatVoiceModePhase.listening))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_buildActiveHarness(container));
    expect(tester.getSize(find.byKey(const ValueKey('voice-overlay-expanded'))).height,greaterThan(650));
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(_buildActiveHarness(container,keyboard:600));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-mode-collapsed')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  test('large text requires enough space for avatar and native controls',(){
    expect(voiceAvatarHasRoom(700,1),isTrue);
    expect(voiceAvatarHasRoom(300,1),isFalse);
    expect(voiceAvatarHasRoom(500,2),isFalse);
  });
  testWidgets('inactive overlay does not collapse a loose Stack', (
    tester,
  ) async {
    const stackKey = Key('chat-stack');
    const bodyKey = Key('chat-body');

    await tester.pumpWidget(
      const ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 500,
              child: Align(
                alignment: Alignment.topLeft,
                child: Stack(
                  key: stackKey,
                  children: [
                    Positioned.fill(
                      child: ColoredBox(key: bodyKey, color: Colors.black),
                    ),
                    ChatVoiceModeOverlay(bottomOffset: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(stackKey)), const Size(300, 500));
    expect(tester.getSize(find.byKey(bodyKey)), const Size(300, 500));
  });

  testWidgets('live transcript updates directly and intensity avoids layout', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatVoiceModeControllerProvider.overrideWith(
          () => _TestVoiceModeController(
            const ChatVoiceModeSnapshot(
              phase: ChatVoiceModePhase.speaking,
              spokenResponse: 'First partial',
              intensity: 0,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildActiveHarness(container));
    final controller = container.read(
      chatVoiceModeControllerProvider.notifier,
    ) as _TestVoiceModeController;
    final dotFinder = find.byKey(const ValueKey('voice-status-dot'));
    final scaleFinder = find.byKey(const ValueKey('voice-status-dot-scale'));
    final initialSize = tester.getSize(dotFinder);
    expect(find.text('First partial', findRichText: true), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-mode-surface-switcher')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('voice-overlay-expanded')),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );

    controller.update(
      const ChatVoiceModeSnapshot(
        phase: ChatVoiceModePhase.speaking,
        spokenResponse: 'Second partial',
        intensity: 10,
      ),
    );
    await tester.pump();

    expect(find.text('Second partial', findRichText: true), findsOneWidget);
    expect(tester.getSize(dotFinder), initialSize);
    expect(
      tester.widget<Transform>(scaleFinder).transform.getMaxScaleOnAxis(),
      greaterThan(1),
    );
  });

  testWidgets('an error is shown by its kind, never as an exception text', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatVoiceModeControllerProvider.overrideWith(
          () => _TestVoiceModeController(
            const ChatVoiceModeSnapshot(
              phase: ChatVoiceModePhase.error,
              errorMessage: 'Microphone permission denied.',
              errorKind: ChatVoiceModeError.microphoneDenied,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildActiveHarness(container));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ChatVoiceModeOverlay)),
    )!;

    expect(find.text(l10n.microphonePermissionDenied), findsOneWidget);

    final controller = container.read(
      chatVoiceModeControllerProvider.notifier,
    ) as _TestVoiceModeController;
    controller.update(
      const ChatVoiceModeSnapshot(
        phase: ChatVoiceModePhase.error,
        errorMessage: 'SocketException: connection refused',
        errorKind: ChatVoiceModeError.other,
      ),
    );
    await tester.pump();

    expect(find.text('SocketException: connection refused'), findsNothing);
    expect(find.text(l10n.voiceCallFailed), findsOneWidget);

    controller.update(
      const ChatVoiceModeSnapshot(
        phase: ChatVoiceModePhase.error,
        errorMessage: 'The server could not answer.',
        errorKind: ChatVoiceModeError.message,
      ),
    );
    await tester.pump();

    expect(find.text('The server could not answer.'), findsOneWidget);
  });

  testWidgets('reduced motion makes voice surface changes spatially static', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatVoiceModeControllerProvider.overrideWith(
          () => _TestVoiceModeController(
            const ChatVoiceModeSnapshot(
              phase: ChatVoiceModePhase.listening,
              intensity: 10,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _buildActiveHarness(container, disableAnimations: true),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey('voice-mode-surface-switcher')),
    );
    final size = tester.widget<AnimatedSize>(
      find.byKey(const ValueKey('voice-mode-surface-size')),
    );
    final scale = tester.widget<Transform>(
      find.byKey(const ValueKey('voice-status-dot-scale')),
    );
    expect(switcher.duration, Duration.zero);
    expect(size.duration, Duration.zero);
    expect(size.clipBehavior, Clip.none);
    expect(scale.transform.getMaxScaleOnAxis(), 1);
  });
}

Widget _buildActiveHarness(
  ProviderContainer container, {
  bool disableAnimations = false,
  double keyboard = 0,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(TweakcnThemes.t3Chat),
      localizationsDelegates: conduitLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size:const Size(402,874),viewInsets:EdgeInsets.only(bottom:keyboard),disableAnimations: disableAnimations),
          child: const SizedBox(
            width: 402,
            height: 874,
            child: Stack(
              children: [
                Positioned.fill(child: SizedBox.shrink()),
                ChatVoiceModeOverlay(bottomOffset: 0),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TestVoiceModeController extends ChatVoiceModeController {
  _TestVoiceModeController(this.initialState);

  final ChatVoiceModeSnapshot initialState;

  @override
  ChatVoiceModeSnapshot build() => initialState;

  void update(ChatVoiceModeSnapshot next) => state = next;
}
