import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/level_match/level_match_screens.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Ver.0.7.2 UI: 対応フェイズが中継風レイアウトで描画される', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // iPhone 13 相当のポートレート。
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final moves = {for (final m in defaultEditorMoves) m.id: m};
    final ws = {for (final w in defaultEditorWrestlers) w.id: w};
    final engine = LevelMatchEngine.create(
      playerWrestler: ws['wrestler_akari']!,
      cpuWrestler: ws['wrestler_misaki']!,
      moves: moves,
      random: Random(3),
      playerStarts: false,
    );
    // CPU が攻撃を宣言し、プレイヤーの対応待ちになるまで進める。
    var steps = 0;
    while (steps++ < 500) {
      final owner = engine.decisionOwnerId();
      final atk = engine.state.pendingAttack;
      if (engine.state.phase == LevelMatchPhase.responseSelection &&
          atk?.defenderId == 'player') {
        break;
      }
      if (owner == 'cpu') {
        engine.autoAdvance();
      } else {
        // プレイヤー手番（対応以外）はスキップして CPU 攻撃まで進める。
        engine.autoAdvance();
      }
    }
    expect(engine.state.phase, LevelMatchPhase.responseSelection);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: LevelMatchBattleScreen(engine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 中継風・統一レイアウトの主要要素が出ている。
    expect(find.text('相手の攻撃！'), findsOneWidget);
    expect(find.text('あなたの対応を選択してください'), findsOneWidget);
    expect(find.text('速度比較'), findsOneWidget);
    expect(find.text('結果予測'), findsOneWidget);
    expect(find.text('受ける'), findsWidgets);
    // Ver.0.7.5：全フェーズ共通の枠（状況・実況・次の操作）。
    expect(find.text('試合の流れ'), findsOneWidget);
    expect(find.text('次の操作'), findsOneWidget);
    // レイアウト例外（オーバーフロー等）が出ていないこと。
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ver.0.7.5 UI: セット等の非対応フェーズも共通レイアウトで描画', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final moves = {for (final m in defaultEditorMoves) m.id: m};
    final ws = {for (final w in defaultEditorWrestlers) w.id: w};
    final engine = LevelMatchEngine.create(
      playerWrestler: ws['wrestler_akari']!,
      cpuWrestler: ws['wrestler_misaki']!,
      moves: moves,
      random: Random(1),
      playerStarts: true,
    );
    expect(engine.state.phase, LevelMatchPhase.setCard);
    await tester.pumpWidget(
      MaterialApp(theme: ThemeData.dark(),
          home: LevelMatchBattleScreen(engine: engine)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('カードセット'), findsWidgets);
    expect(find.text('試合の流れ'), findsOneWidget);
    expect(find.text('次の操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
