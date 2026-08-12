// Combat Ver.1 Playable 2A-1 — Match Guidance widget test
// （lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart内
// `_MatchGuidancePanel`、docs/design/combat_v1_playable_match_ui.md
// 「68章」）。
//
// Guidance derivation自体のlogic testは
// `combat_v1_playable_match_guidance_test.dart`側で完結させ、ここでは
// Widgetが実際にprimary/secondaryを表示すること・CPU処理中は表示しない
// ことだけを確認する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

const _primaryKey = Key('combat_v1_playable_match_guidance_primary');
const _secondaryKey = Key('combat_v1_playable_match_guidance_secondary');

CombatV1PlayableMatchScreen _screen(FakePlayableMatchSession session) =>
    CombatV1PlayableMatchScreen(
      humanWrestlerId: 'akari',
      cpuWrestlerId: 'reina',
      cpuDelay: Duration.zero,
      sessionFactory: (_) => session,
    );

void main() {
  testWidgets('Discard phase: primary/secondaryを表示する', (tester) async {
    final snapshot = testSnapshot(
      phase: CombatV1MatchPhase.discard,
      isHumanInputRequired: true,
      human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1')]),
      legalActions: const [
        CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
      ],
    );
    await tester.pumpWidget(_wrap(_screen(FakePlayableMatchSession(snapshot))));
    await tester.pump();

    expect(find.byKey(_primaryKey), findsOneWidget);
    expect(find.byKey(_secondaryKey), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(_primaryKey)).data, contains('捨てて'));
  });

  testWidgets('PIN可能: secondaryにPIN機会contextを表示する', (tester) async {
    final snapshot = testSnapshot(
      phase: CombatV1MatchPhase.action,
      isHumanInputRequired: true,
      cpu: testCpuStatus(posture: CombatV1WrestlerPosture.down),
      human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1')]),
      legalActions: const [
        CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        CombatV1PinAction(actorPlayerIndex: 0),
        CombatV1EndTurnAction(actorPlayerIndex: 0),
      ],
    );
    await tester.pumpWidget(_wrap(_screen(FakePlayableMatchSession(snapshot))));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(_secondaryKey)).data,
      contains('PIN可能'),
    );
  });

  testWidgets('CPU処理中はguidance widget自体を表示しない（human操作を促さない）', (tester) async {
    // design doc「84章 CPU loop widget tests」と同じ方針——CPU turn
    // snapshotから開始し、`cpuScript`の最後をHuman turnにして、CPU
    // loopが（scriptを使い切って）安全に停止するようにする（scriptが
    // 空のままCPU turn snapshotを与えると、`_runCpuLoop`が
    // `actionsExecuted == 0`を検知するたびに`_afterSnapshotChanged`経由で
    // 自分自身を再起動し続けるため、テストがhangする——widget自体の既存
    // 挙動であり、今回のGuidance追加とは無関係）。
    final cpuTurnSnapshot = testSnapshot(
      phase: CombatV1MatchPhase.action,
      isHumanInputRequired: false,
      currentActorPlayerIndex: 1,
      legalActions: const [],
    );
    final humanTurnSnapshot = testSnapshot(
      phase: CombatV1MatchPhase.action,
      isHumanInputRequired: true,
      legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
    );
    const cpuDelay = Duration(milliseconds: 20);
    final session = FakePlayableMatchSession(cpuTurnSnapshot)
      ..cpuScript = [humanTurnSnapshot];
    await tester.pumpWidget(
      _wrap(
        CombatV1PlayableMatchScreen(
          humanWrestlerId: 'akari',
          cpuWrestlerId: 'reina',
          cpuDelay: cpuDelay,
          sessionFactory: (_) => session,
        ),
      ),
    );
    // postFrameCallbackがCPU loopを開始した直後（`cpuDelay`待ち中）——
    // まだHuman turnへ遷移していない状態でguidanceが出ないことを確認する。
    await tester.pump();
    expect(find.byKey(_primaryKey), findsNothing);
    expect(find.byKey(_secondaryKey), findsNothing);
    expect(find.text('CPU行動中'), findsOneWidget);

    await tester.pump(cpuDelay);
    await tester.pump();

    expect(session.cpuScriptCallCount, 1);
    // Human turnへ遷移した後は、既存actor label同様guidanceも復帰する。
    expect(find.byKey(_primaryKey), findsOneWidget);
  });
}
