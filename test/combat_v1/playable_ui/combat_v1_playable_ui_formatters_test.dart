// Combat Ver.1 Playable 1B — pure formatter tests
// （lib/src/combat_v1/playable_ui/combat_v1_playable_ui_formatters.dart）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_lifecycle.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_ui_formatters.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

void main() {
  group('combatV1PlayableWrestlerDisplayName', () {
    test('production wrestlerIdをregistryの表示名へ解決する', () {
      expect(combatV1PlayableWrestlerDisplayName('misaki'), isNotEmpty);
      expect(combatV1PlayableWrestlerDisplayName('jack'), isNotEmpty);
      expect(combatV1PlayableWrestlerDisplayName('akari'), isNotEmpty);
      expect(combatV1PlayableWrestlerDisplayName('reina'), isNotEmpty);
    });

    test('未知のwrestlerIdはfail-fastする', () {
      expect(
        () => combatV1PlayableWrestlerDisplayName('unknown-wrestler'),
        throwsStateError,
      );
    });
  });

  group('combatV1PlayableWrestlerOrder', () {
    test('production 4 wrestlerを固定順で持つ', () {
      expect(combatV1PlayableWrestlerOrder, ['misaki', 'jack', 'akari', 'reina']);
    });
  });

  group('combatV1PlayableActorLabel', () {
    test('試合終了時は常に「試合終了」', () {
      expect(
        combatV1PlayableActorLabel(
          status: CombatV1PlayableControllerStatus.matchOver,
          phase: CombatV1MatchPhase.turnEnd,
          isHumanInputRequired: false,
          currentActorPlayerIndex: null,
          hasPendingAttack: false,
        ),
        '試合終了',
      );
    });

    test('Human手番・非Counter局面は「あなたのターン」', () {
      expect(
        combatV1PlayableActorLabel(
          status: CombatV1PlayableControllerStatus.active,
          phase: CombatV1MatchPhase.action,
          isHumanInputRequired: true,
          currentActorPlayerIndex: 0,
          hasPendingAttack: false,
        ),
        'あなたのターン',
      );
    });

    test('Human防御のCounter局面は「返し技を選択」', () {
      expect(
        combatV1PlayableActorLabel(
          status: CombatV1PlayableControllerStatus.active,
          phase: CombatV1MatchPhase.counterResponsePending,
          isHumanInputRequired: true,
          currentActorPlayerIndex: 0,
          hasPendingAttack: true,
        ),
        '返し技を選択',
      );
    });

    test('CPU手番・非Counter局面は「CPU行動中」', () {
      expect(
        combatV1PlayableActorLabel(
          status: CombatV1PlayableControllerStatus.active,
          phase: CombatV1MatchPhase.action,
          isHumanInputRequired: false,
          currentActorPlayerIndex: 1,
          hasPendingAttack: false,
        ),
        'CPU行動中',
      );
    });

    test('CPU防御のCounter局面は「CPUが返し技を選択」', () {
      expect(
        combatV1PlayableActorLabel(
          status: CombatV1PlayableControllerStatus.active,
          phase: CombatV1MatchPhase.counterResponsePending,
          isHumanInputRequired: false,
          currentActorPlayerIndex: 1,
          hasPendingAttack: true,
        ),
        'CPUが返し技を選択',
      );
    });
  });

  group('combatV1PlayableTerminalCauseLabel', () {
    test('10パターンをすべて機械的にmapする', () {
      expect(
        combatV1PlayableTerminalCauseLabel(CombatV1MatchTerminalCause.normalPin),
        'PIN',
      );
      expect(
        combatV1PlayableTerminalCauseLabel(CombatV1MatchTerminalCause.directPin),
        'Direct PIN',
      );
      expect(
        combatV1PlayableTerminalCauseLabel(CombatV1MatchTerminalCause.submission),
        'Submission',
      );
      expect(
        combatV1PlayableTerminalCauseLabel(
          CombatV1MatchTerminalCause.submissionFinisher,
        ),
        'Submission Finisher',
      );
      expect(
        combatV1PlayableTerminalCauseLabel(CombatV1MatchTerminalCause.other),
        'Match Over',
      );
    });
  });

  group('combatV1PlayablePostureLabel', () {
    test('STAND/DOWNを表示する', () {
      expect(
        combatV1PlayablePostureLabel(CombatV1WrestlerPosture.stand),
        'STAND',
      );
      expect(combatV1PlayablePostureLabel(CombatV1WrestlerPosture.down), 'DOWN');
    });
  });

  group('combatV1PlayableActionKindLabel', () {
    test('declineCounterはraw名ではなく人間可読な文言', () {
      final label = combatV1PlayableActionKindLabel(
        CombatV1LegalActionKind.declineCounter,
      );
      expect(label, isNot('Decline Counter'));
      expect(label, isNotEmpty);
    });

    test('8 kind全てにlabelがある', () {
      for (final kind in CombatV1LegalActionKind.values) {
        expect(combatV1PlayableActionKindLabel(kind), isNotEmpty);
      }
    });

    // Playable 2A-5「8章 Japanese Primary Actions」——プレイヤーが直接
    // 触るbuttonは日本語を基本にする。PINはゲーム内用語として定着して
    // いるため例外的に維持する。
    test('主要操作buttonは日本語、PINはゲーム用語として維持する', () {
      expect(
        combatV1PlayableActionKindLabel(CombatV1LegalActionKind.technique),
        '技を使う',
      );
      expect(
        combatV1PlayableActionKindLabel(CombatV1LegalActionKind.discard),
        '手札を捨てる',
      );
      expect(
        combatV1PlayableActionKindLabel(CombatV1LegalActionKind.counter),
        '返し技を使う',
      );
      expect(
        combatV1PlayableActionKindLabel(CombatV1LegalActionKind.declineCounter),
        '返し技を使わない',
      );
      expect(
        combatV1PlayableActionKindLabel(CombatV1LegalActionKind.rest),
        '休む',
      );
      expect(
        combatV1PlayableActionKindLabel(CombatV1LegalActionKind.standUp),
        '立ち上がる',
      );
      expect(
        combatV1PlayableActionKindLabel(CombatV1LegalActionKind.endTurn),
        'ターン終了',
      );
      expect(
        combatV1PlayableActionKindLabel(CombatV1LegalActionKind.pin),
        'PIN',
      );
    });
  });

  group('combatV1PlayableObservationLabel', () {
    test('Human自身のactionはYOUプレフィックス', () {
      final observation = testObservation(
        actorPlayerIndex: 0,
        action: const CombatV1EndTurnAction(actorPlayerIndex: 0),
      );
      expect(
        combatV1PlayableObservationLabel(observation, humanPlayerIndex: 0),
        startsWith('YOU:'),
      );
    });

    test('CPUのactionはCPUプレフィックス', () {
      final observation = testObservation(
        actorPlayerIndex: 1,
        action: const CombatV1RestAction(actorPlayerIndex: 1),
      );
      expect(
        combatV1PlayableObservationLabel(observation, humanPlayerIndex: 0),
        startsWith('CPU:'),
      );
    });
  });

  group('combatV1PlayableEnergyCostLabel', () {
    test('0の属性は表示しない', () {
      final label = combatV1PlayableEnergyCostLabel({
        CombatV1EnergyAttribute.strike: 1,
        CombatV1EnergyAttribute.joint: 0,
      });
      expect(label, contains('打'));
      expect(label, isNot(contains('関')));
    });

    test('空・全0はハイフン', () {
      expect(combatV1PlayableEnergyCostLabel(const {}), '-');
    });
  });

  group('combatV1PlayableEnergyComparisonLabel（GitHub Codex App Finding、'
      'PR #22）', () {
    test('具体属性が不足していても＊(wild)を分母へ加算する', () {
      // Cost 打2に対し、具体的な打の使用可能量は1のみだが＊が1あるため、
      // TECHNIQUE支払いは常にwild補完を許可する（docs/combat_rules_v1.md
      // 5.1章）ことにより実際は支払い可能（isUsable==trueになりうる）。
      // 分母が具体属性のみ（1）だと「打2 / 1」に見え、支払い不可能だと
      // 誤解させる——＊込みの2でなければならない。
      final cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2});
      final label = combatV1PlayableEnergyComparisonLabel(cost, {
        CombatV1EnergyAttribute.strike: 1,
        CombatV1EnergyAttribute.wild: 1,
      });
      expect(label, '打2 / 2');
    });

    test('＊が無い場合は具体属性の使用可能量のみを表示する（従来どおり）', () {
      final cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2});
      final label = combatV1PlayableEnergyComparisonLabel(cost, {
        CombatV1EnergyAttribute.strike: 3,
      });
      expect(label, '打2 / 3');
    });

    test('複数属性costでも、それぞれへ同じ＊使用可能量を加算する', () {
      final cost = CombatV1EnergyCost({
        CombatV1EnergyAttribute.strike: 2,
        CombatV1EnergyAttribute.throwing: 1,
      });
      final label = combatV1PlayableEnergyComparisonLabel(cost, {
        CombatV1EnergyAttribute.strike: 1,
        CombatV1EnergyAttribute.throwing: 0,
        CombatV1EnergyAttribute.wild: 1,
      });
      expect(label, '打2 / 2 ・ 投1 / 1');
    });

    test('costが空の場合はハイフン', () {
      expect(
        combatV1PlayableEnergyComparisonLabel(CombatV1EnergyCost.zero, {
          CombatV1EnergyAttribute.wild: 3,
        }),
        '-',
      );
    });
  });

  // Playable 2A-6「5章 Technique Identity Readability」——短縮形
  // （displayLabel）と1:1対応するfull-word labelがすべてのenum値へ
  // 定義されていること、新しいcategorizationを作らず既存6値のみを
  // 対象にしていることを検証する。
  group('combatV1PlayableEnergyAttributeFullLabel', () {
    test('全ての属性へfull-word labelが定義されている', () {
      const expected = {
        CombatV1EnergyAttribute.strike: '打撃',
        CombatV1EnergyAttribute.joint: '関節技',
        CombatV1EnergyAttribute.throwing: '投げ技',
        CombatV1EnergyAttribute.aerial: '飛び技',
        CombatV1EnergyAttribute.rough: 'ラフファイト',
        CombatV1EnergyAttribute.wild: 'ワイルド',
      };
      for (final attribute in CombatV1EnergyAttribute.values) {
        expect(
          combatV1PlayableEnergyAttributeFullLabel(attribute),
          expected[attribute],
          reason: '$attributeのfull-word labelが一致しない',
        );
      }
    });

    test('既存displayLabel（短縮形）と異なる、より長い表記である', () {
      for (final attribute in CombatV1EnergyAttribute.values) {
        final full = combatV1PlayableEnergyAttributeFullLabel(attribute);
        expect(full, isNot(attribute.displayLabel));
        expect(full.length, greaterThan(attribute.displayLabel.length));
      }
    });
  });
}
