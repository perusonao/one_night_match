import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../wrestler_editor/models.dart';
import '../wrestler_editor/repository.dart';
import 'level_match_simulator.dart';
import 'report_export.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);

/// Ver.0.6: CPU対CPUの自動対戦を回し、フォール/ギブアップの発生状況を検証する画面。
class LevelMatchSimulatorScreen extends StatefulWidget {
  const LevelMatchSimulatorScreen({super.key, this.repository});
  final LocalWrestlerRepository? repository;

  @override
  State<LevelMatchSimulatorScreen> createState() =>
      _LevelMatchSimulatorScreenState();
}

class _LevelMatchSimulatorScreenState
    extends State<LevelMatchSimulatorScreen> {
  late final LocalWrestlerRepository repository =
      widget.repository ?? LocalWrestlerRepository();
  List<WrestlerDefinition>? wrestlers;
  int matchesPerPair = 20;
  bool running = false;
  Map<String, dynamic>? report;

  @override
  void initState() {
    super.initState();
    repository.loadAll().then((items) {
      if (mounted) setState(() => wrestlers = items);
    });
  }

  Future<void> _run() async {
    final list = wrestlers;
    if (list == null || list.length < 2) return;
    setState(() {
      running = true;
      report = null;
    });
    // UI に反映させるため1フレーム待ってから実行。
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final simulator = LevelMatchSimulator(repository.moves);
    final result = simulator.run(
      wrestlers: list,
      matchesPerPair: matchesPerPair,
      seed: DateTime.now().millisecondsSinceEpoch % 100000,
    );
    if (!mounted) return;
    setState(() {
      report = result.toJson();
      running = false;
    });
  }

  String get _prettyJson =>
      const JsonEncoder.withIndent('  ').convert(report);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _prettyJson));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('JSONをコピーしました')));
    }
  }

  Future<void> _download() async {
    final name =
        'onm_sim_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.json';
    final ok = await downloadTextFile(name, _prettyJson);
    if (!mounted) return;
    if (!ok) {
      await _copy(); // 非Web はクリップボードへ
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name を保存しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = report?['summary'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(title: const Text('対戦シミュレータ（検証）')),
      body: wrestlers == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'CPU対CPUを自動対戦させ、フォール／ギブアップが発生するか検証します。',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('1組あたり試合数: '),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: matchesPerPair,
                      items: const [5, 20, 50, 100]
                          .map(
                            (n) =>
                                DropdownMenuItem(value: n, child: Text('$n')),
                          )
                          .toList(),
                      onChanged: running
                          ? null
                          : (value) => setState(
                              () => matchesPerPair = value ?? 20,
                            ),
                    ),
                    const Spacer(),
                    Text(
                      '総試合数 ${wrestlers!.length * (wrestlers!.length - 1) * matchesPerPair}',
                      style: const TextStyle(color: _gold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: running ? null : _run,
                  icon: running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_circle),
                  label: Text(running ? 'シミュレーション中…' : 'シミュレーション実行'),
                ),
                const SizedBox(height: 16),
                if (summary != null) ...[
                  _highlight(
                    'フォール発生率',
                    _pct(summary['matchesWithAnyPinAttempt']),
                    'ギブアップ発生率 ${_pct(summary['matchesWithAnySubmissionAttempt'])}',
                  ),
                  _metric('総試合数', '${summary['totalMatches']}'),
                  _metric('3カウント決着率', _pct(summary['pinfallRate'])),
                  _metric('ギブアップ決着率', _pct(summary['submissionRate'])),
                  _metric('消耗決着率', _pct(summary['exhaustionRate'])),
                  _metric(
                    'フィニッシャー使用試合率',
                    _pct(summary['matchesWithAnyFinisher']),
                  ),
                  _metric('平均ターン数', _num(summary['avgTurns'])),
                  _metric('平均フォール試行', _num(summary['avgPinAttempts'])),
                  _metric('平均キックアウト', _num(summary['avgKickOuts'])),
                  _metric('平均ギブアップ判定', _num(summary['avgSubmissionAttempts'])),
                  _metric('平均ロープブレイク', _num(summary['avgRopeBreaks'])),
                  _metric('平均最終HEAT', _num(summary['avgFinalHeat'])),
                  _metric('消耗発生率', _pct(summary['exhaustionOccurredRate'])),
                  const SizedBox(height: 8),
                  const Text(
                    'レスラー別勝利数',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final entry
                      in (summary['winsByWrestler'] as Map).entries)
                    _metric('${entry.key}', '${entry.value}'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy),
                          label: const Text('JSONをコピー'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _download,
                          icon: const Icon(Icons.download),
                          label: const Text('JSONを保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _highlight(String label, String value, String sub) => Card(
    color: const Color(0xff2a1c33),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: _pink,
            ),
          ),
          Text(sub, style: const TextStyle(color: _gold)),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value) => Card(
    child: ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: _gold,
        ),
      ),
    ),
  );

  String _pct(Object? v) =>
      v is num ? '${(v * 100).toStringAsFixed(1)}%' : '-';
  String _num(Object? v) => v is num ? v.toStringAsFixed(2) : '-';
}
