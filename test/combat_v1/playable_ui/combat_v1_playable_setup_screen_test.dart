// Combat Ver.1 Playable 1B — Setup Screen widget test
// （lib/src/combat_v1/playable_ui/combat_v1_playable_setup_screen.dart）。
//
// design doc「77章 Widget Tests — Setup」を検証する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_setup_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

void main() {
  testWidgets('title・Human 4択・CPU 4択・Startボタンを表示する', (tester) async {
    await tester.pumpWidget(_wrap(const CombatV1PlayableSetupScreen()));

    expect(find.text('Combat Ver.1 対戦'), findsOneWidget);
    expect(find.text('あなたのレスラー（YOU）'), findsOneWidget);
    expect(find.text('CPUのレスラー'), findsOneWidget);

    for (final id in ['misaki', 'jack', 'akari', 'reina']) {
      expect(
        find.byKey(Key('combat_v1_playable_wrestler_choice_${id}_unselected')).evaluate().length +
            find.byKey(Key('combat_v1_playable_wrestler_choice_${id}_selected')).evaluate().length,
        2, // Human picker・CPU pickerで1つずつ、合計2箇所に同じidが現れる。
      );
    }

    expect(find.text('Start Match'), findsOneWidget);
  });

  testWidgets('既定選択はHuman=akari・CPU=reina', (tester) async {
    await tester.pumpWidget(_wrap(const CombatV1PlayableSetupScreen()));

    expect(
      find.byKey(const Key('combat_v1_playable_wrestler_choice_akari_selected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('combat_v1_playable_wrestler_choice_reina_selected')),
      findsOneWidget,
    );
  });

  testWidgets('mirror match（同一レスラー）を選択できる', (tester) async {
    await tester.pumpWidget(_wrap(const CombatV1PlayableSetupScreen()));

    // CPU側もakariへ変更 → Human/CPU双方akariのmirror matchになる。
    final cpuAkariUnselected = find.byKey(
      const Key('combat_v1_playable_wrestler_choice_akari_unselected'),
    );
    expect(cpuAkariUnselected, findsOneWidget);
    await tester.tap(cpuAkariUnselected);
    await tester.pump();

    expect(
      find.byKey(const Key('combat_v1_playable_wrestler_choice_akari_selected')),
      findsNWidgets(2),
    );
  });

  testWidgets('Start Matchで選択したwrestlerIdsのままMatch Screenへ遷移する', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const CombatV1PlayableSetupScreen()));

    // CPUをmisakiへ変更してから開始する（Human側もunselectedのmisakiを
    // 持つため、CPU pickerへscopeして曖昧さを排除する）。
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('combat_v1_playable_setup_cpu_picker')),
        matching: find.byKey(
          const Key('combat_v1_playable_wrestler_choice_misaki_unselected'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('combat_v1_playable_setup_start_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CombatV1PlayableMatchScreen), findsOneWidget);
    final screen = tester.widget<CombatV1PlayableMatchScreen>(
      find.byType(CombatV1PlayableMatchScreen),
    );
    expect(screen.humanWrestlerId, 'akari');
    expect(screen.cpuWrestlerId, 'misaki');
  });
}
