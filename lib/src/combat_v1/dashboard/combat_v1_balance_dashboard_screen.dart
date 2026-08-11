/// Balance Dashboard 1A — Fixed Default Run / Read-only Dashboard
/// （docs/design/combat_v1_balance_dashboard_1a.md）。
///
/// Debug分析画面から遷移する開発用画面。「Run Default Simulation」を明示的に
/// 押すと、固定default config（misaki/jack/akari/reina、100 matches/matchup、
/// seed 12345、RandomLegal vs RandomLegal、maxActions 500）でbatch
/// simulationを実行し、結果を表示する。画面を開いただけでは自動実行しない
/// （6章「No Auto Run」）。
///
/// 設定編集・比較・chart・CSV/JSON exportはDashboard 1Bへ先送り（17章）。
library;

import 'package:flutter/material.dart';

import '../simulation/batch/combat_v1_batch_simulation_config.dart';
import 'combat_v1_balance_dashboard_formatting.dart';
import 'combat_v1_balance_dashboard_view_model.dart';
import 'combat_v1_balance_simulation_service.dart';

const _gold = Color(0xffffc857);
const _pink = Color(0xffff477e);
const _cardSurface = Color(0xff211527);
const _healthWarning = Color(0xffffc857);
const _healthError = Color(0xffff5c5c);
const _mirrorTint = Color(0xff2a2035);

enum _DashboardRunStatus { idle, running, success, error }

/// Dashboard 1Aの画面本体。
class CombatV1BalanceDashboardScreen extends StatefulWidget {
  const CombatV1BalanceDashboardScreen({super.key, CombatV1BalanceRunFunction? runFunction})
    : runFunction = runFunction ?? _defaultRunFunction;

  /// production既定はservice経由。widget testでは差し替え可能
  /// （25章「Test Injection」）。
  final CombatV1BalanceRunFunction runFunction;

  static Future<CombatV1BalanceRunOutput> _defaultRunFunction() =>
      const CombatV1BalanceSimulationService().run();

  @override
  State<CombatV1BalanceDashboardScreen> createState() =>
      _CombatV1BalanceDashboardScreenState();
}

class _CombatV1BalanceDashboardScreenState
    extends State<CombatV1BalanceDashboardScreen> {
  final CombatV1BatchSimulationConfig _config =
      combatV1BalanceDashboardDefaultConfig();

  _DashboardRunStatus _status = _DashboardRunStatus.idle;
  CombatV1BalanceRunOutput? _lastOutput;
  String? _errorMessage;

  bool get _isRunning => _status == _DashboardRunStatus.running;

  int get _totalMatches =>
      _config.wrestlerIds.length * _config.wrestlerIds.length * _config.matchesPerMatchup;

  Future<void> _run() async {
    // 48章「Run Button Reentrancy」——二重run禁止。
    if (_isRunning) return;
    setState(() {
      _status = _DashboardRunStatus.running;
      _errorMessage = null;
    });
    // 20・21章「Frame Yield / Main Thread Limitation」——sync runner開始前に
    // spinner/disabled buttonが最低1 frame描画されるようにする。
    await WidgetsBinding.instance.endOfFrame;
    try {
      final output = await widget.runFunction();
      if (!mounted) return;
      setState(() {
        _lastOutput = output;
        _status = _DashboardRunStatus.success;
      });
    } catch (error) {
      // 47章「Structured Invariant is Not Run Error」——ここでcatchするのは
      // service/runner呼び出し自体が投げたexceptionのみ。batch result内の
      // invariantViolation件数は正常なsuccess resultとして扱う（run
      // exceptionにしない）。
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _status = _DashboardRunStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Combat V1 Balance Dashboard')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _DevBadge(),
                const SizedBox(height: 12),
                const _IntroText(),
                const SizedBox(height: 16),
                _ConfigSummaryCard(config: _config, totalMatches: _totalMatches),
                const SizedBox(height: 16),
                _RunControls(
                  status: _status,
                  totalMatches: _totalMatches,
                  onRun: _run,
                ),
                if (_status == _DashboardRunStatus.error) ...[
                  const SizedBox(height: 16),
                  _ErrorPanel(message: _errorMessage ?? '不明なエラーです'),
                ],
                if (_lastOutput != null) ...[
                  const SizedBox(height: 24),
                  _ResultSections(output: _lastOutput!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevBadge extends StatelessWidget {
  const _DevBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: _pink),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '開発用 ・ Balance Analysis',
          style: TextStyle(fontSize: 12, color: _pink, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _IntroText extends StatelessWidget {
  const _IntroText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Combat Ver.1のCPU vs CPU batch simulation結果を確認するための開発用'
      '画面です。ゲーム本編UIではありません。下の固定設定でsimulationを実行し、'
      '結果をこの画面上に表示します。',
      style: TextStyle(color: Colors.white70),
    );
  }
}

class _ConfigSummaryCard extends StatelessWidget {
  const _ConfigSummaryCard({required this.config, required this.totalMatches});

  final CombatV1BatchSimulationConfig config;
  final int totalMatches;

  @override
  Widget build(BuildContext context) {
    final wrestlerNames = config.wrestlerIds
        .map(combatV1DashboardDisplayName)
        .join(' / ');
    final lines = <String>[
      '${config.wrestlerIds.length} wrestlers: $wrestlerNames',
      '${combatV1DashboardPolicyLabel(config.playerAPolicy)} / '
          '${combatV1DashboardPolicyLabel(config.playerBPolicy)}',
      '${config.matchesPerMatchup} matches / matchup',
      '$totalMatches total matches',
      'Seed ${config.masterSeed}',
      'Max Actions ${config.maxActions}',
      'Default Combat V1 Rules',
    ];
    return Card(
      color: _cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Default Run 設定（固定・編集不可）',
              style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('・$line'),
              ),
          ],
        ),
      ),
    );
  }
}

class _RunControls extends StatelessWidget {
  const _RunControls({
    required this.status,
    required this.totalMatches,
    required this.onRun,
  });

  final _DashboardRunStatus status;
  final int totalMatches;
  final VoidCallback onRun;

  bool get _running => status == _DashboardRunStatus.running;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: _running ? null : onRun,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_circle),
          label: Text(_running ? '実行中…' : 'Run Default Simulation'),
        ),
        const SizedBox(height: 6),
        const Text(
          '※ 実行中は画面操作が一時的に停止する場合があります'
          '（main isolate上で同期実行するため）。',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        if (_running) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(
            'Running ${_formatThousands(totalMatches)} simulations…',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ],
    );
  }
}

String _formatThousands(int value) {
  final s = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
    buffer.write(s[i]);
  }
  return buffer.toString();
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _healthError.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error, color: _healthError),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Simulation failed',
                    style: TextStyle(fontWeight: FontWeight.bold, color: _healthError),
                  ),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultSections extends StatelessWidget {
  const _ResultSections({required this.output});

  final CombatV1BalanceRunOutput output;

  @override
  Widget build(BuildContext context) {
    final viewModel = output.viewModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Run Result', 'このrunの実行結果'),
        _RunMetadataPanel(output: output),
        const SizedBox(height: 20),
        _SectionHeader('Summary', 'Global集計'),
        _SummaryCardsGrid(summary: viewModel.globalSummary),
        const SizedBox(height: 20),
        _SectionHeader('Wrestlers', 'レスラー別集計（ランク付けなし）'),
        _WrestlerTable(rows: viewModel.wrestlerRows),
        const SizedBox(height: 20),
        _SectionHeader('Matchup Matrix', '4×4 対戦カード別勝率'),
        _MatrixExplanation(),
        const SizedBox(height: 8),
        _MatchupMatrixView(matrix: viewModel.matchupMatrix),
        const SizedBox(height: 20),
        _SectionHeader('Mirror Matches', '同一レスラー同士の対戦'),
        _MirrorPanel(mirror: viewModel.mirrorSummary),
        const SizedBox(height: 20),
        _SectionHeader('Player A / B', '座席（先手/後手）別集計'),
        _SeatPanel(seat: viewModel.seatSummary),
        const SizedBox(height: 20),
        _SectionHeader('Match Length', '試合の長さ（completed試合のみ）'),
        _LengthPanel(length: viewModel.lengthSummary),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.subtitleJa);

  final String title;
  final String subtitleJa;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _pink),
          ),
          Text(subtitleJa, style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ),
    );
  }
}

class _RunMetadataPanel extends StatelessWidget {
  const _RunMetadataPanel({required this.output});

  final CombatV1BalanceRunOutput output;

  @override
  Widget build(BuildContext context) {
    final run = output.viewModel.runSummary;
    final rows = <(String, String)>[
      ('Seed', '${run.masterSeed}'),
      ('Policies', '${run.playerAPolicyLabel} vs ${run.playerBPolicyLabel}'),
      ('Matches / Matchup', combatV1FormatCount(run.matchesPerMatchup)),
      ('Total', combatV1FormatCount(run.executedMatchCount)),
      ('Max Actions', combatV1FormatCount(run.maxActions)),
      ('Rules', run.rulesLabel),
      ('Runtime', '${output.runtime.inMilliseconds} ms'),
      (
        'Matches / Sec',
        combatV1FormatMatchesPerSecond(run.executedMatchCount, output.runtime),
      ),
      ('Ran At', _formatDateTime(output.ranAt)),
    ];
    return Card(
      color: _cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(label, style: const TextStyle(color: Colors.white70)),
                    ),
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

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class _SummaryCardsGrid extends StatelessWidget {
  const _SummaryCardsGrid({required this.summary});

  final CombatV1DashboardGlobalSummary summary;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _StatTile(
        label: 'Total Matches',
        labelJa: '総試合数',
        value: combatV1FormatCount(summary.totalMatches),
      ),
      _StatTile(
        label: 'Completed',
        labelJa: '完了試合数',
        value: combatV1FormatCount(summary.completedMatches),
      ),
      _StatTile(
        label: 'Player A Win Rate',
        labelJa: 'Player A 勝率',
        value: combatV1FormatPercent(summary.playerAWinRate),
      ),
      _StatTile(
        label: 'Player B Win Rate',
        labelJa: 'Player B 勝率',
        value: combatV1FormatPercent(summary.playerBWinRate),
      ),
      _StatTile(
        label: 'Safety Limit Rate',
        labelJa: 'Safety Limit到達率',
        value: combatV1FormatPercent(summary.safetyLimitRate),
        color: summary.safetyLimitMatches == 0 ? null : _healthWarning,
      ),
      _StatTile(
        label: 'Invariant Violation Rate',
        labelJa: 'Invariant違反率',
        value: combatV1FormatPercent(summary.invariantViolationRate),
        color: summary.invariantViolationMatches == 0 ? null : _healthError,
      ),
      _StatTile(
        label: 'Avg Actions',
        labelJa: '平均action数',
        value: combatV1FormatNullableNumber(summary.avgActions),
      ),
      _StatTile(
        label: 'P90 Actions',
        labelJa: 'action数 P90',
        value: combatV1FormatNullableNumber(summary.p90Actions),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 500
            ? 3
            : 2;
        // 狭幅ほどcard幅が縮み、labelが折り返しやすくなるためaspect ratioを
        // 下げて（cardを縦長にして）overflowを防ぐ（41・42章「Responsive」）。
        final aspectRatio = columns >= 4
            ? 1.75
            : columns == 3
            ? 1.55
            : 1.3;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: aspectRatio,
          children: tiles,
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.labelJa,
    required this.value,
    this.color,
  });

  final String label;
  final String labelJa;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _cardSurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Text(
              labelJa,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color ?? _gold),
            ),
          ],
        ),
      ),
    );
  }
}

class _WrestlerTable extends StatelessWidget {
  const _WrestlerTable({required this.rows});

  final List<CombatV1DashboardWrestlerRow> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Wrestler')),
          DataColumn(label: Text('Win Rate')),
          DataColumn(label: Text('Wins / Completed')),
          DataColumn(label: Text('Player A Win Rate')),
          DataColumn(label: Text('Player B Win Rate')),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                DataCell(Text(row.displayName)),
                DataCell(Text(combatV1FormatPercent(row.completedWinRate))),
                DataCell(
                  Text('${row.wins} / ${row.completedAppearances}'),
                ),
                DataCell(Text(combatV1FormatPercent(row.playerAWinRate))),
                DataCell(Text(combatV1FormatPercent(row.playerBWinRate))),
              ],
            ),
        ],
      ),
    );
  }
}

class _MatrixExplanation extends StatelessWidget {
  const _MatrixExplanation();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '行＝Player A、列＝Player B。セルの勝率は行側レスラーがPlayer Aとして'
      '勝ったcompleted試合の割合です（A vs BとB vs Aは別セル）。',
      style: TextStyle(fontSize: 12, color: Colors.white70),
    );
  }
}

class _MatchupMatrixView extends StatelessWidget {
  const _MatchupMatrixView({required this.matrix});

  final CombatV1DashboardMatchupMatrix matrix;

  @override
  Widget build(BuildContext context) {
    const cellWidth = 128.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        key: const Key('combat_v1_balance_dashboard_matrix_table'),
        border: TableBorder.all(color: Colors.white12),
        defaultColumnWidth: const FixedColumnWidth(cellWidth),
        children: [
          TableRow(
            children: [
              _matrixHeaderCell(''),
              for (final columnId in matrix.wrestlerIds)
                _matrixHeaderCell(combatV1DashboardDisplayName(columnId)),
            ],
          ),
          for (var i = 0; i < matrix.wrestlerIds.length; i++)
            TableRow(
              children: [
                _matrixHeaderCell(combatV1DashboardDisplayName(matrix.wrestlerIds[i])),
                for (final cell in matrix.rows[i]) _MatrixCell(cell: cell),
              ],
            ),
        ],
      ),
    );
  }
}

Widget _matrixHeaderCell(String text) => Padding(
  padding: const EdgeInsets.all(8),
  child: Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
    textAlign: TextAlign.center,
  ),
);

class _MatrixCell extends StatelessWidget {
  const _MatrixCell({required this.cell});

  final CombatV1DashboardMatchupCell cell;

  @override
  Widget build(BuildContext context) {
    final hasHealthNote = cell.safetyLimitMatches > 0 || cell.invariantViolationMatches > 0;
    return Container(
      // 35章「Matrix Color」——勝率高低を赤/緑で意味付けしない。diagonal
      // （mirror）のみsubtleに区別する。
      color: cell.isMirror ? _mirrorTint : null,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            combatV1FormatPercent(cell.completedWinRateForRowWrestler),
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            'n=${cell.completedMatches}',
            style: const TextStyle(fontSize: 10, color: Colors.white38),
          ),
          if (hasHealthNote)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                cell.invariantViolationMatches > 0 ? Icons.error_outline : Icons.warning_amber,
                size: 12,
                color: cell.invariantViolationMatches > 0 ? _healthError : _healthWarning,
              ),
            ),
        ],
      ),
    );
  }
}

class _MirrorPanel extends StatelessWidget {
  const _MirrorPanel({required this.mirror});

  final CombatV1DashboardMirrorSummary mirror;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      (
        'Total / Completed',
        '${combatV1FormatCount(mirror.totalMatches)} / '
            '${combatV1FormatCount(mirror.completedMatches)}',
      ),
      ('Player A Win Rate', combatV1FormatPercent(mirror.playerAWinRate)),
      (
        'Abs. Deviation from 50%',
        combatV1FormatPercent(mirror.absoluteDeviationFromFiftyPercent),
      ),
      ('Safety Limit Rate', combatV1FormatPercent(mirror.safetyLimitRate)),
      ('Invariant Violation Rate', combatV1FormatPercent(mirror.invariantViolationRate)),
    ];
    return _metadataCard(rows);
  }
}

class _SeatPanel extends StatelessWidget {
  const _SeatPanel({required this.seat});

  final CombatV1DashboardSeatSummary seat;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Player A Completed', combatV1FormatCount(seat.playerACompletedMatches)),
      ('Player A Wins', combatV1FormatCount(seat.playerAWins)),
      ('Player A Win Rate', combatV1FormatPercent(seat.playerAWinRate)),
      ('Player B Completed', combatV1FormatCount(seat.playerBCompletedMatches)),
      ('Player B Wins', combatV1FormatCount(seat.playerBWins)),
      ('Player B Win Rate', combatV1FormatPercent(seat.playerBWinRate)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metadataCard(rows),
        const SizedBox(height: 6),
        const Text(
          '※ 現在のEngineではPlayer Aがstarting player（先手）です。',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
      ],
    );
  }
}

class _LengthPanel extends StatelessWidget {
  const _LengthPanel({required this.length});

  final CombatV1DashboardLengthSummary length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
        _distributionCard(length.actionCount),
        const SizedBox(height: 12),
        const Text('Final Turn', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text(
          'Final Turnは最終stateの1始まりターン番号であり、完了したターン数'
          'ではありません。',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        _distributionCard(length.finalTurnNumber),
      ],
    );
  }
}

Widget _distributionCard(CombatV1DashboardDistributionSummary d) {
  final rows = <(String, String)>[
    ('Mean', combatV1FormatNullableNumber(d.mean)),
    ('Median', combatV1FormatNullableNumber(d.median)),
    ('P90', combatV1FormatNullableNumber(d.p90)),
    ('P95', combatV1FormatNullableNumber(d.p95)),
    ('Min', combatV1FormatNullableCount(d.min)),
    ('Max', combatV1FormatNullableCount(d.max)),
  ];
  return _metadataCard(rows);
}

Widget _metadataCard(List<(String, String)> rows) => Card(
  color: _cardSurface,
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: Text(label, style: const TextStyle(color: Colors.white70)),
                ),
                Expanded(child: Text(value)),
              ],
            ),
          ),
      ],
    ),
  ),
);
