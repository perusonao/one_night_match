// Combat Ver.1 Playable 2A-2 — Match Direction widget test
// （lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart内
// `_MatchDirectionPanel`、docs/design/combat_v1_playable_match_ui.md
// 「70章」）。
//
// Direction derivation自体のlogic testは
// `combat_v1_playable_match_direction_test.dart`側で完結させ、ここでは
// Widgetが実際にprimary/secondaryを表示すること・CPU処理中でも表示
// し続けること（Match Guidanceとの意図的な挙動差）・試合終了時は表示
// しないことだけを確認する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

const _primaryKey = Key('combat_v1_playable_match_direction_primary');
const _secondaryKey = Key('combat_v1_playable_match_direction_secondary');

CombatV1PlayableMatchScreen _screen(FakePlayableMatchSession session) =>
    CombatV1PlayableMatchScreen(
      humanWrestlerId: 'akari',
      cpuWrestlerId: 'reina',
      cpuDelay: Duration.zero,
      sessionFactory: (_) => session,
    );

/// Playable 2A-5「9章 Guidance / Direction / Result / Logの圧縮」——Match
/// Directionは既定で折りたたむため、明示的にtoggleをtapして展開する
/// （design doc「70.10章」の到達可能性原則の確認を兼ねる）。
Future<void> _expandDetail(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('combat_v1_playable_detail_toggle')));
  await tester.pump();
}

void main() {
  testWidgets('通常action phase: primaryを表示する', (tester) async {
    final snapshot = testSnapshot(
      phase: CombatV1MatchPhase.action,
      isHumanInputRequired: true,
      cpu: testCpuStatus(hp: 100, koc: 9, posture: CombatV1WrestlerPosture.stand),
      legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
    );
    await tester.pumpWidget(_wrap(_screen(FakePlayableMatchSession(snapshot))));
    await tester.pump();
    await _expandDetail(tester);

    expect(find.byKey(_primaryKey), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(_primaryKey)).data,
      isNotEmpty,
    );
  });

  testWidgets('相手が脆弱な状態（HP低下）: submission routeを表示する', (tester) async {
    final snapshot = testSnapshot(
      phase: CombatV1MatchPhase.action,
      isHumanInputRequired: true,
      cpu: testCpuStatus(hp: 30, koc: 9, posture: CombatV1WrestlerPosture.stand),
      submissionHpThreshold: 50,
      legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
    );
    await tester.pumpWidget(_wrap(_screen(FakePlayableMatchSession(snapshot))));
    await tester.pump();
    await _expandDetail(tester);

    expect(
      tester.widget<Text>(find.byKey(_primaryKey)).data,
      contains('Submission'),
    );
  });

  testWidgets('KOC/決着opportunity: 相手KOC0でdecisiveなwin path文言を表示する', (
    tester,
  ) async {
    final snapshot = testSnapshot(
      phase: CombatV1MatchPhase.action,
      isHumanInputRequired: true,
      cpu: testCpuStatus(hp: 100, koc: 0, posture: CombatV1WrestlerPosture.stand),
      legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
    );
    await tester.pumpWidget(_wrap(_screen(FakePlayableMatchSession(snapshot))));
    await tester.pump();
    await _expandDetail(tester);

    expect(
      tester.widget<Text>(find.byKey(_primaryKey)).data,
      contains('KOC'),
    );
    expect(find.byKey(_secondaryKey), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(_secondaryKey)).data,
      contains('PIN'),
    );
  });

  testWidgets('CPU turn: Match Guidanceと異なりCPU処理中も表示し続ける', (tester) async {
    final cpuTurnSnapshot = testSnapshot(
      phase: CombatV1MatchPhase.action,
      isHumanInputRequired: false,
      currentActorPlayerIndex: 1,
      cpu: testCpuStatus(hp: 100, koc: 9, posture: CombatV1WrestlerPosture.down),
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
    await tester.pump();
    await _expandDetail(tester);
    // CPU turn中でも（Match Guidanceとは違い）Direction panelは表示
    // され続ける——「今何をするか」ではなく「試合がどこへ向かって
    // いるか」を示す情報のため。
    expect(find.byKey(_primaryKey), findsOneWidget);

    await tester.pump(cpuDelay);
    await tester.pump();
    expect(session.cpuScriptCallCount, 1);
  });

  testWidgets('試合終了時（matchOver/safetyLimit等）は表示しない', (tester) async {
    final snapshot = testSnapshot(
      status: CombatV1PlayableControllerStatus.matchOver,
      isHumanInputRequired: false,
      currentActorPlayerIndex: null,
      legalActions: const [],
    );
    final session = FakePlayableMatchSession(snapshot)
      ..result = testResult();
    await tester.pumpWidget(_wrap(_screen(session)));
    await tester.pump();

    expect(find.byKey(_primaryKey), findsNothing);
    expect(find.byKey(_secondaryKey), findsNothing);
  });
}
