import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../wrestler_editor/editor_screens.dart';
import '../wrestler_editor/models.dart';
import '../wrestler_editor/repository.dart';
import 'balance_diagnostics.dart';
import 'deck_balance_models.dart';
import 'deck_balance_report.dart';
import 'deck_balance_simulator.dart';
import 'level_match_deck_builder.dart';
import 'level_match_engine.dart';
import 'report_export.dart';

const _gold = Color(0xffffc857);
const _red = Color(0xffff5c5c);

/// Ver.1.0: Deck Simulator（デッキバランスシミュレーター）。
/// レスラー・技のバランス調整をデータに基づいて行うための管理画面。
class DeckBalanceScreen extends StatefulWidget {
  const DeckBalanceScreen({super.key, this.repository});
  final LocalWrestlerRepository? repository;

  @override
  State<DeckBalanceScreen> createState() => _DeckBalanceScreenState();
}

enum _Tab { overview, moves, wrestlers, aiReport }

class _DeckBalanceScreenState extends State<DeckBalanceScreen> {
  late final LocalWrestlerRepository repository =
      widget.repository ?? LocalWrestlerRepository();
  List<WrestlerDefinition>? wrestlers;

  WrestlerDefinition? playerA;
  WrestlerDefinition? playerB;
  CpuDifficulty cpuDifficulty = CpuDifficulty.normal;
  int matches = 1000;
  SeedMode seedMode = SeedMode.random;
  int fixedSeed = 1;
  MatchResourceMode resourceMode = MatchResourceMode.energy;
  bool? signatureOncePerMatch;
  BasicCardPolicy basicCardPolicy = BasicCardPolicy.unlimitedReuse;
  EnergySurplusPolicy energySurplusPolicy = EnergySurplusPolicy.none;
  int? startingLevel;
  int startingHeat = 0;
  int startingHp = 0;

  bool running = false;
  DeckBalanceReport? report;
  _Tab tab = _Tab.overview;

  @override
  void initState() {
    super.initState();
    repository.loadAll().then((items) {
      if (!mounted) return;
      setState(() {
        wrestlers = items;
        if (items.length >= 2) {
          playerA = items[0];
          playerB = items[1];
        }
      });
    });
  }

  Future<void> _run() async {
    final a = playerA, b = playerB;
    if (a == null || b == null) return;
    setState(() {
      running = true;
      report = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final sim = DeckBalanceSimulator(repository.moves);
    final result = sim.run(DeckSimConfig(
      playerA: a,
      playerB: b,
      cpuDifficulty: cpuDifficulty,
      matches: matches,
      seedMode: seedMode,
      fixedSeed: fixedSeed,
      resourceMode: resourceMode,
      signatureOncePerMatch: signatureOncePerMatch,
      basicCardPolicy: basicCardPolicy,
      energySurplusPolicy: energySurplusPolicy,
      startingLevel: startingLevel,
      startingHeat: startingHeat == 0 ? null : startingHeat,
      startingHp: startingHp == 0 ? null : startingHp,
    ));
    if (!mounted) return;
    setState(() {
      report = result;
      running = false;
      tab = _Tab.overview;
    });
  }

  String get _prettyJson {
    final r = report;
    if (r == null) return '{}';
    return const JsonEncoder.withIndent('  ').convert(r.toJson(repository.moves));
  }

  Future<void> _downloadJson() async {
    final messenger = ScaffoldMessenger.of(context);
    final name =
        'onm_deck_sim_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.json';
    final ok = await downloadTextFile(name, _prettyJson);
    if (!mounted) return;
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: _prettyJson));
      messenger.showSnackBar(const SnackBar(content: Text('JSONをコピーしました')));
    } else {
      messenger.showSnackBar(SnackBar(content: Text('$name を保存しました')));
    }
  }

  Future<void> _downloadCsv(String content, String suffix) async {
    final r = report;
    if (r == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final name =
        'onm_deck_sim_${suffix}_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.csv';
    final ok = await downloadTextFile(name, content);
    if (!mounted) return;
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: content));
      messenger.showSnackBar(SnackBar(content: Text('$suffix CSVをコピーしました')));
    } else {
      messenger.showSnackBar(SnackBar(content: Text('$name を保存しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deck Simulator（デッキバランス）')),
      body: wrestlers == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _configForm(),
                const SizedBox(height: 12),
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
                if (report != null) ..._resultsSection(report!),
              ],
            ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    color: const Color(0xff211527),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: _gold)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  Widget _configForm() {
    final list = wrestlers!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('対戦カード', [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<WrestlerDefinition>(
                  initialValue: playerA,
                  decoration: const InputDecoration(labelText: 'Player A'),
                  items: [
                    for (final w in list)
                      DropdownMenuItem(value: w, child: Text(w.name)),
                  ],
                  onChanged: running ? null : (v) => setState(() => playerA = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<WrestlerDefinition>(
                  initialValue: playerB,
                  decoration: const InputDecoration(labelText: 'Player B'),
                  items: [
                    for (final w in list)
                      DropdownMenuItem(value: w, child: Text(w.name)),
                  ],
                  onChanged: running ? null : (v) => setState(() => playerB = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _deckPreview(playerA)),
              const SizedBox(width: 12),
              Expanded(child: _deckPreview(playerB)),
            ],
          ),
        ]),
        _section('CPU思考 / 試合数 / Seed', [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _dropdown<CpuDifficulty>(
                label: 'CPU思考',
                value: cpuDifficulty,
                items: CpuDifficulty.values,
                labelOf: (v) => switch (v) {
                  CpuDifficulty.normal => 'NORMAL',
                  CpuDifficulty.strong => 'STRONG',
                  CpuDifficulty.random => 'RANDOM',
                },
                onChanged: (v) => setState(() => cpuDifficulty = v),
              ),
              _dropdown<int>(
                label: '試合数',
                value: matches,
                items: const [100, 500, 1000, 5000, 10000],
                labelOf: (v) => '$v',
                onChanged: (v) => setState(() => matches = v),
              ),
              _dropdown<SeedMode>(
                label: 'Seed',
                value: seedMode,
                items: SeedMode.values,
                labelOf: (v) => v == SeedMode.fixed ? '固定' : 'ランダム',
                onChanged: (v) => setState(() => seedMode = v),
              ),
              if (seedMode == SeedMode.fixed)
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    initialValue: '$fixedSeed',
                    decoration: const InputDecoration(labelText: '固定Seed値'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        fixedSeed = int.tryParse(v) ?? fixedSeed,
                  ),
                ),
            ],
          ),
        ]),
        _section('ルール / AIオプション', [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _dropdown<MatchResourceMode>(
                label: 'ルール',
                value: resourceMode,
                items: MatchResourceMode.values,
                labelOf: (v) => v == MatchResourceMode.energy ? 'energy' : 'classic',
                onChanged: (v) => setState(() => resourceMode = v),
              ),
              _dropdown<bool>(
                label: '固有技1試合1回',
                value: signatureOncePerMatch ?? true,
                items: const [true, false],
                labelOf: (v) => v ? 'ON' : 'OFF',
                onChanged: (v) => setState(() => signatureOncePerMatch = v),
              ),
              _dropdown<BasicCardPolicy>(
                label: '通常技の扱い',
                value: basicCardPolicy,
                items: BasicCardPolicy.values,
                labelOf: (v) => switch (v) {
                  BasicCardPolicy.discardAfterUse => '使い切り',
                  BasicCardPolicy.recycleToDeck => '山札へ戻す',
                  BasicCardPolicy.unlimitedReuse => '使い回し可',
                  BasicCardPolicy.reducedCost => 'コスト軽減',
                },
                onChanged: (v) => setState(() => basicCardPolicy = v),
                width: 200,
              ),
              _dropdown<EnergySurplusPolicy>(
                label: '余剰エネルギー活用',
                value: energySurplusPolicy,
                items: EnergySurplusPolicy.values,
                labelOf: (v) => switch (v) {
                  EnergySurplusPolicy.none => 'なし',
                  EnergySurplusPolicy.heatConversion => 'HEAT変換',
                  EnergySurplusPolicy.attributeConversion => '属性変換',
                  EnergySurplusPolicy.burstAction => 'ラッシュ技',
                },
                onChanged: (v) => setState(() => energySurplusPolicy = v),
                width: 200,
              ),
            ],
          ),
        ]),
        _section('開始状態', [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _dropdown<int>(
                label: '開始レベル',
                value: startingLevel ?? 1,
                items: const [1, 2, 3, 4, 5, 6],
                labelOf: (v) => '$v',
                onChanged: (v) => setState(() => startingLevel = v),
              ),
              SizedBox(
                width: 140,
                child: TextFormField(
                  initialValue: '$startingHeat',
                  decoration: const InputDecoration(labelText: '初期HEAT(0=既定)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => startingHeat = int.tryParse(v) ?? 0,
                ),
              ),
              SizedBox(
                width: 140,
                child: TextFormField(
                  initialValue: '$startingHp',
                  decoration: const InputDecoration(labelText: '初期HP(0=既定/満タン)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => startingHp = int.tryParse(v) ?? 0,
                ),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  /// デッキ構成（属性別カード枚数）は現状 LevelMatchDeckBuilder が
  /// レスラー/技定義から自動生成する（手動編集用の永続フィールドは未実装）。
  /// ここでは自動生成結果をプレビュー表示し、調整はレスラーエディタ
  /// （技のコスト・威力・レベル構成）で行う導線を示す。
  Widget _deckPreview(WrestlerDefinition? w) {
    if (w == null) return const SizedBox.shrink();
    const builder = LevelMatchDeckBuilder();
    final build = builder.buildEnergyMode(
      wrestler: w,
      moves: repository.moves,
      owner: 'preview',
    );
    return Card(
      color: const Color(0xff1a1220),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(w.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              [
                for (final a in MoveAttribute.values)
                  if ((build.counts[a] ?? 0) > 0)
                    '${_attrLabel(a)}${build.counts[a]}',
              ].join(' / '),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      WrestlerEditScreen(initial: w, repository: repository),
                ),
              ),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('レスラーエディタで編集'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required void Function(T) onChanged,
    double width = 170,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item, child: Text(labelOf(item))),
      ],
      onChanged: running ? null : (v) { if (v != null) onChanged(v); },
    ),
  );

  List<Widget> _resultsSection(DeckBalanceReport r) {
    return [
      Wrap(
        spacing: 8,
        children: [
          for (final t in _Tab.values)
            ChoiceChip(
              label: Text(switch (t) {
                _Tab.overview => '概要',
                _Tab.moves => '技分析',
                _Tab.wrestlers => 'レスラー分析',
                _Tab.aiReport => 'AIレポート',
              }),
              selected: tab == t,
              onSelected: (_) => setState(() => tab = t),
            ),
        ],
      ),
      const SizedBox(height: 12),
      switch (tab) {
        _Tab.overview => _overviewTab(r),
        _Tab.moves => _movesTab(r),
        _Tab.wrestlers => _wrestlersTab(r),
        _Tab.aiReport => _aiReportTab(r),
      },
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _downloadJson,
              icon: const Icon(Icons.download),
              label: const Text('JSON保存'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _downloadCsv(r.toCsvMoves(), 'moves'),
              icon: const Icon(Icons.table_chart),
              label: const Text('技CSV'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _downloadCsv(r.toCsvWrestlers(), 'wrestlers'),
              icon: const Icon(Icons.table_chart),
              label: const Text('レスラーCSV'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _downloadCsv(r.toCsvSummary(), 'summary'),
              icon: const Icon(Icons.table_chart),
              label: const Text('概要CSV'),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _overviewTab(DeckBalanceReport r) {
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    String num(double v) => v.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metric('総試合数', '${r.matches}'),
        _metric('${r.config.playerA.name} 勝率', pct(r.winRateA)),
        _metric('${r.config.playerB.name} 勝率', pct(r.winRateB)),
        _metric('引き分け率', pct(r.drawRate)),
        _metric('平均ターン数', num(r.avgTurns)),
        _metric('平均HEAT', num(r.avgHeat)),
        _metric('平均レベル', num(
          (r.wrestlerStats[r.config.playerA.id]?.avgLevel ?? 0) +
              (r.wrestlerStats[r.config.playerB.id]?.avgLevel ?? 0),
        )),
        _metric('フィニッシャー発動率', pct(r.finisherTriggerRate)),
        _metric('フィニッシャー成功率', pct(r.finisherSuccessRate)),
        _metric('フォール率(平均試行/試合)', num(r.pinRate)),
        _metric('ギブアップ率(平均試行/試合)', num(r.submissionRate)),
        _metric('KO(レフェリーストップ)率', pct(r.koRate)),
        _metric('時間切れ率', pct(r.timeUpRate)),
        _metric('逆転が起きた試合の割合', pct(r.comebackRate)),
        _metric('平均逆転回数', num(r.avgComebacks)),
        _metric('平均使用技種類数', num(r.avgDistinctMoves)),
        _metric('カウンター成功率', pct(r.counterSuccessRate)),
        _metric('候補0件発生率(平均回数/試合)', num(r.noUsableMoveRate)),
        _metric('平均エネルギー余剰率', pct(r.overallEnergySurplusRate)),
        for (final a in MoveAttribute.values)
          _metric('  └ ${_attrLabel(a)}属性 余剰率', pct(r.energySurplusRateFor(a))),
        _metric('平均観戦評価', '${r.avgEntertainmentScore.toStringAsFixed(1)}点'),
        const SizedBox(height: 8),
        const Text('決着理由内訳', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final e in r.finishReasonCounts.entries)
          _metric(e.key, '${e.value} (${pct(e.value / r.matches)})'),
      ],
    );
  }

  String _attrLabel(MoveAttribute a) => switch (a) {
    MoveAttribute.strike => '打',
    MoveAttribute.throwMove => '投',
    MoveAttribute.submission => '関',
    MoveAttribute.counter => '返',
    MoveAttribute.rough => 'ラフ',
    MoveAttribute.aerial => '飛',
  };

  Widget _movesTab(DeckBalanceReport r) {
    final rows = r.moveStats.entries.toList()
      ..sort((a, b) => b.value.totalUses.compareTo(a.value.totalUses));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('技名')),
          DataColumn(label: Text('Lv')),
          DataColumn(label: Text('使用率')),
          DataColumn(label: Text('未使用率')),
          DataColumn(label: Text('平均ダメージ')),
          DataColumn(label: Text('平均HEAT')),
          DataColumn(label: Text('平均コスト')),
          DataColumn(label: Text('使用時勝率')),
          DataColumn(label: Text('カウンター率')),
          DataColumn(label: Text('フィニッシュ率')),
          DataColumn(label: Text('貢献度')),
          DataColumn(label: Text('期待値')),
          DataColumn(label: Text('AI評価')),
        ],
        rows: [
          for (final e in rows)
            DataRow(cells: [
              DataCell(Text(e.value.name)),
              DataCell(Text('${e.value.level ?? "-"}')),
              DataCell(_ratedCell(e.value.usageRate, unusedStyle: false)),
              DataCell(_ratedCell(e.value.unusedRate, unusedStyle: true)),
              DataCell(Text(e.value.avgDamage.toStringAsFixed(1))),
              DataCell(Text(e.value.avgHeatGain.toStringAsFixed(1))),
              DataCell(Text(e.value.avgCost.toStringAsFixed(1))),
              DataCell(Text('${(e.value.winRateWhenUsed * 100).toStringAsFixed(0)}%')),
              DataCell(Text('${(e.value.counterRate * 100).toStringAsFixed(0)}%')),
              DataCell(Text('${(e.value.finishRate * 100).toStringAsFixed(0)}%')),
              DataCell(Text(e.value.contributionScore.toStringAsFixed(0))),
              DataCell(Text(e.value.expectedValuePerMatch.toStringAsFixed(1))),
              DataCell(Text(repository.moves[e.key] == null
                  ? '-'
                  : e.value.aiEvaluation(repository.moves[e.key]!).toStringAsFixed(0))),
            ]),
        ],
      ),
    );
  }

  Widget _ratedCell(double rate, {required bool unusedStyle}) {
    // 実装④: 未使用率90%以上は赤、使用率80%以上は黄で表示。
    Color? color;
    if (unusedStyle && rate >= 0.9) color = _red;
    if (!unusedStyle && rate >= 0.8) color = _gold;
    return Text(
      '${(rate * 100).toStringAsFixed(0)}%',
      style: color == null ? null : TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }

  Widget _wrestlersTab(DeckBalanceReport r) {
    final rows = r.wrestlerStats.entries.toList()
      ..sort((a, b) => b.value.winRate.compareTo(a.value.winRate));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('レスラー')),
          DataColumn(label: Text('勝率')),
          DataColumn(label: Text('平均試合時間')),
          DataColumn(label: Text('平均レベル')),
          DataColumn(label: Text('平均与ダメ')),
          DataColumn(label: Text('平均被ダメ')),
          DataColumn(label: Text('フォール率')),
          DataColumn(label: Text('ギブアップ率')),
          DataColumn(label: Text('KO率')),
          DataColumn(label: Text('フィニッシャー成功率')),
          DataColumn(label: Text('得意属性')),
          DataColumn(label: Text('苦手属性')),
          DataColumn(label: Text('通常技依存率')),
          DataColumn(label: Text('固有技依存率')),
          DataColumn(label: Text('観戦評価')),
        ],
        rows: [
          for (final e in rows)
            DataRow(cells: [
              DataCell(Text(e.value.name)),
              DataCell(Text('${(e.value.winRate * 100).toStringAsFixed(1)}%')),
              DataCell(Text(e.value.avgTurns.toStringAsFixed(1))),
              DataCell(Text(e.value.avgLevel.toStringAsFixed(2))),
              DataCell(Text(e.value.avgDamageDealt.toStringAsFixed(1))),
              DataCell(Text(e.value.avgDamageTaken.toStringAsFixed(1))),
              DataCell(Text(e.value.pinRate.toStringAsFixed(2))),
              DataCell(Text(e.value.submissionRate.toStringAsFixed(2))),
              DataCell(Text('${(e.value.koRate * 100).toStringAsFixed(1)}%')),
              DataCell(Text('${(e.value.finisherSuccessRate * 100).toStringAsFixed(0)}%')),
              DataCell(Text(e.value.favoriteAttribute == null
                  ? '-'
                  : _attrLabel(e.value.favoriteAttribute!))),
              DataCell(Text(e.value.weakestAttribute == null
                  ? '-'
                  : _attrLabel(e.value.weakestAttribute!))),
              DataCell(Text('${(e.value.basicDependencyRate * 100).toStringAsFixed(0)}%')),
              DataCell(Text('${(e.value.signatureDependencyRate * 100).toStringAsFixed(0)}%')),
              DataCell(Text(e.value.avgEntertainmentScore.toStringAsFixed(1))),
            ]),
        ],
      ),
    );
  }

  Widget _aiReportTab(DeckBalanceReport r) {
    final findings = r.generateAiReport(repository.moves);
    final diagnosis = diagnoseBalance(
      report: r,
      wrestlersById: {r.config.playerA.id: r.config.playerA, r.config.playerB.id: r.config.playerB},
      moves: repository.moves,
    );
    final allFindings = [
      ...diagnosis.wrestlers.expand((w) => w.findings),
      ...diagnosis.overallFindings,
      ...findings,
    ];
    if (allFindings.isEmpty) {
      return const Text('特筆すべき偏りは検出されませんでした。', style: TextStyle(color: Colors.white70));
    }
    return Column(
      children: [
        if (diagnosis.strongWrestlers.isNotEmpty || diagnosis.weakWrestlers.isNotEmpty)
          Card(
            color: const Color(0xff211527),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final w in diagnosis.strongWrestlers)
                    Chip(
                      label: Text('${w.name} 強すぎ(${(w.winRate * 100).toStringAsFixed(1)}%)'),
                      backgroundColor: const Color(0xff3a1620),
                    ),
                  for (final w in diagnosis.weakWrestlers)
                    Chip(
                      label: Text('${w.name} 弱すぎ(${(w.winRate * 100).toStringAsFixed(1)}%)'),
                      backgroundColor: const Color(0xff1a2a3a),
                    ),
                ],
              ),
            ),
          ),
        for (final f in allFindings)
          Card(
            color: switch (f.severity) {
              'critical' => const Color(0xff3a1620),
              'warn' => const Color(0xff33291a),
              _ => const Color(0xff211527),
            },
            child: ListTile(
              leading: Icon(switch (f.severity) {
                'critical' => Icons.error,
                'warn' => Icons.warning_amber,
                _ => Icons.info_outline,
              }, color: switch (f.severity) {
                'critical' => _red,
                'warn' => _gold,
                _ => Colors.white70,
              }),
              title: Text(f.subject, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${f.observation}\n改善案: ${f.suggestion}'),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }

  Widget _metric(String label, String value) => Card(
    child: ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _gold),
      ),
    ),
  );
}
