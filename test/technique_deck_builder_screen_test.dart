import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_builder_screen.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_storage.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart'
    show MoveAttribute, WrestlerDefinition;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TechniqueDeckCardCatalog testCatalog() => const TechniqueDeckCardCatalog(
    techniques: [
      TechniqueDeckTechniqueCard(
        id: 'normal_1',
        name: '通常技A',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: 1},
      ),
      TechniqueDeckTechniqueCard(
        id: 'sig_akari',
        name: '固有技アカリ',
        category: TechniqueCardCategory.signature,
        attribute: MoveAttribute.strike,
        allowedWrestlerIds: ['wrestler_akari'],
      ),
      TechniqueDeckTechniqueCard(
        id: 'fin_akari',
        name: 'フィニッシャーアカリ',
        category: TechniqueCardCategory.finisher,
        attribute: MoveAttribute.strike,
        allowedWrestlerIds: ['wrestler_akari'],
        hasFinisherEffect: true,
      ),
      TechniqueDeckTechniqueCard(
        id: 'sig_jack',
        name: '固有技ジャック',
        category: TechniqueCardCategory.signature,
        attribute: MoveAttribute.strike,
        allowedWrestlerIds: ['wrestler_jack'],
      ),
    ],
    energies: [
      TechniqueEnergyCard(
        id: 'energy_strike',
        attribute: MoveAttribute.strike,
        name: '打エネルギー',
      ),
    ],
    defenseCards: [],
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    TechniqueDeckCardCatalog? catalog,
    TechniqueDeckRepository? deckRepository,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 5000));
    await tester.pumpWidget(
      MaterialApp(
        home: TechniqueDeckBuilderScreen(
          catalog: catalog ?? testCatalog(),
          deckRepository: deckRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expandCategory(WidgetTester tester, String label) async {
    final finder = find.textContaining(label).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('TechniqueDeckBuilderScreen: 初期表示', () {
    testWidgets('レスラーが選択され合計枚数0/30と表示される', (tester) async {
      await pumpScreen(tester);
      expect(find.text('合計枚数 0 / 30'), findsOneWidget);
      expect(find.text('火神アカリ'), findsOneWidget);
      expect(find.textContaining('開発中：Technique Deck Rules'), findsOneWidget);
    });

    testWidgets('エラー・警告バッジが表示される（技エネルギー0枚のためエラーあり）', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('エラー'), findsWidgets);
    });
  });

  group('TechniqueDeckBuilderScreen: レスラー変更', () {
    testWidgets('ドロップダウンでレスラーを変更できる', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byType(DropdownButtonFormField<WrestlerDefinition>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('黒蝶ジャック').last);
      await tester.pumpAndSettle();
      expect(find.text('黒蝶ジャック'), findsWidgets);
    });
  });

  group('TechniqueDeckBuilderScreen: カード枚数増減', () {
    testWidgets('通常技を+すると合計枚数へ即座に反映される', (tester) async {
      await pumpScreen(tester);
      await expandCategory(tester, '通常技');
      final addButtons = find.byIcon(Icons.add_circle_outline);
      await tester.ensureVisible(addButtons.first);
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();
      expect(find.text('合計枚数 1 / 30'), findsOneWidget);
    });

    testWidgets('固有技は同名1枚に達すると+ボタンが無効化される', (tester) async {
      await pumpScreen(tester);
      await expandCategory(tester, '固有技');
      final addButtons = find.byIcon(Icons.add_circle_outline);
      await tester.ensureVisible(addButtons.first);
      await tester.tap(addButtons.first); // 固有技アカリを1枚追加
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.add_circle_outline).first,
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull); // 上限（1枚）に達したため無効化
    });

    testWidgets('使用不能な固有技（他レスラー専用）は+ボタンが無効', (tester) async {
      await pumpScreen(tester); // 既定選択は火神アカリ
      await expandCategory(tester, '固有技');
      // 固有技ジャックの行（最も近いRow祖先）を探す。
      final jackRow = find
          .ancestor(of: find.text('固有技ジャック'), matching: find.byType(Row))
          .first;
      final addButton = find.descendant(
        of: jackRow,
        matching: find.byIcon(Icons.add_circle_outline),
      );
      final button = tester.widget<IconButton>(
        find.ancestor(of: addButton, matching: find.byType(IconButton)).first,
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('30枚超過で赤表示になる', (tester) async {
      await pumpScreen(tester);
      // 技エネルギーは同名上限なしのため、超過テストに使う。
      await expandCategory(tester, '技エネルギー');
      final addButton = find.byIcon(Icons.add_circle_outline).first;
      await tester.ensureVisible(addButton);
      for (var i = 0; i < 31; i++) {
        await tester.tap(addButton);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final totalText = tester.widget<Text>(find.textContaining('合計枚数 31'));
      expect(totalText.style?.color, const Color(0xffff5c5c));
    });
  });

  group('TechniqueDeckBuilderScreen: 保存・読込', () {
    testWidgets('編集すると未保存の変更が表示され、保存すると消える', (tester) async {
      final repo = LocalTechniqueDeckRepository();
      await pumpScreen(tester, deckRepository: repo);
      expect(find.text('保存済み'), findsOneWidget);

      await expandCategory(tester, '通常技');
      final addButton = find.byIcon(Icons.add_circle_outline).first;
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      expect(find.text('未保存の変更があります'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('保存済み'), findsOneWidget);

      final saved = await repo.loadAll();
      expect(saved.length, 1);
      expect(saved.first.entries.length, 1);
    });
  });

  group('TechniqueDeckBuilderScreen: JSON入出力', () {
    testWidgets('JSONダイアログを開いて不正なJSONを検証するとエラーが表示される', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'JSON'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'これは不正なJSONです');
      await tester.tap(find.widgetWithText(TextButton, '検証'));
      await tester.pumpAndSettle();

      expect(find.textContaining('JSONの読み込みに失敗しました'), findsOneWidget);
    });

    testWidgets('有効なJSONを読み込んでプレビューできる', (tester) async {
      await pumpScreen(tester);
      final validDeck = TechniqueDeckDefinition(
        id: 'd1',
        wrestlerId: 'wrestler_akari',
        name: '読込デッキ',
        entries: const [
          TechniqueDeckEntry(
            instanceId: 'e1',
            cardId: 'normal_1',
            cardType: TechniqueDeckCardType.technique,
          ),
        ],
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'JSON'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).last,
        // toJson()相当を手書き（importでconvertを使わず直接文字列化）。
        '{"id":"d1","wrestlerId":"wrestler_akari","name":"読込デッキ",'
        '"entries":[{"instanceId":"e1","cardId":"normal_1","cardType":"technique"}]}',
      );
      await tester.tap(find.widgetWithText(TextButton, '検証'));
      await tester.pumpAndSettle();

      expect(find.text('デッキ名: ${validDeck.name}'), findsOneWidget);
      expect(find.text('枚数: 1'), findsOneWidget);
    });
  });
}
