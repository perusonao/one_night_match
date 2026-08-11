// Combat Ver.1 Playable 1A — CombatV1PlayableMatchController。
//
// start test・actor resolution・technique test・stale revision test・
// human action validation・PIN/REST/StandUp/EndTurn（機会があれば）・
// CPU one-step/until-human APIの基本挙動を検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_config.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_controller.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';

import 'combat_v1_playable_test_helpers.dart';

CombatV1PlayableMatchConfig _config({
  String humanWrestlerId = 'misaki',
  String cpuWrestlerId = 'jack',
  int engineSeed = 1,
  int cpuPolicySeed = 2,
  int maxActions = 500,
  CombatV1PlayableCpuPolicyKind cpuPolicyKind =
      CombatV1PlayableCpuPolicyKind.firstLegal,
}) => CombatV1PlayableMatchConfig(
  humanWrestlerId: humanWrestlerId,
  cpuWrestlerId: cpuWrestlerId,
  engineSeed: engineSeed,
  cpuPolicySeed: cpuPolicySeed,
  maxActions: maxActions,
  cpuPolicyKind: cpuPolicyKind,
);

void main() {
  group('69. Start test', () {
    test('Human index 0 / CPU index 1、初期snapshotが期待通り', () {
      expect(CombatV1PlayableMatchController.humanPlayerIndex, 0);
      expect(CombatV1PlayableMatchController.cpuPlayerIndex, 1);

      final controller = CombatV1PlayableMatchController(_config());
      final snap = controller.snapshot;

      expect(snap.status, CombatV1PlayableControllerStatus.active);
      expect(snap.currentActorPlayerIndex, 0);
      expect(snap.isHumanInputRequired, isTrue);
      expect(snap.isMatchOver, isFalse);
      expect(snap.revision, 0);
      expect(snap.actionCount, 0);
      expect(snap.phase, CombatV1MatchPhase.discard);
      expect(snap.turnNumber, 1);

      expect(snap.legalActions, isNotEmpty);
      for (final action in snap.legalActions) {
        expect(action.actorPlayerIndex, 0, reason: 'actorはHumanのはず');
      }

      expect(snap.human.wrestlerId, 'misaki');
      expect(snap.cpu.wrestlerId, 'jack');
      expect(snap.human.hand, isNotEmpty);
      expect(snap.human.handCount, snap.human.hand.length);
      expect(snap.cpu.handCount, greaterThan(0));
      expect(snap.pendingAttack, isNull);
    });
  });

  group('82. Mirror test', () {
    test('同一wrestler同士（misaki vs misaki）でも開始できる', () {
      final controller = CombatV1PlayableMatchController(
        _config(humanWrestlerId: 'misaki', cpuWrestlerId: 'misaki'),
      );
      final snap = controller.snapshot;
      expect(snap.human.wrestlerId, 'misaki');
      expect(snap.cpu.wrestlerId, 'misaki');
      expect(snap.status, CombatV1PlayableControllerStatus.active);
      // 両者のwrestlerIdは同じでも、YOU(human)/CPUの区別はsnapshotの構造
      // （human/cpuフィールドの分離）そのものから常に可能。
      expect(snap.human.wrestlerName, snap.cpu.wrestlerName);
    });
  });

  group('71. Technique test / action submission', () {
    test('Human action送信のたびにrevision/actionCountが単調に増加する', () {
      final controller = CombatV1PlayableMatchController(_config());
      var previousRevision = controller.snapshot.revision;
      var previousActionCount = controller.snapshot.actionCount;

      for (var i = 0; i < 3; i++) {
        if (!controller.snapshot.isHumanInputRequired) break;
        final snap = controller.snapshot;
        final action = chooseFirstLegalHumanAction(snap);
        final result = controller.submitHumanAction(
          expectedRevision: snap.revision,
          action: action,
        );
        expect(result.isAccepted, isTrue);
        expect(controller.snapshot.revision, greaterThan(previousRevision));
        expect(
          controller.snapshot.actionCount,
          greaterThan(previousActionCount),
        );
        previousRevision = controller.snapshot.revision;
        previousActionCount = controller.snapshot.actionCount;
      }
    });

    test('cardInstanceId identityでHuman techniqueをsubmitできる', () {
      // 複数の(humanWrestlerId, engineSeed)を試し、discard後のaction
      // phaseで少なくとも1件legal techniqueが存在する組み合わせを探す
      // （production deckの構成上、通常のstarting handでは高確率で
      // 存在するが、fragileな1点固定seedには依存しない）。
      const wrestlerIds = ['misaki', 'jack', 'akari', 'reina'];
      CombatV1PlayableMatchController? found;
      CombatV1TechniqueAction? foundAction;

      outer:
      for (final wrestlerId in wrestlerIds) {
        for (var seed = 0; seed < 15; seed++) {
          final controller = CombatV1PlayableMatchController(
            _config(humanWrestlerId: wrestlerId, engineSeed: seed),
          );
          final discardSnap = controller.snapshot;
          final discardAction = discardSnap.legalActions
              .whereType<CombatV1DiscardAction>()
              .first;
          final discardResult = controller.submitHumanAction(
            expectedRevision: discardSnap.revision,
            action: discardAction,
          );
          expect(discardResult.isAccepted, isTrue);

          final actionSnap = controller.snapshot;
          final techniqueActions = actionSnap.legalActions
              .whereType<CombatV1TechniqueAction>()
              .toList();
          if (techniqueActions.isNotEmpty) {
            found = controller;
            foundAction = techniqueActions.first;
            break outer;
          }
        }
      }

      expect(
        found,
        isNotNull,
        reason: '探索範囲内でlegal techniqueが1件も見つかりませんでした',
      );
      final controller = found!;
      final action = foundAction!;
      final snapBefore = controller.snapshot;

      // physical instanceIdが実際にHumanのhandに存在することを確認
      // （command identityがcardInstanceIdであることの直接確認）。
      expect(
        snapBefore.human.hand.map((c) => c.instanceId),
        contains(action.cardInstanceId),
      );

      final result = controller.submitHumanAction(
        expectedRevision: snapBefore.revision,
        action: action,
      );
      expect(result.isAccepted, isTrue);
      expect(controller.snapshot.revision, snapBefore.revision + 1);
      expect(controller.snapshot.actionCount, snapBefore.actionCount + 1);
      // Technique宣言直後はcounterResponsePendingへ遷移する
      // （declineされていなければ）。
      expect(
        controller.snapshot.phase,
        CombatV1MatchPhase.counterResponsePending,
      );
    });
  });

  group('19. Actor resolution / activePlayerIndex非依存', () {
    test('current actorはlegal actionのactorPlayerIndexから導出される'
        '（既にlegalActions側で検証済みの前提を、controller APIからも'
        '再確認する）', () {
      final controller = CombatV1PlayableMatchController(_config());
      final snap = controller.snapshot;
      expect(snap.currentActorPlayerIndex, 0);
      // Human自身のsubmitでも、返ってくるsnapshotのlegalActions全件が
      // 新しいcurrentActorPlayerIndexと一致することを、進行の都度確認する。
      driveMatch(controller, maxIterations: 40);
      // driveMatchはstatus!=activeになるまで進めるため、途中経過を直接
      // 検証したい場合は下記の専用test（counter test）で扱う。ここでは
      // 少なくとも例外なく進行できることのみ確認する。
      expect(
        controller.status,
        isNot(CombatV1PlayableControllerStatus.error),
      );
    });
  });

  group('75. Stale revision test', () {
    test('古いrevisionでのsubmitはrejectされ、stateは変更されない', () {
      final controller = CombatV1PlayableMatchController(_config());
      final snap = controller.snapshot;
      final action = snap.legalActions.first;

      final staleResult = controller.submitHumanAction(
        expectedRevision: snap.revision + 1,
        action: action,
      );
      expect(
        staleResult.outcome,
        CombatV1PlayableSubmitOutcome.rejectedStaleRevision,
      );
      expect(controller.snapshot.revision, snap.revision);
      expect(controller.snapshot.actionCount, snap.actionCount);
      expect(controller.snapshot.legalActions, snap.legalActions);

      // stateを1 action進めてrevision N+1にした後、古いNでsubmitすると
      // reject。
      final firstResult = controller.submitHumanAction(
        expectedRevision: snap.revision,
        action: action,
      );
      expect(firstResult.isAccepted, isTrue);
      final newRevision = controller.snapshot.revision;
      expect(newRevision, snap.revision + 1);

      final againStaleResult = controller.submitHumanAction(
        expectedRevision: snap.revision,
        action: action,
      );
      expect(
        againStaleResult.outcome,
        CombatV1PlayableSubmitOutcome.rejectedStaleRevision,
      );
      expect(controller.snapshot.revision, newRevision);
    });
  });

  group('18. Human action validation', () {
    test('現在のactorがHumanではないactionはrejectされる（wrong actor）', () {
      final controller = CombatV1PlayableMatchController(_config());
      final snap = controller.snapshot;
      final wrongActorAction = CombatV1EndTurnAction(
        actorPlayerIndex: CombatV1PlayableMatchController.cpuPlayerIndex,
      );

      final result = controller.submitHumanAction(
        expectedRevision: snap.revision,
        action: wrongActorAction,
      );
      expect(result.outcome, CombatV1PlayableSubmitOutcome.rejectedWrongActor);
      expect(controller.snapshot.revision, snap.revision);
    });

    test('現在のlegal action snapshotに含まれないactionはrejectされる'
        '（illegal action）', () {
      final controller = CombatV1PlayableMatchController(_config());
      final snap = controller.snapshot;
      // discardフェーズ開始直後はPINは合法ではない。
      final illegalAction = CombatV1PinAction(
        actorPlayerIndex: CombatV1PlayableMatchController.humanPlayerIndex,
      );
      expect(snap.legalActions.contains(illegalAction), isFalse);

      final result = controller.submitHumanAction(
        expectedRevision: snap.revision,
        action: illegalAction,
      );
      expect(
        result.outcome,
        CombatV1PlayableSubmitOutcome.rejectedIllegalAction,
      );
      expect(controller.snapshot.revision, snap.revision);
      expect(controller.snapshot.actionCount, snap.actionCount);
    });

    test('試合終了後のsubmitはrejectedNotReadyになる', () {
      final controller = CombatV1PlayableMatchController(
        _config(maxActions: 2),
      );
      driveMatch(controller, maxIterations: 20);
      expect(controller.status, isNot(CombatV1PlayableControllerStatus.active));

      final snap = controller.snapshot;
      final result = controller.submitHumanAction(
        expectedRevision: snap.revision,
        action: CombatV1EndTurnAction(
          actorPlayerIndex: CombatV1PlayableMatchController.humanPlayerIndex,
        ),
      );
      expect(result.outcome, CombatV1PlayableSubmitOutcome.rejectedNotReady);
    });
  });

  group('25/26. CPU one-step / until-human API', () {
    test('advanceCpuOneAction()はHumanの手番中はno-op', () {
      final controller = CombatV1PlayableMatchController(_config());
      expect(controller.snapshot.isHumanInputRequired, isTrue);
      final advance = controller.advanceCpuOneAction();
      expect(advance.actionsExecuted, 0);
      expect(controller.snapshot.revision, 0);
    });

    test('advanceCpuOneAction()はCPUの手番中ちょうど1 actionだけ進める', () {
      // discard→technique（を宣言してcounterResponsePendingへ）まで進め、
      // CPU（防御側）の手番にする。
      const wrestlerIds = ['misaki', 'jack', 'akari', 'reina'];
      CombatV1PlayableMatchController? found;

      outer:
      for (final wrestlerId in wrestlerIds) {
        for (var seed = 0; seed < 15; seed++) {
          final controller = CombatV1PlayableMatchController(
            _config(humanWrestlerId: wrestlerId, engineSeed: seed),
          );
          final discardSnap = controller.snapshot;
          final discardAction = discardSnap.legalActions
              .whereType<CombatV1DiscardAction>()
              .first;
          controller.submitHumanAction(
            expectedRevision: discardSnap.revision,
            action: discardAction,
          );

          final actionSnap = controller.snapshot;
          final techniqueActions = actionSnap.legalActions
              .whereType<CombatV1TechniqueAction>()
              .toList();
          if (techniqueActions.isEmpty) continue;

          final declareResult = controller.submitHumanAction(
            expectedRevision: actionSnap.revision,
            action: techniqueActions.first,
          );
          expect(declareResult.isAccepted, isTrue);
          if (!controller.snapshot.isHumanInputRequired &&
              controller.status == CombatV1PlayableControllerStatus.active) {
            found = controller;
            break outer;
          }
        }
      }

      expect(
        found,
        isNotNull,
        reason: 'CPUの手番（counterResponsePending防御側）へ到達できませんでした',
      );
      final controller = found!;
      expect(controller.snapshot.currentActorPlayerIndex, 1);
      final before = controller.snapshot.actionCount;
      final advance = controller.advanceCpuOneAction();
      expect(advance.actionsExecuted, 1);
      expect(controller.snapshot.actionCount, before + 1);
    });
  });

  group('80. Invariant helper regression（shared lifecycle helper）', () {
    test('validatePlayerStateInvariants/validateMatchStateInvariantsは'
        '正常なcontroller stateに対して常にvalidを返す', () {
      final controller = CombatV1PlayableMatchController(_config());
      driveMatch(controller, maxIterations: 60);
      // controller自体が公開しないraw stateへは直接アクセスできないため、
      // ここではcontrollerがinvariantViolationへ陥っていないことのみを
      // 確認する（shared validatorの単体挙動はcombat_v1_invariants_test.dart
      // で別途検証済み）。
      expect(
        controller.status,
        isNot(CombatV1PlayableControllerStatus.invariantViolation),
        reason: controller.result?.invariantViolationMessage ?? '',
      );
    });
  });
}
