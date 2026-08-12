// Combat Ver.1 Playable 2A-1 — Match Guidance derivation logic tests
// （lib/src/combat_v1/playable_ui/combat_v1_playable_match_guidance.dart、
// docs/design/combat_v1_playable_match_ui.md「68章」）。
//
// widget treeを一切構築しない、pure derivation関数のみのtest。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_controller.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_guidance.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

const int _human = CombatV1PlayableMatchController.humanPlayerIndex;
const int _cpu = 1;

CombatV1PlayableMatchGuidance? _derive(
  CombatV1PlayableMatchSnapshot snapshot,
) => combatV1PlayableDeriveMatchGuidance(snapshot, humanPlayerIndex: _human);

void main() {
  group('Human入力待ちでない場合', () {
    test('CPU処理中はnull（人間へ操作を促さない）', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: false,
        currentActorPlayerIndex: _cpu,
        legalActions: const [],
      );
      expect(_derive(snapshot), isNull);
    });

    test('試合終了時はnull（Result overlayが担当）', () {
      final snapshot = testSnapshot(
        status: CombatV1PlayableControllerStatus.matchOver,
        isHumanInputRequired: false,
        currentActorPlayerIndex: null,
        legalActions: const [],
      );
      expect(_derive(snapshot), isNull);
    });
  });

  group('Discard phase', () {
    test('強制discardであることを示す', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.discard,
        isHumanInputRequired: true,
        legalActions: [
          CombatV1DiscardAction(actorPlayerIndex: _human, cardInstanceId: 'h1'),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.kind, CombatV1PlayableGuidanceKind.discard);
      expect(guidance.primary, contains('捨てて'));
      expect(guidance.secondary, isNotNull);
    });

    test('DOWN中のdiscardは、今すぐStand Upできると誤解させない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.discard,
        isHumanInputRequired: true,
        human: testHumanStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: [
          CombatV1DiscardAction(actorPlayerIndex: _human, cardInstanceId: 'h1'),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, contains('DOWN'));
      // discard中に「今すぐ」立ち上がれるかのような案内をしない。
      expect(guidance.secondary, isNot(contains('今すぐ')));
      expect(guidance.primary, isNot(contains('Stand Up')));
    });
  });

  group('DOWN decision（action phase・Human DOWN）', () {
    test('Stand Up / Restの意味を示す', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1StandUpAction(actorPlayerIndex: _human),
          CombatV1RestAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.kind, CombatV1PlayableGuidanceKind.downDecision);
      expect(guidance.primary, contains('Stand Up'));
      expect(guidance.primary, contains('Rest'));
      expect(guidance.secondary, contains('Rest'));
      // REST回復量はsnapshotに公開されていないため、数値を複製しない。
      expect(guidance.secondary, isNot(contains(RegExp(r'\d'))));
    });
  });

  group('Counter response', () {
    test('使用できるCounterがある場合は効果を補足する', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        pendingAttack: testPendingAttack(),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: _human, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.kind, CombatV1PlayableGuidanceKind.counterResponse);
      expect(guidance.primary, contains('Counter'));
      expect(guidance.secondary, isNotNull);
    });

    test('使用できるCounterが無い場合は効果を断定しない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        pendingAttack: testPendingAttack(),
        legalActions: const [
          CombatV1DeclineCounterAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, isNull);
    });
  });

  group('Action phase — primaryはlegalActionsだけを反映する', () {
    test('Technique/PIN/EndTurnが全て合法な場合', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        legalActions: const [
          CombatV1TechniqueAction(
            actorPlayerIndex: _human,
            cardInstanceId: 'h1',
          ),
          CombatV1PinAction(actorPlayerIndex: _human),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.kind, CombatV1PlayableGuidanceKind.action);
      expect(guidance.primary, contains('Technique'));
      expect(guidance.primary, contains('PIN'));
      expect(guidance.primary, contains('End Turn'));
    });

    test('PINが非合法な場合「PIN」を案内文へ含めない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        legalActions: const [
          CombatV1TechniqueAction(
            actorPlayerIndex: _human,
            cardInstanceId: 'h1',
          ),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.primary, isNot(contains('PIN')));
    });

    test('Techniqueが非合法な場合「Technique」を案内文へ含めない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.primary, isNot(contains('Technique')));
      expect(guidance.primary, contains('End Turn'));
    });
  });

  group('Context hint優先順位（action phase, 最大1件）', () {
    test('PIN機会 — legalActionsにPINが実在する場合のみ「PIN可能」と断定', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: _human),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, contains('PIN可能'));
    });

    test('PINが非合法な場合「PINできます」と誤表示しない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(posture: CombatV1WrestlerPosture.stand),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, isNot(contains('PIN可能')));
      expect(guidance.secondary, isNot(contains('PINできます')));
    });

    test('Shared HEATが閾値以上 — Finisher解禁のcontextを示す', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        sharedHeat: 200,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, contains('FINISHER解禁'));
    });

    test('Shared HEATが閾値未満では解禁contextを出さない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        sharedHeat: 199,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, isNot(contains('FINISHER解禁')));
    });

    test('相手DOWN（PIN非合法）— ルール上安全な表現に留める', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, contains('DOWN中'));
      expect(guidance.secondary, isNot(contains('PINできます')));
    });

    test('PIN可能 > Finisher解禁 > 相手DOWN の優先順位', () {
      // PINも合法、HEATも解禁済み、相手もDOWN——全て同時成立してもPINの
      // hintだけが返る。
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        sharedHeat: 300,
        finisherHeatThreshold: 200,
        cpu: testCpuStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: _human),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, contains('PIN可能'));
    });

    test('継続Technique — このターン中に既にTechnique使用済み、かつ現在も合法', () {
      final snapshot = testSnapshot(
        turnNumber: 2,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        recentObservations: [
          testObservation(
            turnNumber: 2,
            actorPlayerIndex: _human,
            action: const CombatV1TechniqueAction(
              actorPlayerIndex: _human,
              cardInstanceId: 'used-1',
            ),
          ),
        ],
        legalActions: const [
          CombatV1TechniqueAction(
            actorPlayerIndex: _human,
            cardInstanceId: 'h2',
          ),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, contains('Technique'));
      expect(guidance.secondary, contains('Energy'));
    });

    test('このターン未使用なら継続Techniqueのhintを出さない（毎ターン表示しない）', () {
      final snapshot = testSnapshot(
        turnNumber: 1,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        recentObservations: const [],
        legalActions: const [
          CombatV1TechniqueAction(
            actorPlayerIndex: _human,
            cardInstanceId: 'h1',
          ),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, isNull);
    });

    test('別ターンでのTechnique使用は継続hintの根拠にしない', () {
      final snapshot = testSnapshot(
        turnNumber: 3,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        recentObservations: [
          testObservation(
            turnNumber: 1,
            actorPlayerIndex: _human,
            action: const CombatV1TechniqueAction(
              actorPlayerIndex: _human,
              cardInstanceId: 'used-1',
            ),
          ),
        ],
        legalActions: const [
          CombatV1TechniqueAction(
            actorPlayerIndex: _human,
            cardInstanceId: 'h1',
          ),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, isNull);
    });

    test('特に該当するcontextが無ければsecondaryはnull', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        sharedHeat: 0,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, isNull);
    });
  });

  group('Hidden information safety', () {
    test('CPUのhandCount/hidden情報を一切参照しない（テキストへ出さない）', () {
      // CombatV1PlayableOpponentStatusはそもそもhand内容・hidden
      // Energy・hidden Counterを持たない（構造的に取得不能）ため、text
      // 生成側で漏らしようがないことを確認する回帰guard。
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(handCount: 5, posture: CombatV1WrestlerPosture.down),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      final allText = '${guidance.primary} ${guidance.secondary ?? ''}';
      expect(allText, isNot(contains('5')));
      expect(allText, isNot(contains('Counter')));
    });
  });
}
