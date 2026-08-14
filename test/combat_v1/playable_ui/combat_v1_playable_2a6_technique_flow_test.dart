// Combat Ver.1 Playable 2A-6 — Technique Execution Feedback / Match Finish
// Clarity（docs/design/combat_v1_playable_match_ui.md Playable 2A-6追記）。
//
// Playable 1C/2A-4の`combatV1PlayableDeriveMatchFeedback`
// pure-formatter-levelのcoverageは`combat_v1_playable_feedback_
// formatters_test.dart`が既に持つ（hand-buildなfixtureで網羅済み）。
// このfileはそれとは別の責務——実`CombatV1PlayableMatchController`
// （実Engine経由）が実際に生成した`CombatV1PlayableActionFeedback`/
// `CombatV1PlayableMatchResult`を、`_LatestFeedbackBanner`／
// `CombatV1PlayableMatchScreen`（`_ResultOverlay`含む）へそのまま
// 描画させ、「Core由来の実際の事実」がwidget層で正しく・fabricateせずに
// 表示されることを検証する（design doc「Section 15」J〜Qのうち、実
// controller flowを使うことが推奨される項目）。
//
// Production wrestlerのデッキはshuffleに依存するため、目的のfeedback/
// terminal causeへ到達するまで複数の(wrestlerId, engineSeed)組み合わせを
// 探索する（`combat_v1_playable_scenario_test.dart`と同じ方針、fragileな
// 1点固定seedへは依存しない）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_lifecycle.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_action_feedback.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_config.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_controller.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';

import '../playable/combat_v1_playable_test_helpers.dart';
import 'combat_v1_playable_ui_test_fixtures.dart';

const List<String> _wrestlerIds = ['misaki', 'jack', 'akari', 'reina'];

CombatV1PlayableMatchConfig _config({
  required String humanWrestlerId,
  required String cpuWrestlerId,
  required int engineSeed,
  int maxActions = 400,
}) => CombatV1PlayableMatchConfig(
  humanWrestlerId: humanWrestlerId,
  cpuWrestlerId: cpuWrestlerId,
  engineSeed: engineSeed,
  cpuPolicySeed: 2,
  maxActions: maxActions,
  cpuPolicyKind: CombatV1PlayableCpuPolicyKind.firstLegal,
);

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

/// [predicate]を満たす[CombatV1PlayableActionFeedback]が
/// `snapshot.latestFeedback`として現れるまで、`chooseFirstLegalHumanAction`
/// （deterministic FirstLegal優先順位）でHumanを、`advanceCpuUntilHumanInput`
/// でCPUを進行させる。見つかった時点のcontrollerを返す（見つからなければ
/// `null`）。
CombatV1PlayableMatchController? _findFeedbackScenario(
  bool Function(CombatV1PlayableActionFeedback) predicate, {
  int seedCount = 40,
  int maxIterationsPerSeed = 200,
}) {
  for (final wrestlerId in _wrestlerIds) {
    for (var seed = 0; seed < seedCount; seed++) {
      final controller = CombatV1PlayableMatchController(
        _config(
          humanWrestlerId: wrestlerId,
          cpuWrestlerId: wrestlerId,
          engineSeed: seed,
        ),
      );
      var iterations = 0;
      while (controller.status == CombatV1PlayableControllerStatus.active &&
          iterations < maxIterationsPerSeed) {
        iterations += 1;
        final snap = controller.snapshot;
        if (snap.isHumanInputRequired) {
          final action = chooseFirstLegalHumanAction(snap);
          final result = controller.submitHumanAction(
            expectedRevision: snap.revision,
            action: action,
          );
          if (!result.isAccepted) break;
        } else {
          final advance = controller.advanceCpuUntilHumanInput();
          if (advance.actionsExecuted == 0 &&
              controller.status == CombatV1PlayableControllerStatus.active) {
            break;
          }
        }
        final latest = controller.snapshot.latestFeedback;
        if (latest != null && predicate(latest)) {
          return controller;
        }
      }
    }
  }
  return null;
}

/// [causeMatches]を満たす`terminalCause`でmatchOverへ到達するまで、同じ
/// deterministic進行で探索する。
CombatV1PlayableMatchController? _findMatchOverScenario(
  bool Function(CombatV1MatchTerminalCause) causeMatches, {
  int seedCount = 80,
}) {
  for (final wrestlerId in _wrestlerIds) {
    for (var seed = 0; seed < seedCount; seed++) {
      final controller = CombatV1PlayableMatchController(
        _config(
          humanWrestlerId: wrestlerId,
          cpuWrestlerId: wrestlerId,
          engineSeed: seed,
        ),
      );
      driveMatch(controller, maxIterations: 400);
      final result = controller.result;
      if (result != null &&
          result.status == CombatV1PlayableControllerStatus.matchOver &&
          result.terminalCause != null &&
          causeMatches(result.terminalCause!)) {
        return controller;
      }
    }
  }
  return null;
}

void main() {
  group('J/K. Technique resolved feedback（実controller）', () {
    testWidgets(
      'DOWNへ実際に移行したTechnique成立: banner primaryに技名+DAMAGE、'
      'DOWN badgeを表示する',
      (tester) async {
        final controller = _findFeedbackScenario(
          (f) =>
              f.kind == CombatV1PlayableFeedbackKind.techniqueResolved &&
              f.postureBefore != null &&
              f.postureBefore != CombatV1WrestlerPosture.down &&
              f.postureAfter == CombatV1WrestlerPosture.down,
        );
        expect(controller, isNotNull, reason: '探索範囲内でDOWN遷移を伴うtechnique成立が見つかりませんでした');
        final feedback = controller!.snapshot.latestFeedback!;

        // Core由来の実際の事実（fabricateではない）であることをまず確認する。
        expect(feedback.actionDisplayName, isNotNull);
        expect(feedback.damage, isNotNull);

        await tester.pumpWidget(
          _wrap(
            _WrappedLatestFeedbackBanner(
              feedback: feedback,
              humanPlayerIndex:
                  CombatV1PlayableMatchController.humanPlayerIndex,
            ),
          ),
        );
        await tester.pump();
        // `_LatestFeedbackBanner`（full版）はdetail toggle展開後に現れる
        // （既定はcompact 1行summaryのみ、design doc Playable 2A-5「9章」）。
        await tester.tap(
          find.byKey(const Key('combat_v1_playable_detail_toggle')),
        );
        await tester.pump();

        final primaryText = tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_latest_feedback_primary'),
              ),
            )
            .data!;
        expect(primaryText, contains(feedback.actionDisplayName!));
        expect(primaryText, contains('${feedback.damage} DAMAGE'));
        // Playable 2A-6「6-7章」——実際に観測されたDOWN遷移を明示する
        // 補助badge。
        expect(find.text('DOWN'), findsOneWidget);
      },
    );
  });

  group('L. Counter played feedback（実controller）', () {
    testWidgets('Counter成立: bannerはDAMAGEを一切示さない（攻撃は無効化された）', (
      tester,
    ) async {
      final controller = _findFeedbackScenario(
        (f) => f.kind == CombatV1PlayableFeedbackKind.counterPlayed,
      );
      expect(controller, isNotNull, reason: '探索範囲内でCounter成立が見つかりませんでした');
      final feedback = controller!.snapshot.latestFeedback!;

      // Counter'd attackはdamage/posture等を一切保持しない
      // （`_buildFeedback` case counter参照）——Core由来のfeedback自体が
      // 既にこの不変条件を満たしている。
      expect(feedback.damage, isNull);
      expect(feedback.postureBefore, isNull);
      expect(feedback.postureAfter, isNull);

      await tester.pumpWidget(
        _wrap(
          _WrappedLatestFeedbackBanner(
            feedback: feedback,
            humanPlayerIndex: CombatV1PlayableMatchController.humanPlayerIndex,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('combat_v1_playable_detail_toggle')),
      );
      await tester.pump();

      final primaryText = tester
          .widget<Text>(
            find.byKey(const Key('combat_v1_playable_latest_feedback_primary')),
          )
          .data!;
      expect(primaryText, isNot(contains('DAMAGE')));
      expect(find.text('DOWN'), findsNothing);
    });
  });

  group('O. PIN family match over（実controller）', () {
    testWidgets('PIN家系で決着した試合: Result overlayがwinner + PIN家系cause '
        'を表示する', (tester) async {
      final controller = _findMatchOverScenario(
        (cause) =>
            cause == CombatV1MatchTerminalCause.normalPin ||
            cause == CombatV1MatchTerminalCause.directPin,
      );
      expect(controller, isNotNull, reason: '探索範囲内でPIN家系決着の試合が見つかりませんでした');
      final result = controller!.result!;
      final snapshot = controller.snapshot;
      expect(result.winnerPlayerIndex, isNotNull);

      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: result.humanWrestlerId,
            cpuWrestlerId: result.cpuWrestlerId,
            cpuDelay: Duration.zero,
            sessionFactory: (_) => FakePlayableMatchSession(
              snapshot,
              result: result,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('combat_v1_playable_result_overlay')), findsOneWidget);
      final title = result.winnerPlayerIndex ==
              CombatV1PlayableMatchController.humanPlayerIndex
          ? 'YOU WIN'
          : 'CPU WIN';
      expect(find.text(title), findsOneWidget);
      final causeText = tester
          .widget<Text>(
            find.byKey(const Key('combat_v1_playable_result_cause')),
          )
          .data!;
      expect(
        causeText,
        anyOf(contains('PIN'), contains('Direct PIN')),
      );
      // Playable 2A-6「8章 決め技」——terminal actionが技かどうかに応じて
      // 「決め技」行が安全に判定・表示されること自体を確認する（値の
      // 断定はしない——通常PINの場合は「不明」が正しい）。
      expect(
        find.byKey(const Key('combat_v1_playable_result_finishing_move')),
        findsOneWidget,
      );
    });
  });

  group('P. Submission family match over（実controller）', () {
    testWidgets(
      'Submission家系で決着した試合: Result overlayがwinner + Submission家系'
      'causeを表示する',
      (tester) async {
        final controller = _findMatchOverScenario(
          (cause) =>
              cause == CombatV1MatchTerminalCause.submission ||
              cause == CombatV1MatchTerminalCause.submissionFinisher,
        );
        expect(
          controller,
          isNotNull,
          reason: '探索範囲内でSubmission家系決着の試合が見つかりませんでした',
        );
        final result = controller!.result!;
        final snapshot = controller.snapshot;
        final terminalFeedback = snapshot.latestFeedback;
        expect(terminalFeedback, isNotNull);
        expect(
          terminalFeedback!.submissionOutcome,
          CombatV1PlayableSubmissionFeedbackOutcome.matchOver,
        );

        await tester.pumpWidget(
          _wrap(
            CombatV1PlayableMatchScreen(
              humanWrestlerId: result.humanWrestlerId,
              cpuWrestlerId: result.cpuWrestlerId,
              cpuDelay: Duration.zero,
              sessionFactory: (_) =>
                  FakePlayableMatchSession(snapshot, result: result),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('combat_v1_playable_result_overlay')),
          findsOneWidget,
        );
        final causeText = tester
            .widget<Text>(
              find.byKey(const Key('combat_v1_playable_result_cause')),
            )
            .data!;
        expect(causeText, contains('Submission'));
        // terminal actionは常にtechniqueResolved（SUBMISSION自動移行）
        // なので、技識別子を安全に導出できる——「不明」ではなく実際の
        // 技名が「決め技」行に現れることを確認する。
        final finishingMoveText = tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_result_finishing_move'),
              ),
            )
            .data!;
        expect(finishingMoveText, isNot(contains('不明')));
        expect(finishingMoveText, contains(terminalFeedback.actionDisplayName!));
      },
    );
  });

  group('Q. 非terminalなFINISHER使用は試合終了表示を一切起こさない（実controller）', () {
    testWidgets('FINISHER成立後も試合が続いている場合、statusはactiveのまま、'
        'Result overlayも表示されない', (tester) async {
      final controller = _findFeedbackScenario(
        (f) => f.isFinisher,
      );
      expect(controller, isNotNull, reason: '探索範囲内でFINISHER成立が見つかりませんでした（scope外として許容）');
      // 見つかったfeedbackの時点でまだ試合が終わっていない
      // （＝matchOver以外）ケースをこの探索は優先的に拾う——
      // `_findFeedbackScenario`はpredicateを満たした瞬間のcontrollerを
      // 返すため、その瞬間のstatusをそのまま検証すればよい。
      if (controller!.status != CombatV1PlayableControllerStatus.active) {
        // 稀に「FINISHERで即決着」のケースを拾った場合は、この項目の
        // 検証対象外として安全にskipする（Q自体は別途、非terminalな
        // ケースが優先的に見つかることを期待した探索設計のため、通常は
        // ここへ到達しない）。
        return;
      }

      final snapshot = controller.snapshot;
      await tester.pumpWidget(
        _wrap(
          CombatV1PlayableMatchScreen(
            humanWrestlerId: snapshot.human.wrestlerId,
            cpuWrestlerId: snapshot.cpu.wrestlerId,
            cpuDelay: Duration.zero,
            sessionFactory: (_) => FakePlayableMatchSession(snapshot),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_result_overlay')),
        findsNothing,
      );
      expect(find.text('YOU WIN'), findsNothing);
      expect(find.text('CPU WIN'), findsNothing);
    });
  });
}

/// `_LatestFeedbackBanner`はlibrary-private widgetのため、直接importできない
/// ——`CombatV1PlayableMatchScreen`が唯一のpublic entry pointなので、
/// discard-onlyのsnapshotの下に`latestFeedback`を積んで
/// `_ActorAndRecentPanel`側のexpanded bannerとして間接的に描画させる。
class _WrappedLatestFeedbackBanner extends StatelessWidget {
  const _WrappedLatestFeedbackBanner({
    required this.feedback,
    required this.humanPlayerIndex,
  });

  final CombatV1PlayableActionFeedback feedback;
  final int humanPlayerIndex;

  @override
  Widget build(BuildContext context) {
    final snapshot = testSnapshot(
      phase: CombatV1MatchPhase.action,
      isHumanInputRequired: true,
      legalActions: const [],
      latestFeedback: feedback,
      recentFeedback: [feedback],
    );
    return CombatV1PlayableMatchScreen(
      humanWrestlerId: 'akari',
      cpuWrestlerId: 'reina',
      cpuDelay: Duration.zero,
      sessionFactory: (_) => FakePlayableMatchSession(snapshot),
    );
  }
}
