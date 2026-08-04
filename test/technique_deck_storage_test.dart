import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TechniqueDeckSaveRecord sampleRecord({
    String deckId = 'd1',
    String name = 'テストデッキ',
  }) => TechniqueDeckSaveRecord(
    deckId: deckId,
    name: name,
    wrestlerId: 'w1',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
    entries: const [
      TechniqueDeckEntry(
        instanceId: 'e1',
        cardId: 'c1',
        cardType: TechniqueDeckCardType.technique,
      ),
    ],
    generatorVersion: 'phase2-tentative-v1',
    notes: '暫定生成',
  );

  group('TechniqueDeckSaveRecord', () {
    test('JSON往復', () {
      final record = sampleRecord();
      final round = TechniqueDeckSaveRecord.fromJson(record.toJson());
      expect(round.deckId, record.deckId);
      expect(round.name, record.name);
      expect(round.wrestlerId, record.wrestlerId);
      expect(round.createdAt, record.createdAt);
      expect(round.updatedAt, record.updatedAt);
      expect(round.entries, record.entries);
      expect(round.schemaVersion, record.schemaVersion);
      expect(round.generatorVersion, record.generatorVersion);
      expect(round.notes, record.notes);
    });

    test('欠落フィールドは既定値で補完される', () {
      final record = TechniqueDeckSaveRecord.fromJson(const {'deckId': 'd1'});
      expect(record.deckId, 'd1');
      expect(record.name, '');
      expect(record.wrestlerId, '');
      expect(record.entries, isEmpty);
      expect(record.schemaVersion, 1);
      expect(record.generatorVersion, isNull);
      expect(record.notes, '');
    });

    test('copyWithでgeneratorVersionを明示的にnullへ戻せる', () {
      final record = sampleRecord();
      final updated = record.copyWith(generatorVersion: null);
      expect(updated.generatorVersion, isNull);
      final untouched = record.copyWith(name: '別名');
      expect(untouched.generatorVersion, record.generatorVersion);
    });

    test('toDeckDefinitionでTechniqueDeckDefinitionへ変換できる', () {
      final record = sampleRecord();
      final deck = record.toDeckDefinition();
      expect(deck.id, record.deckId);
      expect(deck.wrestlerId, record.wrestlerId);
      expect(deck.name, record.name);
      expect(deck.entries, record.entries);
    });
  });

  group('LocalTechniqueDeckRepository', () {
    test('保存前は空リストを返す', () async {
      final repo = LocalTechniqueDeckRepository();
      expect(await repo.loadAll(), isEmpty);
    });

    test('保存したデッキをloadAllで取得できる', () async {
      final repo = LocalTechniqueDeckRepository();
      await repo.save(sampleRecord());
      final all = await repo.loadAll();
      expect(all.length, 1);
      expect(all.first.deckId, 'd1');
    });

    test('同じdeckIdで保存すると上書きされる', () async {
      final repo = LocalTechniqueDeckRepository();
      await repo.save(sampleRecord(name: '旧名'));
      await repo.save(sampleRecord(name: '新名'));
      final all = await repo.loadAll();
      expect(all.length, 1);
      expect(all.first.name, '新名');
    });

    test('別IDで保存すると複製として追加される', () async {
      final repo = LocalTechniqueDeckRepository();
      await repo.save(sampleRecord(deckId: 'd1'));
      await repo.save(sampleRecord(deckId: 'd2', name: '複製'));
      final all = await repo.loadAll();
      expect(all.length, 2);
    });

    test('deleteで削除できる', () async {
      final repo = LocalTechniqueDeckRepository();
      await repo.save(sampleRecord(deckId: 'd1'));
      await repo.save(sampleRecord(deckId: 'd2'));
      await repo.delete('d1');
      final all = await repo.loadAll();
      expect(all.length, 1);
      expect(all.first.deckId, 'd2');
    });

    test('既存の保存キー（wrestler_editor）と衝突しない', () async {
      SharedPreferences.setMockInitialValues({
        'one_night_match_wrestler_editor_v04': '[]',
      });
      final repo = LocalTechniqueDeckRepository();
      await repo.save(sampleRecord());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('one_night_match_wrestler_editor_v04'), '[]');
      expect(
        prefs.getString(LocalTechniqueDeckRepository.storageKey),
        isNotNull,
      );
    });

    test('壊れたJSONが保存されていても例外を投げず空リストを返す', () async {
      SharedPreferences.setMockInitialValues({
        LocalTechniqueDeckRepository.storageKey: 'not valid json {{{',
      });
      final repo = LocalTechniqueDeckRepository();
      expect(await repo.loadAll(), isEmpty);
    });
  });
}
