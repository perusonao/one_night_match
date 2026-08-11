// Combat Ver.1 Playable 1A — lifecycle / cross-cutting tests。
//
// 対象: 76章（hidden information test）・77章（RNG determinism test）・
// 78章（different seed test）・79章（safety limit test）・
// 83章（observation retention test）・85章（integration full-match test）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_match_setup.dart';
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

/// [wrestlerId]の全30枚デッキが持つphysical instanceId全件
/// （`combatV1PlayableOwnerId`で組み立てたowner namespaceに対応する
/// deck）。hidden information testの「真のCPU手札universe」として使う。
Set<String> _fullDeckInstanceIds({
  required String wrestlerId,
  required int engineSeed,
  required String playerSuffix,
}) {
  final entry = combatV1ProductionWrestlerRegistry[wrestlerId]!;
  final ownerId = combatV1PlayableOwnerId(
    engineSeed: engineSeed,
    playerSuffix: playerSuffix,
  );
  return entry
      .buildDeck(ownerId: ownerId)
      .entries
      .map((e) => e.instanceId)
      .toSet();
}

/// (actionCount, finalTurnNumber, status, terminalCause, winnerPlayerIndex,
/// human/cpu hp) をまとめた比較用signature。
String _matchSignature(CombatV1PlayableMatchController controller) {
  final snap = controller.snapshot;
  final result = controller.result;
  return [
    snap.actionCount,
    snap.turnNumber,
    snap.status,
    result?.terminalCause,
    result?.winnerPlayerIndex,
    snap.human.hp,
    snap.cpu.hp,
    snap.sharedHeat,
  ].join('|');
}

CombatV1PlayableMatchController _driveFullMatch({
  required String humanWrestlerId,
  required String cpuWrestlerId,
  required int engineSeed,
  required int cpuPolicySeed,
  int maxActions = 500,
}) {
  final controller = CombatV1PlayableMatchController(
    _config(
      humanWrestlerId: humanWrestlerId,
      cpuWrestlerId: cpuWrestlerId,
      engineSeed: engineSeed,
      cpuPolicySeed: cpuPolicySeed,
      maxActions: maxActions,
    ),
  );
  driveMatch(controller, maxIterations: maxActions + 50);
  return controller;
}

void main() {
  group('79. Safety limit test', () {
    test('低いmaxActionsで強制発動し、勝敗を捏造しない', () {
      final controller = CombatV1PlayableMatchController(
        _config(maxActions: 3),
      );
      driveMatch(controller, maxIterations: 30);

      expect(controller.status, CombatV1PlayableControllerStatus.safetyLimit);
      final result = controller.result;
      expect(result, isNotNull);
      expect(result!.safetyLimitReached, isTrue);
      expect(result.winnerPlayerIndex, isNull, reason: '勝敗を捏造しない');
      expect(result.winnerWrestlerId, isNull);
      expect(result.terminalCause, isNull);
      expect(result.actionCount, lessThanOrEqualTo(3));
      expect(result.maxActions, 3);

      // snapshot/result integrity: submit不可・legalActions空。
      expect(controller.snapshot.isHumanInputRequired, isFalse);
      expect(controller.snapshot.legalActions, isEmpty);
    });
  });

  group('77. RNG determinism test', () {
    test('同一config・同一human選択・同一CPU seedなら'
        'action sequence/final state/termination/winnerが再現する', () {
      const humanWrestlerId = 'akari';
      const cpuWrestlerId = 'reina';
      const engineSeed = 555;
      const cpuPolicySeed = 999;

      final a = _driveFullMatch(
        humanWrestlerId: humanWrestlerId,
        cpuWrestlerId: cpuWrestlerId,
        engineSeed: engineSeed,
        cpuPolicySeed: cpuPolicySeed,
      );
      final b = _driveFullMatch(
        humanWrestlerId: humanWrestlerId,
        cpuWrestlerId: cpuWrestlerId,
        engineSeed: engineSeed,
        cpuPolicySeed: cpuPolicySeed,
      );

      expect(a.status, isNot(CombatV1PlayableControllerStatus.error));
      expect(_matchSignature(a), _matchSignature(b));
      expect(a.snapshot.actionCount, b.snapshot.actionCount);
      expect(a.snapshot.turnNumber, b.snapshot.turnNumber);
      expect(a.result?.winnerPlayerIndex, b.result?.winnerPlayerIndex);
      expect(a.result?.terminalCause, b.result?.terminalCause);

      // recentObservationsの末尾（実行されたaction列の直近部分）も一致する
      // ——RNG instance再生成が起きていないことの間接確認。
      final aObs = a.snapshot.recentObservations
          .map((o) => '${o.actorPlayerIndex}:${o.action}')
          .toList();
      final bObs = b.snapshot.recentObservations
          .map((o) => '${o.actorPlayerIndex}:${o.action}')
          .toList();
      expect(aObs, bObs);
    });
  });

  group('78. Different seed test', () {
    test('異なるengineSeedでは、少なくとも1組はaction sequence identityが'
        '変化する（winner差をassertしない）', () {
      const humanWrestlerId = 'misaki';
      const cpuWrestlerId = 'jack';

      final signatures = <int, String>{};
      for (final seed in [1, 2, 3, 4, 5]) {
        final controller = _driveFullMatch(
          humanWrestlerId: humanWrestlerId,
          cpuWrestlerId: cpuWrestlerId,
          engineSeed: seed,
          cpuPolicySeed: seed + 1000,
        );
        signatures[seed] = _matchSignature(controller);
      }

      expect(
        signatures.values.toSet().length,
        greaterThan(1),
        reason: '5個のseedすべてが同一signatureになりました（RNG seedが'
            '結果へ反映されていない可能性）: $signatures',
      );

      // seed metadataそのものはconfigの値をそのまま転記しているだけである
      // ことも確認する。
      final controllerA = _driveFullMatch(
        humanWrestlerId: humanWrestlerId,
        cpuWrestlerId: cpuWrestlerId,
        engineSeed: 42,
        cpuPolicySeed: 43,
      );
      expect(controllerA.result?.engineSeed, 42);
      expect(controllerA.result?.cpuPolicySeed, 43);
    });
  });

  group('83. Observation retention test', () {
    test('recentObservationsは上限を超えたら古いものを破棄する'
        '（O(totalActions)保持にしない）', () {
      final controller = CombatV1PlayableMatchController(
        _config(maxActions: 40),
      );
      driveMatch(controller, maxIterations: 60);

      final snap = controller.snapshot;
      expect(snap.actionCount, greaterThan(8));
      expect(snap.recentObservations.length, lessThanOrEqualTo(8));

      // 直近の履歴のみを保持している——末尾のactionIndexは
      // actionCount-1と一致する。
      if (snap.recentObservations.isNotEmpty) {
        expect(snap.recentObservations.last.actionIndex, snap.actionCount - 1);
        // actionIndexは連続増加している（bounded windowの中身の整合性）。
        for (var i = 1; i < snap.recentObservations.length; i++) {
          expect(
            snap.recentObservations[i].actionIndex,
            snap.recentObservations[i - 1].actionIndex + 1,
          );
        }
      }
    });
  });

  group('76. Hidden information test', () {
    test('CPU手札の物理カード（instanceId）はHuman手番中のlegalActions・'
        'Human handのいずれにも一切現れない', () {
      const humanWrestlerId = 'misaki';
      const cpuWrestlerId = 'jack';
      const engineSeed = 321;

      final allCpuInstanceIds = _fullDeckInstanceIds(
        wrestlerId: cpuWrestlerId,
        engineSeed: engineSeed,
        playerSuffix: 'cpu',
      );
      final allHumanInstanceIds = _fullDeckInstanceIds(
        wrestlerId: humanWrestlerId,
        engineSeed: engineSeed,
        playerSuffix: 'human',
      );
      // 前提: Human/CPUのdeck universeは互いに素（owner namespace分離）。
      expect(allCpuInstanceIds.intersection(allHumanInstanceIds), isEmpty);

      final controller = CombatV1PlayableMatchController(
        _config(
          humanWrestlerId: humanWrestlerId,
          cpuWrestlerId: cpuWrestlerId,
          engineSeed: engineSeed,
        ),
      );

      var iterations = 0;
      while (controller.status == CombatV1PlayableControllerStatus.active &&
          iterations < 200) {
        iterations += 1;
        final snap = controller.snapshot;

        // Human handのinstanceIdはCPU universeと一切重ならない。
        final humanHandIds = snap.human.hand.map((c) => c.instanceId).toSet();
        expect(
          humanHandIds.intersection(allCpuInstanceIds),
          isEmpty,
          reason: 'Human handにCPUの物理カードIDが漏洩しています',
        );

        // legalActions（Human手番の場合のみ非空）のcardInstanceIdもCPU
        // universeと重ならない。
        final legalCardIds = snap.legalActions
            .map((a) => a.cardInstanceId)
            .whereType<String>()
            .toSet();
        expect(
          legalCardIds.intersection(allCpuInstanceIds),
          isEmpty,
          reason: 'legalActionsにCPUの物理カードIDが漏洩しています',
        );

        // CPUの手番中はlegalActions自体が常に空でなければならない。
        if (!snap.isHumanInputRequired &&
            snap.status == CombatV1PlayableControllerStatus.active) {
          expect(snap.legalActions, isEmpty);
        }

        if (snap.isHumanInputRequired) {
          final action = chooseFirstLegalHumanAction(snap);
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

      // 少なくとも数actionは実際に進行したことを確認する
      // （no-opのまま終わっていないか）。
      expect(controller.snapshot.actionCount, greaterThan(0));

      // recentObservationsに現れるCPU actionは、CPU universeに含まれる
      // 正当なcardInstanceIdのみで構成される（宣言済みのカードは公開情報
      // のため、これは「隠すべきでない情報」の確認）。
      for (final observation in controller.snapshot.recentObservations) {
        if (observation.actorPlayerIndex ==
                CombatV1PlayableMatchController.cpuPlayerIndex &&
            observation.action.cardInstanceId != null) {
          expect(
            allCpuInstanceIds,
            contains(observation.action.cardInstanceId),
          );
        }
      }
    });
  });

  group('85. Integration full-match test', () {
    for (final pair in [
      ('misaki', 'jack', 11),
      ('akari', 'reina', 22),
      ('misaki', 'misaki', 33),
    ]) {
      final (humanWrestlerId, cpuWrestlerId, seed) = pair;
      test('$humanWrestlerId vs $cpuWrestlerId（seed=$seed）: '
          'crashなく完走し、valid terminal resultを返す', () {
        final controller = _driveFullMatch(
          humanWrestlerId: humanWrestlerId,
          cpuWrestlerId: cpuWrestlerId,
          engineSeed: seed,
          cpuPolicySeed: seed * 7 + 3,
        );

        expect(
          controller.status,
          anyOf(
            CombatV1PlayableControllerStatus.matchOver,
            CombatV1PlayableControllerStatus.safetyLimit,
          ),
          reason: controller.snapshot.diagnosticMessage ?? '',
        );

        final result = controller.result;
        expect(result, isNotNull);
        expect(result!.actionCount, greaterThan(0));
        expect(result.finalTurnNumber, greaterThanOrEqualTo(1));
        expect(result.humanWrestlerId, humanWrestlerId);
        expect(result.cpuWrestlerId, cpuWrestlerId);
        expect(result.engineSeed, seed);

        if (result.status == CombatV1PlayableControllerStatus.matchOver) {
          expect(result.winnerPlayerIndex, anyOf(0, 1));
          expect(result.winnerWrestlerId, anyOf(humanWrestlerId, cpuWrestlerId));
          expect(result.terminalCause, isNotNull);
        } else {
          expect(result.winnerPlayerIndex, isNull);
        }
      });
    }
  });
}
