import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

enum Attribute { strike, throwMove, submission, illegal }

enum MatchPhase { main, rallyResponse, followUp, kickOutDecision, gameOver }

enum FinishMethod { pin, submission, deckOut }

enum WrestlerStyle { ace, powerhouse, technician, heel }

enum CueType { heat, finisher, pin, kickOut }

class Technique {
  const Technique(
    this.id,
    this.name,
    this.attribute,
    this.basePower,
    this.heat, {
    this.description = '相手へダメージを与える技カード。',
  });

  final String id;
  final String name;
  final Attribute attribute;
  final int basePower;
  final int heat;
  final String description;
}

class Wrestler {
  const Wrestler({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.style,
    required this.maxHp,
    required this.attack,
    required this.defense,
    required this.ability,
    required this.finisher,
    required this.colors,
  });

  final String id;
  final String name;
  final String subtitle;
  final WrestlerStyle style;
  final int maxHp;
  final Map<Attribute, int> attack;
  final Map<Attribute, int> defense;
  final String ability;
  final Technique finisher;
  final List<int> colors;
}

class FighterState {
  FighterState(this.wrestler, List<Technique> deck, {Random? random})
    : hp = wrestler.maxHp,
      deck = List.of(deck),
      hand = [],
      discard = [] {
    this.deck.shuffle(random);
  }

  final Wrestler wrestler;
  int hp;
  final List<Technique> deck;
  final List<Technique> hand;
  final List<Technique> discard;
  bool finisherUsed = false;
  int damageCount = 0;
  int kickOutCount = 0;
  final Set<Attribute> damagingAttributes = {};
}

class PlayedTechnique {
  const PlayedTechnique(
    this.byPlayer,
    this.card,
    this.power, {
    this.finisher = false,
    this.advantage = false,
  });

  final bool byPlayer;
  final Technique card;
  final int power;
  final bool finisher;
  final bool advantage;
}

class GameCue {
  const GameCue(this.type, this.title, {this.detail = '', this.value = 0});

  final CueType type;
  final String title;
  final String detail;
  final int value;
}

class MatchResult {
  const MatchResult(this.playerWon, this.method, this.finishingMove);

  final bool playerWon;
  final FinishMethod method;
  final String finishingMove;
}

class MatchAction {
  MatchAction({
    required this.turn,
    required this.player,
    required this.card,
    required this.attribute,
    required this.power,
    required this.rallyCount,
    required this.timestamp,
  });

  final int turn;
  final String player;
  final String card;
  final String attribute;
  final int power;
  final int rallyCount;
  final DateTime timestamp;
  int damage = 0;
  int heatDelta = 0;
  bool pin = false;
  String? kickOutMethod;

  Map<String, dynamic> toJson() => {
    'turn': turn,
    'player': player,
    'card': card,
    'attribute': attribute,
    'power': power,
    'damage': damage,
    'heatDelta': heatDelta,
    'rallyCount': rallyCount,
    'pin': pin,
    'kickOutMethod': kickOutMethod,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}

class CardAvailability {
  const CardAvailability(this.usable, this.reason);

  final bool usable;
  final String reason;
}

class RallyGuide {
  const RallyGuide({
    required this.cardName,
    required this.attribute,
    required this.power,
    required this.directPower,
    required this.advantageAttribute,
    required this.advantageMinimumPower,
  });

  final String cardName;
  final Attribute attribute;
  final int power;
  final int directPower;
  final Attribute? advantageAttribute;
  final int advantageMinimumPower;
}

class GameCatalog {
  GameCatalog(this.wrestlers, this.cards);

  final List<Wrestler> wrestlers;
  final List<Technique> cards;

  factory GameCatalog.standard() {
    const cards = [
      Technique('elbow', 'エルボー', Attribute.strike, 1, 1),
      Technique('lariat', 'ラリアット', Attribute.strike, 3, 2),
      Technique('kick', 'ハイキック', Attribute.strike, 2, 2),
      Technique('chop', '逆水平チョップ', Attribute.strike, 1, 2),
      Technique('dropkick', 'ドロップキック', Attribute.strike, 2, 3),
      Technique('spear', 'スピアー', Attribute.strike, 4, 2),
      Technique('suplex', 'ブレーンバスター', Attribute.throwMove, 2, 2),
      Technique('backdrop', 'バックドロップ', Attribute.throwMove, 3, 2),
      Technique('bodyslam', 'ボディスラム', Attribute.throwMove, 1, 1),
      Technique('powerbomb', 'パワーボム', Attribute.throwMove, 4, 3),
      Technique('ddt', 'DDT', Attribute.throwMove, 2, 3),
      Technique('german', 'ジャーマンスープレックス', Attribute.throwMove, 3, 3),
      Technique('armbar', '腕ひしぎ逆十字', Attribute.submission, 2, 2),
      Technique('lock', '足4の字固め', Attribute.submission, 3, 3),
      Technique('clutch', 'コブラクラッチ', Attribute.submission, 2, 2),
      Technique('ankle', 'アンクルホールド', Attribute.submission, 4, 3),
      Technique('stretch', 'キャメルクラッチ', Attribute.submission, 1, 2),
      Technique('scorpion', 'サソリ固め', Attribute.submission, 3, 4),
      Technique('chair', 'パイプ椅子攻撃', Attribute.illegal, 5, -2),
      Technique('lowblow', '急所攻撃', Attribute.illegal, 4, -1),
    ];
    const dragon = Technique(
      'dragon_bomb',
      'ドラゴンボム',
      Attribute.throwMove,
      6,
      5,
      description: '渾身の投げ技。成功すると自動的にフォールへ移行する。',
    );
    const burning = Technique(
      'burning_lariat',
      'バーニングラリアット',
      Attribute.strike,
      6,
      5,
      description: '全体重を乗せた豪腕の一撃。',
    );
    const cross = Technique(
      'cross_lock',
      'シルバークロスロック',
      Attribute.submission,
      6,
      5,
      description: '複数の関節を同時に極める必殺技。',
    );
    const villain = Technique(
      'dark_driver',
      'ブラックバタフライ',
      Attribute.illegal,
      7,
      3,
      description: '観客を敵に回してでも勝利を奪う非情の一撃。',
    );
    Map<Attribute, int> stats(int s, int t, int j) => {
      Attribute.strike: s,
      Attribute.throwMove: t,
      Attribute.submission: j,
      Attribute.illegal: 0,
    };
    final wrestlers = [
      Wrestler(
        id: 'akari',
        name: '火神アカリ',
        subtitle: '太陽の正統派エース',
        style: WrestlerStyle.ace,
        maxHp: 15,
        attack: stats(4, 3, 2),
        defense: stats(3, 4, 3),
        ability: '逆境の炎：HP5以下で技が成功するとHEAT+1',
        finisher: dragon,
        colors: const [0xffef4444, 0xfff59e0b],
      ),
      Wrestler(
        id: 'misaki',
        name: '豪田ミサキ',
        subtitle: '不沈艦パワーファイター',
        style: WrestlerStyle.powerhouse,
        maxHp: 17,
        attack: stats(3, 4, 1),
        defense: stats(4, 4, 2),
        ability: '鉄壁の肉体：高いHPと投げ防御で長期戦に強い',
        finisher: burning,
        colors: const [0xff2563eb, 0xff06b6d4],
      ),
      Wrestler(
        id: 'reina',
        name: '白銀レイナ',
        subtitle: '銀盤のテクニシャン',
        style: WrestlerStyle.technician,
        maxHp: 14,
        attack: stats(2, 3, 4),
        defense: stats(3, 3, 4),
        ability: '冷静な切り返し：関節技によるラリーを得意とする',
        finisher: cross,
        colors: const [0xff8b5cf6, 0xffe879f9],
      ),
      Wrestler(
        id: 'jack',
        name: '黒蝶ジャック',
        subtitle: '反則の黒い女王',
        style: WrestlerStyle.heel,
        maxHp: 16,
        attack: stats(3, 3, 3),
        defense: stats(3, 3, 3),
        ability: '悪の華：反則技と観客のブーイングを力に変える',
        finisher: villain,
        colors: const [0xff111827, 0xffdb2777],
      ),
    ];
    return GameCatalog(wrestlers, cards);
  }

  List<Technique> deckFor(Wrestler wrestler) {
    final result = <Technique>[];
    for (var i = 0; i < 30; i++) {
      result.add(cards[(i + wrestler.id.length) % cards.length]);
    }
    return result;
  }
}

class MatchEngine {
  MatchEngine(this.player, this.cpu, {Random? random})
    : random = random ?? Random(),
      gameId = 'onm-${DateTime.now().millisecondsSinceEpoch}';

  static const version = '0.2';

  final FighterState player;
  final FighterState cpu;
  final Random random;
  final String gameId;
  MatchPhase phase = MatchPhase.main;
  bool playerActive = true;
  int turn = 1;
  int heat = 0;
  int maxRally = 0;
  int lastDamage = 0;
  bool lastWasFinisher = false;
  final List<PlayedTechnique> rally = [];
  final List<String> logs = [];
  final List<MatchAction> actions = [];
  final List<GameCue> cues = [];
  MatchResult? result;
  int pinAttempts = 0;
  int successfulPins = 0;
  int hpKickOuts = 0;
  int _lastActionIndex = -1;

  void start() {
    for (var i = 0; i < 5; i++) {
      _draw(player, true);
      _draw(cpu, false);
    }
    logs.add('試合開始！ ${player.wrestler.name} vs ${cpu.wrestler.name}');
  }

  FighterState get active => playerActive ? player : cpu;
  FighterState get defender => playerActive ? cpu : player;
  int get totalKickOuts => player.kickOutCount + cpu.kickOutCount;
  int get kickOutHpAfter => max(0, defender.hp - kickOutCost(lastDamage));

  int power(FighterState fighter, Technique card) =>
      card.basePower + (fighter.wrestler.attack[card.attribute] ?? 0);

  bool hasAdvantage(Attribute a, Attribute b) =>
      (a == Attribute.strike && b == Attribute.submission) ||
      (a == Attribute.submission && b == Attribute.throwMove) ||
      (a == Attribute.throwMove && b == Attribute.strike);

  Attribute? advantageAgainst(Attribute attribute) => switch (attribute) {
    Attribute.strike => Attribute.throwMove,
    Attribute.throwMove => Attribute.submission,
    Attribute.submission => Attribute.strike,
    Attribute.illegal => null,
  };

  CardAvailability availability(
    FighterState fighter,
    Technique card, {
    bool finisher = false,
  }) {
    if (phase != MatchPhase.main && phase != MatchPhase.rallyResponse) {
      return const CardAvailability(false, '現在は技を使用できません');
    }
    if (fighter != active) {
      return const CardAvailability(false, '相手の手番です');
    }
    if (finisher) {
      if (fighter.finisherUsed) {
        return const CardAvailability(false, 'フィニッシャーは使用済みです');
      }
      if (fighter.damageCount < 2) {
        return const CardAvailability(false, 'ダメージ成功が2回必要です');
      }
      if (heat < 8) {
        return const CardAvailability(false, 'HEATが8以上必要です');
      }
    } else if (!fighter.hand.contains(card)) {
      return const CardAvailability(false, '手札にありません');
    }
    if (rally.isEmpty) return const CardAvailability(true, '使用できます');

    final next = power(fighter, card);
    final previous = rally.last;
    if (next > previous.power) {
      return const CardAvailability(true, '実攻撃力が上回っています');
    }
    if (hasAdvantage(card.attribute, previous.card.attribute)) {
      if (previous.power - next <= 2) {
        return const CardAvailability(true, '属性有利で返せます');
      }
      return const CardAvailability(false, '攻撃力不足（属性有利でも差3以上）');
    }
    return const CardAvailability(false, '属性相性なし・攻撃力不足');
  }

  bool canCounter(FighterState fighter, Technique card) =>
      availability(fighter, card).usable;

  bool canUseFinisher(FighterState fighter) =>
      availability(fighter, fighter.wrestler.finisher, finisher: true).usable;

  RallyGuide? get rallyGuide {
    if (rally.isEmpty) return null;
    final previous = rally.last;
    return RallyGuide(
      cardName: previous.card.name,
      attribute: previous.card.attribute,
      power: previous.power,
      directPower: previous.power + 1,
      advantageAttribute: advantageAgainst(previous.card.attribute),
      advantageMinimumPower: max(0, previous.power - 2),
    );
  }

  void play(FighterState fighter, Technique card, {bool finisher = false}) {
    if (!availability(fighter, card, finisher: finisher).usable) return;
    if (finisher) {
      fighter.finisherUsed = true;
      cues.add(GameCue(CueType.finisher, card.name, detail: 'FINISHER'));
    } else {
      fighter.hand.remove(card);
    }
    final advantage =
        rally.isNotEmpty &&
        hasAdvantage(card.attribute, rally.last.card.attribute);
    rally.add(
      PlayedTechnique(
        playerActive,
        card,
        power(fighter, card),
        finisher: finisher,
        advantage: advantage,
      ),
    );
    maxRally = max(maxRally, rally.length);
    var delta = 0;
    if (advantage) {
      delta += addHeat(1, '属性有利');
    }
    actions.add(
      MatchAction(
        turn: turn,
        player: fighter.wrestler.name,
        card: card.name,
        attribute: attributeLabel(card.attribute),
        power: rally.last.power,
        rallyCount: rally.length,
        timestamp: DateTime.now(),
      )..heatDelta = delta,
    );
    _lastActionIndex = actions.length - 1;
    logs.add('${fighter.wrestler.name}が${card.name}！ (威力${rally.last.power})');
    playerActive = !playerActive;
    phase = MatchPhase.rallyResponse;
  }

  void declineResponse() {
    if (rally.isEmpty || phase != MatchPhase.rallyResponse) return;
    final hit = rally.last;
    final attacker = hit.byPlayer ? player : cpu;
    final target = hit.byPlayer ? cpu : player;
    final defense = hit.card.attribute == Attribute.illegal
        ? target.wrestler.defense.values.reduce(min)
        : target.wrestler.defense[hit.card.attribute]!;
    lastDamage = max(1, hit.power - defense);
    target.hp = max(0, target.hp - lastDamage);
    attacker.damageCount++;
    final newAttribute = attacker.damagingAttributes.add(hit.card.attribute);
    var delta = addHeat(hit.card.heat, '${hit.card.name}成功');
    if (rally.length >= 4) delta += addHeat(2, '長いラリー');
    if (attacker.hp <= 3) delta += addHeat(1, '逆境の一撃');
    if (newAttribute &&
        {
          Attribute.strike,
          Attribute.throwMove,
          Attribute.submission,
        }.every(attacker.damagingAttributes.contains)) {
      delta += addHeat(3, '3属性制覇');
    }
    lastWasFinisher = hit.finisher;
    if (_lastActionIndex >= 0) {
      actions[_lastActionIndex]
        ..damage = lastDamage
        ..heatDelta += delta;
    }
    logs.add('${hit.card.name}が決まり、${target.wrestler.name}に$lastDamageダメージ');
    for (final played in rally) {
      if (!played.finisher) {
        (played.byPlayer ? player : cpu).discard.add(played.card);
      }
    }
    rally.clear();
    playerActive = hit.byPlayer;
    phase = MatchPhase.followUp;
  }

  int addHeat(int value, String reason) {
    if (value == 0) return 0;
    heat += value;
    cues.add(GameCue(CueType.heat, reason, value: value));
    return value;
  }

  void declinePin() {
    if (phase != MatchPhase.followUp) return;
    addHeat(1, '試合続行');
    logs.add('${active.wrestler.name}はフォールせずHEATを高める');
    turn++;
    phase = MatchPhase.main;
    _draw(active, playerActive);
  }

  void declarePin() {
    if (phase != MatchPhase.followUp) return;
    pinAttempts++;
    if (_lastActionIndex >= 0) actions[_lastActionIndex].pin = true;
    logs.add('${active.wrestler.name}がフォール！');
    cues.add(const GameCue(CueType.pin, 'ONE  TWO  THREE'));
    phase = MatchPhase.kickOutDecision;
  }

  bool get canHpKickOut => defender.hp - kickOutCost(lastDamage) >= 1;
  bool get hasKickOutCard => defender.hand.length >= 3;

  int kickOutCost(int damage) => damage <= 2
      ? 2
      : damage <= 4
      ? 3
      : damage <= 6
      ? 4
      : 5;

  void kickOut({required bool withCard}) {
    if (phase != MatchPhase.kickOutDecision) return;
    String method;
    if (withCard && hasKickOutCard) {
      final card = defender.hand.removeAt(0);
      defender.discard.add(card);
      method = 'card';
    } else if (!withCard && canHpKickOut) {
      defender.hp -= kickOutCost(lastDamage);
      hpKickOuts++;
      method = 'hp';
    } else {
      acceptDefeat();
      return;
    }
    defender.kickOutCount++;
    final delta = addHeat(lastWasFinisher ? 4 : 2, 'キックアウト');
    if (_lastActionIndex >= 0) {
      actions[_lastActionIndex]
        ..kickOutMethod = method
        ..heatDelta += delta;
    }
    logs.add('${defender.wrestler.name}がキックアウト！');
    cues.add(
      GameCue(
        CueType.kickOut,
        '2.9！',
        detail: method == 'card' ? 'カードキックアウト' : 'HPキックアウト',
      ),
    );
    endTurn();
  }

  void acceptDefeat() {
    successfulPins++;
    final finishingMove = _lastActionIndex >= 0
        ? actions[_lastActionIndex].card
        : 'フォール';
    result = MatchResult(playerActive, FinishMethod.pin, finishingMove);
    phase = MatchPhase.gameOver;
    logs.add('3カウント！ ${active.wrestler.name}の勝利');
  }

  void endTurn() {
    while (active.hand.length > 7) {
      active.discard.add(active.hand.removeLast());
    }
    playerActive = !playerActive;
    turn++;
    phase = MatchPhase.main;
    _draw(active, playerActive);
  }

  void cpuStep() {
    if (phase == MatchPhase.main || phase == MatchPhase.rallyResponse) {
      final fighter = active;
      if (canUseFinisher(fighter)) {
        play(fighter, fighter.wrestler.finisher, finisher: true);
        return;
      }
      final valid = fighter.hand
          .where((card) => availability(fighter, card).usable)
          .toList();
      if (valid.isEmpty) {
        declineResponse();
      } else {
        valid.sort((a, b) => power(fighter, a).compareTo(power(fighter, b)));
        play(fighter, valid.first);
      }
    } else if (phase == MatchPhase.followUp) {
      declarePin();
    } else if (phase == MatchPhase.kickOutDecision) {
      if (hasKickOutCard) {
        kickOut(withCard: true);
      } else if (canHpKickOut) {
        kickOut(withCard: false);
      } else {
        acceptDefeat();
      }
    }
  }

  void _draw(FighterState fighter, bool isPlayer) {
    if (fighter.deck.isEmpty) {
      if (turn > 1 && result == null) {
        result = MatchResult(!isPlayer, FinishMethod.deckOut, '山札切れ');
        phase = MatchPhase.gameOver;
      }
      return;
    }
    fighter.hand.add(fighter.deck.removeLast());
  }

  String get rank => heat >= 30
      ? 'S'
      : heat >= 20
      ? 'A'
      : heat >= 10
      ? 'B'
      : heat >= 1
      ? 'C'
      : 'D';

  String get matchTitle {
    if (heat >= 30) return '今夜のベストバウト！';
    if (maxRally >= 6) return '激闘！';
    if (actions.map((e) => e.attribute).toSet().length >= 3) return '技巧戦！';
    if (totalKickOuts == 0) return '完全決着！';
    return '魂の一戦！';
  }

  Map<String, dynamic> toJson() {
    final matchResult = result;
    return {
      'game': {
        'gameId': gameId,
        'version': version,
        'winner': matchResult == null
            ? null
            : (matchResult.playerWon
                  ? player.wrestler.name
                  : cpu.wrestler.name),
        'finishType': matchResult?.method.name,
        'finishingMove': matchResult?.finishingMove,
        'turns': turn,
        'maxRally': maxRally,
        'finalHeat': heat,
        'rank': rank,
        'title': matchTitle,
        'pinAttempts': pinAttempts,
        'successfulPins': successfulPins,
        'hpKickOuts': hpKickOuts,
      },
      'players': [_fighterJson(player, 'player'), _fighterJson(cpu, 'cpu')],
      'turns': actions.map((action) => action.toJson()).toList(),
    };
  }

  Map<String, dynamic> _fighterJson(FighterState fighter, String id) => {
    'id': id,
    'wrestler': fighter.wrestler.name,
    'finalHp': fighter.hp,
    'kickOutCount': fighter.kickOutCount,
    'finisherUsed': fighter.finisherUsed,
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class MatchAnalytics {
  MatchAnalytics(this.matches);

  final List<Map<String, dynamic>> matches;

  int get totalMatches => matches.length;

  double get playerWinRate {
    if (matches.isEmpty) return 0;
    final wins = matches.where((match) {
      final game = match['game'] as Map<String, dynamic>;
      final players = match['players'] as List<dynamic>;
      return game['winner'] ==
          (players.first as Map<String, dynamic>)['wrestler'];
    }).length;
    return wins / matches.length;
  }

  double averageOf(String key) {
    if (matches.isEmpty) return 0;
    final total = matches.fold<num>(
      0,
      (sum, match) =>
          sum + ((match['game'] as Map<String, dynamic>)[key] as num? ?? 0),
    );
    return total / matches.length;
  }

  double get averageRally => averageOf('maxRally');

  double get finisherUseRate {
    if (matches.isEmpty) return 0;
    final used = matches.where((match) {
      final players = match['players'] as List<dynamic>;
      return players.any(
        (item) => (item as Map<String, dynamic>)['finisherUsed'] == true,
      );
    }).length;
    return used / matches.length;
  }

  double get pinSuccessRate {
    final attempts = matches.fold<num>(
      0,
      (sum, match) =>
          sum +
          ((match['game'] as Map<String, dynamic>)['pinAttempts'] as num? ?? 0),
    );
    if (attempts == 0) return 0;
    final successes = matches.fold<num>(
      0,
      (sum, match) =>
          sum +
          ((match['game'] as Map<String, dynamic>)['successfulPins'] as num? ??
              0),
    );
    return successes / attempts;
  }

  double get hpKickOutRate {
    final kickOuts = matches.fold<num>(0, (sum, match) {
      final players = match['players'] as List<dynamic>;
      return sum +
          players.fold<num>(
            0,
            (playerSum, item) =>
                playerSum +
                ((item as Map<String, dynamic>)['kickOutCount'] as num? ?? 0),
          );
    });
    if (kickOuts == 0) return 0;
    final hp = matches.fold<num>(
      0,
      (sum, match) =>
          sum +
          ((match['game'] as Map<String, dynamic>)['hpKickOuts'] as num? ?? 0),
    );
    return hp / kickOuts;
  }

  Map<String, double> get wrestlerWinRates {
    final played = <String, int>{};
    final won = <String, int>{};
    for (final match in matches) {
      final game = match['game'] as Map<String, dynamic>;
      final players = match['players'] as List<dynamic>;
      for (final item in players) {
        final name = (item as Map<String, dynamic>)['wrestler'] as String;
        played[name] = (played[name] ?? 0) + 1;
        if (game['winner'] == name) won[name] = (won[name] ?? 0) + 1;
      }
    }
    return {
      for (final entry in played.entries)
        entry.key: (won[entry.key] ?? 0) / entry.value,
    };
  }
}

class MatchHistoryStore {
  static const _key = 'one_night_match_history_v02';

  Future<List<Map<String, dynamic>>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_key) ?? [])
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();
  }

  Future<void> save(MatchEngine engine) async {
    final preferences = await SharedPreferences.getInstance();
    final history = preferences.getStringList(_key) ?? <String>[];
    if (history.any((item) => item.contains('"${engine.gameId}"'))) return;
    history.add(jsonEncode(engine.toJson()));
    if (history.length > 100) history.removeAt(0);
    await preferences.setStringList(_key, history);
  }
}

String attributeLabel(Attribute value) => switch (value) {
  Attribute.strike => '打撃',
  Attribute.throwMove => '投げ',
  Attribute.submission => '関節',
  Attribute.illegal => '反則',
};

String styleLabel(WrestlerStyle value) => switch (value) {
  WrestlerStyle.ace => '正統派エース',
  WrestlerStyle.powerhouse => 'パワーファイター',
  WrestlerStyle.technician => 'テクニシャン',
  WrestlerStyle.heel => 'ヒール',
};
