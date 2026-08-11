/// Combat Ver.1 Phase 12A — Simulation Policy descriptor
/// （docs/design/combat_v1_phase12a_simulation_core.md、Codex review
/// Major Finding M1対応）。
///
/// 当初のPhase 12Aは、Policyを`String id`＋任意の
/// `CombatV1DecisionPolicy Function(Random) create`クロージャの組
/// （`CombatV1SimulationPolicySpec`）で表現していた。しかしこれは
/// public `CombatV1SimulationConfig`から任意のfactory closureを注入
/// できることを意味し、以下を防げなかった（Codex review指摘）:
///
/// - external mutable stateをclosureへcaptureできる
/// - 同じpolicy instanceを複数matchで使い回せる
/// - closureが供給されたRandomを無視できる
/// - `id`文字列と実際に生成されたpolicyの`id`を不一致にできる
///
/// これらはPhase 12Aの最重要契約「同じ`CombatV1SimulationConfig` +
/// `masterSeed` + `matchIndex`から同じsimulationを再現できる」を
/// public API上保証できないことを意味する。
///
/// [CombatV1SimulationPolicyKind]はこれを、closed enum（Phase 11Bの
/// `CombatV1FirstLegalPolicy`/`CombatV1RandomLegalPolicy`の2種のみ）へ
/// 置き換えることで解消する。enumのため、任意closureの注入は構造上
/// 不可能——第三者custom policy registry等の汎用拡張機構はPhase 12Aでは
/// 追加しない（必要になった場合は将来Phaseで扱う）。
library;

import 'dart:math';

import '../combat_v1_decision_policy.dart';

/// Simulationで利用可能なPolicyを、Phase 11Bの2種類の built-in policyへ
/// 閉じたenum（Codex review Major Finding M1対応）。
///
/// [CombatV1SimulationConfig.playerAPolicy]/[playerBPolicy]の型として
/// 使う。enumであるため:
///
/// - validな値は[values]の2種類のみ——任意のfactory closureをpublic API
///   へ注入することが構造上不可能
/// - 各variantはstateless（field自体を持たない）——external mutable
///   stateをcaptureする余地がない
enum CombatV1SimulationPolicyKind {
  /// [CombatV1FirstLegalPolicy]（deterministic baseline、Randomは消費
  /// しない）。
  firstLegal,

  /// [CombatV1RandomLegalPolicy]（type-first random policy）。
  randomLegal;

  /// [firstLegal]の実際の`CombatV1FirstLegalPolicy.id`値
  /// （class初期化時に1度だけ読み取り、以降は再利用する）。
  static final String _firstLegalId = const CombatV1FirstLegalPolicy().id;

  /// [randomLegal]の実際の`CombatV1RandomLegalPolicy.id`値。
  /// `Random(0)`は値を読み取るためだけの使い捨てで、実際の試合進行へは
  /// 一切使われない（`id`getterは注入されたRandomの値に依存しない
  /// 純粋な定数のため、副作用のあるRandom消費は発生しない）。
  static final String _randomLegalId = CombatV1RandomLegalPolicy(Random(0)).id;

  /// このkindに対応する、Phase 11B `CombatV1DecisionPolicy.id`と同じ
  /// 値（Codex review「descriptor IDと実際のPhase 11B policy IDが構造上
  /// 不一致にならない」対応）。
  ///
  /// Simulation層で`'firstLegal'`/`'randomLegal'`という文字列literalを
  /// 別途保持しない——常に実際にPhase 11B policyクラスをinstantiateして
  /// その`.id`を読み取ることで値を得る。Phase 11B側で`id`文字列が変更
  /// されれば、このgetterも自動的に追従するため、descriptor IDと
  /// runtime policy IDが構造的に乖離することはない。
  String get policyId => switch (this) {
    CombatV1SimulationPolicyKind.firstLegal => _firstLegalId,
    CombatV1SimulationPolicyKind.randomLegal => _randomLegalId,
  };

  /// [policyRandom]から、このkindに対応する[CombatV1DecisionPolicy]の
  /// 新規instanceを生成する。
  ///
  /// 呼び出すたびに必ず新しいinstanceを返す（`CombatV1FirstLegalPolicy`
  /// はRandomを消費しないstateless policyだが、それでも呼び出しごとに
  /// 再構築する——「同じpolicy instanceを複数matchで使い回せる」という
  /// Codex review指摘を、stateの有無に関わらず構造的に防ぐため）。
  /// [CombatV1RandomLegalPolicy]は必ず[policyRandom]をそのまま
  /// constructorへ渡す——このメソッド自身が独自のRandomを生成したり、
  /// 供給された[policyRandom]を無視したりすることはない。
  CombatV1DecisionPolicy createFresh(Random policyRandom) => switch (this) {
    CombatV1SimulationPolicyKind.firstLegal => CombatV1FirstLegalPolicy(),
    CombatV1SimulationPolicyKind.randomLegal =>
      CombatV1RandomLegalPolicy(policyRandom),
  };
}
