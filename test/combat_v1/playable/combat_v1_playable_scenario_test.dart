// Combat Ver.1 Playable 1A — シナリオ駆動テスト。
//
// Production wrestlerのデッキはshuffleに依存するため、Counter/PIN/REST/
// StandUp/EndTurnといった特定シナリオへ到達するために、複数の
// (wrestlerId, engineSeed)組み合わせをcontroller public APIだけを使って
// 探索する（fragileな1点固定seedへは依存しない）。
//
// 対象: 22章（Counter semantics）・23章（Counter actor test）・
// 24章（discard semantics、通過確認）・72章（Counter tests）・
// 73章（PIN test）・74章（REST/StandUp/EndTurn test）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_config.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_controller.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';

import 'combat_v1_playable_test_helpers.dart';

const List<String> _wrestlerIds = ['misaki', 'jack', 'akari', 'reina'];

CombatV1PlayableMatchConfig _config({
  String humanWrestlerId = 'misaki',
  String cpuWrestlerId = 'jack',
  int engineSeed = 1,
  int cpuPolicySeed = 2,
  int maxActions = 500,
}) => CombatV1PlayableMatchConfig(
  humanWrestlerId: humanWrestlerId,
  cpuWrestlerId: cpuWrestlerId,
  engineSeed: engineSeed,
  cpuPolicySeed: cpuPolicySeed,
  maxActions: maxActions,
  // FirstLegalはdeterministicかつ「Counterがあれば必ず使う」優先順位
  // （PIN > counter > declineCounter > ...）を持つため、シナリオ探索に
  // 最も適したCPU policy。
  cpuPolicyKind: CombatV1PlayableCpuPolicyKind.firstLegal,
);

/// Humanが常に受動的（discard→endTurn、Counter局面ではdecline、DOWN時は
/// standUp優先）に振る舞う選択関数。CPUがattackerになる機会を最大化する
/// ためのシナリオ探索専用ヘルパー。
CombatV1LegalAction _passiveHumanChoice(CombatV1PlayableMatchSnapshot snapshot) {
  final discard = snapshot.legalActions.whereType<CombatV1DiscardAction>();
  if (discard.isNotEmpty) return discard.first;

  final decline = snapshot.legalActions.whereType<CombatV1DeclineCounterAction>();
  if (decline.isNotEmpty) return decline.first;

  final standUp = snapshot.legalActions.whereType<CombatV1StandUpAction>();
  if (standUp.isNotEmpty) return standUp.first;

  final rest = snapshot.legalActions.whereType<CombatV1RestAction>();
  if (rest.isNotEmpty) return rest.first;

  final endTurn = snapshot.legalActions.whereType<CombatV1EndTurnAction>();
  if (endTurn.isNotEmpty) return endTurn.first;

  throw StateError('受動的な選択肢がありません: ${snapshot.legalActions}');
}

/// [predicate]を満たすsnapshotへ到達するまで、Humanは[chooseHuman]で、
/// CPUは`advanceCpuUntilHumanInput`で進行させる。`seedCount`個の
/// engineSeed（0始まり）を順に試し、最初に見つかったcontrollerを返す
/// （見つからなければ`null`）。
CombatV1PlayableMatchController? _findScenario(
  bool Function(CombatV1PlayableMatchSnapshot) predicate, {
  String humanWrestlerId = 'misaki',
  String cpuWrestlerId = 'jack',
  CombatV1LegalAction Function(CombatV1PlayableMatchSnapshot) chooseHuman =
      _passiveHumanChoice,
  int seedCount = 40,
  int maxIterationsPerSeed = 160,
}) {
  for (var seed = 0; seed < seedCount; seed++) {
    final controller = CombatV1PlayableMatchController(
      _config(
        humanWrestlerId: humanWrestlerId,
        cpuWrestlerId: cpuWrestlerId,
        engineSeed: seed,
      ),
    );
    var iterations = 0;
    while (controller.status == CombatV1PlayableControllerStatus.active &&
        iterations < maxIterationsPerSeed) {
      iterations += 1;
      final snap = controller.snapshot;
      if (snap.isHumanInputRequired) {
        if (predicate(snap)) return controller;
        final action = chooseHuman(snap);
        final result = controller.submitHumanAction(
          expectedRevision: snap.revision,
          action: action,
        );
        if (!result.isAccepted) break;
      } else {
        final advance = controller.advanceCpuUntilHumanInput();
        if (advance.actionsExecuted == 0) break;
      }
    }
  }
  return null;
}

bool _isCpuAttackHumanDefend(CombatV1PlayableMatchSnapshot s) =>
    s.pendingAttack != null &&
    s.pendingAttack!.attackerPlayerIndex ==
        CombatV1PlayableMatchController.cpuPlayerIndex;

bool _isCpuAttackWithHumanCounterAvailable(CombatV1PlayableMatchSnapshot s) =>
    _isCpuAttackHumanDefend(s) &&
    s.legalActions.whereType<CombatV1CounterAction>().isNotEmpty;

bool _isHumanDownAndActive(CombatV1PlayableMatchSnapshot s) =>
    s.human.posture == CombatV1WrestlerPosture.down && s.isHumanInputRequired;

void main() {
  group('22-23. Counter semantics / Counter actor test', () {
    test('CPU attacker → Human defender → current actor == Human'
        '（activePlayerはCPUのままでもHumanへ制御が戻る）', () {
      final controller = _findScenario(_isCpuAttackHumanDefend);
      expect(
        controller,
        isNotNull,
        reason: '探索範囲内でCPU attacker→Human defenderの局面が見つかりませんでした',
      );
      final snap = controller!.snapshot;

      expect(snap.status, CombatV1PlayableControllerStatus.active);
      expect(snap.isHumanInputRequired, isTrue);
      expect(
        snap.currentActorPlayerIndex,
        CombatV1PlayableMatchController.humanPlayerIndex,
      );
      // pendingAttack.attackerPlayerIndexは`state.activePlayerIndex`と
      // 同じ値——「activePlayerはCPUのまま」であることを、公開API
      // （raw activePlayerIndexは公開しない）から確認できる唯一の窓。
      expect(
        snap.pendingAttack!.attackerPlayerIndex,
        CombatV1PlayableMatchController.cpuPlayerIndex,
      );
      expect(
        snap.pendingAttack!.defenderPlayerIndex,
        CombatV1PlayableMatchController.humanPlayerIndex,
      );

      // legal actionsはcounter/declineCounterのみ、actorは全てHuman。
      for (final action in snap.legalActions) {
        expect(
          action.kind,
          anyOf(
            CombatV1LegalActionKind.counter,
            CombatV1LegalActionKind.declineCounter,
          ),
        );
        expect(
          action.actorPlayerIndex,
          CombatV1PlayableMatchController.humanPlayerIndex,
        );
      }
      expect(
        snap.legalActions.whereType<CombatV1DeclineCounterAction>(),
        isNotEmpty,
      );
    });
  });

  group('72. Human decline', () {
    test('Human decline後、attackが解決されpendingAttackがクリアされる', () {
      final controller = _findScenario(_isCpuAttackHumanDefend);
      expect(controller, isNotNull);
      final snap = controller!.snapshot;
      final decline = snap.legalActions
          .whereType<CombatV1DeclineCounterAction>()
          .first;

      final result = controller.submitHumanAction(
        expectedRevision: snap.revision,
        action: decline,
      );
      expect(result.isAccepted, isTrue);
      expect(controller.snapshot.revision, snap.revision + 1);
      expect(controller.snapshot.actionCount, snap.actionCount + 1);
      // decline成功でpendingAttackは必ずクリアされる（試合終了時も含め、
      // counterResponsePendingへ留まることはない）。
      expect(controller.snapshot.pendingAttack, isNull);
    });
  });

  group('72. Human counter', () {
    test('HumanがCounterをplayするとpendingAttackが解決される', () {
      final controller = _findScenario(_isCpuAttackWithHumanCounterAvailable);
      expect(
        controller,
        isNotNull,
        reason: '探索範囲内でHuman counterが可能な局面が見つかりませんでした',
      );
      final snap = controller!.snapshot;
      final counterAction = snap.legalActions
          .whereType<CombatV1CounterAction>()
          .first;

      // counterのcardInstanceIdが実際にHumanのhandに存在することを確認
      // （command identityがcardInstanceIdであることの確認）。
      expect(
        snap.human.hand.map((c) => c.instanceId),
        contains(counterAction.cardInstanceId),
      );

      final result = controller.submitHumanAction(
        expectedRevision: snap.revision,
        action: counterAction,
      );
      expect(result.isAccepted, isTrue);
      expect(controller.snapshot.revision, snap.revision + 1);
      expect(controller.snapshot.actionCount, snap.actionCount + 1);
      expect(controller.snapshot.pendingAttack, isNull);
    });
  });

  group('72. CPU counter', () {
    test('CPU（FirstLegal policy）がCounterをplayした場合、'
        'recentObservationsへ反映される（hidden-safeな公開actionとして）', () {
      // Human techniqueをsubmitし、CPU防御側の応答をadvanceCpuUntilHumanInput
      // で1turn分進める。CPUがCounterした場合のみ検証対象とし、declineした
      // 場合は次のseedへ進む。
      CombatV1PlayableMatchController? found;

      outer:
      for (final wrestlerId in _wrestlerIds) {
        for (var seed = 0; seed < 40; seed++) {
          final controller = CombatV1PlayableMatchController(
            _config(humanWrestlerId: wrestlerId, engineSeed: seed),
          );
          final discardSnap = controller.snapshot;
          final discardResult = controller.submitHumanAction(
            expectedRevision: discardSnap.revision,
            action: discardSnap.legalActions
                .whereType<CombatV1DiscardAction>()
                .first,
          );
          if (!discardResult.isAccepted) continue;

          final actionSnap = controller.snapshot;
          final techniqueActions = actionSnap.legalActions
              .whereType<CombatV1TechniqueAction>()
              .toList();
          if (techniqueActions.isEmpty) continue;

          final declareResult = controller.submitHumanAction(
            expectedRevision: actionSnap.revision,
            action: techniqueActions.first,
          );
          if (!declareResult.isAccepted) continue;

          controller.advanceCpuUntilHumanInput();

          final cpuCountered = controller.snapshot.recentObservations.any(
            (o) =>
                o.actorPlayerIndex ==
                    CombatV1PlayableMatchController.cpuPlayerIndex &&
                o.action.kind == CombatV1LegalActionKind.counter,
          );
          if (cpuCountered) {
            found = controller;
            break outer;
          }
        }
      }

      expect(
        found,
        isNotNull,
        reason: '探索範囲内でCPUがCounterする局面が見つかりませんでした',
      );
      final observation = found!.snapshot.recentObservations.lastWhere(
        (o) =>
            o.actorPlayerIndex ==
                CombatV1PlayableMatchController.cpuPlayerIndex &&
            o.action.kind == CombatV1LegalActionKind.counter,
      );
      expect(observation.action.actorPlayerIndex, 1);
      expect(observation.action.cardInstanceId, isNotNull);
    });
  });

  group('73. PIN test', () {
    test('相手をDOWNさせるtechnique成立後、Human declarePinが受理され'
        'Engineの自動解決を通す（controller独自PIN logicなし）', () {
      CombatV1PlayableMatchController? found;

      outer:
      for (final wrestlerId in _wrestlerIds) {
        for (var seed = 0; seed < 20; seed++) {
          final controller = CombatV1PlayableMatchController(
            _config(humanWrestlerId: wrestlerId, engineSeed: seed),
          );
          var iterations = 0;
          while (controller.status == CombatV1PlayableControllerStatus.active &&
              iterations < 60) {
            final snap = controller.snapshot;
            if (!snap.isHumanInputRequired) {
              final advance = controller.advanceCpuUntilHumanInput();
              if (advance.actionsExecuted == 0) break;
              continue;
            }
            iterations += 1;

            final pinActions = snap.legalActions
                .whereType<CombatV1PinAction>()
                .toList();
            if (pinActions.isNotEmpty) {
              final pinResult = controller.submitHumanAction(
                expectedRevision: snap.revision,
                action: pinActions.first,
              );
              if (pinResult.isAccepted) {
                found = controller;
              }
              break;
            }

            // DOWNを狙えるtechniqueがあれば優先、無ければfirstLegal相当。
            final downCard = snap.human.hand.firstWhere(
              (c) =>
                  c.isUsable &&
                  c.technique != null &&
                  c.technique!.resultOpponentState ==
                      CombatV1WrestlerPosture.down &&
                  !c.technique!.directPin,
              orElse: () => snap.human.hand.first,
            );
            final downAction = snap.legalActions
                .whereType<CombatV1TechniqueAction>()
                .where((a) => a.cardInstanceId == downCard.instanceId)
                .toList();
            final action = downAction.isNotEmpty
                ? downAction.first
                : chooseFirstLegalHumanAction(snap);

            final result = controller.submitHumanAction(
              expectedRevision: snap.revision,
              action: action,
            );
            if (!result.isAccepted) break;
          }
          if (found != null) break outer;
        }
      }

      expect(found, isNotNull, reason: '探索範囲内でPINが合法になる局面が見つかりませんでした');
      // findループ内で既にsubmitHumanAction(declarePin)が受理済み。
      // pinCardsHeldの合計はEngine不変条件として維持されているはず
      // （controllerは独自にPINカード移動/count logicを持たない）。
      final result = found!.snapshot;
      expect(
        result.human.pinCardsHeld + result.cpu.pinCardsHeld,
        4,
        reason: 'PINカード総数（既定4枚）はEngineが管理する不変条件のまま',
      );
    });
  });

  group('74. REST / StandUp / EndTurn test', () {
    test('HumanがDOWNになった場合、standUp/restのみが合法になり、'
        'submitが正しく反映される', () {
      final controller = _findScenario(_isHumanDownAndActive);
      expect(
        controller,
        isNotNull,
        reason: '探索範囲内でHumanがDOWNのまま手番へ戻る局面が見つかりませんでした',
      );
      final snap = controller!.snapshot;
      expect(snap.human.posture, CombatV1WrestlerPosture.down);

      // DOWN時はtechnique/PIN/endTurnは列挙されない。
      for (final action in snap.legalActions) {
        expect(
          action.kind,
          anyOf(
            CombatV1LegalActionKind.standUp,
            CombatV1LegalActionKind.rest,
          ),
        );
      }
      expect(snap.legalActions, isNotEmpty);

      final chosen = snap.legalActions.first;
      final result = controller.submitHumanAction(
        expectedRevision: snap.revision,
        action: chosen,
      );
      expect(result.isAccepted, isTrue);
      expect(controller.snapshot.revision, snap.revision + 1);

      if (chosen.kind == CombatV1LegalActionKind.standUp) {
        expect(controller.snapshot.human.posture, CombatV1WrestlerPosture.stand);
      }
    });

    test('endTurnもlegal actionに存在する場合のみsubmit可能', () {
      final controller = CombatV1PlayableMatchController(_config());
      final discardSnap = controller.snapshot;
      // discard phaseではendTurnは合法ではない。
      expect(
        discardSnap.legalActions.whereType<CombatV1EndTurnAction>(),
        isEmpty,
      );

      final discardResult = controller.submitHumanAction(
        expectedRevision: discardSnap.revision,
        action: discardSnap.legalActions.whereType<CombatV1DiscardAction>().first,
      );
      expect(discardResult.isAccepted, isTrue);

      final actionSnap = controller.snapshot;
      // action phase（STAND）ではendTurnは常に合法。
      final endTurnActions = actionSnap.legalActions
          .whereType<CombatV1EndTurnAction>()
          .toList();
      expect(endTurnActions, isNotEmpty);

      final result = controller.submitHumanAction(
        expectedRevision: actionSnap.revision,
        action: endTurnActions.first,
      );
      expect(result.isAccepted, isTrue);
      expect(controller.snapshot.revision, actionSnap.revision + 1);
    });
  });
}
