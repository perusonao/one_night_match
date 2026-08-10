/// Legal Action Enumerator（Phase 11B、
/// docs/design/combat_v1_phase11b_cpu.md）。
///
/// 現在の[CombatV1MatchState]から、そのstateで合法な[CombatV1LegalAction]を
/// 全て列挙する。「CPUが合法性を判断する」のではなく、可能な限り既存の
/// `CombatV1Engine`のlegality API（`checkTechniqueLegality`等）へ委譲する
/// ——FINISHER HEAT gate・ENERGY支払い・posture条件・ROUGH制限・Counter
/// family/group matching・PIN条件・SUBMISSION・DIRECT PINといったルールを
/// このファイルへ再実装しない。
///
/// `discardCard`/`declineCounter`/`endTurn`にはPhase 11B時点でpublic
/// legality APIが存在しない（既知の制約。docs/design/combat_v1_phase11b_cpu.md
/// 「Engine legality API不足」章）。これらについては、この
/// Enumeratorが対応するCommand自身が要求する最小限のprecondition
/// （`phase`・`posture`等、Command本体のガード節と同じ条件）のみをここで
/// 扱うことを本Phaseでは許容する。それ以上のCore Engine変更は行わない。
library;

import 'combat_v1_deck_validation.dart';
import 'combat_v1_engine.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_legal_action.dart';
import 'combat_v1_match_state.dart';
import 'combat_v1_rules_config.dart';

/// [CombatV1MatchState]から合法な[CombatV1LegalAction]を列挙する
/// stateless utility（Phase 11B）。
class CombatV1LegalActionEnumerator {
  const CombatV1LegalActionEnumerator._();

  /// [state]で合法な全[CombatV1LegalAction]を返す。
  ///
  /// - [state.isOver]なら空List。
  /// - `discard`/`action`(STAND/DOWN)/`counterResponsePending`の4パターンを
  ///   個別に扱う（[8]章参照）。
  /// - `setup`/`turnEnd`は`CombatV1Engine`が外部へ返すことのない内部限定
  ///   フェーズのため、このEnumeratorへ渡された場合は
  ///   programming/invariant errorとして[CombatV1IllegalActionException]を
  ///   送出する。
  ///
  /// 正常な非terminal stateで空Listが返ることは想定しない
  /// （discardフェーズでhandが0枚等の異常stateを除く）。空Listをsilentに
  /// CPU終了の合図として扱わず、呼び出し側（[CombatV1CpuMatchRunner]等）が
  /// 明示的な失敗として診断することを前提とする。
  static List<CombatV1LegalAction> enumerate(
    CombatV1MatchState state, {
    required CombatV1CardCatalog catalog,
    required CombatV1RulesConfig rules,
  }) {
    if (state.isOver) return const [];

    switch (state.phase) {
      case CombatV1MatchPhase.discard:
        return _enumerateDiscard(state);
      case CombatV1MatchPhase.action:
        return state.active.posture == CombatV1WrestlerPosture.down
            ? _enumerateActionDown(state)
            : _enumerateActionStand(state, catalog: catalog, rules: rules);
      case CombatV1MatchPhase.counterResponsePending:
        return _enumerateCounterResponse(state, catalog: catalog, rules: rules);
      case CombatV1MatchPhase.setup:
      case CombatV1MatchPhase.turnEnd:
        throw CombatV1IllegalActionException(
          'CombatV1LegalActionEnumeratorはsetup/turnEndフェーズのstateを'
          '列挙できません（現在: ${state.phase.name}）。CombatV1Engineが'
          '外部へ返すstateは常にdiscard/action/counterResponsePendingの'
          'いずれかのはずで、このフェーズへ到達するのはprogramming/'
          'invariant errorです。',
        );
    }
  }

  /// discardフェーズ: active playerのhand全物理instanceを列挙する。
  ///
  /// 正規stateでは少なくとも1枚存在する想定（`CombatV1Engine._startTurn`が
  /// ターン開始時に1ドローするため）。hand 0枚でdiscardフェーズの場合は
  /// 異常stateであり、このEnumeratorは空Listを返すのみで、それを正常な
  /// 「CPU側の意図的なno-op」とは扱わない（呼び出し側の責務）。
  static List<CombatV1LegalAction> _enumerateDiscard(CombatV1MatchState state) {
    final actor = state.activePlayerIndex;
    return [
      for (final entry in state.active.hand)
        CombatV1DiscardAction(
          actorPlayerIndex: actor,
          cardInstanceId: entry.instanceId,
        ),
    ];
  }

  /// action / STAND: legal Technique全件 + legal normal PIN + endTurn。
  /// REST / standUpはSTANDでは列挙しない。
  static List<CombatV1LegalAction> _enumerateActionStand(
    CombatV1MatchState state, {
    required CombatV1CardCatalog catalog,
    required CombatV1RulesConfig rules,
  }) {
    final actor = state.activePlayerIndex;
    final actions = <CombatV1LegalAction>[];

    for (final entry in state.active.hand) {
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        entry.instanceId,
        catalog: catalog,
        rules: rules,
      );
      if (check.legal) {
        actions.add(
          CombatV1TechniqueAction(
            actorPlayerIndex: actor,
            cardInstanceId: entry.instanceId,
          ),
        );
      }
    }

    if (CombatV1Engine.checkPinLegality(state, rules: rules).legal) {
      actions.add(CombatV1PinAction(actorPlayerIndex: actor));
    }

    actions.add(CombatV1EndTurnAction(actorPlayerIndex: actor));
    return actions;
  }

  /// action / DOWN: standUp / RESTのうち合法なものを列挙する（両方legal
  /// なら両方）。Technique / PIN / endTurnはDOWNでは列挙しない。
  static List<CombatV1LegalAction> _enumerateActionDown(CombatV1MatchState state) {
    final actor = state.activePlayerIndex;
    final actions = <CombatV1LegalAction>[];

    if (CombatV1Engine.checkStandUpLegality(state).legal) {
      actions.add(CombatV1StandUpAction(actorPlayerIndex: actor));
    }
    if (CombatV1Engine.checkRestLegality(state).legal) {
      actions.add(CombatV1RestAction(actorPlayerIndex: actor));
    }

    return actions;
  }

  /// counterResponsePending: 防御側handから全legal Counter + declineCounter
  /// を必ず1件列挙する（Counterが0件でもdeclineは常に残る）。
  ///
  /// `activePlayerIndex`は攻撃側のまま変化しないため（
  /// docs/combat_rules_v1.md 7.1章）、actorPlayerIndexは
  /// `state.activePlayerIndex`をそのまま使わず、
  /// `pendingAttack.defenderPlayerIndex`から導出する。
  static List<CombatV1LegalAction> _enumerateCounterResponse(
    CombatV1MatchState state, {
    required CombatV1CardCatalog catalog,
    required CombatV1RulesConfig rules,
  }) {
    final pending = state.pendingAttack;
    if (pending == null) {
      throw CombatV1IllegalActionException(
        'phase==counterResponsePendingですがpendingAttackがnullです'
        '（invariant違反、CombatV1LegalActionEnumerator）。',
      );
    }

    final defenderIndex = pending.defenderPlayerIndex;
    final defender = state.opponent;
    final actions = <CombatV1LegalAction>[];

    for (final entry in defender.hand) {
      final check = CombatV1Engine.checkCounterLegality(
        state,
        entry.instanceId,
        catalog: catalog,
        rules: rules,
      );
      if (check.legal) {
        actions.add(
          CombatV1CounterAction(
            actorPlayerIndex: defenderIndex,
            cardInstanceId: entry.instanceId,
          ),
        );
      }
    }

    actions.add(CombatV1DeclineCounterAction(actorPlayerIndex: defenderIndex));
    return actions;
  }
}
