import 'dart:math';

enum Attribute { strike, throwMove, submission, illegal }

enum MatchPhase { main, rallyResponse, followUp, kickOutDecision, gameOver }

enum FinishMethod { pin, submission, deckOut }

class Technique {
  const Technique(
    this.id,
    this.name,
    this.attribute,
    this.basePower,
    this.satisfaction,
  );
  final String id;
  final String name;
  final Attribute attribute;
  final int basePower;
  final int satisfaction;
}

class Wrestler {
  const Wrestler({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.maxHp,
    required this.attack,
    required this.defense,
    required this.finisher,
  });
  final String id;
  final String name;
  final String subtitle;
  final int maxHp;
  final Map<Attribute, int> attack;
  final Map<Attribute, int> defense;
  final Technique finisher;
}

class FighterState {
  FighterState(this.wrestler, List<Technique> deck)
    : hp = wrestler.maxHp,
      deck = List.of(deck)..shuffle(),
      hand = [],
      discard = [];
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

class MatchResult {
  const MatchResult(this.playerWon, this.method, this.finishingMove);
  final bool playerWon;
  final FinishMethod method;
  final String finishingMove;
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
      Technique('german', 'ジャーマン', Attribute.throwMove, 3, 3),
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
    );
    const burning = Technique(
      'burning_lariat',
      '豪腕ラリアット',
      Attribute.strike,
      6,
      5,
    );
    const cross = Technique('cross_lock', 'クロスロック', Attribute.submission, 6, 5);
    const villain = Technique(
      'dark_driver',
      '暗黒ドライバー',
      Attribute.illegal,
      7,
      3,
    );
    Map<Attribute, int> stats(int s, int t, int j) => {
      Attribute.strike: s,
      Attribute.throwMove: t,
      Attribute.submission: j,
      Attribute.illegal: 0,
    };
    final wrestlers = [
      Wrestler(
        id: 'ken',
        name: '炎龍ケン',
        subtitle: '逆境の赤き龍',
        maxHp: 15,
        attack: stats(4, 3, 2),
        defense: stats(3, 4, 3),
        finisher: dragon,
      ),
      Wrestler(
        id: 'gou',
        name: '剛力ゴウ',
        subtitle: '不沈の怪力',
        maxHp: 17,
        attack: stats(3, 4, 1),
        defense: stats(4, 4, 2),
        finisher: burning,
      ),
      Wrestler(
        id: 'rei',
        name: '白銀レイ',
        subtitle: 'リングの魔術師',
        maxHp: 14,
        attack: stats(2, 3, 4),
        defense: stats(3, 3, 4),
        finisher: cross,
      ),
      Wrestler(
        id: 'jack',
        name: 'ブラック・ジャック',
        subtitle: '反則の帝王',
        maxHp: 16,
        attack: stats(3, 3, 3),
        defense: stats(3, 3, 3),
        finisher: villain,
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
    : random = random ?? Random();
  final FighterState player;
  final FighterState cpu;
  final Random random;
  MatchPhase phase = MatchPhase.main;
  bool playerActive = true;
  int turn = 1;
  int satisfaction = 0;
  int maxRally = 0;
  int lastDamage = 0;
  bool lastWasFinisher = false;
  final List<PlayedTechnique> rally = [];
  final List<String> logs = [];
  MatchResult? result;

  void start() {
    for (var i = 0; i < 5; i++) {
      _draw(player, true);
      _draw(cpu, false);
    }
    logs.add('試合開始！ ${player.wrestler.name} vs ${cpu.wrestler.name}');
  }

  FighterState get active => playerActive ? player : cpu;
  FighterState get defender => playerActive ? cpu : player;

  int power(FighterState fighter, Technique card) =>
      card.basePower + (fighter.wrestler.attack[card.attribute] ?? 0);

  bool hasAdvantage(Attribute a, Attribute b) =>
      (a == Attribute.strike && b == Attribute.submission) ||
      (a == Attribute.submission && b == Attribute.throwMove) ||
      (a == Attribute.throwMove && b == Attribute.strike);

  bool canCounter(FighterState fighter, Technique card) {
    if (rally.isEmpty) return true;
    final next = power(fighter, card);
    final previous = rally.last;
    return next > previous.power ||
        (hasAdvantage(card.attribute, previous.card.attribute) &&
            previous.power - next <= 2);
  }

  bool canUseFinisher(FighterState fighter) =>
      !fighter.finisherUsed &&
      fighter.damageCount >= 2 &&
      satisfaction >= 8 &&
      canCounter(fighter, fighter.wrestler.finisher);

  void play(FighterState fighter, Technique card, {bool finisher = false}) {
    if (phase == MatchPhase.gameOver ||
        fighter != active ||
        !canCounter(fighter, card)) {
      return;
    }
    if (finisher) {
      if (!canUseFinisher(fighter)) return;
      fighter.finisherUsed = true;
    } else {
      if (!fighter.hand.remove(card)) return;
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
    if (advantage) satisfaction += 1;
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
    satisfaction += hit.card.satisfaction;
    if (rally.length >= 4) satisfaction += 2;
    if (attacker.hp <= 3) satisfaction += 1;
    if (newAttribute &&
        {
          Attribute.strike,
          Attribute.throwMove,
          Attribute.submission,
        }.every(attacker.damagingAttributes.contains)) {
      satisfaction += 3;
    }
    lastWasFinisher = hit.finisher;
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

  void declinePin() {
    logs.add('${active.wrestler.name}はフォールせず試合を続行');
    endTurn();
  }

  void declarePin() {
    if (phase != MatchPhase.followUp) return;
    logs.add('${active.wrestler.name}がフォール！');
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
    if (withCard && hasKickOutCard) {
      final card = defender.hand.removeAt(0);
      defender.discard.add(card);
    } else if (!withCard && canHpKickOut) {
      defender.hp -= kickOutCost(lastDamage);
    } else {
      acceptDefeat();
      return;
    }
    defender.kickOutCount++;
    satisfaction += lastWasFinisher ? 4 : 2;
    logs.add('${defender.wrestler.name}がキックアウト！');
    endTurn();
  }

  void acceptDefeat() {
    final move = logs.length > 1 ? logs[logs.length - 2] : 'フォール';
    result = MatchResult(playerActive, FinishMethod.pin, move);
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

  String get rank => satisfaction >= 30
      ? 'S'
      : satisfaction >= 20
      ? 'A'
      : satisfaction >= 10
      ? 'B'
      : satisfaction >= 1
      ? 'C'
      : 'D';
}
