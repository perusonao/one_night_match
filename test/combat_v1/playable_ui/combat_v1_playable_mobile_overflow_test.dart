// Combat Ver.1 Playable 1B — Mobile overflow test（design doc「87章」）。
//
// 320〜390px程度の狭幅viewportでSetup/Match/Counter/Resultがoverflowしない
// ことを確認する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_action_feedback.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_setup_screen.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

Future<void> _withNarrowViewport(
  WidgetTester tester,
  Future<void> Function() body, {
  Size size = const Size(320, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await body();
}

void main() {
  testWidgets('Setup screen: 320px幅でoverflowしない', (tester) async {
    await _withNarrowViewport(tester, () async {
      await tester.pumpWidget(_wrap(const CombatV1PlayableSetupScreen()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Match screen（action phase・hand表示中）: 320px幅でoverflowしない', (
    tester,
  ) async {
    await _withNarrowViewport(tester, () async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(instanceId: 'h1'),
            testTechniqueCard(
              instanceId: 'h2',
              technique: testFinisherTechnique,
            ),
            testCounterCard(instanceId: 'h3'),
          ],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1PinAction(actorPlayerIndex: 0),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: 'akari',
            cpuWrestlerId: 'reina',
            cpuDelay: Duration.zero,
            sessionFactory: (_) => FakePlayableMatchSession(snapshot),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Match screen（DOWN）: 320px幅でoverflowしない', (tester) async {
    await _withNarrowViewport(tester, () async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1StandUpAction(actorPlayerIndex: 0),
          CombatV1RestAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: 'akari',
            cpuWrestlerId: 'reina',
            cpuDelay: Duration.zero,
            sessionFactory: (_) => FakePlayableMatchSession(snapshot),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Counter prompt: 320px幅でoverflowしない', (tester) async {
    await _withNarrowViewport(tester, () async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testCounterCard(instanceId: 'c1'),
            testTechniqueCard(instanceId: 'h1'),
          ],
        ),
        pendingAttack: testPendingAttack(),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: 'akari',
            cpuWrestlerId: 'reina',
            cpuDelay: Duration.zero,
            sessionFactory: (_) => FakePlayableMatchSession(snapshot),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Result overlay: 320px幅でoverflowしない', (tester) async {
    await _withNarrowViewport(tester, () async {
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.matchOver,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
      );
      final session = FakePlayableMatchSession(
        snapshot,
        result: testResult(winnerPlayerIndex: 1),
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
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Playable 1C「Mobile Priority」——390×844（実機に近い縦長viewport）でも
  // 確認する。feedback banner・finisher hint・hand scroll cueなど今回
  // 追加した可変高panelを含む、最も内容量が多い構成で検証する。
  group('390×844（Playable 1C 追加）', () {
    const size = Size(390, 844);

    testWidgets('Setup screen: 390×844でoverflowしない', (tester) async {
      await _withNarrowViewport(tester, () async {
        await tester.pumpWidget(_wrap(const CombatV1PlayableSetupScreen()));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }, size: size);
    });

    testWidgets('Match screen（latest feedback banner + hand + finisher hint）: '
        '390×844でoverflowしない', (tester) async {
      await _withNarrowViewport(tester, () async {
        final feedback = testActionFeedback(
          actorPlayerIndex: 0,
          actionDisplayName: 'テストフィニッシャー・ドロップキック合体技',
          damage: 60,
          hpOwnerPlayerIndex: 1,
          hpBefore: 80,
          hpAfter: 20,
          postureOwnerPlayerIndex: 1,
          postureBefore: CombatV1WrestlerPosture.stand,
          postureAfter: CombatV1WrestlerPosture.down,
          heatBefore: 40,
          heatAfter: 60,
          kocOwnerPlayerIndex: 1,
          kocBefore: 10,
          kocAfter: 7,
          pinOutcome: CombatV1PlayablePinFeedbackOutcome.kickOut,
        );
        final snapshot = testSnapshot(
          phase: CombatV1MatchPhase.action,
          sharedHeat: 360,
          finisherHeatThreshold: 200,
          human: testHumanStatus(
            hand: [
              testTechniqueCard(instanceId: 'h1'),
              testTechniqueCard(
                instanceId: 'h2',
                technique: testFinisherTechnique,
                isUsable: false,
              ),
              testCounterCard(instanceId: 'h3'),
            ],
          ),
          legalActions: const [
            CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
            CombatV1PinAction(actorPlayerIndex: 0),
            CombatV1EndTurnAction(actorPlayerIndex: 0),
          ],
          latestFeedback: feedback,
          recentFeedback: [feedback],
        );
        await tester.pumpWidget(
          _wrap(
            CombatV1PlayableMatchScreen(
              humanWrestlerId: 'akari',
              cpuWrestlerId: 'reina',
              cpuDelay: Duration.zero,
              sessionFactory: (_) => FakePlayableMatchSession(snapshot),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }, size: size);
    });

    testWidgets('Counter prompt: 390×844でoverflowしない', (tester) async {
      await _withNarrowViewport(tester, () async {
        final snapshot = testSnapshot(
          phase: CombatV1MatchPhase.counterResponsePending,
          isHumanInputRequired: true,
          human: testHumanStatus(
            hand: [
              testCounterCard(instanceId: 'c1'),
              testTechniqueCard(instanceId: 'h1'),
            ],
          ),
          pendingAttack: testPendingAttack(),
          legalActions: const [
            CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
            CombatV1DeclineCounterAction(actorPlayerIndex: 0),
          ],
        );
        await tester.pumpWidget(
          _wrap(
            CombatV1PlayableMatchScreen(
              humanWrestlerId: 'akari',
              cpuWrestlerId: 'reina',
              cpuDelay: Duration.zero,
              sessionFactory: (_) => FakePlayableMatchSession(snapshot),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, size: size);
    });

    testWidgets('Result overlay: 390×844でoverflowしない', (tester) async {
      await _withNarrowViewport(tester, () async {
        final snapshot = testSnapshot(
          status: CombatV1PlayableControllerStatus.matchOver,
          isHumanInputRequired: false,
          currentActorPlayerIndex: null,
          legalActions: const [],
        );
        final session = FakePlayableMatchSession(
          snapshot,
          result: testResult(winnerPlayerIndex: 1),
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
        await tester.pump();
        expect(tester.takeException(), isNull);
      }, size: size);
    });
  });
}
