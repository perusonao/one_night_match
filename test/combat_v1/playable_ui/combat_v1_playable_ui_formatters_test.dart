// Combat Ver.1 Playable 1B — pure formatter tests
// （lib/src/combat_v1/playable_ui/combat_v1_playable_ui_formatters.dart）。

import 'package:flutter_test/flutter_test.dart';
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
}
