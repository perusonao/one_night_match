import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/game.dart';

void main() {
  final catalog = GameCatalog.standard();

  MatchEngine engine() => MatchEngine(
    FighterState(
      catalog.wrestlers[0],
      catalog.deckFor(catalog.wrestlers[0]),
      random: Random(1),
    ),
    FighterState(
      catalog.wrestlers[1],
      catalog.deckFor(catalog.wrestlers[1]),
      random: Random(2),
    ),
    random: Random(1),
  )..start();

  test('属性有利は攻撃力差2以内なら返せる', () {
    final match = engine();
    const strike = Technique('a', '打撃', Attribute.strike, 4, 1);
    const throwMove = Technique('b', '投げ', Attribute.throwMove, 2, 1);
    match.player.hand.add(strike);
    match.cpu.hand.add(throwMove);
    match.play(match.player, strike);
    expect(match.canCounter(match.cpu, throwMove), isTrue);
  });

  test('使用不可理由を返す', () {
    final match = engine();
    const strong = Technique('strong', '強い打撃', Attribute.strike, 8, 1);
    const weak = Technique('weak', '弱い打撃', Attribute.strike, 0, 1);
    match.player.hand.add(strong);
    match.cpu.hand.add(weak);
    match.play(match.player, strong);
    final availability = match.availability(match.cpu, weak);
    expect(availability.usable, isFalse);
    expect(availability.reason, contains('攻撃力不足'));
  });

  test('試合続行でHEAT+1かつ攻撃側が次のラリーを開始', () {
    final match = engine();
    final card = match.player.hand.first;
    match.play(match.player, card);
    match.declineResponse();
    final before = match.heat;
    match.declinePin();
    expect(match.heat, before + 1);
    expect(match.playerActive, isTrue);
    expect(match.phase, MatchPhase.main);
  });

  test('HPキックアウトはHPが1以上残る場合だけ可能', () {
    final match = engine();
    match.playerActive = true;
    match.cpu.hp = 3;
    match.lastDamage = 2;
    expect(match.canHpKickOut, isTrue);
    match.cpu.hp = 2;
    expect(match.canHpKickOut, isFalse);
  });

  test('試合JSONに分析可能な必須項目を含む', () {
    final match = engine();
    final card = match.player.hand.first;
    match.play(match.player, card);
    match.declineResponse();
    match.declarePin();
    match.acceptDefeat();
    final json = match.toJson();
    final game = json['game'] as Map<String, dynamic>;
    expect(game['version'], '0.2');
    expect(game['winner'], isNotNull);
    expect(game['finalHeat'], isA<int>());
    expect(json['players'], hasLength(2));
    expect(json['turns'], isNotEmpty);
  });
}
