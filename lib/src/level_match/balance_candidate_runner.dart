import 'dart:math';

import '../wrestler_editor/models.dart';
import 'deck_balance_models.dart';
import 'deck_balance_report.dart';
import 'deck_balance_simulator.dart';

/// Ver.1.1 実装3: 技1つに対する具体的な調整（威力/HEAT/コスト/pinPower/
/// submissionPower/cannotCounterの付与・削除）。実データを直接変更する前に
/// 「もしこう変えたら」を仮想シミュレーションで検証するための最小単位。
class MoveMutation {
  const MoveMutation({
    required this.moveId,
    required this.description,
    required this.apply,
  });

  final String moveId;
  final String description;
  final MoveDefinition Function(MoveDefinition) apply;

  static MoveMutation power(String moveId, int delta) => MoveMutation(
    moveId: moveId,
    description: '威力${delta >= 0 ? "+" : ""}$delta',
    apply: (m) => m.copyWith(power: max(0, m.power + delta)),
  );

  static MoveMutation heat(String moveId, int delta) => MoveMutation(
    moveId: moveId,
    description: 'HEAT${delta >= 0 ? "+" : ""}$delta',
    apply: (m) => m.copyWith(heat: max(0, m.heat + delta)),
  );

  static MoveMutation pinPower(String moveId, int delta) => MoveMutation(
    moveId: moveId,
    description: 'pinPower${delta >= 0 ? "+" : ""}$delta',
    apply: (m) => m.copyWith(pinPower: max(0, m.pinPower + delta)),
  );

  static MoveMutation submissionPower(String moveId, int delta) => MoveMutation(
    moveId: moveId,
    description: 'submissionPower${delta >= 0 ? "+" : ""}$delta',
    apply: (m) => m.copyWith(submissionPower: max(0, m.submissionPower + delta)),
  );

  /// requiredCards（energyモードのコストの元になる値）を属性ごとに
  /// delta枚（負値で軽減）調整する。0未満にはならない。
  static MoveMutation cost(String moveId, int delta) => MoveMutation(
    moveId: moveId,
    description: 'コスト${delta >= 0 ? "+" : ""}$delta',
    apply: (m) => m.copyWith(
      requiredCards: {
        for (final e in m.requiredCards.entries)
          e.key: e.value > 0 ? max(0, e.value + delta) : e.value,
      },
    ),
  );

  static MoveMutation removeCannotCounter(String moveId) => MoveMutation(
    moveId: moveId,
    description: 'cannotCounterを削除',
    apply: (m) => m.copyWith(
      specialAbilities:
          m.specialAbilities.where((s) => s != 'cannotCounter').toList(),
    ),
  );

  static MoveMutation addCannotCounter(String moveId) => MoveMutation(
    moveId: moveId,
    description: 'cannotCounterを付与',
    apply: (m) => m.copyWith(
      specialAbilities: [
        ...m.specialAbilities.where((s) => s != 'cannotCounter'),
        'cannotCounter',
      ],
    ),
  );

  /// 返し技(counterカテゴリ)が対応できる相手属性(counterTypes)を追加する。
  static MoveMutation addCounterType(String moveId, MoveAttribute attribute) =>
      MoveMutation(
        moveId: moveId,
        description: 'counterTypesに${attribute.name}を追加',
        apply: (m) => m.copyWith(
          counterTypes: [
            ...m.counterTypes.where((a) => a != attribute),
            attribute,
          ],
        ),
      );
}

/// Ver.1.1 実装3: 複数のMoveMutationをまとめた1つの調整案。
class AdjustmentCandidate {
  const AdjustmentCandidate({
    required this.label,
    required this.description,
    required this.mutations,
  });

  final String label;
  final String description;
  final List<MoveMutation> mutations;

  Map<String, MoveDefinition> applyTo(Map<String, MoveDefinition> base) {
    final result = Map<String, MoveDefinition>.from(base);
    for (final mutation in mutations) {
      final current = result[mutation.moveId];
      if (current != null) {
        result[mutation.moveId] = mutation.apply(current);
      }
    }
    return result;
  }
}

/// Ver.1.1 実装4: 調整案ごとに、ロースター全体（全ペア総当たり）で
/// 仮想シミュレーションを実行し、実データを一切変更せずに効果を比較する。
class BalanceCandidateSimulator {
  const BalanceCandidateSimulator({
    required this.baseMoves,
    required this.wrestlers,
  });

  final Map<String, MoveDefinition> baseMoves;
  final List<WrestlerDefinition> wrestlers;

  /// candidateがnullなら現行データ（Before）のまま実行する。
  DeckBalanceReport run(
    AdjustmentCandidate? candidate, {
    int matchesPerPair = 1000,
    int fixedSeedBase = 100000,
  }) {
    final moves = candidate?.applyTo(baseMoves) ?? baseMoves;
    final sim = DeckBalanceSimulator(moves);
    final reports = <DeckBalanceReport>[];
    var pairIndex = 0;
    for (var i = 0; i < wrestlers.length; i++) {
      for (var j = i + 1; j < wrestlers.length; j++) {
        reports.add(sim.run(DeckSimConfig(
          playerA: wrestlers[i],
          playerB: wrestlers[j],
          matches: matchesPerPair,
          seedMode: SeedMode.fixed,
          fixedSeed: fixedSeedBase + pairIndex * 1000000,
        )));
        pairIndex++;
      }
    }
    return DeckBalanceReport.merge(
      reports,
      placeholderConfig: DeckSimConfig(
        playerA: wrestlers.first,
        playerB: wrestlers.length > 1 ? wrestlers[1] : wrestlers.first,
        matches: matchesPerPair * reports.length,
      ),
    );
  }
}
