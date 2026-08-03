import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';

void main() {
  MoveDefinition mv(String id, {int rank = 1, int deckPoints = 0}) =>
      MoveDefinition(
        id: id,
        name: id,
        category: MoveCategory.normal,
        attribute: MoveAttribute.throwMove,
        power: 20,
        heat: 2,
        requiredCards: {MoveAttribute.throwMove: 3, MoveAttribute.strike: 1},
        discardAfterUse: const {},
        rank: rank,
        deckPoints: deckPoints,
      );

  test('Ver.0.8.0: rank/deckPoints は JSON 往復で保持', () {
    final m = mv('x', rank: 4, deckPoints: 0);
    final round = MoveDefinition.fromJson(m.toJson());
    expect(round.rank, 4);
    // deckPoints 未設定はランク値。
    expect(round.displayDeckPoints, 4);
    // 明示指定は保持。
    final m2 = mv('y', rank: 3, deckPoints: 2);
    expect(MoveDefinition.fromJson(m2.toJson()).displayDeckPoints, 2);
  });

  test('Ver.0.8.0: energyCost は requiredCards から属性別に取得', () {
    final m = mv('z');
    expect(m.energyCost[MoveAttribute.throwMove], 3);
    expect(m.energyCost[MoveAttribute.strike], 1);
    expect(m.energyCost.containsKey(MoveAttribute.submission), isFalse);
  });

  test('Ver.0.8.0: deckTotalPoints が合算される', () {
    final list = [mv('a', rank: 1), mv('b', rank: 3), mv('c', rank: 5)];
    expect(deckTotalPoints(list), 1 + 3 + 5);
    expect(kDefaultDeckPointCap, 60);
  });

  test('Ver.0.8.0: 既定は rank1・deckPoints=ランク（後方互換）', () {
    final m = MoveDefinition(
      id: 'd',
      name: 'd',
      category: MoveCategory.basic,
      attribute: MoveAttribute.strike,
      power: 5,
      heat: 1,
      requiredCards: const {},
      discardAfterUse: const {},
    );
    expect(m.rank, 1);
    expect(m.displayDeckPoints, 1);
    expect(m.toJson().containsKey('rank'), isFalse); // 既定は書き出さない
  });
}
