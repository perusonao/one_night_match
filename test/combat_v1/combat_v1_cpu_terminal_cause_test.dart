// Combat Ver.1 Phase 11B — Codex Review Findings対応（Finding 2）。
//
// CombatV1CpuMatchRunnerの_classifyTerminalCauseは、CombatV1Engineの
// private実装（_resolvePendingAttackのeffectiveDirectPin/
// effectiveSubmissionHold導出）をCombatV1PendingAttackの公開field
// （category/finisherType/directPin/submissionHold）のみから再現している。
// このファイルは、その分類が現行Engine仕様と一致していることを、
// 10パターン（+補足1件）で直接検証する。分類ロジック自体は変更しない
// （テストのみ追加）。
//
// NORMAL/SIGNATURE: directPin/submissionHoldフィールドがそのまま使われる。
// FINISHER: directPin/submissionHoldフィールドは一切参照されず、
// finisherTypeのみが決着方式を決定する（docs/design/combat_v1_phase1_design.md
// 2.4章）。9/10はFINISHER normalの技にdirectPin/submissionHoldフラグを
// 意図的に矛盾設定し、それらが無視されることを確認する。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_cpu_match_runner.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decision_policy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

const CombatV1RulesConfig rules = fixtureRules;

/// [technique]をhandAへ1枚だけ持たせた状態からdeclareTechnique→
/// declineCounterの2 actionを実行し、その結果を返す（handBは常に空——
/// COUNTERが存在しないため必ずdeclineが選ばれる、fixtureTechniquesを
/// 汚さないテスト専用のlocal catalogを使う）。
CombatV1CpuMatchResult _runDeclinePath({
  required CombatV1Technique technique,
  int sharedHeat = 0,
  int defenderKoc = 0,
  // fx_finisher_bのようにresultOpponentStateを持たない技は、DIRECT
  // PIN自動移行の判定（`resultOpponentState ?? state.opponent.posture`）が
  // 宣言時点の相手postureへfallbackするため、必要に応じてdown状態から
  // 開始できるようにする。
  CombatV1WrestlerPosture defenderPosture = CombatV1WrestlerPosture.stand,
}) {
  final catalog = CombatV1CardCatalog(
    techniques: {technique.id: technique},
    counters: const {},
  );
  final attackEntry = CombatV1DeckEntry(
    instanceId: 'atk',
    cardId: technique.id,
    category: technique.category,
  );
  final state = buildMatchState(
    handA: [attackEntry],
    handB: const [],
    kocB: defenderKoc,
    sharedHeat: sharedHeat,
    postureB: defenderPosture,
  );
  final runner = CombatV1CpuMatchRunner(catalog: catalog, rules: rules, maxActions: 2);
  return runner.run(
    state,
    policyA: const CombatV1FirstLegalPolicy(),
    policyB: const CombatV1FirstLegalPolicy(),
    engineRandom: Random(1),
  );
}

const CombatV1Technique _signatureDirectPin = CombatV1Technique(
  id: 'zz_signature_direct_pin',
  name: 'テスト固有技(directPin)',
  category: CombatV1CardCategory.signature,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
  damage: 20,
  heatGain: 20,
  resultOpponentState: CombatV1WrestlerPosture.down,
  directPin: true,
  family: CombatV1TechniqueFamily.suplex,
);

const CombatV1Technique _signatureSubmissionHold = CombatV1Technique(
  id: 'zz_signature_submission_hold',
  name: 'テスト固有技(submissionHold)',
  category: CombatV1CardCategory.signature,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
  damage: 110,
  heatGain: 20,
  submissionHold: true,
  family: CombatV1TechniqueFamily.armbar,
);

const CombatV1Technique _finisherNormalWithDirectPinFlag = CombatV1Technique(
  id: 'zz_finisher_normal_directpin_flag',
  name: 'テストフィニッシャー(normal、directPinフラグ矛盾設定)',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
  damage: 30,
  heatGain: 30,
  resultOpponentState: CombatV1WrestlerPosture.down,
  directPin: true, // finisherType==normalのため無視されるはず
  finisherType: CombatV1FinisherType.normal,
  family: CombatV1TechniqueFamily.lariat,
);

const CombatV1Technique _finisherNormalWithSubmissionHoldFlag = CombatV1Technique(
  id: 'zz_finisher_normal_submission_flag',
  name: 'テストフィニッシャー(normal、submissionHoldフラグ矛盾設定)',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 2}),
  damage: 130,
  heatGain: 30,
  submissionHold: true, // finisherType==normalのため無視されるはず
  finisherType: CombatV1FinisherType.normal,
  family: CombatV1TechniqueFamily.crossface,
);

void main() {
  test('1. normal PIN → normalPin', () {
    final state = buildMatchState(
      postureB: CombatV1WrestlerPosture.down,
      kocB: 0,
      lastSuccessfulTechnique: fixtureSuccessfulTechnique(
        attackerPlayerIndex: 0,
        turnNumber: 1,
      ),
    );
    final runner = CombatV1CpuMatchRunner(catalog: fixtureCatalog, rules: rules);
    final result = runner.run(
      state,
      policyA: const CombatV1FirstLegalPolicy(),
      policyB: const CombatV1FirstLegalPolicy(),
      engineRandom: Random(1),
    );

    expect(result.termination, CombatV1CpuMatchTermination.matchOver);
    expect(result.terminalCause, CombatV1CpuMatchTerminalCause.normalPin);
  });

  test('2. NORMAL directPin → directPin', () {
    final result = _runDeclinePath(
      technique: fixtureTechniques['fx_normal_direct_pin']!,
    );
    expect(result.termination, CombatV1CpuMatchTermination.matchOver);
    expect(result.terminalCause, CombatV1CpuMatchTerminalCause.directPin);
  });

  test('3. NORMAL submissionHold → submission', () {
    final result = _runDeclinePath(
      technique: fixtureTechniques['fx_normal_submission_hold']!,
    );
    expect(result.termination, CombatV1CpuMatchTermination.matchOver);
    expect(result.terminalCause, CombatV1CpuMatchTerminalCause.submission);
  });

  test('4. SIGNATURE directPin → directPin', () {
    final result = _runDeclinePath(technique: _signatureDirectPin);
    expect(result.termination, CombatV1CpuMatchTermination.matchOver);
    expect(result.terminalCause, CombatV1CpuMatchTerminalCause.directPin);
  });

  test('5. SIGNATURE submissionHold → submission', () {
    final result = _runDeclinePath(technique: _signatureSubmissionHold);
    expect(result.termination, CombatV1CpuMatchTermination.matchOver);
    expect(result.terminalCause, CombatV1CpuMatchTerminalCause.submission);
  });

  test('6. FINISHER normal → 自動決着なし（terminalCause null）', () {
    final result = _runDeclinePath(
      technique: fixtureTechniques['fx_finisher_a']!,
      sharedHeat: rules.finisherHeatThreshold,
    );
    expect(result.termination, CombatV1CpuMatchTermination.safetyLimit);
    expect(result.terminalCause, isNull);
  });

  test('7. FINISHER directPin → directPin', () {
    final result = _runDeclinePath(
      technique: fixtureTechniques['fx_finisher_b']!,
      sharedHeat: rules.finisherHeatThreshold,
      // fx_finisher_bはresultOpponentStateを持たないため、DIRECT
      // PIN自動移行の判定が宣言時点の相手postureへfallbackする
      // （combat_v1_engine.dartの`_resolvePendingAttack`参照）。
      defenderPosture: CombatV1WrestlerPosture.down,
    );
    expect(result.termination, CombatV1CpuMatchTermination.matchOver);
    expect(result.terminalCause, CombatV1CpuMatchTerminalCause.directPin);
  });

  test('8. FINISHER submission → submissionFinisher', () {
    final result = _runDeclinePath(
      technique: fixtureTechniques['fx_finisher_c']!,
      sharedHeat: rules.finisherHeatThreshold,
    );
    expect(result.termination, CombatV1CpuMatchTermination.matchOver);
    expect(result.terminalCause, CombatV1CpuMatchTerminalCause.submissionFinisher);
  });

  test('9. FINISHER normal + directPin flag → flagは無視され自動決着なし', () {
    final result = _runDeclinePath(
      technique: _finisherNormalWithDirectPinFlag,
      sharedHeat: rules.finisherHeatThreshold,
    );
    expect(result.termination, CombatV1CpuMatchTermination.safetyLimit);
    expect(result.terminalCause, isNull);
  });

  test('10. FINISHER normal + submissionHold flag → flagは無視され自動決着なし', () {
    final result = _runDeclinePath(
      technique: _finisherNormalWithSubmissionHoldFlag,
      sharedHeat: rules.finisherHeatThreshold,
    );
    expect(result.termination, CombatV1CpuMatchTermination.safetyLimit);
    expect(result.terminalCause, isNull);
  });

  test('補足: NORMALでdirectPin/submissionHoldがいずれもfalseなら自動決着なし', () {
    final result = _runDeclinePath(
      technique: fixtureTechniques['fx_normal_strike']!,
    );
    expect(result.termination, CombatV1CpuMatchTermination.safetyLimit);
    expect(result.terminalCause, isNull);
  });
}
