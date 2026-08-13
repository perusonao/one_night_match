// Combat Ver.1 Playable 1C.1 — Energy / Counter / DOWN / PIN Clarity
// widget test（lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart）。
//
// Production UX検証で未解消/部分解消だった4項目（B. Energy／C.
// Counter／D. DOWN対象／E. PIN）を、実Engineを経由しないscripted
// snapshot（`combat_v1_playable_ui_test_fixtures.dart`）で検証する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

CombatV1PlayableMatchScreen _screen(
  FakePlayableMatchSession session, {
  String humanWrestlerId = 'akari',
  String cpuWrestlerId = 'reina',
}) => CombatV1PlayableMatchScreen(
  humanWrestlerId: humanWrestlerId,
  cpuWrestlerId: cpuWrestlerId,
  cpuDelay: Duration.zero,
  sessionFactory: (_) => session,
);

/// Playable 2A-5 Review Findings Fix「3章 Compact Hand」——一覧
/// （hand card自身）はcompact表示になり、DMG/HEAT/Energy比較/posture/
/// 使用不可理由は選択後の`_SelectedTechniquePanel`（hand直下）へ移動
/// した。これらの詳細を検証するtestは、まずcardをtapして選択する。
Future<void> _selectHandCard(WidgetTester tester, String instanceId) async {
  await tester.tap(
    find.byKey(Key('combat_v1_playable_hand_card_$instanceId')),
  );
  await tester.pump();
}

/// 相手がSTANDの時のみ使用可・成立後は相手をDOWNにする、通常のテスト技。
const CombatV1Technique testTechniqueRequiresStandResultsDown = CombatV1Technique(
  id: 'test_requires_stand_results_down',
  name: 'テストスラム',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
  damage: 30,
  heatGain: 10,
  family: CombatV1TechniqueFamily.slam,
  requiredOpponentState: CombatV1WrestlerPosture.stand,
  resultOpponentState: CombatV1WrestlerPosture.down,
);

/// 相手がDOWNの時のみ使用可能な（グラウンド）テスト技。状態変化なし。
const CombatV1Technique testTechniqueRequiresDownNoResult = CombatV1Technique(
  id: 'test_requires_down_no_result',
  name: 'テストグラウンド技',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
  damage: 15,
  heatGain: 5,
  family: CombatV1TechniqueFamily.armbar,
  requiredOpponentState: CombatV1WrestlerPosture.down,
);

void main() {
  group('B. Energy（section 7〜13、MUST）', () {
    testWidgets('Match画面にHumanのTechnique Energyパネルが常時表示される', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          energyPool: const CombatV1EnergyPool({
            CombatV1EnergyAttribute.strike: 5,
            CombatV1EnergyAttribute.throwing: 3,
          }),
          availableEnergy: const {
            CombatV1EnergyAttribute.strike: 2,
            CombatV1EnergyAttribute.throwing: 3,
          },
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_energy_panel')),
        findsOneWidget,
      );
      expect(find.textContaining('Technique Energy'), findsOneWidget);
      // 使用可能量／保有量の両方を表示する（「消費されるが自ターン開始時に
      // 全回復する」ことが画面から読み取れるように）。
      expect(find.textContaining('打 2/5'), findsOneWidget);
      expect(find.textContaining('投 3/3'), findsOneWidget);
    });

    testWidgets('保有量0の属性はEnergyパネルに表示しない', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          energyPool: const CombatV1EnergyPool({
            CombatV1EnergyAttribute.strike: 5,
            CombatV1EnergyAttribute.rough: 0,
          }),
          availableEnergy: const {
            CombatV1EnergyAttribute.strike: 5,
            CombatV1EnergyAttribute.rough: 0,
          },
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(find.textContaining('ラフ'), findsNothing);
    });

    testWidgets('技cardにCostと現在Energyの比較表示がある（Cost/Your Energy）', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: testTechniqueRequiresStandResultsDown,
              isUsable: true,
            ),
          ],
          energyPool: const CombatV1EnergyPool({
            CombatV1EnergyAttribute.throwing: 5,
          }),
          availableEnergy: const {CombatV1EnergyAttribute.throwing: 4},
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();
      // Playable 2A-5 Review Findings Fix「3章」——Cost/現在Energyの
      // 比較は選択後の`_SelectedTechniquePanel`（必要Energy/現在Energyを
      // 別々の行で表示）が担当する。
      await _selectHandCard(tester, 'h1');

      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_required_energy',
                ),
              ),
            )
            .data,
        contains('投2'),
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_current_energy',
                ),
              ),
            )
            .data,
        contains('投4'),
      );
    });

    testWidgets(
      'Cost比較表示は＊(wild)使用可能量を分母へ含める'
      '（GitHub Codex App Finding、PR #22）',
      (tester) async {
        // Cost 投2に対し、具体的な投の使用可能量は1のみだが＊が1あるため、
        // 技は実際には使用可能（isUsable==true、TECHNIQUE支払いは常に
        // wild補完を許可する——docs/combat_rules_v1.md 5.1章）。
        // 分母が具体属性のみ（1）だと支払い不可能に見えてしまうため、
        // ＊込みの2（1+1）が表示されなければならない。
        final snapshot = testSnapshot(
          phase: CombatV1MatchPhase.action,
          human: testHumanStatus(
            hand: [
              testTechniqueCard(
                instanceId: 'h1',
                technique: testTechniqueRequiresStandResultsDown,
                isUsable: true,
              ),
            ],
            energyPool: const CombatV1EnergyPool({
              CombatV1EnergyAttribute.throwing: 1,
              CombatV1EnergyAttribute.wild: 1,
            }),
            availableEnergy: const {
              CombatV1EnergyAttribute.throwing: 1,
              CombatV1EnergyAttribute.wild: 1,
            },
          ),
          legalActions: const [
            CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
            CombatV1EndTurnAction(actorPlayerIndex: 0),
          ],
        );
        await tester.pumpWidget(
          _wrap(_screen(FakePlayableMatchSession(snapshot))),
        );
        await tester.pump();
        await _selectHandCard(tester, 'h1');

        // 具体属性のみ（誤った表示）ではなく、＊込みの数値（1+1=2）が
        // 「現在Energy」行に表示される。
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const Key(
                    'combat_v1_playable_selected_technique_current_energy',
                  ),
                ),
              )
              .data,
          contains('投2'),
        );
        // isUsable==trueのままなので「Energy不足」表示は出ない。
        expect(find.textContaining('Energy不足'), findsNothing);
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const Key(
                    'combat_v1_playable_selected_technique_usable_status',
                  ),
                ),
              )
              .data,
          '使用可能',
        );
      },
    );

    testWidgets('ENERGY不足で使用不可な場合、Core Engineと同じ支払いロジックで安全に理由を表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: testTechniqueRequiresStandResultsDown,
              isUsable: false,
            ),
          ],
          energyPool: const CombatV1EnergyPool({
            CombatV1EnergyAttribute.throwing: 5,
          }),
          // Cost 投2に対し、使用可能なのは投1・wildも無し→支払い不可。
          availableEnergy: const {CombatV1EnergyAttribute.throwing: 1},
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();
      await _selectHandCard(tester, 'h1');

      expect(find.textContaining('Energy不足: 投2 / 1'), findsOneWidget);
    });

    testWidgets('支払い可能なのにisUsable==falseの場合はEnergy不足と断定しない', (tester) async {
      // Core Engineのresolveエネルギー計算では支払える（投2 <= 使用可能5）が、
      // 何らかの別理由（posture等）でisUsable==falseになっているケース——
      // UI側は安全に判定できないため汎用メッセージに留める。
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: testTechniqueRequiresStandResultsDown,
              isUsable: false,
            ),
          ],
          energyPool: const CombatV1EnergyPool({
            CombatV1EnergyAttribute.throwing: 5,
          }),
          availableEnergy: const {CombatV1EnergyAttribute.throwing: 5},
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();
      await _selectHandCard(tester, 'h1');

      expect(find.textContaining('Energy不足'), findsNothing);
      expect(find.textContaining('現在は使用できません'), findsOneWidget);
    });

    testWidgets('Shared HEATとTechnique Energyは別セクションで表示される', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        sharedHeat: 40,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_heat_status')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_playable_energy_panel')),
        findsOneWidget,
      );
    });

    testWidgets('CPU側のTechnique Energyは一切公開されない（Hidden Information）', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      // `_EnergyPanel`はHuman専用の1件のみ存在する
      // （`CombatV1PlayableOpponentStatus`自体がenergy fieldを持たない
      // ため、CPU用のEnergyパネルは構造的に構築不可能）。
      expect(
        find.byKey(const Key('combat_v1_playable_energy_panel')),
        findsOneWidget,
      );
    });
  });

  group('C. COUNTER（section 14〜17、MUST）', () {
    testWidgets('通常Action中のCOUNTER cardはdisabledでも用途が説明される', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          hand: [testCounterCard(instanceId: 'c1', isUsable: false)],
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      // compact hand card自体にも「COUNTER」表示はある（一覧段階）。
      expect(find.text('COUNTER'), findsWidgets);

      // 用途の説明（「相手の技を受ける時に使用」）は選択後のpanelが担当。
      await _selectHandCard(tester, 'c1');
      expect(find.text('相手の技を受ける時に使用'), findsOneWidget);
      // 「現在は使用できません」という無内容なメッセージは出さない。
      expect(find.text('現在は使用できません'), findsNothing);
    });

    testWidgets('COUNTER応答時は通常のカード選択と異なる状態であることを明示する', (tester) async {
      final pending = testPendingAttack(resultOpponentState: CombatV1WrestlerPosture.down);
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: pending,
        human: testHumanStatus(
          hand: [testCounterCard(instanceId: 'c1', isUsable: true)],
        ),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pumpAndSettle();

      expect(find.text('返し技を選択'), findsWidgets);
      // COUNTERの動的必要ENERGYが説明される（固定costではないことの明示）。
      expect(find.textContaining('COUNTERに必要なENERGY'), findsOneWidget);
    });
  });

  group('D. TECHNIQUE DOWN/STAND（section 18〜21、MUST）', () {
    testWidgets('技cardは相手への結果状態を対象を明示して表示する（相手 → DOWN）', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: testTechniqueRequiresStandResultsDown,
            ),
          ],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();
      // Playable 2A-5 Review Findings Fix「3章」——required/result
      // postureは選択後の`_SelectedTechniquePanel`が担当する。
      await _selectHandCard(tester, 'h1');

      expect(find.text('相手 → DOWN'), findsOneWidget);
      expect(find.text('相手がSTANDの時のみ使用可'), findsOneWidget);
      // 対象を示さない単独の`DOWN`表示は出さない。
      expect(find.text('DOWN'), findsNothing);
    });

    testWidgets('相手DOWN限定の技は必要状態を明示する（相手がDOWNの時のみ使用可）', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: testTechniqueRequiresDownNoResult,
            ),
          ],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();
      await _selectHandCard(tester, 'h1');

      expect(find.text('相手がDOWNの時のみ使用可'), findsOneWidget);
      // 状態変化なし（resultOpponentState==null）の技には結果状態行を
      // 出さない（推測しない）。
      expect(find.textContaining('相手 →'), findsNothing);
    });

    testWidgets('COUNTER応答中のpending攻撃は、対象がHuman自身であることを明示する（あなた → DOWN）', (
      tester,
    ) async {
      final pending = testPendingAttack(
        resultOpponentState: CombatV1WrestlerPosture.down,
      );
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: pending,
        human: testHumanStatus(
          hand: [testCounterCard(instanceId: 'c1', isUsable: true)],
        ),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('あなた → DOWN'), findsOneWidget);
    });
  });

  group('E. PIN（section 22〜28、MUST）', () {
    testWidgets('ambiguousな「PIN 2」は存在せず、「PIN Cards N」と明示される', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(pinCardsHeld: 2),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(find.text('PIN 2'), findsNothing);
      expect(
        find.byKey(const Key('combat_v1_playable_pin_cards_text')),
        findsWidgets,
      );
      expect(find.textContaining('PIN Cards 2'), findsWidgets);
    });

    testWidgets('PIN Cardsの近くに短い説明（tooltip）がある', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(pinCardsHeld: 2),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').contains('PINを仕掛ける'),
        ),
        findsWidgets,
      );
    });

    testWidgets('PIN buttonにPIN宣言条件の短い説明（tooltip）がある', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: 0),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_action_pin')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').contains('DOWN中の相手にPIN'),
        ),
        findsWidgets,
      );
    });

    testWidgets('KOCの説明はPIN/Submissionとの関係を明示する', (tester) async {
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              (w.message ?? '').contains('KICK OUT') &&
              (w.message ?? '').contains('Submission'),
        ),
        findsWidgets,
      );
    });

    testWidgets('用語ヘルプ（Energy/COUNTER/PIN/KOC/HEAT）をいつでも開ける', (tester) async {
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('combat_v1_playable_rules_help_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('用語ヘルプ'), findsOneWidget);
      expect(find.text('Technique Energy'), findsWidgets);
      expect(find.text('Shared HEAT'), findsOneWidget);
      expect(find.text('COUNTER'), findsWidgets);
      expect(find.text('PIN Cards'), findsWidgets);
      expect(find.text('KOC'), findsWidgets);
    });

    testWidgets(
      '用語ヘルプのKOC説明は「必要KOCを支払えない」ことを決着条件として説明する'
      '（Codex Review Major Finding、KOC==0ではない）',
      (tester) async {
        final snapshot = testSnapshot(
          legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
        );
        await tester.pumpWidget(
          _wrap(_screen(FakePlayableMatchSession(snapshot))),
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('combat_v1_playable_rules_help_button')),
        );
        await tester.pumpAndSettle();

        // 決着条件は「必要なKOCを支払えないこと」——PINのkickout
        // progressionでは要求costが段階ごとに変わりうる（例: remaining
        // KOC=2・required KOC=3でも3カウントになりうる）ため、KOC==0を
        // 決着条件だと誤解させる表現であってはならない。
        expect(
          find.textContaining('必要なKOCを支払えないと'),
          findsOneWidget,
        );
        // PIN（3カウント）・SUBMISSION（GIVE UP）双方に共通する説明で
        // あること。
        expect(find.textContaining('3カウント'), findsWidgets);
        expect(find.textContaining('GIVE UP'), findsWidgets);

        // 誤った「残量ゼロで決着」を意味する表現（旧文言）が存在しない
        // ことを回帰的に確認する。
        expect(find.textContaining('尽きると'), findsNothing);
      },
    );
  });
}
