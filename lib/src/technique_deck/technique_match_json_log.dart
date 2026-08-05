/// Technique Match: 試合ログのJSON出力（ゲームサイクル整理ラウンド 優先度9）。
///
/// `TechniqueMatchScreen`が試合中に収集した構造化ログ（[TechniqueMatchTurnEntry]
/// のリスト）と、試合開始/終了時刻・プレイヤー情報・デッキ情報などを
/// 組み合わせて、ユーザー指定のJSONスキーマへ変換する。
///
/// 【実装範囲についての正直な注記】`turns`配列の各エントリは、エンジン
/// （`TechniqueMatchEngine`）が生成する`TechniqueMatchState.log`の自由文字列を
/// そのままエンジン内部で構造化しているわけではない。エンジンは意図的に
/// 「状態遷移を返すだけの純粋関数」として設計されており、今回のラウンドで
/// エンジンの返り値の型を変更することは（大規模な既存テスト資産への影響が
/// 大きいため）行わなかった。代わりに`TechniqueMatchScreen`側で、各アクション
/// 呼び出しの前後で状態をスナップショットし、追加されたログ行と合わせて
/// [TechniqueMatchTurnEntry]を都度記録する方式を採った。そのため
/// `cardId`/`cardName`など一部フィールドはUI層で分かる範囲のベストエフォート
/// （不明な場合はnull）である。
library;

import 'technique_deck_deck.dart';
import 'technique_deck_models.dart' show WrestlerPosture;
import 'technique_match_state.dart';

/// 1アクション分の構造化ログ（`turns[]`の1要素）。
class TechniqueMatchTurnEntry {
  const TechniqueMatchTurnEntry({
    required this.turn,
    required this.chain,
    required this.timestamp,
    this.remainingTurnSeconds,
    required this.actorId,
    required this.phase,
    required this.action,
    this.cardId,
    this.cardName,
    required this.energyBeforeActor,
    required this.energyAfterActor,
    required this.hpBefore,
    required this.hpAfter,
    required this.heatBefore,
    required this.heatAfter,
    required this.targetPostureBefore,
    required this.targetPostureAfter,
    required this.message,
    this.details,
  });

  final int turn;
  final int chain;
  final DateTime timestamp;
  final int? remainingTurnSeconds;
  final String actorId;
  final String phase;
  final String action;
  final String? cardId;
  final String? cardName;
  final int energyBeforeActor;
  final int energyAfterActor;
  final int hpBefore;
  final int hpAfter;
  final int heatBefore;
  final int heatAfter;
  final String targetPostureBefore;
  final String targetPostureAfter;
  final String message;
  final Map<String, dynamic>? details;

  Map<String, dynamic> toJson() => {
    'turn': turn,
    'chain': chain,
    'timestamp': timestamp.toIso8601String(),
    if (remainingTurnSeconds != null) 'remainingTurnSeconds': remainingTurnSeconds,
    'actorId': actorId,
    'phase': phase,
    'action': action,
    if (cardId != null) 'cardId': cardId,
    if (cardName != null) 'cardName': cardName,
    'energyBefore': energyBeforeActor,
    'energyAfter': energyAfterActor,
    'hpBefore': hpBefore,
    'hpAfter': hpAfter,
    'heatBefore': heatBefore,
    'heatAfter': heatAfter,
    'targetPostureBefore': targetPostureBefore,
    'targetPostureAfter': targetPostureAfter,
    'message': message,
    if (details != null) 'details': details,
  };
}

/// 1プレイヤー分の集計サマリー（`players[]`の1要素）。
class TechniqueMatchPlayerSummary {
  const TechniqueMatchPlayerSummary({
    required this.playerId,
    required this.wrestlerId,
    required this.wrestlerName,
    required this.maxHp,
    required this.finalHp,
    required this.recoveryPower,
    required this.finalHeat,
    required this.posture,
    required this.isCpu,
    required this.movesUsed,
    required this.countersUsed,
    required this.restsUsed,
    required this.pinAttempts,
    required this.submissionAttempts,
    required this.finisherDeclarations,
    required this.kickOuts,
    required this.ropeBreaks,
  });

  final String playerId;
  final String wrestlerId;
  final String wrestlerName;
  final int maxHp;
  final int finalHp;
  final int recoveryPower;
  final int finalHeat;
  final String posture;
  final bool isCpu;
  final int movesUsed;
  final int countersUsed;
  final int restsUsed;
  final int pinAttempts;
  final int submissionAttempts;
  final int finisherDeclarations;
  final int kickOuts;
  final int ropeBreaks;

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'wrestlerId': wrestlerId,
    'wrestlerName': wrestlerName,
    'maxHp': maxHp,
    'finalHp': finalHp,
    'recoveryPower': recoveryPower,
    'finalHeat': finalHeat,
    'posture': posture,
    'isCpu': isCpu,
    'movesUsed': movesUsed,
    'countersUsed': countersUsed,
    'restsUsed': restsUsed,
    'pinAttempts': pinAttempts,
    'submissionAttempts': submissionAttempts,
    'finisherDeclarations': finisherDeclarations,
    'kickOuts': kickOuts,
    'ropeBreaks': ropeBreaks,
  };
}

String _postureLabel(WrestlerPosture posture) => posture.name;

/// [TechniqueMatchScreen]から呼び出される、JSON全体の組み立て。
class TechniqueMatchJsonLog {
  static Map<String, dynamic> build({
    required String gameId,
    required String schemaVersion,
    required String gameVersion,
    required String rulesVersion,
    required String opponentType,
    required String? cpuDifficulty,
    required DateTime startedAt,
    required DateTime finishedAt,
    required TechniqueMatchState state,
    required int elapsedSeconds,
    required int timeOverCount,
    required List<TechniqueMatchPlayerSummary> players,
    required List<TechniqueDeckDefinition> decks,
    required List<TechniqueMatchTurnEntry> turns,
  }) {
    final winnerId = state.winnerIndex != null ? players[state.winnerIndex!].playerId : null;
    return {
      'game': {
        'gameId': gameId,
        'schemaVersion': schemaVersion,
        'gameVersion': gameVersion,
        'rulesVersion': rulesVersion,
        'mode': 'techniqueMatch',
        'opponentType': opponentType,
        'cpuDifficulty': cpuDifficulty,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'winnerId': winnerId,
        'finishReason': state.isDraw ? 'draw' : (state.winReason ?? ''),
        'finishingCardId': null,
        'turns': state.turnNumber,
        'elapsedSeconds': elapsedSeconds,
        'timeOverCount': timeOverCount,
        'deckReshuffleCount': state.playerA.reshuffleCount + state.playerB.reshuffleCount,
      },
      'players': players.map((p) => p.toJson()).toList(),
      'decks': decks
          .map(
            (d) => {
              'deckId': d.id,
              'deckName': d.name,
              'wrestlerId': d.wrestlerId,
              'cards': d.entries
                  .map((e) => {'instanceId': e.instanceId, 'cardId': e.cardId, 'cardType': e.cardType.name})
                  .toList(),
            },
          )
          .toList(),
      'turns': turns.map((t) => t.toJson()).toList(),
      'summary': {
        'rawLog': state.log,
      },
    };
  }
}

/// [WrestlerPosture]をJSON用の文字列へ変換する薄いヘルパー
/// （enum名をそのまま使うがUI層から見えやすい場所に置く）。
String techniqueMatchPostureJsonLabel(WrestlerPosture posture) => _postureLabel(posture);
