/// Balance Dashboard 1B — Editable Config / Presets / Detail / UX Polish
/// （docs/design/combat_v1_balance_dashboard_1b.md）。
///
/// Debug分析画面から遷移する開発用画面。Dashboard 1A（fixed default run /
/// read-only）を拡張し、simulation条件（matchesPerMatchup preset・custom・
/// masterSeed・Player A/B policy・maxActions）をブラウザ上で編集し、
/// matchup単位のdetailを確認できるようにする。wrestler set（canonical
/// 4人）・rules（`const CombatV1RulesConfig()`）は今回も固定・編集不可。
///
/// 画面を開いただけでは自動実行しない（53章「Default First Experience」）。
library;

import 'package:flutter/material.dart';

import '../simulation/batch/combat_v1_batch_matchup.dart';
import '../simulation/batch/combat_v1_batch_simulation_config.dart';
import '../simulation/combat_v1_simulation_policy.dart';
import 'combat_v1_balance_dashboard_formatting.dart';
import 'combat_v1_balance_dashboard_run_config.dart';
import 'combat_v1_balance_dashboard_view_model.dart';
import 'combat_v1_balance_simulation_service.dart';

const _gold = Color(0xffffc857);
const _pink = Color(0xffff477e);
const _cardSurface = Color(0xff211527);
const _healthWarning = Color(0xffffc857);
const _healthError = Color(0xffff5c5c);
const _mirrorTint = Color(0xff2a2035);
const _staleTint = Color(0xff3a2a1a);

/// 320pxのような狭幅を「mobile」とみなすbreakpoint（45〜47章）。
const double _mobileBreakpoint = 600;

enum _DashboardRunStatus { idle, running, success, error }

/// Dashboard 1Bの画面本体。
class CombatV1BalanceDashboardScreen extends StatefulWidget {
  const CombatV1BalanceDashboardScreen({super.key, CombatV1BalanceRunFunction? runFunction})
    : runFunction = runFunction ?? _defaultRunFunction;

  /// production既定はservice経由。widget testでは差し替え可能
  /// （Test Injection、67章)。
  final CombatV1BalanceRunFunction runFunction;

  static Future<CombatV1BalanceRunOutput> _defaultRunFunction(
    CombatV1BatchSimulationConfig config,
  ) => const CombatV1BalanceSimulationService().run(config);

  @override
  State<CombatV1BalanceDashboardScreen> createState() =>
      _CombatV1BalanceDashboardScreenState();
}

class _CombatV1BalanceDashboardScreenState
    extends State<CombatV1BalanceDashboardScreen> {
  // draftConfig vs lastRunConfig（15章「Draft Config vs Last Run
  // Config」）——設定を変更しても既存resultを即消さない。resultは常に
  // lastRunConfigに結び付ける。
  CombatV1BalanceDashboardRunConfig _draft =
      CombatV1BalanceDashboardRunConfig.initial();
  CombatV1BatchSimulationConfig? _lastRunConfig;

  late final TextEditingController _customMatchesController;
  late final TextEditingController _seedController;
  late final TextEditingController _maxActionsController;

  _DashboardRunStatus _status = _DashboardRunStatus.idle;
  CombatV1BalanceRunOutput? _lastOutput;
  String? _errorMessage;

  /// selected matchup cell（screen-local state、44章「Matchup Detail
  /// State」）。domain treeそのものではなくmatchup key（value object）の
  /// みを保持し、表示のたびに最新のviewModelから対応するcellを再導出する
  /// ——新run成功後も同じmatchup keyが存在すれば自然にselectionが維持
  /// される（wrestler setがcanonical固定のため常に存在する）。
  CombatV1Matchup? _selectedMatchup;

  bool get _isRunning => _status == _DashboardRunStatus.running;

  @override
  void initState() {
    super.initState();
    _customMatchesController = TextEditingController(
      text: _draft.customMatchesPerMatchupText,
    );
    _seedController = TextEditingController(text: _draft.masterSeedText);
    _maxActionsController = TextEditingController(text: _draft.maxActionsText);
  }

  @override
  void dispose() {
    _customMatchesController.dispose();
    _seedController.dispose();
    _maxActionsController.dispose();
    super.dispose();
  }

  void _updateDraft(CombatV1BalanceDashboardRunConfig Function(CombatV1BalanceDashboardRunConfig) update) {
    if (_isRunning) return; // 18章「Reentrancy」——running中は編集不可。
    setState(() => _draft = update(_draft));
  }

  /// draft configが最後の成功runと異なるかどうか（16章「Stale Result
  /// UX」）。まだ一度も成功していない場合はfalse（stale表示の対象外）。
  bool get _isStale {
    final lastRun = _lastRunConfig;
    if (lastRun == null) return false;
    if (!_draft.isValid) return true;
    return _draft.matchesPerMatchup != lastRun.matchesPerMatchup ||
        _draft.masterSeed != lastRun.masterSeed ||
        _draft.playerAPolicy != lastRun.playerAPolicy ||
        _draft.playerBPolicy != lastRun.playerBPolicy ||
        _draft.maxActions != lastRun.maxActions;
  }

  /// Run buttonの文言（17章「Run Button」）。
  String get _runButtonLabel {
    if (_isRunning) return '実行中…';
    if (_status == _DashboardRunStatus.success) {
      return _isStale ? 'Run Updated Simulation' : 'Run Again';
    }
    return 'Run Simulation';
  }

  Future<void> _run() async {
    // 18章「Reentrancy」——二重run禁止。
    if (_isRunning) return;
    if (!_draft.isValid) return; // Run buttonがdisabledのため通常到達しない。

    final batchConfig = _draft.toBatchConfig();

    // 21章「Analysis Preset Confirmation」——1000/matchup実行前は確認
    // dialog。Cancelはdialogキャンセルのみ（simulation cancellation機能
    // ではない、25章）。
    if (_draft.requiresRunConfirmation) {
      final confirmed = await _showLargeRunConfirmDialog(
        totalMatches: _draft.totalMatches,
      );
      if (confirmed != true) return; // runner未実行のままreturn。
    }

    await _executeRun(batchConfig);
  }

  Future<bool?> _showLargeRunConfirmDialog({required int totalMatches}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Large Simulation'),
        content: Text(
          '${combatV1FormatCount(totalMatches)} simulations will run. '
          'Large runs may temporarily freeze the browser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Run'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRun(CombatV1BatchSimulationConfig batchConfig) async {
    setState(() {
      _status = _DashboardRunStatus.running;
      _errorMessage = null;
    });
    // 19章「Frame Yield」——sync runner開始前にspinner/disabled controlsが
    // 最低1 frame描画されるようにする。
    await WidgetsBinding.instance.endOfFrame;
    try {
      final output = await widget.runFunction(batchConfig);
      if (!mounted) return;
      setState(() {
        _lastOutput = output;
        // 41章「Config Immutability」——run開始時にsnapshotしたconfigを
        // そのままlastRunConfigとして固定する（draftではなくbatchConfig）。
        _lastRunConfig = batchConfig;
        _status = _DashboardRunStatus.success;
      });
    } catch (error) {
      // batch result内のinvariantViolation件数は正常なsuccess resultとして
      // 扱う（run exceptionにしない）——ここでcatchするのはservice/runner
      // 呼び出し自体が投げたexceptionのみ。
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _status = _DashboardRunStatus.error;
      });
    }
  }

  void _selectMatchup(CombatV1Matchup matchup) {
    setState(() => _selectedMatchup = matchup);
  }

  Future<void> _onCellTap(
    BuildContext context,
    CombatV1DashboardMatchupCell cell,
  ) async {
    _selectMatchup(cell.matchup);
    final isMobile = MediaQuery.sizeOf(context).width < _mobileBreakpoint;
    if (!isMobile) return;
    // 24・47章「Matchup Detail / Mobile Detail」——mobileはbottom sheet。
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardSurface,
      builder: (sheetContext) => _MatchupDetailSheet(detail: cell.detail),
    );
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
                _ConfigCard(
                  draft: _draft,
                  enabled: !_isRunning,
                  customMatchesController: _customMatchesController,
                  seedController: _seedController,
                  maxActionsController: _maxActionsController,
                  onPresetChanged: (preset) =>
                      _updateDraft((d) => d.copyWith(matchesPreset: preset)),
                  onCustomMatchesChanged: (text) => _updateDraft(
                    (d) => d.copyWith(customMatchesPerMatchupText: text),
                  ),
                  onSeedChanged: (text) =>
                      _updateDraft((d) => d.copyWith(masterSeedText: text)),
                  onPlayerAPolicyChanged: (kind) =>
                      _updateDraft((d) => d.copyWith(playerAPolicy: kind)),
                  onPlayerBPolicyChanged: (kind) =>
                      _updateDraft((d) => d.copyWith(playerBPolicy: kind)),
                  onMaxActionsChanged: (text) =>
                      _updateDraft((d) => d.copyWith(maxActionsText: text)),
                ),
                const SizedBox(height: 16),
                _RunControls(
                  status: _status,
                  isStale: _isStale,
                  draft: _draft,
                  label: _runButtonLabel,
                  onRun: _draft.isValid ? _run : null,
                ),
                if (_lastOutput != null &&
                    _status != _DashboardRunStatus.running) ...[
                  const SizedBox(height: 12),
                  _StaleBanner(isStale: _isStale, status: _status),
                ],
                if (_status == _DashboardRunStatus.error) ...[
                  const SizedBox(height: 16),
                  _ErrorPanel(message: _errorMessage ?? '不明なエラーです'),
                ],
                if (_lastOutput != null) ...[
                  const SizedBox(height: 24),
                  _ResultSections(
                    output: _lastOutput!,
                    selectedMatchup: _selectedMatchup,
                    onCellTap: (cell) => _onCellTap(context, cell),
                  ),
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
      '画面です。ゲーム本編UIではありません。下の設定を編集してsimulationを'
      '実行し、結果をこの画面上に表示します。',
      style: TextStyle(color: Colors.white70),
    );
  }
}

/// Simulation条件を編集するcard（7〜14章）。
class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.draft,
    required this.enabled,
    required this.customMatchesController,
    required this.seedController,
    required this.maxActionsController,
    required this.onPresetChanged,
    required this.onCustomMatchesChanged,
    required this.onSeedChanged,
    required this.onPlayerAPolicyChanged,
    required this.onPlayerBPolicyChanged,
    required this.onMaxActionsChanged,
  });

  final CombatV1BalanceDashboardRunConfig draft;
  final bool enabled;
  final TextEditingController customMatchesController;
  final TextEditingController seedController;
  final TextEditingController maxActionsController;
  final ValueChanged<CombatV1BalanceDashboardMatchesPreset> onPresetChanged;
  final ValueChanged<String> onCustomMatchesChanged;
  final ValueChanged<String> onSeedChanged;
  final ValueChanged<CombatV1SimulationPolicyKind> onPlayerAPolicyChanged;
  final ValueChanged<CombatV1SimulationPolicyKind> onPlayerBPolicyChanged;
  final ValueChanged<String> onMaxActionsChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Simulation Config（編集可能）',
              style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
            ),
            const SizedBox(height: 4),
            const Text(
              '4 wrestlers: 豪田ミサキ / 黒蝶ジャック / 火神アカリ / 白銀レイナ'
              '（canonical固定）',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            const Text('Matches / Matchup', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              key: const Key('combat_v1_balance_dashboard_matches_preset_wrap'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in CombatV1BalanceDashboardMatchesPreset.values)
                  ChoiceChip(
                    key: Key('combat_v1_balance_dashboard_preset_${preset.name}'),
                    label: Text(preset.label),
                    selected: draft.matchesPreset == preset,
                    onSelected: enabled ? (_) => onPresetChanged(preset) : null,
                  ),
              ],
            ),
            if (draft.matchesPreset == CombatV1BalanceDashboardMatchesPreset.custom) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('combat_v1_balance_dashboard_custom_matches_field'),
                controller: customMatchesController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Custom matches / matchup (1–1000)',
                  errorText: draft.matchesPerMatchupError,
                ),
                onChanged: onCustomMatchesChanged,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '16 × ${draft.matchesPerMatchup ?? draft.customMatchesPerMatchupText} = '
              '${combatV1FormatCount(draft.totalMatches)} total matches',
              style: const TextStyle(color: Colors.white70),
            ),
            if (draft.showsPerformanceWarning) ...[
              const SizedBox(height: 6),
              const _PerformanceWarningNote(),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('combat_v1_balance_dashboard_seed_field'),
              controller: seedController,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(
                labelText: 'Master Seed',
                errorText: draft.masterSeedError,
              ),
              onChanged: onSeedChanged,
            ),
            const SizedBox(height: 16),
            const Text('Policies', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                final policyA = _PolicyDropdown(
                  keyValue: const Key('combat_v1_balance_dashboard_player_a_policy_field'),
                  label: 'Player A Policy',
                  value: draft.playerAPolicy,
                  enabled: enabled,
                  onChanged: onPlayerAPolicyChanged,
                );
                final policyB = _PolicyDropdown(
                  keyValue: const Key('combat_v1_balance_dashboard_player_b_policy_field'),
                  label: 'Player B Policy',
                  value: draft.playerBPolicy,
                  enabled: enabled,
                  onChanged: onPlayerBPolicyChanged,
                );
                // 45章「Mobile Config」——狭幅では縦積み、overflow回避。
                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [policyA, const SizedBox(height: 10), policyB],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: policyA),
                    const SizedBox(width: 12),
                    Expanded(child: policyB),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '※ 現在のEngineではPlayer Aがstarting player（先手）です。',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('combat_v1_balance_dashboard_advanced_tile'),
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Advanced',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              children: [
                TextField(
                  key: const Key('combat_v1_balance_dashboard_max_actions_field'),
                  controller: maxActionsController,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Max Actions',
                    errorText: draft.maxActionsError,
                  ),
                  onChanged: onMaxActionsChanged,
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Rules: Default Combat V1（固定・編集不可）',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyDropdown extends StatelessWidget {
  const _PolicyDropdown({
    required this.keyValue,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final Key keyValue;
  final String label;
  final CombatV1SimulationPolicyKind value;
  final bool enabled;
  final ValueChanged<CombatV1SimulationPolicyKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<CombatV1SimulationPolicyKind>(
      key: keyValue,
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final kind in CombatV1SimulationPolicyKind.values)
          DropdownMenuItem(
            value: kind,
            child: Text(combatV1DashboardPolicyLabel(kind)),
          ),
      ],
      onChanged: enabled
          ? (kind) {
              if (kind != null) onChanged(kind);
            }
          : null,
    );
  }
}

class _PerformanceWarningNote extends StatelessWidget {
  const _PerformanceWarningNote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Large runs may temporarily freeze the browser.',
      style: TextStyle(fontSize: 12, color: _healthWarning, fontWeight: FontWeight.bold),
    );
  }
}

class _RunControls extends StatelessWidget {
  const _RunControls({
    required this.status,
    required this.isStale,
    required this.draft,
    required this.label,
    required this.onRun,
  });

  final _DashboardRunStatus status;
  final bool isStale;
  final CombatV1BalanceDashboardRunConfig draft;
  final String label;
  final VoidCallback? onRun;

  bool get _running => status == _DashboardRunStatus.running;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          key: const Key('combat_v1_balance_dashboard_run_button'),
          onPressed: _running ? null : onRun,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_circle),
          label: Text(label),
        ),
        const SizedBox(height: 6),
        const Text(
          '※ 実行中は画面操作が一時的に停止する場合があります'
          '（main isolate上で同期実行するため）。Web Worker/isolateは使用しません。',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        if (_running) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(
            'Running ${_formatThousands(draft.totalMatches)} simulations…',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ],
    );
  }
}

/// stale result UX（16章）——最後の成功run後にdraft configが変更された
/// 場合、結果が最新設定と一致しないことを明示する。
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.isStale, required this.status});

  final bool isStale;
  final _DashboardRunStatus status;

  @override
  Widget build(BuildContext context) {
    if (!isStale || status == _DashboardRunStatus.running) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('combat_v1_balance_dashboard_stale_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _staleTint,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _healthWarning.withValues(alpha: 0.6)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: _healthWarning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Settings changed — run again to refresh results.',
              style: TextStyle(fontSize: 12, color: _healthWarning),
            ),
          ),
        ],
      ),
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
  const _ResultSections({
    required this.output,
    required this.selectedMatchup,
    required this.onCellTap,
  });

  final CombatV1BalanceRunOutput output;
  final CombatV1Matchup? selectedMatchup;
  final ValueChanged<CombatV1DashboardMatchupCell> onCellTap;

  CombatV1DashboardMatchupCell? _findSelectedCell(
    CombatV1DashboardMatchupMatrix matrix,
  ) {
    final key = selectedMatchup;
    if (key == null) return null;
    for (final row in matrix.rows) {
      for (final cell in row) {
        if (cell.matchup == key) return cell;
      }
    }
    // 44章「Matchup Detail State」——同じmatchup keyが見つからない場合は
    // 安全にnull（未選択）として扱う。
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = output.viewModel;
    final selectedCell = _findSelectedCell(viewModel.matchupMatrix);
    final isMobile = MediaQuery.sizeOf(context).width < _mobileBreakpoint;
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
        _SectionHeader('Matchup Matrix', '4×4 対戦カード別勝率（セルをtapするとdetailを表示）'),
        const _MatrixExplanation(),
        const SizedBox(height: 8),
        _MatchupMatrixView(
          matrix: viewModel.matchupMatrix,
          selectedMatchup: selectedMatchup,
          onCellTap: onCellTap,
        ),
        if (!isMobile) ...[
          const SizedBox(height: 12),
          _MatchupDetailPanel(detail: selectedCell?.detail),
        ],
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
      ('Player A Policy', run.playerAPolicyLabel),
      ('Player B Policy', run.playerBPolicyLabel),
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
        // 下げて（cardを縦長にして）overflowを防ぐ。
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
  const _MatchupMatrixView({
    required this.matrix,
    required this.selectedMatchup,
    required this.onCellTap,
  });

  final CombatV1DashboardMatchupMatrix matrix;
  final CombatV1Matchup? selectedMatchup;
  final ValueChanged<CombatV1DashboardMatchupCell> onCellTap;

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
                for (final cell in matrix.rows[i])
                  _MatrixCell(
                    cell: cell,
                    isSelected: cell.matchup == selectedMatchup,
                    onTap: () => onCellTap(cell),
                  ),
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
  const _MatrixCell({
    required this.cell,
    required this.isSelected,
    required this.onTap,
  });

  final CombatV1DashboardMatchupCell cell;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasHealthNote = cell.safetyLimitMatches > 0 || cell.invariantViolationMatches > 0;
    return InkWell(
      key: Key(
        'combat_v1_balance_dashboard_matrix_cell_'
        '${cell.matchup.wrestlerAId}_${cell.matchup.wrestlerBId}',
      ),
      onTap: onTap,
      child: Container(
        // 28・35章「Matrix Cell / Matrix Color」——勝率高低を赤/緑で意味
        // 付けしない（heatmap禁止）。diagonal（mirror）と選択cellのみ
        // subtleに区別する。
        decoration: BoxDecoration(
          color: cell.isMirror ? _mirrorTint : null,
          border: isSelected ? Border.all(color: _gold, width: 2) : null,
        ),
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
      ),
    );
  }
}

/// Desktop用matchup detail panel（24章「Matchup Detail」、matrix下に表示）。
class _MatchupDetailPanel extends StatelessWidget {
  const _MatchupDetailPanel({required this.detail});

  final CombatV1DashboardMatchupDetail? detail;

  @override
  Widget build(BuildContext context) {
    final currentDetail = detail;
    return Card(
      key: const Key('combat_v1_balance_dashboard_matchup_detail_panel'),
      color: _cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: currentDetail == null
            ? const Text(
                'Matchup Detail — tap a matrix cell to see details.',
                style: TextStyle(color: Colors.white38),
              )
            : _MatchupDetailView(detail: currentDetail),
      ),
    );
  }
}

/// Mobile用matchup detail bottom sheet（24・47章）。scrollable。
class _MatchupDetailSheet extends StatelessWidget {
  const _MatchupDetailSheet({required this.detail});

  final CombatV1DashboardMatchupDetail detail;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              controller: scrollController,
              child: _MatchupDetailView(detail: detail),
            ),
          ),
        );
      },
    );
  }
}

/// desktop panel / mobile bottom sheet共通のmatchup detail content
/// （25〜27章「Matchup Detail Content / Terminal Cause Detail / Matchup
/// Length Detail」）。
class _MatchupDetailView extends StatelessWidget {
  const _MatchupDetailView({required this.detail});

  final CombatV1DashboardMatchupDetail detail;

  @override
  Widget build(BuildContext context) {
    final summaryRows = <(String, String)>[
      ('Wrestler A', detail.wrestlerADisplayName),
      ('Wrestler B', detail.wrestlerBDisplayName),
      ('Total Matches', combatV1FormatCount(detail.totalMatches)),
      ('Completed', combatV1FormatCount(detail.completedMatches)),
      ('Player A Wins', combatV1FormatCount(detail.playerAWins)),
      ('Player A Win Rate', combatV1FormatPercent(detail.playerAWinRate)),
      ('Player B Wins', combatV1FormatCount(detail.playerBWins)),
      ('Player B Win Rate', combatV1FormatPercent(detail.playerBWinRate)),
      (
        'Safety Limit',
        '${combatV1FormatCount(detail.safetyLimitMatches)} '
            '(${combatV1FormatPercent(detail.safetyLimitRate)})',
      ),
      (
        'Invariant Violation',
        '${combatV1FormatCount(detail.invariantViolationMatches)} '
            '(${combatV1FormatPercent(detail.invariantViolationRate)})',
      ),
    ];
    final causes = detail.terminalCauseCounts;
    final causeRows = <(String, String)>[
      ('Normal PIN', combatV1FormatCount(causes.normalPin)),
      ('Direct PIN', combatV1FormatCount(causes.directPin)),
      ('Submission', combatV1FormatCount(causes.submission)),
      ('Submission Finisher', combatV1FormatCount(causes.submissionFinisher)),
      ('Other', combatV1FormatCount(causes.other)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${detail.wrestlerADisplayName} vs ${detail.wrestlerBDisplayName}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _pink),
        ),
        const SizedBox(height: 8),
        _metadataCard(summaryRows),
        const SizedBox(height: 14),
        const Text('Terminal Causes', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text(
          '正常終了causeのみ（safety limit / invariant violationは上記へ別掲）。',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        const SizedBox(height: 4),
        _metadataCard(causeRows),
        const SizedBox(height: 14),
        const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
        _distributionCard(detail.actionCount),
        const SizedBox(height: 14),
        const Text('Final Turn', style: TextStyle(fontWeight: FontWeight.bold)),
        _distributionCard(detail.finalTurnNumber),
      ],
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
