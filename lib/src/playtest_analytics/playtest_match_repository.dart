/// Playtest Analytics Phase A: ローカル（SharedPreferences）へ試合ログと
/// 自動解析結果を保存するRepository。
///
/// 既存の`MatchHistoryStore`（`lib/src/game.dart`）と同じくSharedPreferencesの
/// 文字列配列に1試合1エントリでJSONを保存する方式を踏襲しつつ、
/// Technique Match Analytics専用のキー・スキーマ（試合ログ本体＋自動診断結果）
/// を持つ。Firestore導入（Phase B以降）はこのRepositoryとは別実装とし、
/// ローカル保存の役割は「Firestore未接続でもPlaytest Analyticsを確認できる
/// こと」「Firestore保存に失敗した場合のフォールバック」として残す。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'technique_match_analysis_result.dart';

/// 1試合分の保存レコード（試合ログJSON＋自動解析結果）。
class PlaytestMatchRecord {
  const PlaytestMatchRecord({
    required this.matchJson,
    required this.analysisResults,
    required this.savedAt,
    this.saveStatus = 'saved',
  });

  /// `TechniqueMatchJsonLog.build()`が返すMapと同じスキーマ。
  final Map<String, dynamic> matchJson;
  final List<TechniqueMatchAnalysisResult> analysisResults;
  final DateTime savedAt;

  /// 'saved' | 'failed'。Phase AはFirestore非依存のためローカル保存の成否
  /// のみを表す（Phase B以降、Firestore保存の成否を表す用途へ拡張する
  /// 想定のフィールド）。
  final String saveStatus;

  Map<String, dynamic> get _game =>
      (matchJson['game'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> get _players =>
      ((matchJson['players'] as List?) ?? const [])
          .map((p) => (p as Map).cast<String, dynamic>())
          .toList();

  String get gameId => _game['gameId'] as String? ?? 'unknown';
  String get appVersion => _game['appVersion'] as String? ?? '';
  String get gameVersion => _game['gameVersion'] as String? ?? '';
  String? get buildLabel => _game['buildLabel'] as String?;
  String get opponentType => _game['opponentType'] as String? ?? '';
  String? get cpuDifficulty => _game['cpuDifficulty'] as String?;
  int get turns => _game['turns'] as int? ?? 0;
  String get finishReason => _game['finishReason'] as String? ?? '';
  int get matchTimeSeconds => _game['matchTimeSeconds'] as int? ?? 0;
  String get matchTimeDisplay => _game['matchTimeDisplay'] as String? ?? '';
  String? get winnerId => _game['winnerId'] as String?;
  int get deckReshuffleCount => _game['deckReshuffleCount'] as int? ?? 0;
  List<Map<String, dynamic>> get players => _players;

  DateTime get playedAt =>
      DateTime.tryParse(_game['finishedAt'] as String? ?? '') ?? savedAt;

  String get matchupLabel {
    if (_players.length < 2) return '?';
    final a = _players[0]['wrestlerName'] as String? ?? '?';
    final b = _players[1]['wrestlerName'] as String? ?? '?';
    return '$a vs $b';
  }

  bool get isDraw => finishReason == 'draw';

  /// 勝者のレスラー名（DRAWの場合は'DRAW'、不明な場合は'?'）。
  String get winnerLabel {
    if (isDraw) return 'DRAW';
    final winner = _players
        .where((p) => p['playerId'] == winnerId)
        .toList();
    if (winner.isEmpty) return '?';
    return (winner.first['wrestlerName'] as String?) ?? '?';
  }

  TechniqueMatchAnalysisSummary get summary =>
      TechniqueMatchAnalysisSummary.fromResults(analysisResults);

  Map<String, dynamic> toJson() => {
    'matchJson': matchJson,
    'analysisResults': analysisResults.map((r) => r.toJson()).toList(),
    'savedAt': savedAt.toIso8601String(),
    'saveStatus': saveStatus,
  };

  factory PlaytestMatchRecord.fromJson(Map<String, dynamic> json) =>
      PlaytestMatchRecord(
        matchJson: (json['matchJson'] as Map).cast<String, dynamic>(),
        analysisResults: ((json['analysisResults'] as List?) ?? const [])
            .map(
              (r) => TechniqueMatchAnalysisResult.fromJson(
                (r as Map).cast<String, dynamic>(),
              ),
            )
            .toList(),
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
        saveStatus: json['saveStatus'] as String? ?? 'saved',
      );
}

/// Technique Match Analytics専用のローカル保存リポジトリ。
class PlaytestMatchRepository {
  static const _key = 'playtest_analytics_history_v1';

  /// 【暫定上限】Firestore導入前のローカル保存件数上限。古いものから破棄する。
  static const int maxEntries = 100;

  Future<List<PlaytestMatchRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final records = <PlaytestMatchRecord>[];
    for (final item in raw) {
      try {
        records.add(
          PlaytestMatchRecord.fromJson(jsonDecode(item) as Map<String, dynamic>),
        );
      } catch (_) {
        // 壊れたエントリはスキップして残りを読み込む
        // （`LocalTechniqueDeckRepository`と同じ方針）。
      }
    }
    return records;
  }

  /// 試合を保存する。同じ`gameId`が既に存在する場合は置き換える。
  Future<void> save(PlaytestMatchRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    raw.removeWhere((item) {
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        final matchJson = (decoded['matchJson'] as Map?)?.cast<String, dynamic>();
        final game = (matchJson?['game'] as Map?)?.cast<String, dynamic>();
        return game?['gameId'] == record.gameId;
      } catch (_) {
        return false;
      }
    });
    raw.add(jsonEncode(record.toJson()));
    while (raw.length > maxEntries) {
      raw.removeAt(0);
    }
    await prefs.setStringList(_key, raw);
  }
}
