import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_night_match/src/playtest_analytics/playtest_analytics_screen.dart';
import 'package:one_night_match/src/playtest_analytics/playtest_match_repository.dart';
import 'package:one_night_match/src/playtest_analytics/technique_match_analysis_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 【スマホ向けUIのため縦に長い】既定のテストサーフェス（800x600）だと
  // 統計カード＋試合一覧＋詳細画面のセクションがビューポート外になり、
  // ListViewの遅延構築で該当ウィジェットがElementツリーへ一切構築されず
  // `find`で見つからない（スクロールが必要な内容は`find`が届かない）。
  // 縦に十分長いサーフェスへ変更して、スクロールなしで内容を検証できる
  // ようにする。
  Future<void> setTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

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
      {
        'playerId': 'A',
        'wrestlerId': 'w_a',
        'wrestlerName': 'アカリ',
        'maxHp': 100,
        'finalHp': 40,
        'finalHeat': 5,
        'isCpu': false,
        'movesUsed': 4,
        'countersUsed': 1,
        'pinAttempts': 1,
        'submissionAttempts': 0,
        'finisherDeclarations': 0,
        'kickOuts': 0,
      },
      {
        'playerId': 'B',
        'wrestlerId': 'w_b',
        'wrestlerName': 'ミサキ',
        'maxHp': 100,
        'finalHp': 0,
        'finalHeat': 3,
        'isCpu': true,
        'movesUsed': 2,
        'countersUsed': 0,
        'pinAttempts': 0,
        'submissionAttempts': 0,
        'finisherDeclarations': 0,
        'kickOuts': 0,
      },
    ],
    'decks': const [],
    'turns': [
      {
        'turn': 1,
        'chain': 1,
        'timestamp': DateTime(2026, 1, 1).toIso8601String(),
        'actorId': 'w_a',
        'phase': 'end',
        'action': 'declareAttack',
        'cardName': '通常技A',
        'energyBefore': 3,
        'energyAfter': 2,
        'hpBefore': 100,
        'hpAfter': 100,
        'heatBefore': 0,
        'heatAfter': 1,
        'targetPostureBefore': 'stand',
        'targetPostureAfter': 'stand',
        'message': 'アカリの通常技Aが成立した',
      },
    ],
    'cpuTraces': const [],
    'summary': {'rawLog': const <String>[]},
  };

  Future<void> pumpWithRecord(WidgetTester tester, PlaytestMatchRecord record) async {
    await PlaytestMatchRepository().save(record);
    await tester.pumpWidget(const MaterialApp(home: PlaytestAnalyticsScreen()));
    await tester.pumpAndSettle();
  }

  group('PlaytestAnalyticsScreen 一覧', () {
    testWidgets('保存済み試合が0件の場合は案内文が表示される', (tester) async {
      await setTallSurface(tester);
      await tester.pumpWidget(const MaterialApp(home: PlaytestAnalyticsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('保存された試合がありません'), findsOneWidget);
    });

    testWidgets('保存済み試合の総試合数・対戦カードが表示される', (tester) async {
      await setTallSurface(tester);
      await pumpWithRecord(
        tester,
        PlaytestMatchRecord(
          matchJson: matchJson(),
          analysisResults: const [],
          savedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(find.text('総試合数'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.textContaining('アカリ vs ミサキ'), findsOneWidget);
    });

    testWidgets('CRITICAL診断がある試合はCRITICAL件数・アイコンが表示される', (tester) async {
      await setTallSurface(tester);
      await pumpWithRecord(
        tester,
        PlaytestMatchRecord(
          matchJson: matchJson(),
          analysisResults: const [
            TechniqueMatchAnalysisResult(
              severity: TechniqueMatchAnalysisSeverity.critical,
              diagnosticCode: 'CRITICAL_LEGAL_MOVE_PASS',
              title: '合法技があるのにpassTurnを選択',
              description: 'test',
              turnNumber: 3,
              playerId: 'B',
            ),
          ],
          savedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(find.text('CRITICAL件数'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsWidgets);
    });
  });

  group('PlaytestAnalyticsScreen 試合詳細', () {
    testWidgets('試合をタップすると詳細（概要・自動診断・選手統計・CPU Trace・ターンログ）が表示される', (tester) async {
      await setTallSurface(tester);
      await pumpWithRecord(
        tester,
        PlaytestMatchRecord(
          matchJson: matchJson(),
          analysisResults: const [
            TechniqueMatchAnalysisResult(
              severity: TechniqueMatchAnalysisSeverity.warning,
              diagnosticCode: 'WARNING_DRAW',
              title: 'テスト診断',
              description: 'test description',
            ),
          ],
          savedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await tester.tap(find.textContaining('アカリ vs ミサキ').first);
      await tester.pumpAndSettle();

      expect(find.text('概要'), findsOneWidget);
      expect(find.text('自動診断'), findsOneWidget);
      expect(find.text('選手統計'), findsOneWidget);
      expect(find.text('CPU Trace'), findsOneWidget);
      expect(find.text('ターンログ'), findsOneWidget);
      expect(find.text('テスト診断'), findsOneWidget);
      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
    });
  });
}
