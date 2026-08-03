import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/level_match/level_match_screens.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('演出システム: 技をタップしても最後まで例外なく進行する', (tester) async {
    // audioplayersはプラットフォームチャンネル未対応のテスト環境だと、
    // グローバルイベントストリーム購読時にMissingPluginExceptionを
    // "services library"経由で報告する（通常のtry/catchでは捕まらない）。
    // SEはベストエフォートの演出でありゲーム進行に影響しないため無視する。
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('audioplayers')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

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
      random: Random(2),
      playerStarts: true,
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
    await tester.pump(const Duration(milliseconds: 50));

    // 単体技（コスト不要・常に使用可能）のCTAをタップして攻撃を宣言する。
    final cta = find.text('この技で攻撃');
    expect(cta, findsWidgets);
    await tester.tap(cta.first);
    await tester.pump();

    // pumpAndSettleは思考中タイマー(Timer.periodic)のせいで使えないため、
    // 固定刻みで時間を進めて演出キューが最後まで流れることを確認する。
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    }

    // 何らかの形で試合が進行している（宣言直後のchooseMoveのままではない）。
    expect(
      engine.state.phase != LevelMatchPhase.chooseMove ||
          engine.state.turnNumber > 1,
      isTrue,
    );
  });
}
