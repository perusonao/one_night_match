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
import 'combat_v1_pin_rules.dart';
import 'combat_v1_rest_rules.dart';
import 'combat_v1_rules_config.dart';
import 'combat_v1_state_invariants.dart';
import 'combat_v1_submission_rules.dart';
import 'combat_v1_successful_technique_snapshot.dart';
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

  /// 試合が既に決着している（Phase 5、[CombatV1MatchState.isOver]）。
  /// PINによる決着後は`phase`が`action`のまま残るケースがあるため
  /// （docs/combat_rules_v1.md 8.2章、Phase 5）、`wrongPhase`とは独立に
  /// 判定する。
  matchOver,

  /// `phase == action`ではない。
  wrongPhase,

  /// 自分（active player）がDOWN状態のまま（docs/combat_rules_v1.md 11章
  /// 「DOWN状態の自ターンでは、起き上がりまたはRESTを選択できる」、Phase
  /// 7）。先に[CombatV1Engine.standUp]または[CombatV1Engine.rest]で
  /// DOWNから復帰しない限り、TECHNIQUEは使用できない。
  selfDown,

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

  /// [CombatV1MatchState]自体が構造的に不整合（`phase`と`pendingAttack`の
  /// 整合性、pendingの`attackerPlayerIndex`/`defenderPlayerIndex`の整合性
  /// など）。通常のCommand呼び出しでは到達しないが、直接構築された
  /// malformed stateに対する防御的チェック（Phase 4 Codexレビュー指摘H1）。
  malformedPendingState,
}

/// [CombatV1Engine.checkTechniqueLegality] 等、読み取り専用の判定APIの結果。
///
/// Phase 4のCodexレビュー指摘（M2、旧10-2）対応: 以前は`legal`と
/// [reasonCode]を別々の位置引数として渡す設計だったため、理論上
/// `legal=false`かつ`reasonCode=legal`のような矛盾した組み合わせを型
/// システムが防げなかった。名前付きファクトリコンストラクタ
/// （[CombatV1ActionCheck.success]/[CombatV1ActionCheck.failure]）のみを
/// 公開し、矛盾した組み合わせを構築できない設計へ改めた。
///
/// Phase 4 Codexレビュー追加指摘（H4）: 当初`failure`側は`assert`で
/// `reasonCode != legal`を強制していたが、`assert`はrelease
/// buildで無効化されるため、release環境では矛盾状態を構築できてしまう
/// 欠陥があった。`assert`に依存せず、コンストラクタ本体で無条件に
/// [ArgumentError]を送出する方式へ変更した（この検証のため`failure`は
/// `const`コンストラクタではなくなった。`success`は矛盾しようがないため
/// 引き続き`const`のまま）。
class CombatV1ActionCheck {
  const CombatV1ActionCheck.success(this.reason)
    : legal = true,
      reasonCode = CombatV1TechniqueLegalityReasonCode.legal;

  CombatV1ActionCheck.failure(this.reason, this.reasonCode) : legal = false {
    if (reasonCode == CombatV1TechniqueLegalityReasonCode.legal) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'CombatV1ActionCheck.failureにはlegal以外のreasonCodeを指定してください',
      );
    }
  }

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

  /// [CombatV1MatchState]自体が構造的に不整合（`pendingStructuralConsistencyViolation`
  /// 参照、Phase 4 Codexレビュー指摘H1）、または`pendingAttack`が所有する
  /// カードの所有権が壊れている（`pendingAttackOwnershipViolation`参照、
  /// Phase 4 Codex再レビュー指摘H1残件）。
  malformedPendingState,
}

/// [CombatV1Engine.checkCounterLegality]の結果。[CombatV1ActionCheck]と同じ
/// 設計（`success`/`failure`ファクトリのみを公開し、矛盾した`legal`/
/// `reasonCode`の組み合わせを構築できないようにする。`failure`が`assert`
/// ではなく[ArgumentError]でrelease buildでも拒否する点も同じ、H4対応）。
class CombatV1CounterActionCheck {
  const CombatV1CounterActionCheck.success(this.reason)
    : legal = true,
      reasonCode = CombatV1CounterLegalityReasonCode.legal;

  CombatV1CounterActionCheck.failure(this.reason, this.reasonCode)
    : legal = false {
    if (reasonCode == CombatV1CounterLegalityReasonCode.legal) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'CombatV1CounterActionCheck.failureにはlegal以外のreasonCodeを'
        '指定してください',
      );
    }
  }

  final bool legal;
  final String reason;
  final CombatV1CounterLegalityReasonCode reasonCode;
}

/// [CombatV1Engine.checkPinLegality]が返す機械判定用の理由コード（Phase 5、
/// docs/combat_rules_v1.md 8章「PIN」）。
///
/// DIRECT PINは同一Command内で自動的に解決するため専用のlegality
/// チェックを持たない（`_resolvePendingAttack`のコメント参照）。この
/// reasonCodeは[CombatV1Engine.declarePin]（通常PIN）専用。
enum CombatV1PinLegalityReasonCode {
  /// 宣言可能。
  legal,

  /// 試合が既に決着している（[CombatV1MatchState.isOver]）。
  matchOver,

  /// 攻撃側がPINカードを保有していない（`pinCardsHeld < 1`、
  /// docs/combat_rules_v1.md 8章「DIRECT PINでもPINカードを使用する」・
  /// 8.1章。Phase 5 Codexレビュー指摘）。正規のCommand経路では最低1枚保証
  /// （8.1章）により通常到達しないが、[malformedPinState]より前に明示的な
  /// legality理由として判定する。
  noPinCard,

  /// [CombatV1MatchState]のPIN関連state（攻撃側/防御側の`pinCardsHeld`・
  /// `koc`）がPhase 5の最小限のinvariantを満たさない
  /// （`pinStateConsistencyViolation`参照、Phase 5 Codexレビュー指摘H1）。
  /// [noPinCard]で捕捉されない残りのケース（防御側pinCardsHeld<1、PINカード
  /// 合計不一致、koc負数のいずれか）を指す。
  malformedPinState,

  /// `phase == action`ではない。
  wrongPhase,

  /// 自分（active player＝攻撃側）がDOWN状態のまま（docs/combat_rules_v1.md
  /// 11章、Phase 7）。通常のCommand経路では、TECHNIQUE宣言自体が
  /// [CombatV1TechniqueLegalityReasonCode.selfDown]で先に拒否されるため
  /// `noSuccessfulTechniqueThisTurn`より前に到達しないはずだが、防御的に
  /// 判定する（他のmalformed state判定と同じ位置付け）。
  selfDown,

  /// 相手がDOWN状態ではない（docs/combat_rules_v1.md 8章「通常PINは、
  /// 相手がDOWNで」）。
  opponentNotDown,

  /// このターン中に自分（攻撃側）がTECHNIQUEを成功させていない
  /// （docs/combat_rules_v1.md 8章「その攻撃ターン中にTECHNIQUEを
  /// 成功させている場合」）。`lastSuccessfulTechnique`はmatch-levelで
  /// ターンを跨いで残るため、`turnNumber`も一致することを要求する
  /// （stale snapshot対策、Phase 5）。
  noSuccessfulTechniqueThisTurn,
}

/// [CombatV1Engine.checkPinLegality]の結果。[CombatV1ActionCheck]・
/// [CombatV1CounterActionCheck]と同じ設計（`success`/`failure`ファクトリの
/// みを公開し、矛盾した`legal`/`reasonCode`の組み合わせを構築できないよう
/// にする）。
class CombatV1PinActionCheck {
  const CombatV1PinActionCheck.success(this.reason)
    : legal = true,
      reasonCode = CombatV1PinLegalityReasonCode.legal;

  CombatV1PinActionCheck.failure(this.reason, this.reasonCode) : legal = false {
    if (reasonCode == CombatV1PinLegalityReasonCode.legal) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'CombatV1PinActionCheck.failureにはlegal以外のreasonCodeを指定してください',
      );
    }
  }

  final bool legal;
  final String reason;
  final CombatV1PinLegalityReasonCode reasonCode;
}

/// [CombatV1Engine.checkStandUpLegality]が返す機械判定用の理由コード
/// （Phase 7、docs/combat_rules_v1.md 11章「REST / DOWN」）。
enum CombatV1StandUpLegalityReasonCode {
  /// 起き上がり可能。
  legal,

  /// 試合が既に決着している（[CombatV1MatchState.isOver]）。
  matchOver,

  /// [CombatV1MatchState]自体が構造的に不整合
  /// （[pendingStructuralConsistencyViolation]、他の判定APIと同じ防御的
  /// チェック）。
  malformedPendingState,

  /// `phase == action`ではない。
  wrongPhase,

  /// 自分（active player）がDOWN状態ではない（docs/combat_rules_v1.md 11章
  /// 「DOWN状態の自ターンでは」——起き上がり／RESTはDOWN限定）。
  notDown,
}

/// [CombatV1Engine.checkStandUpLegality]の結果。他の`ActionCheck`系クラスと
/// 同じ設計（`success`/`failure`ファクトリのみを公開する）。
class CombatV1StandUpActionCheck {
  const CombatV1StandUpActionCheck.success(this.reason)
    : legal = true,
      reasonCode = CombatV1StandUpLegalityReasonCode.legal;

  CombatV1StandUpActionCheck.failure(this.reason, this.reasonCode)
    : legal = false {
    if (reasonCode == CombatV1StandUpLegalityReasonCode.legal) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'CombatV1StandUpActionCheck.failureにはlegal以外のreasonCodeを'
        '指定してください',
      );
    }
  }

  final bool legal;
  final String reason;
  final CombatV1StandUpLegalityReasonCode reasonCode;
}

/// [CombatV1Engine.checkRestLegality]が返す機械判定用の理由コード（Phase 7、
/// docs/combat_rules_v1.md 11章「REST / DOWN」）。
enum CombatV1RestLegalityReasonCode {
  /// REST可能。
  legal,

  /// 試合が既に決着している（[CombatV1MatchState.isOver]）。
  matchOver,

  /// [CombatV1MatchState]自体が構造的に不整合
  /// （[pendingStructuralConsistencyViolation]、他の判定APIと同じ防御的
  /// チェック）。
  malformedPendingState,

  /// `phase == action`ではない。
  wrongPhase,

  /// 自分（active player）がDOWN状態ではない（docs/combat_rules_v1.md 11章
  /// 「DOWN状態の自ターンでは」——起き上がり／RESTはDOWN限定）。
  notDown,
}

/// [CombatV1Engine.checkRestLegality]の結果。他の`ActionCheck`系クラスと
/// 同じ設計（`success`/`failure`ファクトリのみを公開する）。
class CombatV1RestActionCheck {
  const CombatV1RestActionCheck.success(this.reason)
    : legal = true,
      reasonCode = CombatV1RestLegalityReasonCode.legal;

  CombatV1RestActionCheck.failure(this.reason, this.reasonCode) : legal = false {
    if (reasonCode == CombatV1RestLegalityReasonCode.legal) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'CombatV1RestActionCheck.failureにはlegal以外のreasonCodeを'
        '指定してください',
      );
    }
  }

  final bool legal;
  final String reason;
  final CombatV1RestLegalityReasonCode reasonCode;
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
    if (state.isOver) {
      throw CombatV1IllegalActionException(
        '試合は既に終了しているためdiscardCardを実行できません',
      );
    }
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
      directPin: technique.directPin,
      submissionHold: technique.submissionHold,
      finisherType: technique.finisherType,
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
    if (state.isOver) {
      throw CombatV1IllegalActionException(
        '試合は既に終了しているためplayCounterを実行できません',
      );
    }
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
  ///
  /// `checkCounterLegality`を経由しないCommandのため、
  /// `pendingStructuralConsistencyViolation`に加えて
  /// `pendingAttackOwnershipViolation`も直接ガードする（malformedな
  /// pending card ownership stateを処理しない、Phase 4 Codex再レビュー
  /// 指摘H1残件）。いずれの違反も[state]を一切変更する前に検出するため、
  /// atomicityは保たれる。
  static CombatV1MatchState declineCounter(
    CombatV1MatchState state, {
    CombatV1RulesConfig rules = const CombatV1RulesConfig(),
    Random? random,
  }) {
    if (state.isOver) {
      throw CombatV1IllegalActionException(
        '試合は既に終了しているためdeclineCounterを実行できません',
      );
    }
    final invariantViolation = pendingStructuralConsistencyViolation(state);
    if (invariantViolation != null) {
      throw CombatV1IllegalActionException(invariantViolation);
    }
    final ownershipViolation = pendingAttackOwnershipViolation(state);
    if (ownershipViolation != null) {
      throw CombatV1IllegalActionException(ownershipViolation);
    }

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

    return _resolvePendingAttack(
      state,
      pending,
      rules: rules,
      random: random ?? Random(),
    );
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
  /// 7. `lastSuccessfulTechnique`を更新（decline成功時のみ、Phase 4
  ///    Codexレビュー指摘H2/H3/12/13）
  /// 8. pending clear、phase = action
  /// 9. DIRECT PINなら同一遷移内でPINへ自動移行する（Phase
  ///    5、docs/combat_rules_v1.md 8章「DIRECT PINを持つ技は成功後に
  ///    自動的にPINへ移行する」）。古い`lastSuccessfulTechnique`
  ///    snapshotを後から参照するのではなく、今まさに解決した[pending]を
  ///    直接使うことで、stale snapshotの再発火を構造的に防ぐ
  ///    （docs/combat_rules_v1.md 8章のstale対策方針）。そうでなく
  ///    submissionHold技で解決後の相手HPが閾値以下（10.1章）なら、同じ
  ///    思想で同一遷移内でSUBMISSIONへ自動移行する（Phase 6、[pending]の
  ///    directPin/submissionHoldは排他のためelse-ifで判定する
  ///    ——`combat_v1_catalog_validation.dart`参照）。
  ///
  /// 0. （上記1に先立って）DIRECT PIN/SUBMISSIONへ移行することが事前に
  ///    判明している場合、Phase 5/6のstate invariant
  ///    （[pinStateConsistencyViolation]/[submissionStateConsistencyViolation]）
  ///    をTechnique成功のいかなるstate commitより前に検証する（Phase 5
  ///    Codexレビュー指摘H1と同じ思想、DIRECT PIN/SUBMISSION Command
  ///    atomicity）。`koc`/`pinCardsHeld`はTechnique解決自体では変化しない
  ///    ため、[state]（解決前の元state）の値で判定して問題ない。不正なら
  ///    [CombatV1IllegalActionException]を送出し、[state]を一切変更しない
  ///    （DMG・HEAT・posture・discard・attacker
  ///    draw・`lastSuccessfulTechnique`のいずれもcommitされない——
  ///    「Technique成功だけ残してPIN/SUBMISSIONだけ拒否する」設計には
  ///    しない）。
  static CombatV1MatchState _resolvePendingAttack(
    CombatV1MatchState state,
    CombatV1PendingAttack pending, {
    required CombatV1RulesConfig rules,
    required Random random,
  }) {
    if (pending.directPin) {
      final resolvedOpponentPosture =
          pending.resultOpponentState ?? state.opponent.posture;
      if (resolvedOpponentPosture == CombatV1WrestlerPosture.down) {
        final attacker = pending.attackerPlayerIndex == 0
            ? state.playerA
            : state.playerB;
        final defender = pending.defenderPlayerIndex == 0
            ? state.playerA
            : state.playerB;
        final violation = pinStateConsistencyViolation(
          attacker: attacker,
          defender: defender,
          rules: rules,
        );
        if (violation != null) {
          throw CombatV1IllegalActionException(
            'DIRECT PINへ移行できません（Technique成功処理ごと拒否）: $violation',
          );
        }
      }
    }

    if (pending.submissionHold) {
      final wouldBeOpponentHp = max(
        0,
        min(state.opponent.hp - pending.damage, state.opponent.maxHp),
      );
      if (submissionEligible(opponentHp: wouldBeOpponentHp, rules: rules)) {
        final defender = pending.defenderPlayerIndex == 0
            ? state.playerA
            : state.playerB;
        final violation = submissionStateConsistencyViolation(
          defender: defender,
        );
        if (violation != null) {
          throw CombatV1IllegalActionException(
            'SUBMISSIONへ移行できません（Technique成功処理ごと拒否）: $violation',
          );
        }
      }
    }

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

    // 7. lastSuccessfulTechniqueを更新（decline経路でのみ更新する。
    // playCounter側では一切更新しない、docs/combat_rules_v1.md 7.1章）。
    next = next.copyWith(
      lastSuccessfulTechnique: CombatV1SuccessfulTechniqueSnapshot(
        attackerPlayerIndex: pending.attackerPlayerIndex,
        turnNumber: next.turnNumber,
        cardInstanceId: pending.attackCardInstance.instanceId,
        cardId: pending.attackCardId,
        category: pending.category,
        attribute: pending.attribute,
        family: pending.family,
        directPin: pending.directPin,
        submissionHold: pending.submissionHold,
        finisherType: pending.finisherType,
        resultOpponentState: pending.resultOpponentState,
      ),
    );

    // 8. pending clear、phase = action
    next = next.clearPendingAttack().copyWith(phase: CombatV1MatchPhase.action);

    // 9. DIRECT PIN自動移行（同一遷移内、上記コメント参照）。相手がDOWNで
    // なければPINへは移行しない（PINは相手DOWNが前提、docs/combat_rules_v1.md
    // 8章）。
    if (pending.directPin &&
        next.opponent.posture == CombatV1WrestlerPosture.down) {
      next = _resolvePin(
        next,
        attackerIndex: pending.attackerPlayerIndex,
        defenderIndex: pending.defenderPlayerIndex,
        rules: rules,
        random: random,
        source: CombatV1PinSource.directPin,
      );
    } else if (pending.submissionHold &&
        submissionEligible(opponentHp: next.opponent.hp, rules: rules)) {
      // 通常SUBMISSION自動移行（同一遷移内、docs/combat_rules_v1.md
      // 10.1章「相手HP50以下で宣言可能」、Phase 6）。DIRECT PINと同じ
      // 思想——`state.lastSuccessfulTechnique`（match-level・stale化
      // しうる）は一切参照せず、今まさに解決した[pending]を直接使うことで
      // 古い成功記録によるSUBMISSIONの再発火を構造的に防ぐ。
      next = _resolveSubmission(
        next,
        attackerIndex: pending.attackerPlayerIndex,
        defenderIndex: pending.defenderPlayerIndex,
        rules: rules,
        random: random,
      );
    }

    return next;
  }

  /// ターンを終了する。`phase == action`でのみ許可。手番を交代し、新しい
  /// 手番プレイヤーのターン開始処理（ENERGY全回復・1ドロー）を行った状態
  /// （`phase == discard`）を返す。
  static CombatV1MatchState endTurn(
    CombatV1MatchState state, {
    Random? random,
  }) {
    if (state.isOver) {
      throw CombatV1IllegalActionException(
        '試合は既に終了しているためendTurnを実行できません',
      );
    }
    if (state.phase != CombatV1MatchPhase.action) {
      throw CombatV1IllegalActionException(
        'endTurnはactionフェーズでのみ呼び出せます（現在: ${state.phase.name}）',
      );
    }
    if (state.active.posture == CombatV1WrestlerPosture.down) {
      throw CombatV1IllegalActionException(
        '自分がDOWN状態のため、REST（rest）または起き上がり（standUp）を'
        '行ってからでなければendTurnを実行できません'
        '（docs/combat_rules_v1.md 11章、Phase 7）',
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

  /// DOWN状態から、HPを回復せずに起き上がる（docs/combat_rules_v1.md 11章
  /// 「DOWN状態の自ターンでは、起き上がりまたはRESTを選択できる」、Phase
  /// 7）。`phase == action`かつ自分（active player）がDOWN状態の場合のみ
  /// 許可する。
  ///
  /// posture: down→standへ遷移する以外の副作用は無い（HP・KOC・ENERGY・
  /// HEAT・hand/draw/discardのいずれも変化しない、`phase`・
  /// `activePlayerIndex`・`turnNumber`も変化しない）。ターンは終了せず、
  /// 起き上がった後は同一ターン内で通常のaction（TECHNIQUE使用等）へ進める
  /// （REST（[rest]）とは異なり、`standUp`自体はそのターンの行動を消費しない）。
  static CombatV1MatchState standUp(CombatV1MatchState state) {
    if (state.isOver) {
      throw CombatV1IllegalActionException(
        '試合は既に終了しているためstandUpを実行できません',
      );
    }
    final check = checkStandUpLegality(state);
    if (!check.legal) {
      throw CombatV1IllegalActionException(check.reason);
    }

    final player = state.active;
    final updated = player.copyWith(posture: CombatV1WrestlerPosture.stand);
    return state.withActive(updated).copyWith(
      log: [...state.log, '${player.wrestlerName}が起き上がった'],
    );
  }

  /// RESTする（docs/combat_rules_v1.md 11章「REST: HP+10回復（最大150を
  /// 超えない）。RESTしたターンはTECHNIQUEを使用できないが、COUNTERは使用
  /// 可能」、Phase 7）。`phase == action`かつ自分（active player）がDOWN
  /// 状態の場合のみ許可する。
  ///
  /// 効果:
  /// 1. HPを[CombatV1RulesConfig.restHpRecovery]回復する（`maxHp`を超えない、
  ///    [restRecoveredHp]）。
  /// 2. posture: down→standへ遷移する。
  /// 3. そのターンの行動をRESTで確定し、`endTurn`と同じ内部処理
  ///    （手番交代・turnNumber加算・新しい手番プレイヤーのターン開始処理）
  ///    まで一括で進める。
  ///
  /// 「RESTしたターンはTECHNIQUEを使用できない」（11章）は、RESTがそのターン
  /// を終了させること自体によって自然に満たされる——TECHNIQUE使用を個別に
  /// 禁止するフラグは追加しない。「COUNTERは使用可能」（11章）についても、
  /// RESTは自分（active player）の`spentEnergy`等を変更しないため、既存の
  /// COUNTER legality判定（`checkCounterLegality`）へ一切影響しない
  /// （追加コードは不要）。
  ///
  /// KOC・PINカード・HEAT・hand/draw/discardはRESTでは変化しない
  /// （docs/combat_rules_v1.md 11章に明記が無いため変更しない、13・20・21章
  /// の方針）。
  static CombatV1MatchState rest(
    CombatV1MatchState state, {
    required CombatV1RulesConfig rules,
    Random? random,
  }) {
    if (state.isOver) {
      throw CombatV1IllegalActionException(
        '試合は既に終了しているためrestを実行できません',
      );
    }
    final check = checkRestLegality(state);
    if (!check.legal) {
      throw CombatV1IllegalActionException(check.reason);
    }

    final rng = random ?? Random();
    final player = state.active;
    final healedHp = restRecoveredHp(
      currentHp: player.hp,
      maxHp: player.maxHp,
      recoveryAmount: rules.restHpRecovery,
    );
    final rested = player.copyWith(
      hp: healedHp,
      posture: CombatV1WrestlerPosture.stand,
    );

    var next = state.withActive(rested).copyWith(
      log: [
        ...state.log,
        '${player.wrestlerName}がRESTしてHPを回復した'
            '（+${rules.restHpRecovery}、HP:$healedHp）',
      ],
    );

    final flipped = next.copyWith(
      activePlayerIndex: next.activePlayerIndex == 0 ? 1 : 0,
      turnNumber: next.turnNumber + 1,
      log: [...next.log, 'ターン終了'],
    );
    return _startTurn(flipped, rng);
  }

  /// 通常PINを宣言する（docs/combat_rules_v1.md 8章、Phase 5）。`phase ==
  /// action`から任意に宣言できる（DIRECT PINのような自動移行ではなく、
  /// 攻撃側の明示的な選択）。
  ///
  /// [checkPinLegality]でlegalityを検証したうえで、[_resolvePin]で
  /// カウント・KOC・PINカード移動・kick out後の展開まで同一Command内で
  /// 一括して解決する（Phase 5セッションでユーザーが確定した「KICK OUTは
  /// 自動、カウントは一括決定」方針。防御側の任意選択によるCOUNTERのような
  /// 応答待ちフェーズは導入しない——防御側に実質的な選択肢がないため）。
  static CombatV1MatchState declarePin(
    CombatV1MatchState state, {
    required CombatV1RulesConfig rules,
    Random? random,
  }) {
    final check = checkPinLegality(state, rules: rules);
    if (!check.legal) {
      throw CombatV1IllegalActionException(check.reason);
    }

    final attackerIndex = state.activePlayerIndex;
    final defenderIndex = attackerIndex == 0 ? 1 : 0;

    return _resolvePin(
      state,
      attackerIndex: attackerIndex,
      defenderIndex: defenderIndex,
      rules: rules,
      random: random ?? Random(),
      source: CombatV1PinSource.normal,
    );
  }

  /// PINを解決する（[declarePin]・DIRECT PIN自動移行の共通処理、Phase 5、
  /// docs/combat_rules_v1.md 8章）。
  ///
  /// 防御側の[CombatV1PlayerState.koc]から、支払える最も有利なカウント
  /// （[determinePinCountResult]、8.2章）を一括で決定する。支払えるKOCが
  /// 無ければ3カウントとしてPIN決着（[CombatV1MatchState.winnerPlayerIndex]
  /// を攻撃側に設定）する。
  ///
  /// 支払い可能性を先に判定してから状態を変更する（docs/combat_rules_v1.md
  /// 「KOC invariant」方針、negativeなKOCを絶対に生成しない）。
  ///
  /// カウント結果に応じた処理（8.1・8.2章）:
  /// - 1カウント: 防御側KOC-3、PINカードが攻撃側→防御側へ1枚移動
  ///   （最低1枚保証あり）、防御側が1ドロー、その後1/2カウント共通の
  ///   ターン終了処理（下記）。
  /// - 2カウント: 防御側KOC-2、PINカード移動は1カウントと同じ、ドローなし。
  /// - 2.9カウント: 防御側KOC-1、PINカード移動なし、攻撃側は攻撃を継続
  ///   できる（`phase`・`activePlayerIndex`とも変更しない）。
  /// - 1/2カウント後: Phase 5セッションでユーザーが確定した方針により
  ///   攻守交代・ターン終了寄りの扱いとする。`endTurn`と同じ内部処理
  ///   （[_startTurn]）で防御側の新しいターンへ進める。
  static CombatV1MatchState _resolvePin(
    CombatV1MatchState state, {
    required int attackerIndex,
    required int defenderIndex,
    required CombatV1RulesConfig rules,
    required Random random,
    required CombatV1PinSource source,
  }) {
    final attackerName =
        (attackerIndex == 0 ? state.playerA : state.playerB).wrestlerName;
    final defenderBefore = defenderIndex == 0 ? state.playerA : state.playerB;
    final defenderName = defenderBefore.wrestlerName;
    final sourceLabel = source == CombatV1PinSource.directPin
        ? 'DIRECT PIN'
        : 'PIN';

    var next = state.copyWith(
      log: [...state.log, '$attackerNameが$defenderNameへ$sourceLabelを仕掛けた'],
    );

    final count = determinePinCountResult(
      defenderKoc: defenderBefore.koc,
      rules: rules,
    );

    if (count == null) {
      // 必要なKOCを支払えない → 3カウント、PIN決着
      // （docs/combat_rules_v1.md 8.2章）。
      return next.copyWith(
        winnerPlayerIndex: attackerIndex,
        log: [
          ...next.log,
          '$defenderNameはKOC不足でカウントを止められず、'
              '$attackerNameの3カウントPIN勝利で試合が終了した',
        ],
      );
    }

    final kocCost = pinKocCostFor(count, rules);
    next = _updatePlayerAt(
      next,
      defenderIndex,
      (p) => p.copyWith(koc: p.koc - kocCost),
    );

    final attackerPinCardsHeld =
        (attackerIndex == 0 ? next.playerA : next.playerB).pinCardsHeld;
    final transfer = pinCardTransferAmount(
      count: count,
      attackerPinCardsHeld: attackerPinCardsHeld,
    );
    if (transfer > 0) {
      next = _updatePlayerAt(
        next,
        attackerIndex,
        (p) => p.copyWith(pinCardsHeld: p.pinCardsHeld - transfer),
      );
      next = _updatePlayerAt(
        next,
        defenderIndex,
        (p) => p.copyWith(pinCardsHeld: p.pinCardsHeld + transfer),
      );
    }

    next = next.copyWith(
      log: [
        ...next.log,
        '$defenderNameがKOC$kocCostを支払い${count.displayLabel}カウントで'
            'キックアウトした',
      ],
    );

    if (pinCountGrantsBonusDraw(count)) {
      final defenderForDraw = defenderIndex == 0 ? next.playerA : next.playerB;
      final (drawnDefender, drawLogs) = _drawOne(defenderForDraw, random);
      next = defenderIndex == 0
          ? next.copyWith(playerA: drawnDefender)
          : next.copyWith(playerB: drawnDefender);
      next = next.copyWith(log: [...next.log, ...drawLogs]);
    }

    if (pinCountAllowsAttackerToContinue(count)) {
      // 2.9カウント: 攻撃側は攻撃を継続できる（docs/combat_rules_v1.md
      // 8.2章）。phase/activePlayerIndexとも変更しない。
      return next;
    }

    // 1/2カウント: 攻守交代・ターン終了寄り
    // （Phase 5セッションでユーザーが確定した方針）。endTurnと同じ内部処理
    // で防御側の新しいターンへ進める。
    final flipped = next.copyWith(
      activePlayerIndex: defenderIndex,
      turnNumber: next.turnNumber + 1,
      log: [...next.log, 'ターン終了'],
    );
    return _startTurn(flipped, random);
  }

  /// [index]（0=playerA、1=playerB）のプレイヤーへ[update]を適用した新しい
  /// stateを返す（`_resolvePin`内でattacker/defenderのどちらを更新するかを
  /// index経由で共通化するためのヘルパー）。
  static CombatV1MatchState _updatePlayerAt(
    CombatV1MatchState state,
    int index,
    CombatV1PlayerState Function(CombatV1PlayerState) update,
  ) => index == 0
      ? state.copyWith(playerA: update(state.playerA))
      : state.copyWith(playerB: update(state.playerB));

  /// SUBMISSIONを解決する（submissionHold Technique自動移行専用、Phase 6、
  /// docs/combat_rules_v1.md 10.1章「通常SUBMISSION」）。
  ///
  /// 防御側の[CombatV1PlayerState.koc]から、ESCAPE可否を一括で自動決定する
  /// （[determineSubmissionOutcome]。PINのKICK OUT自動判定と同じ思想——
  /// 防御側が必要なKOCを保有していれば必ずESCAPEし、あえて支払わない選択肢は
  /// 存在しない）。
  ///
  /// - ESCAPE: 防御側のKOCを[CombatV1RulesConfig.submissionEscapeKocCost]
  ///   だけ減らす。その後は攻撃側のターンを終了し、`endTurn`と同じ内部処理
  ///   でESCAPEした側（防御側）の新しいターンへ進める（PIN 1/2カウントと
  ///   同じ扱い。Phase 6セッションでユーザーが確定した方針）。
  /// - GIVE UP: KOCを支払えず、攻撃側の勝利で試合が終了する
  ///   （[CombatV1MatchState.winnerPlayerIndex]を攻撃側に設定）。
  ///
  /// PINと異なりPINカードは一切操作しない（docs/combat_rules_v1.md
  /// 10章「SUBMISSIONはPINカードを使用しない」）。支払い可能性を先に判定
  /// してから状態を変更するため、負のKOCをCommandで生成しない
  /// （docs/combat_rules_v1.md 9章）。
  static CombatV1MatchState _resolveSubmission(
    CombatV1MatchState state, {
    required int attackerIndex,
    required int defenderIndex,
    required CombatV1RulesConfig rules,
    required Random random,
  }) {
    final attackerName =
        (attackerIndex == 0 ? state.playerA : state.playerB).wrestlerName;
    final defenderBefore = defenderIndex == 0 ? state.playerA : state.playerB;
    final defenderName = defenderBefore.wrestlerName;

    var next = state.copyWith(
      log: [...state.log, '$attackerNameが$defenderNameへSUBMISSIONを仕掛けた'],
    );

    final outcome = determineSubmissionOutcome(
      defenderKoc: defenderBefore.koc,
      rules: rules,
    );

    if (outcome == CombatV1SubmissionOutcome.giveUp) {
      // 必要なKOCを支払えない → GIVE UP、SUBMISSION決着
      // （docs/combat_rules_v1.md 10.1章）。
      return next.copyWith(
        winnerPlayerIndex: attackerIndex,
        log: [
          ...next.log,
          '$defenderNameはKOC不足でESCAPEできず、'
              '$attackerNameのSUBMISSION勝利（GIVE UP）で試合が終了した',
        ],
      );
    }

    final kocCost = rules.submissionEscapeKocCost;
    next = _updatePlayerAt(
      next,
      defenderIndex,
      (p) => p.copyWith(koc: p.koc - kocCost),
    );
    next = next.copyWith(
      log: [
        ...next.log,
        '$defenderNameがKOC$kocCostを支払いSUBMISSIONからESCAPEした',
      ],
    );

    // ESCAPE成功後は攻撃側のターンを終了し、ESCAPEした側（防御側）の
    // 新しいターンへ進める（PIN 1/2カウントと同じ扱い、Phase 6セッションで
    // ユーザーが確定した方針）。
    final flipped = next.copyWith(
      activePlayerIndex: defenderIndex,
      turnNumber: next.turnNumber + 1,
      log: [...next.log, 'ターン終了'],
    );
    return _startTurn(flipped, random);
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
    if (state.isOver) {
      return CombatV1ActionCheck.failure(
        '試合は既に終了しています',
        CombatV1TechniqueLegalityReasonCode.matchOver,
      );
    }

    final invariantViolation = pendingStructuralConsistencyViolation(state);
    if (invariantViolation != null) {
      return CombatV1ActionCheck.failure(
        invariantViolation,
        CombatV1TechniqueLegalityReasonCode.malformedPendingState,
      );
    }

    if (state.phase != CombatV1MatchPhase.action) {
      return CombatV1ActionCheck.failure(
        'actionフェーズではありません（現在: ${state.phase.name}）',
        CombatV1TechniqueLegalityReasonCode.wrongPhase,
      );
    }

    if (state.active.posture == CombatV1WrestlerPosture.down) {
      return CombatV1ActionCheck.failure(
        '自分がDOWN状態です。先にREST（rest）または起き上がり（standUp）を'
        '行ってください（docs/combat_rules_v1.md 11章、Phase 7）',
        CombatV1TechniqueLegalityReasonCode.selfDown,
      );
    }

    final attacker = state.active;
    final entry = _findInHand(attacker, instanceId);
    if (entry == null) {
      return CombatV1ActionCheck.failure(
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
      return CombatV1ActionCheck.failure(
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
      return CombatV1ActionCheck.failure(
        'FINISHERはまだ実装されていません（Phase 9で実装予定）',
        CombatV1TechniqueLegalityReasonCode.finisherNotImplemented,
      );
    }

    if (!technique.isStaticDataValid) {
      return CombatV1ActionCheck.failure(
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
  /// `pendingStructuralConsistencyViolation`（構造整合性）に加えて
  /// `pendingAttackOwnershipViolation`（pendingが所有するカードのゾーン
  /// 所有権）も先頭で検証する（Phase 4 Codex再レビュー指摘H1残件）。
  /// [hasAnyPlayableCounter]はこの関数へ委譲するだけで、判定ロジックを
  /// 重複実装しない。
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
    final invariantViolation = pendingStructuralConsistencyViolation(state);
    if (invariantViolation != null) {
      return CombatV1CounterActionCheck.failure(
        invariantViolation,
        CombatV1CounterLegalityReasonCode.malformedPendingState,
      );
    }
    final ownershipViolation = pendingAttackOwnershipViolation(state);
    if (ownershipViolation != null) {
      return CombatV1CounterActionCheck.failure(
        ownershipViolation,
        CombatV1CounterLegalityReasonCode.malformedPendingState,
      );
    }

    if (state.phase != CombatV1MatchPhase.counterResponsePending) {
      return CombatV1CounterActionCheck.failure(
        'counterResponsePendingフェーズではありません（現在: ${state.phase.name}）',
        CombatV1CounterLegalityReasonCode.wrongPhase,
      );
    }

    final pending = state.pendingAttack;
    if (pending == null) {
      return CombatV1CounterActionCheck.failure(
        '応答待ちの攻撃がありません',
        CombatV1CounterLegalityReasonCode.noPendingAttack,
      );
    }

    final defender = state.opponent;
    final entry = _findInHand(defender, instanceId);
    if (entry == null) {
      return CombatV1CounterActionCheck.failure(
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
      return CombatV1CounterActionCheck.failure(
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
      return CombatV1CounterActionCheck.failure(
        'このCOUNTERのattributeがwildです（Catalog validation違反データ）',
        CombatV1CounterLegalityReasonCode.wildAttribute,
      );
    }

    if (!techniqueFamilyMatchesCounter(counter, pending.family)) {
      return CombatV1CounterActionCheck.failure(
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

  /// 通常PIN（[declarePin]）のlegalityを判定する（Phase 5、
  /// docs/combat_rules_v1.md 8章「PIN」）。UI/CPU/Simulatorが共通で使う
  /// 読み取り専用API（例外を出さず`legal`/`reason`/`reasonCode`を返す、
  /// 3・4章と同じ設計）。
  ///
  /// 少なくとも以下を順に判定する:
  /// 1. 試合が決着していないか（[CombatV1MatchState.isOver]）
  /// 2. 攻撃側がPINカードを保有しているか（`pinCardsHeld >= 1`）
  /// 3. 攻撃側/防御側のPIN関連state（pinCardsHeld合計・koc）がPhase
  ///    5のinvariantを満たすか（[pinStateConsistencyViolation]、Phase 5
  ///    Codexレビュー指摘H1）
  /// 4. `phase == action`
  /// 5. 相手がDOWN状態か
  /// 6. このターン中に自分がTECHNIQUEを成功させているか（stale
  ///    snapshot対策込み、`turnNumber`一致まで確認する）
  ///
  /// DIRECT PIN（TECHNIQUE成功と同一遷移内で自動的に開始される、
  /// `_resolvePendingAttack`参照）はこのAPIの対象外——プレイヤーが選択して
  /// 呼び出すCommandではないため。DIRECT PIN側は同じ
  /// [pinStateConsistencyViolation]をTechnique成功のstate commitより前に
  /// 直接呼び出すことでatomicityを確保する（`_resolvePendingAttack`参照）。
  static CombatV1PinActionCheck checkPinLegality(
    CombatV1MatchState state, {
    CombatV1RulesConfig rules = const CombatV1RulesConfig(),
  }) {
    if (state.isOver) {
      return CombatV1PinActionCheck.failure(
        '試合は既に終了しています',
        CombatV1PinLegalityReasonCode.matchOver,
      );
    }

    final attacker = state.active;
    final defender = state.opponent;

    if (attacker.pinCardsHeld < 1) {
      return CombatV1PinActionCheck.failure(
        '攻撃側がPINカードを保有していません',
        CombatV1PinLegalityReasonCode.noPinCard,
      );
    }

    final pinViolation = pinStateConsistencyViolation(
      attacker: attacker,
      defender: defender,
      rules: rules,
    );
    if (pinViolation != null) {
      return CombatV1PinActionCheck.failure(
        pinViolation,
        CombatV1PinLegalityReasonCode.malformedPinState,
      );
    }

    if (state.phase != CombatV1MatchPhase.action) {
      return CombatV1PinActionCheck.failure(
        'actionフェーズではありません（現在: ${state.phase.name}）',
        CombatV1PinLegalityReasonCode.wrongPhase,
      );
    }

    if (attacker.posture == CombatV1WrestlerPosture.down) {
      return CombatV1PinActionCheck.failure(
        '自分がDOWN状態です。先にREST（rest）または起き上がり（standUp）を'
        '行ってください（docs/combat_rules_v1.md 11章、Phase 7）',
        CombatV1PinLegalityReasonCode.selfDown,
      );
    }

    if (defender.posture != CombatV1WrestlerPosture.down) {
      return CombatV1PinActionCheck.failure(
        '相手がDOWN状態ではありません',
        CombatV1PinLegalityReasonCode.opponentNotDown,
      );
    }

    final last = state.lastSuccessfulTechnique;
    final hasFreshSuccess =
        last != null &&
        last.attackerPlayerIndex == state.activePlayerIndex &&
        last.turnNumber == state.turnNumber;
    if (!hasFreshSuccess) {
      return CombatV1PinActionCheck.failure(
        'このターン中にTECHNIQUEを成功させていません',
        CombatV1PinLegalityReasonCode.noSuccessfulTechniqueThisTurn,
      );
    }

    return const CombatV1PinActionCheck.success('PINを宣言できます');
  }

  /// [declarePin]で使用できるPINが存在するか（[checkPinLegality]への委譲、
  /// docs/combat_rules_v1.md 8章、Phase 5）。判定ロジックを重複実装しない
  /// （[hasAnyPlayableCounter]と同じ方針）。
  static bool hasPinOption(
    CombatV1MatchState state, {
    CombatV1RulesConfig rules = const CombatV1RulesConfig(),
  }) => checkPinLegality(state, rules: rules).legal;

  /// [standUp]のlegalityを判定する（Phase 7、docs/combat_rules_v1.md 11章
  /// 「REST / DOWN」）。UI/CPU/Simulatorが共通で使う読み取り専用API（例外を
  /// 出さず`legal`/`reason`/`reasonCode`を返す、他のcheck系APIと同じ設計）。
  ///
  /// 少なくとも以下を順に判定する:
  /// 1. 試合が決着していないか（[CombatV1MatchState.isOver]）
  /// 2. [CombatV1MatchState]自体が構造的に不整合でないか
  ///    （[pendingStructuralConsistencyViolation]）
  /// 3. `phase == action`
  /// 4. 自分（active player）がDOWN状態か（起き上がり／RESTはDOWN限定、
  ///    STAND状態では選択できない）
  static CombatV1StandUpActionCheck checkStandUpLegality(
    CombatV1MatchState state,
  ) {
    if (state.isOver) {
      return CombatV1StandUpActionCheck.failure(
        '試合は既に終了しています',
        CombatV1StandUpLegalityReasonCode.matchOver,
      );
    }

    final invariantViolation = pendingStructuralConsistencyViolation(state);
    if (invariantViolation != null) {
      return CombatV1StandUpActionCheck.failure(
        invariantViolation,
        CombatV1StandUpLegalityReasonCode.malformedPendingState,
      );
    }

    if (state.phase != CombatV1MatchPhase.action) {
      return CombatV1StandUpActionCheck.failure(
        'actionフェーズではありません（現在: ${state.phase.name}）',
        CombatV1StandUpLegalityReasonCode.wrongPhase,
      );
    }

    if (state.active.posture != CombatV1WrestlerPosture.down) {
      return CombatV1StandUpActionCheck.failure(
        '自分がDOWN状態ではありません',
        CombatV1StandUpLegalityReasonCode.notDown,
      );
    }

    return const CombatV1StandUpActionCheck.success('起き上がれます');
  }

  /// [standUp]で使用できる起き上がりが存在するか（[checkStandUpLegality]への
  /// 委譲、docs/combat_rules_v1.md 11章、Phase 7）。判定ロジックを重複実装
  /// しない（[hasPinOption]と同じ方針）。
  static bool hasStandUpOption(CombatV1MatchState state) =>
      checkStandUpLegality(state).legal;

  /// [rest]のlegalityを判定する（Phase 7、docs/combat_rules_v1.md 11章
  /// 「REST / DOWN」）。判定順序は[checkStandUpLegality]と同じ
  /// （起き上がり／RESTはどちらもDOWN限定・`phase == action`限定で、条件が
  /// 同一のため）。
  static CombatV1RestActionCheck checkRestLegality(CombatV1MatchState state) {
    if (state.isOver) {
      return CombatV1RestActionCheck.failure(
        '試合は既に終了しています',
        CombatV1RestLegalityReasonCode.matchOver,
      );
    }

    final invariantViolation = pendingStructuralConsistencyViolation(state);
    if (invariantViolation != null) {
      return CombatV1RestActionCheck.failure(
        invariantViolation,
        CombatV1RestLegalityReasonCode.malformedPendingState,
      );
    }

    if (state.phase != CombatV1MatchPhase.action) {
      return CombatV1RestActionCheck.failure(
        'actionフェーズではありません（現在: ${state.phase.name}）',
        CombatV1RestLegalityReasonCode.wrongPhase,
      );
    }

    if (state.active.posture != CombatV1WrestlerPosture.down) {
      return CombatV1RestActionCheck.failure(
        '自分がDOWN状態ではありません',
        CombatV1RestLegalityReasonCode.notDown,
      );
    }

    return const CombatV1RestActionCheck.success('RESTできます');
  }

  /// [rest]で使用できるRESTが存在するか（[checkRestLegality]への委譲、
  /// docs/combat_rules_v1.md 11章、Phase 7）。判定ロジックを重複実装しない
  /// （[hasPinOption]と同じ方針）。
  static bool hasRestOption(CombatV1MatchState state) =>
      checkRestLegality(state).legal;

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
