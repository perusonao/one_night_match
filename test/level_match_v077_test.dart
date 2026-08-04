import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};
  WrestlerDefinition byId(String id) =>
      defaultEditorWrestlers.firstWhere((w) => w.id == id);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Ver.0.7.7: レスラー固有の通常技が解決される', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_jack'),
      moves: moves,
      random: Random(1),
      playerStarts: true,
    );
    // Ver.0.9: 技カードは固有技（ド派手な固有名）とも技エネルギーカード
    // （属性名のみ）とも混同しないよう、実在感のある技名で統一。
    expect(m.basicMoveFor(MoveAttribute.strike, m.state.player)!.name, '速射ジャブ');
    expect(m.basicMoveFor(MoveAttribute.strike, m.state.player)!.id, 'akari_nt_strike');
    expect(m.basicMoveFor(MoveAttribute.strike, m.state.cpu)!.name, '不意打ちジャブ');
    expect(m.basicMoveFor(MoveAttribute.strike, m.state.cpu)!.id, 'jack_nt_strike');
    // 未指定属性は共通の通常技へフォールバック。
    expect(m.basicMoveFor(MoveAttribute.counter, m.state.player)!.id, 'basic_counter');
  });

  test('Ver.0.7.7: 固有技IDがレスラー間で重複しない', () {
    final all = <String>{};
    for (final w in defaultEditorWrestlers) {
      for (final lv in w.levels) {
        for (final id in lv.moveIds) {
          expect(all.add(id), isTrue,
              reason: '固有技IDが重複: $id (${w.name})');
        }
      }
    }
  });

  _editorModelTests();

  test('Ver.0.7.7: 各レスラーの固有技・通常技・フィニッシャーが揃う', () {
    for (final w in defaultEditorWrestlers) {
      // 固有技6種（L1-L3 各2）。
      final sig = [for (final lv in w.levels) ...lv.moveIds];
      expect(sig.length, 6, reason: '${w.name} の固有技数');
      // フィニッシャーがL3に登録。
      expect(w.levels.last.finisherId, isNotNull);
      expect(moves[w.levels.last.finisherId]!.category,
          MoveCategory.finisher);
      // 固有の通常技を持つ。
      expect(w.basicMoveIds, isNotEmpty);
    }
  });
}

// ===== Ver.0.7.7 エディタ関連の回帰 =====
void _editorModelTests() {
  test('MoveDefinition.copyWith はUI未対応フィールドを保持する', () {
    final moves = {for (final m in defaultEditorMoves) m.id: m};
    final jack = moves['jack_roughslam']!;
    expect(jack.specialAbilities, contains('cannotCounter'));
    // 威力だけ変更しても、cannotCounter・速度・consumesSetCards は保持。
    final edited = jack.copyWith(power: 30);
    expect(edited.power, 30);
    expect(edited.specialAbilities, contains('cannotCounter'));
    expect(edited.speed, jack.speed);
    expect(edited.consumesSetCards, jack.consumesSetCards);
  });

  test('WrestlerDefinition.basicMoveIds は JSON 往復で保持される', () {
    final akari =
        defaultEditorWrestlers.firstWhere((w) => w.id == 'wrestler_akari');
    expect(akari.basicMoveIds[MoveAttribute.strike], 'akari_nt_strike');
    final round = WrestlerDefinition.fromJson(akari.toJson());
    expect(round.basicMoveIds, akari.basicMoveIds);
  });
}
