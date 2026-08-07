import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/playtest_analytics/technique_match_analysis_result.dart';
import 'package:one_night_match/src/playtest_analytics/technique_match_analyzer.dart';

/// Playtest Analytics Phase A: [TechniqueMatchAnalyzer]のunit test。
///
/// `TechniqueMatchJsonLog.build()`の出力と同じスキーマのMapを直接組み立てて
/// 入力する（Analyzerはこのスキーマにのみ依存する純粋関数のため、
/// エンジンやUIを経由しなくてもテストできる）。
void main() {
  Map<String, dynamic> baseGame({
    int turns = 5,
    String finishReason = 'フォール勝利',
    int matchTimeSeconds = 150,
    String matchTimeDisplay = '2:30',
    int deckReshuffleCount = 0,
  }) => {
    'gameId': 'test-game',
    'schemaVersion': '1.0.0',
    'gameVersion': 'phase8.5A-2',
    'appVersion': '0.8.5A-2',
    'buildLabel': 'Test Build',
    'rulesVersion': 'technique-deck-rules',
    'mode': 'techniqueMatch',
    'opponentType': 'cpu',
    'cpuDifficulty': 'normal',
    'startedAt': DateTime(2026, 1, 1).toIso8601String(),
    'finishedAt': DateTime(2026, 1, 1).toIso8601String(),
    'winnerId': 'A',
    'finishReason': finishReason,
    'finishingCardId': null,
    'turns': turns,
    'elapsedSeconds': 60,
    'elapsedRealSeconds': 60,
    'matchTimeSeconds': matchTimeSeconds,
    'matchTimeDisplay': matchTimeDisplay,
    'timeOverCount': 0,
    'deckReshuffleCount': deckReshuffleCount,
  };

  Map<String, dynamic> player({
    required String playerId,
    required String wrestlerName,
    bool isCpu = false,
    int movesUsed = 3,
    int countersUsed = 1,
    int finalHeat = 5,
    int pinAttempts = 1,
    int submissionAttempts = 0,
  }) => {
    'playerId': playerId,
    'wrestlerId': 'wrestler_$playerId',
    'wrestlerName': wrestlerName,
    'maxHp': 100,
    'finalHp': 40,
    'recoveryPower': 0,
    'finalHeat': finalHeat,
    'posture': 'stand',
    'isCpu': isCpu,
    'movesUsed': movesUsed,
    'countersUsed': countersUsed,
    'restsUsed': 0,
    'pinAttempts': pinAttempts,
    'submissionAttempts': submissionAttempts,
    'finisherDeclarations': 0,
    'kickOuts': 0,
    'ropeBreaks': 0,
  };

  Map<String, dynamic> cpuTrace({
    required int turnNumber,
    required int playerIndex,
    required String decisionType,
    required String chosenAction,
    int? legalMoveCount,
    String? bestEligibleCardId,
    String? bestEligibleCardName,
    int? bestEligibleScore,
    String? noLegalMoveReasonCode,
    List<Map<String, dynamic>> candidates = const [],
  }) => {
    'turnNumber': turnNumber,
    'playerIndex': playerIndex,
    'cpuLevel': 'normal',
    'decisionType': decisionType,
    'candidates': candidates,
    'chosen': {'action': chosenAction, 'reason': 'test'},
    'rejected': const [],
    'legalMoveCount': ?legalMoveCount,
    'bestEligibleCardId': ?bestEligibleCardId,
    'bestEligibleCardName': ?bestEligibleCardName,
    'bestEligibleScore': ?bestEligibleScore,
    'noLegalMoveReasonCode': ?noLegalMoveReasonCode,
  };

  const analyzer = TechniqueMatchAnalyzer();

  group('CRITICAL_LEGAL_MOVE_PASS / CRITICAL_LEGAL_MOVE_END_RALLY', () {
    test('legalMoveCount > 0 かつ passTurn ならCRITICALを検出する', () {
      final json = {
        'game': baseGame(),
        'players': [player(playerId: 'A', wrestlerName: 'アカリ'), player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true)],
        'cpuTraces': [
          cpuTrace(
            turnNumber: 3,
            playerIndex: 1,
            decisionType: 'passTurn',
            chosenAction: 'passTurn',
            legalMoveCount: 2,
            bestEligibleCardId: 'card_x',
            bestEligibleCardName: '技X',
            bestEligibleScore: 10,
          ),
        ],
      };
      final results = analyzer.analyze(json);
      final hit = results.where((r) => r.diagnosticCode == 'CRITICAL_LEGAL_MOVE_PASS');
      expect(hit, hasLength(1));
      expect(hit.first.severity, TechniqueMatchAnalysisSeverity.critical);
      expect(hit.first.turnNumber, 3);
      expect(hit.first.playerId, 'B');
      expect(hit.first.relatedCardId, 'card_x');
    });

    test('legalMoveCount > 0 かつ endRally ならCRITICALを検出する', () {
      final json = {
        'game': baseGame(),
        'players': [player(playerId: 'A', wrestlerName: 'アカリ'), player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true)],
        'cpuTraces': [
          cpuTrace(
            turnNumber: 5,
            playerIndex: 1,
            decisionType: 'endRally',
            chosenAction: 'endRally',
            legalMoveCount: 1,
          ),
        ],
      };
      final results = analyzer.analyze(json);
      final hit = results.where((r) => r.diagnosticCode == 'CRITICAL_LEGAL_MOVE_END_RALLY');
      expect(hit, hasLength(1));
      expect(hit.first.severity, TechniqueMatchAnalysisSeverity.critical);
    });

    test('legalMoveCount == 0 のpassTurnはCRITICALにならない（正常系）', () {
      final json = {
        'game': baseGame(),
        'players': [player(playerId: 'A', wrestlerName: 'アカリ'), player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true)],
        'cpuTraces': [
          cpuTrace(
            turnNumber: 3,
            playerIndex: 1,
            decisionType: 'passTurn',
            chosenAction: 'passTurn',
            legalMoveCount: 0,
            noLegalMoveReasonCode: 'insufficientEnergy',
          ),
        ],
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode.startsWith('CRITICAL_LEGAL_MOVE')), isEmpty);
    });
  });

  group('CRITICAL_CPU_NO_ATTACK', () {
    test('CPUのmovesUsed==0かつターン数が十分ならCRITICAL', () {
      final json = {
        'game': baseGame(turns: 15),
        'players': [
          player(playerId: 'A', wrestlerName: 'アカリ'),
          player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true, movesUsed: 0),
        ],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      final hit = results.where((r) => r.diagnosticCode == 'CRITICAL_CPU_NO_ATTACK');
      expect(hit, hasLength(1));
      expect(hit.first.playerId, 'B');
    });

    test('ターン数が少なければCRITICALにならない', () {
      final json = {
        'game': baseGame(turns: 3),
        'players': [
          player(playerId: 'A', wrestlerName: 'アカリ'),
          player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true, movesUsed: 0),
        ],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode == 'CRITICAL_CPU_NO_ATTACK'), isEmpty);
    });
  });

  group('WARNING_DRAW', () {
    test('finishReason==draw ならWARNING', () {
      final json = {
        'game': baseGame(finishReason: 'draw'),
        'players': [player(playerId: 'A', wrestlerName: 'アカリ'), player(playerId: 'B', wrestlerName: 'ミサキ')],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode == 'WARNING_DRAW'), hasLength(1));
    });
  });

  group('WARNING_LONG_MATCH', () {
    test('ターン数が閾値以上ならWARNING', () {
      final json = {
        'game': baseGame(turns: 70),
        'players': [player(playerId: 'A', wrestlerName: 'アカリ'), player(playerId: 'B', wrestlerName: 'ミサキ')],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode == 'WARNING_LONG_MATCH'), hasLength(1));
    });
  });

  group('WARNING_COUNTER_HEAVY', () {
    test('countersUsedが閾値以上ならWARNING', () {
      final json = {
        'game': baseGame(),
        'players': [
          player(playerId: 'A', wrestlerName: 'アカリ', countersUsed: 20),
          player(playerId: 'B', wrestlerName: 'ミサキ'),
        ],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      final hit = results.where((r) => r.diagnosticCode == 'WARNING_COUNTER_HEAVY');
      expect(hit, hasLength(1));
      expect(hit.first.playerId, 'A');
    });
  });

  group('WARNING_NO_PLAYABLE_MOVE_HIGH', () {
    test('合法技0件だった意思決定の比率が高ければWARNING', () {
      final traces = List.generate(
        10,
        (i) => cpuTrace(
          turnNumber: i + 1,
          playerIndex: 1,
          decisionType: 'passTurn',
          chosenAction: 'passTurn',
          legalMoveCount: i < 6 ? 0 : 1,
        ),
      );
      final json = {
        'game': baseGame(turns: 10),
        'players': [player(playerId: 'A', wrestlerName: 'アカリ'), player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true)],
        'cpuTraces': traces,
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode == 'WARNING_NO_PLAYABLE_MOVE_HIGH'), hasLength(1));
    });

    test('サンプル数が少なすぎる場合は判定しない', () {
      final traces = [
        cpuTrace(turnNumber: 1, playerIndex: 1, decisionType: 'passTurn', chosenAction: 'passTurn', legalMoveCount: 0),
      ];
      final json = {
        'game': baseGame(),
        'players': [player(playerId: 'A', wrestlerName: 'アカリ'), player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true)],
        'cpuTraces': traces,
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode == 'WARNING_NO_PLAYABLE_MOVE_HIGH'), isEmpty);
    });
  });

  group('WARNING_FINISHER_DOMINANCE', () {
    test('フィニッシャー勝利かつフォール/ギブアップ試行0回ならWARNING', () {
      final json = {
        'game': baseGame(finishReason: 'フィニッシャー勝利'),
        'players': [
          player(playerId: 'A', wrestlerName: 'アカリ', pinAttempts: 0, submissionAttempts: 0),
          player(playerId: 'B', wrestlerName: 'ミサキ', pinAttempts: 0, submissionAttempts: 0),
        ],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode == 'WARNING_FINISHER_DOMINANCE'), hasLength(1));
    });

    test('フォール/ギブアップの試行があれば発火しない', () {
      final json = {
        'game': baseGame(finishReason: 'フィニッシャー勝利'),
        'players': [
          player(playerId: 'A', wrestlerName: 'アカリ', pinAttempts: 1),
          player(playerId: 'B', wrestlerName: 'ミサキ'),
        ],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode == 'WARNING_FINISHER_DOMINANCE'), isEmpty);
    });
  });

  group('WARNING_ZERO_HEAT', () {
    test('CPUのfinalHeat==0かつターン数十分ならWARNING', () {
      final json = {
        'game': baseGame(turns: 10),
        'players': [
          player(playerId: 'A', wrestlerName: 'アカリ'),
          player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true, finalHeat: 0),
        ],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      expect(results.where((r) => r.diagnosticCode == 'WARNING_ZERO_HEAT'), hasLength(1));
    });
  });

  group('INFO_DECK_RESHUFFLE', () {
    test('deckReshuffleCount > 0 ならINFO', () {
      final json = {
        'game': baseGame(deckReshuffleCount: 2),
        'players': [player(playerId: 'A', wrestlerName: 'アカリ'), player(playerId: 'B', wrestlerName: 'ミサキ')],
        'cpuTraces': const [],
      };
      final results = analyzer.analyze(json);
      final hit = results.where((r) => r.diagnosticCode == 'INFO_DECK_RESHUFFLE');
      expect(hit, hasLength(1));
      expect(hit.first.severity, TechniqueMatchAnalysisSeverity.info);
    });
  });

  group('正常試合', () {
    test('異常のない試合ではCRITICALが1件も出ない', () {
      final json = {
        'game': baseGame(turns: 8, finishReason: 'フォール勝利'),
        'players': [
          player(playerId: 'A', wrestlerName: 'アカリ', movesUsed: 4, countersUsed: 1, pinAttempts: 1),
          player(playerId: 'B', wrestlerName: 'ミサキ', isCpu: true, movesUsed: 3, countersUsed: 1, finalHeat: 6),
        ],
        'cpuTraces': [
          cpuTrace(
            turnNumber: 2,
            playerIndex: 1,
            decisionType: 'declareAttack',
            chosenAction: 'declareAttack',
            legalMoveCount: 2,
          ),
          cpuTrace(
            turnNumber: 4,
            playerIndex: 1,
            decisionType: 'passTurn',
            chosenAction: 'passTurn',
            legalMoveCount: 0,
            noLegalMoveReasonCode: 'insufficientEnergy',
          ),
        ],
      };
      final results = analyzer.analyze(json);
      expect(
        results.where((r) => r.severity == TechniqueMatchAnalysisSeverity.critical),
        isEmpty,
      );
    });
  });
}
