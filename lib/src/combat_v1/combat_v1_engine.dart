/// Combat Ver.1 Engine本体（docs/design/combat_v1_phase1_design.md 4章）。
///
/// 不変状態を受け取り、新しい不変状態を返す静的関数群。UI/CPU/Simulator/Test
/// はすべて同じAPIを呼ぶ（UI Widgetを一切渡さない、
/// docs/combat_rules_v1.md 1章）。エンジン自身は自律的な選択を一切行わない。
/// 状態遷移は常に外部からの明示的なコマンド呼び出しでのみ進む
/// （docs/design/combat_v1_phase1_design.md 3章）。
///
/// 既存の①`lib/src/game.dart`／②`lib/src/level_match/`／
/// ③`lib/src/technique_deck/`はいずれもimportしない（独立性の方針、
/// docs/combat_rules_v1.md 1章）。
library;

import 'dart:math';

import 'combat_v1_deck.dart';
import 'combat_v1_deck_validation.dart';
import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_match_state.dart';
import 'combat_v1_rules_config.dart';
import 'combat_v1_technique.dart';
import 'combat_v1_wrestler.dart';

/// 不正なCommand呼び出し時に送出する例外
/// （docs/design/combat_v1_phase1_design.md 4章）。
///
/// silent no-opにはしない（フェイルファスト）。ENERGY不足・不正フェーズ・
/// 手札に存在しないカード・使用条件不一致などはすべてこの例外で通知する。
class CombatV1IllegalActionException implements Exception {
  CombatV1IllegalActionException(this.message);

  final String message;

  @override
  String toString() => 'CombatV1IllegalActionException: $message';
}

/// [CombatV1Engine.checkTechniqueLegality] 等、読み取り専用の判定APIの結果。
///
/// `game.dart`の`CardAvailability(usable, reason)`と同型の軽量パターン。
class CombatV1ActionCheck {
  const CombatV1ActionCheck(this.legal, this.reason);

  final bool legal;
  final String reason;
}

/// Combat Ver.1 Engine。
class CombatV1Engine {
  /// 試合を開始する。
  ///
  /// 両者のデッキを[catalog]・[rules]に基づいて検証（[validateDeck]、
  /// docs/combat_rules_v1.md 4章）したうえでシャッフルし、初期手札を配り、
  /// 先攻（playerA）のターン開始処理（ENERGY全回復・1ドロー）まで行った状態
  /// を返す（`phase == discard`）。不正なデッキではMatchを開始できない。
  static CombatV1MatchState start({
    required CombatV1Wrestler wrestlerA,
    required CombatV1DeckDefinition deckA,
    required CombatV1Wrestler wrestlerB,
    required CombatV1DeckDefinition deckB,
    required CombatV1RulesConfig rules,
    required CombatV1CardCatalog catalog,
    Random? random,
  }) {
    _validateDeckOrThrow(wrestlerA.name, deckA, catalog: catalog, rules: rules);
    _validateDeckOrThrow(wrestlerB.name, deckB, catalog: catalog, rules: rules);

    final rng = random ?? Random();

    final playerA = _initPlayer(wrestlerA, deckA, rules, rng);
    final playerB = _initPlayer(wrestlerB, deckB, rules, rng);

    final state = CombatV1MatchState(
      matchId: 'combat-v1-${DateTime.now().microsecondsSinceEpoch}',
      playerA: playerA,
      playerB: playerB,
      activePlayerIndex: 0,
      sharedHeat: 0,
      turnNumber: 1,
      phase: CombatV1MatchPhase.setup,
      log: [
        '試合開始: ${wrestlerA.name} vs ${wrestlerB.name}',
      ],
    );

    return _startTurn(state, rng);
  }

  /// [deck]を[validateDeck]で検証し、不正なら
  /// [CombatV1IllegalActionException]を送出する（docs/combat_rules_v1.md
  /// 4章）。複数のエラーがある場合はすべてメッセージへまとめる。
  static void _validateDeckOrThrow(
    String wrestlerName,
    CombatV1DeckDefinition deck, {
    required CombatV1CardCatalog catalog,
    required CombatV1RulesConfig rules,
  }) {
    final result = validateDeck(deck, catalog: catalog, rules: rules);
    if (!result.isValid) {
      throw CombatV1IllegalActionException(
        '$wrestlerNameのデッキが不正です: '
        '${result.errors.map((e) => e.message).join(' / ')}',
      );
    }
  }

  static CombatV1PlayerState _initPlayer(
    CombatV1Wrestler wrestler,
    CombatV1DeckDefinition deck,
    CombatV1RulesConfig rules,
    Random rng,
  ) {
    final shuffled = List<CombatV1DeckEntry>.from(deck.entries)..shuffle(rng);
    final hand = shuffled.take(rules.startingHandSize).toList();
    final drawPile = shuffled.skip(rules.startingHandSize).toList();
    return CombatV1PlayerState(
      wrestlerId: wrestler.id,
      wrestlerName: wrestler.name,
      maxHp: rules.startingHp,
      hp: rules.startingHp,
      koc: rules.startingKoc,
      pinCardsHeld: rules.startingPinCards,
      energyPool: wrestler.energyPool,
      drawPile: drawPile,
      hand: hand,
    );
  }

  /// 手番プレイヤーのターン開始処理
  /// （ENERGY全回復・`techniquesUsedThisTurn`リセット・1ドロー）を行い、
  /// `phase == discard`の状態を返す
  /// （docs/design/combat_v1_phase1_design.md 3章の内部遷移。`setup`/
  /// `turnEnd`はこの関数の内部でのみ経由し、外部へは返さない）。
  static CombatV1MatchState _startTurn(CombatV1MatchState state, Random rng) {
    final resetPlayer = state.active.copyWith(
      spentEnergy: const {},
      techniquesUsedThisTurn: 0,
    );
    final (drawnPlayer, drawLogs) = _drawOne(resetPlayer, rng);
    return state
        .withActive(drawnPlayer)
        .copyWith(phase: CombatV1MatchPhase.discard, log: [
          ...state.log,
          ...drawLogs,
        ]);
  }

  /// 山札から1枚引く。山札が空なら捨て札をシャッフルして山札を再構築する
  /// （docs/combat_rules_v1.md 16章。FATIGUEペナルティ——HP減少・HEAT増加・
  /// 強制TKO・再構築回数による自動敗北——はいずれも発生させない）。
  /// 山札・捨て札とも空の場合は何も起きない（引けるカードがない）。
  static (CombatV1PlayerState, List<String>) _drawOne(
    CombatV1PlayerState player,
    Random rng,
  ) {
    var drawPile = player.drawPile;
    var discardPile = player.discardPile;
    var reshuffleCount = player.reshuffleCount;
    final logs = <String>[];

    if (drawPile.isEmpty) {
      if (discardPile.isEmpty) {
        return (player, logs);
      }
      drawPile = List<CombatV1DeckEntry>.from(discardPile)..shuffle(rng);
      discardPile = const [];
      reshuffleCount += 1;
      logs.add('${player.wrestlerName}の山札を再構築した');
    }

    final card = drawPile.first;
    final remainingDrawPile = drawPile.skip(1).toList();
    final hand = [...player.hand, card];
    logs.add('${player.wrestlerName}がカードを1枚引いた');

    return (
      player.copyWith(
        drawPile: remainingDrawPile,
        hand: hand,
        discardPile: discardPile,
        reshuffleCount: reshuffleCount,
      ),
      logs,
    );
  }

  /// 手札から指定カードを1枚捨てる（手札循環、docs/combat_rules_v1.md
  /// 16.1章）。`phase == discard`でのみ許可。
  static CombatV1MatchState discardCard(
    CombatV1MatchState state,
    String instanceId,
  ) {
    if (state.phase != CombatV1MatchPhase.discard) {
      throw CombatV1IllegalActionException(
        'discardCardはdiscardフェーズでのみ呼び出せます（現在: ${state.phase.name}）',
      );
    }
    final player = state.active;
    final entry = _findInHand(player, instanceId);
    if (entry == null) {
      throw CombatV1IllegalActionException('指定されたカードは手札にありません: $instanceId');
    }

    final hand = List<CombatV1DeckEntry>.from(player.hand)..remove(entry);
    final discardPile = [...player.discardPile, entry];
    final updated = player.copyWith(hand: hand, discardPile: discardPile);

    return state
        .withActive(updated)
        .copyWith(
          phase: CombatV1MatchPhase.action,
          log: [...state.log, '${player.wrestlerName}が手札を1枚捨てた'],
        );
  }

  /// TECHNIQUEを使用する（docs/combat_rules_v1.md 4・6章）。
  /// `phase == action`でのみ許可。ENERGY支払い→DMG適用（HP0クランプ）→
  /// 共有HEAT加算→相手posture更新→使用カード捨て札化→1ドロー、を行う。
  /// `phase`は`action`のまま（同一ターン内でさらにTECHNIQUEを使用できる）。
  static CombatV1MatchState playTechnique(
    CombatV1MatchState state,
    String instanceId, {
    required Map<String, CombatV1Technique> techniques,
    Random? random,
  }) {
    final check = checkTechniqueLegality(
      state,
      instanceId,
      techniques: techniques,
    );
    if (!check.legal) {
      throw CombatV1IllegalActionException(check.reason);
    }

    final rng = random ?? Random();
    final attacker = state.active;
    final defender = state.opponent;
    final entry = _findInHand(attacker, instanceId)!;
    final technique = techniques[entry.cardId]!;

    final payment = resolveEnergyPayment(
      pool: attacker.energyPool,
      spent: attacker.spentEnergy,
      cost: technique.energyCost,
      allowWildSubstitution: true,
    );
    if (!payment.isSuccess) {
      // checkTechniqueLegalityで支払い可能と確認済みのため通常到達しないが、
      // 防御的にfail-fastしておく。
      throw CombatV1IllegalActionException(payment.failureReason!);
    }

    final handAfterUse = List<CombatV1DeckEntry>.from(attacker.hand)
      ..remove(entry);
    final attackerAfterUse = attacker.copyWith(
      hand: handAfterUse,
      discardPile: [...attacker.discardPile, entry],
      spentEnergy: payment.updatedSpent,
      techniquesUsedThisTurn: attacker.techniquesUsedThisTurn + 1,
    );

    // 注: int.clamp()はnumを返しintに暗黙変換できないため、min/maxで実装する。
    final newDefenderHp = max(0, min(defender.hp - technique.damage, defender.maxHp));
    final newDefenderPosture =
        technique.resultOpponentState ?? defender.posture;
    final defenderAfterHit = defender.copyWith(
      hp: newDefenderHp,
      posture: newDefenderPosture,
    );

    var next = state
        .withActive(attackerAfterUse)
        .withOpponent(defenderAfterHit)
        .copyWith(
          sharedHeat: state.sharedHeat + technique.heatGain,
          log: [
            ...state.log,
            '${attacker.wrestlerName}が${technique.name}を使用'
                '（DMG${technique.damage}、HEAT+${technique.heatGain}）',
          ],
        );

    // TECHNIQUE使用後の1ドロー（docs/combat_rules_v1.md 16.1章）。
    final (drawnAttacker, drawLogs) = _drawOne(next.active, rng);
    next = next.withActive(drawnAttacker).copyWith(
      log: [...next.log, ...drawLogs],
    );

    return next;
  }

  /// ターンを終了する。`phase == action`でのみ許可。手番を交代し、新しい
  /// 手番プレイヤーのターン開始処理（ENERGY全回復・1ドロー）を行った状態
  /// （`phase == discard`）を返す。
  static CombatV1MatchState endTurn(
    CombatV1MatchState state, {
    Random? random,
  }) {
    if (state.phase != CombatV1MatchPhase.action) {
      throw CombatV1IllegalActionException(
        'endTurnはactionフェーズでのみ呼び出せます（現在: ${state.phase.name}）',
      );
    }
    final rng = random ?? Random();
    final flipped = state.copyWith(
      activePlayerIndex: state.activePlayerIndex == 0 ? 1 : 0,
      turnNumber: state.turnNumber + 1,
      log: [...state.log, 'ターン終了'],
    );
    return _startTurn(flipped, rng);
  }

  // ---- 読み取り専用の判定API ----
  // 例外を出さず、legal/reasonの組で結果を返す
  // （docs/design/combat_v1_phase1_design.md 4章）。

  static CombatV1ActionCheck checkTechniqueLegality(
    CombatV1MatchState state,
    String instanceId, {
    required Map<String, CombatV1Technique> techniques,
  }) {
    if (state.phase != CombatV1MatchPhase.action) {
      return CombatV1ActionCheck(
        false,
        'actionフェーズではありません（現在: ${state.phase.name}）',
      );
    }

    final attacker = state.active;
    final entry = _findInHand(attacker, instanceId);
    if (entry == null) {
      return const CombatV1ActionCheck(false, '指定されたカードは手札にありません');
    }
    if (entry.category == CombatV1CardCategory.counter) {
      return const CombatV1ActionCheck(
        false,
        'COUNTERカードはTECHNIQUEとして使用できません',
      );
    }

    final technique = techniques[entry.cardId];
    if (technique == null) {
      return const CombatV1ActionCheck(false, '技カタログに見つかりません');
    }

    final required = technique.requiredOpponentState;
    if (required != null && state.opponent.posture != required) {
      return CombatV1ActionCheck(
        false,
        '相手の状態（${state.opponent.posture.name}）が使用条件'
        '（${required.name}）を満たしません',
      );
    }

    final payment = resolveEnergyPayment(
      pool: attacker.energyPool,
      spent: attacker.spentEnergy,
      cost: technique.energyCost,
      allowWildSubstitution: true,
    );
    if (!payment.isSuccess) {
      return CombatV1ActionCheck(false, payment.failureReason!);
    }

    return const CombatV1ActionCheck(true, '使用できます');
  }

  /// 現在の手番プレイヤーが使用可能なTECHNIQUEを1枚でも持っているか。
  /// エンジン自身はこれを見て自動的にターンを進めたりしない
  /// （呼び出し側の判断材料としてのみ提供する）。
  static bool hasAnyPlayableTechnique(
    CombatV1MatchState state, {
    required Map<String, CombatV1Technique> techniques,
  }) {
    if (state.phase != CombatV1MatchPhase.action) return false;
    for (final entry in state.active.hand) {
      final check = checkTechniqueLegality(
        state,
        entry.instanceId,
        techniques: techniques,
      );
      if (check.legal) return true;
    }
    return false;
  }

  static CombatV1DeckEntry? _findInHand(
    CombatV1PlayerState player,
    String instanceId,
  ) {
    for (final entry in player.hand) {
      if (entry.instanceId == instanceId) return entry;
    }
    return null;
  }
}
