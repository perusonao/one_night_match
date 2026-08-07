/// Playtest Analytics Phase A: ローカル保存された試合ログ＋自動診断結果を
/// 確認するための画面。Debug分析画面から遷移する。
///
/// 【Firestore非依存】このフェーズではFirebase/Firestoreを一切使わず、
/// [PlaytestMatchRepository]（SharedPreferences）から読み込むのみ。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../level_match/report_export.dart';
import 'playtest_match_repository.dart';
import 'technique_match_analysis_result.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);
const _critical = Color(0xffff5252);
const _warning = Color(0xffffc857);
const _info = Color(0xff8fa3c8);

Color _severityColor(TechniqueMatchAnalysisSeverity severity) => switch (severity) {
  TechniqueMatchAnalysisSeverity.critical => _critical,
  TechniqueMatchAnalysisSeverity.error => const Color(0xffff8a3d),
  TechniqueMatchAnalysisSeverity.warning => _warning,
  TechniqueMatchAnalysisSeverity.info => _info,
};

String _severityLabel(TechniqueMatchAnalysisSeverity severity) => switch (severity) {
  TechniqueMatchAnalysisSeverity.critical => 'CRITICAL',
  TechniqueMatchAnalysisSeverity.error => 'ERROR',
  TechniqueMatchAnalysisSeverity.warning => 'WARNING',
  TechniqueMatchAnalysisSeverity.info => 'INFO',
};

/// 一覧画面。
class PlaytestAnalyticsScreen extends StatefulWidget {
  const PlaytestAnalyticsScreen({super.key});

  @override
  State<PlaytestAnalyticsScreen> createState() => _PlaytestAnalyticsScreenState();
}

class _PlaytestAnalyticsScreenState extends State<PlaytestAnalyticsScreen> {
  List<PlaytestMatchRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await PlaytestMatchRepository().loadAll();
    if (!mounted) return;
    records.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    setState(() => _records = records);
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(title: const Text('Playtest Analytics')),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: records.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            '保存された試合がありません。Technique Matchを1試合プレイすると、'
                            '終了時に自動でここへ記録されます。',
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _SummaryHeader(records: records),
                        const SizedBox(height: 20),
                        Text(
                          '試合一覧（${records.length}件）',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        for (final record in records) _MatchListTile(record: record),
                      ],
                    ),
            ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.records});

  final List<PlaytestMatchRecord> records;

  @override
  Widget build(BuildContext context) {
    final total = records.length;
    final criticalTotal = records.fold<int>(0, (sum, r) => sum + r.summary.criticalCount);
    final warningTotal = records.fold<int>(0, (sum, r) => sum + r.summary.warningCount);
    final drawCount = records.where((r) => r.isDraw).length;
    final drawRate = total == 0 ? 0.0 : drawCount / total;
    final avgSeconds = total == 0
        ? 0
        : records.fold<int>(0, (sum, r) => sum + r.matchTimeSeconds) / total;
    final avgMinutes = (avgSeconds / 60).toStringAsFixed(1);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: [
        _StatTile(label: '総試合数', value: '$total'),
        _StatTile(label: 'CRITICAL件数', value: '$criticalTotal', color: _critical),
        _StatTile(label: 'WARNING件数', value: '$warningTotal', color: _warning),
        _StatTile(label: 'DRAW率', value: '${(drawRate * 100).toStringAsFixed(1)}%'),
        _StatTile(label: '平均試合時間', value: '$avgMinutes分'),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color ?? _gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchListTile extends StatelessWidget {
  const _MatchListTile({required this.record});

  final PlaytestMatchRecord record;

  @override
  Widget build(BuildContext context) {
    final summary = record.summary;
    final finishLabel = record.isDraw ? 'DRAW' : record.finishReason;
    return Card(
      color: summary.criticalCount > 0
          ? _critical.withValues(alpha: 0.12)
          : null,
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlaytestMatchDetailScreen(record: record)),
        ),
        leading: CircleAvatar(
          backgroundColor: _severityColor(summary.overallSeverity),
          child: Text(
            summary.criticalCount > 0
                ? '${summary.criticalCount}'
                : summary.warningCount > 0
                ? '${summary.warningCount}'
                : '✓',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(record.matchupLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_formatDateTime(record.playedAt)} ・ ${record.appVersion}'
          '${record.buildLabel != null ? ' (${record.buildLabel})' : ''}\n'
          '勝者: ${record.winnerLabel} ・ $finishLabel ・ ${record.matchTimeDisplay}',
        ),
        isThreeLine: true,
        trailing: Icon(
          summary.overallSeverity == TechniqueMatchAnalysisSeverity.critical
              ? Icons.error
              : summary.overallSeverity == TechniqueMatchAnalysisSeverity.warning
              ? Icons.warning_amber
              : Icons.check_circle_outline,
          color: _severityColor(summary.overallSeverity),
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// 試合詳細画面: 概要→自動診断→選手統計→CPU Trace→ターンログ。
class PlaytestMatchDetailScreen extends StatelessWidget {
  const PlaytestMatchDetailScreen({super.key, required this.record});

  final PlaytestMatchRecord record;

  Future<void> _downloadJson(BuildContext context) async {
    final content = const JsonEncoder.withIndent('  ').convert(record.matchJson);
    final filename = 'one-night-match-technique-${record.gameId}.json';
    final ok = await downloadTextFile(filename, content);
    if (!context.mounted) return;
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: content));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ダウンロード非対応のため、JSONをクリップボードにコピーしました')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('試合ログを $filename としてダウンロードしました')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cpuTraces = ((record.matchJson['cpuTraces'] as List?) ?? const [])
        .map((t) => (t as Map).cast<String, dynamic>())
        .toList();
    final turns = ((record.matchJson['turns'] as List?) ?? const [])
        .map((t) => (t as Map).cast<String, dynamic>())
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(record.matchupLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '試合ログをJSONで保存',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _downloadJson(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('概要'),
          _OverviewSection(record: record),
          const _SectionHeader('自動診断'),
          _DiagnosticsSection(results: record.analysisResults),
          const _SectionHeader('選手統計'),
          _PlayerStatsSection(players: record.players),
          const _SectionHeader('CPU Trace'),
          _CpuTraceSection(cpuTraces: cpuTraces),
          const _SectionHeader('ターンログ'),
          _TurnLogSection(turns: turns),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _pink),
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.record});

  final PlaytestMatchRecord record;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('gameId', record.gameId),
      ('日時', _formatDateTime(record.playedAt)),
      ('バージョン', record.appVersion),
      ('Build', record.buildLabel ?? '-'),
      ('対戦相手', record.opponentType == 'cpu' ? 'CPU（${record.cpuDifficulty ?? '-'}）' : '人間'),
      ('対戦カード', record.matchupLabel),
      ('勝者', record.winnerLabel),
      ('決着方法', record.isDraw ? 'DRAW' : record.finishReason),
      ('ターン数', '${record.turns}'),
      ('試合時間', record.matchTimeDisplay),
      ('山札再構築回数', '${record.deckReshuffleCount}'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white70))),
                    Expanded(child: Text(value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({required this.results});

  final List<TechniqueMatchAnalysisResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('自動診断で異常は検出されませんでした。'),
        ),
      );
    }
    final sorted = [...results]..sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return Column(
      children: [
        for (final result in sorted)
          Card(
            color: _severityColor(result.severity).withValues(alpha: 0.14),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _severityColor(result.severity),
                child: Text(
                  _severityLabel(result.severity).substring(0, 1),
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(result.title),
              subtitle: Text(
                '${result.diagnosticCode}'
                '${result.turnNumber != null ? ' ・ Turn${result.turnNumber}' : ''}'
                '${result.playerId != null ? ' ・ ${result.playerId}' : ''}\n'
                '${result.description}',
              ),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }
}

class _PlayerStatsSection extends StatelessWidget {
  const _PlayerStatsSection({required this.players});

  final List<Map<String, dynamic>> players;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final player in players)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${player['wrestlerName']}${player['isCpu'] == true ? '（CPU）' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _stat('HP', '${player['finalHp']}/${player['maxHp']}'),
                      _stat('HEAT', '${player['finalHeat']}'),
                      _stat('使用技', '${player['movesUsed']}'),
                      _stat('返技', '${player['countersUsed']}'),
                      _stat('フォール', '${player['pinAttempts']}'),
                      _stat('ギブアップ', '${player['submissionAttempts']}'),
                      _stat('フィニッシャー', '${player['finisherDeclarations']}'),
                      _stat('キックアウト', '${player['kickOuts']}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _stat(String label, String value) => Text('$label: $value', style: const TextStyle(fontSize: 13));
}

class _CpuTraceSection extends StatelessWidget {
  const _CpuTraceSection({required this.cpuTraces});

  final List<Map<String, dynamic>> cpuTraces;

  @override
  Widget build(BuildContext context) {
    if (cpuTraces.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('CPU Decision Traceはありません（人間同士の対戦）。'),
        ),
      );
    }
    return Column(
      children: [
        for (final trace in cpuTraces)
          _CpuTraceTile(trace: trace),
      ],
    );
  }
}

class _CpuTraceTile extends StatelessWidget {
  const _CpuTraceTile({required this.trace});

  final Map<String, dynamic> trace;

  @override
  Widget build(BuildContext context) {
    final chosen = (trace['chosen'] as Map?)?.cast<String, dynamic>() ?? const {};
    final legalMoveCount = trace['legalMoveCount'];
    final action = chosen['action'] as String?;
    final suspicious =
        legalMoveCount is int &&
        legalMoveCount > 0 &&
        (action == 'passTurn' || action == 'endRally');
    return Card(
      color: suspicious ? _critical.withValues(alpha: 0.14) : null,
      child: ExpansionTile(
        title: Text(
          'Turn${trace['turnNumber']} P${trace['playerIndex']} '
          '${trace['decisionType']} → ${chosen['action']}'
          '${chosen['cardName'] != null ? '（${chosen['cardName']}）' : ''}',
        ),
        subtitle: Text(
          'legalMoveCount: ${legalMoveCount ?? '-'}'
          '${trace['noLegalMoveReasonCode'] != null ? ' ・ 理由: ${trace['noLegalMoveReasonCode']}' : ''}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('reason: ${chosen['reason']}'),
                if (trace['bestEligibleCardName'] != null)
                  Text('最良合法候補: ${trace['bestEligibleCardName']}（score=${trace['bestEligibleScore']}）'),
                const SizedBox(height: 6),
                Text('candidates:', style: Theme.of(context).textTheme.bodySmall),
                for (final candidate in ((trace['candidates'] as List?) ?? const []))
                  Text(
                    '  - ${candidate['cardName']} eligible=${candidate['eligible']} score=${candidate['score']}'
                    '${candidate['ineligibleReason'] != null ? ' (${candidate['ineligibleReason']})' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnLogSection extends StatelessWidget {
  const _TurnLogSection({required this.turns});

  final List<Map<String, dynamic>> turns;

  @override
  Widget build(BuildContext context) {
    if (turns.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('ターンログがありません。')),
      );
    }
    return Column(
      children: [
        for (final entry in turns)
          ListTile(
            dense: true,
            leading: Text('T${entry['turn']}', style: const TextStyle(fontSize: 12)),
            title: Text('${entry['actorId']} ${entry['action']}${entry['cardName'] != null ? '（${entry['cardName']}）' : ''}'),
            subtitle: Text(
              '${entry['message'] ?? ''}\n'
              'HP ${entry['hpBefore']}→${entry['hpAfter']} ・ HEAT ${entry['heatBefore']}→${entry['heatAfter']}',
            ),
            isThreeLine: true,
          ),
      ],
    );
  }
}
