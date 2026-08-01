import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../wrestler_editor/models.dart';

enum LevelMatchPhase {
  setup,
  draw,
  setCard,
  unlockCheck,
  levelChange,
  chooseMove,
  resolveMove,
  turnEnd,
  gameOver,
}

enum LevelFinishReason { hpZero, deckOut }

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
  final String version = '0.4';
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
  int lastDamage = 0;
  String? unlockNotice;
  final DateTime startedAt;
  DateTime? finishedAt;

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
      'turns': turnNumber,
      'finalHeat': sharedHeat,
      'lastMove': lastMove,
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

  static LevelMatchEngine create({
    required WrestlerDefinition playerWrestler,
    required WrestlerDefinition cpuWrestler,
    required Map<String, MoveDefinition> moves,
    Random? random,
    bool playerStarts = true,
  }) {
    final rng = random ?? Random();
    final playerDeck = buildDeck('player')..shuffle(rng);
    final cpuDeck = buildDeck('cpu')..shuffle(rng);
    final player = PlayerLevelMatchState(
      playerId: 'player',
      wrestler: playerWrestler,
      currentHp: playerWrestler.maxHp,
      deck: playerDeck,
      hand: [],
    );
    final cpu = PlayerLevelMatchState(
      playerId: 'cpu',
      wrestler: cpuWrestler,
      currentHp: cpuWrestler.maxHp,
      deck: cpuDeck,
      hand: [],
    );
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
    return LevelMatchEngine(state: state, moves: moves, random: rng)
      ..beginTurn();
  }

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
    state.phase = LevelMatchPhase.draw;
    _log(actor, 'turnStart', '${actor.wrestler.name}のターン開始');
    evaluateUnlocks(actor);
    if (actor.deck.isEmpty) {
      _finish(state.defender, LevelFinishReason.deckOut);
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
    _log(actor, 'changeLevel', 'Level $before → Level $targetLevel', {
      'levelBefore': before,
      'levelAfter': targetLevel,
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
    if (move.category == MoveCategory.counter) {
      reasons.add('返し技判定はVer.0.4未対応です');
    }
    if (move.category == MoveCategory.finisher && actor.finisherUsed) {
      reasons.add('フィニッシャーは使用済みです');
    }
    if (move.usageLimit != null &&
        (actor.moveUsageCounts[move.id] ?? 0) >= move.usageLimit!) {
      reasons.add('使用回数制限に達しています');
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

  void useMove(String playerId, String moveId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.chooseMove) {
      throw StateError('技選択フェイズではありません');
    }
    final move = moves[moveId];
    if (move == null) throw StateError('技が見つかりません');
    final availability = evaluateMove(actor, move);
    if (!availability.usable) throw StateError(availability.reasons.join('\n'));
    final target = state.defender;
    state.phase = LevelMatchPhase.resolveMove;
    final resistance = target.levelCard.resistances[move.attribute] ?? 0;
    final damage = max(0, move.power - resistance);
    final hpBefore = target.currentHp;
    final heatBefore = state.sharedHeat;
    target.currentHp = max(0, target.currentHp - damage);
    actor.damageDealtCount++;
    target.damageTakenCount++;
    final firstAttribute =
        (actor.attributeSuccessCounts[move.attribute] ?? 0) == 0;
    actor.attributeSuccessCounts[move.attribute] =
        (actor.attributeSuccessCounts[move.attribute] ?? 0) + 1;
    actor.moveUsageCounts[move.id] = (actor.moveUsageCounts[move.id] ?? 0) + 1;
    var heatDelta = move.heat;
    if (damage > 0 && firstAttribute) heatDelta++;
    if (actor.currentHp <= 30) heatDelta++;
    if (move.category == MoveCategory.finisher) {
      heatDelta += 3;
      actor.finisherUsed = true;
      actor.finisherUsedTurn = state.turnNumber;
      state.pendingAnimation = move.name;
    }
    final discarded = _discardSetCards(actor, move.discardAfterUse);
    state.sharedHeat += heatDelta;
    state.lastMove = move.name;
    state.lastDamage = damage;
    _log(actor, 'useMove', '${move.name}！ $damageダメージ', {
      'selectedMove': move.id,
      'moveAttribute': move.attribute.name,
      'movePower': move.power,
      'targetResistance': resistance,
      'finalDamage': damage,
      'heatBefore': heatBefore,
      'heatDelta': heatDelta,
      'heatAfter': state.sharedHeat,
      'discardedSetCards': discarded.map((item) => item.toJson()).toList(),
      'targetHpBefore': hpBefore,
      'targetHpAfter': target.currentHp,
      'additionalChecks': move.additionalChecks
          .map((item) => item.name)
          .toList(),
    });
    evaluateUnlocks(actor);
    evaluateUnlocks(target);
    if (target.currentHp <= 0) {
      _finish(actor, LevelFinishReason.hpZero);
      return;
    }
    endTurn();
  }

  void skipMove(String playerId) {
    final actor = _requireTurn(playerId);
    if (state.phase != LevelMatchPhase.chooseMove) {
      throw StateError('技をスキップできません');
    }
    _log(actor, 'skipMove', '技を使用せずターン終了');
    endTurn();
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
      details.add(result.$3);
    }
    final satisfied =
        values.isNotEmpty &&
        (group.operator == ConditionOperator.and
            ? values.every((value) => value)
            : values.any((value) => value));
    return UnlockEvaluation(
      level: level.level,
      satisfied: satisfied && supported,
      supported: supported,
      details: details,
    );
  }

  void runCpuTurn() {
    if (state.isGameOver || state.activePlayerId != 'cpu') return;
    final cpu = state.cpu;
    if (state.phase == LevelMatchPhase.setCard) {
      final desired = _desiredAttributes(cpu);
      final candidates = cpu.hand
          .where((card) => desired.contains(card.attribute))
          .toList();
      final card = candidates.isNotEmpty
          ? candidates.first
          : (cpu.hand.isEmpty ? null : cpu.hand.first);
      if (card == null) {
        skipSetCard('cpu');
      } else if (cpu.setCards.length < 6) {
        setTechniqueCard('cpu', card.instanceId);
      } else {
        final removable = cpu.setCards.firstWhere(
          (item) => !desired.contains(item.attribute),
          orElse: () => cpu.setCards.first,
        );
        setTechniqueCard(
          'cpu',
          card.instanceId,
          replaceInstanceId: removable.instanceId,
        );
      }
    }
    if (state.phase == LevelMatchPhase.levelChange) {
      final options =
          cpu.unlockedLevels
              .where((level) => level != cpu.currentLevel)
              .toList()
            ..sort();
      int? best;
      var bestDamage = _bestDamage(cpu, cpu.currentLevel);
      for (final level in options) {
        final score = _bestDamage(cpu, level);
        if (score > bestDamage) {
          best = level;
          bestDamage = score;
        }
      }
      if (best == null) {
        skipLevelChange('cpu');
      } else {
        _log(cpu, 'cpuDecision', '使用可能技が増えるLevel $bestを選択', {
          'candidates': options,
          'selectionReason': 'maximumLegalDamage',
        });
        changeLevel('cpu', best);
      }
    }
    if (state.phase == LevelMatchPhase.chooseMove) {
      final candidates = _currentMoves(
        cpu,
      ).where((move) => evaluateMove(cpu, move).usable).toList();
      candidates.sort((a, b) {
        if (a.category == MoveCategory.finisher) return -1;
        if (b.category == MoveCategory.finisher) return 1;
        final damageA = max(
          0,
          a.power - (state.player.levelCard.resistances[a.attribute] ?? 0),
        );
        final damageB = max(
          0,
          b.power - (state.player.levelCard.resistances[b.attribute] ?? 0),
        );
        return damageB.compareTo(damageA);
      });
      if (candidates.isEmpty) {
        _log(cpu, 'cpuDecision', '使用可能な技なし', {'candidates': <String>[]});
        skipMove('cpu');
      } else {
        final selected = candidates.first;
        _log(cpu, 'cpuDecision', '${selected.name}を選択', {
          'candidates': candidates.map((item) => item.id).toList(),
          'selectionReason': selected.category == MoveCategory.finisher
              ? 'finisherAvailable'
              : 'maximumDamage',
        });
        useMove('cpu', selected.id);
      }
    }
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
}
