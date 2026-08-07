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

import 'technique_cpu_decision_trace.dart';
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
///
/// **LEGACY / deprecated fields**: [recoveryPower]（休息システム廃止により
/// 常に無効果）・[restsUsed]（休息廃止によりカウント対象の行動自体が
/// 発生しないため常に0）は、既存JSONログ・分析ツールとの互換性維持のため
/// 残しているが、次期`schemaVersion`での削除候補（詳細は docs/history/
/// technique_deck_rule_history.md）。新しい用途へ転用しないこと。
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

/// 【Phase 8.5A-2 ⑫】ターン数を「試合時間」表示へ変換する。
///
/// 実時間のタイマーを復活させるものではなく、`turnCount * 30`秒という
/// 完全に見た目上の換算（1ターン=30秒相当という演出上の目安）。画面表示
/// （Technique Matchの試合画面・結果画面）とJSONログの`matchTimeDisplay`
/// で同じ関数を使い、表記が食い違わないようにする。
String formatMatchTime(int turnCount) {
  final totalSeconds = turnCount * 30;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

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
    // **LEGACY / deprecated**: 1ターン30秒のリアルタイム制限（TIME OVER）は
    // Phase 8.5Aで廃止済みのため、この値は呼び出し側で常に0が渡される。
    // 既存JSONログ・分析ツールとの互換性維持のため`game.timeOverCount`
    // キーは残しているが、次期schemaVersionでの削除候補（詳細はdocs/history/
    // technique_deck_rule_history.md）。新しい用途へ転用しないこと。
    required int timeOverCount,
    required List<TechniqueMatchPlayerSummary> players,
    required List<TechniqueDeckDefinition> decks,
    required List<TechniqueMatchTurnEntry> turns,
    List<TechniqueCpuDecisionTrace> cpuTraces = const [],
    // 【Phase 8.5A-2 ⑩】画面表示のバージョンとJSONログを常に一致させる
    // ため、呼び出し側（TechniqueMatchScreen）からAppBuildInfoの値を
    // そのまま渡す。省略時はgameVersionと同じ値を使う（後方互換）。
    String? appVersion,
    String? buildLabel,
    // 【Phase 8.5A-2 ⑫】ターン数から換算した試合内時間（実時間の
    // タイマーではなく、演出上の目安表示用）。elapsedSecondsは実プレイ
    // 時間として引き続き使う（意味を変えず、命名だけ明確化する）。
    int? matchTimeSeconds,
    String? matchTimeDisplay,
    int? elapsedRealSeconds,
  }) {
    final winnerId = state.winnerIndex != null ? players[state.winnerIndex!].playerId : null;
    // 【Phase 8.5A-2】決着した技のcardIdを、勝者が最後に宣言した
    // declareAttack／declareFinisherのターン記録から逆引きする（従来は
    // 常にnullだった）。フォール／ギブアップ／フィニッシャーいずれの決着
    // でも、直前の宣言エントリが決着技そのものになる。
    String? finishingCardId;
    if (state.winnerIndex != null) {
      final winnerWrestlerId = state.playerAt(state.winnerIndex!).wrestlerId;
      for (final turn in turns.reversed) {
        if (turn.actorId == winnerWrestlerId &&
            (turn.action == 'declareAttack' || turn.action == 'declareFinisher') &&
            turn.cardId != null) {
          finishingCardId = turn.cardId;
          break;
        }
      }
    }
    return {
      'game': {
        'gameId': gameId,
        'schemaVersion': schemaVersion,
        'gameVersion': gameVersion,
        'appVersion': appVersion ?? gameVersion,
        'buildLabel': buildLabel,
        'rulesVersion': rulesVersion,
        'mode': 'techniqueMatch',
        'opponentType': opponentType,
        'cpuDifficulty': cpuDifficulty,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'winnerId': winnerId,
        'finishReason': state.isDraw ? 'draw' : (state.winReason ?? ''),
        'finishingCardId': finishingCardId,
        'turns': state.turnNumber,
        // 【Phase 8.5A-2 ⑫】elapsedSecondsは既存フィールド名を維持したまま
        // （後方互換）、意味の重複を避けるためelapsedRealSecondsも併記する
        // （同じ値。実プレイの経過秒数）。matchTimeSeconds/matchTimeDisplay
        // は「ターン数×30秒」の演出上の換算値で、実時間タイマーではない。
        'elapsedSeconds': elapsedSeconds,
        'elapsedRealSeconds': elapsedRealSeconds ?? elapsedSeconds,
        'matchTimeSeconds': matchTimeSeconds ?? state.turnNumber * 30,
        'matchTimeDisplay': matchTimeDisplay ?? formatMatchTime(state.turnNumber),
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
      // 【Phase 8.5A-2】CPUの意思決定ログ（候補技・スコア・不採用理由・
      // 選択理由・ラリー/ComboSpeedのスナップショット等）。CPUが関与しない
      // 対戦（人間同士）では常に空配列。
      'cpuTraces': cpuTraces.map((t) => t.toJson()).toList(),
      'summary': {
        'rawLog': state.log,
      },
    };
  }
}

/// [WrestlerPosture]をJSON用の文字列へ変換する薄いヘルパー
/// （enum名をそのまま使うがUI層から見えやすい場所に置く）。
String techniqueMatchPostureJsonLabel(WrestlerPosture posture) => _postureLabel(posture);
