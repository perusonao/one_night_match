import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/deck_balance_screen.dart';
import 'package:one_night_match/src/wrestler_editor/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Deck Simulator: 設定→実行→結果タブ切り替えまで例外なく動く', (tester) async {
    // 設定フォームが長くビューポート外(offstage)になるため、テスト画面を
    // 縦に大きく取ってスクロールなしで全要素を可視状態にする。
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: DeckBalanceScreen(repository: LocalWrestlerRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Deck Simulator（デッキバランス）'), findsOneWidget);
    expect(find.text('シミュレーション実行'), findsOneWidget);

    // 試合数を100に切り替えて実行時間を短縮する。
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, '1000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('シミュレーション実行'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('総試合数'), findsOneWidget);

    // タブ切り替えが例外なく動く。
    await tester.tap(find.text('技分析'));
    await tester.pumpAndSettle();
    expect(find.text('技名'), findsOneWidget);

    await tester.tap(find.text('レスラー分析'));
    await tester.pumpAndSettle();
    expect(find.text('レスラー'), findsOneWidget);

    await tester.tap(find.text('AIレポート'));
    await tester.pumpAndSettle();
    // 所見なし/ありのどちらでも例外が出なければOK。
  });
}
