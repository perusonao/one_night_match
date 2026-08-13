// Combat Ver.1 Playable 1B — Mobile overflow test（design doc「87章」）。
//
// 320〜390px程度の狭幅viewportでSetup/Match/Counter/Resultがoverflowしない
// ことを確認する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_lifecycle.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_action_feedback.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_setup_screen.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

// jack_kurocho_driver相当（ROUGH属性 かつ Direct PIN FINISHER）——複数の
// 重要traitが同時に成立する実在の組み合わせ（Playable 2A-3 mobile
// regression「B. Technique with multiple important traits」用）。
const CombatV1Technique _multiTraitTechnique = CombatV1Technique(
  id: 'test_mobile_multi_trait',
  name: 'テスト複合トレイト技',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.rough,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 3}),
  damage: 30,
  heatGain: 50,
  family: CombatV1TechniqueFamily.driver,
  finisherType: CombatV1FinisherType.directPin,
);

const CombatV1Technique _submissionFinisherTechnique = CombatV1Technique(
  id: 'test_mobile_submission_finisher',
  name: 'テストサブミッションフィニッシャー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 3}),
  damage: 30,
  heatGain: 40,
  family: CombatV1TechniqueFamily.legLock,
  finisherType: CombatV1FinisherType.submission,
);

// Review Findings Fix（Minor、4.1章）——jack_kurocho_driver相当（ROUGH +
// Direct PIN FINISHER）に、長めの名前・required/result postureを追加した
// 情報量最大級のTechnique card fixture。isUsable:falseと組み合わせて
// unusable reason行も同時に表示させ、Tier1〜3の全情報が同時に存在する
// 代表ケースを作る。
const CombatV1Technique _maxInfoTechnique = CombatV1Technique(
  id: 'test_mobile_max_info',
  name: 'テスト最大情報量ダイレクトピンフィニッシャー・ドライバー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.rough,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 3}),
  damage: 30,
  heatGain: 50,
  requiredOpponentState: CombatV1WrestlerPosture.stand,
  resultOpponentState: CombatV1WrestlerPosture.down,
  family: CombatV1TechniqueFamily.driver,
  finisherType: CombatV1FinisherType.directPin,
);

/// [_maxInfoTechnique]（family: driver、throwing group）を実際に返せる
/// Counter fixture——`testCounterCard()`既定の`testCounter`は
/// `counterableFamilies: [elbow]`のみのため一致しない
/// （`combat_v1_playable_ui_test_fixtures.dart`参照）。family/group
/// information（`combat_v1_playable_counter_family_match`）が実際に
/// 描画される状態でreachability testを行うため、専用のCounterを構築する。
final CombatV1Counter _maxInfoMatchingCounter = CombatV1Counter(
  id: 'test_mobile_counter_throw',
  name: 'テスト投げ技カウンター',
  attribute: CombatV1EnergyAttribute.throwing,
  counterableGroups: const [CombatV1TechniqueFamilyGroup.throwing],
);

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

/// Playable 2A-5「9章 Guidance / Direction / Result / Logの圧縮」——Match
/// Direction／Latest Result banner／Recent Logは既定で折りたたむため、
/// これらの内容を検証するtestは明示的にtoggleをtapして展開する（design
/// doc「70.10章」の到達可能性原則——折りたたんだ場合もユーザーの明示
/// 操作で到達できることの確認を兼ねる）。
Future<void> _expandDetail(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('combat_v1_playable_detail_toggle')));
  await tester.pump();
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
          await _expandDetail(tester);

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

  // Playable 2A-3「Technique / Counter Decision Readability」——Technique
  // decision trait badge・Counter incoming attack summaryの拡張により
  // 情報量が増えたため、代表ケースB〜Eで320/360/390px幅のoverflowと、
  // primary controlのhit-testabilityを確認する（24章）。
  group('Technique / Counter Decision Traits（Playable 2A-3 追加）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 780);

      testWidgets(
        'B. 複数の重要traitを持つTechnique card（ROUGH + FINISHER · PIN）: '
        '${width.toInt()}px幅でoverflowせず、primary controlへ到達できる',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              sharedHeat: 200,
              finisherHeatThreshold: 200,
              human: testHumanStatus(
                hand: [
                  testTechniqueCard(
                    instanceId: 'h1',
                    technique: _multiTraitTechnique,
                  ),
                ],
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

            // Playable 2A-5 Review Findings Fix「3章」——完全なtrait
            // badge（合成label込み）は選択後の`_SelectedTechniquePanel`
            // が担当する。
            await tester.tap(
              find.byKey(const Key('combat_v1_playable_hand_card_h1')),
            );
            await tester.pump();
            expect(find.text('FINISHER · PIN'), findsOneWidget);
            expect(find.text('ROUGH'), findsOneWidget);

            // Primary control（End Turn button）がviewport内にあり、
            // hit-testableであることを確認する。
            final endTurnFinder = find.byKey(
              const Key('combat_v1_playable_action_end_turn'),
            );
            expect(endTurnFinder, findsOneWidget);
            final screenRect = Offset.zero & size;
            final buttonRect = tester.getRect(endTurnFinder);
            expect(screenRect.contains(buttonRect.center), isTrue);
          }, size: size);
        },
      );

      testWidgets(
        'C. FINISHER card（trait badge付き）: ${width.toInt()}px幅でoverflowしない',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              sharedHeat: 200,
              finisherHeatThreshold: 200,
              human: testHumanStatus(
                hand: [
                  testTechniqueCard(instanceId: 'h1'),
                  testTechniqueCard(
                    instanceId: 'h2',
                    technique: _submissionFinisherTechnique,
                  ),
                ],
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
            // Playable 2A-5 Review Findings Fix「3章」——完全なtrait
            // badge（合成label込み）は選択後の`_SelectedTechniquePanel`
            // が担当する。
            await tester.tap(
              find.byKey(const Key('combat_v1_playable_hand_card_h2')),
            );
            await tester.pump();
            expect(find.text('FINISHER · SUBMISSION'), findsOneWidget);
          }, size: size);
        },
      );

      testWidgets(
        'D. Counter response（HEAT・trait badge・prevents hint込みの長い'
        'incoming attack summary）: ${width.toInt()}px幅でoverflowせず、'
        'decline buttonへ実際にhit-testできる（Review Findings Fix、Minor、'
        '16章）',
        (tester) async {
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
              pendingAttack: testPendingAttack(
                technique: _multiTraitTechnique,
              ),
              legalActions: const [
                CombatV1CounterAction(
                  actorPlayerIndex: 0,
                  cardInstanceId: 'c1',
                ),
                CombatV1DeclineCounterAction(actorPlayerIndex: 0),
              ],
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
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            final declineFinder = find.byKey(
              const Key('combat_v1_playable_counter_decline_button'),
            );
            expect(declineFinder, findsOneWidget);
            final screenRect = Offset.zero & size;
            expect(
              screenRect.contains(tester.getRect(declineFinder).center),
              isTrue,
            );

            // Review Findings Fix（Minor、16章）: centerがscreen内である
            // ことの確認だけでなく、実際にdeclineをtapし、期待するstate
            // 変化（実際にsubmitHumanActionへdeclineCounter actionが渡る
            // こと）までassertする。
            await tester.tap(declineFinder);
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(session.submitCalls, isNotEmpty);
            expect(
              session.submitCalls.last.action.kind,
              CombatV1LegalActionKind.declineCounter,
            );
          }, size: size);
        },
      );

      testWidgets(
        'E. Counter response（Submission FINISHER incoming、特殊決着技）: '
        '${width.toInt()}px幅でoverflowしない',
        (tester) async {
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
              pendingAttack: testPendingAttack(
                technique: _submissionFinisherTechnique,
              ),
              legalActions: const [
                CombatV1CounterAction(
                  actorPlayerIndex: 0,
                  cardInstanceId: 'c1',
                ),
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
            expect(find.text('FINISHER · SUBMISSION'), findsOneWidget);
          }, size: size);
        },
      );
    }
  });

  // Review Findings Fix（Minor、Playable 2A-3独立レビュー「4章 Mobile
  // Visibility Tests」）——`tester.takeException() == null`だけでは
  // 「情報が読める」ことを保証しない（Playable 2A-2で発生した
  // regressionと同じ穴）。ここでは`getRect`で実座標を取得し、重要情報
  // widgetが実際にviewportとintersectしていることを検証する。
  group('Mobile Visibility — Technique Card（Review Findings Fix、4.1章）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 780);

      testWidgets(
        '情報量最大級のTechnique card（ROUGH+FINISHER·PIN+posture+unusable '
        'reason）: ${width.toInt()}px幅で主要情報が実際にviewport内へ表示される',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              // sharedHeat < finisherHeatThreshold → unusable reason
              // （HEAT要件hint）が同時に表示される最大情報量構成。
              sharedHeat: 0,
              finisherHeatThreshold: 200,
              human: testHumanStatus(
                hand: [
                  testTechniqueCard(
                    instanceId: 'h1',
                    technique: _maxInfoTechnique,
                    isUsable: false,
                  ),
                ],
              ),
              legalActions: const [],
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

            // Review Findings Fix（Minor、4.1章）: 画面全体の矩形ではなく、
            // 実際のclip viewport（Technique areaのSingleChildScrollView
            // 自身のrender box）を使う——画面全体を使うと、AppBar/他panel
            // の分だけ過大に見積もり、実際にはscroll clipで見えない要素を
            // 誤って「viewport内」と判定してしまう（旧実装でclipされても
            // greenになるtestにしないための対応）。
            final scrollAreaFinder = find.byKey(
              const Key('combat_v1_playable_technique_area_scroll'),
            );
            // `.first`——このkeyed SingleChildScrollView自身のScrollable
            // （欲しいのはこちら）に加え、内側の`_HandRow`（横scroll
            // ListView）のScrollableも子孫として一致してしまうため、
            // tree順で先に現れる外側（縦scroll）のものを選ぶ。
            final scrollableFinder = find
                .descendant(of: scrollAreaFinder, matching: find.byType(Scrollable))
                .first;

            // Review Findings Fix（Minor、4.1章）: 320pxなど狭幅では他panel
            // （HP/KOC/Hand/PIN Cards行等）がより多く折り返され、Technique
            // areaの実際のclip viewport高が狭くなることがある——この場合、
            // 末尾情報（unusable reason等）は初期scroll位置では見えない。
            // 「scroll前は見えない／scroll後に実際に見える」ことを実座標で
            // 検証することで、旧実装でclipされたままgreenになるtestに
            // しない（4章）。
            Future<void> expectReachableInViewport(
              Finder finder,
              String label,
            ) async {
              expect(finder, findsOneWidget, reason: '$labelが見つからない');
              var viewportRect = tester.getRect(scrollAreaFinder);
              var rect = tester.getRect(finder);
              if (!rect.overlaps(viewportRect)) {
                await tester.scrollUntilVisible(
                  finder,
                  50,
                  scrollable: scrollableFinder,
                );
                await tester.pumpAndSettle();
                viewportRect = tester.getRect(scrollAreaFinder);
                rect = tester.getRect(finder);
              }
              expect(
                rect.overlaps(viewportRect),
                isTrue,
                reason:
                    '$labelへ実際に到達できない（scroll後もviewport外）: '
                    'rect=$rect, viewport=$viewportRect',
              );
            }

            // Playable 2A-5 Review Findings Fix「3章 Compact Hand」——
            // 一覧段階（compact hand card自体）で読める最低限の情報：
            // 識別できる名前・required Energy（ellipsisで折り返されても
            // Text自体の実座標が画面内にあれば読める＝視認性の代理指標
            // として使う）。
            await expectReachableInViewport(
              find.text(_maxInfoTechnique.name),
              'Technique name（compact hand card）',
            );
            await expectReachableInViewport(
              find.byKey(const Key('combat_v1_playable_card_energy_line')),
              'Energy line（compact hand card）',
            );

            // 詳細（trait badge・DMG/HEAT・posture・使用不可理由）は
            // 選択後の`_SelectedTechniquePanel`（hand直下）が担当する。
            // 縦scrollは許容する（「一覧＝比較はscroll不要、詳細閲覧は
            // 必要に応じてscroll可能」という役割分離、design doc
            // Playable 2A-5 Review Findings Fix追記「11章」）。
            final cardFinder = find.byKey(
              const Key('combat_v1_playable_hand_card_h1'),
            );
            await tester.ensureVisible(cardFinder);
            await tester.pumpAndSettle();
            await tester.tap(cardFinder);
            await tester.pump();

            final panelFinder = find.byKey(
              const Key('combat_v1_playable_selected_technique_panel'),
            );
            expect(panelFinder, findsOneWidget);

            // trait badge（FINISHER · PINとROUGHの両方）——panel専用key
            // のため、compact hand cardのmajor trait chipとは衝突しない。
            await expectReachableInViewport(
              find.byKey(
                const Key('combat_v1_playable_card_finisher_resolution_badge'),
              ),
              'FINISHER resolution badge',
            );
            await expectReachableInViewport(
              find.byKey(const Key('combat_v1_playable_card_rough_badge')),
              'ROUGH badge',
            );
            // DMG/HEAT行——compact hand card側にも短い"DMG NN"表示がある
            // ため、panelへscopeして一意に特定する。
            await expectReachableInViewport(
              find.descendant(
                of: panelFinder,
                matching: find.textContaining(
                  'DMG ${_maxInfoTechnique.damage}',
                ),
              ),
              'DMG/HEAT line（panel）',
            );
            // required/result posture行。
            await expectReachableInViewport(
              find.byKey(
                const Key('combat_v1_playable_card_required_posture'),
              ),
              'required posture line',
            );
            await expectReachableInViewport(
              find.byKey(const Key('combat_v1_playable_card_result_posture')),
              'result posture line',
            );
            // unusable reason（selected panelのusable status行）。
            await expectReachableInViewport(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_usable_status',
                ),
              ),
              'unusable reason',
            );
          }, size: size);
        },
      );

      testWidgets(
        '選択可能なTechnique card: ${width.toInt()}px幅でtap targetへ実際に'
        'hit-testできる',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              sharedHeat: 200,
              finisherHeatThreshold: 200,
              human: testHumanStatus(
                hand: [
                  testTechniqueCard(
                    instanceId: 'h1',
                    technique: _maxInfoTechnique,
                  ),
                ],
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

            final cardFinder = find.byKey(
              const Key('combat_v1_playable_hand_card_h1'),
            );
            expect(cardFinder, findsOneWidget);
            await tester.ensureVisible(cardFinder);
            await tester.pumpAndSettle();

            // Review Findings Fix（Minor、4.1章）: `tester.tap()`は
            // widgetの「全高込みの幾何中心」を狙うが、狭幅×実際のprimary
            // action button併存時は、ensureVisible後も中心の数十pxが
            // viewport外に残ることがある（`_MatchBody`のExpanded/
            // SingleChildScrollViewの実高がcard高より小さいため）。これは
            // real deviceでの実際の未到達を意味しない——指は現在
            // 見えている範囲内の任意の点を押せる。そのため、widget中心
            // ではなく「card rectとviewportの交差領域中心」（＝実際に
            // 見えていて押せる点）でhit-testを検証する
            // （`hitTestOnBinding`と同じ考え方、24章）。
            // 実際のclip viewport（Technique areaのSingleChildScrollView
            // 自身のrender box——`Expanded`が割り当てた高さそのもの）を
            // 使う。画面全体の矩形をそのまま使うと、AppBar/他panel分
            // 過大に見積もり、実際にはscroll clipで見えない領域まで
            // 「見えている」と誤判定してしまう。
            final clipViewportRect = tester.getRect(
              find.byKey(
                const Key('combat_v1_playable_technique_area_scroll'),
              ),
            );
            final cardRect = tester.getRect(cardFinder);
            final visibleRect = cardRect.intersect(clipViewportRect);
            expect(
              visibleRect.width > 0 && visibleRect.height > 0,
              isTrue,
              reason:
                  'cardが実際のclip viewportと全く交差していない'
                  '（真に到達不能）: card=$cardRect, '
                  'viewport=$clipViewportRect',
            );
            // `tapAt`は指定座標へ実際のpointer eventを送るだけで
            // widget-targetとの一致チェックは行わない——real deviceの
            // タップと同じ動作。「そこを押すと本当に選択状態になるか」を
            // 後続のbutton state assertionで検証することで、
            // hit-testabilityを実際の挙動ベースで確認する。
            await tester.tapAt(visibleRect.center);
            await tester.pump();
            expect(tester.takeException(), isNull);

            // 選択状態（selectedならTechnique action buttonが有効化される）
            // への到達を確認する。`_ActionButton`（private widget）が
            // 内部で`FilledButton`を構築するため、descendantとして取得する。
            final techniqueButton = find.byKey(
              const Key('combat_v1_playable_action_technique'),
            );
            expect(techniqueButton, findsOneWidget);
            final filledButton = find.descendant(
              of: techniqueButton,
              matching: find.byType(FilledButton),
            );
            expect(
              tester.widget<FilledButton>(filledButton).onPressed,
              isNotNull,
              reason: '見えている範囲をtapしてもcard選択状態にならなかった',
            );
          }, size: size);
        },
      );
    }
  });

  // Review Findings Fix（Minor、4.2章）——Counter応答UIも同様に、
  // 「overflowしない」だけでなく「重要情報へ実際に到達できる」ことを
  // 実座標のintersection／scroll reachabilityで検証する。
  group('Mobile Visibility — Counter UI（Review Findings Fix、4.2章）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 780);

      testWidgets(
        '情報量最大級のincoming Technique（ROUGH+FINISHER·PIN+family/group '
        '+DMG+HEAT+posture）: ${width.toInt()}px幅でCounter応答UIの主要要素へ'
        '実際に到達できる',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.counterResponsePending,
              isHumanInputRequired: true,
              human: testHumanStatus(
                hand: [
                  // Review Findings Fix（Minor、4.2章）: `_maxInfoTechnique`
                  // （family: driver）を実際に返せるCounterを使う——既定の
                  // `testCounterCard()`（family: elbowのみ対応）では
                  // family/group informationが描画されない。
                  CombatV1PlayableHandCard(
                    instanceId: 'c1',
                    cardId: _maxInfoMatchingCounter.id,
                    category: CombatV1CardCategory.counter,
                    displayName: _maxInfoMatchingCounter.name,
                    isUsable: true,
                    counter: _maxInfoMatchingCounter,
                  ),
                  testTechniqueCard(instanceId: 'h1'),
                ],
              ),
              pendingAttack: testPendingAttack(technique: _maxInfoTechnique),
              legalActions: const [
                CombatV1CounterAction(
                  actorPlayerIndex: 0,
                  cardInstanceId: 'c1',
                ),
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

            final viewportRect = Offset.zero & size;

            // 到達確認: viewport内に無ければ、まずsheet内をscrollして
            // 到達させてから確認する（旧実装でclipされたままgreenになる
            // testにしない）。
            Future<void> expectReachable(Finder finder, String label) async {
              expect(finder, findsOneWidget, reason: '$labelが見つからない');
              var rect = tester.getRect(finder);
              if (!rect.overlaps(viewportRect)) {
                await tester.scrollUntilVisible(
                  finder,
                  100,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.pumpAndSettle();
                rect = tester.getRect(finder);
              }
              expect(
                rect.overlaps(viewportRect),
                isTrue,
                reason: '$labelへ到達できない: rect=$rect, viewport=$viewportRect',
              );
            }

            // incoming summary（DMG/HEAT/posture結果）。
            await expectReachable(
              find.byKey(const Key('combat_v1_playable_pending_effect_line')),
              'incoming summary',
            );
            // Counter prevents explanation。
            await expectReachable(
              find.byKey(
                const Key('combat_v1_playable_pending_counter_prevents_hint'),
              ),
              'Counter prevents explanation',
            );
            // ROUGH consequence（非対称性note）。
            await expectReachable(
              find.byKey(
                const Key('combat_v1_playable_pending_rough_counter_note'),
              ),
              'ROUGH consequence note',
            );
            // family/group information（usable Counter card側）。
            await expectReachable(
              find.byKey(
                const Key('combat_v1_playable_counter_family_match'),
              ),
              'Counter card family/group information',
            );
            // Counter card information（Counter card自体）。
            await expectReachable(
              find.byKey(
                const Key('combat_v1_playable_counter_card_c1'),
              ),
              'Counter card',
            );
            // decline / receive action。
            await expectReachable(
              find.byKey(
                const Key('combat_v1_playable_counter_decline_button'),
              ),
              'decline button',
            );
            // Counter action（Play Counter button）。
            await expectReachable(
              find.byKey(
                const Key('combat_v1_playable_counter_play_button'),
              ),
              'Play Counter button',
            );
          }, size: size);
        },
      );
    }
  });

  // Playable 2A-4「Match Flow / Result Feedback Readability」——Latest
  // Result（primary/secondary）の再設計により表示内容量が変わったため、
  // 代表ケース3種（15章 Mobile test strategy）で320/360/390px幅の
  // overflowと実際のreachabilityを確認する。
  group('Latest Result Reachability（Playable 2A-4 追加）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 780);

      testWidgets(
        '1. long Technique result（FINISHER） + Direction secondary + '
        'recent logs: ${width.toInt()}px幅でoverflowせず、末尾のrecent logへ'
        '到達できる',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            // Direction primary+secondaryとも表示される代表状態（相手KOC0
            // ＝decisiveKoc、既存「Match Direction Reachability」groupと
            // 同じ方針）。postureはstandのまま——CPU DOWNにするとGuidance
            // panel（capped scroll領域の外、固定領域）の補足文言が伸び、
            // このシナリオが検証したいLatest Result側の内容量とは無関係な
            // 既存レイアウトの余白不足を誘発してしまうため、既存の
            // 検証済み構成に揃える。
            final cpu = testCpuStatus(
              hp: 20,
              koc: 0,
              posture: CombatV1WrestlerPosture.stand,
            );
            // 複数行になる（damage/HP/posture/HEAT全て変化する）長い
            // FINISHER feedback。
            final latest = testActionFeedback(
              actionIndex: 4,
              actorPlayerIndex: 0,
              actionDisplayName: 'テスト最大情報量ダイレクトピンフィニッシャー・ドライバー',
              damage: 60,
              isFinisher: true,
              hpOwnerPlayerIndex: 1,
              hpBefore: 80,
              hpAfter: 20,
              postureOwnerPlayerIndex: 1,
              postureBefore: CombatV1WrestlerPosture.stand,
              postureAfter: CombatV1WrestlerPosture.down,
              heatBefore: 150,
              heatAfter: 200,
            );
            final older = [
              for (var i = 0; i < 5; i++)
                testActionFeedback(
                  actionIndex: i,
                  actorPlayerIndex: i.isEven ? 0 : 1,
                  actionDisplayName: 'テスト技目録その$i番',
                  damage: 10 + i,
                ),
            ];
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              cpu: cpu,
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
              latestFeedback: latest,
              recentFeedback: [...older, latest],
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
            await _expandDetail(tester);

            expect(
              find.byKey(
                const Key('combat_v1_playable_latest_feedback_primary'),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(
                const Key('combat_v1_playable_latest_feedback_secondary'),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(
                const Key('combat_v1_playable_match_direction_primary'),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(
                const Key('combat_v1_playable_match_direction_secondary'),
              ),
              findsOneWidget,
            );

            const scrollKey = Key('combat_v1_playable_actor_recent_scroll');
            const lastLogItemKey = Key(
              'combat_v1_playable_recent_log_item_3',
            );
            expect(find.byKey(lastLogItemKey), findsOneWidget);

            var viewportRect = tester.getRect(find.byKey(scrollKey));
            var itemRect = tester.getRect(find.byKey(lastLogItemKey));
            if (!itemRect.overlaps(viewportRect)) {
              await tester.drag(find.byKey(scrollKey), const Offset(0, -400));
              await tester.pumpAndSettle();
            }
            viewportRect = tester.getRect(find.byKey(scrollKey));
            itemRect = tester.getRect(find.byKey(lastLogItemKey));
            expect(
              itemRect.overlaps(viewportRect),
              isTrue,
              reason:
                  '末尾のrecent logへ到達できない: item=$itemRect, '
                  'viewport=$viewportRect',
            );
          }, size: size);
        },
      );

      testWidgets(
        '2. Counter result（DirectPin/Submission/ROUGH全部防いだ長い'
        'secondary） + Technique/EndTurn control: ${width.toInt()}px幅で'
        'overflowせず、Latest Result primary/secondaryへ実際に到達でき、'
        'End Turnが実際にhit-testできる（Review Findings Fix、Minor）',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final latest = testActionFeedback(
              kind: CombatV1PlayableFeedbackKind.counterPlayed,
              actorPlayerIndex: 0,
              actionDisplayName: 'テスト投げ技カウンター',
              relatedActionDisplayName:
                  'テスト最大情報量ダイレクトピンフィニッシャー・ドライバー',
              preventedDirectPin: true,
              preventedSubmissionHold: true,
              preventedIsRough: true,
            );
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
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
              latestFeedback: latest,
              recentFeedback: [latest],
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
            expect(tester.takeException(), isNull);
            await _expandDetail(tester);

            // Review Findings Fix（Minor、13章）: widgetの存在確認だけでは
            // なく、実際のclip viewport（Latest Result primary/secondaryが
            // 属する`combat_v1_playable_actor_recent_scroll`、高さ上限
            // 132pxのSingleChildScrollView）とのintersectionを検証する
            // ——`findsOneWidget`だけでは、実際にはscroll clipで見えない
            // 状態でもgreenになってしまう（14章）。
            const scrollKey = Key('combat_v1_playable_actor_recent_scroll');
            const primaryKey = Key(
              'combat_v1_playable_latest_feedback_primary',
            );
            const secondaryKey = Key(
              'combat_v1_playable_latest_feedback_secondary',
            );
            expect(find.byKey(primaryKey), findsOneWidget);
            expect(find.byKey(secondaryKey), findsOneWidget);

            Future<void> expectReachableInScroll(Key key, String label) async {
              final finder = find.byKey(key);
              var viewportRect = tester.getRect(find.byKey(scrollKey));
              var rect = tester.getRect(finder);
              if (!rect.overlaps(viewportRect)) {
                // 初期scroll位置では見えない場合、実際にdragしてから
                // 再検証する（14章「1. scroll前はviewport外 2. drag 3.
                // scroll後にintersection」）。
                await tester.drag(
                  find.byKey(scrollKey),
                  const Offset(0, -400),
                );
                await tester.pumpAndSettle();
                viewportRect = tester.getRect(find.byKey(scrollKey));
                rect = tester.getRect(finder);
              }
              expect(
                rect.overlaps(viewportRect),
                isTrue,
                reason:
                    '$labelへ実際に到達できない: rect=$rect, '
                    'viewport=$viewportRect',
              );
            }

            await expectReachableInScroll(primaryKey, 'Latest Result primary');
            await expectReachableInScroll(
              secondaryKey,
              'Latest Result secondary',
            );

            // Primary control（End Turn button）とTechnique hand cardが
            // viewport内にあり、hit-testableであることを確認する
            // ——Latest Resultの内容量が増えても、下部固定領域
            // （Human status panel/Primary actions bar）は常にscroll不要で
            // 画面内へ収まる既存レイアウトを維持する（design doc「17章」）。
            final screenRect = Offset.zero & size;
            final endTurnFinder = find.byKey(
              const Key('combat_v1_playable_action_end_turn'),
            );
            expect(endTurnFinder, findsOneWidget);
            expect(
              screenRect.contains(tester.getRect(endTurnFinder).center),
              isTrue,
            );

            // Review Findings Fix（Minor、15章）: Technique cardは画面全体
            // ではなく、実際のTechnique scroll viewport
            // （`combat_v1_playable_technique_area_scroll`、2A-3で確立した
            // observability）と比較する。
            final handCardFinder = find.byKey(
              const Key('combat_v1_playable_hand_card_h1'),
            );
            expect(handCardFinder, findsOneWidget);
            final techniqueViewportRect = tester.getRect(
              find.byKey(
                const Key('combat_v1_playable_technique_area_scroll'),
              ),
            );
            expect(
              tester.getRect(handCardFinder).overlaps(techniqueViewportRect),
              isTrue,
            );

            // Review Findings Fix（Minor、16章）: centerがscreen内である
            // ことの確認だけでなく、実際にEnd Turnをtapし、期待する
            // state変化（実際にsubmitHumanActionへendTurn actionが渡る
            // こと）までassertする。
            await tester.tap(endTurnFinder);
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(session.submitCalls, isNotEmpty);
            expect(
              session.submitCalls.last.action.kind,
              CombatV1LegalActionKind.endTurn,
            );
          }, size: size);
        },
      );

      testWidgets(
        '3. PIN/SUBMISSION result（Result overlay内）: ${width.toInt()}px幅で'
        'overflowせず、Rematch/Backへ到達できる',
        (tester) async {
          await _withNarrowViewport(tester, () async {
            final terminalFeedback = testActionFeedback(
              kind: CombatV1PlayableFeedbackKind.pinResolved,
              actorPlayerIndex: 0,
              actionDisplayName: null,
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
            final terminalSession = FakePlayableMatchSession(
              snapshot,
              result: testResult(
                status: CombatV1PlayableControllerStatus.matchOver,
                terminalCause: CombatV1MatchTerminalCause.normalPin,
                winnerPlayerIndex: 0,
              ),
            );
            // Review Findings Fix（Minor、16章）: Rematchを実際にtapした際、
            // `_startNewMatch`が`sessionFactory`を再度呼び出す
            // ——2回目以降の呼び出しでは非terminalなsessionを返すように
            // scriptedし、「Rematchをtapすると実際に新しい試合へ遷移する
            // （Result overlayが消える）」という期待state変化を検証できる
            // ようにする。
            final rematchSession = FakePlayableMatchSession(testSnapshot());
            var sessionFactoryCallCount = 0;
            await tester.pumpWidget(
              _wrap(
                CombatV1PlayableMatchScreen(
                  humanWrestlerId: 'akari',
                  cpuWrestlerId: 'reina',
                  cpuDelay: Duration.zero,
                  sessionFactory: (_) {
                    sessionFactoryCallCount += 1;
                    return sessionFactoryCallCount == 1
                        ? terminalSession
                        : rematchSession;
                  },
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            final overlayFinder = find.byKey(
              const Key('combat_v1_playable_result_overlay'),
            );
            expect(overlayFinder, findsOneWidget);
            final terminalFeedbackFinder = find.descendant(
              of: overlayFinder,
              matching: find.byKey(
                const Key('combat_v1_playable_result_terminal_feedback'),
              ),
            );
            expect(terminalFeedbackFinder, findsOneWidget);

            // Review Findings Fix（Minor、17章）: overlay内のLatest Result
            // primary/secondaryについても、overlay自身の実viewport
            // （`Positioned.fill`によりoverlay containerは画面全体を覆う）
            // とのintersectionを検証する——findsOneWidgetだけで済ませない。
            final overlayViewportRect = tester.getRect(overlayFinder);
            final overlayScrollableFinder = find
                .descendant(of: overlayFinder, matching: find.byType(Scrollable))
                .first;

            Future<void> expectReachableInOverlay(Finder finder, String label) async {
              expect(finder, findsOneWidget, reason: '$labelが見つからない');
              var rect = tester.getRect(finder);
              if (!rect.overlaps(overlayViewportRect)) {
                // 長文で初期position外の場合、overlay内をscrollしてから
                // 再検証する（17章「scroll前→drag→scroll後」）。
                await tester.scrollUntilVisible(
                  finder,
                  50,
                  scrollable: overlayScrollableFinder,
                );
                await tester.pumpAndSettle();
                rect = tester.getRect(finder);
              }
              expect(
                rect.overlaps(overlayViewportRect),
                isTrue,
                reason:
                    '$labelへ実際に到達できない: rect=$rect, '
                    'viewport=$overlayViewportRect',
              );
            }

            await expectReachableInOverlay(
              find.descendant(
                of: terminalFeedbackFinder,
                matching: find.byKey(
                  const Key('combat_v1_playable_latest_feedback_primary'),
                ),
              ),
              'terminal Latest Result primary',
            );
            final terminalSecondaryFinder = find.descendant(
              of: terminalFeedbackFinder,
              matching: find.byKey(
                const Key('combat_v1_playable_latest_feedback_secondary'),
              ),
            );
            if (terminalSecondaryFinder.evaluate().isNotEmpty) {
              await expectReachableInOverlay(
                terminalSecondaryFinder,
                'terminal Latest Result secondary',
              );
            }

            final screenRect = Offset.zero & size;
            final rematchFinder = find.byKey(
              const Key('combat_v1_playable_result_rematch_button'),
            );
            final backFinder = find.byKey(
              const Key('combat_v1_playable_result_back_button'),
            );
            expect(rematchFinder, findsOneWidget);
            expect(backFinder, findsOneWidget);
            expect(
              screenRect.contains(tester.getRect(rematchFinder).center),
              isTrue,
            );
            expect(
              screenRect.contains(tester.getRect(backFinder).center),
              isTrue,
            );

            // Review Findings Fix（Minor、16章）: centerがscreen内である
            // ことの確認だけでなく、実際にRematchをtapし、期待するUI
            // 変化（terminal状態が解消されResult overlayが消えること）
            // までassertする。
            await tester.tap(rematchFinder);
            await tester.pump();
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.byKey(const Key('combat_v1_playable_result_overlay')),
              findsNothing,
              reason: 'Rematchをtapしても新しい試合へ遷移しなかった'
                  '（Result overlayが消えない）',
            );
          }, size: size);
        },
      );
    }
  });
}
