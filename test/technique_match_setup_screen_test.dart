import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_night_match/src/technique_deck/technique_match_screen.dart';
import 'package:one_night_match/src/technique_deck/technique_match_setup_screen.dart';

/// 【ゲームサイクル整理ラウンド 優先度10】トップページからのゲーム開始導線
/// のテスト。トップ→試合設定→Technique Matchの流れと、保存済みデッキ
/// 優先・モデルデッキへのフォールバックの表示を検証する。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSetup(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    await tester.pumpWidget(
      const MaterialApp(home: TechniqueMatchSetupScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('セットアップ画面が開き、CPUレスラー選択欄が表示される（標準=CPU対戦）', (tester) async {
    await pumpSetup(tester);

    expect(find.text('CPU対戦'), findsOneWidget);
    expect(find.text('2人対戦'), findsOneWidget);
    // 標準でCPU対戦が選ばれているため、④CPUレスラー・⑤CPU難易度欄が
    // 最初から見えている（2人対戦時のみ隠れる項目）。
    expect(find.text('④ CPUレスラー'), findsOneWidget);
    expect(find.text('⑤ CPU難易度'), findsOneWidget);
  });

  testWidgets('保存済みデッキが無いレスラーはモデルデッキ使用の案内が表示される', (tester) async {
    await pumpSetup(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('デッキを使用します'), findsOneWidget);
  });

  testWidgets('試合開始でTechniqueMatchScreen（CPU対戦モード）へ遷移する', (tester) async {
    await pumpSetup(tester);

    await tester.tap(find.text('試合開始'));
    await tester.pumpAndSettle();

    expect(find.byType(TechniqueMatchScreen), findsOneWidget);
    final screen = tester.widget<TechniqueMatchScreen>(find.byType(TechniqueMatchScreen));
    expect(screen.vsCpu, isTrue);
    expect(screen.initialWrestlerAId, isNotNull);
    expect(screen.initialWrestlerBId, isNotNull);
  });

  testWidgets('2人対戦を選ぶとvsCpu:falseで遷移する', (tester) async {
    await pumpSetup(tester);

    await tester.tap(find.text('2人対戦'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('試合開始'));
    await tester.pumpAndSettle();

    final screen = tester.widget<TechniqueMatchScreen>(find.byType(TechniqueMatchScreen));
    expect(screen.vsCpu, isFalse);
  });
}
