import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/level_match/level_match_screens.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Ver.0.8.0 energyモード：セットフェイズが崩れず描画される', (tester) async {
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
      resourceMode: MatchResourceMode.energy,
    );
    expect(engine.state.phase, LevelMatchPhase.setCard);
    expect(engine.state.resourceMode, MatchResourceMode.energy);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: LevelMatchBattleScreen(engine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('エネルギー'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ver.0.8.0 energyモード：技選択フェイズにコスト表示が出る', (tester) async {
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
      resourceMode: MatchResourceMode.energy,
    );
    engine.skipSetCard('player');
    engine.skipLevelChange('player');
    expect(engine.state.phase, LevelMatchPhase.chooseMove);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: LevelMatchBattleScreen(engine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('固有技（エネルギーを消費・決着可）'), findsOneWidget);
    // Ver.0.8.0：無料の単体技セクションはenergyモードでは非表示。
    expect(find.text('単体技（カード1枚で使用・コスト不要）'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
