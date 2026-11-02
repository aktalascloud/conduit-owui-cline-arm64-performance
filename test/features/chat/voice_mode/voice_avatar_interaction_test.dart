import 'package:conduit/features/chat/voice_mode/voice_avatar_interaction.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('camera controls and drag do not intercept the call-end button', (tester) async {
    final commands=<Map<String,Object>>[];
    var ended=false;
    await tester.pumpWidget(MaterialApp(
      theme:AppTheme.dark(TweakcnThemes.t3Chat), locale:const Locale('ru'),
      localizationsDelegates:conduitLocalizationsDelegates,
      supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:Column(children:[
        SizedBox(width:320,height:320,child:VoiceAvatarInteraction(
          enabled:true,onView:commands.add,child:const IgnorePointer(child:ColoredBox(color:Colors.black)))),
        TextButton(key:const Key('call-end'),onPressed:()=>ended=true,child:const Text('Завершить')),
      ])),
    ));
    expect(find.byIcon(Icons.zoom_in), findsNothing);
    expect(find.byIcon(Icons.zoom_out), findsNothing);
    await tester.tap(find.byKey(const Key('avatar-reset-view')));
    expect(commands.single, {'reset':true});
    final surface=find.byType(VoiceAvatarInteraction);
    final origin=tester.getTopLeft(surface);
    await tester.dragFrom(origin+const Offset(70,150),const Offset(80,30));
    expect(commands.any((c)=>(c['dx'] as num? ?? 0)!=0),isTrue);
    final before=commands.length;
    await tester.tap(find.byKey(const Key('call-end')));
    expect(ended,isTrue); expect(commands.length,before);
    expect(find.byTooltip('Сбросить ракурс'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pump(const Duration(milliseconds:350));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
