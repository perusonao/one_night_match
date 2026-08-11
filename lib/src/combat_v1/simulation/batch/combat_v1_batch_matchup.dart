/// Combat Ver.1 Phase 12B-1 — Matchup / Policy Pairing / Matrix generation
/// （docs/design/combat_v1_phase12b1_batch_core_aggregation.md 6・7章）。
///
/// [CombatV1Matchup]は「A vs B」という1組の対戦カードを表すimmutable value
/// object。[CombatV1PolicyPairing]は1 batch全体で使うplayerA/B policyの組。
/// [combatV1GenerateMatchupMatrix]は、渡されたwrestlerId順序からordered
/// Cartesian product（N wrestlerならN×N matchup、mirrorを含む）を生成する
/// pure function。
library;

import '../combat_v1_simulation_policy.dart';

/// 1組の対戦カード（`wrestlerAId` vs `wrestlerBId`）を表すimmutable value
/// object（6章）。
///
/// 単なる文字列key（例: `"akari-vs-reina"`）は使わない——`==`/`hashCode`に
/// よるvalue equalityを持ち、`Map<CombatV1Matchup, ...>`のkeyや
/// `CombatV1MatchupAggregate.matchup`として使える。
class CombatV1Matchup {
  const CombatV1Matchup({required this.wrestlerAId, required this.wrestlerBId});

  final String wrestlerAId;
  final String wrestlerBId;

  /// `wrestlerAId == wrestlerBId`かどうか（mirror match判定）。
  bool get isMirror => wrestlerAId == wrestlerBId;

  @override
  bool operator ==(Object other) =>
      other is CombatV1Matchup &&
      other.wrestlerAId == wrestlerAId &&
      other.wrestlerBId == wrestlerBId;

  @override
  int get hashCode => Object.hash(wrestlerAId, wrestlerBId);

  @override
  String toString() => 'CombatV1Matchup($wrestlerAId vs $wrestlerBId)';
}

/// 1 batch全体で使うplayerA/B policyの組（7章）。immutable value object。
///
/// 対応可能な組み合わせは[CombatV1SimulationPolicyKind]の2値（`firstLegal`/
/// `randomLegal`）の総当たりのみ（Phase 12A由来のclosed enumをそのまま
/// 利用するため、第三者factory/closure/custom policy registryは追加できない）。
class CombatV1PolicyPairing {
  const CombatV1PolicyPairing({
    required this.playerAPolicy,
    required this.playerBPolicy,
  });

  /// default pairing（randomLegal / randomLegal、8章）。
  static const CombatV1PolicyPairing randomVsRandom = CombatV1PolicyPairing(
    playerAPolicy: CombatV1SimulationPolicyKind.randomLegal,
    playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
  );

  final CombatV1SimulationPolicyKind playerAPolicy;
  final CombatV1SimulationPolicyKind playerBPolicy;

  @override
  bool operator ==(Object other) =>
      other is CombatV1PolicyPairing &&
      other.playerAPolicy == playerAPolicy &&
      other.playerBPolicy == playerBPolicy;

  @override
  int get hashCode => Object.hash(playerAPolicy, playerBPolicy);

  @override
  String toString() =>
      'CombatV1PolicyPairing(${playerAPolicy.name} vs ${playerBPolicy.name})';
}

/// [wrestlerIds]の順序を使ったordered Cartesian product
/// （外側ループ=wrestlerA、内側ループ=wrestlerB）を生成する（6章）。
///
/// N wrestlerならN×N matchup。mirror（`wrestlerAId == wrestlerBId`）を
/// 除外しない。A vs BとB vs Aは別matchupとして両方生成する。戻り値は
/// deterministic order・`List.unmodifiable`。pure function
/// （[wrestlerIds]以外の外部stateに依存しない）。
List<CombatV1Matchup> combatV1GenerateMatchupMatrix(List<String> wrestlerIds) =>
    List.unmodifiable([
      for (final wrestlerAId in wrestlerIds)
        for (final wrestlerBId in wrestlerIds)
          CombatV1Matchup(wrestlerAId: wrestlerAId, wrestlerBId: wrestlerBId),
    ]);
