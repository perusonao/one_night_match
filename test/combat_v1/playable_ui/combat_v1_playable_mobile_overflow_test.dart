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
      // Final Merge Gate Major fix: Result overlay内にterminal
      // feedback（技名・damage・HP/posture/HEAT変化・PIN/SUBMISSION
      // outcome）が増えたため、最も内容量が多い構成でoverflowを確認する。
      final terminalFeedback = testActionFeedback(
        actionDisplayName: 'テストフィニッシャー・ドロップキック合体技',
        damage: 60,
        hpOwnerPlayerIndex: 1,
        hpBefore: 80,
        hpAfter: 0,
        postureOwnerPlayerIndex: 1,
        postureBefore: CombatV1WrestlerPosture.stand,
        postureAfter: CombatV1WrestlerPosture.down,
        heatBefore: 180,
        heatAfter: 220,
        kocOwnerPlayerIndex: 1,
        kocBefore: 0,
        kocAfter: 0,
        pinOutcome: CombatV1PlayablePinFeedbackOutcome.matchOver,
      );
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.matchOver,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
        latestFeedback: terminalFeedback,
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
        // Final Merge Gate Major fix: Result overlay内にterminal
        // feedback（技名・damage・HP/posture/HEAT変化・PIN/SUBMISSION
        // outcome）が増えたため、最も内容量が多い構成でoverflowを確認する。
        final terminalFeedback = testActionFeedback(
          actionDisplayName: 'テストフィニッシャー・ドロップキック合体技',
          damage: 60,
          hpOwnerPlayerIndex: 1,
          hpBefore: 80,
          hpAfter: 0,
          postureOwnerPlayerIndex: 1,
          postureBefore: CombatV1WrestlerPosture.stand,
          postureAfter: CombatV1WrestlerPosture.down,
          heatBefore: 180,
          heatAfter: 220,
          kocOwnerPlayerIndex: 1,
          kocBefore: 0,
          kocAfter: 0,
          pinOutcome: CombatV1PlayablePinFeedbackOutcome.matchOver,
        );
        final snapshot = testSnapshot(
          status: CombatV1PlayableControllerStatus.matchOver,
          isHumanInputRequired: false,
          currentActorPlayerIndex: null,
          legalActions: const [],
          latestFeedback: terminalFeedback,
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

  // Playable 2A-1「Match Guidance」——actor labelの直下へ追加した
  // primary/secondary guidance textがoverflowを起こさないことを、代表幅
  // 320／360／390で確認する（design doc「68章 UI / Mobile」）。
  group('Match Guidance（Playable 2A-1 追加）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 780);

      testWidgets('Discard phase（DOWN併発、secondaryが最長）: '
          '${width.toInt()}px幅でoverflowしない', (tester) async {
        await _withNarrowViewport(tester, () async {
          final snapshot = testSnapshot(
            phase: CombatV1MatchPhase.discard,
            isHumanInputRequired: true,
            human: testHumanStatus(
              posture: CombatV1WrestlerPosture.down,
              hand: [testTechniqueCard(instanceId: 'h1')],
            ),
            legalActions: const [
              CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
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
        }, size: size);
      });

      testWidgets('DOWN decision: ${width.toInt()}px幅でoverflowしない', (
        tester,
      ) async {
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
        }, size: size);
      });

      testWidgets(
        'Action phase（PIN opportunity context + latest feedback banner併発）: '
        '${width.toInt()}px幅でoverflowしない',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final feedback = testActionFeedback(
              actorPlayerIndex: 0,
              actionDisplayName: 'テストストライク',
              damage: 20,
              hpOwnerPlayerIndex: 1,
              hpBefore: 100,
              hpAfter: 80,
              postureOwnerPlayerIndex: 1,
              postureBefore: CombatV1WrestlerPosture.stand,
              postureAfter: CombatV1WrestlerPosture.down,
              heatBefore: 40,
              heatAfter: 50,
            );
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              cpu: testCpuStatus(posture: CombatV1WrestlerPosture.down),
              human: testHumanStatus(
                hand: [
                  testTechniqueCard(instanceId: 'h1'),
                  testCounterCard(instanceId: 'h2'),
                ],
              ),
              legalActions: const [
                CombatV1TechniqueAction(
                  actorPlayerIndex: 0,
                  cardInstanceId: 'h1',
                ),
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
        },
      );

      testWidgets('Counter response: ${width.toInt()}px幅でoverflowしない', (
        tester,
      ) async {
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
    }
  });

  group('Match Direction（Playable 2A-2 追加）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 780);

      testWidgets(
        'Action phase（Match Guidance PIN可能 + Match Direction '
        '「PINで相手のKOCを削りましょう」併発、latest feedback banner付き）: '
        '${width.toInt()}px幅でoverflowしない',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final feedback = testActionFeedback(
              actorPlayerIndex: 0,
              actionDisplayName: 'テストストライク',
              damage: 20,
              hpOwnerPlayerIndex: 1,
              hpBefore: 100,
              hpAfter: 80,
              postureOwnerPlayerIndex: 1,
              postureBefore: CombatV1WrestlerPosture.stand,
              postureAfter: CombatV1WrestlerPosture.down,
              heatBefore: 40,
              heatAfter: 50,
            );
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              cpu: testCpuStatus(
                hp: 100,
                koc: 9,
                posture: CombatV1WrestlerPosture.down,
              ),
              human: testHumanStatus(
                hand: [
                  testTechniqueCard(instanceId: 'h1'),
                  testCounterCard(instanceId: 'h2'),
                ],
              ),
              legalActions: const [
                CombatV1TechniqueAction(
                  actorPlayerIndex: 0,
                  cardInstanceId: 'h1',
                ),
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
        },
      );

      testWidgets(
        '相手KOC0（decisiveKoc、primary+secondaryとも表示）: '
        '${width.toInt()}px幅でoverflowしない',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              cpu: testCpuStatus(
                hp: 20,
                koc: 0,
                posture: CombatV1WrestlerPosture.stand,
              ),
              human: testHumanStatus(
                hand: [testTechniqueCard(instanceId: 'h1')],
              ),
              legalActions: const [
                CombatV1TechniqueAction(
                  actorPlayerIndex: 0,
                  cardInstanceId: 'h1',
                ),
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
          }, size: size);
        },
      );
    }
  });

  group('Match Direction Reachability（Review Findings Fix、Major）', () {
    // Review Findings Fix（Major、Playable 2A-2独立レビュー）——旧実装は
    // `NeverScrollableScrollPhysics`のため、Match Direction／latest
    // feedback／recent action logの合計content量が高さ上限（132px）を
    // 超えるとRenderFlex overflowこそ起きないものの、末尾の情報へ
    // ユーザーが一切到達できなかった。ここでは「overflowしない」だけ
    // でなく、「実際にscrollして末尾のrecent logへ到達できる」ことを、
    // widget rectangleのintersectionで検証する。
    const scrollKey = Key('combat_v1_playable_actor_recent_scroll');

    CombatV1PlayableMatchSnapshot buildOverflowingSnapshot() {
      // Direction primary+secondaryとも表示される代表状態（相手KOC0＝
      // decisiveKoc）。
      final cpu = testCpuStatus(hp: 20, koc: 0, posture: CombatV1WrestlerPosture.stand);
      // 複数行になる（damage/HP/posture/HEAT全て変化する）latest
      // feedback。
      final latest = testActionFeedback(
        actionIndex: 4,
        actorPlayerIndex: 0,
        actionDisplayName: 'テストフィニッシャー',
        damage: 60,
        hpOwnerPlayerIndex: 1,
        hpBefore: 80,
        hpAfter: 20,
        postureOwnerPlayerIndex: 1,
        postureBefore: CombatV1WrestlerPosture.stand,
        postureAfter: CombatV1WrestlerPosture.down,
        heatBefore: 150,
        heatAfter: 200,
      );
      // recentFeedback: 5件（`recents = reversed.skip(1).take(4)`により、
      // 直近4件がrecent logのWrapへ表示される代表的な最大件数）。
      final older = [
        for (var i = 0; i < 5; i++)
          testActionFeedback(
            actionIndex: i,
            actorPlayerIndex: i.isEven ? 0 : 1,
            actionDisplayName: 'テスト技目録その$i番',
            damage: 10 + i,
          ),
      ];
      return testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: cpu,
        human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1')]),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
        latestFeedback: latest,
        recentFeedback: [...older, latest],
      );
    }

    testWidgets(
      '320px幅: content量が高さ上限を超えても、scrollで末尾のrecent logへ到達できる',
      (tester) async {
        await _withNarrowViewport(tester, () async {
          final snapshot = buildOverflowingSnapshot();
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

          // Direction primary/secondaryが実際に描画されていることを
          // 前提として確認する（到達可否テストの土台）。
          expect(
            find.byKey(const Key('combat_v1_playable_match_direction_primary')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('combat_v1_playable_match_direction_secondary')),
            findsOneWidget,
          );

          // 末尾のrecent log entry（skip(1).take(4)の最後＝index 3）。
          const lastLogItemKey = Key('combat_v1_playable_recent_log_item_3');
          expect(find.byKey(lastLogItemKey), findsOneWidget);

          final viewportRectBefore = tester.getRect(find.byKey(scrollKey));
          final itemRectBefore = tester.getRect(find.byKey(lastLogItemKey));

          // Before scroll: 末尾のlog entryはviewportの下端より下（未到達）
          // であることを確認する——このassertion自体が「そもそも
          // scrollが必要な状況を再現できているか」の検証を兼ねる
          // （scroll不要な状況でtestが誤ってgreenになることを防ぐ）。
          final reachedBeforeScroll =
              itemRectBefore.bottom <= viewportRectBefore.bottom + 0.5;
          expect(
            reachedBeforeScroll,
            isFalse,
            reason:
                'テスト前提が崩れている: scroll前から末尾のrecent logが'
                'viewport内に収まっている（content量を増やすか代表構成を'
                '見直す必要がある）。viewport=$viewportRectBefore, '
                'item=$itemRectBefore',
          );

          // User scroll — 内部領域を実際にドラッグしてscrollする。
          await tester.drag(find.byKey(scrollKey), const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // After scroll: 末尾のlog entryがviewport内（到達可能）に
          // なっていることを確認する。
          final viewportRectAfter = tester.getRect(find.byKey(scrollKey));
          final itemRectAfter = tester.getRect(find.byKey(lastLogItemKey));
          final intersects = itemRectAfter.overlaps(viewportRectAfter);
          expect(
            intersects,
            isTrue,
            reason:
                'scroll後も末尾のrecent logへ到達できていない。'
                'viewport=$viewportRectAfter, item=$itemRectAfter',
          );
        }, size: const Size(320, 780));
      },
    );
  });
}
