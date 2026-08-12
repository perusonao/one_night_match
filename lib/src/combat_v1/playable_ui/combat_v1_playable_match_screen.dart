/// Combat Ver.1 Playable 1B — Match Screen
/// （docs/design/combat_v1_playable_match_ui.md Playable 1B追記）。
///
/// `CombatV1PlayableMatchController`（`CombatV1PlayableMatchSession`経由）
/// のsnapshot/action APIだけを表示・操作するUI層。legality・damage・
/// Counter/PIN/REST/StandUp/terminal判定はいずれも再実装しない
/// ——このfileが行うのは「snapshotの表示」と「legal actionの選択・
/// submit」のみ。
library;

import 'package:flutter/material.dart';

import '../combat_v1_enums.dart';
import '../combat_v1_legal_action.dart';
import '../playable/combat_v1_playable_action_feedback.dart';
import '../playable/combat_v1_playable_match_config.dart';
import '../playable/combat_v1_playable_match_controller.dart'
    show CombatV1PlayableMatchController;
import '../playable/combat_v1_playable_match_result.dart';
import '../playable/combat_v1_playable_match_snapshot.dart';
import 'combat_v1_playable_feedback_formatters.dart';
import 'combat_v1_playable_match_session.dart';
import 'combat_v1_playable_ui_formatters.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);
const _cardSurface = Color(0xff211527);
const _healthError = Color(0xffff5c5c);

/// CPU 1手ごとのpresentation delay既定値（design doc「17章 CPU
/// Delay」）。widget testでは`Duration.zero`等へ差し替える
/// （`CombatV1PlayableMatchScreen.cpuDelay`）。
const Duration combatV1PlayableDefaultCpuDelay = Duration(milliseconds: 400);

/// Match画面本体。
class CombatV1PlayableMatchScreen extends StatefulWidget {
  const CombatV1PlayableMatchScreen({
    super.key,
    required this.humanWrestlerId,
    required this.cpuWrestlerId,
    this.sessionFactory = combatV1PlayableDefaultSessionFactory,
    this.cpuDelay = combatV1PlayableDefaultCpuDelay,
    this.maxActions = 500,
    this.seedGenerator = combatV1PlayableGenerateSeeds,
  });

  final String humanWrestlerId;
  final String cpuWrestlerId;

  /// design doc「74章 Runner Injection」——widget testはscripted fakeを
  /// 返すfactoryを注入できる。
  final CombatV1PlayableSessionFactory sessionFactory;

  /// design doc「17・73章」——widget testは`Duration.zero`を注入する。
  final Duration cpuDelay;

  final int maxActions;

  /// design doc「12章 Seed Strategy」——UI/application層専用のseed生成。
  final CombatV1PlayableSeedGenerator seedGenerator;

  @override
  State<CombatV1PlayableMatchScreen> createState() =>
      _CombatV1PlayableMatchScreenState();
}

class _CombatV1PlayableMatchScreenState
    extends State<CombatV1PlayableMatchScreen> {
  static const int _humanPlayerIndex =
      CombatV1PlayableMatchController.humanPlayerIndex;

  late CombatV1PlayableMatchSession _session;
  late CombatV1PlayableMatchSnapshot _snapshot;
  CombatV1PlayableMatchConfig? _config;

  String? _selectedCardInstanceId;
  String? _submitErrorMessage;
  bool _cpuBusy = false;

  /// bottom sheet多重表示防止（design doc「43章 Counter Prompt
  /// Close」）。
  bool _counterSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _startNewMatch();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _afterSnapshotChanged(),
    );
  }

  void _startNewMatch() {
    final seeds = widget.seedGenerator();
    final config = CombatV1PlayableMatchConfig(
      humanWrestlerId: widget.humanWrestlerId,
      cpuWrestlerId: widget.cpuWrestlerId,
      engineSeed: seeds.engineSeed,
      cpuPolicySeed: seeds.cpuPolicySeed,
      maxActions: widget.maxActions,
    );
    _config = config;
    _session = widget.sessionFactory(config);
    _snapshot = _session.snapshot;
    _selectedCardInstanceId = null;
    _submitErrorMessage = null;
    _cpuBusy = false;
    _counterSheetOpen = false;
  }

  /// 直近snapshot更新後の共通後処理（design doc「71・72章」）: Counter
  /// promptを開くべきか／CPU進行を開始すべきかを判定する。
  void _afterSnapshotChanged() {
    if (!mounted) return;
    if (_snapshot.isHumanInputRequired && _snapshot.pendingAttack != null) {
      _maybeShowCounterSheet();
      return;
    }
    if (_snapshot.status == CombatV1PlayableControllerStatus.active &&
        !_snapshot.isHumanInputRequired) {
      _runCpuLoop();
    }
  }

  void _maybeShowCounterSheet() {
    if (_counterSheetOpen) return;
    _counterSheetOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        // 43章「Counter Prompt Close」——system back tap/外側tapで勝手に
        // 閉じない。Legal choiceを行うまでprompt維持。
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        backgroundColor: _cardSurface,
        builder: (sheetContext) => PopScope(
          canPop: false,
          child: _CounterPromptSheet(
            snapshot: _snapshot,
            onDecision: (action) =>
                _handleCounterDecision(sheetContext, action),
          ),
        ),
      );
      _counterSheetOpen = false;
    });
  }

  void _handleCounterDecision(
    BuildContext sheetContext,
    CombatV1LegalAction action,
  ) {
    Navigator.of(sheetContext).pop();
    _counterSheetOpen = false;
    _submitAction(action);
  }

  Future<void> _runCpuLoop() async {
    // 20章「Reentrancy」——二重CPU loop禁止。
    if (_cpuBusy) return;
    setState(() => _cpuBusy = true);
    while (mounted &&
        _snapshot.status == CombatV1PlayableControllerStatus.active &&
        !_snapshot.isHumanInputRequired) {
      await Future<void>.delayed(widget.cpuDelay);
      // 19章「Mounted Safety」——delay/Future間で必ずmountedを確認する。
      if (!mounted) return;
      final result = _session.advanceCpuOneAction();
      if (!mounted) return;
      setState(() => _snapshot = result.snapshot);
      if (result.actionsExecuted == 0) break;
    }
    if (!mounted) return;
    setState(() => _cpuBusy = false);
    _afterSnapshotChanged();
  }

  void _submitAction(CombatV1LegalAction action) {
    if (_cpuBusy) return;
    final result = _session.submitHumanAction(
      expectedRevision: _snapshot.revision,
      action: action,
    );
    setState(() {
      _snapshot = result.snapshot;
      _selectedCardInstanceId = null;
      _submitErrorMessage = result.isAccepted
          ? null
          : (result.message ?? '操作を受け付けられませんでした');
    });
    if (result.isAccepted) {
      _afterSnapshotChanged();
    }
  }

  CombatV1LegalAction? _findLegalAction(
    CombatV1LegalActionKind kind, {
    String? cardInstanceId,
  }) {
    for (final action in _snapshot.legalActions) {
      if (action.kind == kind && action.cardInstanceId == cardInstanceId) {
        return action;
      }
    }
    return null;
  }

  void _onSelectCard(String instanceId) {
    setState(() {
      _selectedCardInstanceId = _selectedCardInstanceId == instanceId
          ? null
          : instanceId;
    });
  }

  void _rematch() {
    setState(_startNewMatch);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _afterSnapshotChanged(),
    );
  }

  void _back() => Navigator.of(context).pop();

  void _showDetails() {
    final config = _config;
    if (config == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Match Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Engine Seed: ${config.engineSeed}'),
            Text('CPU Policy Seed: ${config.cpuPolicySeed}'),
            Text('Max Actions: ${config.maxActions}'),
            const Text('Rules: Default Combat V1'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${combatV1PlayableWrestlerDisplayName(widget.humanWrestlerId)} vs '
          '${combatV1PlayableWrestlerDisplayName(widget.cpuWrestlerId)}',
        ),
        actions: [
          IconButton(
            key: const Key('combat_v1_playable_match_details_button'),
            icon: const Icon(Icons.info_outline),
            tooltip: 'Match Details',
            onPressed: _showDetails,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      _CpuStatusPanel(cpu: snapshot.cpu),
                      _SharedStatusPanel(snapshot: snapshot),
                      // Playable 1C: latest action feedback banner等、
                      // 内容量が変動するpanelが増えたため、この panel
                      // 自体は内部で高さ上限を持つ（下記
                      // `_ActorAndRecentPanel`参照）——Human status
                      // panel/Primary actions barがscroll不要で常に画面内に
                      // 収まる既存レイアウトを維持するため。
                      _ActorAndRecentPanel(
                        snapshot: snapshot,
                        humanPlayerIndex: _humanPlayerIndex,
                        cpuBusy: _cpuBusy,
                      ),
                      if (_submitErrorMessage != null)
                        _ErrorBanner(message: _submitErrorMessage!),
                      Expanded(
                        child: IgnorePointer(
                          ignoring: _cpuBusy,
                          child: SingleChildScrollView(
                            child: _MatchBody(
                              snapshot: snapshot,
                              selectedCardInstanceId: _selectedCardInstanceId,
                              onSelectCard: _onSelectCard,
                            ),
                          ),
                        ),
                      ),
                      _HumanStatusPanel(human: snapshot.human),
                      IgnorePointer(
                        ignoring: _cpuBusy,
                        child: _PrimaryActionsBar(
                          snapshot: snapshot,
                          selectedCardInstanceId: _selectedCardInstanceId,
                          busy: _cpuBusy,
                          findAction: _findLegalAction,
                          onSubmit: _submitAction,
                        ),
                      ),
                    ],
                  ),
                ),
                if (snapshot.status != CombatV1PlayableControllerStatus.active)
                  _ResultOverlay(
                    snapshot: snapshot,
                    result: _session.result,
                    onRematch: _rematch,
                    onBack: _back,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

class _StatusPanelShell extends StatelessWidget {
  const _StatusPanelShell({
    super.key,
    required this.badgeLabel,
    required this.badgeColor,
    required this.wrestlerName,
    required this.hp,
    required this.maxHp,
    required this.koc,
    required this.posture,
    required this.handCount,
    required this.pinCardsHeld,
  });

  final String badgeLabel;
  final Color badgeColor;
  final String wrestlerName;
  final int hp;
  final int maxHp;
  final int koc;
  final CombatV1WrestlerPosture posture;
  final int handCount;
  final int pinCardsHeld;

  @override
  Widget build(BuildContext context) {
    final hpRatio = maxHp <= 0 ? 0.0 : (hp / maxHp).clamp(0.0, 1.0);
    final isDown = posture == CombatV1WrestlerPosture.down;
    return Card(
      color: _cardSurface,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _MiniBadge(label: badgeLabel, color: badgeColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          wrestlerName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        combatV1PlayablePostureLabel(posture),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDown ? _healthError : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: hpRatio,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 12,
                    children: [
                      Text(
                        'HP $hp / $maxHp',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Tooltip(
                        message: 'PIN / Submissionからの脱出に使用',
                        child: Text(
                          'KOC $koc',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        'Hand $handCount',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'PIN $pinCardsHeld',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CpuStatusPanel extends StatelessWidget {
  const _CpuStatusPanel({required this.cpu});
  final CombatV1PlayableOpponentStatus cpu;

  @override
  Widget build(BuildContext context) {
    return _StatusPanelShell(
      key: const Key('combat_v1_playable_cpu_status_panel'),
      badgeLabel: 'CPU',
      badgeColor: _gold,
      wrestlerName: cpu.wrestlerName,
      hp: cpu.hp,
      maxHp: cpu.maxHp,
      koc: cpu.koc,
      posture: cpu.posture,
      handCount: cpu.handCount,
      pinCardsHeld: cpu.pinCardsHeld,
    );
  }
}

class _HumanStatusPanel extends StatelessWidget {
  const _HumanStatusPanel({required this.human});
  final CombatV1PlayableHumanStatus human;

  @override
  Widget build(BuildContext context) {
    return _StatusPanelShell(
      key: const Key('combat_v1_playable_human_status_panel'),
      badgeLabel: 'YOU',
      badgeColor: _pink,
      wrestlerName: human.wrestlerName,
      hp: human.hp,
      maxHp: human.maxHp,
      koc: human.koc,
      posture: human.posture,
      handCount: human.handCount,
      pinCardsHeld: human.pinCardsHeld,
    );
  }
}

class _SharedStatusPanel extends StatelessWidget {
  const _SharedStatusPanel({required this.snapshot});
  final CombatV1PlayableMatchSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    // Playable 1C「HEAT UI Recommendation」——「HEAT 360 / 200」のような
    // progress上限表現は「200が上限」に見えてしまう（HEATは消費されず、
    // 200超もそのまま蓄積し続ける、docs/combat_rules_v1.md 12章）。current
    // valueとFINISHER解禁閾値を別々に表示し、HEATが共有・蓄積型である
    // ことをTooltipで補足する。
    final unlocked = snapshot.sharedHeat >= snapshot.finisherHeatThreshold;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // 61章「Small Screen」——狭幅でも折り返してoverflowしないようRowでは
      // なくWrapを使う（`mainAxisAlignment.spaceBetween`のRowは狭幅で
      // overflowしうる）。
      child: Wrap(
        key: const Key('combat_v1_playable_shared_status'),
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 2,
        children: [
          Text(
            'Turn ${snapshot.turnNumber}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          Text(
            combatV1PlayablePhaseLabel(snapshot.phase),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          Tooltip(
            message:
                'HEATは両者共有・蓄積型（減りません）。'
                '${snapshot.finisherHeatThreshold}に達するとFINISHERカードが解禁されます'
                '（上限ではなく解禁ラインです）',
            child: Wrap(
              key: const Key('combat_v1_playable_heat_status'),
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  'Shared HEAT ${snapshot.sharedHeat}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _gold,
                  ),
                ),
                Text(
                  'Finisher Unlock ${snapshot.finisherHeatThreshold}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                if (unlocked) const _MiniBadge(label: 'UNLOCKED', color: _gold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActorAndRecentPanel extends StatelessWidget {
  const _ActorAndRecentPanel({
    required this.snapshot,
    required this.humanPlayerIndex,
    required this.cpuBusy,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final int humanPlayerIndex;
  final bool cpuBusy;

  @override
  Widget build(BuildContext context) {
    final actorLabel = combatV1PlayableActorLabel(
      status: snapshot.status,
      phase: snapshot.phase,
      isHumanInputRequired: snapshot.isHumanInputRequired,
      currentActorPlayerIndex: snapshot.currentActorPlayerIndex,
      hasPendingAttack: snapshot.pendingAttack != null,
    );
    // Playable 1C「Recent Action Log Upgrade」——直近1件は大きめbanner、
    // その前のもの（compact list）をあわせて表示する（「Keep Log
    // Compact」——8件保持全件は必ずしも見せない、直近4件のみ）。
    final recents = snapshot.recentFeedback.reversed.skip(1).take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (cpuBusy)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Text(
                actorLabel,
                key: const Key('combat_v1_playable_actor_label'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _pink,
                ),
              ),
            ],
          ),
          // Playable 1C「Keep Log Compact」——feedback内容量が可変のため、
          // ここだけ高さ上限＋内部clip-scrollにして、Human status
          // panel/Primary actions barが常にscroll不要で画面内へ収まる
          // 既存レイアウト（Expanded/固定bottom bar）を壊さないようにする
          // （念のための上限であり、通常の1〜2行feedbackでは到達しない）。
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  if (snapshot.latestFeedback != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _LatestFeedbackBanner(
                        feedback: snapshot.latestFeedback!,
                        humanPlayerIndex: humanPlayerIndex,
                      ),
                    ),
                  if (recents.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        key: const Key('combat_v1_playable_recent_log'),
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          for (final feedback in recents)
                            Text(
                              combatV1PlayableFeedbackCompactLabel(
                                feedback,
                                humanPlayerIndex: humanPlayerIndex,
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 直近1件のaction feedbackを表示する大きめbanner（Playable 1C「Action
/// Result Feedback」「Feedback Display Duration」）。次のactionのfeedbackが
/// 届くまで表示され続ける——CPUが400ms間隔で連続行動しても、直前の結果を
/// 読み逃さないようにする（大幅なCPU delay増加ではなく、feedback
/// persistenceで解決する方針）。
class _LatestFeedbackBanner extends StatelessWidget {
  const _LatestFeedbackBanner({
    required this.feedback,
    required this.humanPlayerIndex,
  });

  final CombatV1PlayableActionFeedback feedback;
  final int humanPlayerIndex;

  @override
  Widget build(BuildContext context) {
    final title = combatV1PlayableFeedbackTitle(
      feedback,
      humanPlayerIndex: humanPlayerIndex,
    );
    final details = combatV1PlayableFeedbackDetailLines(
      feedback,
      humanPlayerIndex: humanPlayerIndex,
    );
    final isHuman = feedback.actorPlayerIndex == humanPlayerIndex;
    return Container(
      key: const Key('combat_v1_playable_latest_feedback_banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isHuman ? _pink : _gold).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isHuman ? _pink : _gold).withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            key: const Key('combat_v1_playable_latest_feedback_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isHuman ? _pink : _gold,
            ),
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                key: const Key('combat_v1_playable_latest_feedback_details'),
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 2,
                children: [
                  for (final line in details)
                    Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('combat_v1_playable_submit_error_banner'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _healthError.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _healthError),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, color: _healthError),
      ),
    );
  }
}

class _MatchBody extends StatelessWidget {
  const _MatchBody({
    required this.snapshot,
    required this.selectedCardInstanceId,
    required this.onSelectCard,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final String? selectedCardInstanceId;
  final ValueChanged<String> onSelectCard;

  bool get _isDown =>
      snapshot.human.posture == CombatV1WrestlerPosture.down &&
      snapshot.phase == CombatV1MatchPhase.action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (snapshot.phase == CombatV1MatchPhase.discard &&
              snapshot.isHumanInputRequired)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '手札から1枚捨ててください',
                    key: Key('combat_v1_playable_discard_prompt'),
                    style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
                  ),
                  // Playable 1C「Discard Context Help」——初回/常時、短い
                  // 説明のみ（フルルール説明はしない）。
                  Text(
                    'ターン開始時に手札を1枚捨てます',
                    key: Key('combat_v1_playable_discard_hint'),
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          if (_isDown)
            const _DownIndicator()
          else
            _HandRow(
              hand: snapshot.human.hand,
              selectedCardInstanceId: selectedCardInstanceId,
              onSelectCard: onSelectCard,
              sharedHeat: snapshot.sharedHeat,
              finisherHeatThreshold: snapshot.finisherHeatThreshold,
            ),
        ],
      ),
    );
  }
}

class _DownIndicator extends StatelessWidget {
  const _DownIndicator();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Text(
              'DOWN',
              key: Key('combat_v1_playable_down_indicator'),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: _healthError,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Stand UpまたはRestを選んでください',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            // Playable 1C「Stand Up / Rest Context Help」——事前に違いが
            // 分かるよう、button前にそれぞれ短い説明を置く。
            const _ActionHint(
              key: Key('combat_v1_playable_stand_up_hint'),
              label: 'Stand Up',
              description: '立ち上がって、このターンの行動を続ける',
            ),
            const SizedBox(height: 4),
            const _ActionHint(
              key: Key('combat_v1_playable_rest_hint'),
              label: 'Rest',
              description: 'HPを回復してターン終了',
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionHint extends StatelessWidget {
  const _ActionHint({
    super.key,
    required this.label,
    required this.description,
  });

  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    // `RichText`ではなく`Text.rich`を使う——内部的には同じ`RichText`を
    // 構築するが、`find.text`/`find.textContaining`（既定`findRichText:
    // false`）が`Text`系widgetとしてmatchできるようにするため。
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 11, color: Colors.white54),
        children: [
          TextSpan(
            text: '$label — ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          TextSpan(text: description),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _HandRow extends StatelessWidget {
  const _HandRow({
    required this.hand,
    required this.selectedCardInstanceId,
    required this.onSelectCard,
    this.sharedHeat,
    this.finisherHeatThreshold,
  });

  final List<CombatV1PlayableHandCard> hand;
  final String? selectedCardInstanceId;
  final ValueChanged<String> onSelectCard;

  /// Playable 1C「Finisher Feedback」——finisher cardのHEAT要件表示用。
  /// COUNTER応答sheetなど、この文脈がない呼び出し元では`null`のままにする。
  final int? sharedHeat;
  final int? finisherHeatThreshold;

  @override
  Widget build(BuildContext context) {
    if (hand.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('手札がありません', style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Playable 1C「Horizontal Hand Cue」——右側のusable cardを見落とし
        // やすいため、小さなscroll cueを添える（大規模carousel UI不要）。
        if (hand.length > 1)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              '→ 横にスクロールできます',
              key: Key('combat_v1_playable_hand_scroll_hint'),
              style: TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ),
        SizedBox(
          // Playable 1C: finisher cardの「Requires HEAT」hint行が追加された
          // ため168pxから拡張（`_CounterPromptSheet`のcounter hand専用
          // SizedBoxは対象外——counter cardはfinisherになり得ないため）。
          height: 182,
          child: ListView.separated(
            key: const Key('combat_v1_playable_human_hand'),
            scrollDirection: Axis.horizontal,
            itemCount: hand.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final card = hand[index];
              return _HandCardTile(
                key: ValueKey(
                  'combat_v1_playable_hand_card_${card.instanceId}',
                ),
                card: card,
                selected: card.instanceId == selectedCardInstanceId,
                onTap: () => onSelectCard(card.instanceId),
                sharedHeat: sharedHeat,
                finisherHeatThreshold: finisherHeatThreshold,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HandCardTile extends StatelessWidget {
  const _HandCardTile({
    super.key,
    required this.card,
    required this.selected,
    required this.onTap,
    this.sharedHeat,
    this.finisherHeatThreshold,
  });

  final CombatV1PlayableHandCard card;
  final bool selected;
  final VoidCallback onTap;
  final int? sharedHeat;
  final int? finisherHeatThreshold;

  /// Playable 1C「Finisher Feedback / Do Not Invent Finisher Reasons」——
  /// 安全に判定できるのはHEAT閾値だけなので、それ以外のlegality理由は
  /// 断定しない。HEAT不足だと判定できる場合のみ具体的な数値を出し、
  /// それ以外は既存の汎用メッセージに留める。
  String _disabledMessage() {
    final threshold = finisherHeatThreshold;
    final heat = sharedHeat;
    if (card.category == CombatV1CardCategory.finisher &&
        threshold != null &&
        heat != null &&
        heat < threshold) {
      return 'Requires HEAT $threshold (current $heat)';
    }
    return '現在は使用できません';
  }

  @override
  Widget build(BuildContext context) {
    final technique = card.technique;
    final counter = card.counter;
    final disabled = !card.isUsable;
    final threshold = finisherHeatThreshold;
    return Semantics(
      // Playable 1C「Accessibility Semantics」——selected/enabledを明示する。
      button: true,
      selected: selected,
      enabled: !disabled,
      label: card.displayName,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 134,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _pink : Colors.white24,
                width: selected ? 2 : 1,
              ),
            ),
            // Playable 1C: finisher HEAT要件hint等、任意行が増えて縦幅が
            // 変動するようになったため、`SingleChildScrollView`で包んで
            // 万一カード高を超えてもRenderFlex overflowにしない（cardの
            // 見た目の高さ自体は外側`SizedBox`で固定のまま）。
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    combatV1PlayableCategoryLabel(card.category),
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                  const SizedBox(height: 4),
                  if (technique != null) ...[
                    Text(
                      '${technique.attribute.displayLabel} DMG ${technique.damage} '
                      'HEAT ${technique.heatGain}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      'Cost ${combatV1PlayableEnergyCostLabel(technique.energyCost.amounts)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ] else if (counter != null) ...[
                    Text(
                      'Cost属性 ${counter.attribute.displayLabel}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (card.category == CombatV1CardCategory.finisher)
                        const _MiniBadge(label: 'FINISHER', color: _pink),
                      if (card.category == CombatV1CardCategory.counter)
                        const _MiniBadge(label: 'COUNTER', color: _gold),
                    ],
                  ),
                  // finisher要件hintとdisabledメッセージは、どちらもHEAT
                  // 要件について述べる内容が重複しうるため同時には出さない
                  // （disabled時は`_disabledMessage()`側がHEAT要件を含む）。
                  if (!disabled &&
                      card.category == CombatV1CardCategory.finisher &&
                      threshold != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Requires HEAT $threshold',
                        key: const Key('combat_v1_playable_finisher_heat_hint'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  if (disabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _disabledMessage(),
                        key: const Key(
                          'combat_v1_playable_card_disabled_message',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.lowEmphasis = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool lowEmphasis;

  @override
  Widget build(BuildContext context) {
    if (lowEmphasis) {
      return OutlinedButton(onPressed: onPressed, child: Text(label));
    }
    if (primary) {
      return FilledButton(onPressed: onPressed, child: Text(label));
    }
    return FilledButton.tonal(onPressed: onPressed, child: Text(label));
  }
}

class _PrimaryActionsBar extends StatelessWidget {
  const _PrimaryActionsBar({
    required this.snapshot,
    required this.selectedCardInstanceId,
    required this.busy,
    required this.findAction,
    required this.onSubmit,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final String? selectedCardInstanceId;
  final bool busy;
  final CombatV1LegalAction? Function(
    CombatV1LegalActionKind kind, {
    String? cardInstanceId,
  })
  findAction;
  final ValueChanged<CombatV1LegalAction> onSubmit;

  @override
  Widget build(BuildContext context) {
    if (!snapshot.isHumanInputRequired || busy) {
      return const SizedBox(height: 8);
    }
    if (snapshot.phase == CombatV1MatchPhase.counterResponsePending) {
      // 40章「Counter Prompt」——bottom sheetが担当するため、下部barには
      // 表示しない。
      return const SizedBox(height: 8);
    }

    final kinds = snapshot.legalActions.map((a) => a.kind).toSet();
    final buttons = <Widget>[];

    if (snapshot.phase == CombatV1MatchPhase.discard) {
      final action = selectedCardInstanceId == null
          ? null
          : findAction(
              CombatV1LegalActionKind.discard,
              cardInstanceId: selectedCardInstanceId,
            );
      buttons.add(
        _ActionButton(
          key: const Key('combat_v1_playable_action_discard'),
          label: combatV1PlayableActionKindLabel(
            CombatV1LegalActionKind.discard,
          ),
          onPressed: action == null ? null : () => onSubmit(action),
          primary: true,
        ),
      );
    } else {
      if (kinds.contains(CombatV1LegalActionKind.standUp)) {
        final action = findAction(CombatV1LegalActionKind.standUp);
        buttons.add(
          _ActionButton(
            key: const Key('combat_v1_playable_action_stand_up'),
            label: combatV1PlayableActionKindLabel(
              CombatV1LegalActionKind.standUp,
            ),
            onPressed: action == null ? null : () => onSubmit(action),
            primary: true,
          ),
        );
      }
      if (kinds.contains(CombatV1LegalActionKind.rest)) {
        final action = findAction(CombatV1LegalActionKind.rest);
        buttons.add(
          _ActionButton(
            key: const Key('combat_v1_playable_action_rest'),
            label: combatV1PlayableActionKindLabel(
              CombatV1LegalActionKind.rest,
            ),
            onPressed: action == null ? null : () => onSubmit(action),
          ),
        );
      }
      if (kinds.contains(CombatV1LegalActionKind.technique)) {
        final action = selectedCardInstanceId == null
            ? null
            : findAction(
                CombatV1LegalActionKind.technique,
                cardInstanceId: selectedCardInstanceId,
              );
        buttons.add(
          _ActionButton(
            key: const Key('combat_v1_playable_action_technique'),
            label: combatV1PlayableActionKindLabel(
              CombatV1LegalActionKind.technique,
            ),
            onPressed: action == null ? null : () => onSubmit(action),
            primary: true,
          ),
        );
      }
      if (kinds.contains(CombatV1LegalActionKind.pin)) {
        final action = findAction(CombatV1LegalActionKind.pin);
        buttons.add(
          _ActionButton(
            key: const Key('combat_v1_playable_action_pin'),
            label: combatV1PlayableActionKindLabel(CombatV1LegalActionKind.pin),
            onPressed: action == null ? null : () => onSubmit(action),
          ),
        );
      }
      if (kinds.contains(CombatV1LegalActionKind.endTurn)) {
        final action = findAction(CombatV1LegalActionKind.endTurn);
        buttons.add(
          _ActionButton(
            key: const Key('combat_v1_playable_action_end_turn'),
            label: combatV1PlayableActionKindLabel(
              CombatV1LegalActionKind.endTurn,
            ),
            onPressed: action == null ? null : () => onSubmit(action),
            // 38章「誤操作対策」——Techniqueより視覚優先度を下げる。
            lowEmphasis: true,
          ),
        );
      }
    }

    if (buttons.isEmpty) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        key: const Key('combat_v1_playable_primary_actions'),
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: buttons,
      ),
    );
  }
}

class _PendingAttackSummary extends StatelessWidget {
  const _PendingAttackSummary({required this.pending});
  final CombatV1PlayablePendingAttackView pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('combat_v1_playable_pending_attack_summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '相手: ${pending.displayName}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${pending.attribute.displayLabel} ・ DMG ${pending.damage} ・ '
            '${pending.resultOpponentState == null ? "状態変化なし" : combatV1PlayablePostureLabel(pending.resultOpponentState!)}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _CounterPromptSheet extends StatefulWidget {
  const _CounterPromptSheet({required this.snapshot, required this.onDecision});
  final CombatV1PlayableMatchSnapshot snapshot;
  final ValueChanged<CombatV1LegalAction> onDecision;

  @override
  State<_CounterPromptSheet> createState() => _CounterPromptSheetState();
}

class _CounterPromptSheetState extends State<_CounterPromptSheet> {
  String? _selectedCounterInstanceId;

  @override
  Widget build(BuildContext context) {
    final pending = widget.snapshot.pendingAttack;
    final declineAction = _firstWhereOrNull(
      widget.snapshot.legalActions,
      (a) => a is CombatV1DeclineCounterAction,
    );
    final counterActions = widget.snapshot.legalActions
        .whereType<CombatV1CounterAction>()
        .toList();
    // 41章「Counter Card UI」——Human hand全体ではなく、isUsable
    // Counterを中心に表示する。
    final usableCounterCards = widget.snapshot.human.hand
        .where(
          (card) =>
              card.category == CombatV1CardCategory.counter && card.isUsable,
        )
        .toList();

    final selectedAction = _selectedCounterInstanceId == null
        ? null
        : _firstWhereOrNull(
            counterActions,
            (a) => a.cardInstanceId == _selectedCounterInstanceId,
          );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '返し技を選択',
              key: Key('combat_v1_playable_counter_prompt_title'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: _pink,
              ),
            ),
            const SizedBox(height: 8),
            if (pending != null) _PendingAttackSummary(pending: pending),
            const SizedBox(height: 12),
            if (usableCounterCards.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '使用できるCOUNTERカードがありません',
                  style: TextStyle(color: Colors.white38),
                ),
              )
            else
              SizedBox(
                height: 168,
                child: ListView.separated(
                  key: const Key('combat_v1_playable_counter_hand'),
                  scrollDirection: Axis.horizontal,
                  itemCount: usableCounterCards.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final card = usableCounterCards[index];
                    return _HandCardTile(
                      key: ValueKey(
                        'combat_v1_playable_counter_card_${card.instanceId}',
                      ),
                      card: card,
                      selected: card.instanceId == _selectedCounterInstanceId,
                      onTap: () => setState(
                        () => _selectedCounterInstanceId =
                            card.instanceId == _selectedCounterInstanceId
                            ? null
                            : card.instanceId,
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('combat_v1_playable_counter_play_button'),
                    onPressed: selectedAction == null
                        ? null
                        : () => widget.onDecision(selectedAction),
                    child: const Text('Play Counter'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('combat_v1_playable_counter_decline_button'),
                    onPressed: declineAction == null
                        ? null
                        : () => widget.onDecision(declineAction),
                    child: const Text('技を受ける'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({
    required this.snapshot,
    required this.result,
    required this.onRematch,
    required this.onBack,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final CombatV1PlayableMatchResult? result;
  final VoidCallback onRematch;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        key: const Key('combat_v1_playable_result_overlay'),
        color: Colors.black87,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: _cardSurface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final r = result;
    // 53章「Winner Display Guard」——status==matchOverでない限りwinnerを
    // 表示しない。resultが未構築（error状態）の場合も同様の防御的panel。
    if (r == null) {
      return _errorContent();
    }
    return switch (r.status) {
      CombatV1PlayableControllerStatus.matchOver => _matchOverContent(r),
      CombatV1PlayableControllerStatus.safetyLimit => _safetyLimitContent(r),
      CombatV1PlayableControllerStatus.invariantViolation => _invariantContent(
        r,
      ),
      CombatV1PlayableControllerStatus.active ||
      CombatV1PlayableControllerStatus.error => _errorContent(),
    };
  }

  Widget _errorContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Match stopped due to internal consistency error',
          key: Key('combat_v1_playable_result_title'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _healthError,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          snapshot.diagnosticMessage ?? '内部エラーにより試合が停止しました。',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 16),
        _buttons(),
      ],
    );
  }

  Widget _safetyLimitContent(CombatV1PlayableMatchResult r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Match stopped',
          key: Key('combat_v1_playable_result_title'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _gold,
          ),
        ),
        const Text(
          'Safety limit reached',
          key: Key('combat_v1_playable_result_subtitle'),
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        _statsRows(r),
        const SizedBox(height: 16),
        _buttons(),
      ],
    );
  }

  Widget _invariantContent(CombatV1PlayableMatchResult r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Match stopped due to internal consistency error',
          key: Key('combat_v1_playable_result_title'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _healthError,
          ),
        ),
        const SizedBox(height: 16),
        _buttons(),
      ],
    );
  }

  Widget _matchOverContent(CombatV1PlayableMatchResult r) {
    final winnerIndex = r.winnerPlayerIndex;
    final title = winnerIndex == null
        ? 'Match Over'
        : winnerIndex == CombatV1PlayableMatchController.humanPlayerIndex
        ? 'YOU WIN'
        : 'CPU WIN';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: const Key('combat_v1_playable_result_title'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: _pink,
          ),
        ),
        const SizedBox(height: 4),
        if (r.terminalCause != null)
          Text(
            combatV1PlayableTerminalCauseLabel(r.terminalCause!),
            key: const Key('combat_v1_playable_result_cause'),
            style: const TextStyle(color: Colors.white70),
          ),
        const SizedBox(height: 12),
        _statsRows(r),
        const SizedBox(height: 16),
        _buttons(),
      ],
    );
  }

  Widget _statsRows(CombatV1PlayableMatchResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HP ${combatV1PlayableWrestlerDisplayName(r.humanWrestlerId)} '
          '${r.finalHumanStatus.hp}/${r.finalHumanStatus.maxHp}',
        ),
        Text(
          'HP ${combatV1PlayableWrestlerDisplayName(r.cpuWrestlerId)} '
          '${r.finalCpuStatus.hp}/${r.finalCpuStatus.maxHp}',
        ),
        Text('KOC ${r.finalHumanStatus.koc} / ${r.finalCpuStatus.koc}'),
        Text('Actions ${r.actionCount} ・ Turn ${r.finalTurnNumber}'),
      ],
    );
  }

  Widget _buttons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            key: const Key('combat_v1_playable_result_rematch_button'),
            onPressed: onRematch,
            child: const Text('Rematch'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            key: const Key('combat_v1_playable_result_back_button'),
            onPressed: onBack,
            child: const Text('Back'),
          ),
        ),
      ],
    );
  }
}
