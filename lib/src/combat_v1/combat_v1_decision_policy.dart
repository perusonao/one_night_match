/// CPU Decision Policy（Phase 11B、docs/design/combat_v1_phase11b_cpu.md）。
///
/// [CombatV1LegalActionEnumerator]が列挙した合法手の中から1手を選ぶ責務
/// のみを持つ。「強いCPU」ではなく、deterministic test可能な最小限の
/// baseline policy 2種（[CombatV1FirstLegalPolicy]/[CombatV1RandomLegalPolicy]）
/// を提供する。Heuristic AI・Wrestler固有AI・damage評価・価値評価は一切
/// 実装しない。
library;

import 'dart:math';

import 'combat_v1_engine.dart';
import 'combat_v1_legal_action.dart';
import 'combat_v1_match_state.dart';

/// [CombatV1LegalActionEnumerator]が列挙した合法手から1手を選ぶ
/// interface（Phase 11B）。
///
/// 実装は[state]/[legalActions]以外の外部可変状態を持たない（Policy内部で
/// `Random()`を新規生成しないこと——[CombatV1RandomLegalPolicy]参照）。
abstract interface class CombatV1DecisionPolicy {
  /// ログ・test・[CombatV1CpuMatchResult]で識別するための安定したID
  /// （Phase 11B addendum「Policy Metadata」——将来のPhase
  /// 12/heuristic policyも同じSimulator APIで識別できるよう、値を変更
  /// しない）。
  String get id;

  /// [legalActions]から1手を選ぶ。[legalActions]が空の場合は
  /// [CombatV1IllegalActionException]でfail-fastする（silent no-opにしない）。
  CombatV1LegalAction choose(
    CombatV1MatchState state,
    List<CombatV1LegalAction> legalActions,
  );
}

/// Deterministic baseline policy（Phase 11B）。
///
/// 「自然なCPU」「強いCPU」ではなく、明確なテスト用baselineとして実装する。
/// 優先順位:
///
/// 1. PIN
/// 2. Counter
/// 3. declineCounter
/// 4. standUp
/// 5. Technique
/// 6. REST
/// 7. endTurn
/// 8. discard
///
/// 同じAction type内では`cardInstanceId`昇順でdeterministicに選ぶ
/// （Production definition順biasが発生することを許容する。biasを直すための
/// Heuristicは実装しない）。
final class CombatV1FirstLegalPolicy implements CombatV1DecisionPolicy {
  const CombatV1FirstLegalPolicy();

  @override
  String get id => 'firstLegal';

  static const List<CombatV1LegalActionKind> _priority = [
    CombatV1LegalActionKind.pin,
    CombatV1LegalActionKind.counter,
    CombatV1LegalActionKind.declineCounter,
    CombatV1LegalActionKind.standUp,
    CombatV1LegalActionKind.technique,
    CombatV1LegalActionKind.rest,
    CombatV1LegalActionKind.endTurn,
    CombatV1LegalActionKind.discard,
  ];

  @override
  CombatV1LegalAction choose(
    CombatV1MatchState state,
    List<CombatV1LegalAction> legalActions,
  ) {
    if (legalActions.isEmpty) {
      throw CombatV1IllegalActionException(
        'CombatV1FirstLegalPolicy.choose: legalActionsが空です',
      );
    }

    for (final kind in _priority) {
      final candidates = legalActions
          .where((action) => action.kind == kind)
          .toList()
        ..sort(_compareDeterministic);
      if (candidates.isNotEmpty) return candidates.first;
    }

    // _priorityは全8 variantを網羅しているため、legalActionsが非空である
    // 限りここへは到達しない。
    throw CombatV1IllegalActionException(
      'CombatV1FirstLegalPolicy.choose: 未知のLegalAction種別です',
    );
  }

  static int _compareDeterministic(CombatV1LegalAction a, CombatV1LegalAction b) {
    final idA = a.cardInstanceId;
    final idB = b.cardInstanceId;
    if (idA != null && idB != null) return idA.compareTo(idB);
    return 0;
  }
}

/// Type-first random policy（Phase 11B）。
///
/// 物理LegalAction全件から一様randomは採用しない（手札枚数が多い
/// Action typeほど選ばれやすくなるbiasを避けるため）。代わりに:
///
/// 1. 現在存在するAction Typeを抽出する
/// 2. Action Typeを一様randomで1つ選択する
/// 3. 選択したtype内のActionから一様randomで1つ選択する
///
/// 例: Technique 8枚・PIN 1件・endTurn 1件が列挙された場合、Technique
/// type/PIN/endTurnはそれぞれ1/3の確率で選ばれ、Technique typeが選ばれた
/// 後に8枚から1枚を一様randomで選ぶ（Counter 3件+decline 1件の場合も同様、
/// Counter typeが1/2、decline単体で1/2）。カード枚数そのものがCounter率等を
/// 過剰に上げない設計とする。
///
/// [_decisionRandom]はCPU decision専用のRandomで、Engine resolution用
/// Random（shuffle・draw・PIN・COUNTER解決）とは常に分離する
/// （docs/design/combat_v1_phase11b_cpu.md「RNG分離」章）。Policy内部で
/// `Random()`を新規生成しない——呼び出し側が明示的に注入することで、同seed
/// による選択sequenceの再現性を保証する。
final class CombatV1RandomLegalPolicy implements CombatV1DecisionPolicy {
  CombatV1RandomLegalPolicy(this._decisionRandom);

  final Random _decisionRandom;

  @override
  String get id => 'randomLegal';

  static const List<CombatV1LegalActionKind> _canonicalOrder = [
    CombatV1LegalActionKind.discard,
    CombatV1LegalActionKind.technique,
    CombatV1LegalActionKind.counter,
    CombatV1LegalActionKind.declineCounter,
    CombatV1LegalActionKind.pin,
    CombatV1LegalActionKind.rest,
    CombatV1LegalActionKind.standUp,
    CombatV1LegalActionKind.endTurn,
  ];

  @override
  CombatV1LegalAction choose(
    CombatV1MatchState state,
    List<CombatV1LegalAction> legalActions,
  ) {
    if (legalActions.isEmpty) {
      throw CombatV1IllegalActionException(
        'CombatV1RandomLegalPolicy.choose: legalActionsが空です',
      );
    }

    final byKind = <CombatV1LegalActionKind, List<CombatV1LegalAction>>{};
    for (final action in legalActions) {
      (byKind[action.kind] ??= <CombatV1LegalAction>[]).add(action);
    }

    final presentKinds = [
      for (final kind in _canonicalOrder)
        if (byKind.containsKey(kind)) kind,
    ];

    final chosenKind = presentKinds[_decisionRandom.nextInt(presentKinds.length)];
    final candidates = byKind[chosenKind]!;
    return candidates[_decisionRandom.nextInt(candidates.length)];
  }
}
