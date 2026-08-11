// Combat Ver.1 Playable 1B — Integration test（design doc「88章」）。
//
// 実`CombatV1PlayableMatchController`（`combatV1PlayableDefaultSessionFactory`
// 経由）を使い、Setup config → controller → Match UIのconnectionを検証
// する。Controller-level full matchは既にPlayable 1Aで検証済みのため、
// ここでは長時間のWidget操作でterminalまで到達させることを目的としない
// （88章）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

/// Human向けの1手を、単純なbutton優先順位（card選択不要な手を優先）で
/// 進める。無理に賢い選択ロジックは構築しない（90章）——Discard/StandUp/
/// Rest/PIN/EndTurnのうち画面上に見つかったものをそのまま押すだけ。
/// Counter promptはdecline一択（button常にenabled）。Technique/PINなど
/// card選択が必要な手のみ先頭のhand cardを選んでから押す。
///
/// 戻り値: 何らかの操作を実行できたか（falseならこれ以上進められる
/// 単純な手が見つからなかった、というだけで異常ではない）。
Future<bool> _driveOneHumanStep(WidgetTester tester) async {
  const counterDeclineKey = Key('combat_v1_playable_counter_decline_button');
  if (find.byKey(counterDeclineKey).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(counterDeclineKey));
    await tester.pumpAndSettle();
    return true;
  }

  const discardKey = Key('combat_v1_playable_action_discard');
  if (find.byKey(discardKey).evaluate().isNotEmpty) {
    final firstCard = find
        .descendant(
          of: find.byKey(const Key('combat_v1_playable_human_hand')),
          matching: find.byType(InkWell),
        )
        .first;
    await tester.tap(firstCard);
    await tester.pump();
    await tester.tap(find.byKey(discardKey));
    await tester.pumpAndSettle();
    return true;
  }

  for (final key in const [
    Key('combat_v1_playable_action_stand_up'),
    Key('combat_v1_playable_action_pin'),
    Key('combat_v1_playable_action_end_turn'),
    Key('combat_v1_playable_action_rest'),
  ]) {
    if (find.byKey(key).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      return true;
    }
  }

  return false;
}

void main() {
  testWidgets('Setup config → real controller → Match UIのconnection', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CombatV1PlayableMatchScreen(
          humanWrestlerId: 'akari',
          cpuWrestlerId: 'reina',
          cpuDelay: Duration.zero,
          // widget testでもUI層のseed生成をそのまま使う——決定論性は
          // controller-level test（Playable 1A）側で担保済み。
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 初期描画: real controllerのsnapshotがそのまま反映されている。
    expect(find.textContaining('HP'), findsWidgets);
    expect(find.byKey(const Key('combat_v1_playable_cpu_status_panel')), findsOneWidget);
    expect(find.byKey(const Key('combat_v1_playable_human_status_panel')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 単純な優先順位でHumanの手を数ターン分進める（90章: 複雑な自動選択
    // ロジックは構築しない、terminalまでの完走も必須ではない）。
    for (var i = 0; i < 6; i++) {
      final progressed = await _driveOneHumanStep(tester);
      expect(tester.takeException(), isNull);
      if (!progressed) break;
    }

    expect(tester.takeException(), isNull);
  });
}
