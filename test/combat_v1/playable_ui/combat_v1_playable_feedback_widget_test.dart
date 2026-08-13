// Combat Ver.1 Playable 1C — Action Feedback / Context Help / Accessibility
// widget test（lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart
// 他）。
//
// docs/design/combat_v1_playable_match_ui.md「Playable 1C」章を、実Engineを
// 経由しないscripted `CombatV1PlayableActionFeedback`/synthetic snapshot
// （`combat_v1_playable_ui_test_fixtures.dart`）で検証する。

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_lifecycle.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_action_feedback.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_controller.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_setup_screen.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

void main() {
  group('Action Result Feedback banner（MUST）', () {
    testWidgets('Human technique feedbackが表示される（技名・damage・HP変化・HEAT変化）', (
      tester,
    ) async {
      final feedback = testActionFeedback(
        actorPlayerIndex: 0,
        actionDisplayName: 'ドロップキック',
        damage: 20,
        hpOwnerPlayerIndex: 1,
        hpBefore: 80,
        hpAfter: 60,
        postureOwnerPlayerIndex: 1,
        postureBefore: CombatV1WrestlerPosture.stand,
        postureAfter: CombatV1WrestlerPosture.down,
        heatBefore: 40,
        heatAfter: 60,
      );
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

      expect(
        find.byKey(const Key('combat_v1_playable_latest_feedback_banner')),
        findsOneWidget,
      );
      expect(find.textContaining('YOU'), findsWidgets);
      expect(find.textContaining('ドロップキック'), findsWidgets);
      expect(find.textContaining('20 DAMAGE'), findsOneWidget);
      expect(find.textContaining('HP 80 → 60'), findsOneWidget);
      expect(find.textContaining('STAND'), findsWidgets);
      expect(find.textContaining('DOWN'), findsWidgets);
      expect(find.textContaining('HEAT +20'), findsOneWidget);
    });

    testWidgets('CPU technique feedbackが表示される（damage・HP変化が追える）', (
      tester,
    ) async {
      final feedback = testActionFeedback(
        actorPlayerIndex: 1,
        actionDisplayName: 'ラリアット',
        damage: 15,
        hpOwnerPlayerIndex: 0,
        hpBefore: 100,
        hpAfter: 85,
        heatBefore: 10,
        heatAfter: 10,
      );
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

      expect(find.textContaining('CPU'), findsWidgets);
      expect(find.textContaining('ラリアット'), findsWidgets);
      expect(find.textContaining('15 DAMAGE'), findsOneWidget);
      expect(find.textContaining('HP 100 → 85'), findsOneWidget);
      // HEATが変化しない場合はHEAT行を出さない（推測でdeltaを埋めない）。
      expect(find.textContaining('HEAT +0'), findsNothing);
    });

    testWidgets('FINISHER成立feedbackは primaryに"FINISHER"を明示する'
        '（Playable 2A-4）', (tester) async {
      final feedback = testActionFeedback(
        actorPlayerIndex: 0,
        actionDisplayName: 'テストフィニッシャー',
        damage: 60,
        hpOwnerPlayerIndex: 1,
        hpBefore: 60,
        hpAfter: 0,
        isFinisher: true,
      );
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

      final primaryText = tester
          .widget<Text>(
            find.byKey(
              const Key('combat_v1_playable_latest_feedback_primary'),
            ),
          )
          .data;
      expect(primaryText, contains('FINISHER'));
      expect(find.textContaining('テストフィニッシャー'), findsWidgets);
      expect(find.textContaining('60 DAMAGE'), findsOneWidget);
    });

    testWidgets('ROUGH技へのCounter成立feedbackは非対称性の説明をsecondaryへ表示する'
        '（Playable 2A-4、86章と同じ事実）', (tester) async {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.counterPlayed,
        actorPlayerIndex: 0,
        actionDisplayName: 'テストカウンター',
        relatedActionDisplayName: 'テストラフ技',
        preventedIsRough: true,
      );
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

      final secondaryText = tester
          .widget<Text>(
            find.byKey(
              const Key('combat_v1_playable_latest_feedback_secondary'),
            ),
          )
          .data;
      expect(secondaryText, contains('cannot PIN this turn'));
      expect(secondaryText, contains('next-turn TECHNIQUE limit'));
    });

    // Playable 2A-4 Review Findings Fix（Major、Integration/Widget test）
    // ——`preventedDirectPin`/`preventedSubmissionHold`が実際に「Counterが
    // DIRECT PIN/SUBMISSION自動移行を防いだ」ことを意味する場合のみUI上に
    // 断定文言を出し、`false`（trait はあったがCore条件〈DOWN posture/
    // HP閾値〉を満たさなかったケースを含む）では出さないことを、
    // formatter単体テストだけでなくwidget tree（実際にrenderされる
    // Latest Result banner）まで通して確認する。production catalogには
    // DIRECT PIN traitを持つ技（FINISHER限定）のresultOpponentStateが
    // 全てDOWN固定のものしか存在しない
    // （`combat_v1_technique_catalog.dart`）ため、「traitはあるが
    // DOWNにならない」ケースは実データでは再現できない——controller側の
    // 判定自体は`combat_v1_playable_counter_prevention_test.dart`の
    // 純粋関数testで既にCore条件と直接照合済みなので、ここでは
    // controllerが実際にその判定結果（`preventedDirectPin == false`）を
    // 返した場合を想定したfeedbackで、formatterからwidget treeまでの
    // 経路が安全表現を保つことを確認する。
    testWidgets(
      'preventedDirectPin == true: Latest Resultに自動PIN移行を防いだ旨を表示する',
      (tester) async {
        final feedback = testActionFeedback(
          kind: CombatV1PlayableFeedbackKind.counterPlayed,
          actorPlayerIndex: 0,
          actionDisplayName: 'テストカウンター',
          relatedActionDisplayName: 'テストダイレクトピン技',
          preventedDirectPin: true,
        );
        final snapshot = testSnapshot(
          legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

        final secondaryText = tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_latest_feedback_secondary'),
              ),
            )
            .data;
        expect(secondaryText, contains('automatic PIN transition'));
      },
    );

    testWidgets(
      'preventedDirectPin == false: DIRECT PIN traitを持つ技へのCounterでも'
      '「自動PIN移行を防いだ」とはLatest Resultに表示しない'
      '（trait単独ではDOWN transitionを保証しないため）',
      (tester) async {
        final feedback = testActionFeedback(
          kind: CombatV1PlayableFeedbackKind.counterPlayed,
          actorPlayerIndex: 0,
          actionDisplayName: 'テストカウンター',
          relatedActionDisplayName: 'テストダイレクトピン技',
          preventedDirectPin: false,
        );
        final snapshot = testSnapshot(
          legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

        final secondaryText = tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_latest_feedback_secondary'),
              ),
            )
            .data;
        expect(secondaryText, isNot(contains('PIN')));
      },
    );

    testWidgets(
      'preventedSubmissionHold == true: Latest ResultにSUBMISSION移行条件を'
      '防いだ旨を表示する',
      (tester) async {
        final feedback = testActionFeedback(
          kind: CombatV1PlayableFeedbackKind.counterPlayed,
          actorPlayerIndex: 0,
          actionDisplayName: 'テストカウンター',
          relatedActionDisplayName: 'テストアームキャッチ',
          preventedSubmissionHold: true,
        );
        final snapshot = testSnapshot(
          legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

        final secondaryText = tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_latest_feedback_secondary'),
              ),
            )
            .data;
        expect(secondaryText, contains('SUBMISSION transition condition'));
      },
    );

    testWidgets(
      'preventedSubmissionHold == false: SUBMISSION traitを持つ技への'
      'Counterでも「SUBMISSION移行条件を防いだ」とはLatest Resultに表示しない'
      '（damage適用後HPが閾値を超えるケースを含む）',
      (tester) async {
        final feedback = testActionFeedback(
          kind: CombatV1PlayableFeedbackKind.counterPlayed,
          actorPlayerIndex: 0,
          actionDisplayName: 'テストカウンター',
          relatedActionDisplayName: 'テストアームキャッチ',
          preventedSubmissionHold: false,
        );
        final snapshot = testSnapshot(
          legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

        final secondaryText = tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_latest_feedback_secondary'),
              ),
            )
            .data;
        expect(secondaryText, isNot(contains('SUBMISSION')));
      },
    );

    testWidgets('latest feedbackは次のsnapshotが来るまで表示され続ける（persistence）', (
      tester,
    ) async {
      final firstFeedback = testActionFeedback(
        actorPlayerIndex: 0,
        actionDisplayName: '最初の技',
        damage: 10,
      );
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
        latestFeedback: firstFeedback,
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
      // pump()を複数回重ねても（時間経過を模しても）バナーは消えない。
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('最初の技'), findsWidgets);
    });
  });

  group('Latest Result — Guidance / Direction責務分離（Playable 2A-4）', () {
    testWidgets('Latest Resultは過去形の事実のみ——Guidanceが担当する'
        '「次に何をすべきか」の勧誘文言を含めない', (tester) async {
      // PINがlegalな局面（Guidanceが「PIN可能」を案内する状況）でも、
      // Latest Resultは直前に起きた事実（DOWNさせた技の結果）のみを
      // 述べる——「PINしましょう」等の提案はGuidance側の責務。
      final feedback = testActionFeedback(
        actorPlayerIndex: 0,
        actionDisplayName: 'テストスラム',
        damage: 20,
        postureOwnerPlayerIndex: 1,
        postureBefore: CombatV1WrestlerPosture.stand,
        postureAfter: CombatV1WrestlerPosture.down,
      );
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        cpu: testCpuStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: [
          const CombatV1PinAction(actorPlayerIndex: 0),
          const CombatV1EndTurnAction(actorPlayerIndex: 0),
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

      // GuidanceパネルとLatest Result primaryが両方存在し、別々の文字列
      // であること（同じ内容の二重表示ではない）。
      final guidancePrimary = tester
          .widget<Text>(
            find.byKey(
              const Key('combat_v1_playable_match_guidance_primary'),
            ),
          )
          .data;
      final resultPrimary = tester
          .widget<Text>(
            find.byKey(
              const Key('combat_v1_playable_latest_feedback_primary'),
            ),
          )
          .data;
      expect(guidancePrimary, isNotNull);
      expect(resultPrimary, isNotNull);
      expect(resultPrimary, isNot(equals(guidancePrimary)));
      // Latest Result側にGuidanceの提案語彙（PIN勧誘の動詞）が漏れていない。
      expect(resultPrimary!.toLowerCase(), isNot(contains('pin')));
    });
  });

  group('PIN Feedback（MUST）', () {
    testWidgets('PIN kickoutメッセージを表示する', (tester) async {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.pinResolved,
        actorPlayerIndex: 0,
        actionDisplayName: null,
        kocOwnerPlayerIndex: 1,
        kocBefore: 10,
        kocAfter: 7,
        pinOutcome: CombatV1PlayablePinFeedbackOutcome.kickOut,
      );
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
        latestFeedback: feedback,
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

      expect(find.textContaining('PIN ATTEMPT'), findsOneWidget);
      expect(find.textContaining('KICK OUT'), findsOneWidget);
      expect(find.textContaining('MATCH OVER'), findsNothing);
      // Kick outはterminalではないため、Result overlayは出ない
      // （Final Merge Gate Major fixがnon-terminal PINを壊していないことの
      // regression確認）。
      expect(
        find.byKey(const Key('combat_v1_playable_result_overlay')),
        findsNothing,
      );
    });

    testWidgets('PIN match-overメッセージを表示する（推測countなし・Result overlayの下に'
        '隠れず、overlay自身のcontentとして見える——Final Merge Gate Major fix）', (
      tester,
    ) async {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.pinResolved,
        actorPlayerIndex: 0,
        actionDisplayName: null,
        kocOwnerPlayerIndex: 1,
        kocBefore: 0,
        kocAfter: 0,
        pinOutcome: CombatV1PlayablePinFeedbackOutcome.matchOver,
      );
      // PIN/SUBMISSIONで決着すると同じsnapshotでstatus==matchOverと
      // なりResult overlayが全画面を覆う（production path）。
      // statusをactiveのままにするとResult overlay自体が出現せず、
      // 「overlayの下に隠れる」不具合を検出できないため、statusも
      // terminal状態に揃える。
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.matchOver,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
        latestFeedback: feedback,
      );
      final session = FakePlayableMatchSession(
        snapshot,
        result: testResult(
          status: CombatV1PlayableControllerStatus.matchOver,
          terminalCause: CombatV1MatchTerminalCause.normalPin,
          winnerPlayerIndex: CombatV1PlayableMatchController.humanPlayerIndex,
        ),
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

      final overlay = find.byKey(
        const Key('combat_v1_playable_result_overlay'),
      );
      expect(overlay, findsOneWidget);

      // terminal feedbackが、hidden layerのsiblingとしてではなく
      // Result overlay自身のcontent（子孫）としてrenderされていること。
      final terminalFeedback = find.descendant(
        of: overlay,
        matching: find.byKey(
          const Key('combat_v1_playable_result_terminal_feedback'),
        ),
      );
      expect(terminalFeedback, findsOneWidget);
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('PIN ATTEMPT'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('3 COUNT'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('MATCH OVER'),
        ),
        findsOneWidget,
      );
      // 「1」「2」「2.9」のようなカウント数値は一切表示しない。
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('1 COUNT'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('2 COUNT'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('2.9'),
        ),
        findsNothing,
      );

      // terminal feedbackと同じoverlay内で、winner/terminal causeも
      // 同時にvisibleであること（53章 Winner Display Guardと整合）。
      expect(
        find.descendant(of: overlay, matching: find.text('YOU WIN')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: overlay,
          matching: find.byKey(const Key('combat_v1_playable_result_cause')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Submission match-overメッセージがResult overlay自身のcontentとして'
        '見える（Final Merge Gate Major fix）', (tester) async {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        actorPlayerIndex: 0,
        actionDisplayName: 'テスト関節技',
        damage: 10,
        hpOwnerPlayerIndex: 1,
        hpBefore: 40,
        hpAfter: 30,
        heatBefore: 100,
        heatAfter: 110,
        submissionOutcome: CombatV1PlayableSubmissionFeedbackOutcome.matchOver,
      );
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.matchOver,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
        latestFeedback: feedback,
      );
      final session = FakePlayableMatchSession(
        snapshot,
        result: testResult(
          status: CombatV1PlayableControllerStatus.matchOver,
          terminalCause: CombatV1MatchTerminalCause.submission,
          winnerPlayerIndex: CombatV1PlayableMatchController.humanPlayerIndex,
        ),
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

      final overlay = find.byKey(
        const Key('combat_v1_playable_result_overlay'),
      );
      expect(overlay, findsOneWidget);

      final terminalFeedback = find.descendant(
        of: overlay,
        matching: find.byKey(
          const Key('combat_v1_playable_result_terminal_feedback'),
        ),
      );
      expect(terminalFeedback, findsOneWidget);
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('SUBMISSION'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('GIVE UP'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: terminalFeedback,
          matching: find.textContaining('MATCH OVER'),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(of: overlay, matching: find.text('YOU WIN')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: overlay,
          matching: find.byKey(const Key('combat_v1_playable_result_cause')),
        ),
        findsOneWidget,
      );
    });
  });

  group('KOC / HEAT Context Help（MUST）', () {
    testWidgets('KOCのcontext help（tooltip）が存在する', (tester) async {
      final snapshot = testSnapshot(
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').contains('Submission'),
        ),
        findsWidgets,
      );
    });

    testWidgets('HEATのcontext help（Shared/Finisher Unlock表記＋tooltip）が存在する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        sharedHeat: 120,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

      expect(find.textContaining('Shared HEAT 120'), findsOneWidget);
      expect(find.textContaining('Finisher Unlock 200'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').contains('共有'),
        ),
        findsWidgets,
      );
      // 上限を暗示する「120 / 200」progress表現は出さない。
      expect(find.textContaining('120 / 200'), findsNothing);
    });

    testWidgets('HEATが閾値を超えても自然に表示される（UNLOCKEDバッジ）', (tester) async {
      final snapshot = testSnapshot(
        sharedHeat: 360,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

      expect(find.textContaining('Shared HEAT 360'), findsOneWidget);
      expect(find.text('UNLOCKED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('FINISHER threshold hint（MUST）', () {
    testWidgets('finisher cardにHEAT要件hintを表示する', (tester) async {
      final snapshot = testSnapshot(
        sharedHeat: 40,
        finisherHeatThreshold: 200,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'f1',
              technique: testFinisherTechnique,
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

      expect(find.textContaining('Requires HEAT 200'), findsOneWidget);
      expect(find.textContaining('current 40'), findsOneWidget);
    });
  });

  group('Context Help（SHOULD）', () {
    testWidgets('Rest/Stand Upの説明が表示される（DOWN時）', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
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

      expect(
        find.byKey(const Key('combat_v1_playable_stand_up_hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_playable_rest_hint')),
        findsOneWidget,
      );
      expect(find.textContaining('立ち上がって'), findsOneWidget);
      expect(find.textContaining('HPを回復'), findsOneWidget);
    });

    testWidgets('discardの説明が表示される', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.discard,
        human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1')]),
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

      expect(
        find.byKey(const Key('combat_v1_playable_discard_hint')),
        findsOneWidget,
      );
    });

    testWidgets('handが複数枚ある場合、横スクロールcueを表示する', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(instanceId: 'h1'),
            testTechniqueCard(instanceId: 'h2'),
          ],
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
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

      expect(
        find.byKey(const Key('combat_v1_playable_hand_scroll_hint')),
        findsOneWidget,
      );
    });
  });

  group('Accessibility Semantics', () {
    testWidgets('Setup screen: wrestler selected/unselected semanticsが正しい', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(const CombatV1PlayableSetupScreen()));

      final selected = tester.getSemantics(
        find.byKey(
          const Key('combat_v1_playable_wrestler_choice_akari_selected'),
        ),
      );
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);

      // 'misaki'はHuman/CPU双方のpickerで未選択のため同じkeyが2箇所に
      // 存在する——Human picker側へscopeして曖昧さを排除する
      // （既存setup screen testと同じ方針）。
      final unselected = tester.getSemantics(
        find.descendant(
          of: find.byKey(const Key('combat_v1_playable_setup_human_picker')),
          matching: find.byKey(
            const Key('combat_v1_playable_wrestler_choice_misaki_unselected'),
          ),
        ),
      );
      expect(unselected.flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('Match screen: card selected/enabled/disabled semanticsが正しい', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(instanceId: 'usable', isUsable: true),
            testTechniqueCard(instanceId: 'unusable', isUsable: false),
          ],
        ),
        legalActions: const [
          CombatV1TechniqueAction(
            actorPlayerIndex: 0,
            cardInstanceId: 'usable',
          ),
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

      final usable = tester.getSemantics(
        find.byKey(const Key('combat_v1_playable_hand_card_usable')),
      );
      expect(usable.flagsCollection.isEnabled, Tristate.isTrue);
      expect(usable.flagsCollection.isSelected, Tristate.isFalse);

      final unusable = tester.getSemantics(
        find.byKey(const Key('combat_v1_playable_hand_card_unusable')),
      );
      expect(unusable.flagsCollection.isEnabled, Tristate.isFalse);

      await tester.tap(
        find.byKey(const Key('combat_v1_playable_hand_card_usable')),
      );
      await tester.pump();

      final selectedAfterTap = tester.getSemantics(
        find.byKey(const Key('combat_v1_playable_hand_card_usable')),
      );
      expect(selectedAfterTap.flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });
  });
}
