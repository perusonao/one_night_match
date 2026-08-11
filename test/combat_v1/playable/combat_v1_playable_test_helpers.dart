/// Combat Ver.1 Playable 1Aテスト共通ヘルパー。
///
/// `_test.dart`という命名ではないため、`flutter test`からは直接テスト
/// スイートとして実行されず、他のテストファイルから共有ヘルパーとして
/// importする（`combat_v1_test_fixtures.dart`と同じ方針）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_controller.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';

/// [CombatV1FirstLegalPolicy]（`combat_v1_decision_policy.dart`）と同じ
/// deterministic priority（PIN > counter > declineCounter > standUp >
/// technique > rest > endTurn > discard、同type内は`cardInstanceId`昇順）
/// で、[snapshot.legalActions]からHuman actionを1つ選ぶ。Human側の
/// deterministic testで、controllerのpublic snapshotだけを参照して
/// 「賢く」進行させるための共有ヘルパー。
const List<CombatV1LegalActionKind> firstLegalPriority = [
  CombatV1LegalActionKind.pin,
  CombatV1LegalActionKind.counter,
  CombatV1LegalActionKind.declineCounter,
  CombatV1LegalActionKind.standUp,
  CombatV1LegalActionKind.technique,
  CombatV1LegalActionKind.rest,
  CombatV1LegalActionKind.endTurn,
  CombatV1LegalActionKind.discard,
];

CombatV1LegalAction chooseFirstLegalHumanAction(
  CombatV1PlayableMatchSnapshot snapshot,
) {
  for (final kind in firstLegalPriority) {
    final candidates = snapshot.legalActions
        .where((a) => a.kind == kind)
        .toList()
      ..sort((a, b) => (a.cardInstanceId ?? '').compareTo(b.cardInstanceId ?? ''));
    if (candidates.isNotEmpty) return candidates.first;
  }
  throw StateError('legalActionsの中にサポートされているkindがありません: '
      '${snapshot.legalActions}');
}

/// [snapshot.legalActions]の中から、declineCounterを避けてCounterを
/// 優先的に選ぶ（Human counterのpositive caseをtestするための選択関数。
/// Counterが無ければdeclineへfall back）。
CombatV1LegalAction chooseCounterOverDeclineHumanAction(
  CombatV1PlayableMatchSnapshot snapshot,
) {
  final counters = snapshot.legalActions
      .whereType<CombatV1CounterAction>()
      .toList()
    ..sort((a, b) => a.cardInstanceId.compareTo(b.cardInstanceId));
  if (counters.isNotEmpty) return counters.first;
  return chooseFirstLegalHumanAction(snapshot);
}

/// [controller]を、Humanの手番なら[chooseHumanAction]で選んだactionを
/// submitし、CPUの手番なら[CombatV1PlayableMatchController.
/// advanceCpuUntilHumanInput]でCPUを進行させる、という手順を
/// `status != active`になるまで繰り返す（`submitHumanAction`はCPUへ自動
/// 連鎖しない設計のため、Human/CPU双方を明示的に交互駆動する）。
///
/// 各submitが必ず受理される（[CombatV1PlayableSubmitOutcome.accepted]）
/// ことを`expect`で確認しながら進める。実行したHuman submitの回数を返す。
/// [maxIterations]は無限ループ防止用のtest-only safety guard
/// （controller自身のsafetyLimitとは独立）。
int driveMatch(
  CombatV1PlayableMatchController controller, {
  CombatV1LegalAction Function(CombatV1PlayableMatchSnapshot snapshot)
  chooseHumanAction = chooseFirstLegalHumanAction,
  int maxIterations = 500,
}) {
  var humanSubmits = 0;
  var iterations = 0;
  while (controller.status == CombatV1PlayableControllerStatus.active &&
      iterations < maxIterations) {
    iterations += 1;
    final snapshot = controller.snapshot;
    if (snapshot.isHumanInputRequired) {
      final action = chooseHumanAction(snapshot);
      final result = controller.submitHumanAction(
        expectedRevision: snapshot.revision,
        action: action,
      );
      expect(
        result.isAccepted,
        isTrue,
        reason: 'submitHumanAction rejected: ${result.outcome} / '
            '${result.message}',
      );
      humanSubmits += 1;
    } else {
      final advance = controller.advanceCpuUntilHumanInput();
      if (advance.actionsExecuted == 0 &&
          controller.status == CombatV1PlayableControllerStatus.active) {
        fail(
          'advanceCpuUntilHumanInput()がCPUの手番なのに1件も進行しません'
          'でした（status: ${controller.status}, currentActor: '
          '${controller.snapshot.currentActorPlayerIndex}）',
        );
      }
    }
  }
  return humanSubmits;
}
