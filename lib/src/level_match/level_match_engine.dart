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
enum LevelFinishReason { hpZero, deckOut, pinfall, submission, exhaustion }

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
const int kKickOutPenaltyStep = 5; // キックアウト成功ごとの必要HP増加
const int kEscapePenaltyStep = 5; // ギブアップ耐久成功ごとの必要HP増加
const int kKickOutHeatGain = 5; // キックアウト成功時のHEAT
const int kEscapeHeatGain = 3; // ギブアップ耐久成功時のHEAT
const int kFinisherKickOutHpCost = 40; // フィニッシャーのHPキックアウト固定コスト
const int kExhaustionHpLoss = 5; // 疲労1ターンあたりのHP減少
const int kExhaustionHeatGain = 5; // 疲労1ターンあたりのHEAT増加
const int kMaxTurnSafetyCap = 200; // 無限試合を避ける安全弁

class TechniqueResourceCard {
  const TechniqueResourceCard(this.instanceId, this.attribute);
  final String instanceId;
  final MoveAttribute attribute;
  String get name => '${moveAttributeLabel(attribute)}カード';

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'attribute': attribute.name,
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
  final List<TechniqueResourceCard> deck;
  final List<TechniqueResourceCard> hand;
  final List<TechniqueResourceCard> discardPile = [];
  final List<TechniqueResourceCard> setCards = [];
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
  }) {
    final rng = random ?? Random();
    final playerDeckBuild = deckBuilder.build(
      wrestler: playerWrestler,
      moves: moves,
      owner: 'player',
    );
    final cpuDeckBuild = deckBuilder.build(
      wrestler: cpuWrestler,
      moves: moves,
      owner: 'cpu',
    );
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
    );
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
    if (actor.isDown) {
      actor.isDown = false;
      _log(actor, 'downRecovered', '${actor.wrestler.name}はダウンから立ち上がった');
    }
    state.phase = LevelMatchPhase.draw;
    _log(actor, 'turnStart', '${actor.wrestler.name}のターン開始');
    evaluateUnlocks(actor);

    // Ver.0.6: 無限試合を避ける安全弁（通常到達しない高ターン数）。
    if (state.turnNumber > kMaxTurnSafetyCap) {
      final winner = state.player.currentHp >= state.cpu.currentHp
          ? state.player
          : state.cpu;
      state.finishingMove = '消耗の果て';
      _finish(winner, LevelFinishReason.exhaustion);
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
    if (move.category == MoveCategory.finisher && actor.finisherUsed) {
      reasons.add('フィニッシャーは使用済みです');
    }
    if (move.usageLimit != null &&
        (actor.moveUsageCounts[move.id] ?? 0) >= move.usageLimit!) {
      reasons.add('使用回数制限に達しています');
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
    final move = moves[moveId];
    if (move == null) throw StateError('技が見つかりません');
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
    final consumed = isBasic
        ? const <TechniqueResourceCard>[]
        : _consumeCost(actor, move);
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
    if (move.isCounterMove && !move.canUseAsNormalMove) {
      // 返し技は「対応成立」する時だけ使える。
      if (clashBetween(attack, move) != ClashOutcome.counter) {
        return const MoveAvailability(false, ['この攻撃には対応できません']);
      }
    }
    if (isBasic) return const MoveAvailability(true, []);
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
    final move = moves[moveId];
    if (move == null) throw StateError('技が見つかりません');
    final avail = responseAvailability(defender, move, isBasic: false);
    if (!avail.usable) throw StateError(avail.reasons.join('\n'));
    defender.moveUsageCounts[move.id] =
        (defender.moveUsageCounts[move.id] ?? 0) + 1;
    defender.previousMoveId = move.id;
    if (move.category == MoveCategory.finisher) {
      defender.finisherUsed = true;
      defender.finisherUsedTurn = state.turnNumber;
    }
    _consumeCost(defender, move);
    _resolveExchange(response: move, responder: defender, responseIsBasic: false);
  }

  /// 防御側：単体技でレスポンスする。
  void respondWithBasic(String playerId, String cardInstanceId) {
    final atk = state.pendingAttack;
    if (state.phase != LevelMatchPhase.responseSelection || atk == null) {
      throw StateError('対応できる局面ではありません');
    }
    if (atk.defenderId != playerId) throw StateError('対応できるのは防御側です');
    final defender = state.byId(playerId);
    final index = defender.hand.indexWhere(
      (c) => c.instanceId == cardInstanceId,
    );
    if (index < 0) throw StateError('手札にカードがありません');
    final card = defender.hand[index];
    final move = basicMoveFor(card.attribute);
    if (move == null) throw StateError('この属性の単体技がありません');
    defender.hand.removeAt(index);
    defender.discardPile.add(card);
    defender.previousMoveId = move.id;
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
  MoveDefinition? basicMoveFor(MoveAttribute attribute) {
    for (final move in moves.values) {
      if (move.category == MoveCategory.basic && move.attribute == attribute) {
        return move;
      }
    }
    return null;
  }

  /// Ver.0.7.1: 手札のカードを単体技として「宣言」する（相手のレスポンス待ちへ）。
  void useBasicMove(String playerId, String cardInstanceId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.chooseMove) {
      throw StateError('技選択フェイズではありません');
    }
    final cardIndex = actor.hand.indexWhere(
      (item) => item.instanceId == cardInstanceId,
    );
    if (cardIndex < 0) throw StateError('手札にカードがありません');
    final card = actor.hand[cardIndex];
    final move = basicMoveFor(card.attribute);
    if (move == null) throw StateError('この属性の単体技がありません');
    // 宣言＝コミット：手札から捨て札へ。
    actor.hand.removeAt(cardIndex);
    actor.discardPile.add(card);
    _declareAttack(actor, move, isBasic: true);
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
    final basicCards = defender.hand
        .where((c) => basicMoveFor(c.attribute) != null)
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
      final m = basicMoveFor(c.attribute)!;
      final clash = clashBetween(attackMove, m);
      if (clash == ClashOutcome.speedWin) {
        final score = 50 + m.power;
        if (score > bestBasicScore) {
          bestBasicScore = score;
          bestBasic = c;
        }
      }
    }
    // 攻撃が決着技（強い脅威）なら、勝てる手があれば必ず出す。
    if (bestSig != null && bestSigScore >= bestBasicScore) {
      _log(defender, 'cpuDecision', '返し/速度で対応: ${bestSig.name}', {});
      respondWithMove(defender.playerId, bestSig.id);
    } else if (bestBasic != null) {
      _log(defender, 'cpuDecision', '単体技で対応', {});
      respondWithBasic(defender.playerId, bestBasic.instanceId);
    } else {
      respondTake(defender.playerId);
    }
  }

  void _autoSetCard(PlayerLevelMatchState actor) {
    final id = actor.playerId;
    final desired = _desiredAttributes(actor);
    final candidates = actor.hand
        .where((card) => desired.contains(card.attribute))
        .toList();
    final card = candidates.isNotEmpty
        ? candidates.first
        : (actor.hand.isEmpty ? null : actor.hand.first);
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
    if (candidates.isEmpty) {
      // Ver.0.7: 固有技が使えなければ単体技で攻める（手札があれば）。
      final basicCard = actor.hand
          .cast<TechniqueResourceCard?>()
          .firstWhere(
            (card) => basicMoveFor(card!.attribute) != null,
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
    return score;
  }

  void _autoPinDecision(PlayerLevelMatchState attacker) {
    final pin = state.pendingPin!;
    final defender = state.byId(pin.defenderId);
    // Ver.0.6: CPUを積極化。HP70でフォール検討、40/20は確実に、
    // カード切れで返せない見込みならHP高でも仕掛ける。
    final shouldPin =
        pin.fromFinisher ||
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
