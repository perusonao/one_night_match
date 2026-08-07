import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/app_build_info.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_model_decks.dart';
import 'package:one_night_match/src/technique_deck/technique_match_json_log.dart';
import 'package:one_night_match/src/technique_deck/technique_match_state.dart';

/// Phase 8.5A-2 ⑩⑫: バージョン表示とJSONログの整合性、および
/// ターン数→試合時間換算のテスト。
void main() {
  group('formatMatchTime（Phase 8.5A-2 ⑫）', () {
    test('1ターン=0:30', () => expect(formatMatchTime(1), '0:30'));
    test('2ターン=1:00', () => expect(formatMatchTime(2), '1:00'));
    test('21ターン=10:30', () => expect(formatMatchTime(21), '10:30'));
    test('30ターン=15:00', () => expect(formatMatchTime(30), '15:00'));
    test('0ターン=0:00', () => expect(formatMatchTime(0), '0:00'));
  });

  group('TechniqueMatchJsonLog: バージョン整合性（Phase 8.5A-2 ⑩）', () {
    test('gameVersion/appVersion/buildLabelはAppBuildInfoの値と一致する', () {
      final deckA = findTechniquePhase7AModelDeck('wrestler_akari')!;
      final deckB = findTechniquePhase7AModelDeck('wrestler_misaki')!;
      final state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_akari',
        wrestlerAName: 'アカリ',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'wrestler_misaki',
        wrestlerBName: 'ミサキ',
        wrestlerBMaxHp: 100,
        deckB: deckB,
      );
      final now = DateTime.now();
      final json = TechniqueMatchJsonLog.build(
        gameId: 'test-game',
        schemaVersion: '1.0.0',
        gameVersion: AppBuildInfo.gameVersionId,
        appVersion: AppBuildInfo.version,
        buildLabel: AppBuildInfo.buildLabel,
        rulesVersion: 'technique-deck-rules',
        opponentType: 'human',
        cpuDifficulty: null,
        startedAt: now,
        finishedAt: now,
        state: state,
        elapsedSeconds: 0,
        timeOverCount: 0,
        players: const [],
        decks: [deckA, deckB],
        turns: const [],
      );
      final game = json['game'] as Map<String, dynamic>;
      expect(game['gameVersion'], AppBuildInfo.gameVersionId);
      expect(game['appVersion'], AppBuildInfo.version);
      expect(game['buildLabel'], AppBuildInfo.buildLabel);
      // 過去に発生した「画面は新ルールなのにJSONは古い固定値のまま」という
      // バグの再発防止（ユーザー添付ログで実際に発生した不整合）。
      expect(game['gameVersion'], isNot('phase8.2'));
    });

    test('matchTimeSeconds/matchTimeDisplayはstate.turnNumber由来でformatMatchTimeと一致する', () {
      final deckA = findTechniquePhase7AModelDeck('wrestler_akari')!;
      final deckB = findTechniquePhase7AModelDeck('wrestler_misaki')!;
      final state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_akari',
        wrestlerAName: 'アカリ',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'wrestler_misaki',
        wrestlerBName: 'ミサキ',
        wrestlerBMaxHp: 100,
        deckB: deckB,
      );
      final now = DateTime.now();
      final json = TechniqueMatchJsonLog.build(
        gameId: 'test-game',
        schemaVersion: '1.0.0',
        gameVersion: AppBuildInfo.gameVersionId,
        rulesVersion: 'technique-deck-rules',
        opponentType: 'human',
        cpuDifficulty: null,
        startedAt: now,
        finishedAt: now,
        state: state,
        elapsedSeconds: 131,
        timeOverCount: 0,
        players: const [],
        decks: [deckA, deckB],
        turns: const [],
      );
      final game = json['game'] as Map<String, dynamic>;
      expect(game['turns'], state.turnNumber);
      expect(game['matchTimeSeconds'], state.turnNumber * 30);
      expect(game['matchTimeDisplay'], formatMatchTime(state.turnNumber));
      // 実プレイ時間（elapsedRealSeconds）は既存のelapsedSecondsと後方互換に
      // 一致し、換算表示（matchTimeSeconds）とは別概念であることを確認する。
      expect(game['elapsedSeconds'], 131);
      expect(game['elapsedRealSeconds'], 131);
      expect(game['matchTimeSeconds'], isNot(131));
    });
  });

  group('ソース内に旧バージョン固定値が残っていないこと（Phase 8.5A-2 ⑩）', () {
    test('lib/以下のどのファイルにもgameVersionの固定リテラル"phase8.2"が残っていない', () {
      // コード中で過去のバグの経緯に触れるコメント（"phase8.2"という文字列
      // 自体への言及）は許容し、実際に値として使われている
      // `gameVersion: 'phase8.2'` のようなハードコードだけを検出する。
      final libDir = Directory('lib');
      final offenders = <String>[];
      final stalePattern = RegExp("""gameVersion:\\s*['"]phase8\\.2['"]""");
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (stalePattern.hasMatch(content)) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty, reason: '古いgameVersion固定値が残っています: $offenders');
    });
  });
}
