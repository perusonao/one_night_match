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

import 'combat_v1_catalog_validation.dart';
import 'combat_v1_counter_rules.dart';
import 'combat_v1_deck.dart';
import 'combat_v1_deck_validation.dart';
import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_match_state.dart';
import 'combat_v1_pending_attack.dart';
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

/// [CombatV1Engine.checkTechniqueLegality]が返す機械判定用の理由コード
/// （Phase 3、docs/combat_rules_v1.md 4・6章）。
///
/// UI／CPU／Simulatorが`reason`（人間可読文字列）を文字列解析しなくて済む
/// ようにするための構造化情報。`legal`な場合は常に[legal]を返す。
enum CombatV1TechniqueLegalityReasonCode {
  /// 使用可能（`CombatV1ActionCheck.legal == true`の場合の既定値）。
  legal,

  /// `phase == action`ではない。
  wrongPhase,

  /// 指定instanceIdがactive playerのhandに存在しない。
  cardNotInHand,

  /// cardIdがCatalogに存在しない。
  missingCatalogEntry,

  /// `DeckEntry.category`とTechnique定義の`category`が一致しない
  /// （docs/combat_rules_v1.md 4章のDeck validationと同じ不変条件を、
  /// Engine実行時にも防御的に確認する）。
  categoryMismatch,

  /// COUNTERカードはTECHNIQUEとして使用できない（docs/combat_rules_v1.md
  /// 7章。COUNTER本処理はPhase 4）。
  counterCannotAttack,

  /// FINISHERは通常TECHNIQUEとして使用できない（FINISHER本処理はPhase 9、
  /// docs/combat_rules_v1.md 13章）。
  finisherNotImplemented,

  /// 相手の状態（`requiredOpponentState`）が使用条件を満たさない。
  opponentStateMismatch,

  /// Technique定義の静的データが不正（[CombatV1Technique.isStaticDataValid]
  /// がfalse）。
  invalidTechniqueData,

  /// ENERGYが不足している（ワイルド補完込みで支払い不可）。
  insufficientEnergy,
}

/// [CombatV1Engine.checkTechniqueLegality] 等、読み取り専用の判定APIの結果。
///
/// Phase 4のCodexレビュー指摘（10-2）対応: 以前は`legal`と[reasonCode]を
/// 別々の位置引数として渡す設計だったため、理論上`legal=false`かつ
/// `reasonCode=legal`のような矛盾した組み合わせを型システムが防げなかった。
/// 名前付きファクトリコンストラクタ（[CombatV1ActionCheck.success]/
/// [CombatV1ActionCheck.failure]）のみを公開し、矛盾した組み合わせを
/// 構築できない設計へ改めた（`failure`側は`assert`で
/// `reasonCode != legal`を強制する）。
class CombatV1ActionCheck {
  const CombatV1ActionCheck.success(this.reason)
    : legal = true,
      reasonCode = CombatV1TechniqueLegalityReasonCode.legal;

  const CombatV1ActionCheck.failure(this.reason, this.reasonCode)
    : legal = false,
      assert(
        reasonCode != CombatV1TechniqueLegalityReasonCode.legal,
        'CombatV1ActionCheck.failureにはlegal以外のreasonCodeを指定してください',
      );

  final bool legal;

  /// 人間可読な説明（ログ・簡易UI用）。
  final String reason;

  /// 機械判定用の理由コード（Phase 3で追加、UI/CPU/Simulator用）。
  final CombatV1TechniqueLegalityReasonCode reasonCode;
}

/// [CombatV1Engine.checkCounterLegality]が返す機械判定用の理由コード
/// （Phase 4、docs/combat_rules_v1.md 7章「COUNTER」）。
enum CombatV1CounterLegalityReasonCode {
  /// 使用可能。
  legal,

  /// `phase == counterResponsePending`ではない。
  wrongPhase,

  /// 応答待ちの攻撃（[CombatV1MatchState.pendingAttack]）が存在しない
  /// （`wrongPhase`と独立に、防御的に検証する）。
  noPendingAttack,

  /// 指定instanceIdが防御側（[CombatV1MatchState.opponent]、
  /// `counterResponsePending`の間は常に`pendingAttack.defenderPlayerIndex`
  /// と一致する）の手札に存在しない。攻撃側が自分の手札のカードで
  /// COUNTERしようとした場合もこのreasonCodeになる（「攻撃側は自分の攻撃を
  /// COUNTERできない」——防御側の手札にしか無いカードを要求することで、
  /// 呼び出し側に別途「actor」引数を追加せずとも自然に拒否される）。
  cardNotInHand,

  /// cardIdがCatalogに存在しない。
  missingCatalogEntry,

  /// カード定義がCOUNTERではない（NORMAL/SIGNATURE/FINISHERカードをCOUNTER
  /// として使おうとした）。
  notCounterCard,

  /// `DeckEntry.category`とCounter定義の`category`が一致しない。
  categoryMismatch,

  /// Counter定義のattributeがwild（Catalog validationで本来拒否される
  /// はずのデータに対する防御的チェック）。
  wildAttribute,

  /// 攻撃の技系統・技系統グループのいずれともCOUNTERの対象が一致しない
  /// （docs/combat_rules_v1.md「23.5章 COUNTER matching」）。
  familyGroupMismatch,

  /// 動的ENERGY COST（返される攻撃のCost総量）を支払えない。
  insufficientEnergy,
}

/// [CombatV1Engine.checkCounterLegality]の結果。[CombatV1ActionCheck]と同じ
/// 設計（`success`/`failure`ファクトリのみを公開し、矛盾した`legal`/
/// `reasonCode`の組み合わせを構築できないようにする）。
class CombatV1CounterActionCheck {
  const CombatV1CounterActionCheck.success(this.reason)
    : legal = true,
      reasonCode = CombatV1CounterLegalityReasonCode.legal;

  const CombatV1CounterActionCheck.failure(this.reason, this.reasonCode)
    : legal = false,
      assert(
        reasonCode != CombatV1CounterLegalityReasonCode.legal,
        'CombatV1CounterActionCheck.failureにはlegal以外のreasonCodeを'
        '指定してください',
      );

  final bool legal;
  final String reason;
  final CombatV1CounterLegalityReasonCode reasonCode;
}

/// Combat Ver.1 Engine。
class CombatV1Engine {
  /// 試合を開始する。
  ///
  /// [catalog]のDefinitionそのものの整合性（[validateCatalog]）と、両者の
  /// デッキ（[validateDeck]、docs/combat_rules_v1.md 4章）をそれぞれ
  /// 検証したうえでシャッフルし、初期手札を配り、先攻（playerA）のターン
  /// 開始処理（ENERGY全回復・1ドロー）まで行った状態を返す
  /// （`phase == discard`）。不正なカタログ・デッキではMatchを開始できない。
  static CombatV1MatchState start({
    required CombatV1Wrestler wrestlerA,
    required CombatV1DeckDefinition deckA,
    required CombatV1Wrestler wrestlerB,
    required CombatV1DeckDefinition deckB,
    required CombatV1RulesConfig rules,
    required CombatV1CardCatalog catalog,
    Random? random,
  }) {
    _validateCatalogOrThrow(catalog);
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

  /// [catalog]を[validateCatalog]で検証し、不正なら
  /// [CombatV1IllegalActionException]を送出する（docs/combat_rules_v1.md
  /// 「23.6章 Catalog validation」、Phase 4）。
  static void _validateCatalogOrThrow(CombatV1CardCatalog catalog) {
    final result = validateCatalog(catalog);
    if (!result.isValid) {
      throw CombatV1IllegalActionException(
        'カタログが不正です: ${result.errors.map((e) => e.message).join(' / ')}',
      );
    }
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
  ///
  /// 防御側のCOUNTER ENERGY（`spentEnergy`）は自ターン外で消費されていても
  /// この処理まで自動回復しない（docs/combat_rules_v1.md 7.1章）——この
  /// 関数は常に`state.active`（手番プレイヤー）だけをリセットするため、
  /// 相手のspentEnergyには触れない。
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

  /// TECHNIQUEを宣言する（docs/combat_rules_v1.md 4・6・7章、Phase
  /// 4で`playTechnique`から改称）。`phase == action`でのみ許可。
  ///
  /// Phase 3までは即座に成功解決していたが、Phase 4からはCOUNTER応答待ち
  /// （`counterResponsePending`）へ入るだけで、この時点ではDMG・HEAT・
  /// 相手状態変化・discard・drawのいずれも発生しない
  /// （docs/combat_rules_v1.md 7.1章）。実際の効果は
  /// [playCounter]（COUNTER成立時、攻撃を完全無効化）または
  /// [declineCounter]（COUNTERしない場合、攻撃を成立させる）で確定する。
  ///
  /// 宣言時点でコミットする内容:
  /// 1. 攻撃側のENERGY消費
  /// 2. 攻撃カードをhandから除去
  /// 3. 攻撃カードを[CombatV1PendingAttack]の所有へ移動
  ///    （hand/drawPile/discardPileのいずれにも存在しなくなる）
  /// 4. `techniquesUsedThisTurn`を+1（COUNTERはTECHNIQUEではないため、
  ///    ここでカウントする方式で確定する。docs/combat_rules_v1.md 15章
  ///    「COUNTERはtechniquesUsedThisTurnに含めない」）
  /// 5. pendingを作成
  /// 6. `phase = counterResponsePending`
  static CombatV1MatchState declareTechnique(
    CombatV1MatchState state,
    String instanceId, {
    required CombatV1CardCatalog catalog,
  }) {
    final prepared = _prepareTechniqueUse(state, instanceId, catalog: catalog);
    return _commitTechniqueDeclaration(state, prepared);
  }

  /// TECHNIQUE宣言の準備: legalityを検証し、ENERGY支払いを確定する。
  ///
  /// 不正なら[CombatV1IllegalActionException]を送出する（fail-fast）。
  /// このメソッドが例外を投げずに戻った時点では、[state]はまだ一切
  /// 変更されていない（読み取りと純粋な計算のみを行うため、失敗時の
  /// atomicityはこの関数自体が状態を変更しないことで保証される）。
  static _PreparedTechniqueUse _prepareTechniqueUse(
    CombatV1MatchState state,
    String instanceId, {
    required CombatV1CardCatalog catalog,
  }) {
    final check = checkTechniqueLegality(state, instanceId, catalog: catalog);
    if (!check.legal) {
      throw CombatV1IllegalActionException(check.reason);
    }

    final attacker = state.active;
    final entry = _findInHand(attacker, instanceId)!;
    final technique = catalog.techniques[entry.cardId]!;

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

    return _PreparedTechniqueUse(
      entry: entry,
      technique: technique,
      updatedSpentEnergy: payment.updatedSpent!,
    );
  }

  /// TECHNIQUE宣言のコミット（docs/combat_rules_v1.md 7.1章）。
  /// [_prepareTechniqueUse]でlegality・ENERGY支払いは確定済みのため失敗しない。
  static CombatV1MatchState _commitTechniqueDeclaration(
    CombatV1MatchState state,
    _PreparedTechniqueUse prepared,
  ) {
    final technique = prepared.technique;
    final attackerIndex = state.activePlayerIndex;
    final defenderIndex = attackerIndex == 0 ? 1 : 0;
    final attackerName = state.active.wrestlerName;

    final handAfterDeclare = List<CombatV1DeckEntry>.from(state.active.hand)
      ..remove(prepared.entry);

    var next = state.withActive(
      state.active.copyWith(
        spentEnergy: prepared.updatedSpentEnergy,
        hand: handAfterDeclare,
        techniquesUsedThisTurn: state.active.techniquesUsedThisTurn + 1,
      ),
    );

    final pending = CombatV1PendingAttack(
      attackerPlayerIndex: attackerIndex,
      defenderPlayerIndex: defenderIndex,
      attackCardInstance: prepared.entry,
      category: technique.category,
      attribute: technique.attribute,
      family: technique.family,
      energyCost: technique.energyCost,
      damage: technique.damage,
      heatGain: technique.heatGain,
      requiredOpponentState: technique.requiredOpponentState,
      resultOpponentState: technique.resultOpponentState,
    );

    return next.copyWith(
      phase: CombatV1MatchPhase.counterResponsePending,
      pendingAttack: pending,
      log: [
        ...next.log,
        '$attackerNameが${technique.name}を宣言した',
      ],
    );
  }

  /// COUNTERを使用する（docs/combat_rules_v1.md 7.1章、Phase
  /// 4）。`phase == counterResponsePending`でのみ許可。
  ///
  /// COUNTER成立時は攻撃の効果を完全に無効化する（DMG・HEAT・相手状態変化
  /// いずれも発生しない）。攻撃側・防御側の双方が1枚ずつドローし
  /// （docs/combat_rules_v1.md 7.1章）、`activePlayerIndex`は宣言した
  /// 攻撃側のまま変化しない（docs/combat_rules_v1.md 7.1章）。
  static CombatV1MatchState playCounter(
    CombatV1MatchState state,
    String instanceId, {
    required CombatV1CardCatalog catalog,
    required CombatV1RulesConfig rules,
    Random? random,
  }) {
    final check = checkCounterLegality(
      state,
      instanceId,
      catalog: catalog,
      rules: rules,
    );
    if (!check.legal) {
      throw CombatV1IllegalActionException(check.reason);
    }

    final pending = state.pendingAttack!;
    final defenderBefore = state.opponent;
    final counterEntry = _findInHand(defenderBefore, instanceId)!;
    final counter = catalog.counters[counterEntry.cardId]!;
    final syntheticCost = counterSyntheticCost(counter, pending.energyCost);
    final payment = resolveEnergyPayment(
      pool: defenderBefore.energyPool,
      spent: defenderBefore.spentEnergy,
      cost: syntheticCost,
      allowWildSubstitution: rules.counterAllowsWildSubstitution,
    );
    if (!payment.isSuccess) {
      // checkCounterLegalityで支払い可能と確認済みのため通常到達しないが、
      // _prepareTechniqueUseと同じ理由で防御的にfail-fastしておく。
      throw CombatV1IllegalActionException(payment.failureReason!);
    }

    final rng = random ?? Random();
    final attackerName = state.active.wrestlerName;
    final defenderName = defenderBefore.wrestlerName;

    // 6. defender COUNTER ENERGY支払い事前計算（上で完了）→ 8. spentEnergy更新
    var next = state.withOpponent(
      defenderBefore.copyWith(spentEnergy: payment.updatedSpent),
    );

    // 9. pending attack card → attacker discard（攻撃効果は無効、DMG/HEAT/
    // posture変更なし）
    next = next.withActive(
      next.active.copyWith(
        discardPile: [...next.active.discardPile, pending.attackCardInstance],
      ),
    );

    // 10. Counter card → defender handからdiscard
    final defenderAfterCounter = next.opponent;
    final handAfterCounter = List<CombatV1DeckEntry>.from(
      defenderAfterCounter.hand,
    )..remove(counterEntry);
    next = next.withOpponent(
      defenderAfterCounter.copyWith(
        hand: handAfterCounter,
        discardPile: [...defenderAfterCounter.discardPile, counterEntry],
      ),
    );

    next = next.copyWith(
      log: [
        ...next.log,
        '$defenderNameが${counter.name}で$attackerNameの攻撃をCOUNTERした',
      ],
    );

    // 12. attacker 1 draw
    final (attackerAfterDraw, attackerDrawLogs) = _drawOne(next.active, rng);
    next = next
        .withActive(attackerAfterDraw)
        .copyWith(log: [...next.log, ...attackerDrawLogs]);

    // 13. defender 1 draw
    final (defenderAfterDraw, defenderDrawLogs) = _drawOne(next.opponent, rng);
    next = next
        .withOpponent(defenderAfterDraw)
        .copyWith(log: [...next.log, ...defenderDrawLogs]);

    // 14. pending clear、15. phase = action
    // （16. activePlayerIndexは変更しないため攻撃側のまま維持される）
    return next.clearPendingAttack().copyWith(phase: CombatV1MatchPhase.action);
  }

  /// COUNTERせずに攻撃を成立させる（docs/combat_rules_v1.md 7.1章、
  /// Phase 4）。`phase == counterResponsePending`でのみ
  /// 許可。ゲーム結果としてはPhase 3の即時成功解決と同じになる
  /// （DMG→HP 0 clamp→shared HEAT→相手状態変化→使用カードdiscard→1
  /// draw）。
  static CombatV1MatchState declineCounter(
    CombatV1MatchState state, {
    Random? random,
  }) {
    if (state.phase != CombatV1MatchPhase.counterResponsePending) {
      throw CombatV1IllegalActionException(
        'declineCounterはcounterResponsePendingフェーズでのみ呼び出せます'
        '（現在: ${state.phase.name}）',
      );
    }
    final pending = state.pendingAttack;
    if (pending == null) {
      throw CombatV1IllegalActionException('応答待ちの攻撃がありません');
    }

    return _resolvePendingAttack(state, pending, random: random ?? Random());
  }

  /// pending攻撃を成立させる（decline経路専用。docs/combat_rules_v1.md
  /// 7.1章の処理順、Phase
  /// 3の`_resolveSuccessfulTechnique`の責務を再利用する）:
  ///
  /// 1. DMG適用
  /// 2. HP 0 clamp
  /// 3. shared HEAT加算
  /// 4. 相手状態変化
  /// 5. pending攻撃カードを攻撃側のdiscardへ
  /// 6. 攻撃側1 draw
  /// 7. pending clear、phase = action
  static CombatV1MatchState _resolvePendingAttack(
    CombatV1MatchState state,
    CombatV1PendingAttack pending, {
    required Random random,
  }) {
    final attackerName = state.active.wrestlerName;

    // 1. DMG適用 + 2. HP 0 clamp
    final hpAfterDamage = max(
      0,
      min(state.opponent.hp - pending.damage, state.opponent.maxHp),
    );
    var next = state.withOpponent(state.opponent.copyWith(hp: hpAfterDamage));

    // 3. shared HEAT加算
    next = next.copyWith(sharedHeat: next.sharedHeat + pending.heatGain);

    // 4. 相手状態変化（nullなら状態変化なし）
    if (pending.resultOpponentState != null) {
      next = next.withOpponent(
        next.opponent.copyWith(posture: pending.resultOpponentState),
      );
    }

    // 5. pending攻撃カードを攻撃側のdiscardへ
    next = next.withActive(
      next.active.copyWith(
        discardPile: [...next.active.discardPile, pending.attackCardInstance],
      ),
    );
    next = next.copyWith(
      log: [
        ...next.log,
        '$attackerNameの攻撃がCOUNTERされず成立した'
            '（DMG${pending.damage}、HEAT+${pending.heatGain}）',
      ],
    );

    // 6. 攻撃側1 draw
    final (drawnAttacker, drawLogs) = _drawOne(next.active, random);
    next = next.withActive(drawnAttacker).copyWith(
      log: [...next.log, ...drawLogs],
    );

    // 7. pending clear、phase = action
    return next.clearPendingAttack().copyWith(phase: CombatV1MatchPhase.action);
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
  // 例外を出さず、legal/reason/reasonCodeの組で結果を返す
  // （docs/design/combat_v1_phase1_design.md 4章、Phase 3でreasonCodeを追加）。

  /// TECHNIQUE使用のlegalityを判定する（Phase 3で正式化、
  /// docs/combat_rules_v1.md 4・6・7・13章）。
  ///
  /// 少なくとも以下を順に判定する:
  /// 1. `phase == action`
  /// 2. 指定instanceIdがactive playerのhandに存在するか
  /// 3. cardIdが[catalog]に存在するか
  /// 4. COUNTERカードではないか（COUNTERはTECHNIQUEとして使用不可、7章）
  /// 5. `entry.category`とTechnique定義の`category`が一致するか
  /// 6. FINISHERではないか（FINISHER本処理はPhase 9、13章）
  /// 7. Technique定義の静的データが有効か（[CombatV1Technique.isStaticDataValid]）
  /// 8. `requiredOpponentState`を満たすか
  /// 9. ENERGYを支払えるか（ワイルド補完込み、5.1章）
  ///
  /// [CombatV1CardCatalog]を横断参照の正式な入口として使う（Phase
  /// 2で導入、`combat_v1_deck_validation.dart`）。TECHNIQUE/COUNTER双方の
  /// カタログを持つため、COUNTERカードの誤用や、cardIdがCOUNTERとして
  /// 定義されているのに`entry.category`がnormal/signatureを騙るような
  /// 不整合エントリも検出できる。
  ///
  /// Phase 4のCodexレビュー指摘（10-3）対応: 以前は`catalog.categoryOf`が
  /// counter以外の非nullカテゴリを返したのに`catalog.techniques[cardId]`が
  /// nullになる（＝カード定義がTECHNIQUEではない）という防御的な
  /// `notTechnique`分岐を持っていたが、`categoryOf`の実装
  /// （`combat_v1_deck_validation.dart`）を確認したところ、techniques側に
  /// 該当cardIdが存在する場合にのみcounter以外の値を返す構造になっており、
  /// この分岐は構造的に到達不能だった。到達不能なreasonCodeを形骸化させず
  /// 削除し、下記の非null assertionへ整理した。
  static CombatV1ActionCheck checkTechniqueLegality(
    CombatV1MatchState state,
    String instanceId, {
    required CombatV1CardCatalog catalog,
  }) {
    if (state.phase != CombatV1MatchPhase.action) {
      return CombatV1ActionCheck.failure(
        'actionフェーズではありません（現在: ${state.phase.name}）',
        CombatV1TechniqueLegalityReasonCode.wrongPhase,
      );
    }

    final attacker = state.active;
    final entry = _findInHand(attacker, instanceId);
    if (entry == null) {
      return const CombatV1ActionCheck.failure(
        '指定されたカードは手札にありません',
        CombatV1TechniqueLegalityReasonCode.cardNotInHand,
      );
    }

    final definedCategory = catalog.categoryOf(entry.cardId);
    if (definedCategory == null) {
      return CombatV1ActionCheck.failure(
        '技カタログに見つかりません: ${entry.cardId}',
        CombatV1TechniqueLegalityReasonCode.missingCatalogEntry,
      );
    }
    if (definedCategory == CombatV1CardCategory.counter) {
      return const CombatV1ActionCheck.failure(
        'COUNTERカードはTECHNIQUEとして使用できません',
        CombatV1TechniqueLegalityReasonCode.counterCannotAttack,
      );
    }

    // definedCategory != null && != counterの時点で、categoryOfの実装
    // （techniques側を先に見て非nullならそのcategoryを返す）により
    // catalog.techniques[entry.cardId]は必ず非null（上記コメント参照）。
    final technique = catalog.techniques[entry.cardId]!;

    if (entry.category != definedCategory) {
      return CombatV1ActionCheck.failure(
        '${entry.cardId}のカテゴリが一致しません'
        '（DeckEntry: ${entry.category.name}、カード定義: '
        '${definedCategory.name}）',
        CombatV1TechniqueLegalityReasonCode.categoryMismatch,
      );
    }

    if (technique.category == CombatV1CardCategory.finisher) {
      return const CombatV1ActionCheck.failure(
        'FINISHERはまだ実装されていません（Phase 9で実装予定）',
        CombatV1TechniqueLegalityReasonCode.finisherNotImplemented,
      );
    }

    if (!technique.isStaticDataValid) {
      return const CombatV1ActionCheck.failure(
        '技の静的データが不正です（ENERGY COST・DMG・HEATのいずれかが不正です）',
        CombatV1TechniqueLegalityReasonCode.invalidTechniqueData,
      );
    }

    final required = technique.requiredOpponentState;
    if (required != null && state.opponent.posture != required) {
      return CombatV1ActionCheck.failure(
        '相手の状態（${state.opponent.posture.name}）が使用条件'
        '（${required.name}）を満たしません',
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    }

    final payment = resolveEnergyPayment(
      pool: attacker.energyPool,
      spent: attacker.spentEnergy,
      cost: technique.energyCost,
      allowWildSubstitution: true,
    );
    if (!payment.isSuccess) {
      return CombatV1ActionCheck.failure(
        payment.failureReason!,
        CombatV1TechniqueLegalityReasonCode.insufficientEnergy,
      );
    }

    return const CombatV1ActionCheck.success('使用できます');
  }

  /// COUNTER使用のlegalityを判定する（Phase 4、docs/combat_rules_v1.md
  /// 7章「COUNTER」）。
  ///
  /// 少なくとも以下を順に判定する:
  /// 1. `phase == counterResponsePending`
  /// 2. pendingが存在するか
  /// 3. 指定instanceIdが防御側（`state.opponent`。`counterResponsePending`
  ///    の間`activePlayerIndex`は攻撃側のまま変化しないため、常に
  ///    `pendingAttack.defenderPlayerIndex`と一致する）のhandに存在するか
  /// 4. cardIdが[catalog]に存在するか
  /// 5. カード定義がCOUNTERか
  /// 6. `entry.category`とCounter定義の`category`が一致するか
  /// 7. Counter.attributeがwildではないか
  /// 8. 技系統・技系統グループが一致するか（[techniqueFamilyMatchesCounter]）
  /// 9. 動的ENERGY COSTを支払えるか（[counterSyntheticCost]、
  ///    [CombatV1RulesConfig.counterAllowsWildSubstitution]に従う）
  static CombatV1CounterActionCheck checkCounterLegality(
    CombatV1MatchState state,
    String instanceId, {
    required CombatV1CardCatalog catalog,
    required CombatV1RulesConfig rules,
  }) {
    if (state.phase != CombatV1MatchPhase.counterResponsePending) {
      return CombatV1CounterActionCheck.failure(
        'counterResponsePendingフェーズではありません（現在: ${state.phase.name}）',
        CombatV1CounterLegalityReasonCode.wrongPhase,
      );
    }

    final pending = state.pendingAttack;
    if (pending == null) {
      return const CombatV1CounterActionCheck.failure(
        '応答待ちの攻撃がありません',
        CombatV1CounterLegalityReasonCode.noPendingAttack,
      );
    }

    final defender = state.opponent;
    final entry = _findInHand(defender, instanceId);
    if (entry == null) {
      return const CombatV1CounterActionCheck.failure(
        '指定されたカードは防御側の手札にありません',
        CombatV1CounterLegalityReasonCode.cardNotInHand,
      );
    }

    final definedCategory = catalog.categoryOf(entry.cardId);
    if (definedCategory == null) {
      return CombatV1CounterActionCheck.failure(
        '技カタログに見つかりません: ${entry.cardId}',
        CombatV1CounterLegalityReasonCode.missingCatalogEntry,
      );
    }
    if (definedCategory != CombatV1CardCategory.counter) {
      return const CombatV1CounterActionCheck.failure(
        'COUNTER以外のカードはCOUNTERとして使用できません',
        CombatV1CounterLegalityReasonCode.notCounterCard,
      );
    }

    final counter = catalog.counters[entry.cardId]!;

    if (entry.category != definedCategory) {
      return CombatV1CounterActionCheck.failure(
        '${entry.cardId}のカテゴリが一致しません'
        '（DeckEntry: ${entry.category.name}、カード定義: '
        '${definedCategory.name}）',
        CombatV1CounterLegalityReasonCode.categoryMismatch,
      );
    }

    if (counter.attribute == CombatV1EnergyAttribute.wild) {
      return const CombatV1CounterActionCheck.failure(
        'このCOUNTERのattributeがwildです（Catalog validation違反データ）',
        CombatV1CounterLegalityReasonCode.wildAttribute,
      );
    }

    if (!techniqueFamilyMatchesCounter(counter, pending.family)) {
      return const CombatV1CounterActionCheck.failure(
        '攻撃の技系統・技系統グループのいずれとも一致しません',
        CombatV1CounterLegalityReasonCode.familyGroupMismatch,
      );
    }

    final syntheticCost = counterSyntheticCost(counter, pending.energyCost);
    final payment = resolveEnergyPayment(
      pool: defender.energyPool,
      spent: defender.spentEnergy,
      cost: syntheticCost,
      allowWildSubstitution: rules.counterAllowsWildSubstitution,
    );
    if (!payment.isSuccess) {
      return CombatV1CounterActionCheck.failure(
        payment.failureReason!,
        CombatV1CounterLegalityReasonCode.insufficientEnergy,
      );
    }

    return const CombatV1CounterActionCheck.success('COUNTERできます');
  }

  /// 現在の手番プレイヤーが使用可能なTECHNIQUEを1枚でも持っているか。
  /// エンジン自身はこれを見て自動的にターンを進めたりしない
  /// （呼び出し側の判断材料としてのみ提供する）。
  static bool hasAnyPlayableTechnique(
    CombatV1MatchState state, {
    required CombatV1CardCatalog catalog,
  }) {
    if (state.phase != CombatV1MatchPhase.action) return false;
    for (final entry in state.active.hand) {
      final check = checkTechniqueLegality(
        state,
        entry.instanceId,
        catalog: catalog,
      );
      if (check.legal) return true;
    }
    return false;
  }

  /// 防御側が使用可能なCOUNTERを1枚でも持っているか（Phase 4、
  /// docs/combat_rules_v1.md 7章「COUNTER」）。
  static bool hasAnyPlayableCounter(
    CombatV1MatchState state, {
    required CombatV1CardCatalog catalog,
    required CombatV1RulesConfig rules,
  }) {
    if (state.phase != CombatV1MatchPhase.counterResponsePending) return false;
    if (state.pendingAttack == null) return false;
    for (final entry in state.opponent.hand) {
      final check = checkCounterLegality(
        state,
        entry.instanceId,
        catalog: catalog,
        rules: rules,
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

/// [CombatV1Engine._prepareTechniqueUse]の結果。TECHNIQUE宣言のlegality検証
/// とENERGY支払い確定は済んでいるが、まだ宣言はコミットされていない状態を
/// 表す（`_commitTechniqueDeclaration`が実際のコミットを行う）。
class _PreparedTechniqueUse {
  const _PreparedTechniqueUse({
    required this.entry,
    required this.technique,
    required this.updatedSpentEnergy,
  });

  final CombatV1DeckEntry entry;
  final CombatV1Technique technique;
  final Map<CombatV1EnergyAttribute, int> updatedSpentEnergy;
}
