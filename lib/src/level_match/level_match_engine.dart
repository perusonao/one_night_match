import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../wrestler_editor/models.dart';
import 'level_match_deck_builder.dart';
import 'level_match_finish_models.dart';

enum LevelMatchPhase {
  setup,
  draw,
  setCard,
  unlockCheck,
  levelChange,
  chooseMove,
  responseSelection,
  resolveMove,
  pinDecision,
  kickOutDecision,
  submissionDecision,
  turnEnd,
  gameOver,
}

/// 決着理由。Ver.0.5 で pinfall / submission を追加。
/// hpZero は旧Ver.0.4ログ互換のため残すが、Ver.0.5では新規に出力しない。
/// deckOut も Ver.0.6 で新規には出さない（山札切れは疲労へ）。exhaustion は安全弁。
/// Ver.0.9: 決着は3カウント／ギブアップのみとし、時間切れ・消耗打ち切りは
/// 勝敗を決めず draw（引き分け）とする。decision/exhaustion は旧ログ互換のため残す。
enum LevelFinishReason {
  hpZero,
  deckOut,
  pinfall,
  submission,
  exhaustion,
  decision,
  draw,
  // Ver.0.9.1: 山札切れで消耗しHPが尽きた側は、レフェリーストップ（TKO）で
  // 即座に相手の勝利とする。従来はここで決着がつかず200ターン安全弁の
  // 引き分けまで間延びしていたための追加。
  koStoppage,
}

/// Ver.0.8.0: リソース方式（将来の特殊ルール拡張の土台）。
/// classic = 現行のセットカード制（Ver.0.7バランス。カードは永続消費）。
/// energy  = MTG風エネルギーゾーン制（毎自ターン開始時にアンタップ／全回復）。
enum MatchResourceMode { classic, energy }

/// Ver.0.8.0 energyモード：場に置かれた技エネルギーカード（Ready/Used）。
class EnergyCardState {
  EnergyCardState({
    required this.instanceId,
    required this.attribute,
    required this.name,
    this.ready = true,
  });
  final String instanceId;
  final MoveAttribute attribute;
  final String name;
  bool ready;

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'attribute': attribute.name,
    'name': name,
    'ready': ready,
  };
}

/// Ver.0.7 Phase B: 攻防クラッシュの結果（レスポンダー視点）。
/// counter/speedWin = レスポンダーの勝ち、speedLoss/neutral = 攻撃側の勝ち。
enum ClashOutcome { counter, speedWin, speedLoss, neutral }

/// Ver.0.7.1: 宣言された攻撃（相手のレスポンス待ち）。
class PendingAttack {
  PendingAttack({
    required this.attackerId,
    required this.defenderId,
    required this.moveId,
    required this.isBasic,
  });
  final String attackerId;
  final String defenderId;
  final String moveId;
  final bool isBasic;

  Map<String, dynamic> toJson() => {
    'attackerId': attackerId,
    'defenderId': defenderId,
    'moveId': moveId,
    'isBasic': isBasic,
  };
}

/// Ver.0.6 バランス定数。
// Ver.0.7.3: 応酬ごとの必要HP増加を強め、フォール/ギブアップ合戦が
// 長引かず終盤へ収束するように（平均ターン短縮＝“間延び”是正）。
const int kKickOutPenaltyStep = 7; // キックアウト成功ごとの必要HP増加
const int kEscapePenaltyStep = 7; // ギブアップ耐久成功ごとの必要HP増加
const int kKickOutHeatGain = 5; // キックアウト成功時のHEAT
const int kEscapeHeatGain = 3; // ギブアップ耐久成功時のHEAT
const int kFinisherKickOutHpCost = 40; // フィニッシャーのHPキックアウト固定コスト
const int kExhaustionHpLoss = 5; // 疲労1ターンあたりのHP減少
const int kExhaustionHeatGain = 5; // 疲労1ターンあたりのHEAT増加
const int kMaxTurnSafetyCap = 200; // 無限試合を避ける安全弁

class TechniqueResourceCard {
  const TechniqueResourceCard(this.instanceId, this.attribute, {this.techniqueMoveId});
  final String instanceId;
  final MoveAttribute attribute;

  /// Ver.0.8.0 energyモード：このカードが「技カード」（手札から使用・使用後は捨て札）
  /// を表す場合に技IDを持つ。nullなら純粋な「技エネルギーカード」（場にセット）。
  final String? techniqueMoveId;

  /// エネルギーカードか（＝技として直接使えないセット専用カード）。
  bool get isEnergyOnly => techniqueMoveId == null;

  String get name => '${moveAttributeLabel(attribute)}カード';

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'attribute': attribute.name,
    if (techniqueMoveId != null) 'techniqueMoveId': techniqueMoveId,
  };
}

class MoveAvailability {
  const MoveAvailability(this.usable, this.reasons);
  final bool usable;
  final List<String> reasons;
}

class UnlockEvaluation {
  const UnlockEvaluation({
    required this.level,
    required this.satisfied,
    required this.supported,
    required this.details,
  });
  final int level;
  final bool satisfied;
  final bool supported;
  final List<String> details;

  Map<String, dynamic> toJson() => {
    'level': level,
    'satisfied': satisfied,
    'supported': supported,
    'details': details,
  };
}

class PlayerLevelMatchState {
  PlayerLevelMatchState({
    required this.playerId,
    required this.wrestler,
    required this.currentHp,
    required this.deck,
    required this.hand,
  });

  final String playerId;
  final WrestlerDefinition wrestler;
  int currentHp;
  int currentLevel = 1;
  final Set<int> unlockedLevels = {1};
  // Ver.0.9.1: 一度でも滞在したレベル（固有技の到達判定用）。CPUが
  // 複数レベル同時解禁時に上位へ直行し、中間レベル固有技が一生
  // 出番を得られない問題への対処に使う。
  final Set<int> visitedLevels = {1};
  final List<TechniqueResourceCard> deck;
  final List<TechniqueResourceCard> hand;
  final List<TechniqueResourceCard> discardPile = [];
  final List<TechniqueResourceCard> setCards = [];
  // Ver.0.8.0 energyモード専用（classicには影響しない・常に空）。
  final List<EnergyCardState> energyZone = [];
  bool finisherUsed = false;
  final Map<String, int> moveUsageCounts = {};
  int damageDealtCount = 0;
  int damageTakenCount = 0;
  final Map<MoveAttribute, int> attributeSuccessCounts = {};
  bool levelChangeUsedThisTurn = false;
  bool cardSetUsedThisTurn = false;
  int kickOutCount = 0;
  int setReplacementCount = 0;
  int? level2UnlockedTurn;
  int? level3UnlockedTurn;
  int? finisherUsedTurn;

  // Ver.0.5: レスポンスカード（イベントカード最小実装）。
  int kickOutCards = 1;
  int ropeBreakCards = 1;
  int kickOutCardUsedCount = 0;
  int ropeBreakUsedCount = 0;

  // Ver.0.5: 決着関連カウンタ。
  int pinKickOutCount = 0;
  int submissionEscapeCount = 0;
  int finisherKickOutCount = 0;
  int pinAttemptsReceived = 0;
  int submissionAttemptsReceived = 0;
  bool isDown = false;
  int? hpZeroReachedTurn;

  // Ver.0.7 Phase B: 将来拡張用の状態（コーナー/場外）。
  bool isCornered = false;
  bool isOutside = false;

  // Ver.0.6: 累積キックアウト／ギブアップ耐久ペナルティ（返すほど重くなる）。
  int kickOutPenalty = 0;
  int submissionEscapePenalty = 0;

  // Ver.0.6: 疲労状態（山札切れ→敗北ではなく疲労）。
  bool isExhausted = false;
  int exhaustionTurns = 0;

  // Ver.0.5: 飛び級解放条件用トラッキング。
  int levelChangeCount = 0;
  final Map<int, int> levelUsedCounts = {};
  final Map<int, int> levelMoveSuccessCounts = {};

  // Ver.0.5: CPU評価用（直前使用技）。
  String? previousMoveId;

  // Ver.0.7: このプレイヤーが直前に使った技（相手の「前ターン技」表示・読み合い用）。
  String? lastUsedMoveId;
  String? lastUsedMoveName;
  int? lastUsedMoveSpeed;
  bool lastUsedWasBasic = false;

  // Ver.0.5: 自動生成デッキの内訳（プレビュー・ログ用）。
  DeckBuildResult? deckBuild;

  WrestlerLevelDefinition get levelCard =>
      wrestler.levels.firstWhere((item) => item.level == currentLevel);

  Map<MoveAttribute, int> get setAttributeCounts => {
    for (final attribute in MoveAttribute.values)
      attribute: setCards.where((card) => card.attribute == attribute).length,
  };

  /// Ver.0.8.0: エネルギーゾーンのうちReady（使用可能）な枚数を属性別に集計。
  Map<MoveAttribute, int> get readyEnergyCounts {
    final map = <MoveAttribute, int>{for (final a in MoveAttribute.values) a: 0};
    for (final e in energyZone) {
      if (e.ready) map[e.attribute] = (map[e.attribute] ?? 0) + 1;
    }
    return map;
  }

  Map<String, dynamic> toSummaryJson() => {
    'playerId': playerId,
    'wrestlerId': wrestler.id,
    'wrestlerName': wrestler.name,
    'maxHp': wrestler.maxHp,
    'finalHp': currentHp,
    'finalLevel': currentLevel,
    'unlockedLevels': unlockedLevels.toList()..sort(),
    'finisherUsed': finisherUsed,
    'level2UnlockedTurn': level2UnlockedTurn,
    'level3UnlockedTurn': level3UnlockedTurn,
    'finisherUsedTurn': finisherUsedTurn,
    'setReplacementCount': setReplacementCount,
    'kickOutCount': kickOutCount,
    'pinKickOutCount': pinKickOutCount,
    'submissionEscapeCount': submissionEscapeCount,
    'finisherKickOutCount': finisherKickOutCount,
    'pinAttemptsReceived': pinAttemptsReceived,
    'submissionAttemptsReceived': submissionAttemptsReceived,
    'kickOutCardUsedCount': kickOutCardUsedCount,
    'ropeBreakUsed': ropeBreakUsedCount,
    'kickOutCardsRemaining': kickOutCards,
    'ropeBreakCardsRemaining': ropeBreakCards,
    'hpZeroReachedTurn': hpZeroReachedTurn,
    'levelChangeCount': levelChangeCount,
    'kickOutPenalty': kickOutPenalty,
    'submissionEscapePenalty': submissionEscapePenalty,
    'exhausted': isExhausted,
    'exhaustionTurns': exhaustionTurns,
    'deck': deckBuild?.toJson(),
    if (energyZone.isNotEmpty)
      'energyZone': energyZone.map((e) => e.toJson()).toList(),
  };
}

class LevelMatchLogEntry {
  LevelMatchLogEntry({
    required this.turn,
    required this.playerId,
    required this.phase,
    required this.action,
    required this.message,
    this.details = const {},
  }) : timestamp = DateTime.now().toUtc();

  final int turn;
  final String playerId;
  final String phase;
  final String action;
  final String message;
  final Map<String, dynamic> details;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'turn': turn,
    'playerId': playerId,
    'phase': phase,
    'action': action,
    'message': message,
    'details': details,
    'timestamp': timestamp.toIso8601String(),
  };

  factory LevelMatchLogEntry.fromJson(Map<String, dynamic> json) =>
      LevelMatchLogEntry(
        turn: (json['turn'] as num?)?.toInt() ?? 0,
        playerId: json['playerId'] as String? ?? '',
        phase: json['phase'] as String? ?? '',
        action: json['action'] as String? ?? '',
        message: json['message'] as String? ?? '',
        details: Map<String, dynamic>.from(json['details'] as Map? ?? const {}),
      );
}

class LevelMatchState {
  LevelMatchState({
    required this.gameId,
    required this.player,
    required this.cpu,
    required this.activePlayerId,
    required this.startedAt,
  });

  final String gameId;
  final String version = '0.7';
  final String mode = 'levelCardMatch';
  LevelMatchPhase phase = LevelMatchPhase.setup;
  final PlayerLevelMatchState player;
  final PlayerLevelMatchState cpu;
  String activePlayerId;
  int turnNumber = 1;
  int sharedHeat = 0;
  String? winnerId;
  LevelFinishReason? finishReason;

  // Ver.0.8.0: 試合時間ルール（0=無制限）。1ターン=30秒。
  static const int secondsPerTurn = 30;
  int matchTimeSeconds = 0;
  MatchResourceMode resourceMode = MatchResourceMode.classic;

  // Ver.0.9: 固有技（MoveCategory.normal）をフィニッシャー同様
  // 「試合中1回まで」に制限する（レベルアップしても回数は回復しない）。
  // 1040試合のシミュレーション検証（技の偏り解消・通常技の価値向上・
  // 引き分け率改善を確認）を経てVer.0.9.1で正式採用、既定trueに変更。
  bool signatureOncePerMatch = true;

  bool get isTimed => matchTimeSeconds > 0;
  int? get turnLimit => isTimed ? matchTimeSeconds ~/ secondsPerTurn : null;

  /// 残り時間（秒）。無制限なら null。ターン開始前に完了したターン数で計算。
  int? get remainingSeconds {
    if (!isTimed) return null;
    final elapsed = (turnNumber - 1) * secondsPerTurn;
    final left = matchTimeSeconds - elapsed;
    return left < 0 ? 0 : left;
  }

  bool get isFinalMinute {
    final r = remainingSeconds;
    return r != null && r <= 60;
  }
  final List<LevelMatchLogEntry> logs = [];
  String? pendingAnimation;
  String? lastMove;
  String? lastMoveId;
  int lastDamage = 0;
  String? unlockNotice;
  final DateTime startedAt;
  DateTime? finishedAt;

  // Ver.0.7.1: 宣言中の攻撃（相手のレスポンス待ち）。
  PendingAttack? pendingAttack;

  // Ver.0.5: 進行中のフォール／ギブアップ判定と決着メタ情報。
  PendingPin? pendingPin;
  PendingSubmission? pendingSubmission;
  String? finishMoveId;
  String? finishingMove;
  int pinAttemptCount = 0;
  int submissionAttemptCount = 0;
  int kickOutTotalCount = 0;
  int submissionEscapeTotalCount = 0;
  int ropeBreakTotalCount = 0;
  int finisherKickOutTotalCount = 0;

  PlayerLevelMatchState byId(String id) =>
      id == player.playerId ? player : cpu;

  PlayerLevelMatchState get active =>
      activePlayerId == player.playerId ? player : cpu;
  PlayerLevelMatchState get defender =>
      activePlayerId == player.playerId ? cpu : player;
  bool get isGameOver => phase == LevelMatchPhase.gameOver;

  Map<String, dynamic> toJson() => {
    'game': {
      'gameId': gameId,
      'version': version,
      'mode': mode,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt?.toIso8601String(),
      'winner': winnerId,
      'finishReason': finishReason?.name,
      'finishingMove': finishingMove ?? lastMove,
      'finishMoveId': finishMoveId ?? lastMoveId,
      'turns': turnNumber,
      'finalHeat': sharedHeat,
      'matchTimeSeconds': matchTimeSeconds,
      'remainingSeconds': remainingSeconds,
      'resourceMode': resourceMode.name,
      'signatureOncePerMatch': signatureOncePerMatch,
      'lastMove': lastMove,
      'pinAttempts': pinAttemptCount,
      'kickOuts': kickOutTotalCount,
      'submissionAttempts': submissionAttemptCount,
      'submissionEscapes': submissionEscapeTotalCount,
      'ropeBreaks': ropeBreakTotalCount,
      'finisherKickOuts': finisherKickOutTotalCount,
    },
    'players': [player.toSummaryJson(), cpu.toSummaryJson()],
    'turns': logs.map((item) => item.toJson()).toList(),
  };
}

class LevelMatchEngine {
  LevelMatchEngine({required this.state, required this.moves, Random? random})
    : random = random ?? Random();

  final LevelMatchState state;
  final Map<String, MoveDefinition> moves;
  final Random random;

  static const deckBuilder = LevelMatchDeckBuilder();

  static LevelMatchEngine create({
    required WrestlerDefinition playerWrestler,
    required WrestlerDefinition cpuWrestler,
    required Map<String, MoveDefinition> moves,
    Random? random,
    bool playerStarts = true,
    int matchTimeSeconds = 0,
    MatchResourceMode resourceMode = MatchResourceMode.classic,
    // Ver.0.9.1: 未指定時はenergyモード（実プレイで使われる唯一のモード）でのみ
    // 既定trueとする。classicモードは大量の旧テスト資産のバランス前提
    // （固有技の反復使用込み）を保持するため既定falseのまま据え置く。
    bool? signatureOncePerMatch,
  }) {
    final rng = random ?? Random();
    final effectiveSignatureOncePerMatch =
        signatureOncePerMatch ?? (resourceMode == MatchResourceMode.energy);
    // Ver.0.8.0：energyモードは技カード／技エネルギーカードが混在するデッキを使う。
    // classic側のデッキ生成アルゴリズムはbuildEnergyMode内部で再利用するのみで、
    // classicモードの挙動には一切影響しない。
    final playerDeckBuild = resourceMode == MatchResourceMode.energy
        ? deckBuilder.buildEnergyMode(
            wrestler: playerWrestler, moves: moves, owner: 'player')
        : deckBuilder.build(
            wrestler: playerWrestler, moves: moves, owner: 'player');
    final cpuDeckBuild = resourceMode == MatchResourceMode.energy
        ? deckBuilder.buildEnergyMode(
            wrestler: cpuWrestler, moves: moves, owner: 'cpu')
        : deckBuilder.build(wrestler: cpuWrestler, moves: moves, owner: 'cpu');
    final playerDeck = List.of(playerDeckBuild.cards)..shuffle(rng);
    final cpuDeck = List.of(cpuDeckBuild.cards)..shuffle(rng);
    final player = PlayerLevelMatchState(
      playerId: 'player',
      wrestler: playerWrestler,
      currentHp: playerWrestler.maxHp,
      deck: playerDeck,
      hand: [],
    )..deckBuild = playerDeckBuild;
    final cpu = PlayerLevelMatchState(
      playerId: 'cpu',
      wrestler: cpuWrestler,
      currentHp: cpuWrestler.maxHp,
      deck: cpuDeck,
      hand: [],
    )..deckBuild = cpuDeckBuild;
    for (var i = 0; i < 5; i++) {
      player.hand.add(player.deck.removeLast());
      cpu.hand.add(cpu.deck.removeLast());
    }
    final state = LevelMatchState(
      gameId: 'level-${DateTime.now().microsecondsSinceEpoch}',
      player: player,
      cpu: cpu,
      activePlayerId: playerStarts ? 'player' : 'cpu',
      startedAt: DateTime.now().toUtc(),
    )
      ..matchTimeSeconds = matchTimeSeconds
      ..resourceMode = resourceMode
      ..signatureOncePerMatch = effectiveSignatureOncePerMatch;
    final engine = LevelMatchEngine(state: state, moves: moves, random: rng);
    for (final side in [player, cpu]) {
      engine._log(side, 'deckGenerated', '${side.wrestler.name}のデッキを自動生成', {
        'deck': side.deckBuild?.toJson(),
      });
    }
    return engine..beginTurn();
  }

  /// 後方互換用の固定デッキ生成（テスト等が参照する場合に備え残す）。
  static List<TechniqueResourceCard> buildDeck(String owner) {
    final counts = <MoveAttribute, int>{
      MoveAttribute.strike: 6,
      MoveAttribute.throwMove: 6,
      MoveAttribute.submission: 6,
      MoveAttribute.counter: 4,
      MoveAttribute.rough: 4,
      MoveAttribute.aerial: 4,
    };
    var serial = 0;
    return [
      for (final entry in counts.entries)
        for (var i = 0; i < entry.value; i++)
          TechniqueResourceCard('$owner-${serial++}', entry.key),
    ];
  }

  void beginTurn() {
    if (state.isGameOver) return;
    final actor = state.active;
    actor.cardSetUsedThisTurn = false;
    actor.levelChangeUsedThisTurn = false;
    // Ver.0.8.0 energyモード：自ターン開始時にエネルギーを全てアンタップ（Ready）。
    if (state.resourceMode == MatchResourceMode.energy) {
      for (final e in actor.energyZone) {
        e.ready = true;
      }
    }
    if (actor.isDown) {
      actor.isDown = false;
      _log(actor, 'downRecovered', '${actor.wrestler.name}はダウンから立ち上がった');
    }
    state.phase = LevelMatchPhase.draw;
    _log(actor, 'turnStart', '${actor.wrestler.name}のターン開始');
    evaluateUnlocks(actor);

    // Ver.0.9: 試合時間切れ → 引き分け（時間制限ルール時のみ）。
    // 決着は3カウント／ギブアップのみとし、時間切れでは勝敗をつけない。
    final limit = state.turnLimit;
    if (limit != null && state.turnNumber > limit) {
      _timeUpDraw();
      return;
    }

    // Ver.0.6: 無限試合を避ける安全弁（通常到達しない高ターン数）。
    // Ver.0.9: これも決着ではなく引き分け（消耗の果て）とする。
    if (state.turnNumber > kMaxTurnSafetyCap) {
      state.finishingMove = '消耗の果て';
      _finishDraw(LevelFinishReason.exhaustion);
      return;
    }

    // Ver.0.6: 山札切れは敗北ではなく「疲労」。毎ターンHP-5・HEAT+5。
    if (actor.deck.isEmpty) {
      actor.isExhausted = true;
      actor.exhaustionTurns++;
      actor.currentHp = max(0, actor.currentHp - kExhaustionHpLoss);
      state.sharedHeat += kExhaustionHeatGain;
      if (actor.currentHp <= 0 && actor.hpZeroReachedTurn == null) {
        actor.hpZeroReachedTurn = state.turnNumber;
      }
      _log(actor, 'exhausted', '${actor.wrestler.name}は消耗（山札切れ）: HP-$kExhaustionHpLoss', {
        'exhaustionTurns': actor.exhaustionTurns,
        'hpAfter': actor.currentHp,
        'heatAfter': state.sharedHeat,
      });
      // Ver.0.9.1: 山札が尽きた状態でHPも0まで消耗した場合、これ以上
      // 攻防を継続できないとみなしレフェリーストップ（TKO）で即決着とする。
      // 200ターン安全弁まで膠着して引き分けになる問題への対処。
      if (actor.currentHp <= 0) {
        final opponent = _opponentOf(actor);
        state.finishingMove = 'レフェリーストップ';
        _finish(opponent, LevelFinishReason.koStoppage);
        return;
      }
      state.phase = LevelMatchPhase.setCard;
      return;
    }
    final card = actor.deck.removeLast();
    actor.hand.add(card);
    _log(actor, 'draw', '${card.name}をドロー', {
      'drawnCard': card.toJson(),
      'handAfter': actor.hand.length,
    });
    state.phase = LevelMatchPhase.setCard;
  }

  void setTechniqueCard(
    String playerId,
    String cardInstanceId, {
    String? replaceInstanceId,
  }) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.setCard) {
      throw StateError('現在は技カードセットフェイズではありません');
    }
    if (actor.cardSetUsedThisTurn) throw StateError('1ターンにセットできるのは1枚です');
    final cardIndex = actor.hand.indexWhere(
      (item) => item.instanceId == cardInstanceId,
    );
    if (cardIndex < 0) throw StateError('手札にカードがありません');

    // Ver.0.8.0 energyモード：エネルギーゾーンへセット（永続・毎ターンアンタップ）。
    // 技カード（techniqueMoveId付き）はセット不可＝使用（捨て札）専用。
    if (state.resourceMode == MatchResourceMode.energy) {
      if (!actor.hand[cardIndex].isEnergyOnly) {
        throw StateError('技カードはエネルギーとしてセットできません（使用してください）');
      }
      final card = actor.hand.removeAt(cardIndex);
      final energyCard = EnergyCardState(
        instanceId: card.instanceId,
        attribute: card.attribute,
        name: card.name,
      );
      actor.energyZone.add(energyCard);
      actor.cardSetUsedThisTurn = true;
      _log(actor, 'setEnergy', '${card.name}をエネルギーゾーンへセット', {
        'energyCard': energyCard.toJson(),
        'readyEnergyCounts': _attributeJson(actor.readyEnergyCounts),
      });
      evaluateUnlocks(actor);
      state.phase = LevelMatchPhase.levelChange;
      return;
    }

    TechniqueResourceCard? removed;
    if (actor.setCards.length >= 6) {
      if (replaceInstanceId == null) throw StateError('セット上限です。交換が必要です');
      final removeIndex = actor.setCards.indexWhere(
        (item) => item.instanceId == replaceInstanceId,
      );
      if (removeIndex < 0) throw StateError('交換対象が見つかりません');
      removed = actor.setCards.removeAt(removeIndex);
      actor.discardPile.add(removed);
      actor.setReplacementCount++;
    }
    final card = actor.hand.removeAt(cardIndex);
    actor.setCards.add(card);
    actor.cardSetUsedThisTurn = true;
    _log(actor, 'setCard', '${card.name}をセット', {
      'setCard': card.toJson(),
      'removedSetCard': removed?.toJson(),
      'setAttributeCounts': _attributeJson(actor.setAttributeCounts),
    });
    evaluateUnlocks(actor);
    state.phase = LevelMatchPhase.levelChange;
  }

  void skipSetCard(String playerId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.setCard) {
      throw StateError('セットをスキップできません');
    }
    actor.cardSetUsedThisTurn = true;
    _log(actor, 'skipSet', '技カードのセットを見送った');
    state.phase = LevelMatchPhase.levelChange;
  }

  void changeLevel(String playerId, int targetLevel) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.levelChange) {
      throw StateError('レベル変更フェイズではありません');
    }
    if (actor.levelChangeUsedThisTurn) throw StateError('レベル変更は1ターンに1回です');
    if (!actor.unlockedLevels.contains(targetLevel)) {
      throw StateError('未解放レベルです');
    }
    if (actor.currentLevel == targetLevel) throw StateError('現在と同じレベルです');
    final before = actor.currentLevel;
    actor.currentLevel = targetLevel;
    actor.visitedLevels.add(targetLevel);
    actor.levelChangeUsedThisTurn = true;
    actor.levelChangeCount++;
    _log(actor, 'changeLevel', 'Level $before → Level $targetLevel', {
      'levelBefore': before,
      'levelAfter': targetLevel,
      'levelChangeCount': actor.levelChangeCount,
    });
    evaluateUnlocks(actor);
    state.phase = LevelMatchPhase.chooseMove;
  }

  void skipLevelChange(String playerId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.levelChange) {
      throw StateError('レベル変更をスキップできません');
    }
    _log(actor, 'keepLevel', 'Level ${actor.currentLevel}を維持');
    state.phase = LevelMatchPhase.chooseMove;
  }

  MoveAvailability evaluateMove(
    PlayerLevelMatchState actor,
    MoveDefinition move,
  ) {
    final reasons = <String>[];
    final level = actor.levelCard;
    final registered =
        level.moveIds.contains(move.id) ||
        level.counterMoveId == move.id ||
        level.finisherId == move.id;
    if (!registered) reasons.add('現在のLevelカードに登録されていません');
    if (state.resourceMode == MatchResourceMode.energy) {
      // Ver.0.8.0 energyモード：Ready状態のエネルギーで支払えるかを判定。
      final ready = actor.readyEnergyCounts;
      for (final entry in move.energyModeRequiredCards.entries) {
        final shortage = entry.value - (ready[entry.key] ?? 0);
        if (shortage > 0) {
          reasons.add(
            '${moveAttributeLabel(entry.key)}エネルギーがReadyで$shortage不足しています',
          );
        }
      }
    } else {
      final counts = actor.setAttributeCounts;
      for (final entry in move.requiredCards.entries) {
        final shortage = entry.value - (counts[entry.key] ?? 0);
        if (shortage > 0) {
          reasons.add('${moveAttributeLabel(entry.key)}カードが$shortage枚不足しています');
        }
      }
      for (final entry in move.discardAfterUse.entries) {
        final shortage = entry.value - (counts[entry.key] ?? 0);
        if (shortage > 0) {
          reasons.add(
            '破棄する${moveAttributeLabel(entry.key)}カードが$shortage枚不足しています',
          );
        }
      }
    }
    if (move.category == MoveCategory.finisher && actor.finisherUsed) {
      reasons.add('フィニッシャーは使用済みです');
    }
    if (move.usageLimit != null &&
        (actor.moveUsageCounts[move.id] ?? 0) >= move.usageLimit!) {
      reasons.add('使用回数制限に達しています');
    }
    // Ver.0.9: 検証用オプションルール。固有技を試合中1回までに制限する
    // （レベルアップしても回復しない）。フィニッシャーは元々1回のみなので対象外。
    if (state.signatureOncePerMatch &&
        move.category == MoveCategory.normal &&
        (actor.moveUsageCounts[move.id] ?? 0) >= 1) {
      reasons.add('固有技は1試合1回までです（使用済み）');
    }
    if (!_meetsRequiredState(actor, move)) {
      reasons.add('必要な状態（${move.requiredPreviousState}）を満たしていません');
    }
    for (final condition in move.conditions) {
      if (!_evaluateMoveCondition(condition, actor)) {
        reasons.add(
          _isSupportedMoveCondition(condition.type)
              ? '使用条件「${condition.type}」を満たしていません'
              : 'この技にはVer.0.4未対応の使用条件があります（${condition.type}）',
        );
      }
    }
    return MoveAvailability(reasons.isEmpty, reasons);
  }

  /// Ver.0.7.1: 固有技を「宣言」する（相手のレスポンス待ちへ）。
  void useMove(String playerId, String moveId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.chooseMove) {
      throw StateError('技選択フェイズではありません');
    }
    final rawMove = moves[moveId];
    if (rawMove == null) throw StateError('技が見つかりません');
    // Ver.0.8.0: energyモード専用バランス上書き（classicの技マスタ本体は不変）。
    final move = state.resourceMode == MatchResourceMode.energy
        ? rawMove.resolvedForEnergyMode
        : rawMove;
    if (move.isCounterMove && !move.canUseAsNormalMove) {
      throw StateError('返し技は相手の技に対応するときだけ使えます');
    }
    final availability = evaluateMove(actor, move);
    if (!availability.usable) throw StateError(availability.reasons.join('\n'));
    _declareAttack(actor, move, isBasic: false);
  }

  void _declareAttack(
    PlayerLevelMatchState actor,
    MoveDefinition move, {
    required bool isBasic,
  }) {
    // 宣言＝コミット。使用回数を加算し、コストを消費（失敗しても戻らない）。
    actor.moveUsageCounts[move.id] = (actor.moveUsageCounts[move.id] ?? 0) + 1;
    actor.previousMoveId = move.id;
    if (move.category == MoveCategory.finisher) {
      actor.finisherUsed = true;
      actor.finisherUsedTurn = state.turnNumber;
    }
    List<TechniqueResourceCard> consumed = const <TechniqueResourceCard>[];
    List<String>? energySpent;
    Map<MoveAttribute, int>? readyBefore;
    Map<MoveAttribute, int>? readyAfter;
    if (state.resourceMode == MatchResourceMode.energy) {
      // Ver.0.8.0 energyモード：単体技も固有技も等しくエネルギーを消費する
      // （「無料通常技」の廃止）。検証・観戦用に消費前後の内訳を記録する。
      readyBefore = Map.of(actor.readyEnergyCounts);
      energySpent = _consumeEnergy(actor, move.energyModeRequiredCards);
      readyAfter = Map.of(actor.readyEnergyCounts);
    } else if (!isBasic) {
      consumed = _consumeCost(actor, move);
    }
    final defender = state.defender;
    state.pendingAttack = PendingAttack(
      attackerId: actor.playerId,
      defenderId: defender.playerId,
      moveId: move.id,
      isBasic: isBasic,
    );
    state.phase = LevelMatchPhase.responseSelection;
    state.lastMove = move.name;
    state.lastMoveId = move.id;
    _log(
      actor,
      'attackDeclared',
      '${move.name}を繰り出す（${isBasic ? "単体技" : "固有技"}・速度${move.speed}）',
      {
        'moveId': move.id,
        'basic': isBasic,
        'attribute': move.attribute.name,
        'speed': move.speed,
        'power': move.power,
        'consumedSetCards': consumed.map((e) => e.toJson()).toList(),
        if (state.resourceMode == MatchResourceMode.energy) ...{
          'energyCost': _attributeJson(move.energyModeRequiredCards),
          'energySpent': energySpent,
          'readyEnergyBefore': _attributeJson(readyBefore!),
          'readyEnergyAfter': _attributeJson(readyAfter!),
        },
        'offersPin': move.offersPin && !isBasic,
        'offersSubmission': move.offersSubmission && !isBasic,
        'causesDown': move.causesDown && !isBasic,
      },
    );
  }

  List<TechniqueResourceCard> _consumeCost(
    PlayerLevelMatchState actor,
    MoveDefinition move,
  ) {
    // Ver.0.7.1: 固有技は「必要コスト」をセットから消費（再使用に再セットが必要）。
    final cost = move.consumesSetCards ? move.requiredCards : move.discardAfterUse;
    return _discardSetCards(actor, cost);
  }

  /// Ver.0.8.0 energyモード：ReadyなエネルギーをUsedに変える（消費）。
  /// evaluateMove/responseAvailability で事前に支払い可能と確認済みの前提。
  /// 消費したエネルギーカードのinstanceIdを返す（ログ検証用）。
  List<String> _consumeEnergy(
    PlayerLevelMatchState actor,
    Map<MoveAttribute, int> cost,
  ) {
    final spent = <String>[];
    for (final entry in cost.entries) {
      var remaining = entry.value;
      for (final e in actor.energyZone) {
        if (remaining <= 0) break;
        if (e.attribute == entry.key && e.ready) {
          e.ready = false;
          spent.add(e.instanceId);
          remaining--;
        }
      }
      if (remaining > 0) {
        throw StateError('${moveAttributeLabel(entry.key)}エネルギーが不足しています');
      }
    }
    return spent;
  }

  /// 最終ダメージを5刻みに丸める（0か最低5）。
  int _roundDamage(int raw) {
    if (raw <= 0) return 0;
    final rounded = (raw / 5).round() * 5;
    return rounded <= 0 ? 5 : rounded;
  }

  /// 攻撃 attack に対して response が勝つか（レスポンダー視点）。
  ClashOutcome clashBetween(MoveDefinition attack, MoveDefinition response) {
    final canCounter =
        response.counterTypes.contains(attack.attribute) ||
        (response.category == MoveCategory.counter &&
            (response.counterTypes.isEmpty ||
                response.counterTypes.contains(attack.attribute)));
    final blocked =
        attack.specialAbilities.contains('cannotCounter') ||
        response.cannotCounterTypes.contains(attack.attribute) ||
        attack.cannotCounterTypes.contains(response.attribute);
    if (canCounter && !blocked) return ClashOutcome.counter;
    // Ver.0.7.2: フィニッシャーは通常技のSpeed勝ちで割り込めない（切り札）。
    // 有効な専用返しがなければ攻撃側が通る（neutral）。
    if (attack.ignoreNormalSpeed) return ClashOutcome.neutral;
    if (response.speed > attack.speed) return ClashOutcome.speedWin;
    if (response.speed < attack.speed) return ClashOutcome.speedLoss;
    return ClashOutcome.neutral;
  }

  /// レスポンスとして move を使えるか。返し技は対応する攻撃がある時のみ。
  MoveAvailability responseAvailability(
    PlayerLevelMatchState defender,
    MoveDefinition move, {
    required bool isBasic,
  }) {
    final atk = state.pendingAttack;
    if (atk == null) return const MoveAvailability(false, ['対応する攻撃がありません']);
    final attack = moves[atk.moveId];
    if (attack == null) return const MoveAvailability(false, ['攻撃技が不明です']);
    // Ver.0.7.2: フィニッシャーへの対応は「専用返し（返し成立）」のみ。
    // 通常技・単体技のSpeed勝ちでは割り込めない。
    if (attack.ignoreNormalSpeed) {
      if (clashBetween(attack, move) != ClashOutcome.counter) {
        return const MoveAvailability(false, ['フィニッシャーには通常技で割り込めません']);
      }
    }
    if (move.isCounterMove && !move.canUseAsNormalMove) {
      // 返し技は「対応成立」する時だけ使える。
      if (clashBetween(attack, move) != ClashOutcome.counter) {
        return const MoveAvailability(false, ['この攻撃には対応できません']);
      }
    }
    if (isBasic) {
      // Ver.0.8.0 energyモード：単体技での対応は廃止（固有技のみ）。
      if (state.resourceMode == MatchResourceMode.energy) {
        return const MoveAvailability(false, ['エネルギーモードでは単体技で対応できません']);
      }
      // フィニッシャーへ単体技で割り込むのは不可（上でカバー済み）。
      return const MoveAvailability(true, []);
    }
    return evaluateMove(defender, move);
  }

  /// 防御側：技を受ける（宣言された攻撃がそのまま成立）。
  void respondTake(String playerId) {
    final atk = state.pendingAttack;
    if (state.phase != LevelMatchPhase.responseSelection || atk == null) {
      throw StateError('対応できる局面ではありません');
    }
    if (atk.defenderId != playerId) throw StateError('対応できるのは防御側です');
    _log(state.byId(playerId), 'responseTake', '${state.byId(playerId).wrestler.name}は技を受ける');
    _resolveExchange(response: null, responder: null, responseIsBasic: false);
  }

  /// 防御側：固有技でレスポンスする。
  void respondWithMove(String playerId, String moveId) {
    final atk = state.pendingAttack;
    if (state.phase != LevelMatchPhase.responseSelection || atk == null) {
      throw StateError('対応できる局面ではありません');
    }
    if (atk.defenderId != playerId) throw StateError('対応できるのは防御側です');
    final defender = state.byId(playerId);
    final rawMove = moves[moveId];
    if (rawMove == null) throw StateError('技が見つかりません');
    final move = state.resourceMode == MatchResourceMode.energy
        ? rawMove.resolvedForEnergyMode
        : rawMove;
    final avail = responseAvailability(defender, move, isBasic: false);
    if (!avail.usable) throw StateError(avail.reasons.join('\n'));
    defender.moveUsageCounts[move.id] =
        (defender.moveUsageCounts[move.id] ?? 0) + 1;
    defender.previousMoveId = move.id;
    if (move.category == MoveCategory.finisher) {
      defender.finisherUsed = true;
      defender.finisherUsedTurn = state.turnNumber;
    }
    if (state.resourceMode == MatchResourceMode.energy) {
      // Ver.0.8.0：迎撃（速度勝ち）・返し技（counterカテゴリ）とも、
      // 支払ったエネルギー内訳をログへ残す（返専用エネルギーの検証用）。
      final readyBefore = Map.of(defender.readyEnergyCounts);
      final spent = _consumeEnergy(defender, move.energyModeRequiredCards);
      final readyAfter = Map.of(defender.readyEnergyCounts);
      _log(
        defender,
        'respondEnergyConsumed',
        '${move.name}で対応（${move.isCounterMove ? "返し技" : "迎撃"}）',
        {
          'moveId': move.id,
          'isCounterMove': move.isCounterMove,
          'energyCost': _attributeJson(move.energyModeRequiredCards),
          'energySpent': spent,
          'readyEnergyBefore': _attributeJson(readyBefore),
          'readyEnergyAfter': _attributeJson(readyAfter),
        },
      );
    } else {
      _consumeCost(defender, move);
    }
    _resolveExchange(response: move, responder: defender, responseIsBasic: false);
  }

  /// 防御側：単体技でレスポンスする。
  void respondWithBasic(String playerId, String cardInstanceId) {
    final atk = state.pendingAttack;
    if (state.phase != LevelMatchPhase.responseSelection || atk == null) {
      throw StateError('対応できる局面ではありません');
    }
    if (atk.defenderId != playerId) throw StateError('対応できるのは防御側です');
    // Ver.0.8.0 energyモード：単体技での対応（迎撃）も廃止。
    // 対応は固有技（同属性エネルギーでの迎撃 or 返専用エネルギーでの返し技）のみ。
    if (state.resourceMode == MatchResourceMode.energy) {
      throw StateError('エネルギーモードでは単体技で対応できません（固有技のみ）');
    }
    final defender = state.byId(playerId);
    final index = defender.hand.indexWhere(
      (c) => c.instanceId == cardInstanceId,
    );
    if (index < 0) throw StateError('手札にカードがありません');
    final attack = moves[atk.moveId];
    if (attack != null && attack.ignoreNormalSpeed) {
      throw StateError('フィニッシャーには単体技で割り込めません');
    }
    final card = defender.hand[index];
    final move = basicMoveFor(card.attribute, defender);
    if (move == null) throw StateError('この属性の単体技がありません');
    defender.hand.removeAt(index);
    defender.discardPile.add(card);
    defender.previousMoveId = move.id;
    _resolveExchange(response: move, responder: defender, responseIsBasic: true);
  }

  /// Ver.0.8.0 energyモード：技カードで対応（迎撃）する。
  /// 速い技カードなら攻撃をつぶせる。返し技として成立させたい場合は
  /// 固有の返し技（counterカテゴリ、返エネルギー要）を使うこと。
  void respondWithTechniqueCard(String playerId, String cardInstanceId) {
    final atk = state.pendingAttack;
    if (state.phase != LevelMatchPhase.responseSelection || atk == null) {
      throw StateError('対応できる局面ではありません');
    }
    if (atk.defenderId != playerId) throw StateError('対応できるのは防御側です');
    if (state.resourceMode != MatchResourceMode.energy) {
      throw StateError('技カードはエネルギーモード専用です');
    }
    final defender = state.byId(playerId);
    final index = defender.hand.indexWhere(
      (c) => c.instanceId == cardInstanceId,
    );
    if (index < 0) throw StateError('手札にカードがありません');
    final card = defender.hand[index];
    if (card.isEnergyOnly) throw StateError('これは技エネルギーカードです（技カードではありません）');
    final attack = moves[atk.moveId];
    if (attack != null && attack.ignoreNormalSpeed) {
      throw StateError('フィニッシャーには技カードで割り込めません');
    }
    final rawMove = moves[card.techniqueMoveId];
    if (rawMove == null) throw StateError('技が見つかりません');
    final move = rawMove.resolvedForEnergyMode;
    if (!canAffordEnergy(defender, move.energyModeRequiredCards)) {
      throw StateError('エネルギーが不足しているため対応できません');
    }
    defender.hand.removeAt(index);
    defender.discardPile.add(card);
    defender.previousMoveId = move.id;
    final readyBefore = Map.of(defender.readyEnergyCounts);
    final spent = _consumeEnergy(defender, move.energyModeRequiredCards);
    final readyAfter = Map.of(defender.readyEnergyCounts);
    _log(defender, 'respondEnergyConsumed', '${move.name}（技カード）で対応（迎撃）', {
      'moveId': move.id,
      'isCounterMove': move.isCounterMove,
      'energyCost': _attributeJson(move.energyModeRequiredCards),
      'energySpent': spent,
      'readyEnergyBefore': _attributeJson(readyBefore),
      'readyEnergyAfter': _attributeJson(readyAfter),
    });
    _resolveExchange(response: move, responder: defender, responseIsBasic: true);
  }

  void _resolveExchange({
    required MoveDefinition? response,
    required PlayerLevelMatchState? responder,
    required bool responseIsBasic,
  }) {
    final atk = state.pendingAttack!;
    final attacker = state.byId(atk.attackerId);
    final defender = state.byId(atk.defenderId);
    final attackMove = moves[atk.moveId]!;
    state.pendingAttack = null;
    if (response == null) {
      _land(
        winner: attacker,
        loser: defender,
        move: attackMove,
        isBasic: atk.isBasic,
        isCounter: false,
        clash: ClashOutcome.neutral,
      );
      return;
    }
    final clash = clashBetween(attackMove, response);
    final responderWins =
        clash == ClashOutcome.counter || clash == ClashOutcome.speedWin;
    _log(responder!, 'clashResolution', responderWins
        ? '${response.name}が${attackMove.name}を上回った（${clash.name}）'
        : '${attackMove.name}が${response.name}を振り切った（${clash.name}）', {
      'attackMove': attackMove.id,
      'attackSpeed': attackMove.speed,
      'responseMove': response.id,
      'responseSpeed': response.speed,
      'outcome': clash.name,
      'winner': responderWins ? responder.playerId : attacker.playerId,
    });
    if (responderWins) {
      _land(
        winner: responder,
        loser: attacker,
        move: response,
        isBasic: responseIsBasic,
        isCounter: clash == ClashOutcome.counter,
        clash: clash,
      );
    } else {
      _land(
        winner: attacker,
        loser: defender,
        move: attackMove,
        isBasic: atk.isBasic,
        isCounter: false,
        clash: clash,
      );
    }
  }

  /// 勝った側の技を成立させる（ダメージ＋決着分岐）。
  void _land({
    required PlayerLevelMatchState winner,
    required PlayerLevelMatchState loser,
    required MoveDefinition move,
    required bool isBasic,
    required bool isCounter,
    required ClashOutcome clash,
  }) {
    state.phase = LevelMatchPhase.resolveMove;
    final resistance = loser.levelCard.resistances[move.attribute] ?? 0;
    final damage = _roundDamage(move.power - resistance);
    final hpBefore = loser.currentHp;
    final heatBefore = state.sharedHeat;
    loser.currentHp = max(0, loser.currentHp - damage);
    winner.damageDealtCount++;
    loser.damageTakenCount++;
    final firstAttribute =
        (winner.attributeSuccessCounts[move.attribute] ?? 0) == 0;
    winner.attributeSuccessCounts[move.attribute] =
        (winner.attributeSuccessCounts[move.attribute] ?? 0) + 1;
    winner.levelUsedCounts[winner.currentLevel] =
        (winner.levelUsedCounts[winner.currentLevel] ?? 0) + 1;
    if (damage > 0) {
      winner.levelMoveSuccessCounts[winner.currentLevel] =
          (winner.levelMoveSuccessCounts[winner.currentLevel] ?? 0) + 1;
    }
    final fromFinisher = move.category == MoveCategory.finisher;
    var heatDelta = move.heat;
    if (isCounter) {
      heatDelta += 5;
    } else if (clash == ClashOutcome.speedWin) {
      heatDelta += 1;
    }
    if (damage > 0 && firstAttribute) heatDelta++;
    if (winner.currentHp <= 30) heatDelta++;
    if (fromFinisher) {
      heatDelta += 3;
      state.pendingAnimation = move.name;
    }
    winner
      ..lastUsedMoveId = move.id
      ..lastUsedMoveName = move.name
      ..lastUsedMoveSpeed = move.speed
      ..lastUsedWasBasic = isBasic;
    // 成立した技のみ表示。負けた側の直前技はリセット（Speedを持ち越さない）。
    loser
      ..lastUsedMoveId = null
      ..lastUsedMoveName = null
      ..lastUsedMoveSpeed = null;
    state.sharedHeat += heatDelta;
    state.lastMove = move.name;
    state.lastMoveId = move.id;
    state.lastDamage = damage;
    if (loser.currentHp <= 0 && loser.hpZeroReachedTurn == null) {
      loser.hpZeroReachedTurn = state.turnNumber;
      _log(loser, 'hpZeroReached', '${loser.wrestler.name}のHPが0に到達（試合は継続）', {
        'turn': state.turnNumber,
      });
    }
    final loserWasDown = loser.isDown;
    _log(winner, 'moveResolved', '${move.name}成立！ $damageダメージ', {
      'selectedMove': move.id,
      'basic': isBasic,
      'moveAttribute': move.attribute.name,
      'movePower': move.power,
      'targetResistance': resistance,
      'finalDamage': damage,
      'heatBefore': heatBefore,
      'heatDelta': heatDelta,
      'heatAfter': state.sharedHeat,
      'targetHpBefore': hpBefore,
      'targetHpAfter': loser.currentHp,
      'isCounter': isCounter,
      'clash': clash.name,
      'offersPin': move.offersPin && !isBasic,
      'offersSubmission': move.offersSubmission && !isBasic,
    });
    evaluateUnlocks(winner);
    evaluateUnlocks(loser);
    if (!isBasic) {
      if (move.causesCorner) loser.isCornered = true;
      if (move.causesOutside) loser.isOutside = true;
      if (move.causesDown && !loser.isDown) {
        loser.isDown = true;
        _log(loser, 'down', '${loser.wrestler.name}がダウン！', {
          'until': 'nextTurnStart',
          'nextPinBonus': 5,
        });
      }
      if (move.offersPin) {
        _beginPin(
          attacker: winner,
          defender: loser,
          move: move,
          damage: damage,
          fromFinisher: fromFinisher,
          targetWasDown: loserWasDown,
        );
        return;
      }
      if (move.offersSubmission) {
        _beginSubmission(
          attacker: winner,
          defender: loser,
          move: move,
          damage: damage,
          fromFinisher: fromFinisher,
        );
        return;
      }
    }
    endTurn();
  }

  void _beginPin({
    required PlayerLevelMatchState attacker,
    required PlayerLevelMatchState defender,
    required MoveDefinition move,
    required int damage,
    required bool fromFinisher,
    required bool targetWasDown,
  }) {
    final strength = computePinStrength(
      move: move,
      finalDamage: damage,
      targetHp: defender.currentHp,
      fromFinisher: fromFinisher,
      targetWasDown: targetWasDown,
    );
    state.pendingPin = PendingPin(
      attackerId: attacker.playerId,
      defenderId: defender.playerId,
      moveId: move.id,
      moveName: move.name,
      strength: strength,
      // Ver.0.6: フィニッシャーは固定の重いHPコスト、通常は強度基準。
      // いずれも累積ペナルティ（返すほど重い）を加算。
      hpKickOutCost:
          (fromFinisher
              ? kFinisherKickOutHpCost
              : requiredHpCostFor(strength.total)) +
          defender.kickOutPenalty,
      fromFinisher: fromFinisher,
      targetWasDown: targetWasDown,
    );
    if (move.autoPin || fromFinisher) {
      // 自動フォール／フィニッシャーは宣言を省略して即カウントへ。
      _confirmPinAttempt();
    } else {
      state.phase = LevelMatchPhase.pinDecision;
      _log(attacker, 'pinOffered', '${move.name}後、フォール可能', {
        'pinStrength': strength.total,
        'hpKickOutCost': state.pendingPin!.hpKickOutCost,
      });
    }
  }

  void _beginSubmission({
    required PlayerLevelMatchState attacker,
    required PlayerLevelMatchState defender,
    required MoveDefinition move,
    required int damage,
    required bool fromFinisher,
  }) {
    final resistance = defender.levelCard.resistances[MoveAttribute.submission] ?? 0;
    final strength = computeSubmissionStrength(
      move: move,
      finalDamage: damage,
      targetHp: defender.currentHp,
      fromFinisher: fromFinisher,
      targetSubmissionResistance: resistance,
    );
    state.pendingSubmission = PendingSubmission(
      attackerId: attacker.playerId,
      defenderId: defender.playerId,
      moveId: move.id,
      moveName: move.name,
      strength: strength,
      // Ver.0.6: 耐えるほど重くなる累積ペナルティを加算。
      hpEscapeCost:
          requiredHpCostFor(strength.total) + defender.submissionEscapePenalty,
      fromFinisher: fromFinisher,
      targetSubmissionResistance: resistance,
    );
    defender.submissionAttemptsReceived++;
    state.submissionAttemptCount++;
    state.phase = LevelMatchPhase.submissionDecision;
    _log(attacker, 'submissionAttempt', '${move.name}でギブアップ判定', {
      'submissionStrength': strength.total,
      'submissionComponents': strength.toJson(),
      'hpEscapeCost': state.pendingSubmission!.hpEscapeCost,
      'defenderOptions': _submissionOptions(defender),
    });
  }

  void skipMove(String playerId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.chooseMove) {
      throw StateError('技をスキップできません');
    }
    _log(actor, 'skipMove', '技を使用せずターン終了');
    endTurn();
  }

  /// 手札のカードから探せる単体技（属性が一致する MoveCategory.basic）。
  MoveDefinition? basicMoveFor(
    MoveAttribute attribute, [
    PlayerLevelMatchState? actor,
  ]) {
    // Ver.0.7.7: レスラー固有の通常技があれば優先（無ければ共通の通常技）。
    final ownId = actor?.wrestler.basicMoveIds[attribute];
    if (ownId != null) {
      final own = moves[ownId];
      if (own != null) return own;
    }
    // 共通の通常技（id が basic_ で始まる）を優先し、無ければ最初の該当技。
    MoveDefinition? any;
    for (final move in moves.values) {
      if (move.category == MoveCategory.basic && move.attribute == attribute) {
        if (move.id.startsWith('basic_')) return move;
        any ??= move;
      }
    }
    return any;
  }

  /// Ver.0.7.1: 手札のカードを単体技として「宣言」する（相手のレスポンス待ちへ）。
  void useBasicMove(String playerId, String cardInstanceId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.chooseMove) {
      throw StateError('技選択フェイズではありません');
    }
    // Ver.0.8.0 energyモード：無料の単体技（basic_*）は廃止。攻撃は固有技のみ。
    // 手札のカードはエネルギーゾーンへセットする専用リソースとなり、
    // 技として直接使う用途とは完全に分離される。
    if (state.resourceMode == MatchResourceMode.energy) {
      throw StateError('エネルギーモードでは単体技は使用できません（固有技のみ）');
    }
    final cardIndex = actor.hand.indexWhere(
      (item) => item.instanceId == cardInstanceId,
    );
    if (cardIndex < 0) throw StateError('手札にカードがありません');
    final card = actor.hand[cardIndex];
    final move = basicMoveFor(card.attribute, actor);
    if (move == null) throw StateError('この属性の単体技がありません');
    // 宣言＝コミット：手札から捨て札へ。
    actor.hand.removeAt(cardIndex);
    actor.discardPile.add(card);
    _declareAttack(actor, move, isBasic: true);
  }

  /// Ver.0.8.0 energyモード：技カード（手札から使用・使用後は捨て札）を攻撃として宣言する。
  /// 技エネルギーカード（isEnergyOnly）はここでは使えない。
  void useTechniqueCard(String playerId, String cardInstanceId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.chooseMove) {
      throw StateError('技選択フェイズではありません');
    }
    if (state.resourceMode != MatchResourceMode.energy) {
      throw StateError('技カードはエネルギーモード専用です');
    }
    final cardIndex = actor.hand.indexWhere(
      (item) => item.instanceId == cardInstanceId,
    );
    if (cardIndex < 0) throw StateError('手札にカードがありません');
    final card = actor.hand[cardIndex];
    if (card.isEnergyOnly) throw StateError('これは技エネルギーカードです（技カードではありません）');
    final rawMove = moves[card.techniqueMoveId];
    if (rawMove == null) throw StateError('技が見つかりません');
    final move = rawMove.resolvedForEnergyMode;
    if (!canAffordEnergy(actor, move.energyModeRequiredCards)) {
      throw StateError('エネルギーが不足しているため使用できません');
    }
    // 宣言＝コミット：手札から捨て札へ（エネルギー消費は_declareAttack内で行う）。
    actor.hand.removeAt(cardIndex);
    actor.discardPile.add(card);
    _declareAttack(actor, move, isBasic: true);
  }

  bool canAffordEnergy(PlayerLevelMatchState actor, Map<MoveAttribute, int> cost) {
    final ready = actor.readyEnergyCounts;
    for (final entry in cost.entries) {
      if ((ready[entry.key] ?? 0) < entry.value) return false;
    }
    return true;
  }

  // ===== Ver.0.5: フォール（3カウント） =====

  /// 攻撃側がフォールを宣言する。
  void declarePin(String playerId) {
    final pin = state.pendingPin;
    if (state.phase != LevelMatchPhase.pinDecision || pin == null) {
      throw StateError('フォールを宣言できる局面ではありません');
    }
    if (pin.attackerId != playerId) throw StateError('フォール宣言は攻撃側のみです');
    _confirmPinAttempt();
  }

  /// 攻撃側がフォールを見送る（試合続行、HEAT+1）。
  void declinePin(String playerId) {
    final pin = state.pendingPin;
    if (state.phase != LevelMatchPhase.pinDecision || pin == null) {
      throw StateError('フォール判断の局面ではありません');
    }
    if (pin.attackerId != playerId) throw StateError('攻撃側のみ選択できます');
    final attacker = state.byId(pin.attackerId);
    state.sharedHeat += 1;
    _log(attacker, 'pinDeclined', 'フォールせず試合を続ける（HEAT+1）', {
      'heatAfter': state.sharedHeat,
    });
    state.pendingPin = null;
    endTurn();
  }

  void _confirmPinAttempt() {
    final pin = state.pendingPin!;
    final defender = state.byId(pin.defenderId);
    final attacker = state.byId(pin.attackerId);
    defender.pinAttemptsReceived++;
    state.pinAttemptCount++;
    state.phase = LevelMatchPhase.kickOutDecision;
    _log(attacker, 'pinAttempt', '${pin.moveName}でフォール！ ONE… TWO…', {
      'pinStrength': pin.strength.total,
      'pinComponents': pin.strength.toJson(),
      'hpKickOutCost': pin.hpKickOutCost,
      'fromFinisher': pin.fromFinisher,
      'defenderOptions': _kickOutOptions(defender, pin),
    });
  }

  /// 防御側のキックアウト対応。
  void kickOut(String playerId, DefenseMethod method) {
    final pin = state.pendingPin;
    if (state.phase != LevelMatchPhase.kickOutDecision || pin == null) {
      throw StateError('キックアウトできる局面ではありません');
    }
    if (pin.defenderId != playerId) throw StateError('キックアウトは防御側のみです');
    final defender = state.byId(pin.defenderId);
    switch (method) {
      case DefenseMethod.card:
        if (defender.kickOutCards <= 0) throw StateError('キックアウトカードがありません');
        defender.kickOutCards--;
        defender.kickOutCardUsedCount++;
        final heat = kKickOutHeatGain + (pin.fromFinisher ? 2 : 0);
        state.sharedHeat += heat;
        _registerKickOut(defender, pin, method: 'card', heat: heat);
      case DefenseMethod.hp:
        if (defender.currentHp <= 0) throw StateError('HP0のためHP消費キックアウト不可');
        if (defender.currentHp < pin.hpKickOutCost) throw StateError('HPが足りません');
        defender.currentHp -= pin.hpKickOutCost;
        final heat = kKickOutHeatGain + (pin.fromFinisher ? 2 : 0);
        state.sharedHeat += heat;
        _registerKickOut(defender, pin, method: 'hp', heat: heat);
      case DefenseMethod.accept:
        _finishPin(pin);
    }
  }

  void _registerKickOut(
    PlayerLevelMatchState defender,
    PendingPin pin, {
    required String method,
    required int heat,
  }) {
    defender.kickOutCount++;
    defender.pinKickOutCount++;
    state.kickOutTotalCount++;
    // Ver.0.6: 返すほど次回のHPキックアウトが重くなる（“もう返せない”を作る）。
    final penaltyBefore = defender.kickOutPenalty;
    defender.kickOutPenalty += kKickOutPenaltyStep;
    if (pin.fromFinisher) {
      defender.finisherKickOutCount++;
      state.finisherKickOutTotalCount++;
    }
    _log(defender, 'kickOut', '${defender.wrestler.name}がキックアウト！ 2.9！', {
      'selectedKickOutMethod': method,
      'hpCost': method == 'hp' ? pin.hpKickOutCost : 0,
      'cardUsed': method == 'card',
      'kickOutSuccess': true,
      'threeCount': false,
      'fromFinisher': pin.fromFinisher,
      'heatDelta': heat,
      'heatAfter': state.sharedHeat,
      'kickOutPenaltyBefore': penaltyBefore,
      'kickOutPenaltyAfter': defender.kickOutPenalty,
      'nextHpKickOutExtra': defender.kickOutPenalty,
    });
    state.pendingPin = null;
    state.pendingAnimation = null;
    endTurn();
  }

  void _finishPin(PendingPin pin) {
    _log(state.byId(pin.defenderId), 'threeCount', 'ONE… TWO… THREE！', {
      'kickOutSuccess': false,
      'threeCount': true,
    });
    state.finishMoveId = pin.moveId;
    state.finishingMove = pin.moveName;
    state.pendingPin = null;
    _finish(state.byId(pin.attackerId), LevelFinishReason.pinfall);
  }

  // ===== Ver.0.5: ギブアップ（サブミッション） =====

  /// 防御側のギブアップ対応。card=ロープブレイク / hp=耐える / accept=ギブアップ。
  void escapeSubmission(String playerId, DefenseMethod method) {
    final sub = state.pendingSubmission;
    if (state.phase != LevelMatchPhase.submissionDecision || sub == null) {
      throw StateError('ギブアップ判定の局面ではありません');
    }
    if (sub.defenderId != playerId) throw StateError('対応できるのは防御側です');
    final defender = state.byId(sub.defenderId);
    switch (method) {
      case DefenseMethod.card:
        if (defender.ropeBreakCards <= 0) throw StateError('ロープブレイクカードがありません');
        defender.ropeBreakCards--;
        defender.ropeBreakUsedCount++;
        state.ropeBreakTotalCount++;
        state.sharedHeat += kEscapeHeatGain;
        _registerEscape(defender, sub, method: 'ropeBreak', heat: kEscapeHeatGain);
      case DefenseMethod.hp:
        if (defender.currentHp <= 0) throw StateError('HP0のためHP消費不可');
        if (defender.currentHp < sub.hpEscapeCost) throw StateError('HPが足りません');
        defender.currentHp -= sub.hpEscapeCost;
        state.sharedHeat += kEscapeHeatGain;
        _registerEscape(defender, sub, method: 'hp', heat: kEscapeHeatGain);
      case DefenseMethod.accept:
        _finishSubmission(sub);
    }
  }

  void _registerEscape(
    PlayerLevelMatchState defender,
    PendingSubmission sub, {
    required String method,
    required int heat,
  }) {
    defender.submissionEscapeCount++;
    state.submissionEscapeTotalCount++;
    // Ver.0.6: 耐えるほど次回のHP耐久が重くなる。
    final penaltyBefore = defender.submissionEscapePenalty;
    defender.submissionEscapePenalty += kEscapePenaltyStep;
    _log(defender, 'submissionEscape', '${defender.wrestler.name}が耐えた！', {
      'selectedEscapeMethod': method,
      'hpCost': method == 'hp' ? sub.hpEscapeCost : 0,
      'ropeBreakUsed': method == 'ropeBreak',
      'escapeSuccess': true,
      'submissionFinish': false,
      'heatDelta': heat,
      'heatAfter': state.sharedHeat,
      'escapePenaltyBefore': penaltyBefore,
      'escapePenaltyAfter': defender.submissionEscapePenalty,
    });
    state.pendingSubmission = null;
    endTurn();
  }

  void _finishSubmission(PendingSubmission sub) {
    _log(state.byId(sub.defenderId), 'submissionFinish', 'ギブアップ！', {
      'escapeSuccess': false,
      'submissionFinish': true,
    });
    state.finishMoveId = sub.moveId;
    state.finishingMove = sub.moveName;
    state.pendingSubmission = null;
    _finish(state.byId(sub.attackerId), LevelFinishReason.submission);
  }

  List<String> _kickOutOptions(PlayerLevelMatchState defender, PendingPin pin) => [
    if (defender.kickOutCards > 0) 'card',
    if (defender.currentHp > 0 && defender.currentHp >= pin.hpKickOutCost) 'hp',
    'accept',
  ];

  List<String> _submissionOptions(PlayerLevelMatchState defender) {
    final sub = state.pendingSubmission;
    return [
      if (defender.ropeBreakCards > 0) 'ropeBreak',
      if (sub != null &&
          defender.currentHp > 0 &&
          defender.currentHp >= sub.hpEscapeCost)
        'hp',
      'giveUp',
    ];
  }

  List<UnlockEvaluation> evaluateUnlocks(PlayerLevelMatchState actor) {
    final evaluations = <UnlockEvaluation>[];
    for (final level in actor.wrestler.levels.where(
      (item) => !actor.unlockedLevels.contains(item.level),
    )) {
      final evaluation = evaluateUnlockCondition(actor, level);
      evaluations.add(evaluation);
      if (evaluation.satisfied && evaluation.supported) {
        actor.unlockedLevels.add(level.level);
        if (level.level == 2) actor.level2UnlockedTurn = state.turnNumber;
        if (level.level == 3) actor.level3UnlockedTurn = state.turnNumber;
        state.unlockNotice = '${actor.wrestler.name} Level ${level.level} 解放！';
        _log(actor, 'unlockLevel', state.unlockNotice!, evaluation.toJson());
      } else if (!evaluation.supported) {
        _log(
          actor,
          'unlockUnsupported',
          'Level ${level.level}: 未対応の解放条件',
          evaluation.toJson(),
        );
      }
    }
    return evaluations;
  }

  UnlockEvaluation evaluateUnlockCondition(
    PlayerLevelMatchState actor,
    WrestlerLevelDefinition level,
  ) {
    final group = level.unlockCondition;
    if (level.level == 1 || group == null) {
      return UnlockEvaluation(
        level: level.level,
        satisfied: true,
        supported: true,
        details: const ['条件なし'],
      );
    }
    final values = <bool>[];
    final details = <String>[];
    var supported = true;
    for (final condition in group.conditions) {
      final result = _evaluateUnlock(condition, actor, level.level);
      values.add(result.$1);
      supported = supported && result.$2;
      // Ver.0.7.1: 各条件の成立/未成立を明示（✓/×）。
      details.add('${result.$1 ? "✓" : "×"} ${result.$3}');
    }
    final satisfied =
        values.isNotEmpty &&
        (group.operator == ConditionOperator.and
            ? values.every((value) => value)
            : values.any((value) => value));
    if (satisfied && supported && details.isNotEmpty) {
      final label = group.operator == ConditionOperator.and ? 'AND成立' : 'OR成立';
      details.insert(0, label);
    }
    return UnlockEvaluation(
      level: level.level,
      satisfied: satisfied && supported,
      supported: supported,
      details: details,
    );
  }

  PlayerLevelMatchState _opponentOf(PlayerLevelMatchState actor) =>
      actor.playerId == state.player.playerId ? state.cpu : state.player;

  /// 現在、判断すべきプレイヤーID（手番中の通常操作＋防御側としての対応）。
  /// draw/turnEnd/resolveMove 等は自動遷移のため null。
  String? decisionOwnerId() {
    if (state.isGameOver) return null;
    switch (state.phase) {
      case LevelMatchPhase.pinDecision:
        return state.pendingPin?.attackerId;
      case LevelMatchPhase.kickOutDecision:
        return state.pendingPin?.defenderId;
      case LevelMatchPhase.submissionDecision:
        return state.pendingSubmission?.defenderId;
      case LevelMatchPhase.responseSelection:
        return state.pendingAttack?.defenderId;
      case LevelMatchPhase.setCard:
      case LevelMatchPhase.levelChange:
      case LevelMatchPhase.chooseMove:
        return state.activePlayerId;
      default:
        return null;
    }
  }

  /// CPU が今すぐ判断すべき局面か。
  bool get cpuActionPending => decisionOwnerId() == 'cpu';

  /// シミュレーション用：現在の判断者に対して1手だけ自動で進める（両プレイヤー対応）。
  void autoAdvance() {
    final ownerId = decisionOwnerId();
    if (ownerId != null) _autoStepFor(state.byId(ownerId));
  }

  void runCpuTurn() {
    if (decisionOwnerId() == 'cpu') _autoStepFor(state.cpu);
  }

  void _autoStepFor(PlayerLevelMatchState actor) {
    switch (state.phase) {
      case LevelMatchPhase.pinDecision:
        _autoPinDecision(actor);
      case LevelMatchPhase.kickOutDecision:
        _autoKickOut(actor);
      case LevelMatchPhase.submissionDecision:
        _autoEscape(actor);
      case LevelMatchPhase.responseSelection:
        _autoRespond(actor);
      case LevelMatchPhase.setCard:
        _autoSetCard(actor);
      case LevelMatchPhase.levelChange:
        _autoLevelChange(actor);
      case LevelMatchPhase.chooseMove:
        _autoChooseMove(actor);
      default:
        break;
    }
  }

  /// 防御側の自動レスポンス（返し＞速度勝ち＞受ける）。
  void _autoRespond(PlayerLevelMatchState defender) {
    final atk = state.pendingAttack!;
    final attackMove = moves[atk.moveId]!;
    // 候補：使用可能な固有技＋手札の単体技。
    final signatureOptions = _currentMoves(defender)
        .where((m) => responseAvailability(defender, m, isBasic: false).usable)
        .toList();
    // Ver.0.8.0 energyモード：単体技(basic_*)は廃止。代わりに手札の技カード
    // （エネルギーで支払えるもの）を迎撃候補にする。フィニッシャーには不可。
    final isEnergyMode = state.resourceMode == MatchResourceMode.energy;
    final canInterceptFinisher = !(attackMove.ignoreNormalSpeed);
    final techniqueCards = isEnergyMode && canInterceptFinisher
        ? defender.hand
            .where((c) =>
                !c.isEnergyOnly &&
                moves[c.techniqueMoveId] != null &&
                canAffordEnergy(defender, moves[c.techniqueMoveId]!.energyModeRequiredCards))
            .toList()
        : const <TechniqueResourceCard>[];
    final basicCards = isEnergyMode
        ? const <TechniqueResourceCard>[]
        : defender.hand
            .where((c) => basicMoveFor(c.attribute, defender) != null)
            .toList();
    // 勝てるレスポンスを探す（counter を最優先）。
    MoveDefinition? bestSig;
    var bestSigScore = 0;
    for (final m in signatureOptions) {
      final clash = clashBetween(attackMove, m);
      final win = clash == ClashOutcome.counter
          ? 100
          : clash == ClashOutcome.speedWin
          ? 50
          : 0;
      final score = win + m.power;
      if (win > 0 && score > bestSigScore) {
        bestSigScore = score;
        bestSig = m;
      }
    }
    TechniqueResourceCard? bestBasic;
    var bestBasicScore = 0;
    for (final c in basicCards) {
      final m = basicMoveFor(c.attribute, defender)!;
      final clash = clashBetween(attackMove, m);
      if (clash == ClashOutcome.speedWin) {
        final score = 50 + m.power;
        if (score > bestBasicScore) {
          bestBasicScore = score;
          bestBasic = c;
        }
      }
    }
    TechniqueResourceCard? bestTechCard;
    var bestTechScore = 0;
    for (final c in techniqueCards) {
      final m = moves[c.techniqueMoveId]!;
      final clash = clashBetween(attackMove, m);
      if (clash == ClashOutcome.speedWin) {
        final score = 50 + m.power;
        if (score > bestTechScore) {
          bestTechScore = score;
          bestTechCard = c;
        }
      }
    }
    // 攻撃が決着技（強い脅威）なら、勝てる手があれば必ず出す。
    if (bestSig != null && bestSigScore >= bestBasicScore && bestSigScore >= bestTechScore) {
      _log(defender, 'cpuDecision', '返し/速度で対応: ${bestSig.name}', {});
      respondWithMove(defender.playerId, bestSig.id);
    } else if (bestTechCard != null && bestTechScore >= bestBasicScore) {
      _log(defender, 'cpuDecision', '技カードで迎撃: ${moves[bestTechCard.techniqueMoveId]!.name}', {});
      respondWithTechniqueCard(defender.playerId, bestTechCard.instanceId);
    } else if (bestBasic != null) {
      _log(defender, 'cpuDecision', '単体技で対応', {});
      respondWithBasic(defender.playerId, bestBasic.instanceId);
    } else {
      respondTake(defender.playerId);
    }
  }

  /// Ver.0.7.3: actor が今バンクを進めるべきフィニッシャー
  /// （現Levelに登録済み・未使用）。無ければ null。
  MoveDefinition? _finisherToBank(PlayerLevelMatchState actor) {
    if (actor.finisherUsed) return null;
    final id = actor.levelCard.finisherId;
    if (id == null) return null;
    final fin = moves[id];
    if (fin == null || fin.category != MoveCategory.finisher) return null;
    return fin;
  }

  /// Ver.0.7.3: いま切り札を狙うべき局面か。
  /// 序中盤は通常攻防で試合を作り、相手が弱ってきたら“決め”に切り替える。
  bool _shouldPursueFinisher(PlayerLevelMatchState actor) {
    // 現Levelに依存せず「フィニッシャーを持ち・未使用」で判定する
    // （L3へ上がる前から“狙う”意思を持てるようにする）。
    if (actor.finisherUsed) return false;
    if (_finisherLevelOf(actor) == null) return false;
    final opponent = _opponentOf(actor);
    // Ver.0.8.0: 残り1分未満なら積極的に勝負へ（時間制限ルール時）。
    if (state.isFinalMinute) return true;
    // Ver.0.7.3: “決めに行く”のを終盤に寄せる。序中盤は通常攻防で試合を作り、
    // 相手が十分削れてから切り札を狙う（試合の間延び・切り札過多を抑制）。
    return opponent.currentHp <= 40 || state.sharedHeat >= 65;
  }

  /// フィニッシャーの必須カードがまだ揃っていない（バンク継続が必要）か。
  bool _needsMoreForFinisher(PlayerLevelMatchState actor, MoveDefinition fin) {
    return _finisherCardsShort(actor, fin) > 0;
  }

  /// Ver.0.9: energyモードでの「これまでにセットした属性別枚数」。
  /// classicの actor.setAttributeCounts は actor.setCards を数えるが、
  /// energyモードではカードは setCards ではなく energyZone へ入るため、
  /// setAttributeCounts は常に0を返してしまう（CPUのAIが使うと、
  /// 「まだ何も揃っていない」と永久に誤認し続けるバグの原因になる）。
  /// Ready/Used を問わず、場に投入済みの総量を返す。
  Map<MoveAttribute, int> _investedEnergyCounts(PlayerLevelMatchState actor) {
    final map = <MoveAttribute, int>{};
    for (final e in actor.energyZone) {
      map[e.attribute] = (map[e.attribute] ?? 0) + 1;
    }
    return map;
  }

  /// フィニッシャー成立まであと何枚必要か（不足合計）。
  /// energyモードでは実際のエネルギーコスト（energyModeRequiredCards）と
  /// 投入済みエネルギー総量を基準にする（classicのrequiredCards/
  /// setAttributeCountsのままだと常に不足扱いのまま解消しない）。
  int _finisherCardsShort(PlayerLevelMatchState actor, MoveDefinition fin) {
    final isEnergy = state.resourceMode == MatchResourceMode.energy;
    final counts =
        isEnergy ? _investedEnergyCounts(actor) : actor.setAttributeCounts;
    final cost = isEnergy ? fin.energyModeRequiredCards : fin.requiredCards;
    var short = 0;
    for (final entry in cost.entries) {
      final lack = entry.value - (counts[entry.key] ?? 0);
      if (lack > 0) short += lack;
    }
    return short;
  }

  /// Ver.0.7.3: フィニッシャーが解禁されているレベル（無ければ null）。
  int? _finisherLevelOf(PlayerLevelMatchState actor) {
    for (final level in actor.wrestler.levels) {
      final id = level.finisherId;
      if (id != null && (moves[id]?.category == MoveCategory.finisher)) {
        return level.level;
      }
    }
    return null;
  }

  void _autoSetCard(PlayerLevelMatchState actor) {
    final id = actor.playerId;
    final isEnergy = state.resourceMode == MatchResourceMode.energy;
    // Ver.0.8.0 energyモード：技カードはセットできない（使用専用）ため、
    // セット候補はエネルギーカード（isEnergyOnly）に限る。
    final setable = isEnergy
        ? actor.hand.where((c) => c.isEnergyOnly).toList()
        : actor.hand;

    if (isEnergy) {
      // Ver.0.9: energyモードのCPUは実際のエネルギーコストを見て、
      // 最も不足している属性へ優先投入する（1属性に偏らせない）。
      final fin = _finisherToBank(actor);
      final Map<MoveAttribute, int> shortfalls;
      if (fin != null &&
          _shouldPursueFinisher(actor) &&
          _needsMoreForFinisher(actor, fin)) {
        final invested = _investedEnergyCounts(actor);
        shortfalls = {
          for (final entry in fin.energyModeRequiredCards.entries)
            if (entry.value > (invested[entry.key] ?? 0))
              entry.key: entry.value - (invested[entry.key] ?? 0),
        };
      } else {
        shortfalls = _desiredAttributeShortfalls(actor);
      }
      MoveAttribute? bestAttribute;
      var bestShortfall = 0;
      for (final entry in shortfalls.entries) {
        if (setable.any((c) => c.attribute == entry.key) &&
            entry.value > bestShortfall) {
          bestShortfall = entry.value;
          bestAttribute = entry.key;
        }
      }
      final card = bestAttribute != null
          ? setable.firstWhere((c) => c.attribute == bestAttribute)
          : (setable.isEmpty ? null : setable.first);
      if (card == null) {
        skipSetCard(id);
      } else {
        setTechniqueCard(id, card.instanceId);
      }
      return;
    }

    // Ver.0.7.3: フィニッシャー始動中は、不足している必須属性を最優先でバンクする。
    final fin = _finisherToBank(actor);
    final Set<MoveAttribute> desired;
    if (fin != null &&
        _shouldPursueFinisher(actor) &&
        _needsMoreForFinisher(actor, fin)) {
      final counts = actor.setAttributeCounts;
      desired = {
        for (final entry in fin.requiredCards.entries)
          if ((counts[entry.key] ?? 0) < entry.value) entry.key,
      };
    } else {
      desired = _desiredAttributes(actor);
    }
    final candidates = setable
        .where((card) => desired.contains(card.attribute))
        .toList();
    final card = candidates.isNotEmpty
        ? candidates.first
        : (setable.isEmpty ? null : setable.first);
    if (card == null) {
      skipSetCard(id);
    } else if (actor.setCards.length < 6) {
      setTechniqueCard(id, card.instanceId);
    } else {
      final removable = actor.setCards.firstWhere(
        (item) => !desired.contains(item.attribute),
        orElse: () => actor.setCards.first,
      );
      setTechniqueCard(id, card.instanceId, replaceInstanceId: removable.instanceId);
    }
  }

  void _autoLevelChange(PlayerLevelMatchState actor) {
    final id = actor.playerId;
    final options =
        actor.unlockedLevels
            .where((level) => level != actor.currentLevel)
            .toList()
          ..sort();
    // Ver.0.7.3: フィニッシャー登録レベルが解禁されたら、そこへ上がって切り札を狙う。
    // （切り札は威力・信頼性が高く、決着に直結する。多少の火力減は許容。）
    final finLevel = _finisherLevelOf(actor);
    if (finLevel != null &&
        !actor.finisherUsed &&
        _shouldPursueFinisher(actor) &&
        actor.currentLevel != finLevel &&
        actor.unlockedLevels.contains(finLevel)) {
      _log(actor, 'cpuDecision', 'フィニッシャーを狙いLevel $finLevelへ', {
        'candidates': options,
        'selectionReason': 'setupFinisher',
      });
      changeLevel(id, finLevel);
      return;
    }
    // Ver.0.9.1: 複数レベルが同時解禁された場合、火力最大のレベルへ直行すると
    // 中間レベルの固有技が一生使われないままになる（例: Level1→3の即時到達で
    // Level2固有技が完全に出番を失う）。フィニッシャーを急ぐ局面でなければ、
    // まだ滞在していない解禁済みレベルのうち、火力を落とさず経由できる
    // ものを優先して一度は立ち寄る。
    final unvisited = options.where((l) => !actor.visitedLevels.contains(l));
    if (unvisited.isNotEmpty) {
      final currentDamage = _bestDamage(actor, actor.currentLevel);
      for (final level in unvisited) {
        if (_bestDamage(actor, level) >= currentDamage) {
          _log(actor, 'cpuDecision', '未経験のLevel $levelを経由（固有技を試す）', {
            'candidates': options,
            'selectionReason': 'visitUnexploredLevel',
          });
          changeLevel(id, level);
          return;
        }
      }
    }
    int? best;
    var bestDamage = _bestDamage(actor, actor.currentLevel);
    for (final level in options) {
      final score = _bestDamage(actor, level);
      if (score > bestDamage) {
        best = level;
        bestDamage = score;
      }
    }
    if (best == null) {
      skipLevelChange(id);
    } else {
      _log(actor, 'cpuDecision', '使用可能技が増えるLevel $bestを選択', {
        'candidates': options,
        'selectionReason': 'maximumLegalDamage',
      });
      changeLevel(id, best);
    }
  }

  void _autoChooseMove(PlayerLevelMatchState actor) {
    final id = actor.playerId;
    final candidates = _currentMoves(actor)
        // 返し技は攻撃として宣言できない（canUseAsNormalMove を除く）。
        .where((move) => !move.isCounterMove || move.canUseAsNormalMove)
        .where((move) => evaluateMove(actor, move).usable)
        .toList();
    // Ver.0.7.3: フィニッシャー始動中は、必須属性カードを消費する固有技を温存し、
    // 切り札のバンクを優先する（切り札そのものは揃えば使う）。揃うまでは
    // 別属性の固有技か単体技（コスト消費なし）で攻める。
    // Ver.0.9: これはclassic（カードを恒久的に消費する方式）専用の最適化。
    // energyモードは使ってもエネルギーが恒久的に減るわけではなく自ターンで
    // 全回復するため、温存の必要が無い（温存すると逆にただ手数が減るだけ）。
    final fin = _finisherToBank(actor);
    // 切り札まで残り1枚のときだけ、必須属性を消費する固有技を温存する
    // （序中盤は通常攻防で試合を作り、停滞＝“単体技しか出せない”期間を短くする）。
    if (state.resourceMode != MatchResourceMode.energy &&
        fin != null &&
        _shouldPursueFinisher(actor) &&
        _finisherCardsShort(actor, fin) == 1) {
      final needed = <MoveAttribute>{
        for (final entry in fin.requiredCards.entries)
          if ((actor.setAttributeCounts[entry.key] ?? 0) < entry.value)
            entry.key,
      };
      candidates.removeWhere((move) {
        if (move.id == fin.id) return false;
        final cost =
            move.consumesSetCards ? move.requiredCards : move.discardAfterUse;
        return cost.keys.any(needed.contains);
      });
    }
    if (state.resourceMode == MatchResourceMode.energy) {
      // Ver.0.8.0 energyモード：固有技（無料のbasic_*は廃止）に加え、
      // 手札の技カード（techniqueMoveId付き・エネルギーで支払えるもの）も
      // 対等な選択肢として評価する。
      final techniqueOptions = <(MoveDefinition, TechniqueResourceCard)>[
        for (final card in actor.hand)
          if (!card.isEnergyOnly && moves[card.techniqueMoveId] != null)
            if (canAffordEnergy(actor, moves[card.techniqueMoveId]!.energyModeRequiredCards))
              (moves[card.techniqueMoveId]!, card),
      ];
      if (candidates.isEmpty && techniqueOptions.isEmpty) {
        _log(actor, 'cpuDecision', '使用可能な技なし', {'candidates': <String>[]});
        skipMove(id);
        return;
      }
      MoveDefinition? bestSig;
      var bestSigScore = -1 << 30;
      for (final m in candidates) {
        final s = _scoreMoveFor(actor, m);
        if (s > bestSigScore) {
          bestSigScore = s;
          bestSig = m;
        }
      }
      (MoveDefinition, TechniqueResourceCard)? bestTech;
      var bestTechScore = -1 << 30;
      for (final entry in techniqueOptions) {
        final s = _scoreMoveFor(actor, entry.$1);
        if (s > bestTechScore) {
          bestTechScore = s;
          bestTech = entry;
        }
      }
      if (bestSig != null && bestSigScore >= bestTechScore) {
        _log(actor, 'cpuDecision', '${bestSig.name}を選択（固有技）', {
          'score': bestSigScore,
          'selectionReason': 'maximumScore',
        });
        useMove(id, bestSig.id);
      } else if (bestTech != null) {
        _log(actor, 'cpuDecision', '${bestTech.$1.name}を選択（技カード）', {
          'score': bestTechScore,
          'card': bestTech.$2.instanceId,
          'selectionReason': 'maximumScore',
        });
        useTechniqueCard(id, bestTech.$2.instanceId);
      } else {
        _log(actor, 'cpuDecision', '使用可能な技なし', {'candidates': <String>[]});
        skipMove(id);
      }
      return;
    }
    if (candidates.isEmpty) {
      // Ver.0.7: 固有技が使えなければ単体技で攻める（手札があれば）。
      final basicCard = actor.hand
          .cast<TechniqueResourceCard?>()
          .firstWhere(
            (card) => basicMoveFor(card!.attribute, actor) != null,
            orElse: () => null,
          );
      if (basicCard != null) {
        _log(actor, 'cpuDecision', '単体技で攻める', {'card': basicCard.attribute.name});
        useBasicMove(id, basicCard.instanceId);
      } else {
        _log(actor, 'cpuDecision', '使用可能な技なし', {'candidates': <String>[]});
        skipMove(id);
      }
    } else {
      candidates.sort(
        (a, b) => _scoreMoveFor(actor, b).compareTo(_scoreMoveFor(actor, a)),
      );
      final selected = candidates.first;
      _log(actor, 'cpuDecision', '${selected.name}を選択', {
        'candidates': [
          for (final move in candidates)
            {'id': move.id, 'score': _scoreMoveFor(actor, move)},
        ],
        'selectionReason': selected.category == MoveCategory.finisher
            ? 'finisherAvailable'
            : (selected.offersPin
                  ? 'pinChance'
                  : selected.offersSubmission
                  ? 'submissionChance'
                  : 'maximumScore'),
      });
      useMove(id, selected.id);
    }
  }

  /// CPU の技評価値（§13）。actor 視点で相手を評価する。
  int _scoreMoveFor(PlayerLevelMatchState cpu, MoveDefinition move) {
    final opponent = _opponentOf(cpu);
    final damage = max(
      0,
      move.power - (opponent.levelCard.resistances[move.attribute] ?? 0),
    );
    var score = damage + move.heat;
    if (move.offersPin) score += 8;
    if (move.offersSubmission) score += 8;
    if (move.category == MoveCategory.finisher) {
      if (opponent.currentHp <= 20) {
        score += 30;
      } else if (opponent.currentHp <= 50) {
        score += 20;
      } else if (opponent.currentHp >= 80) {
        score += 0;
      } else {
        score += 8;
      }
    } else if (move.offersPin || move.offersSubmission) {
      // Ver.0.9.1: フィニッシャーに限らず、フォール／ギブアップを狙える技は
      // 相手が弱っているほど「決めに行く価値」が上がる。威力の低い固有技でも、
      // 終盤の決定機では十分に選ぶ理由を持たせる
      // （「残りHPが少ないなら低コスト技でも使う」という状況判断）。
      if (opponent.currentHp <= 20) {
        score += 14;
      } else if (opponent.currentHp <= 50) {
        score += 7;
      }
    }
    if (move.id == cpu.previousMoveId) score -= 5; // 同一技連続ペナルティ
    if ((cpu.moveUsageCounts[move.id] ?? 0) == 0) score += 3; // 初使用ボーナス
    if ((cpu.attributeSuccessCounts[move.attribute] ?? 0) == 0) {
      score += 3; // 初使用属性ボーナス
    }
    // 相手のキックアウトカードが尽きているならフォール技を後押し。
    if (move.offersPin && opponent.kickOutCards == 0) score += 5;
    // Ver.0.7.1: 速い固有技ほど、相手のレスポンスに潰されにくい。
    score += move.speed;
    // Ver.0.9.1: エネルギー効率（1コストあたりのダメージ）を軽く加点する。
    // 高威力・高コスト技だけが常に選ばれる偏りを緩和し、軽い技にも
    // 「コストの割に見合う」独自の勝ち筋を持たせる。
    if (state.resourceMode == MatchResourceMode.energy) {
      final totalCost = move.energyModeRequiredCards.values.fold(
        0,
        (a, b) => a + b,
      );
      if (totalCost > 0) {
        score += (damage / totalCost).round();
        // 保有エネルギーが乏しく大技を撃つ余裕が無いときほど、
        // 「今すぐ確実に出せる」軽量技を優遇する。
        final readyTotal = cpu.readyEnergyCounts.values.fold(
          0,
          (a, b) => a + b,
        );
        if (readyTotal <= totalCost + 1 && totalCost <= 2) {
          score += 3 - totalCost;
        }
      }
    }
    // Ver.0.7.2: フィニッシャーは通常技で割り込まれない“信頼できる切り札”。
    // 相手が弱っているほど期待値が高い（返し残数・HP・HEATを加味）。
    if (move.ignoreNormalSpeed) {
      score += 12;
      if (opponent.kickOutCards == 0) score += 8;
      if (state.sharedHeat >= 40) score += 4;
    }
    return score;
  }

  void _autoPinDecision(PlayerLevelMatchState attacker) {
    final pin = state.pendingPin!;
    final defender = state.byId(pin.defenderId);
    // Ver.0.6: CPUを積極化。HP70でフォール検討、40/20は確実に、
    // カード切れで返せない見込みならHP高でも仕掛ける。
    final shouldPin =
        pin.fromFinisher ||
        state.isFinalMinute || // Ver.0.8.0: 残り1分未満は必ず仕掛ける。
        defender.currentHp <= 70 ||
        (defender.kickOutCards == 0 &&
            defender.currentHp < pin.hpKickOutCost);
    _log(attacker, 'cpuDecision', shouldPin ? 'フォールを選択' : 'フォールを見送り', {
      'pinStrength': pin.strength.total,
      'defenderHp': defender.currentHp,
      'defenderKickOutCards': defender.kickOutCards,
    });
    if (shouldPin) {
      declarePin(attacker.playerId);
    } else {
      declinePin(attacker.playerId);
    }
  }

  void _autoKickOut(PlayerLevelMatchState defender) {
    final pin = state.pendingPin!;
    final canHp =
        defender.currentHp > 0 && defender.currentHp >= pin.hpKickOutCost;
    final bigCost = pin.hpKickOutCost > defender.currentHp * 0.5;
    final DefenseMethod method;
    if (defender.kickOutCards > 0 && (!canHp || bigCost)) {
      method = DefenseMethod.card;
    } else if (canHp) {
      method = DefenseMethod.hp;
    } else if (defender.kickOutCards > 0) {
      method = DefenseMethod.card;
    } else {
      method = DefenseMethod.accept;
    }
    _log(defender, 'cpuDecision', 'キックアウト対応: ${method.name}', {
      'hpKickOutCost': pin.hpKickOutCost,
      'currentHp': defender.currentHp,
      'kickOutCards': defender.kickOutCards,
    });
    kickOut(defender.playerId, method);
  }

  void _autoEscape(PlayerLevelMatchState defender) {
    final sub = state.pendingSubmission!;
    final canHp =
        defender.currentHp > 0 && defender.currentHp >= sub.hpEscapeCost;
    final DefenseMethod method;
    if (defender.ropeBreakCards > 0) {
      method = DefenseMethod.card;
    } else if (canHp) {
      method = DefenseMethod.hp;
    } else {
      method = DefenseMethod.accept;
    }
    _log(defender, 'cpuDecision', 'ギブアップ対応: ${method.name}', {
      'hpEscapeCost': sub.hpEscapeCost,
      'currentHp': defender.currentHp,
      'ropeBreakCards': defender.ropeBreakCards,
    });
    escapeSubmission(defender.playerId, method);
  }

  void endTurn() {
    if (state.isGameOver) return;
    state.phase = LevelMatchPhase.turnEnd;
    state.activePlayerId = state.activePlayerId == state.player.playerId
        ? state.cpu.playerId
        : state.player.playerId;
    state.turnNumber++;
    beginTurn();
  }

  List<MoveDefinition> currentMoves(PlayerLevelMatchState actor) =>
      _currentMoves(actor);

  PlayerLevelMatchState _requireTurn(String playerId) {
    if (state.activePlayerId != playerId) throw StateError('手番ではありません');
    return state.active;
  }

  List<MoveDefinition> _currentMoves(PlayerLevelMatchState actor) {
    final level = actor.levelCard;
    return [
      ...level.moveIds,
      if (level.counterMoveId != null) level.counterMoveId!,
      if (level.finisherId != null) level.finisherId!,
    ].map((id) => moves[id]).whereType<MoveDefinition>().toList();
  }

  /// Ver.0.7 Phase B: actor が move を出したとき、相手の前ターン技に対する解決結果。

  /// requiredPreviousState を満たすか（例: 'down'=相手ダウン中）。
  bool _meetsRequiredState(PlayerLevelMatchState actor, MoveDefinition move) {
    final required = move.requiredPreviousState;
    if (required == null || required.isEmpty) return true;
    final opponent = _opponentOf(actor);
    return switch (required) {
      'down' || 'opponentDown' => opponent.isDown,
      'cornered' || 'opponentCorner' => opponent.isCornered,
      'outside' || 'opponentOutside' => opponent.isOutside,
      'selfDown' => actor.isDown,
      // 未対応の要求状態（topRope/running/springboardReady 等）は安全側で不可。
      _ => false,
    };
  }

  Set<MoveAttribute> _desiredAttributes(PlayerLevelMatchState actor) {
    if (state.resourceMode == MatchResourceMode.energy) {
      return _desiredAttributeShortfalls(actor).keys.toSet();
    }
    final desired = <MoveAttribute>{};
    for (final level in actor.wrestler.levels) {
      if (level.level != actor.currentLevel &&
          !actor.unlockedLevels.contains(level.level)) {
        continue;
      }
      for (final id in [
        ...level.moveIds,
        if (level.finisherId != null) level.finisherId!,
      ]) {
        final move = moves[id];
        if (move == null) continue;
        for (final entry in move.requiredCards.entries) {
          if ((actor.setAttributeCounts[entry.key] ?? 0) < entry.value) {
            desired.add(entry.key);
          }
        }
      }
    }
    return desired;
  }

  /// Ver.0.9: energyモード専用。属性ごとの「まだ足りていない枚数」を返す
  /// （必要枚数は同一属性を使う技の中で最大値を採用＝その属性を賄うのに
  /// 最低限必要な投資量）。_autoSetCard から、最も不足している属性へ
  /// 優先してエネルギーを投入するために使う。
  Map<MoveAttribute, int> _desiredAttributeShortfalls(
    PlayerLevelMatchState actor,
  ) {
    final need = <MoveAttribute, int>{};
    for (final level in actor.wrestler.levels) {
      if (level.level != actor.currentLevel &&
          !actor.unlockedLevels.contains(level.level)) {
        continue;
      }
      for (final id in [
        ...level.moveIds,
        if (level.finisherId != null) level.finisherId!,
      ]) {
        final move = moves[id];
        if (move == null) continue;
        for (final entry in move.energyModeRequiredCards.entries) {
          if (entry.value <= 0) continue;
          need[entry.key] = max(need[entry.key] ?? 0, entry.value);
        }
      }
    }
    final invested = _investedEnergyCounts(actor);
    final shortfalls = <MoveAttribute, int>{};
    for (final entry in need.entries) {
      final lack = entry.value - (invested[entry.key] ?? 0);
      if (lack > 0) shortfalls[entry.key] = lack;
    }
    return shortfalls;
  }

  int _bestDamage(PlayerLevelMatchState actor, int levelNumber) {
    final level = actor.wrestler.levels.firstWhere(
      (item) => item.level == levelNumber,
    );
    final ids = [
      ...level.moveIds,
      if (level.finisherId != null) level.finisherId!,
    ];
    return ids
        .map((id) => moves[id])
        .whereType<MoveDefinition>()
        .where((move) {
          final old = actor.currentLevel;
          actor.currentLevel = levelNumber;
          final usable = evaluateMove(actor, move).usable;
          actor.currentLevel = old;
          return usable;
        })
        .fold<int>(0, (best, move) => max(best, move.power));
  }

  (bool, bool, String) _evaluateUnlock(
    UnlockCondition condition,
    PlayerLevelMatchState actor,
    int targetLevel,
  ) {
    final value = condition.value ?? 0;
    return switch (condition.type) {
      UnlockConditionType.hpAtMost => (
        actor.currentHp <= value,
        true,
        'HP ${actor.currentHp} ≤ $value',
      ),
      UnlockConditionType.hpAtLeast => (
        actor.currentHp >= value,
        true,
        'HP ${actor.currentHp} ≥ $value',
      ),
      UnlockConditionType.heatAtLeast => (
        state.sharedHeat >= value,
        true,
        'HEAT ${state.sharedHeat} ≥ $value',
      ),
      UnlockConditionType.turnAtLeast => (
        state.turnNumber >= value,
        true,
        'TURN ${state.turnNumber} ≥ $value',
      ),
      UnlockConditionType.damageGivenAtLeast => (
        actor.damageDealtCount >= value,
        true,
        '与ダメージ回数 ${actor.damageDealtCount} ≥ $value',
      ),
      UnlockConditionType.damageReceivedAtLeast => (
        actor.damageTakenCount >= value,
        true,
        '被ダメージ回数 ${actor.damageTakenCount} ≥ $value',
      ),
      UnlockConditionType.attributeSuccessAtLeast => (
        (actor.attributeSuccessCounts[condition.attribute] ?? 0) >= value,
        condition.attribute != null,
        '属性成功回数 ${(actor.attributeSuccessCounts[condition.attribute] ?? 0)} ≥ $value',
      ),
      UnlockConditionType.kickOutCountAtLeast => (
        actor.kickOutCount >= value,
        true,
        'キックアウト ${actor.kickOutCount} ≥ $value',
      ),
      UnlockConditionType.previousLevelUnlocked => (
        actor.unlockedLevels.contains(targetLevel - 1),
        true,
        '前レベル解放済み',
      ),
      // Ver.0.5: 飛び級を許容する条件群。
      UnlockConditionType.specificLevelUsedAtLeast => (
        (actor.levelUsedCounts[condition.level ?? targetLevel - 1] ?? 0) >=
            value,
        condition.level != null,
        'Lv.${condition.level}使用回数 '
            '${actor.levelUsedCounts[condition.level ?? -1] ?? 0} ≥ $value',
      ),
      UnlockConditionType.specificLevelMoveSuccessAtLeast => (
        (actor.levelMoveSuccessCounts[condition.level ?? targetLevel - 1] ??
                0) >=
            value,
        condition.level != null,
        'Lv.${condition.level}技成功 '
            '${actor.levelMoveSuccessCounts[condition.level ?? -1] ?? 0} ≥ $value',
      ),
      UnlockConditionType.currentLevelIs => (
        actor.currentLevel == value,
        true,
        '現在Level ${actor.currentLevel} == $value',
      ),
      UnlockConditionType.levelChangeCountAtLeast => (
        actor.levelChangeCount >= value,
        true,
        'レベル変更回数 ${actor.levelChangeCount} ≥ $value',
      ),
      UnlockConditionType.pinKickOutCountAtLeast => (
        actor.pinKickOutCount >= value,
        true,
        'キックアウト回数 ${actor.pinKickOutCount} ≥ $value',
      ),
      UnlockConditionType.submissionEscapeCountAtLeast => (
        actor.submissionEscapeCount >= value,
        true,
        'ギブアップ回避 ${actor.submissionEscapeCount} ≥ $value',
      ),
      UnlockConditionType.finisherKickOutCountAtLeast => (
        actor.finisherKickOutCount >= value,
        true,
        'フィニッシャー返し ${actor.finisherKickOutCount} ≥ $value',
      ),
      UnlockConditionType.bleeding => (false, false, '流血状態は未対応'),
      UnlockConditionType.eventOccurred => (false, false, 'イベント条件は未対応'),
    };
  }

  bool _isSupportedMoveCondition(String type) => {
    'levelIs',
    'levelEquals',
    'levelAtLeast',
    'heatAtLeast',
    'selfHpAtMost',
    'selfHpAtLeast',
    'opponentHpAtMost',
    'previousLevelUnlocked',
    'requiredCardsSet',
    'finisherUnused',
    'unusedThisMatch',
  }.contains(type);

  bool _evaluateMoveCondition(
    RuleCondition condition,
    PlayerLevelMatchState actor,
  ) {
    final value = condition.value ?? 0;
    return switch (condition.type) {
      'levelIs' || 'levelEquals' => actor.currentLevel == value,
      'levelAtLeast' => actor.currentLevel >= value,
      'heatAtLeast' => state.sharedHeat >= value,
      'selfHpAtMost' => actor.currentHp <= value,
      'selfHpAtLeast' => actor.currentHp >= value,
      'opponentHpAtMost' => state.defender.currentHp <= value,
      'previousLevelUnlocked' => actor.unlockedLevels.contains(
        actor.currentLevel - 1,
      ),
      'requiredCardsSet' => true,
      'finisherUnused' || 'unusedThisMatch' => !actor.finisherUsed,
      _ => false,
    };
  }

  List<TechniqueResourceCard> _discardSetCards(
    PlayerLevelMatchState actor,
    Map<MoveAttribute, int> costs,
  ) {
    final discarded = <TechniqueResourceCard>[];
    for (final entry in costs.entries) {
      for (var i = 0; i < entry.value; i++) {
        final index = actor.setCards.indexWhere(
          (item) => item.attribute == entry.key,
        );
        if (index < 0) break;
        final card = actor.setCards.removeAt(index);
        actor.discardPile.add(card);
        discarded.add(card);
      }
    }
    return discarded;
  }

  /// Ver.0.9: 時間切れ＝引き分け。3カウント／ギブアップ以外では勝敗をつけない。
  void _timeUpDraw() {
    final p = state.player, c = state.cpu;
    state.finishingMove = '時間切れ';
    _log(p, 'timeOver', '時間切れ！ 決着つかず引き分け', {
      'playerHp': p.currentHp,
      'cpuHp': c.currentHp,
    });
    _finishDraw(LevelFinishReason.draw);
  }

  void _finish(PlayerLevelMatchState winner, LevelFinishReason reason) {
    state.winnerId = winner.playerId;
    state.finishReason = reason;
    state.finishedAt = DateTime.now().toUtc();
    state.phase = LevelMatchPhase.gameOver;
    _log(winner, 'gameOver', '${winner.wrestler.name}の勝利', {
      'finishReason': reason.name,
      'finishingMove': state.finishingMove ?? state.lastMove,
      'finishMoveId': state.finishMoveId ?? state.lastMoveId,
    });
  }

  /// Ver.0.9: 引き分け決着（時間切れ・消耗打ち切り）。勝者を立てない。
  void _finishDraw(LevelFinishReason reason) {
    state.winnerId = null;
    state.finishReason = reason;
    state.finishedAt = DateTime.now().toUtc();
    state.phase = LevelMatchPhase.gameOver;
    _log(state.player, 'gameOver', '引き分け', {
      'finishReason': reason.name,
      'finishingMove': state.finishingMove ?? state.lastMove,
      'finishMoveId': state.finishMoveId ?? state.lastMoveId,
    });
  }

  void _log(
    PlayerLevelMatchState actor,
    String action,
    String message, [
    Map<String, dynamic> details = const {},
  ]) {
    state.logs.add(
      LevelMatchLogEntry(
        turn: state.turnNumber,
        playerId: actor.playerId,
        phase: state.phase.name,
        action: action,
        message: message,
        details: details,
      ),
    );
  }
}

Map<String, int> _attributeJson(Map<MoveAttribute, int> source) => {
  for (final entry in source.entries) entry.key.name: entry.value,
};

class LevelMatchHistoryStore {
  static const key = 'one_night_match_level_history_v04';
  Future<List<Map<String, dynamic>>> load() async {
    final values =
        (await SharedPreferences.getInstance()).getStringList(key) ?? [];
    final result = <Map<String, dynamic>>[];
    for (final value in values) {
      try {
        result.add(Map<String, dynamic>.from(jsonDecode(value) as Map));
      } on Object {
        // Skip one corrupt record without losing the remaining history.
      }
    }
    return result;
  }

  Future<void> save(LevelMatchState state) async {
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(key) ?? <String>[];
    if (values.any((item) => item.contains(state.gameId))) return;
    values.add(jsonEncode(state.toJson()));
    if (values.length > 100) values.removeRange(0, values.length - 100);
    await preferences.setStringList(key, values);
  }
}

class LevelMatchAnalytics {
  const LevelMatchAnalytics(this.matches);
  final List<Map<String, dynamic>> matches;
  int get totalMatches => matches.length;
  double get playerWinRate =>
      _ratio((match) => (match['game'] as Map)['winner'] == 'player');
  double get deckOutRate =>
      _ratio((match) => (match['game'] as Map)['finishReason'] == 'deckOut');
  double get averageSetReplacements {
    if (matches.isEmpty) return 0;
    var total = 0;
    for (final match in matches) {
      for (final player in (match['players'] as List).cast<Map>()) {
        total += (player['setReplacementCount'] as num?)?.toInt() ?? 0;
      }
    }
    return total / (matches.length * 2);
  }

  Map<String, double> get wrestlerWinRates {
    final played = <String, int>{};
    final wins = <String, int>{};
    for (final match in matches) {
      final game = match['game'] as Map;
      for (final player in (match['players'] as List).cast<Map>()) {
        final name = player['wrestlerName'] as String? ?? '';
        played[name] = (played[name] ?? 0) + 1;
        if (player['playerId'] == game['winner']) {
          wins[name] = (wins[name] ?? 0) + 1;
        }
      }
    }
    return {
      for (final entry in played.entries)
        entry.key: (wins[entry.key] ?? 0) / entry.value,
    };
  }

  Map<String, double> get attributeMoveUseRates {
    final counts = <String, int>{};
    var total = 0;
    for (final match in matches) {
      for (final log in (match['turns'] as List).cast<Map>()) {
        if (log['action'] != 'useMove') continue;
        final details = log['details'] as Map;
        final attribute = details['moveAttribute'] as String? ?? 'unknown';
        counts[attribute] = (counts[attribute] ?? 0) + 1;
        total++;
      }
    }
    return {
      for (final entry in counts.entries)
        entry.key: total == 0 ? 0 : entry.value / total,
    };
  }

  double averageGame(String key) => matches.isEmpty
      ? 0
      : matches
                .map((m) => ((m['game'] as Map)[key] as num?)?.toDouble() ?? 0)
                .reduce((a, b) => a + b) /
            matches.length;
  double playerMetricRate(String key) => _ratio((match) {
    final players = match['players'] as List;
    final player = players.cast<Map>().firstWhere(
      (item) => item['playerId'] == 'player',
    );
    return player[key] != null && player[key] != false;
  });
  double averagePlayerTurn(String key) {
    final values = <double>[];
    for (final match in matches) {
      final players = match['players'] as List;
      final player = players.cast<Map>().firstWhere(
        (item) => item['playerId'] == 'player',
      );
      if (player[key] is num) values.add((player[key] as num).toDouble());
    }
    return values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  }

  double _ratio(bool Function(Map<String, dynamic>) test) =>
      matches.isEmpty ? 0 : matches.where(test).length / matches.length;

  // ===== Ver.0.5 用メトリクス =====

  Map<String, dynamic> _game(Map<String, dynamic> match) =>
      Map<String, dynamic>.from(match['game'] as Map? ?? const {});
  List<Map<String, dynamic>> _players(Map<String, dynamic> match) => [
    for (final item in (match['players'] as List? ?? const []))
      Map<String, dynamic>.from(item as Map),
  ];
  int _sumGame(String key) => matches.fold<int>(
    0,
    (sum, match) => sum + ((_game(match)[key] as num?)?.toInt() ?? 0),
  );
  int _sumPlayers(String key) => matches.fold<int>(0, (sum, match) {
    return sum +
        _players(match).fold<int>(
          0,
          (inner, player) => inner + ((player[key] as num?)?.toInt() ?? 0),
        );
  });

  double get pinfallFinishRate =>
      _ratio((match) => _game(match)['finishReason'] == 'pinfall');
  double get submissionFinishRate =>
      _ratio((match) => _game(match)['finishReason'] == 'submission');
  double get finisherFinishRate => _ratio((match) {
    final game = _game(match);
    final reason = game['finishReason'];
    if (reason != 'pinfall' && reason != 'submission') return false;
    return _players(match).any(
      (player) =>
          player['playerId'] == game['winner'] &&
          player['finisherUsed'] == true,
    );
  });
  double get averagePinAttempts => averageGame('pinAttempts');
  double get averageSubmissionAttempts => averageGame('submissionAttempts');

  double get pinSuccessRate {
    final attempts = _sumGame('pinAttempts');
    if (attempts == 0) return 0;
    final successes = matches
        .where((match) => _game(match)['finishReason'] == 'pinfall')
        .length;
    return successes / attempts;
  }

  double get kickOutCardUseRate {
    final kickOuts = _sumGame('kickOuts');
    if (kickOuts == 0) return 0;
    return _sumPlayers('kickOutCardUsedCount') / kickOuts;
  }

  double get hpKickOutRate {
    final kickOuts = _sumGame('kickOuts');
    if (kickOuts == 0) return 0;
    final card = _sumPlayers('kickOutCardUsedCount');
    return (kickOuts - card) / kickOuts;
  }

  double get finisherKickOutRate {
    final kickOuts = _sumGame('kickOuts');
    if (kickOuts == 0) return 0;
    return _sumGame('finisherKickOuts') / kickOuts;
  }

  double get ropeBreakUseRate {
    final attempts = _sumGame('submissionAttempts');
    if (attempts == 0) return 0;
    return _sumGame('ropeBreaks') / attempts;
  }

  double get hpEnduranceRate {
    final escapes = _sumGame('submissionEscapes');
    if (escapes == 0) return 0;
    return (escapes - _sumGame('ropeBreaks')) / escapes;
  }

  double get averageContinueAfterHpZero {
    final samples = <int>[];
    for (final match in matches) {
      final turns = (_game(match)['turns'] as num?)?.toInt() ?? 0;
      for (final player in _players(match)) {
        final reached = (player['hpZeroReachedTurn'] as num?)?.toInt();
        if (reached != null) samples.add(max(0, turns - reached));
      }
    }
    return samples.isEmpty
        ? 0
        : samples.reduce((a, b) => a + b) / samples.length;
  }

  /// レスラー別の平均デッキ構成（属性別枚数）。
  Map<String, Map<String, double>> get deckCompositionByWrestler {
    final totals = <String, Map<String, int>>{};
    final counts = <String, int>{};
    for (final match in matches) {
      for (final player in _players(match)) {
        final deck = player['deck'];
        if (deck is! Map) continue;
        final name = player['wrestlerName'] as String? ?? '';
        final attributeCounts = Map<String, dynamic>.from(
          deck['counts'] as Map? ?? const {},
        );
        final target = totals.putIfAbsent(name, () => {});
        attributeCounts.forEach((key, value) {
          target[key] = (target[key] ?? 0) + ((value as num?)?.toInt() ?? 0);
        });
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    return {
      for (final entry in totals.entries)
        entry.key: {
          for (final attribute in entry.value.entries)
            attribute.key: attribute.value / (counts[entry.key] ?? 1),
        },
    };
  }

  /// 一度も参照されない属性が入っていた割合（不要カード率）。
  double get unusedCardRate {
    var unused = 0;
    var total = 0;
    for (final match in matches) {
      for (final player in _players(match)) {
        final deck = player['deck'];
        if (deck is! Map) continue;
        final used = ((deck['usedAttributes'] as List?) ?? const [])
            .map((item) => item.toString())
            .toSet();
        final counts = Map<String, dynamic>.from(
          deck['counts'] as Map? ?? const {},
        );
        counts.forEach((key, value) {
          final n = (value as num?)?.toInt() ?? 0;
          total += n;
          if (!used.contains(key)) unused += n;
        });
      }
    }
    return total == 0 ? 0 : unused / total;
  }
}
