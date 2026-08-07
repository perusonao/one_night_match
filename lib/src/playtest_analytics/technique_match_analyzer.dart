/// Playtest Analytics Phase A: Technique Matchの試合ログ（
/// `TechniqueMatchJsonLog.build()`が返すMapと同じスキーマ）を解析し、
/// [TechniqueMatchAnalysisResult]の一覧を返す純粋なDartロジック。
///
/// 【設計方針】UI（Flutter Widget）・Firestore・ローカルストレージのいずれにも
/// 依存しない。入力はJSON Map、出力はプレーンなDartオブジェクトのリストのみ。
/// これにより、試合終了直後の自動解析だけでなく、将来的に既存JSONログ
/// （手動ダウンロードしたファイル）を読み込んでの再解析にもそのまま使い回せる。
///
/// 【CPU側との二重実装禁止について】CRITICAL_LEGAL_MOVE_PASS /
/// CRITICAL_LEGAL_MOVE_END_RALLYの判定は、STEP7で`TechniqueCpuDecisionTrace`
/// へ追加された`legalMoveCount`（`TechniqueMatchCpu._decideRallyAction`が
/// 実際に評価した`candidates`から算出した値）をそのまま利用する。「どの技が
/// 合法か」をAnalyzer側で独自に再計算することはしない（CPUのエネルギー
/// コスト・Combo Speed・targetState判定等のルールをAnalyzer側に複製すると、
/// 二重実装によりCPUロジック変更時に解析側が追従できず不整合を起こすため）。
library;

import 'technique_match_analysis_result.dart';

/// 各診断ルールの閾値。実プレイデータが増えたら調整する前提の暫定値
/// （根拠は各定数のコメントを参照）。
class TechniqueMatchAnalyzerThresholds {
  const TechniqueMatchAnalyzerThresholds._();

  /// CRITICAL_CPU_NO_ATTACK: このターン数以上進んでCPUが1度も技を使って
  /// いなければ異常とみなす（数ターム程度の初動の遅れは正常な範囲のため、
  /// ある程度の猶予を持たせる）。
  static const int minTurnsForCpuNoAttack = 10;

  /// WARNING_LONG_MATCH: `matchTimeSeconds`はターン数×30秒の演出上の換算値
  /// （[formatMatchTime]参照）。30分（1800秒）＝60ターン相当を「長すぎる
  /// 試合」の目安とする。
  static const int longMatchTurns = 60;

  /// WARNING_COUNTER_HEAVY: 1人のプレイヤーの`countersUsed`がこの値以上
  /// なら「返技過多」とみなす。
  static const int counterHeavyThreshold = 15;

  /// WARNING_NO_PLAYABLE_MOVE_HIGH: 合法技0件だった意思決定の比率
  /// （`legalMoveCount == 0`のtrace数 ÷ 全ラリー意思決定trace数）。
  static const double noPlayableMoveHighRatio = 0.4;

  /// WARNING_NO_PLAYABLE_MOVE_HIGH: 母数が小さいと比率が不安定になるため、
  /// 最低限このtrace数が無ければ判定しない。
  static const int noPlayableMoveMinSamples = 5;

  /// WARNING_ZERO_HEAT: このターン数以上進んでもCPUのfinalHeatが0のままなら
  /// 異常とみなす。
  static const int zeroHeatMinTurns = 6;
}

/// Technique Matchの試合ログ（JSON Map）を解析するAnalyzer本体。
class TechniqueMatchAnalyzer {
  const TechniqueMatchAnalyzer();

  /// [matchJson]は`TechniqueMatchJsonLog.build()`が返すMapと同じスキーマ
  /// （`game` / `players` / `turns` / `cpuTraces`キーを持つ）を想定する。
  List<TechniqueMatchAnalysisResult> analyze(Map<String, dynamic> matchJson) {
    final game = (matchJson['game'] as Map?)?.cast<String, dynamic>() ?? const {};
    final players = ((matchJson['players'] as List?) ?? const [])
        .map((p) => (p as Map).cast<String, dynamic>())
        .toList();
    final cpuTraces = ((matchJson['cpuTraces'] as List?) ?? const [])
        .map((t) => (t as Map).cast<String, dynamic>())
        .toList();

    final results = <TechniqueMatchAnalysisResult>[];
    results.addAll(_detectLegalMoveViolations(cpuTraces, players));
    results.addAll(_detectCpuNoAttack(game, players));
    results.addAll(_detectDraw(game));
    results.addAll(_detectLongMatch(game));
    results.addAll(_detectCounterHeavy(players));
    results.addAll(_detectNoPlayableMoveHigh(cpuTraces));
    results.addAll(_detectFinisherDominance(game, players));
    results.addAll(_detectZeroHeat(game, players));
    results.addAll(_detectDeckReshuffle(game));
    return results;
  }

  // ============================================================
  // CRITICAL_LEGAL_MOVE_PASS / CRITICAL_LEGAL_MOVE_END_RALLY
  // ============================================================
  //
  // STEP7で`_decideRallyAction`のpassTurn／endRally分岐にはデバッグビルド
  // 限定の`assert()`不変条件が既に入っている（legalMoveCount==0でなければ
  // 到達しないはず）。この診断は、その不変条件がreleaseビルドや未知の経路で
  // 破られていないかを、保存された試合ログから事後的に検出するもの。
  List<TechniqueMatchAnalysisResult> _detectLegalMoveViolations(
    List<Map<String, dynamic>> cpuTraces,
    List<Map<String, dynamic>> players,
  ) {
    final results = <TechniqueMatchAnalysisResult>[];
    for (final trace in cpuTraces) {
      final chosen = (trace['chosen'] as Map?)?.cast<String, dynamic>();
      final action = chosen?['action'] as String?;
      if (action != 'passTurn' && action != 'endRally') continue;
      final legalMoveCount = trace['legalMoveCount'] as int?;
      if (legalMoveCount == null || legalMoveCount <= 0) continue;

      final playerIndex = trace['playerIndex'] as int?;
      final playerId = playerIndex == null
          ? null
          : (playerIndex == 0 ? 'A' : 'B');
      final code = action == 'passTurn'
          ? 'CRITICAL_LEGAL_MOVE_PASS'
          : 'CRITICAL_LEGAL_MOVE_END_RALLY';
      final actionLabel = action == 'passTurn' ? 'passTurn' : 'endRally';
      results.add(
        TechniqueMatchAnalysisResult(
          severity: TechniqueMatchAnalysisSeverity.critical,
          diagnosticCode: code,
          title: '合法技があるのに$actionLabelを選択',
          description:
              'Turn${trace['turnNumber']} ${playerId ?? '?'}: '
              '合法な技候補が$legalMoveCount件あったにもかかわらず、'
              'CPUは$actionLabelを選択した。'
              '${trace['bestEligibleCardName'] != null ? '最良の合法候補は「${trace['bestEligibleCardName']}」（score=${trace['bestEligibleScore']}）。' : ''}'
              'CPU選択ロジックの不変条件違反の疑いがある。',
          turnNumber: trace['turnNumber'] as int?,
          playerId: playerId,
          relatedCardId: trace['bestEligibleCardId'] as String?,
          actualValue: legalMoveCount,
          threshold: 0,
          metadata: {
            'chosenAction': action,
            if (trace['bestEligibleScore'] != null)
              'bestEligibleScore': trace['bestEligibleScore'],
            if (trace['noLegalMoveReasonCode'] != null)
              'noLegalMoveReasonCode': trace['noLegalMoveReasonCode'],
          },
        ),
      );
    }
    return results;
  }

  // ============================================================
  // CRITICAL_CPU_NO_ATTACK
  // ============================================================
  List<TechniqueMatchAnalysisResult> _detectCpuNoAttack(
    Map<String, dynamic> game,
    List<Map<String, dynamic>> players,
  ) {
    final turns = game['turns'] as int? ?? 0;
    if (turns < TechniqueMatchAnalyzerThresholds.minTurnsForCpuNoAttack) {
      return const [];
    }
    final results = <TechniqueMatchAnalysisResult>[];
    for (var i = 0; i < players.length; i++) {
      final player = players[i];
      if (player['isCpu'] != true) continue;
      final movesUsed = player['movesUsed'] as int? ?? 0;
      if (movesUsed != 0) continue;
      final playerId = i == 0 ? 'A' : 'B';
      results.add(
        TechniqueMatchAnalysisResult(
          severity: TechniqueMatchAnalysisSeverity.critical,
          diagnosticCode: 'CRITICAL_CPU_NO_ATTACK',
          title: 'CPUが一度も攻撃していない',
          description:
              '${player['wrestlerName'] ?? playerId}（CPU）は$turnsターン経過しても'
              '一度も技を使用しなかった（movesUsed=0）。',
          playerId: playerId,
          actualValue: movesUsed,
          threshold: TechniqueMatchAnalyzerThresholds.minTurnsForCpuNoAttack,
          metadata: {'turns': turns},
        ),
      );
    }
    return results;
  }

  // ============================================================
  // WARNING_DRAW
  // ============================================================
  List<TechniqueMatchAnalysisResult> _detectDraw(Map<String, dynamic> game) {
    if (game['finishReason'] != 'draw') return const [];
    return [
      TechniqueMatchAnalysisResult(
        severity: TechniqueMatchAnalysisSeverity.warning,
        diagnosticCode: 'WARNING_DRAW',
        title: '試合がDRAWで終了',
        description: '勝敗が決着せず引き分け（${game['turns']}ターン）で終了した。',
        actualValue: game['turns'] as num?,
      ),
    ];
  }

  // ============================================================
  // WARNING_LONG_MATCH
  // ============================================================
  List<TechniqueMatchAnalysisResult> _detectLongMatch(Map<String, dynamic> game) {
    final turns = game['turns'] as int? ?? 0;
    if (turns < TechniqueMatchAnalyzerThresholds.longMatchTurns) return const [];
    return [
      TechniqueMatchAnalysisResult(
        severity: TechniqueMatchAnalysisSeverity.warning,
        diagnosticCode: 'WARNING_LONG_MATCH',
        title: '試合時間が長すぎる',
        description:
            '試合時間換算${game['matchTimeDisplay'] ?? '?'}（$turnsターン）は'
            '想定より長い。膠着・決着ロジックの偏りの可能性がある。',
        actualValue: turns,
        threshold: TechniqueMatchAnalyzerThresholds.longMatchTurns,
      ),
    ];
  }

  // ============================================================
  // WARNING_COUNTER_HEAVY
  // ============================================================
  List<TechniqueMatchAnalysisResult> _detectCounterHeavy(
    List<Map<String, dynamic>> players,
  ) {
    final results = <TechniqueMatchAnalysisResult>[];
    for (var i = 0; i < players.length; i++) {
      final player = players[i];
      final countersUsed = player['countersUsed'] as int? ?? 0;
      if (countersUsed < TechniqueMatchAnalyzerThresholds.counterHeavyThreshold) {
        continue;
      }
      final playerId = i == 0 ? 'A' : 'B';
      results.add(
        TechniqueMatchAnalysisResult(
          severity: TechniqueMatchAnalysisSeverity.warning,
          diagnosticCode: 'WARNING_COUNTER_HEAVY',
          title: '返技回数が極端に多い',
          description:
              '${player['wrestlerName'] ?? playerId}の返技回数が'
              '$countersUsed回に達している。返技バランスの偏りの可能性がある。',
          playerId: playerId,
          actualValue: countersUsed,
          threshold: TechniqueMatchAnalyzerThresholds.counterHeavyThreshold,
        ),
      );
    }
    return results;
  }

  // ============================================================
  // WARNING_NO_PLAYABLE_MOVE_HIGH
  // ============================================================
  //
  // 「ラリー意思決定」（declareAttack/declareFinisher/passTurn/endRally、
  // いずれも`_decideRallyAction`が生成しSTEP7で`legalMoveCount`を必ず
  // 付与しているdecisionType）のうち、合法技0件だった比率を見る。
  List<TechniqueMatchAnalysisResult> _detectNoPlayableMoveHigh(
    List<Map<String, dynamic>> cpuTraces,
  ) {
    const rallyDecisionTypes = {
      'declareAttack',
      'declareFinisher',
      'passTurn',
      'endRally',
    };
    final rallyTraces = cpuTraces
        .where((t) => rallyDecisionTypes.contains(t['decisionType']))
        .where((t) => t['legalMoveCount'] != null)
        .toList();
    if (rallyTraces.length < TechniqueMatchAnalyzerThresholds.noPlayableMoveMinSamples) {
      return const [];
    }
    final zeroCount = rallyTraces.where((t) => (t['legalMoveCount'] as int) == 0).length;
    final ratio = zeroCount / rallyTraces.length;
    if (ratio < TechniqueMatchAnalyzerThresholds.noPlayableMoveHighRatio) {
      return const [];
    }
    return [
      TechniqueMatchAnalysisResult(
        severity: TechniqueMatchAnalysisSeverity.warning,
        diagnosticCode: 'WARNING_NO_PLAYABLE_MOVE_HIGH',
        title: '合法技なしのターン率が高い',
        description:
            'CPUの意思決定$zeroCount/${rallyTraces.length}件'
            '（${(ratio * 100).toStringAsFixed(0)}%）で合法な技が1つも無かった。'
            'デッキ構成・エネルギーコストバランスの偏りの可能性がある。',
        actualValue: double.parse(ratio.toStringAsFixed(3)),
        threshold: TechniqueMatchAnalyzerThresholds.noPlayableMoveHighRatio,
        metadata: {'zeroLegalMoveCount': zeroCount, 'totalRallyDecisions': rallyTraces.length},
      ),
    ];
  }

  // ============================================================
  // WARNING_FINISHER_DOMINANCE
  // ============================================================
  //
  // 【解釈についての注記】「フィニッシャー決着へ極端に偏っている」を
  // 単一試合から機械的に判定するため、この試合が「フィニッシャー勝利」で
  // 終わり、かつ両プレイヤーとも一度もフォール／ギブアップを狙わなかった
  // （pinAttempts・submissionAttemptsが両者0）場合を対象とする。通常決着の
  // 選択肢が一切試みられずフィニッシャーのみで試合が終わっている、という
  // 狭い条件。より緩やかな「フィニッシャー偏重」傾向は、Analytics画面側の
  // 集計（フィニッシャー決着率）で試合横断的に確認する。
  List<TechniqueMatchAnalysisResult> _detectFinisherDominance(
    Map<String, dynamic> game,
    List<Map<String, dynamic>> players,
  ) {
    if (game['finishReason'] != 'フィニッシャー勝利') return const [];
    final totalPinAttempts = players.fold<int>(
      0,
      (sum, p) => sum + (p['pinAttempts'] as int? ?? 0),
    );
    final totalSubmissionAttempts = players.fold<int>(
      0,
      (sum, p) => sum + (p['submissionAttempts'] as int? ?? 0),
    );
    if (totalPinAttempts + totalSubmissionAttempts > 0) return const [];
    return [
      TechniqueMatchAnalysisResult(
        severity: TechniqueMatchAnalysisSeverity.warning,
        diagnosticCode: 'WARNING_FINISHER_DOMINANCE',
        title: 'フィニッシャー決着への偏り',
        description:
            'この試合はフィニッシャー勝利で決着したが、フォール・ギブアップは'
            '一度も試みられなかった。通常決着ルートが機能していない可能性がある。',
        actualValue: 0,
        metadata: {'finishReason': game['finishReason']},
      ),
    ];
  }

  // ============================================================
  // WARNING_ZERO_HEAT
  // ============================================================
  List<TechniqueMatchAnalysisResult> _detectZeroHeat(
    Map<String, dynamic> game,
    List<Map<String, dynamic>> players,
  ) {
    final turns = game['turns'] as int? ?? 0;
    if (turns < TechniqueMatchAnalyzerThresholds.zeroHeatMinTurns) return const [];
    final results = <TechniqueMatchAnalysisResult>[];
    for (var i = 0; i < players.length; i++) {
      final player = players[i];
      if (player['isCpu'] != true) continue;
      final finalHeat = player['finalHeat'] as int? ?? 0;
      if (finalHeat != 0) continue;
      final playerId = i == 0 ? 'A' : 'B';
      results.add(
        TechniqueMatchAnalysisResult(
          severity: TechniqueMatchAnalysisSeverity.warning,
          diagnosticCode: 'WARNING_ZERO_HEAT',
          title: 'CPUのHEATがほぼ増えていない',
          description:
              '${player['wrestlerName'] ?? playerId}（CPU）は$turnsターン経過しても'
              'HEATが0のままだった。行動量が極端に少ない可能性がある。',
          playerId: playerId,
          actualValue: finalHeat,
          threshold: 0,
        ),
      );
    }
    return results;
  }

  // ============================================================
  // INFO_DECK_RESHUFFLE
  // ============================================================
  List<TechniqueMatchAnalysisResult> _detectDeckReshuffle(Map<String, dynamic> game) {
    final count = game['deckReshuffleCount'] as int? ?? 0;
    if (count <= 0) return const [];
    return [
      TechniqueMatchAnalysisResult(
        severity: TechniqueMatchAnalysisSeverity.info,
        diagnosticCode: 'INFO_DECK_RESHUFFLE',
        title: '山札再構築が発生',
        description: '試合中に山札の再構築が$count回発生した。',
        actualValue: count,
      ),
    ];
  }
}
