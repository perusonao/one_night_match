import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/app_build_info.dart';
import 'package:one_night_match/src/game.dart';
import 'package:one_night_match/src/screens.dart';

/// Phase 8.5A-2 ⑩: トップ画面のバージョン表示・改修履歴（changelog）モーダル
/// のテスト。
void main() {
  Future<void> pumpTitle(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TitleScreen(catalog: GameCatalog.standard())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('トップ画面に現在のバージョンが常時表示される', (tester) async {
    await pumpTitle(tester);
    expect(find.textContaining('Ver. ${AppBuildInfo.version}'), findsOneWidget);
  });

  testWidgets('「更新内容」ボタンから直近の改修履歴を開ける', (tester) async {
    await pumpTitle(tester);
    expect(find.text('更新内容'), findsOneWidget);

    await tester.tap(find.text('更新内容'));
    await tester.pumpAndSettle();

    // 直近3〜5件（現状2件）の各バージョン見出しが表示される。
    for (final entry in AppBuildInfo.changelog) {
      expect(find.textContaining(entry.version), findsWidgets);
      for (final item in entry.items) {
        expect(find.textContaining(item), findsOneWidget);
      }
    }
  });

  testWidgets('ゲーム開始ボタン群は改修履歴ボタン追加後も表示されたまま', (tester) async {
    await pumpTitle(tester);
    expect(find.text('クラシックマッチ  Ver.0.2'), findsOneWidget);
    expect(find.text('レベルカードマッチ  Ver.0.7'), findsOneWidget);
    expect(find.text('試合を始める（Technique Match）'), findsOneWidget);
  });
}
