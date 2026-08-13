// Combat Ver.1 Playable 2A-4 — Counter Prevention Projection
// （Review Findings Fix、Major）。
//
// `combatV1PlayableWouldTransitionToDirectPin`/
// `combatV1PlayableWouldTransitionToSubmission`
// （`lib/src/combat_v1/playable/combat_v1_playable_counter_prevention.dart`）
// が、Core `combat_v1_engine.dart` `_resolvePendingAttack`と同じDOWN
// posture/HP閾値条件を再現しているかを、synthetic入力による純粋関数
// テストとして検証する（production wrestlerのシナリオ探索に依存しない）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_counter_prevention.dart';

void main() {
  group('Direct PIN', () {
    // Case 1: normal Direct PIN、resultOpponentState == DOWN → true。
    test('resultOpponentStateがDOWNを直接指定していればtrue', () {
      expect(
        combatV1PlayableWouldTransitionToDirectPin(
          effectiveDirectPin: true,
          resultOpponentState: CombatV1WrestlerPosture.down,
          defenderPostureBeforeResolution: CombatV1WrestlerPosture.stand,
        ),
        isTrue,
      );
    });

    // Case 2: normal Direct PIN、defender STAND、resultOpponentState ==
    // null → false（解決後もSTANDのまま、PIN移行なし）。
    test(
      'resultOpponentStateがnullで防御側がSTANDのままならfalse',
      () {
        expect(
          combatV1PlayableWouldTransitionToDirectPin(
            effectiveDirectPin: true,
            resultOpponentState: null,
            defenderPostureBeforeResolution: CombatV1WrestlerPosture.stand,
          ),
          isFalse,
        );
      },
    );

    // Case 3: normal Direct PIN、防御側が既にDOWN、resultOpponentState ==
    // null → Coreの`pending.resultOpponentState ?? state.opponent.posture`
    // は既存DOWNをそのまま維持するため、trueと一致する。
    test('防御側が既にDOWNでresultOpponentStateがnullでもtrue', () {
      expect(
        combatV1PlayableWouldTransitionToDirectPin(
          effectiveDirectPin: true,
          resultOpponentState: null,
          defenderPostureBeforeResolution: CombatV1WrestlerPosture.down,
        ),
        isTrue,
      );
    });

    // Case 4: Direct PIN FINISHER、DOWN transition成立 → true
    // （呼び出し側でFINISHER優先順位を適用済みのeffectiveDirectPin: true
    // を渡すだけで、この関数自体はNORMAL/FINISHERを区別しない）。
    test('FINISHERでもDOWN transition成立ならtrue', () {
      expect(
        combatV1PlayableWouldTransitionToDirectPin(
          effectiveDirectPin: true,
          resultOpponentState: CombatV1WrestlerPosture.down,
          defenderPostureBeforeResolution: CombatV1WrestlerPosture.stand,
        ),
        isTrue,
      );
    });

    // Case 5: Direct PIN FINISHER、DOWN transition不成立 → false。
    test('FINISHERでもDOWN transition不成立ならfalse', () {
      expect(
        combatV1PlayableWouldTransitionToDirectPin(
          effectiveDirectPin: true,
          resultOpponentState: null,
          defenderPostureBeforeResolution: CombatV1WrestlerPosture.stand,
        ),
        isFalse,
      );
    });

    test('effectiveDirectPinがfalseなら、DOWN条件を満たしていてもfalse', () {
      expect(
        combatV1PlayableWouldTransitionToDirectPin(
          effectiveDirectPin: false,
          resultOpponentState: CombatV1WrestlerPosture.down,
          defenderPostureBeforeResolution: CombatV1WrestlerPosture.stand,
        ),
        isFalse,
      );
    });
  });

  group('Submission', () {
    const rules = CombatV1RulesConfig(); // submissionHpThreshold == 50

    // Case 6: normal Submission、post-damage HP == threshold → true。
    test('damage適用後HPが閾値ちょうどならtrue', () {
      expect(
        combatV1PlayableWouldTransitionToSubmission(
          effectiveSubmissionHold: true,
          defenderHpBeforeResolution: 60,
          defenderMaxHp: 150,
          damage: 10,
          rules: rules,
        ),
        isTrue,
      );
    });

    // Case 7: normal Submission、post-damage HP == threshold + 1 →
    // false。
    test('damage適用後HPが閾値+1ならfalse', () {
      expect(
        combatV1PlayableWouldTransitionToSubmission(
          effectiveSubmissionHold: true,
          defenderHpBeforeResolution: 61,
          defenderMaxHp: 150,
          damage: 10,
          rules: rules,
        ),
        isFalse,
      );
    });

    // Case 8: normal Submission、damageによりthreshold内へ入る → true
    // （HP100からdamage60でpost-damage HP40 <= 50）。
    test('damageで閾値内へ入るならtrue', () {
      expect(
        combatV1PlayableWouldTransitionToSubmission(
          effectiveSubmissionHold: true,
          defenderHpBeforeResolution: 100,
          defenderMaxHp: 150,
          damage: 60,
          rules: rules,
        ),
        isTrue,
      );
    });

    test('damageが閾値内へ入らないほど小さければfalse（HP100・damage10）', () {
      expect(
        combatV1PlayableWouldTransitionToSubmission(
          effectiveSubmissionHold: true,
          defenderHpBeforeResolution: 100,
          defenderMaxHp: 150,
          damage: 10,
          rules: rules,
        ),
        isFalse,
      );
    });

    // Case 9: Submission FINISHER、Core上transition対象になる境界
    // （突入条件`submissionEligible`はNORMAL/FINISHERで同一——HP0でも
    // 突入自体は妨げられない、10.2章「HP0: 即GIVE UP」はESCAPE/GIVE UP
    // 判定側の特殊処理であり突入条件には影響しない）。
    test('FINISHERでpost-damage HPが0でも突入条件はtrue', () {
      expect(
        combatV1PlayableWouldTransitionToSubmission(
          effectiveSubmissionHold: true,
          defenderHpBeforeResolution: 30,
          defenderMaxHp: 150,
          damage: 999,
          rules: rules,
        ),
        isTrue,
      );
    });

    // Case 10: Submission FINISHER、transition対象にならない境界
    // （post-damage HPが閾値を超える）。
    test('FINISHERでもpost-damage HPが閾値を超えればfalse', () {
      expect(
        combatV1PlayableWouldTransitionToSubmission(
          effectiveSubmissionHold: true,
          defenderHpBeforeResolution: 150,
          defenderMaxHp: 150,
          damage: 1,
          rules: rules,
        ),
        isFalse,
      );
    });

    test('effectiveSubmissionHoldがfalseなら、HP条件を満たしていてもfalse', () {
      expect(
        combatV1PlayableWouldTransitionToSubmission(
          effectiveSubmissionHold: false,
          defenderHpBeforeResolution: 10,
          defenderMaxHp: 150,
          damage: 0,
          rules: rules,
        ),
        isFalse,
      );
    });

    test('damage適用後HPがマイナスになる場合も0にclampしてから閾値判定する', () {
      expect(
        combatV1PlayableWouldTransitionToSubmission(
          effectiveSubmissionHold: true,
          defenderHpBeforeResolution: 20,
          defenderMaxHp: 150,
          damage: 999,
          rules: rules,
        ),
        isTrue,
      );
    });
  });
}
