import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/game.dart';

void main() {
  final catalog = GameCatalog.standard();

  test('属性有利は攻撃力差2以内なら返せる', () {
    final engine = MatchEngine(
      FighterState(catalog.wrestlers[0], catalog.deckFor(catalog.wrestlers[0])),
      FighterState(catalog.wrestlers[1], catalog.deckFor(catalog.wrestlers[1])),
      random: Random(1),
    )..start();
    const strike = Technique('a', '打撃', Attribute.strike, 4, 1);
    const throwMove = Technique('b', '投げ', Attribute.throwMove, 2, 1);
    engine.player.hand.add(strike);
    engine.play(engine.player, strike);
    expect(engine.canCounter(engine.cpu, throwMove), isTrue);
  });

  test('技を返さないと最低1ダメージを受ける', () {
    final engine = MatchEngine(
      FighterState(catalog.wrestlers[0], catalog.deckFor(catalog.wrestlers[0])),
      FighterState(catalog.wrestlers[1], catalog.deckFor(catalog.wrestlers[1])),
      random: Random(1),
    )..start();
    final card = engine.player.hand.first;
    final before = engine.cpu.hp;
    engine.play(engine.player, card);
    engine.declineResponse();
    expect(engine.cpu.hp, lessThan(before));
    expect(engine.phase, MatchPhase.followUp);
  });

  test('HPキックアウトはHPが1以上残る場合だけ可能', () {
    final engine = MatchEngine(
      FighterState(catalog.wrestlers[0], catalog.deckFor(catalog.wrestlers[0])),
      FighterState(catalog.wrestlers[1], catalog.deckFor(catalog.wrestlers[1])),
    );
    engine.cpu.hp = 3;
    engine.lastDamage = 2;
    expect(engine.canHpKickOut, isTrue);
    engine.cpu.hp = 2;
    expect(engine.canHpKickOut, isFalse);
  });
}
