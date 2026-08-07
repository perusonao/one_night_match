import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_night_match/src/playtest_analytics/playtest_match_repository.dart';
import 'package:one_night_match/src/playtest_analytics/technique_match_analysis_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Map<String, dynamic> matchJson({
    String gameId = 'game-1',
    String finishReason = 'フォール勝利',
  }) => {
    'game': {
      'gameId': gameId,
      'appVersion': '0.8.5A-2',
      'gameVersion': 'phase8.5A-2',
      'buildLabel': 'Test Build',
      'opponentType': 'cpu',
      'cpuDifficulty': 'normal',
      'startedAt': DateTime(2026, 1, 1).toIso8601String(),
      'finishedAt': DateTime(2026, 1, 1, 0, 5).toIso8601String(),
      'winnerId': 'A',
      'finishReason': finishReason,
      'turns': 10,
      'matchTimeSeconds': 300,
      'matchTimeDisplay': '5:00',
      'deckReshuffleCount': 0,
    },
    'players': [
      {'playerId': 'A', 'wrestlerId': 'w_a', 'wrestlerName': 'アカリ', 'isCpu': false},
      {'playerId': 'B', 'wrestlerId': 'w_b', 'wrestlerName': 'ミサキ', 'isCpu': true},
    ],
    'decks': const [],
    'turns': const [],
    'cpuTraces': const [],
    'summary': {'rawLog': const <String>[]},
  };

  const analysisResults = [
    TechniqueMatchAnalysisResult(
      severity: TechniqueMatchAnalysisSeverity.critical,
      diagnosticCode: 'CRITICAL_LEGAL_MOVE_PASS',
      title: 'test',
      description: 'test description',
      turnNumber: 3,
      playerId: 'B',
    ),
  ];

  group('PlaytestMatchRecord', () {
    test('toJson/fromJsonの往復でmatchJson・analysisResultsが保持される', () {
      final record = PlaytestMatchRecord(
        matchJson: matchJson(),
        analysisResults: analysisResults,
        savedAt: DateTime.utc(2026, 1, 1),
      );
      final round = PlaytestMatchRecord.fromJson(record.toJson());
      expect(round.gameId, 'game-1');
      expect(round.analysisResults, hasLength(1));
      expect(round.analysisResults.first.diagnosticCode, 'CRITICAL_LEGAL_MOVE_PASS');
      expect(round.matchupLabel, 'アカリ vs ミサキ');
      expect(round.winnerLabel, 'アカリ');
      expect(round.summary.criticalCount, 1);
    });

    test('DRAWの場合はwinnerLabelがDRAWになる', () {
      final record = PlaytestMatchRecord(
        matchJson: matchJson(finishReason: 'draw'),
        analysisResults: const [],
        savedAt: DateTime.utc(2026, 1, 1),
      );
      expect(record.isDraw, isTrue);
      expect(record.winnerLabel, 'DRAW');
    });
  });

  group('PlaytestMatchRepository', () {
    test('保存前は空リストを返す', () async {
      final repo = PlaytestMatchRepository();
      expect(await repo.loadAll(), isEmpty);
    });

    test('保存した試合をloadAllで取得できる', () async {
      final repo = PlaytestMatchRepository();
      await repo.save(
        PlaytestMatchRecord(
          matchJson: matchJson(),
          analysisResults: analysisResults,
          savedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final all = await repo.loadAll();
      expect(all, hasLength(1));
      expect(all.first.gameId, 'game-1');
      expect(all.first.summary.criticalCount, 1);
    });

    test('同じgameIdで再保存すると重複せず置き換えられる', () async {
      final repo = PlaytestMatchRepository();
      await repo.save(
        PlaytestMatchRecord(
          matchJson: matchJson(),
          analysisResults: const [],
          savedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repo.save(
        PlaytestMatchRecord(
          matchJson: matchJson(),
          analysisResults: analysisResults,
          savedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      final all = await repo.loadAll();
      expect(all, hasLength(1));
      expect(all.first.summary.criticalCount, 1);
    });

    test('別のgameIdで保存すると複数件保持される', () async {
      final repo = PlaytestMatchRepository();
      await repo.save(
        PlaytestMatchRecord(
          matchJson: matchJson(gameId: 'game-1'),
          analysisResults: const [],
          savedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repo.save(
        PlaytestMatchRecord(
          matchJson: matchJson(gameId: 'game-2'),
          analysisResults: const [],
          savedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final all = await repo.loadAll();
      expect(all, hasLength(2));
    });

    test('上限（100件）を超えると古いものから破棄される', () async {
      final repo = PlaytestMatchRepository();
      for (var i = 0; i < 105; i++) {
        await repo.save(
          PlaytestMatchRecord(
            matchJson: matchJson(gameId: 'game-$i'),
            analysisResults: const [],
            savedAt: DateTime.utc(2026, 1, 1),
          ),
        );
      }
      final all = await repo.loadAll();
      expect(all, hasLength(PlaytestMatchRepository.maxEntries));
      expect(all.first.gameId, 'game-5');
      expect(all.last.gameId, 'game-104');
    });

    test('壊れたJSONが保存されていても例外を投げず読み込める分だけ返す', () async {
      SharedPreferences.setMockInitialValues({
        'playtest_analytics_history_v1': ['not valid json', '{"broken":'],
      });
      final repo = PlaytestMatchRepository();
      expect(await repo.loadAll(), isEmpty);
    });
  });
}
