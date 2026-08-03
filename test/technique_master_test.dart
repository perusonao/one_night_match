import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:one_night_match/src/wrestler_editor/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  MoveDefinition newMove(String id, {MoveCategory c = MoveCategory.normal}) =>
      MoveDefinition(
        id: id,
        name: id,
        category: c,
        attribute: MoveAttribute.strike,
        power: 10,
        heat: 1,
        requiredCards: {for (final v in MoveAttribute.values) v: 0},
        discardAfterUse: {for (final v in MoveAttribute.values) v: 0},
      );

  test('技マスタCRUD：保存・使用数・削除', () async {
    final repo = LocalWrestlerRepository();
    await repo.loadAll(); // seed defaults
    await repo.saveMove(newMove('custom_tech'));
    expect(repo.moves['custom_tech'], isNotNull);
    // 未使用なら削除可能。
    expect(await repo.moveUsageCount('custom_tech'), 0);
    await repo.deleteMove('custom_tech');
    expect(repo.moves['custom_tech'], isNull);
    // 使用中の技は削除不可（アカリの固有技）。
    expect(await repo.moveUsageCount('akari_dropkick'), greaterThan(0));
    await expectLater(
        repo.deleteMove('akari_dropkick'), throwsA(isA<StateError>()));
  });

  test('MoveDefinition.extra はJSON往復で保持（将来拡張）', () {
    final m = newMove('x').copyWith();
    final withExtra = MoveDefinition(
      id: 'x',
      name: 'x',
      category: MoveCategory.normal,
      attribute: MoveAttribute.strike,
      power: 10,
      heat: 1,
      requiredCards: {for (final v in MoveAttribute.values) v: 0},
      discardAfterUse: {for (final v in MoveAttribute.values) v: 0},
      extra: const {'aiPriority': 5, 'rarity': 3},
    );
    expect(m.extra, isEmpty);
    final round = MoveDefinition.fromJson(withExtra.toJson());
    expect(round.extra['aiPriority'], 5);
    expect(round.extra['rarity'], 3);
  });
}
