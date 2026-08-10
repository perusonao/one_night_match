/// CombatV1ActionExecutor（Phase 11B、docs/design/combat_v1_phase11b_cpu.md）。
///
/// [CombatV1LegalAction]を既存の`CombatV1Engine` Commandへ変換して呼び出す
/// 薄いlayer。Engineルールの再実装は一切行わない——responsibility は
/// variant dispatch・actor一致検証・Engine command呼び出し・Catalog/
/// rules/random受け渡しのみ。
library;

import 'dart:math';

import 'combat_v1_deck_validation.dart';
import 'combat_v1_engine.dart';
import 'combat_v1_legal_action.dart';
import 'combat_v1_match_state.dart';
import 'combat_v1_rules_config.dart';

/// [CombatV1LegalAction]を`CombatV1Engine`のCommandへ変換して実行する
/// stateless utility（Phase 11B）。
class CombatV1ActionExecutor {
  const CombatV1ActionExecutor._();

  /// [action]を[state]へ適用し、新しい[CombatV1MatchState]を返す。
  ///
  /// [action]は必ず「今まさに[state]を[CombatV1LegalActionEnumerator]で
  /// 列挙した結果」から選ばれたものである前提とする（enumerate → choose →
  /// executeの正常フロー）。[action.actorPlayerIndex]が[state]から導出される
  /// 期待actorと一致しない場合、stale actionまたは呼び出し側のmisuseとして
  /// [CombatV1IllegalActionException]をEngine呼び出し前にfail-fastで送出する
  /// （recoverable failureとして握り潰さない）。
  ///
  /// [random]はEngine resolution専用のRandom（decision policyのRandomとは
  /// 分離する。docs/design/combat_v1_phase11b_cpu.md「RNG分離」章）。
  static CombatV1MatchState execute(
    CombatV1MatchState state,
    CombatV1LegalAction action, {
    required CombatV1CardCatalog catalog,
    required CombatV1RulesConfig rules,
    Random? random,
  }) {
    _verifyActor(state, action);

    return switch (action) {
      CombatV1DiscardAction(:final cardInstanceId) => CombatV1Engine.discardCard(
        state,
        cardInstanceId,
      ),
      CombatV1TechniqueAction(:final cardInstanceId) =>
        CombatV1Engine.declareTechnique(
          state,
          cardInstanceId,
          catalog: catalog,
          rules: rules,
        ),
      CombatV1CounterAction(:final cardInstanceId) => CombatV1Engine.playCounter(
        state,
        cardInstanceId,
        catalog: catalog,
        rules: rules,
        random: random,
      ),
      CombatV1DeclineCounterAction() => CombatV1Engine.declineCounter(
        state,
        rules: rules,
        random: random,
      ),
      CombatV1PinAction() => CombatV1Engine.declarePin(
        state,
        rules: rules,
        random: random,
      ),
      CombatV1RestAction() => CombatV1Engine.rest(
        state,
        rules: rules,
        random: random,
      ),
      CombatV1StandUpAction() => CombatV1Engine.standUp(state),
      CombatV1EndTurnAction() => CombatV1Engine.endTurn(state, random: random),
    };
  }

  /// [action.actorPlayerIndex]が[state]から導出される期待actorと一致するか
  /// 検証する。
  ///
  /// COUNTER/declineCounterのactorは常に防御側（`1 -
  /// state.activePlayerIndex`）——`counterResponsePending`中は
  /// `activePlayerIndex`が攻撃側のまま変化しないため
  /// （docs/combat_rules_v1.md 7.1章）。それ以外のActionのactorは常に
  /// `state.activePlayerIndex`。
  static void _verifyActor(CombatV1MatchState state, CombatV1LegalAction action) {
    final expectedActor = switch (action) {
      CombatV1CounterAction() ||
      CombatV1DeclineCounterAction() => 1 - state.activePlayerIndex,
      CombatV1DiscardAction() ||
      CombatV1TechniqueAction() ||
      CombatV1PinAction() ||
      CombatV1RestAction() ||
      CombatV1StandUpAction() ||
      CombatV1EndTurnAction() => state.activePlayerIndex,
    };

    if (action.actorPlayerIndex != expectedActor) {
      throw CombatV1IllegalActionException(
        'CombatV1ActionExecutor: actor不一致のLegalActionです'
        '（${action.runtimeType}.actorPlayerIndex='
        '${action.actorPlayerIndex}, 期待値=$expectedActor）。'
        'stale actionまたは別stateから生成されたActionの可能性があります。'
        '同じstateからenumerate→choose→executeしてください。',
      );
    }
  }
}
