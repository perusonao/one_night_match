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

  /// カタログ上に存在するがTechnique定義ではない（防御的フォールバック。
  /// 通常は[counterCannotAttack]がこのケースより先に検出される）。
  notTechnique,

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
/// `game.dart`の`CardAvailability(usable, reason)`と同型の軽量パターンに、
/// Phase 3で[reasonCode]（構造化理由コード）を追加した。
class CombatV1ActionCheck {
  const CombatV1ActionCheck(
    this.legal,
    this.reason, [
    this.reasonCode = CombatV1TechniqueLegalityReasonCode.legal,
  ]);

  final bool legal;

  /// 人間可読な説明（ログ・簡易UI用）。
  final String reason;

  /// 機械判定用の理由コード（Phase 3で追加、UI/CPU/Simulator用）。
  final CombatV1TechniqueLegalityReasonCode reasonCode;
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
  /// `phase == action`でのみ許可。`phase`は`action`のまま
  /// （同一ターン内でさらにTECHNIQUEを使用できる）。
  ///
  /// 内部では「宣言可能性の検証＋ENERGY支払い確定」（[_prepareTechniqueUse]）
  /// と「成功時の効果適用」（[_resolveSuccessfulTechnique]）に処理を分離して
  /// いる。Phase 3ではこの間を置かず連続して呼び出すだけだが、Phase 4で
  /// COUNTERを実装する際、両者の間に`counterResponsePending`
  /// （宣言→COUNTER応答→解決）を挟めるようにするための内部境界である
  /// （外部APIとしての`playTechnique`の即時成功解決という挙動自体はPhase 3の
  /// 間は変わらない）。
  static CombatV1MatchState playTechnique(
    CombatV1MatchState state,
    String instanceId, {
    required CombatV1CardCatalog catalog,
    Random? random,
  }) {
    final prepared = _prepareTechniqueUse(state, instanceId, catalog: catalog);
    return _resolveSuccessfulTechnique(
      state,
      prepared,
      random: random ?? Random(),
    );
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

  /// TECHNIQUE成功時のresolution（docs/combat_rules_v1.md 11章で確定した
  /// 処理順）:
  ///
  /// 1. ENERGY消費
  /// 2. DMG適用
  /// 3. HP 0 clamp
  /// 4. shared HEAT加算
  /// 5. 相手状態変化
  /// 6. 使用カードをhandからdiscard
  /// 7. 1 draw
  ///
  /// [_prepareTechniqueUse]でlegality・ENERGY支払いは確定済みのため、この
  /// メソッドは失敗しない（例外を送出しない）。Phase
  /// 4でCOUNTERが成立した場合はこのメソッド自体を呼ばず無効化する想定で、
  /// [_prepareTechniqueUse]とは独立して呼び出せるようにしてある。
  static CombatV1MatchState _resolveSuccessfulTechnique(
    CombatV1MatchState state,
    _PreparedTechniqueUse prepared, {
    required Random random,
  }) {
    final technique = prepared.technique;
    final attackerName = state.active.wrestlerName;

    // 1. ENERGY消費
    var next = state.withActive(
      state.active.copyWith(spentEnergy: prepared.updatedSpentEnergy),
    );

    // 2. DMG適用 + 3. HP 0 clamp
    // 注: int.clamp()はnumを返しintに暗黙変換できないため、min/maxで実装する。
    final hpAfterDamage = max(
      0,
      min(next.opponent.hp - technique.damage, next.opponent.maxHp),
    );
    next = next.withOpponent(next.opponent.copyWith(hp: hpAfterDamage));

    // 4. shared HEAT加算
    next = next.copyWith(sharedHeat: next.sharedHeat + technique.heatGain);

    // 5. 相手状態変化（nullなら状態変化なし）
    if (technique.resultOpponentState != null) {
      next = next.withOpponent(
        next.opponent.copyWith(posture: technique.resultOpponentState),
      );
    }

    // 6. 使用カードをhandからdiscard
    final handAfterUse = List<CombatV1DeckEntry>.from(next.active.hand)
      ..remove(prepared.entry);
    next = next.withActive(
      next.active.copyWith(
        hand: handAfterUse,
        discardPile: [...next.active.discardPile, prepared.entry],
        techniquesUsedThisTurn: next.active.techniquesUsedThisTurn + 1,
      ),
    );
    next = next.copyWith(
      log: [
        ...next.log,
        '$attackerNameが${technique.name}を使用'
            '（DMG${technique.damage}、HEAT+${technique.heatGain}）',
      ],
    );

    // 7. 1 draw（docs/combat_rules_v1.md 16.1章）
    final (drawnAttacker, drawLogs) = _drawOne(next.active, random);
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
  /// 5. カード定義がTechniqueであるか（防御的フォールバック）
  /// 6. `entry.category`とTechnique定義の`category`が一致するか
  /// 7. FINISHERではないか（FINISHER本処理はPhase 9、13章）
  /// 8. Technique定義の静的データが有効か（[CombatV1Technique.isStaticDataValid]）
  /// 9. `requiredOpponentState`を満たすか
  /// 10. ENERGYを支払えるか（ワイルド補完込み、5.1章）
  ///
  /// [CombatV1CardCatalog]を横断参照の正式な入口として使う（Phase
  /// 2で導入、`combat_v1_deck_validation.dart`）。TECHNIQUE/COUNTER双方の
  /// カタログを持つため、COUNTERカードの誤用や、cardIdがCOUNTERとして
  /// 定義されているのに`entry.category`がnormal/signatureを騙るような
  /// 不整合エントリも検出できる。
  static CombatV1ActionCheck checkTechniqueLegality(
    CombatV1MatchState state,
    String instanceId, {
    required CombatV1CardCatalog catalog,
  }) {
    if (state.phase != CombatV1MatchPhase.action) {
      return CombatV1ActionCheck(
        false,
        'actionフェーズではありません（現在: ${state.phase.name}）',
        CombatV1TechniqueLegalityReasonCode.wrongPhase,
      );
    }

    final attacker = state.active;
    final entry = _findInHand(attacker, instanceId);
    if (entry == null) {
      return const CombatV1ActionCheck(
        false,
        '指定されたカードは手札にありません',
        CombatV1TechniqueLegalityReasonCode.cardNotInHand,
      );
    }

    final definedCategory = catalog.categoryOf(entry.cardId);
    if (definedCategory == null) {
      return CombatV1ActionCheck(
        false,
        '技カタログに見つかりません: ${entry.cardId}',
        CombatV1TechniqueLegalityReasonCode.missingCatalogEntry,
      );
    }
    if (definedCategory == CombatV1CardCategory.counter) {
      return const CombatV1ActionCheck(
        false,
        'COUNTERカードはTECHNIQUEとして使用できません',
        CombatV1TechniqueLegalityReasonCode.counterCannotAttack,
      );
    }

    final technique = catalog.techniques[entry.cardId];
    if (technique == null) {
      // definedCategoryがcounter以外かつcatalogに存在する以上、通常は
      // 到達しない（catalog.techniques/countersが正しく分離されていれば）。
      // カタログ自体の不整合に対する防御的フォールバック。
      return const CombatV1ActionCheck(
        false,
        'カード定義がTECHNIQUEではありません',
        CombatV1TechniqueLegalityReasonCode.notTechnique,
      );
    }

    if (entry.category != definedCategory) {
      return CombatV1ActionCheck(
        false,
        '${entry.cardId}のカテゴリが一致しません'
        '（DeckEntry: ${entry.category.name}、カード定義: '
        '${definedCategory.name}）',
        CombatV1TechniqueLegalityReasonCode.categoryMismatch,
      );
    }

    if (technique.category == CombatV1CardCategory.finisher) {
      return const CombatV1ActionCheck(
        false,
        'FINISHERはまだ実装されていません（Phase 9で実装予定）',
        CombatV1TechniqueLegalityReasonCode.finisherNotImplemented,
      );
    }

    if (!technique.isStaticDataValid) {
      return const CombatV1ActionCheck(
        false,
        '技の静的データが不正です（ENERGY COSTに負数またはwildが含まれています）',
        CombatV1TechniqueLegalityReasonCode.invalidTechniqueData,
      );
    }

    final required = technique.requiredOpponentState;
    if (required != null && state.opponent.posture != required) {
      return CombatV1ActionCheck(
        false,
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
      return CombatV1ActionCheck(
        false,
        payment.failureReason!,
        CombatV1TechniqueLegalityReasonCode.insufficientEnergy,
      );
    }

    return const CombatV1ActionCheck(true, '使用できます');
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
/// とENERGY支払い確定は済んでいるが、まだ効果は適用されていない状態を表す。
///
/// Phase 4でCOUNTERを実装する際、この値を`counterResponsePending`の間
/// 保持しておき、COUNTER不成立なら[CombatV1Engine._resolveSuccessfulTechnique]
/// へ、COUNTER成立なら無効化パスへ渡す、という拡張を想定している
/// （Phase 3では作らない。docs/design/combat_v1_phase1_design.md 8章）。
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
