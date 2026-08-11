/// Combat Ver.1 Phase 12A — Simulation seed derivation
/// （docs/design/combat_v1_phase12a_simulation_core.md）。
///
/// 「同じ設定＋同じseedなら再現可能」を保証するための、masterSeedから
/// matchSeed・engineSeed・playerAPolicySeed・playerBPolicySeedを導出する
/// deterministic pure function群。
///
/// 制約（Phase 12A要件）:
///
/// - DartのhashCode（`String.hashCode`/`Object.hashCode`）を使用しない
///   （プラットフォーム間で安定性が保証されないため）。
/// - `Random`を順番に呼び出して子seedを作る方式は使わない（呼び出し回数の
///   変化に脆弱なため）。
/// - すべてpure function（同じ引数なら常に同じ結果、外部stateに依存しない）。
///
/// 32-bit FNV-1aハッシュ + 有限混合（finalizer）による小規模な
/// deterministic mixerで十分とする（Phase 12Aでは暗号学的な強度は不要）。
library;

/// このファイルのseed derivationロジックのバージョン。[deriveV1SimulationSeeds]
/// が返す[CombatV1SimulationSeedSet.derivationVersion]と同じ値。ロジックを
/// 変更する場合は必ずインクリメントし、既存Simulation Resultとの
/// 再現性の非互換を明示できるようにする。
const int combatV1SeedDerivationVersion = 1;

/// [deriveV1SimulationSeeds]が1試合分について生成するseed群。
class CombatV1SimulationSeedSet {
  const CombatV1SimulationSeedSet({
    required this.matchIndex,
    required this.masterSeed,
    required this.matchSeed,
    required this.engineSeed,
    required this.playerAPolicySeed,
    required this.playerBPolicySeed,
    required this.derivationVersion,
  });

  final int matchIndex;
  final int masterSeed;

  /// `masterSeed` + `matchIndex` + config（wrestlerA/B・policyA/B id）から
  /// 導出された、この試合固有のseed。[engineSeed]/[playerAPolicySeed]/
  /// [playerBPolicySeed]はすべてこの値から派生する。
  final int matchSeed;

  /// `CombatV1Engine`のCommand実行（shuffle/draw/PIN/COUNTER解決）専用に
  /// 使うRandomのseed（`CombatV1ProductionMatchStarter.start`の初期shuffle
  /// から`CombatV1CpuMatchRunner.run`のengineRandomまで、1試合を通して
  /// 同一のRandomインスタンスへ使う。7章「RNG Separation」参照）。
  final int engineSeed;

  /// playerA（`CombatV1DecisionPolicy` for player index 0）専用のdecision
  /// Randomのseed。
  final int playerAPolicySeed;

  /// playerB（`CombatV1DecisionPolicy` for player index 1）専用のdecision
  /// Randomのseed。
  final int playerBPolicySeed;

  /// この結果を生成したseed derivationロジックのバージョン
  /// （[combatV1SeedDerivationVersion]と同じ値）。
  final int derivationVersion;
}

/// masterSeedから1試合分の[CombatV1SimulationSeedSet]を導出する（Phase 12A
/// 「Seed Strategy」）。
///
/// 同じ[masterSeed]・[matchIndex]・[wrestlerAId]・[wrestlerBId]・
/// [playerAPolicyId]・[playerBPolicyId]なら、常に同じ[CombatV1SimulationSeedSet]
/// を返す（pure function）。[wrestlerAId]/[wrestlerBId]/[playerAPolicyId]/
/// [playerBPolicyId]のいずれかが変われば[CombatV1SimulationSeedSet.matchSeed]
/// も変わる——同じ`masterSeed`/`matchIndex`のまま対戦カードやpolicyだけを
/// 差し替えて実行した場合に、seed群が意図せず衝突しないようにするため。
CombatV1SimulationSeedSet deriveV1SimulationSeeds({
  required int masterSeed,
  required int matchIndex,
  required String wrestlerAId,
  required String wrestlerBId,
  required String playerAPolicyId,
  required String playerBPolicyId,
}) {
  final matchSeed = _deriveV1(<Object>[
    masterSeed,
    matchIndex,
    wrestlerAId,
    wrestlerBId,
    playerAPolicyId,
    playerBPolicyId,
  ], 'match');

  final engineSeed = _deriveV1(<Object>[matchSeed], 'engine');
  final playerAPolicySeed = _deriveV1(<Object>[matchSeed], 'policyA');
  final playerBPolicySeed = _deriveV1(<Object>[matchSeed], 'policyB');

  return CombatV1SimulationSeedSet(
    matchIndex: matchIndex,
    masterSeed: masterSeed,
    matchSeed: matchSeed,
    engineSeed: engineSeed,
    playerAPolicySeed: playerAPolicySeed,
    playerBPolicySeed: playerBPolicySeed,
    derivationVersion: combatV1SeedDerivationVersion,
  );
}

/// [components]（順序を含めて意味を持つ）と[lane]（同じcomponentsから複数の
/// 独立したseedを分岐させるための識別子、例:`'engine'`/`'policyA'`）から、
/// 32-bit非負整数のseedを1つ決定論的に導出する。
///
/// `components`を`'|'`区切りの文字列へ直列化してFNV-1aでハッシュ化した後、
/// [_mix32]でavalanche（1bitの変化が出力全体へ広がる性質）を高める
/// 2段構成。`Random`の逐次呼び出しには依存しない。
int _deriveV1(List<Object> components, String lane) {
  final key = <String>[
    'combatV1SimSeed.v$combatV1SeedDerivationVersion',
    for (final component in components) component.toString(),
    lane,
  ].join('|');
  return _mix32(_fnv1a32(key));
}

/// 文字列の32-bit FNV-1aハッシュ（`String.hashCode`は使用しない——
/// プラットフォーム・SDKバージョン間で安定性が保証されないため、
/// このファイル内で完結する固定アルゴリズムを直接実装する）。
int _fnv1a32(String input) {
  const int offsetBasis = 0x811C9DC5;
  const int prime = 0x01000193;
  var hash = offsetBasis;
  for (final unit in input.codeUnits) {
    hash = (hash ^ unit) & 0xFFFFFFFF;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash;
}

/// 32-bit整数用の小規模deterministic mixer（MurmurHash3 finalizerと同型の
/// 有限混合）。[_fnv1a32]の出力を追加で撹拌し、近い入力（例: 連続する
/// matchIndex）が近い出力にならないようにする。暗号学的な強度は不要
/// （Phase 12A要件）。
int _mix32(int seed) {
  var x = seed & 0xFFFFFFFF;
  x = ((x ^ (x >>> 16)) * 0x85EBCA6B) & 0xFFFFFFFF;
  x = ((x ^ (x >>> 13)) * 0xC2B2AE35) & 0xFFFFFFFF;
  x = (x ^ (x >>> 16)) & 0xFFFFFFFF;
  return x;
}
