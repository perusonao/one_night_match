import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};
  WrestlerDefinition byId(String id) =>
      defaultEditorWrestlers.firstWhere((w) => w.id == id);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Ver.0.8.0: 残り時間が計算される（15分=30ターン）', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(1),
      matchTimeSeconds: 900,
    );
    expect(m.state.isTimed, isTrue);
    expect(m.state.turnLimit, 30);
    expect(m.state.remainingSeconds, 900); // ターン1開始時
  });

  test('Ver.0.8.0: 時間切れで判定決着になる', () {
    // 60秒=2ターンの超短時間。フォールが出なければ3ターン目開始で判定。
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(3),
      matchTimeSeconds: 60,
    );
    var guard = 0;
    while (!m.state.isGameOver && guard++ < 500) {
      m.autoAdvance();
    }
    expect(m.state.isGameOver, isTrue);
    // 短時間なので判定決着（または稀にフォール）。勝者は必ず決まる。
    expect(m.state.winnerId, isNotNull);
    // 時間制限を大きく超えない。
    expect(m.state.turnNumber, lessThanOrEqualTo(4));
  });

  test('Ver.0.8.0: 無制限（既定）は従来通り時間切れなし', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(3),
    );
    expect(m.state.isTimed, isFalse);
    expect(m.state.remainingSeconds, isNull);
  });

  test('Ver.0.8.0: displayHeatCost がカテゴリから推定される', () {
    expect(moves['basic_strike']!.displayHeatCost, 1); // 通常技
    expect(moves['high_speed_german']!.displayHeatCost, 8); // フィニッシャー
    // 固有技はコストに応じて3〜6。
    final sig = moves['akari_dragon']!; // cost3 throw
    expect(sig.displayHeatCost, inInclusiveRange(3, 6));
    // heatCost 明示指定は往復で保持。
    final custom = sig.copyWith(heatCost: 5);
    expect(MoveDefinition.fromJson(custom.toJson()).heatCost, 5);
  });
}
