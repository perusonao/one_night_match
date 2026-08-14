// Combat Ver.1 Playable 2A-5 — Card Interaction / Hand Readability widget
// test（lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart）。
//
// docs/design/combat_v1_playable_match_ui.md「Playable 2A-5」章を、実
// Engineを経由しないscripted snapshot（`combat_v1_playable_ui_test_
// fixtures.dart`）で検証する。既存2A-1〜2A-4 regression tests（Match
// Guidance/Match Direction/Technique Decision Traits/Latest Result
// Reachability等）は各既存ファイルに残したうえで、ここでは2A-5固有の
// 変更点だけを検証する：
//
// - Energy readability（必要Energy/現在Energyの並置表示）
// - Technique選択→直接実行（hand直下のinline panel）
// - Technique使用とdiscardのUI上の明確な分離
// - 日本語主要操作button
// - Hand visibility（通常ケースでscroll不要）
// - Guidance/Direction/Result/Logの圧縮（既定折りたたみ・明示操作で到達）
// - Counterの日本語操作
// - 320/360/390pxでの実座標hit-testability

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
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

bool _isEnabled(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
  return button.onPressed != null;
}

Future<void> _withViewport(
  WidgetTester tester,
  Future<void> Function() body, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await body();
}

/// テスト専用の高cost technique。`testEnergyPool`の打保有量は5、＊(wild)は
/// 1のため、実効使用可能量は6（`combatV1PlayableEffectiveAvailableEnergy`
/// と同じwild込み集計）。確実に不足させるため打7を要求する。
const CombatV1Technique _expensiveStrikeTechnique = CombatV1Technique(
  id: 'test_2a5_expensive_strike',
  name: 'テスト高コスト打撃',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 7}),
  damage: 25,
  heatGain: 15,
  family: CombatV1TechniqueFamily.elbow,
);

void main() {
  group('Energy Readability（6章）', () {
    testWidgets('選択したusable Techniqueは必要Energy・現在Energy・使用可能を並べて表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: testNormalTechnique,
              isUsable: true,
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

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      expect(
        find.byKey(
          const Key('combat_v1_playable_selected_technique_energy_block'),
        ),
        findsOneWidget,
      );
      final required = tester
          .widget<Text>(
            find.byKey(
              const Key(
                'combat_v1_playable_selected_technique_required_energy',
              ),
            ),
          )
          .data;
      final current = tester
          .widget<Text>(
            find.byKey(
              const Key(
                'combat_v1_playable_selected_technique_current_energy',
              ),
            ),
          )
          .data;
      // testNormalTechniqueは打1、testEnergyPoolの打保有量は5・＊(wild)は
      // 1（全量使用可能な既定状態）。「現在Energy」はwild込みの実効使用
      // 可能量（5+1=6）を表示する——`combatV1PlayableEnergyComparisonLabel`
      // と同じ集計（`combatV1PlayableEffectiveAvailableEnergy`）。
      expect(required, contains('打1'));
      expect(current, contains('打6'));

      final statusText = tester
          .widget<Text>(
            find.byKey(
              const Key('combat_v1_playable_selected_technique_usable_status'),
            ),
          )
          .data;
      expect(statusText, '使用可能');
    });

    testWidgets('Energy不足で選択したTechniqueはusable statusにEnergy不足の理由を表示し'
        'buttonをdisabledのままにする', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: _expensiveStrikeTechnique,
              isUsable: false,
            ),
          ],
        ),
        // isUsable:falseの技はlegalActionsにも現れない
        // （`_buildHumanStatus`のusableInstanceIds、SSOT一致）。
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      final statusText = tester
          .widget<Text>(
            find.byKey(
              const Key('combat_v1_playable_selected_technique_usable_status'),
            ),
          )
          .data;
      expect(statusText, contains('Energy不足'));

      final techniqueKey = const Key('combat_v1_playable_action_technique');
      expect(techniqueKey, isNotNull);
      final buttonFinder = find.byKey(techniqueKey);
      expect(buttonFinder, findsOneWidget);
      await tester.ensureVisible(buttonFinder);
      expect(_isEnabled(tester, techniqueKey), isFalse);
    });
  });

  group('Technique Selection → Direct Execution（5章）', () {
    testWidgets('カード選択直後はbuttonが存在せず、選択後にhand直下へ現れてtapで直接送信する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        revision: 4,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [testTechniqueCard(instanceId: 'h1', isUsable: true)],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_selected_technique_panel')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      final panel = find.byKey(
        const Key('combat_v1_playable_selected_technique_panel'),
      );
      expect(panel, findsOneWidget);
      // Technique名・買いhand card自体とpanelが近接している
      // （同じ`_TechniqueSelectionArea`のColumn内、hand直下）ことを、
      // panelのY座標がhand cardのY座標より下にあることで確認する。
      final handRect = tester.getRect(
        find.byKey(const Key('combat_v1_playable_hand_card_h1')),
      );
      final panelRect = tester.getRect(panel);
      expect(panelRect.top, greaterThanOrEqualTo(handRect.top));

      final buttonFinder = find.byKey(
        const Key('combat_v1_playable_action_technique'),
      );
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pump();

      expect(session.submitCalls, hasLength(1));
      expect(session.submitCalls.single.expectedRevision, 4);
      expect(
        session.submitCalls.single.action,
        const CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
      );
    });

    testWidgets('COUNTERカードを通常Action中に選択しても技buttonは出さず用途のみ案内する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [testCounterCard(instanceId: 'c1', isUsable: false)],
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_c1')));
      await tester.pump();

      final notice = find.byKey(
        const Key('combat_v1_playable_selected_counter_notice'),
      );
      expect(notice, findsOneWidget);
      expect(
        find.byKey(const Key('combat_v1_playable_action_technique')),
        findsNothing,
      );
      // hand card自身のdisabled messageとは別に、選択中panel側にも同じ
      // 安全な用途説明が出ることを、panelへscopeして確認する（hand card
      // 側の同文言と衝突しないように）。
      expect(
        find.descendant(
          of: notice,
          matching: find.textContaining('相手の技を受ける時に使用'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Technique使用とDiscardの明確な分離（7章）／Playable 2A-6「1・3章」', () {
    // Review Findings（Playable 2A-6、実プレイテスト由来）: Playable
    // 2A-5時点ではdiscard phaseのhand tileがDMG/HEAT/Energy/trait badgeを
    // 一切出さない設計だったが、「情報が無さすぎて捨てるカードを比較
    // できない」問題が判明した。そのため、Playable 2A-6でこれらを
    // 「技として使う場合の参考情報」として復元した——ただし「捨てる」
    // framing（別のverb label・色・selected文言）でTechnique compact
    // tileとは視覚的・文言的に区別する（design doc Playable 2A-6追記
    // 「1・3章」）。discard自体は手札の全カードが常にlegalであることは
    // 変わらない。
    testWidgets(
      'discard phaseのhand tileは「捨てる」framingでcategory/Energy/DMG/trait '
      'chipを参考情報として表示する',
      (tester) async {
        final snapshot = testSnapshot(
          phase: CombatV1MatchPhase.discard,
          isHumanInputRequired: true,
          human: testHumanStatus(
            hand: [
              testTechniqueCard(
                instanceId: 'h1',
                technique: testFinisherTechnique,
              ),
            ],
          ),
          legalActions: const [
            CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          ],
        );
        await tester.pumpWidget(
          _wrap(_screen(FakePlayableMatchSession(snapshot))),
        );
        await tester.pump();

        // discard専用tile key（discardModeで描画されていることの直接証跡）。
        final tileFinder = find.byKey(
          const Key('combat_v1_playable_discard_hand_card_h1'),
        );
        expect(tileFinder, findsOneWidget);
        // 「捨てる」framing（Technique compact tileには存在しないlabel）。
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.byKey(
              const Key('combat_v1_playable_discard_card_verb_label'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.byKey(
              const Key('combat_v1_playable_discard_card_energy_line'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.textContaining(
              'DMG ${testFinisherTechnique.damage}',
            ),
          ),
          findsOneWidget,
        );
        // 「技として使用可否」は捨てる可否とは無関係な参考情報として
        // 明示される。
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.byKey(
              const Key(
                'combat_v1_playable_discard_card_technique_usable_reference',
              ),
            ),
          ),
          findsOneWidget,
        );
        // Technique compact tile専用のusable icon key/trait badges keyは
        // discard tileには存在しない（別のtile実装であることの証跡）。
        expect(
          find.descendant(
            of: tileFinder,
            matching: find.byKey(
              const Key('combat_v1_playable_compact_card_usable_icon'),
            ),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('discardカード選択で「捨てるカード」パネルが現れ、名前が一致する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.discard,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(instanceId: 'h1', technique: testNormalTechnique),
          ],
        ),
        legalActions: const [
          CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_discard_confirm_panel')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_discard_confirm_panel')),
        findsOneWidget,
      );
      final selectedName = tester
          .widget<Text>(
            find.byKey(
              const Key('combat_v1_playable_discard_selected_card_name'),
            ),
          )
          .data;
      expect(selectedName, testNormalTechnique.name);
      // discard専用button（Technique buttonとは別key）が現れる。
      expect(
        find.byKey(const Key('combat_v1_playable_action_discard')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_playable_action_technique')),
        findsNothing,
      );
    });

    testWidgets('別のカードをtapすると捨てるカードの選択が切り替わる（変更）', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.discard,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: testNormalTechnique,
            ),
            testTechniqueCard(
              instanceId: 'h2',
              technique: testFinisherTechnique,
            ),
          ],
        ),
        legalActions: const [
          CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h2'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_discard_selected_card_name'),
              ),
            )
            .data,
        testNormalTechnique.name,
      );

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h2')));
      await tester.pump();
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_discard_selected_card_name'),
              ),
            )
            .data,
        testFinisherTechnique.name,
      );

      // 選択中のカードを再度tapすると選択解除——確認panelが消える
      // （キャンセル）。
      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h2')));
      await tester.pump();
      expect(
        find.byKey(const Key('combat_v1_playable_discard_confirm_panel')),
        findsNothing,
      );
    });

    testWidgets('discard確定tapで正しいCombatV1DiscardActionがcontrollerへ渡る', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        revision: 9,
        phase: CombatV1MatchPhase.discard,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [testTechniqueCard(instanceId: 'h1')],
        ),
        legalActions: const [
          CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      final button = find.byKey(const Key('combat_v1_playable_action_discard'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      expect(session.submitCalls, hasLength(1));
      expect(session.submitCalls.single.expectedRevision, 9);
      expect(
        session.submitCalls.single.action,
        const CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
      );
    });
  });

  group('Japanese Primary Actions（8章）', () {
    testWidgets('End Turn/Stand Up/Restは日本語、PINはそのまま', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: 0),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(find.text('ターン終了'), findsOneWidget);
      expect(find.text('PIN'), findsOneWidget);
      expect(find.text('End Turn'), findsNothing);
    });

    testWidgets('DOWN中はStand Up/Restが日本語で表示される', (tester) async {
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
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(find.text('立ち上がる'), findsOneWidget);
      expect(find.text('休む'), findsOneWidget);
      expect(find.text('Stand Up'), findsNothing);
      expect(find.text('Rest'), findsNothing);
    });

    testWidgets('Result overlayのRematch/Backは日本語（再戦・戻る）', (tester) async {
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.matchOver,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
      );
      final session = FakePlayableMatchSession(
        snapshot,
        result: testResult(winnerPlayerIndex: 0),
      );
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      expect(find.text('再戦'), findsOneWidget);
      expect(find.text('戻る'), findsOneWidget);
      expect(find.text('Rematch'), findsNothing);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('Counter promptのPlay/Declineは日本語（返し技を使う・返し技を使わない）', (
      tester,
    ) async {
      final pending = testPendingAttack();
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        pendingAttack: pending,
        human: testHumanStatus(hand: [testCounterCard(instanceId: 'c1')]),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('返し技を使う'), findsOneWidget);
      expect(find.text('返し技を使わない'), findsOneWidget);
      expect(find.text('Play Counter'), findsNothing);
    });
  });

  group('Guidance / Direction / Result / Logの圧縮（9章）', () {
    testWidgets('既定ではMatch Direction/Recent Logは折りたたまれ、toggleで展開できる', (
      tester,
    ) async {
      final feedback = testActionFeedback(
        actorPlayerIndex: 0,
        actionDisplayName: 'テスト技',
        damage: 10,
      );
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(koc: 0),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
        latestFeedback: feedback,
        recentFeedback: [feedback],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      // Guidance（Tier 3）は既定表示のまま。
      expect(
        find.byKey(const Key('combat_v1_playable_match_guidance_primary')),
        findsOneWidget,
      );
      // Direction/Latest banner/Recent log（Tier 4）は既定で折りたたみ。
      expect(
        find.byKey(const Key('combat_v1_playable_match_direction_primary')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('combat_v1_playable_latest_feedback_banner')),
        findsNothing,
      );
      // ただしLatest Resultのcompact 1行要約は残る（責務は消さない）。
      expect(
        find.byKey(
          const Key('combat_v1_playable_latest_feedback_compact_summary'),
        ),
        findsOneWidget,
      );

      final toggle = find.byKey(const Key('combat_v1_playable_detail_toggle'));
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_match_direction_primary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_playable_latest_feedback_banner')),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pump();
      expect(
        find.byKey(const Key('combat_v1_playable_match_direction_primary')),
        findsNothing,
      );
    });
  });

  group('Hand Visibility（4章）', () {
    for (final size in [
      const Size(320, 720),
      const Size(360, 780),
      const Size(390, 844),
    ]) {
      testWidgets(
        '${size.width.toInt()}×${size.height.toInt()}: 通常の1枚hand選択時、'
        'scroll前から手札cardの主要情報がviewport内にある',
        (tester) async {
          await _withViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              human: testHumanStatus(
                hand: [
                  testTechniqueCard(
                    instanceId: 'h1',
                    technique: testNormalTechnique,
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
              _wrap(_screen(FakePlayableMatchSession(snapshot))),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            final viewportRect = tester.getRect(
              find.byKey(
                const Key('combat_v1_playable_technique_area_scroll'),
              ),
            );
            // Playable 2A-5「4章 Hand Visibility」——通常の意思決定時
            // （1枚のみのhand）は、scrollしなくても技名・DMG/HEAT・
            // Energy行という主要な意思決定情報がすでにviewport内へ届いて
            // いることを、各要素の実座標とviewportのintersectionで確認
            // する（card全体の矩形ではなく、実際に読む必要がある行単位
            // で検証する——card下部のtrait detailまで無条件に見えている
            // 必要はない）。
            void expectVisible(Finder finder, String label) {
              final rect = tester.getRect(finder);
              expect(
                rect.overlaps(viewportRect),
                isTrue,
                reason:
                    '$labelがscroll前にviewport内へ届いていない: '
                    'rect=$rect, viewport=$viewportRect',
              );
            }

            expectVisible(
              find.text(testNormalTechnique.name),
              'Technique名',
            );
            expectVisible(
              find.textContaining('DMG ${testNormalTechnique.damage}'),
              'DMG/HEAT行',
            );
            expectVisible(
              find.byKey(const Key('combat_v1_playable_card_energy_line')),
              'Energy行',
            );
          }, size: size);
        },
      );
    }
  });

  group('320/360/390px — 実座標hit-testability（14章）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 780);

      testWidgets(
        '${width.toInt()}px: hand card選択→技buttonまで実tapで到達し、'
        '正しいLegalActionがsubmitされる',
        (tester) async {
          await _withViewport(tester, () async {
            final snapshot = testSnapshot(
              revision: 5,
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              human: testHumanStatus(
                hand: [testTechniqueCard(instanceId: 'h1', isUsable: true)],
              ),
              legalActions: const [
                CombatV1TechniqueAction(
                  actorPlayerIndex: 0,
                  cardInstanceId: 'h1',
                ),
                CombatV1EndTurnAction(actorPlayerIndex: 0),
              ],
            );
            final session = FakePlayableMatchSession(snapshot);
            await tester.pumpWidget(_wrap(_screen(session)));
            await tester.pump();

            final cardFinder = find.byKey(
              const Key('combat_v1_playable_hand_card_h1'),
            );
            final clipViewportRect = tester.getRect(
              find.byKey(
                const Key('combat_v1_playable_technique_area_scroll'),
              ),
            );
            final cardRect = tester.getRect(cardFinder);
            final visibleCardRect = cardRect.intersect(clipViewportRect);
            expect(visibleCardRect.width, greaterThan(0));
            expect(visibleCardRect.height, greaterThan(0));
            await tester.tapAt(visibleCardRect.center);
            await tester.pump();

            final buttonFinder = find.byKey(
              const Key('combat_v1_playable_action_technique'),
            );
            expect(buttonFinder, findsOneWidget);
            // Playable 2A-6「4章 Sticky Technique Action」——buttonは
            // もはや`combat_v1_playable_technique_area_scroll`の内側
            // ではなく、その外側（兄弟）に固定表示されるsticky footer
            // （`_TechniqueStickyActionBar`）の中にある。そのため
            // 「実際の画面viewport全体」に対してhit-testableであることを
            // 確認する（scrollしなくても既に画面内にあるはず、design doc
            // Playable 2A-6追記「4章」の中核要件）。
            await tester.pumpAndSettle();
            final screenRect =
                Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
            final buttonRect = tester.getRect(buttonFinder);
            final visibleButtonRect = buttonRect.intersect(screenRect);
            expect(visibleButtonRect.width, greaterThan(0));
            expect(visibleButtonRect.height, greaterThan(0));
            await tester.tapAt(visibleButtonRect.center);
            await tester.pump();

            expect(session.submitCalls, hasLength(1));
            expect(session.submitCalls.single.expectedRevision, 5);
            expect(
              session.submitCalls.single.action,
              const CombatV1TechniqueAction(
                actorPlayerIndex: 0,
                cardInstanceId: 'h1',
              ),
            );
          }, size: size);
        },
      );

      testWidgets(
        '${width.toInt()}px: discard card選択→確定buttonまで実tapで到達し、'
        '正しいLegalActionがsubmitされる',
        (tester) async {
          await _withViewport(tester, () async {
            final snapshot = testSnapshot(
              revision: 6,
              phase: CombatV1MatchPhase.discard,
              isHumanInputRequired: true,
              human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1')]),
              legalActions: const [
                CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
              ],
            );
            final session = FakePlayableMatchSession(snapshot);
            await tester.pumpWidget(_wrap(_screen(session)));
            await tester.pump();

            final cardFinder = find.byKey(
              const Key('combat_v1_playable_hand_card_h1'),
            );
            await tester.ensureVisible(cardFinder);
            await tester.pumpAndSettle();
            await tester.tap(cardFinder);
            await tester.pump();

            final buttonFinder = find.byKey(
              const Key('combat_v1_playable_action_discard'),
            );
            expect(buttonFinder, findsOneWidget);
            await tester.ensureVisible(buttonFinder);
            await tester.pumpAndSettle();
            await tester.tap(buttonFinder);
            await tester.pump();

            expect(session.submitCalls, hasLength(1));
            expect(session.submitCalls.single.expectedRevision, 6);
            expect(
              session.submitCalls.single.action,
              const CombatV1DiscardAction(
                actorPlayerIndex: 0,
                cardInstanceId: 'h1',
              ),
            );
          }, size: size);
        },
      );
    }
  });
}
