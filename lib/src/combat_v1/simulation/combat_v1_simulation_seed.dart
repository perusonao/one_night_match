/// Combat Ver.1 Phase 12A — Simulation seed / identity derivation
/// （docs/design/combat_v1_phase12a_simulation_core.md）。
///
/// このファイルは目的が異なる2つのpure function群を提供する（Codex
/// review Blocking Finding M3対応で明確に分離した）:
///
/// 1. [deriveV1SimulationSeeds] — 「同じ設定＋同じseedなら再現可能」を
///    保証するためのRNG seed derivation。masterSeedから
///    matchSeed・engineSeed・playerAPolicySeed・playerBPolicySeedを導出
///    する。[maxActions]/[CombatV1RulesConfig]には一切依存しない
///    ——これらはEngine/PolicyのRandom sequenceを決定しないため。
/// 2. [deriveV1SimulationMatchId] — Phase 12Bの集計・監査・replay
///    boundaryとして使う、Simulator独自のcanonical simulation identity。
///    RNG seedとは異なり、`maxActions`・`CombatV1RulesConfig`の
///    outcome-affecting fieldも含む（試合結果へ実際に影響する設定が
///    違えば、別のmatchとして区別する必要があるため）。
///
/// 両者は同じ低レベルhash primitive（[_deriveV1]/[_encodeLengthPrefixed]/
/// [_fnv1a32]/[_mix32]/[_mul32]）を共有するが、互いの出力に依存しない
/// 独立した計算である——[deriveV1SimulationMatchId]の入力を変えても
/// [deriveV1SimulationSeeds]の結果（したがって既存golden vector）は
/// 一切変化しない。
///
/// 制約（Phase 12A要件）:
///
/// - DartのhashCode（`String.hashCode`/`Object.hashCode`）を使用しない
///   （プラットフォーム間で安定性が保証されないため）。
/// - `Random`を順番に呼び出して子seedを作る方式は使わない（呼び出し回数の
///   変化に脆弱なため）。
/// - すべてpure function（同じ引数なら常に同じ結果、外部stateに依存しない）。
/// - `rules.toString()`/`hashCode`/`Object.hash`/Map・Set iteration/
///   reflection/`DateTime`のいずれにも依存しない。
///
/// 32-bit FNV-1aハッシュ + 有限混合（finalizer）による小規模な
/// deterministic mixerで十分とする（Phase 12Aでは暗号学的な強度は不要）。
library;

import '../combat_v1_rules_config.dart';

/// RNG seed derivationロジックのバージョン。[deriveV1SimulationSeeds]が
/// 返す[CombatV1SimulationSeedSet.derivationVersion]と同じ値。ロジックを
/// 変更する場合は必ずインクリメントし、既存Simulation Resultとの
/// 再現性の非互換を明示できるようにする。
///
/// [combatV1SimulationIdentityVersion]（simulation identity derivation）
/// とは独立してバージョン管理する——RNG seedの算出方式とsimulation
/// identityの算出方式は別々に進化しうるため（Codex review M3対応）。
const int combatV1SeedDerivationVersion = 1;

/// Simulation identity derivationロジックのバージョン
/// （[deriveV1SimulationMatchId]が使用）。[CombatV1RulesConfig]のどの
/// fieldをidentityへ含めるか等、identity算出方式を変更する場合は必ず
/// インクリメントする。[combatV1SeedDerivationVersion]（RNG seed）とは
/// 独立。
const int combatV1SimulationIdentityVersion = 1;

/// [deriveV1SimulationSeeds]が1試合分について生成するRNG seed群。
///
/// `simulationMatchId`はこのclassには含まない——[deriveV1SimulationMatchId]
/// が独立したpure functionとして提供する（Codex review M3対応、RNG seed
/// derivationとsimulation identity derivationの分離）。
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

  /// この結果を生成したRNG seed derivationロジックのバージョン
  /// （[combatV1SeedDerivationVersion]と同じ値）。
  final int derivationVersion;
}

/// masterSeedから1試合分の[CombatV1SimulationSeedSet]（RNG seedのみ）を
/// 導出する（Phase 12A「Seed Strategy」）。
///
/// 同じ[masterSeed]・[matchIndex]・[wrestlerAId]・[wrestlerBId]・
/// [playerAPolicyId]・[playerBPolicyId]なら、常に同じ[CombatV1SimulationSeedSet]
/// を返す（pure function）。[wrestlerAId]/[wrestlerBId]/[playerAPolicyId]/
/// [playerBPolicyId]のいずれかが変われば[CombatV1SimulationSeedSet.matchSeed]
/// も変わる——同じ`masterSeed`/`matchIndex`のまま対戦カードやpolicyだけを
/// 差し替えて実行した場合に、seed群が意図せず衝突しないようにするため。
///
/// [maxActions]・[CombatV1RulesConfig]は受け取らない——これらはEngine/
/// PolicyのRandom sequenceを一切決定しないため（Codex review M3対応。
/// これらを識別子へ反映する必要がある場合は[deriveV1SimulationMatchId]
/// を使う）。
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
  ], 'match', versionTag: _seedVersionTag);

  final engineSeed = _deriveV1(<Object>[
    matchSeed,
  ], 'engine', versionTag: _seedVersionTag);
  final playerAPolicySeed = _deriveV1(<Object>[
    matchSeed,
  ], 'policyA', versionTag: _seedVersionTag);
  final playerBPolicySeed = _deriveV1(<Object>[
    matchSeed,
  ], 'policyB', versionTag: _seedVersionTag);

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

/// Simulator独自のdeterministic simulation identity
/// （[CombatV1MatchSimulationResult.simulationMatchId]）を算出する
/// （Codex review Blocking Finding M3対応）。
///
/// [deriveV1SimulationSeeds]（RNG seed derivation）とは独立したpure
/// function。masterSeed/matchIndex/wrestlerA・B/policyA・Bに加え、実際に
/// 試合結果へ影響する[maxActions]・[rules]（の全outcome-affecting
/// field、[_rulesIdentityComponents]参照）も識別子へ反映する——旧実装
/// （`matchSeed`から`'matchId'` laneで派生させる方式）は`maxActions`/
/// `rules`の違いを反映できず、異なる試合条件を誤って同一matchとして
/// 扱ってしまう問題があった。
///
/// 保証する性質:
///
/// - **deterministic**: 同一の全引数なら常に同じ結果
/// - **match separation**: `matchIndex`が異なれば別の結果になる
///   （`matchIndex`自体を文字列内に直接埋め込むことでも二重に保証する）
/// - **maxActions/rules差の反映**: 他の引数が同一でも、`maxActions`や
///   `rules`のoutcome-affecting fieldが異なれば別の結果になる
/// - **Engine matchId非依存**: `CombatV1Engine.start`が生成する時刻
///   依存の`matchId`は一切参照しない
/// - **Random非消費**: pure functionのみで構成され、`Random`を一切
///   消費しない
/// - **RNG seedへ無影響**: [deriveV1SimulationSeeds]の結果
///   （したがって既存golden vector）には一切影響しない
String deriveV1SimulationMatchId({
  required int masterSeed,
  required int matchIndex,
  required String wrestlerAId,
  required String wrestlerBId,
  required String playerAPolicyId,
  required String playerBPolicyId,
  required int maxActions,
  required CombatV1RulesConfig rules,
}) {
  final identityValue = _deriveV1(<Object>[
    masterSeed,
    matchIndex,
    wrestlerAId,
    wrestlerBId,
    playerAPolicyId,
    playerBPolicyId,
    maxActions,
    ..._rulesIdentityComponents(rules),
  ], 'simulationMatchId', versionTag: _identityVersionTag);

  return 'sim-v$combatV1SimulationIdentityVersion-$masterSeed-$matchIndex-'
      '${identityValue.toRadixString(16).padLeft(8, '0')}';
}

String get _seedVersionTag => 'combatV1SimSeed.v$combatV1SeedDerivationVersion';

String get _identityVersionTag =>
    'combatV1SimIdentity.v$combatV1SimulationIdentityVersion';

/// [rules]（[CombatV1RulesConfig]）の全outcome-affecting fieldを、固定順の
/// tag/value pairとして列挙する（Codex review M3「Rules Canonical
/// Representation」対応）。
///
/// `rules.toString()`・`hashCode`・`Object.hash`・Map/Set iteration・
/// reflection・`DateTime`のいずれにも依存しない、明示的・小規模な
/// canonical representation。各field値の直前にfield名（tag）を挿入する
/// ことで、値の並びだけでは区別できない曖昧さを避ける
/// （[_encodeLengthPrefixed]による長さ接頭辞化と組み合わせ、bijectiveな
/// 直列化になる）。
///
/// **重要（Future Rule Addition Risk対応）**: [CombatV1RulesConfig]に
/// 新しいfieldが追加された場合、必ずこの一覧へも追加すること——追加を
/// 忘れると、そのfieldの違いが`simulationMatchId`へ反映されなくなる。
/// `combat_v1_simulation_seed_test.dart`の「M3: rules field毎の識別」
/// testが、現時点で列挙済みの各fieldについて「その1 fieldだけを変えると
/// `simulationMatchId`が変わる」ことを網羅的に固定しているため、新field
/// を追加する際は対応するtest caseも追加すること
/// （reflection・generic serializer・code generationのような大規模な
/// 汎用機構は、Phase 12Aのscopeでは意図的に採用していない）。
List<Object> _rulesIdentityComponents(CombatV1RulesConfig rules) => <Object>[
  'rulesCanonicalization.v1',
  'startingHp',
  rules.startingHp,
  'startingKoc',
  rules.startingKoc,
  'startingPinCards',
  rules.startingPinCards,
  'startingHandSize',
  rules.startingHandSize,
  'deckComposition.normalCount',
  rules.deckComposition.normalCount,
  'deckComposition.signatureCount',
  rules.deckComposition.signatureCount,
  'deckComposition.finisherCount',
  rules.deckComposition.finisherCount,
  'deckComposition.counterCount',
  rules.deckComposition.counterCount,
  'normalSameNameLimit',
  rules.normalSameNameLimit,
  'signatureSameNameLimit',
  rules.signatureSameNameLimit,
  'finisherSameNameLimit',
  rules.finisherSameNameLimit,
  'counterSameNameLimit',
  rules.counterSameNameLimit,
  'counterAllowsWildSubstitution',
  rules.counterAllowsWildSubstitution,
  'totalPinCards',
  rules.totalPinCards,
  'pinCountOneKocCost',
  rules.pinCountOneKocCost,
  'pinCountTwoKocCost',
  rules.pinCountTwoKocCost,
  'pinCountTwoPointNineKocCost',
  rules.pinCountTwoPointNineKocCost,
  'submissionHpThreshold',
  rules.submissionHpThreshold,
  'submissionEscapeKocCost',
  rules.submissionEscapeKocCost,
  'restHpRecovery',
  rules.restHpRecovery,
  'roughRestrictedTechniqueLimit',
  rules.roughRestrictedTechniqueLimit,
  'finisherHeatThreshold',
  rules.finisherHeatThreshold,
];

/// [components]（順序を含めて意味を持つ）と[lane]（同じcomponentsから複数の
/// 独立した値を分岐させるための識別子、例:`'engine'`/`'policyA'`）・
/// [versionTag]（呼び出し元のderivation namespace、RNG seedと
/// simulation identityで別の値を使う——Codex review M3対応）から、
/// 32-bit非負整数を1つ決定論的に導出する。
///
/// [components]を[_encodeLengthPrefixed]でbijectiveに直列化してFNV-1aで
/// ハッシュ化した後、[_mix32]でavalanche（1bitの変化が出力全体へ広がる
/// 性質）を高める2段構成。`Random`の逐次呼び出しには依存しない。
int _deriveV1(
  List<Object> components,
  String lane, {
  required String versionTag,
}) {
  final parts = <String>[
    versionTag,
    for (final component in components) component.toString(),
    lane,
  ];
  return _mix32(_fnv1a32(_encodeLengthPrefixed(parts)));
}

/// [parts]を長さ接頭辞（length-prefix）方式でbijectiveに直列化する
/// （Codex review指摘「Seed serialization」対応）。
///
/// 単純な区切り文字joinでは、要素の内容次第で異なる[parts]列が同じ直列化
/// 結果になり得る（例: `['a', 'b|c']`と`['a|b', 'c']`はどちらも単純joinで
/// `'a|b|c'`になってしまう）。各要素の直前にUTF-16 code unit数
/// （`String.length`、プラットフォーム非依存）と`':'`を書き込むことで、
/// 直列化結果から常に一意に元の[parts]列を復元できる——異なる[parts]列が
/// 同じ直列化結果になることは構造上あり得ない。
String _encodeLengthPrefixed(List<String> parts) {
  final buffer = StringBuffer();
  for (final part in parts) {
    buffer
      ..write(part.length)
      ..write(':')
      ..write(part);
  }
  return buffer.toString();
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
    hash = _mul32(hash, prime);
  }
  return hash;
}

/// 32-bit整数用の小規模deterministic mixer（MurmurHash3 finalizerと同型の
/// 有限混合）。[_fnv1a32]の出力を追加で撹拌し、近い入力（例: 連続する
/// matchIndex）が近い出力にならないようにする。暗号学的な強度は不要
/// （Phase 12A要件）。
int _mix32(int seed) {
  var x = seed & 0xFFFFFFFF;
  x = _mul32(x ^ (x >>> 16), 0x85EBCA6B);
  x = _mul32(x ^ (x >>> 13), 0xC2B2AE35);
  x = (x ^ (x >>> 16)) & 0xFFFFFFFF;
  return x;
}

/// [a]・[b]（いずれも32-bit unsigned値として扱う）の積を、下位32-bitへ
/// 切り詰めて返す（`(a * b) & 0xFFFFFFFF`と数学的に同値）。
///
/// `a * b`をそのまま計算すると、32-bit×32-bit＝最大64-bit相当の中間結果に
/// なり得る。Dart VM上の`int`は64-bit整数として正確に計算できるが、
/// dart2js/dartdevcでコンパイルされたWeb上では`int`がJavaScriptの
/// number（53-bit精度のdouble）で表現されるため、64-bit相当の中間結果は
/// 精度を失い、VMと異なる結果になり得る（実測で確認済み）。
///
/// 16-bit×16-bitへ分割してから合成する標準的な安全乗算により、すべての
/// 中間値を53-bit精度でも誤差なく表現できる範囲（最大でも約2^33）に
/// 収め、VM/Web双方で常に同一の結果になるようにする。
int _mul32(int a, int b) {
  final aLo = a & 0xFFFF;
  final aHi = (a >>> 16) & 0xFFFF;
  final bLo = b & 0xFFFF;
  final bHi = (b >>> 16) & 0xFFFF;
  final low = aLo * bLo;
  final mid = (aHi * bLo + aLo * bHi) & 0xFFFF;
  return (low + (mid << 16)) & 0xFFFFFFFF;
}
