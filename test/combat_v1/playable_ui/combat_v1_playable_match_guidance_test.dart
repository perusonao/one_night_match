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
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_ui_formatters.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

final _techniqueLabel = combatV1PlayableActionKindLabel(
  CombatV1LegalActionKind.technique,
);
final _standUpLabel = combatV1PlayableActionKindLabel(
  CombatV1LegalActionKind.standUp,
);
final _restLabel = combatV1PlayableActionKindLabel(
  CombatV1LegalActionKind.rest,
);
final _endTurnLabel = combatV1PlayableActionKindLabel(
  CombatV1LegalActionKind.endTurn,
);

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
      expect(guidance.primary, isNot(contains(_standUpLabel)));
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
      expect(guidance.primary, contains(_standUpLabel));
      expect(guidance.primary, contains(_restLabel));
      expect(guidance.secondary, contains(_restLabel));
      // 英語一文字列（'Stand Up'/'Rest'）を独自に複製していないこと
      // （Playable 2A-6「10章 Guidance Label Consistency」）。
      expect(guidance.primary, isNot(contains('Stand Up')));
      expect(guidance.secondary, isNot(contains('Rest')));
      // REST回復量はsnapshotに公開されていないため、数値を複製しない。
      expect(guidance.secondary, isNot(contains(RegExp(r'\d'))));
    });
  });

  group('Counter response', () {
    test('Counter可能: primaryにCounter選択、secondaryに無効化説明がある', () {
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
      expect(guidance.primary, contains('Counterするか'));
      expect(guidance.secondary, isNotNull);
      expect(guidance.secondary, contains('無効化'));
    });

    // Review Findings Fix（Major）——legalActionsがDecline Counterのみ
    // （＝Counter actionが1件も無い）場合に、primaryが存在しない
    // Counterという選択肢を提示していた回帰を防ぐguard。
    test('Counter不能: legalActionsがDecline Counterのみの場合、'
        '存在しないCounter選択を案内しない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        pendingAttack: testPendingAttack(),
        legalActions: const [
          CombatV1DeclineCounterAction(actorPlayerIndex: _human),
        ],
      );
      final guidance = _derive(snapshot)!;
      // legalActionsに実在する唯一の進行（技を受ける）を正しく説明する。
      expect(guidance.primary, contains('受け'));
      // 「Counterするか」のような、Counterが選べるかのような表現を
      // 一切含めない。
      expect(guidance.primary, isNot(contains('Counterするか')));
      expect(guidance.primary, isNot(contains('Counterを選択')));
      // Counter可能性を示すsecondaryも出さない。
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
      expect(guidance.primary, contains(_techniqueLabel));
      expect(guidance.primary, contains('PIN'));
      expect(guidance.primary, contains(_endTurnLabel));
      // 英語一文字列（'Technique'/'End Turn'）を独自に複製していない
      // こと（Playable 2A-6「10章 Guidance Label Consistency」）。
      expect(guidance.primary, isNot(contains('Technique')));
      expect(guidance.primary, isNot(contains('End Turn')));
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
      expect(guidance.primary, isNot(contains(_techniqueLabel)));
      expect(guidance.primary, contains(_endTurnLabel));
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

    // Review Findings Fix（Minor）——HEAT条件が満たされたことのみを
    // 述べ、「双方がFinisherを使用できる」とは断定しない。Human側の
    // legalActionsがEnd Turnのみ（Finisher actionが非legal）でも、
    // HEAT条件のcontext自体は表示してよい——「使用できる」という
    // 断定さえしなければLegalAction SSOTと矛盾しないため。
    test('Shared HEATが閾値以上 — HEAT条件到達のcontextを示す（使用可能とは断定しない）', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        sharedHeat: 200,
        finisherHeatThreshold: 200,
        // FinisherのLegalActionは存在しない——HEAT以外の条件
        // （card所持等）が満たされていない前提でも、文言が「使用
        // できる」と誤読される表現を含めてはいけない。
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, contains('FINISHER HEAT到達'));
      expect(guidance.secondary, contains('HEAT条件'));
      // 「使用できます」「使用可能」等、Finisherが実際にlegalである
      // かのような断定を含めない。
      expect(guidance.secondary, isNot(contains('使用でき')));
      expect(guidance.secondary, isNot(contains('使用可能')));
      expect(guidance.secondary, isNot(contains('使用条件を満たせます')));
    });

    test('Shared HEATが閾値未満ではHEAT到達contextを出さない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        sharedHeat: 199,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final guidance = _derive(snapshot)!;
      expect(guidance.secondary, isNot(contains('FINISHER HEAT到達')));
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

    test('PIN可能 > Shared HEAT到達 > 相手DOWN の優先順位', () {
      // PINも合法、HEATも閾値到達済み、相手もDOWN——全て同時成立してもPINの
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
      expect(guidance.secondary, contains(_techniqueLabel));
      expect(guidance.secondary, contains('Energy'));
      // 英語一文字列（'Technique'）を独自に複製していないこと
      // （Playable 2A-6「10章 Guidance Label Consistency」）。
      expect(guidance.secondary, isNot(contains('Technique')));
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
