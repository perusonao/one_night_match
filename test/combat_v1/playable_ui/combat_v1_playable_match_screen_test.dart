// Combat Ver.1 Playable 1B — Match Screen widget test
// （lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart）。
//
// design doc「78〜83・85・86章」を、実Engineを経由しないscripted
// [FakePlayableMatchSession]（`combat_v1_playable_ui_test_fixtures.dart`）で
// 検証する。CPU loop・Counter promptは別ファイル
// （combat_v1_playable_match_screen_cpu_test.dart）を参照。

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

/// `_ActionButton`（private widget）配下の実際のbutton widgetから
/// enabled状態を読み取る（keyは`_ActionButton`自身に付与されているため、
/// `tester.widget<FilledButton>`の直接castは失敗する）。
bool _isButtonEnabled(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
  return button.onPressed != null;
}

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

void main() {
  group('Match Initial（78章）', () {
    testWidgets('Human/CPU status・hand・HEAT・actor・primary actionsを表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        sharedHeat: 40,
        finisherHeatThreshold: 200,
        human: testHumanStatus(
          wrestlerName: 'あかり',
          hp: 130,
          maxHp: 150,
          hand: [testTechniqueCard(instanceId: 'h1')],
        ),
        cpu: testCpuStatus(wrestlerName: 'れいな', hp: 150, maxHp: 150),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(find.byKey(const Key('combat_v1_playable_cpu_status_panel')), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_human_status_panel')), findsOneWidget);
      expect(find.text('あかり'), findsOneWidget);
      expect(find.text('れいな'), findsOneWidget);
      expect(find.textContaining('HP 130 / 150'), findsOneWidget);
      expect(find.textContaining('Shared HEAT 40'), findsOneWidget);
      expect(find.textContaining('Finisher Unlock 200'), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_human_hand')), findsOneWidget);
      expect(find.text('あなたのターン'), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_action_end_turn')), findsOneWidget);
    });
  });

  group('Discard（79章）', () {
    testWidgets('discard promptを表示し、card選択→submitでcontrollerへ渡す', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        revision: 3,
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

      expect(find.byKey(const Key('combat_v1_playable_discard_prompt')), findsOneWidget);
      // Technique等のprimary操作は見せない（discard専用button以外なし）。
      expect(find.byKey(const Key('combat_v1_playable_action_technique')), findsNothing);
      expect(find.byKey(const Key('combat_v1_playable_action_end_turn')), findsNothing);

      // Playable 2A-5「7章」——discardの確定操作は、カードを選ぶまで
      // 存在しない（hand直下のinline confirm panelとして選択後に現れる）。
      const discardKey = Key('combat_v1_playable_action_discard');
      expect(find.byKey(discardKey), findsNothing);
      expect(
        find.byKey(const Key('combat_v1_playable_discard_confirm_panel')),
        findsNothing,
      );

      // Playable 2A-3: Technique decision trait badge行の追加でhand card
      // 高さが232px→268pxへ拡張されたため、既定のtest viewport（800×600）
      // ではdiscard prompt文言込みでcardの一部がExpanded/scrollview領域の
      // 下端を越えうる。`ensureVisible`で実際にscrollしてから
      // tapする（実機でユーザーがscrollしてから操作するのと同じ）。
      final handCardFinder = find.byKey(
        const Key('combat_v1_playable_hand_card_h1'),
      );
      await tester.ensureVisible(handCardFinder);
      await tester.tap(handCardFinder);
      await tester.pump();

      // Playable 2A-5「7章」——選択後、「捨てるカード」を明示した
      // confirm panelがhand直下に現れる。
      expect(
        find.byKey(const Key('combat_v1_playable_discard_confirm_panel')),
        findsOneWidget,
      );
      final discardButtonFinder = find.byKey(discardKey);
      expect(discardButtonFinder, findsOneWidget);
      expect(_isButtonEnabled(tester, discardKey), isTrue);

      // Playable 2A-5「5・7章」——確認buttonはhand直下（selection panel
      // 内）にあり、既定のtest viewport（800×600）では画面外になりうる
      // ため、実機のscroll操作と同じくensureVisibleしてからtapする。
      await tester.ensureVisible(discardButtonFinder);
      await tester.tap(discardButtonFinder);
      await tester.pump();

      expect(session.submitCalls, hasLength(1));
      expect(session.submitCalls.single.expectedRevision, 3);
      expect(
        session.submitCalls.single.action,
        const CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
      );
    });
  });

  group('Technique（80章）', () {
    testWidgets('usable Techniqueをselect→executeでcontrollerへ正しいactionが渡る', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        revision: 7,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1', isUsable: true)]),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      // Playable 2A-5「5章」——Technique使用buttonは、カードを選ぶまで
      // 存在しない（hand直下のinline`_SelectedTechniquePanel`として
      // 選択後に現れる）。
      const techniqueKey = Key('combat_v1_playable_action_technique');
      expect(find.byKey(techniqueKey), findsNothing);
      expect(
        find.byKey(const Key('combat_v1_playable_selected_technique_panel')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_selected_technique_panel')),
        findsOneWidget,
      );
      final techniqueButtonFinder = find.byKey(techniqueKey);
      expect(techniqueButtonFinder, findsOneWidget);
      expect(_isButtonEnabled(tester, techniqueKey), isTrue);

      // Playable 2A-5「5章」——確認buttonはhand直下（selection panel
      // 内）にあり、既定のtest viewport（800×600）では画面外になりうる
      // ため、実機のscroll操作と同じくensureVisibleしてからtapする。
      await tester.ensureVisible(techniqueButtonFinder);
      await tester.tap(techniqueButtonFinder);
      await tester.pump();

      expect(session.submitCalls, hasLength(1));
      expect(session.submitCalls.single.expectedRevision, 7);
      expect(
        session.submitCalls.single.action,
        const CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
      );
    });

    testWidgets('unusable cardはdisabled styling・使用不可メッセージを表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1', isUsable: false)]),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();
      // Playable 2A-5 Review Findings Fix「3章」——使用不可の理由は
      // 選択後panelのusable status行が担当する。
      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      expect(find.text('現在は使用できません'), findsOneWidget);
    });
  });

  group('DOWN（82章）', () {
    testWidgets('Stand Up・Restのみを強調表示し、hand操作を抑制する', (tester) async {
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

      expect(find.byKey(const Key('combat_v1_playable_down_indicator')), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_action_stand_up')), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_action_rest')), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_action_technique')), findsNothing);
      expect(find.byKey(const Key('combat_v1_playable_action_end_turn')), findsNothing);
      expect(find.byKey(const Key('combat_v1_playable_human_hand')), findsNothing);
    });

    testWidgets('Stand Up tapでcontrollerへ渡る', (tester) async {
      final snapshot = testSnapshot(
        revision: 2,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1StandUpAction(actorPlayerIndex: 0),
          CombatV1RestAction(actorPlayerIndex: 0),
        ],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      await tester.tap(find.byKey(const Key('combat_v1_playable_action_stand_up')));
      await tester.pump();

      expect(session.submitCalls.single.action, const CombatV1StandUpAction(actorPlayerIndex: 0));
    });
  });

  group('PIN（83章）', () {
    testWidgets('legalならPIN buttonを表示する', (tester) async {
      final withPin = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: 0),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(_wrap(_screen(FakePlayableMatchSession(withPin))));
      await tester.pump();
      expect(find.byKey(const Key('combat_v1_playable_action_pin')), findsOneWidget);
    });

    testWidgets('非legalならPIN buttonを表示しない', (tester) async {
      final withoutPin = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(_wrap(_screen(FakePlayableMatchSession(withoutPin))));
      await tester.pump();
      expect(find.byKey(const Key('combat_v1_playable_action_pin')), findsNothing);
    });
  });

  group('Hidden Info（86章）', () {
    testWidgets('CPU hand contentsはWidget treeに一切存在しない', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'human-only-card')]),
        cpu: testCpuStatus(handCount: 5),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      // Human handは1枚だけ描画される。
      expect(find.byKey(const Key('combat_v1_playable_human_hand')), findsOneWidget);
      expect(
        find.byKey(const Key('combat_v1_playable_hand_card_human-only-card')),
        findsOneWidget,
      );
      // CPU hand用の別リストは存在しない（`CombatV1PlayableOpponentStatus`
      // はhandを一切公開しないため、構造的にrenderできない）。
      expect(find.textContaining('Hand 5'), findsOneWidget);
    });
  });

  group('Result overlay（85章）', () {
    testWidgets('matchOverでwinner/terminal cause/Rematch/Backを表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.matchOver,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
      );
      final session = FakePlayableMatchSession(
        snapshot,
        result: testResult(
          status: CombatV1PlayableControllerStatus.matchOver,
          winnerPlayerIndex: 0,
          terminalCause: null,
        ),
      );
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      expect(find.text('YOU WIN'), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_result_rematch_button')), findsOneWidget);
      expect(find.byKey(const Key('combat_v1_playable_result_back_button')), findsOneWidget);
    });

    testWidgets('safetyLimitはwinnerを表示せず専用文言のみ', (tester) async {
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.safetyLimit,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
      );
      final session = FakePlayableMatchSession(
        snapshot,
        result: testResult(
          status: CombatV1PlayableControllerStatus.safetyLimit,
          winnerPlayerIndex: null,
          terminalCause: null,
          safetyLimitReached: true,
        ),
      );
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      expect(find.text('Safety limit reached'), findsOneWidget);
      expect(find.text('YOU WIN'), findsNothing);
      expect(find.text('CPU WIN'), findsNothing);
    });

    testWidgets(
      'invariantViolationはwinnerがresultに残っていても表示しない（53章 Winner Display Guard）',
      (tester) async {
        final snapshot = testSnapshot(
          status: CombatV1PlayableControllerStatus.invariantViolation,
          isHumanInputRequired: false,
          currentActorPlayerIndex: null,
          legalActions: const [],
          diagnosticMessage: 'synthetic invariant violation',
        );
        final session = FakePlayableMatchSession(
          snapshot,
          // Playable 1A Known Minor B相当（winner fieldsがgateされずに
          // 残るケース）を模した、あえてwinnerPlayerIndexを埋めたresult。
          result: testResult(
            status: CombatV1PlayableControllerStatus.invariantViolation,
            winnerPlayerIndex: 0,
            terminalCause: null,
            invariantViolationMessage: 'synthetic invariant violation',
          ),
        );
        await tester.pumpWidget(_wrap(_screen(session)));
        await tester.pump();

        expect(
          find.text('Match stopped due to internal consistency error'),
          findsOneWidget,
        );
        expect(find.text('YOU WIN'), findsNothing);
        expect(find.text('CPU WIN'), findsNothing);
      },
    );

    testWidgets('error状態（result未構築）はdiagnosticMessageのみ表示', (tester) async {
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.error,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
        diagnosticMessage: 'synthetic executor failure',
      );
      final session = FakePlayableMatchSession(snapshot); // result == null
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      expect(
        find.text('Match stopped due to internal consistency error'),
        findsOneWidget,
      );
      expect(find.text('synthetic executor failure'), findsOneWidget);
      expect(find.text('YOU WIN'), findsNothing);
    });
  });
}
