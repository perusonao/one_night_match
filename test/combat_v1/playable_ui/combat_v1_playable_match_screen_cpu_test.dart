// Combat Ver.1 Playable 1B — CPU loop / Counter prompt widget test
// （lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart）。
//
// design doc「81・84章」を、scripted [FakePlayableMatchSession]
// （`combat_v1_playable_ui_test_fixtures.dart`）で検証する。

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

void main() {
  group('CPU loop（84章）', () {
    testWidgets('busy indicator・Human入力disabled・delay injection・Human手番で停止', (
      tester,
    ) async {
      const cpuDelay = Duration(milliseconds: 20);
      final initial = testSnapshot(
        revision: 0,
        isHumanInputRequired: false,
        currentActorPlayerIndex: 1,
        legalActions: const [],
      );
      final cpuStep1 = testSnapshot(
        revision: 1,
        isHumanInputRequired: false,
        currentActorPlayerIndex: 1,
        legalActions: const [],
      );
      final cpuStep2 = testSnapshot(
        revision: 2,
        isHumanInputRequired: false,
        currentActorPlayerIndex: 1,
        legalActions: const [],
      );
      final humanTurn = testSnapshot(
        revision: 3,
        isHumanInputRequired: true,
        currentActorPlayerIndex: 0,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      final session = FakePlayableMatchSession(initial)
        ..cpuScript = [cpuStep1, cpuStep2, humanTurn];

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
      // postFrameCallbackがCPU loopを開始する。
      await tester.pump();

      // busy中: spinner表示・primary actionsは出ない（Human input
      // disabled）。
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.byKey(const Key('combat_v1_playable_action_end_turn')), findsNothing);

      await tester.pump(cpuDelay);
      await tester.pump(cpuDelay);
      await tester.pump(cpuDelay);
      // 3回目のstepでHuman手番へ遷移した後の後処理（setState）まで進める。
      await tester.pump();

      expect(session.cpuScriptCallCount, 3);
      expect(find.text('あなたのターン'), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_action_end_turn')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('CPUの手番でなければloopは何もしない（no-op）', (tester) async {
      final snapshot = testSnapshot(
        isHumanInputRequired: true,
        currentActorPlayerIndex: 0,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: 'akari',
            cpuWrestlerId: 'reina',
            cpuDelay: Duration.zero,
            sessionFactory: (_) => session,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(session.cpuScriptCallCount, 0);
      expect(find.byKey(const Key('combat_v1_playable_action_end_turn')), findsOneWidget);
    });
  });

  group('Counter prompt（81章）', () {
    CombatV1PlayableMatchSnapshot counterSnapshot({int revision = 5}) => testSnapshot(
      revision: revision,
      phase: CombatV1MatchPhase.counterResponsePending,
      isHumanInputRequired: true,
      currentActorPlayerIndex: 0,
      human: testHumanStatus(
        hand: [
          testTechniqueCard(instanceId: 'h1'),
          testCounterCard(instanceId: 'c1', isUsable: true),
        ],
      ),
      pendingAttack: testPendingAttack(),
      legalActions: const [
        CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
        CombatV1DeclineCounterAction(actorPlayerIndex: 0),
      ],
    );

    testWidgets('Human防御時にCounter promptを表示し、Counter cardを選んでsubmitできる', (
      tester,
    ) async {
      final session = FakePlayableMatchSession(counterSnapshot())
        // submit後はCounterが解決してaction phaseへ戻った、というsnapshotを
        // 返す（fake session側の都合——実Engineの解決ロジックは検証しない）。
        ..nextSubmitSnapshot = testSnapshot(
          revision: 6,
          phase: CombatV1MatchPhase.action,
          isHumanInputRequired: true,
          currentActorPlayerIndex: 0,
          legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
        );
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: 'akari',
            cpuWrestlerId: 'reina',
            cpuDelay: Duration.zero,
            sessionFactory: (_) => session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_playable_counter_prompt_title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_playable_pending_attack_summary')),
        findsOneWidget,
      );
      expect(find.text(testNormalTechnique.name), findsWidgets);

      const playButtonKey = Key('combat_v1_playable_counter_play_button');
      expect(
        tester.widget<FilledButton>(find.byKey(playButtonKey)).onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('combat_v1_playable_counter_card_c1')));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(playButtonKey)).onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(playButtonKey));
      await tester.pumpAndSettle();

      expect(session.submitCalls, hasLength(1));
      expect(session.submitCalls.single.expectedRevision, 5);
      expect(
        session.submitCalls.single.action,
        const CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
      );
      // sheetは自分のaction送信で閉じる。
      expect(
        find.byKey(const Key('combat_v1_playable_counter_prompt_title')),
        findsNothing,
      );
    });

    testWidgets('Declineで技を受ける（cardを選ばなくても送信できる）', (tester) async {
      final session = FakePlayableMatchSession(counterSnapshot(revision: 9))
        ..nextSubmitSnapshot = testSnapshot(
          revision: 10,
          phase: CombatV1MatchPhase.action,
          isHumanInputRequired: true,
          currentActorPlayerIndex: 0,
          legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
        );
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: 'akari',
            cpuWrestlerId: 'reina',
            cpuDelay: Duration.zero,
            sessionFactory: (_) => session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('combat_v1_playable_counter_decline_button')));
      await tester.pumpAndSettle();

      expect(session.submitCalls, hasLength(1));
      expect(session.submitCalls.single.expectedRevision, 9);
      expect(
        session.submitCalls.single.action,
        const CombatV1DeclineCounterAction(actorPlayerIndex: 0),
      );
    });

    testWidgets('外側tap（barrier）ではpromptが閉じない（isDismissible: false）', (
      tester,
    ) async {
      final session = FakePlayableMatchSession(counterSnapshot());
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: 'akari',
            cpuWrestlerId: 'reina',
            cpuDelay: Duration.zero,
            sessionFactory: (_) => session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_playable_counter_prompt_title')),
        findsOneWidget,
      );

      // sheet外側（barrier領域）をtapしても閉じない。
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_playable_counter_prompt_title')),
        findsOneWidget,
      );
      expect(session.submitCalls, isEmpty);
    });

    testWidgets('CPU防御時（isHumanInputRequired == false）はpromptを出さない', (
      tester,
    ) async {
      // CPUがdefenderのCounter局面 → CPU自身の応答を経てHuman手番へ遷移する
      // までのscript。この間、一度もHuman向けpromptを出してはならない。
      final cpuDefending = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: false,
        currentActorPlayerIndex: 1,
        pendingAttack: testPendingAttack(attackerPlayerIndex: 0, defenderPlayerIndex: 1),
        legalActions: const [],
      );
      final afterCpuDecision = testSnapshot(
        revision: 1,
        isHumanInputRequired: true,
        currentActorPlayerIndex: 0,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      final session = FakePlayableMatchSession(cpuDefending)
        ..cpuScript = [afterCpuDecision];
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: 'akari',
            cpuWrestlerId: 'reina',
            cpuDelay: Duration.zero,
            sessionFactory: (_) => session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_playable_counter_prompt_title')),
        findsNothing,
      );
      expect(session.cpuScriptCallCount, 1);
      expect(find.text('あなたのターン'), findsOneWidget);
    });
  });
}
