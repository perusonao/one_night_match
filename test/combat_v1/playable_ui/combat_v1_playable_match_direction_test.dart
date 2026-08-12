// Combat Ver.1 Playable 2A-2 — Match Direction derivation logic tests
// （lib/src/combat_v1/playable_ui/combat_v1_playable_match_direction.dart、
// docs/design/combat_v1_playable_match_ui.md「70章」）。
//
// widget treeを一切構築しない、pure derivation関数のみのtest。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_controller.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_direction.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

const int _human = CombatV1PlayableMatchController.humanPlayerIndex;
const int _cpu = 1;

CombatV1PlayableMatchDirection? _derive(
  CombatV1PlayableMatchSnapshot snapshot,
) => combatV1PlayableDeriveMatchDirection(snapshot, humanPlayerIndex: _human);

void main() {
  group('match start / neutral state', () {
    test('該当する強い信号が無い場合はwin path全体像を1度だけ示す', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 100, koc: 9, posture: CombatV1WrestlerPosture.stand),
        human: testHumanStatus(posture: CombatV1WrestlerPosture.stand),
        sharedHeat: 0,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.neutral);
      expect(direction.primary, isNotEmpty);
    });
  });

  group('opponent HP', () {
    test('high（閾値超過）— submission/HP0の特別扱いをしない', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 150, koc: 9),
        submissionHpThreshold: 50,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, isNot(CombatV1PlayableMatchDirectionKind.submissionRoute));
      expect(direction.kind, isNot(CombatV1PlayableMatchDirectionKind.hpZeroClarify));
    });

    test('low（閾値以下・0より大）— submission route', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 40, koc: 9),
        submissionHpThreshold: 50,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.submissionRoute);
      expect(direction.primary, contains('Submission'));
    });

    test('zero — HP0だけでは決着しないことを明示する', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 0, koc: 9),
        submissionHpThreshold: 50,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.hpZeroClarify);
      expect(direction.primary, contains('0'));
      expect(direction.primary, contains('決着しません'));
    });
  });

  group('opponent KOC', () {
    test('high — 決着断定しない', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 150, koc: 10),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, isNot(CombatV1PlayableMatchDirectionKind.decisiveKoc));
    });

    test('low（非0）— 決着断定しない（誤ったKOC=life単純化をしない）', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 150, koc: 1),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, isNot(CombatV1PlayableMatchDirectionKind.decisiveKoc));
    });

    test('zero — 次に成立したPIN/Submissionで決着することを示す（最優先）', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 150, koc: 0, posture: CombatV1WrestlerPosture.stand),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.decisiveKoc);
      expect(direction.primary, contains('KOC'));
      expect(direction.secondary, contains('PIN'));
    });
  });

  group('opponent posture', () {
    test('STAND — DOWN routeを示さない', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(koc: 9, posture: CombatV1WrestlerPosture.stand),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, isNot(CombatV1PlayableMatchDirectionKind.opponentDownRoute));
    });

    test('DOWN（PIN非合法）— DOWNからPINへ繋がる道筋を示す', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(koc: 9, posture: CombatV1WrestlerPosture.down),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.opponentDownRoute);
      // Playable 2A-1の「相手はDOWN中 — PINや一部Techniqueにつながる
      // 重要な状態です」と一字一句重複させない。
      expect(direction.primary, isNot(contains('相手はDOWN中')));
    });
  });

  group('PIN legality', () {
    // Review Findings Fix（Minor）——「PINで相手のKOCを削りましょう」
    // （旧文言）はGuidanceの「PIN可能 — 相手のKOCを削り、決着を狙えます」
    // とほぼ同じ内容を繰り返していた。DirectionはPINのlegalityそのもの
    // （Guidanceの役割）を反復せず、KOCという勝ち筋resourceの意味を
    // 述べるだけにとどめる。
    test('legal — KOCという勝ち筋resourceの意味を示す（Guidanceの'
        '「PIN可能」文言とは重複させない）', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(koc: 9, posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: _human),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.pinOpportunity);
      expect(direction.primary, contains('KOC'));
      expect(direction.secondary, contains('KOC'));
      // Guidanceの既存文言（2A-1）と一字一句重複させない。
      expect(direction.primary, isNot(contains('PIN可能')));
      expect(direction.primary, isNot(contains('決着を狙えます')));
    });

    test('illegal（相手DOWNだがPINなし）— opponentDownRouteへfallback', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(koc: 9, posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: _human, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.opponentDownRoute);
    });
  });

  group('Shared HEAT', () {
    test('閾値未満 — Finisher routeを示さない', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(koc: 9, posture: CombatV1WrestlerPosture.stand),
        sharedHeat: 199,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, isNot(CombatV1PlayableMatchDirectionKind.finisherRoute));
    });

    test('閾値以上（他の信号無し）— Finisher routeを示す。'
        '2A-1と同じ「HEAT到達」文言は重複させない', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 150, koc: 9, posture: CombatV1WrestlerPosture.stand),
        human: testHumanStatus(posture: CombatV1WrestlerPosture.stand),
        sharedHeat: 300,
        finisherHeatThreshold: 200,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.finisherRoute);
      expect(direction.primary, isNot(contains('HEAT到達')));
    });
  });

  group('Human自身のDOWN', () {
    test('相手のPIN条件の一部を満たすことを示す（他の強い信号が無い場合）', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(posture: CombatV1WrestlerPosture.down),
        cpu: testCpuStatus(hp: 150, koc: 9, posture: CombatV1WrestlerPosture.stand),
        sharedHeat: 0,
        legalActions: const [
          CombatV1StandUpAction(actorPlayerIndex: _human),
          CombatV1RestAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.humanDownRisk);
    });
  });

  group('Counter response phase', () {
    test('phase != actionでもDirectionは通常どおり計算される（PIN opportunityは主張しない）', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        pendingAttack: testPendingAttack(),
        cpu: testCpuStatus(hp: 150, koc: 9, posture: CombatV1WrestlerPosture.stand),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: _human, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.neutral);
    });
  });

  group('CPU turn', () {
    test('Human入力待ちでなくてもnullにしない（Guidanceと異なる挙動）', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: false,
        currentActorPlayerIndex: _cpu,
        cpu: testCpuStatus(hp: 150, koc: 9, posture: CombatV1WrestlerPosture.down),
        legalActions: const [],
      );
      final direction = _derive(snapshot)!;
      // legalActionsが空（CPUの手番のため非公開）でも、PINが合法だと
      // 誤って断定しない——opponentDownRouteへ安全にfallbackする。
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.opponentDownRoute);
    });
  });

  group('match over', () {
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

  group('priority ordering', () {
    test('相手KOC0が最優先——PIN legal／HP低下／相手DOWNが同時成立しても'
        'decisiveKocのみを返す', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(hp: 20, koc: 0, posture: CombatV1WrestlerPosture.down),
        submissionHpThreshold: 50,
        sharedHeat: 300,
        finisherHeatThreshold: 200,
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: _human),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.decisiveKoc);
    });

    test('PIN legalがHP低下／相手DOWN routeより優先される', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(hp: 20, koc: 9, posture: CombatV1WrestlerPosture.down),
        submissionHpThreshold: 50,
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: _human),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.pinOpportunity);
    });

    test('HP低下routeが相手DOWN routeより優先される', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(hp: 20, koc: 9, posture: CombatV1WrestlerPosture.down),
        submissionHpThreshold: 50,
        legalActions: const [
          // PINは非legal（このターンまだ技を成功させていない想定）。
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.submissionRoute);
    });
  });

  group('Hidden information safety', () {
    test('CPUのhandCount等hidden情報を一切参照しない（テキストへ出さない）', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(
          hp: 150,
          koc: 9,
          handCount: 5,
          posture: CombatV1WrestlerPosture.stand,
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      final allText = '${direction.primary} ${direction.secondary ?? ''}';
      expect(allText, isNot(contains('5')));
      expect(allText, isNot(contains('Counter')));
    });

    test('no hidden information dependency — CombatV1PlayableOpponentStatusは'
        '構造的にhand内容/hidden Energy/hidden Counterを保持しない', () {
      // CombatV1PlayableOpponentStatusのフィールドはhp/maxHp/koc/posture/
      // handCount/drawPileCount/discardPileCount/pinCardsHeld/
      // reshuffleCountのみ（16章）——Directionはこの型のフィールドしか
      // 参照できないため、hidden情報参照は構造的に不可能。
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 150, koc: 9, posture: CombatV1WrestlerPosture.stand),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      expect(_derive(snapshot), isNotNull);
    });
  });

  // Review Findings Fix（9章 Boundary Tests）——thresholdはsnapshot自身の
  // fieldから取り、テストロジック側でCoreのmagic numberを独自に
  // 再実装しない（同じ変数をsnapshot構築とassertion双方へ渡す）。
  group('Submission threshold boundary', () {
    const threshold = 50;

    test('HP == submissionHpThreshold（境界値）— submission routeになる', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(hp: threshold, koc: 9, posture: CombatV1WrestlerPosture.stand),
        submissionHpThreshold: threshold,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.submissionRoute);
    });

    test('HP == submissionHpThreshold + 1（境界値の外）— submission routeにならない', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(
          hp: threshold + 1,
          koc: 9,
          posture: CombatV1WrestlerPosture.stand,
        ),
        submissionHpThreshold: threshold,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, isNot(CombatV1PlayableMatchDirectionKind.submissionRoute));
    });
  });

  group('HEAT threshold boundary', () {
    const heatThreshold = 200;

    test('sharedHeat == finisherHeatThreshold（境界値）— finisher routeになる', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 150, koc: 9, posture: CombatV1WrestlerPosture.stand),
        human: testHumanStatus(posture: CombatV1WrestlerPosture.stand),
        sharedHeat: heatThreshold,
        finisherHeatThreshold: heatThreshold,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.finisherRoute);
    });

    test('sharedHeat == finisherHeatThreshold - 1（境界値の外）— finisher routeにならない', () {
      final snapshot = testSnapshot(
        cpu: testCpuStatus(hp: 150, koc: 9, posture: CombatV1WrestlerPosture.stand),
        human: testHumanStatus(posture: CombatV1WrestlerPosture.stand),
        sharedHeat: heatThreshold - 1,
        finisherHeatThreshold: heatThreshold,
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, isNot(CombatV1PlayableMatchDirectionKind.finisherRoute));
    });
  });

  // Review Findings Fix（9章 Priority collisions）——到達可能なCore state
  // の組み合わせのみを対象とする。
  group('Priority collisions', () {
    test('KOC 0 + PIN legal — decisiveKocが優先される', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(hp: 100, koc: 0, posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1PinAction(actorPlayerIndex: _human),
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.decisiveKoc);
    });

    test('KOC 0 + Human DOWN — decisiveKocが優先される', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(hp: 100, koc: 0, posture: CombatV1WrestlerPosture.stand),
        human: testHumanStatus(posture: CombatV1WrestlerPosture.down),
        legalActions: const [
          CombatV1StandUpAction(actorPlayerIndex: _human),
          CombatV1RestAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.decisiveKoc);
    });

    test('HP 0 + KOC 0 — decisiveKocが優先される（hpZeroClarifyより上位）', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(hp: 0, koc: 0, posture: CombatV1WrestlerPosture.stand),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: _human)],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.decisiveKoc);
    });

    test('submission threshold + opponent DOWN — submissionRouteが優先される', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        cpu: testCpuStatus(hp: 30, koc: 9, posture: CombatV1WrestlerPosture.down),
        submissionHpThreshold: 50,
        legalActions: const [
          // このターンまだ技を成功させていない想定でPINは非legal。
          CombatV1EndTurnAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.submissionRoute);
    });

    test('CPU turn + KOC 0 — CPUの手番でもdecisiveKocを表示する', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: false,
        currentActorPlayerIndex: _cpu,
        cpu: testCpuStatus(hp: 100, koc: 0, posture: CombatV1WrestlerPosture.stand),
        legalActions: const [],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.decisiveKoc);
    });

    test('Counter response + 脆弱な相手（HP低下）— submissionRouteを示す'
        '（PIN opportunityは主張しない）', () {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        pendingAttack: testPendingAttack(),
        cpu: testCpuStatus(hp: 30, koc: 9, posture: CombatV1WrestlerPosture.stand),
        submissionHpThreshold: 50,
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: _human, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: _human),
        ],
      );
      final direction = _derive(snapshot)!;
      expect(direction.kind, CombatV1PlayableMatchDirectionKind.submissionRoute);
    });
  });
}
