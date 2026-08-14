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

import '../combat_v1_energy.dart';
import '../combat_v1_enums.dart';
import '../combat_v1_legal_action.dart';
import '../combat_v1_technique.dart';
import '../playable/combat_v1_playable_action_feedback.dart';
import '../playable/combat_v1_playable_match_config.dart';
import '../playable/combat_v1_playable_match_controller.dart'
    show CombatV1PlayableMatchController;
import '../playable/combat_v1_playable_match_result.dart';
import '../playable/combat_v1_playable_match_snapshot.dart';
import 'combat_v1_playable_feedback_formatters.dart';
import 'combat_v1_playable_match_direction.dart';
import 'combat_v1_playable_match_guidance.dart';
import 'combat_v1_playable_match_session.dart';
import 'combat_v1_playable_technique_traits.dart';
import 'combat_v1_playable_ui_formatters.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);
const _teal = Color(0xff5fd9c6);
const _cardSurface = Color(0xff211527);
const _healthError = Color(0xffff5c5c);
// Playable 2A-3「Technique Card — Decision Traits」——SUBMISSION/ROUGH
// badge専用の色。既存の_pink（YOU/FINISHER/DIRECT PIN）・_gold（CPU/
// COUNTER/HEAT）と視覚的に区別できるものを新規に割り当てる（18章
// 「Accessibility / Semantics」——色だけでtraitを区別しない前提のうえで、
// 追加の視覚区別として使う。文字labelは全badge共通で必須）。
const _submissionBadge = _teal;
const _roughBadge = Color(0xffb388ff);

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

  /// Playable 1C.1「Compact Rule Help」——大規模tutorialは作らず、Energy・
  /// COUNTER・PIN・KOC・Shared HEATの意味だけを短くまとめたdialogを
  /// 常時アクセス可能にする（30章「No Full Tutorial」・31章「First-Screen
  /// Clarity」）。
  void _showRulesHelp() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('用語ヘルプ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RulesHelpEntry(
                term: 'Technique Energy',
                body:
                    '技・COUNTERを使うために消費する属性別リソースです。'
                    '自分のターン開始時に全回復します（保有量そのものは'
                    '変化しません）。',
              ),
              _RulesHelpEntry(
                term: 'Shared HEAT',
                body:
                    '両者共有・蓄積型のリソースです（減りません）。既定'
                    '200に達するとFINISHERカードが解禁されます。',
              ),
              _RulesHelpEntry(
                term: 'COUNTER',
                body:
                    '相手の技に対して使用する返し技です。自分のTechnique '
                    '使用中は選べません（相手の技を受ける番のみ選べます）。',
              ),
              _RulesHelpEntry(
                term: 'PIN Cards',
                body:
                    'PINを仕掛ける際に使用する保有カード枚数です（開始時'
                    '2枚）。KICK OUTの結果によって相手との間で移動する'
                    'ことがあります。',
              ),
              _RulesHelpEntry(
                term: 'KOC',
                body:
                    'PINのKICK OUTやSUBMISSIONからの脱出に使うリソースです'
                    '（開始時10、防御側のみ消費）。必要なKOCを支払えないと、'
                    '3カウント／GIVE UPで試合が決着します。',
              ),
            ],
          ),
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
            key: const Key('combat_v1_playable_rules_help_button'),
            icon: const Icon(Icons.help_outline),
            tooltip: '用語ヘルプ',
            onPressed: _showRulesHelp,
          ),
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
                      // Playable 2A-5「1章 最重要方針」——両wrestlerの
                      // 背景状態（HP/KOC/PIN Cards等）をここへ隣接させて
                      // まとめる。以前はHuman status panelがhand群の下部
                      // （画面最下段近く）に独立して置かれ、Expandedへ
                      // 割り当てられる高さを圧迫していた（「4章 Hand
                      // Visibility」調査結果、`docs/design/
                      // combat_v1_playable_match_ui.md`Playable 2A-5追記
                      // 参照）。Tier 1（現在操作するTechnique hand）を
                      // 常時スクロールなしで比較できるようにするため、
                      // Tier優先度が相対的に低い「両者の背景ステータス」を
                      // 画面上部へ集約し、Expandedへ渡す残り高さを増やす。
                      _CpuStatusPanel(cpu: snapshot.cpu),
                      _HumanStatusPanel(human: snapshot.human),
                      _SharedStatusPanel(snapshot: snapshot),
                      // Playable 2A-5「9章 Guidance / Direction / Result /
                      // Logの圧縮」——Tier 3（Guidance）は常時表示のまま、
                      // Tier 4（Direction/Latest Result/Recent Log）は
                      // 既定で折りたたむ（`_ActorAndRecentPanel`参照）。
                      // 責務・情報自体は削除しない——明示操作（トグル）で
                      // 常に到達可能（design doc「70.10章」の到達可能性
                      // 原則を維持）。
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
                          // Playable 2A-6「4章 Sticky Technique Action」
                          // ——このExpanded領域を「scrollする詳細
                          // （hand＋技/discard情報）」と「常に固定表示の
                          // 技action footer」の2段Columnへ分割する。
                          // scrollできるのは前者だけ——後者
                          // （`_TechniqueStickyActionBar`）はscroll
                          // viewportの外側（兄弟）に置かれるため、
                          // どれだけhand/detailが長くなってもscroll
                          // せずに常に画面内へ残る。
                          child: Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  // Review Findings Fix（Minor、4.1章）
                                  // ——mobile visibility testが、この
                                  // 領域の実際のclip viewport（Expanded
                                  // へ割り当てられた高さ）を正確に取得
                                  // できるようにするためのkey。この
                                  // Viewport矩形こそが「実際に見えて
                                  // いる範囲」であり、画面全体のサイズ
                                  // をそのまま使うとAppBar/他panelの分
                                  // だけ広く見積もってしまう（実際には
                                  // この範囲外はscroll clipで見えない）。
                                  key: const Key(
                                    'combat_v1_playable_technique_area_scroll',
                                  ),
                                  child: _MatchBody(
                                    snapshot: snapshot,
                                    selectedCardInstanceId:
                                        _selectedCardInstanceId,
                                    onSelectCard: _onSelectCard,
                                    findAction: _findLegalAction,
                                    onSubmit: _submitAction,
                                  ),
                                ),
                              ),
                              _TechniqueStickyActionBar(
                                snapshot: snapshot,
                                selectedCardInstanceId:
                                    _selectedCardInstanceId,
                                findAction: _findLegalAction,
                                onSubmit: _submitAction,
                              ),
                            ],
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: _cpuBusy,
                        child: _PrimaryActionsBar(
                          snapshot: snapshot,
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

/// Playable 1C.1「Energy Insufficient — Safe Diagnosis」——`resolveEnergyPayment`
/// （Core Engineの支払い解決ロジックそのもの、`combat_v1_energy.dart`）を
/// 呼び出し側の公開snapshot値（[availableEnergy]）に対して再適用し、
/// 「今まさにこのCostを支払えるか」だけを判定する。isUsable自体の判定は
/// 一切変更しない（LegalActionが唯一のSSOTのまま）——ここではisUsable
/// ==falseになった"理由"がENERGYだと安全に断定できるかどうかの説明目的
/// のみに使う。
///
/// Playable 2A-5: `_HandCardTile`（手札card）と`_SelectedTechniquePanel`
/// （選択中Technique詳細panel）の両方が同じ判定を必要とするため、
/// module-level pure functionへ抽出し重複実装を避ける。
bool _techniqueEnergyWouldFail(
  CombatV1Technique technique,
  Map<CombatV1EnergyAttribute, int>? availableEnergy,
) {
  final available = availableEnergy;
  if (available == null) return false;
  final payment = resolveEnergyPayment(
    pool: CombatV1EnergyPool(available),
    spent: const {},
    cost: technique.energyCost,
    // Technique支払いは常にワイルド補完を許可する
    // （docs/combat_rules_v1.md 5.1章、Phase 1のTECHNIQUE支払いは常にtrue）。
    allowWildSubstitution: true,
  );
  return !payment.isSuccess;
}

/// Playable 1C「Finisher Feedback / Do Not Invent Finisher Reasons」——
/// 安全に判定できる理由（HEAT閾値・ENERGY支払い可否）だけを具体的に示し、
/// それ以外のlegality理由は断定しない（既存の汎用メッセージに留める）。
/// Playable 2A-5: `_HandCardTile`と`_SelectedTechniquePanel`の両方が
/// 同じ文言を必要とするため、module-level pure functionへ抽出する。
String _handCardDisabledMessage(
  CombatV1PlayableHandCard card, {
  int? sharedHeat,
  int? finisherHeatThreshold,
  Map<CombatV1EnergyAttribute, int>? availableEnergy,
}) {
  if (card.category == CombatV1CardCategory.counter) {
    // Playable 1C.1「Counter Semantics」——通常Action中にCOUNTER
    // cardが常にdisabledなのは「COUNTERは相手の技への応答専用」と
    // いう用途上の制約であって、ENERGY不足等ではない。用途を明示する。
    return '相手の技を受ける時に使用';
  }
  final threshold = finisherHeatThreshold;
  final heat = sharedHeat;
  if (card.category == CombatV1CardCategory.finisher &&
      threshold != null &&
      heat != null &&
      heat < threshold) {
    // Playable 2A-5 Review Findings Fix「7章 Minor — English unusable
    // reason」——HEATというゲーム用語自体は維持しつつ、説明部分を
    // 日本語化する。
    return 'HEATが不足しています（必要 $threshold / 現在 $heat）';
  }
  final technique = card.technique;
  if (technique != null && _techniqueEnergyWouldFail(technique, availableEnergy)) {
    final shortfall = combatV1PlayableEnergyComparisonLabel(
      technique.energyCost,
      availableEnergy!,
    );
    return 'Energy不足: $shortfall';
  }
  return '現在は使用できません';
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
                        // Playable 1C.1「KOC + PIN Relation」——PINのKICK
                        // OUTとSubmissionからの脱出、両方に使うリソース
                        // であることを明示する。
                        message:
                            'PINのKICK OUTやSubmissionからの脱出に使用す'
                            'るリソースです（開始時10、防御側のみ消費）',
                        child: Text(
                          'KOC $koc',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        'Hand $handCount',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Tooltip(
                        // Playable 1C.1「PIN Card vs Count Clarity」——
                        // ambiguousな「PIN N」ではなく「PIN Cards」と明示
                        // する（Match resultのcount feedbackとは別概念）。
                        message:
                            'PINを仕掛ける際に使用する保有カード枚数です'
                            '（開始時2枚）。KICK OUTの結果次第で相手との'
                            '間を移動します',
                        child: Text(
                          'PIN Cards $pinCardsHeld',
                          key: const Key('combat_v1_playable_pin_cards_text'),
                          style: const TextStyle(fontSize: 12),
                        ),
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

/// Playable 1C.1「Match Screen Energy Panel」（section 9、MUST）——
/// HumanのTechnique Energy構成（属性別、現在の使用可能量／保有量）を
/// 試合中いつでも確認できるようにする。Setup画面だけの表示では不十分
/// （section 9）。CPU側のENERGYは公開しない（hidden information、
/// `CombatV1PlayableOpponentStatus`自体がこの値を持たない）。
class _EnergyPanel extends StatelessWidget {
  const _EnergyPanel({required this.human});
  final CombatV1PlayableHumanStatus human;

  @override
  Widget build(BuildContext context) {
    // 保有量0の属性（そのレスラーがそもそも持たない属性）は表示しない。
    final attributes = [
      for (final attribute in CombatV1EnergyAttribute.values)
        if (human.energyPool.amountFor(attribute) > 0) attribute,
    ];
    if (attributes.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      // 8章「Do Not Call It "Current Energy" If Not Consumed」——技/
      // COUNTERで消費されるが、自ターン開始時に全回復するリソースである
      // ことを明示する。HEATとは別リソースであることも明示する（12章）。
      message:
          '技・COUNTERを使うために消費するENERGYです（Shared HEATとは'
          '別のリソースです）。「使用可能／保有」の形式で表示し、自分の'
          'ターン開始時に使用可能量が保有量まで全回復します',
      child: Container(
        key: const Key('combat_v1_playable_energy_panel'),
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Technique Energy',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 2,
                children: [
                  for (final attribute in attributes)
                    Text(
                      '${attribute.displayLabel} '
                      '${human.availableEnergy[attribute] ?? 0}/'
                      '${human.energyPool.amountFor(attribute)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
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

/// Review Findings Fix（Major、Playable 2A-2独立レビュー）——旧実装は
/// `ConstrainedBox(maxHeight: 132)` + `SingleChildScrollView(physics:
/// NeverScrollableScrollPhysics())`で、Match Guidance／Match
/// Direction／latest feedback banner／recent action logの内容が
/// 132pxを超えてもRenderFlex overflowは起きない一方、末尾の情報へ
/// ユーザーが一切到達できなかった（scrollが無効化されていたため）。
/// `_ActorAndRecentPanel`をStatefulWidget化し、実際にscroll可能な
/// `ScrollController`を保持することで、この領域を「安全なだけ」ではなく
/// 「実際に読める」ものにする（design doc「70.10章」）。
///
/// Playable 2A-5「9章 Guidance / Direction / Result / Logの圧縮」——
/// Tier 3（Match Guidance＝今何ができるか）は常時表示のまま、Tier 4
/// （Match Direction／Latest Result／Recent Log）は既定で折りたたむ
/// （`_detailExpanded`）。責務・情報は削除しない——`combat_v1_playable_
/// detail_toggle`を明示的にtapすると、以前と同じ内容（同じwidget/key）が
/// 実際にscroll到達可能な状態でそのまま展開される（design doc「70.10章」
/// の到達可能性原則を維持）。Latest Resultだけは、折りたたみ中も
/// 「直前に何が起きたか」を見失わないよう、既に確定済みのprimary文言を
/// 1行だけcompact表示する（新しいderivationは行わない、既存
/// `combatV1PlayableDeriveMatchFeedback`の出力をそのまま使う）。
class _ActorAndRecentPanel extends StatefulWidget {
  const _ActorAndRecentPanel({
    required this.snapshot,
    required this.humanPlayerIndex,
    required this.cpuBusy,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final int humanPlayerIndex;
  final bool cpuBusy;

  @override
  State<_ActorAndRecentPanel> createState() => _ActorAndRecentPanelState();
}

class _ActorAndRecentPanelState extends State<_ActorAndRecentPanel> {
  // このcontrollerは`_ActorAndRecentPanel`のStateが生きている間
  // （Match Screen自体がdisposeされるまで）保持される——毎buildで
  // 新規生成しないため、Scrollbarの`thumbVisibility: true`が要求する
  // 「ScrollPositionにattachされたScrollController」を安定して満たす。
  final ScrollController _scrollController = ScrollController();

  /// Playable 2A-5「9章」——既定は折りたたみ（Tier 1のTechnique handへ
  /// 縦方向の空間を譲る）。ユーザーがtapすると展開し、以後この
  /// `_ActorAndRecentPanel`が生きている間（同じ試合が続く間）は状態を
  /// 保持する——毎snapshot更新のたびに閉じ直されるとユーザー操作が
  /// 無意味になるため。
  bool _detailExpanded = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final humanPlayerIndex = widget.humanPlayerIndex;
    final cpuBusy = widget.cpuBusy;
    final actorLabel = combatV1PlayableActorLabel(
      status: snapshot.status,
      phase: snapshot.phase,
      isHumanInputRequired: snapshot.isHumanInputRequired,
      currentActorPlayerIndex: snapshot.currentActorPlayerIndex,
      hasPendingAttack: snapshot.pendingAttack != null,
    );
    // Playable 2A-1「Match Guidance」——actor labelのすぐ下へ統合する
    // （既存actor/phase表示と別panelへ重複表示しない、design doc
    // 「68章 Architecture」）。CPU処理中・試合終了時は`null`。
    final guidance = combatV1PlayableDeriveMatchGuidance(
      snapshot,
      humanPlayerIndex: humanPlayerIndex,
    );
    // Playable 1C「Recent Action Log Upgrade」——直近1件は大きめbanner、
    // その前のもの（compact list）をあわせて表示する（「Keep Log
    // Compact」——8件保持全件は必ずしも見せない、直近4件のみ）。
    final recents = snapshot.recentFeedback.reversed.skip(1).take(4).toList();
    final latestFeedback = snapshot.latestFeedback;
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
          if (guidance != null) _MatchGuidancePanel(guidance: guidance),
          if (!_detailExpanded && latestFeedback != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                combatV1PlayableDeriveMatchFeedback(
                  latestFeedback,
                  humanPlayerIndex: humanPlayerIndex,
                ).primary,
                key: const Key(
                  'combat_v1_playable_latest_feedback_compact_summary',
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TextButton(
              key: const Key('combat_v1_playable_detail_toggle'),
              onPressed: () =>
                  setState(() => _detailExpanded = !_detailExpanded),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _detailExpanded ? '▲ 閉じる' : '▼ 試合の詳細（勝利へのヒント・直前の結果・履歴）',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
          ),
          // Playable 1C「Keep Log Compact」——feedback内容量が可変のため、
          // ここだけ高さ上限つきにして、Human status panel/Primary
          // actions barが常に画面内へ収まる既存レイアウト（Expanded/
          // 固定bottom bar）を壊さないようにする。
          //
          // Playable 2A-2「Win Path / Match Direction」もこの内側へ置く
          // （17章「Mobile UX」——guidanceがTechnique areaを過度に
          // 押し下げないようにするため、常時表示の固定領域をこれ以上
          // 増やさない。Match Guidance/latest feedback/recent logと同じ
          // 「内容量が可変な情報」として同じ安全弁を共有する）。
          //
          // Review Findings Fix（Major）——高さ上限を超えた分は、以前は
          // `NeverScrollableScrollPhysics`によりRenderFlex overflowこそ
          // 起きないものの、ユーザーが一切scrollしてたどり着けなかった
          // （情報が存在はするが到達不能）。`Scrollbar` +
          // 実際にscroll可能な`SingleChildScrollView`へ変更し、
          // 「到達可能」であることを構造的に保証する（design doc
          // 「70.10章」）。この領域は画面上、Technique area
          // （`Expanded` + 独立した`SingleChildScrollView`）とは兄弟
          // 関係にあり親子関係にないため、双方のscroll gestureは競合
          // しない。
          //
          // Playable 2A-5: 既定で折りたたむため（`_detailExpanded ==
          // false`）widget自体を`SizedBox.shrink()`にする——高さ0の
          // `ConstrainedBox`ではなく完全に取り除くことで、Tier 1
          // （Technique hand）へ渡る`Expanded`の高さを実際に増やす。
          if (_detailExpanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  key: const Key('combat_v1_playable_actor_recent_scroll'),
                  controller: _scrollController,
                  child: Column(
                    children: [
                      _MatchDirectionPanel(
                        snapshot: snapshot,
                        humanPlayerIndex: humanPlayerIndex,
                      ),
                      if (latestFeedback != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _LatestFeedbackBanner(
                            feedback: latestFeedback,
                            humanPlayerIndex: humanPlayerIndex,
                          ),
                        ),
                      if (recents.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 6),
                          child: Wrap(
                            key: const Key('combat_v1_playable_recent_log'),
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              for (final (index, feedback) in recents.indexed)
                                Text(
                                  combatV1PlayableFeedbackCompactLabel(
                                    feedback,
                                    humanPlayerIndex: humanPlayerIndex,
                                  ),
                                  // Review Findings Fix（Major）——scroll
                                  // reachability testが、内容量が多い場合
                                  // でも末尾のlog entryへ実際にscroll経由で
                                  // 到達できることを、indexで安定した
                                  // widget keyから直接検証できるようにする。
                                  key: Key(
                                    'combat_v1_playable_recent_log_item_$index',
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
          ),
        ],
      ),
    );
  }
}

/// Playable 2A-1「Match Guidance」——「1行primary + 必要時のみ1行
/// secondary」（design doc「68章 UI / Mobile」）。tutorial panel／modalは
/// 追加せず、既存actor labelの直下へ小さく統合する。Combat rule判定は
/// 一切行わない——`combatV1PlayableDeriveMatchGuidance`が既に確定した
/// 文字列をそのまま表示するだけ。
class _MatchGuidancePanel extends StatelessWidget {
  const _MatchGuidancePanel({required this.guidance});

  final CombatV1PlayableMatchGuidance guidance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          Text(
            guidance.primary,
            key: const Key('combat_v1_playable_match_guidance_primary'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (guidance.secondary != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                guidance.secondary!,
                key: const Key('combat_v1_playable_match_guidance_secondary'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}

/// Playable 2A-2「Win Path / Match Direction」——「primary 1行 + 必要時
/// のみsecondary 1行」（design doc「70章 UI / Mobile」）。試合が`active`
/// である限りHuman/CPUどちらの手番でも表示する（Match Guidanceと違い
/// CPU処理中でも隠さない、`combat_v1_playable_match_direction.dart`
/// 参照）。Combat rule判定は一切行わない——
/// `combatV1PlayableDeriveMatchDirection`が既に確定した文字列をそのまま
/// 表示するだけ。Match Guidance（white70/38）とは配色を変え
/// （`_teal`）、2つのpanelを一目で区別できるようにする——ただしprimary
/// action（下部bottom bar）より視覚的に強くならない、控えめなfont
/// sizeのまま（17章「Mobile UX」）。
///
/// `_ActorAndRecentPanel`内の、latest feedback banner/recent logと同じ
/// 高さ上限つきscroll領域（`ConstrainedBox(maxHeight: 132)`）の中へ
/// 置く——常時表示の固定領域をこれ以上増やさず、guidanceがTechnique
/// areaを過度に押し下げないようにするため（17章「Mobile UX」）。
class _MatchDirectionPanel extends StatelessWidget {
  const _MatchDirectionPanel({
    required this.snapshot,
    required this.humanPlayerIndex,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final int humanPlayerIndex;

  @override
  Widget build(BuildContext context) {
    final direction = combatV1PlayableDeriveMatchDirection(
      snapshot,
      humanPlayerIndex: humanPlayerIndex,
    );
    if (direction == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        children: [
          Text(
            direction.primary,
            key: const Key('combat_v1_playable_match_direction_primary'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _teal,
            ),
          ),
          if (direction.secondary != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                direction.secondary!,
                key: const Key('combat_v1_playable_match_direction_secondary'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}

/// 直近1件のaction feedbackを表示する大きめbanner（Playable 1C「Action
/// Result Feedback」「Feedback Display Duration」、Playable 2A-4「Latest
/// Result — Primary / Secondary」）。次のactionのfeedbackが届くまで
/// 表示され続ける——CPUが400ms間隔で連続行動しても、直前の結果を読み
/// 逃さないようにする（大幅なCPU delay増加ではなく、feedback
/// persistenceで解決する方針）。
///
/// Match Guidance/Match Directionと同じ「primary（何が起きたか）+
/// secondary（その結果どう状態が変わったか）」の2段階構成
/// （`combatV1PlayableDeriveMatchFeedback`）。加えて、Tier 1/2
/// （試合結果に直結・大きな状態変化）は枠線・背景を強調し、情報階層
/// （design doc「Result Feedbackの情報階層」）を視覚的にも区別する
/// ——ただし色だけに依存しない（文言自体が既に事実を明示している、
/// 18章「Accessibility Semantics」）。
///
/// Playable 2A-6「6-7章 Technique Execution Feedback」——primary文言
/// 自体（「actor — 技名 — DAMAGE」の順序、`combatV1PlayableDeriveMatchFeedback`
/// が既に確定済み）は変更しない。「一目でactor・技名・結果が読める」
/// ことをfont weight/強調stateだけで底上げする（新しいderivationは
/// 行わない）——DOWNへ移行した事実（`feedback.postureBefore/After`、
/// 既存field）がある場合のみ、secondary文言と重複しない補助badgeとして
/// 明示する（推測で作らない、実際に観測されたposture差分のみを見る）。
class _LatestFeedbackBanner extends StatelessWidget {
  const _LatestFeedbackBanner({
    super.key,
    required this.feedback,
    required this.humanPlayerIndex,
  });

  final CombatV1PlayableActionFeedback feedback;
  final int humanPlayerIndex;

  @override
  Widget build(BuildContext context) {
    final result = combatV1PlayableDeriveMatchFeedback(
      feedback,
      humanPlayerIndex: humanPlayerIndex,
    );
    final isHuman = feedback.actorPlayerIndex == humanPlayerIndex;
    final color = isHuman ? _pink : _gold;
    final isDecisive =
        result.severity == CombatV1PlayableFeedbackSeverity.matchDecisive;
    final emphasized =
        isDecisive ||
        result.severity == CombatV1PlayableFeedbackSeverity.majorStateChange;
    // Playable 2A-6「6-7章」——実際に観測されたposture差分（`feedback`
    // 自身のfield）からのみDOWN badgeを出す。fabricateしない
    // ——Counter'd attackはそもそも`postureBefore`/`postureAfter`を
    // 一切設定しないため（`_buildFeedback` case counter参照）、この
    // badgeは自動的に出ない。
    final becameDown =
        feedback.postureBefore != null &&
        feedback.postureBefore != CombatV1WrestlerPosture.down &&
        feedback.postureAfter == CombatV1WrestlerPosture.down;
    return Container(
      key: const Key('combat_v1_playable_latest_feedback_banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasized ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: emphasized ? 0.85 : 0.6),
          width: emphasized ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(
                result.primary,
                key: const Key('combat_v1_playable_latest_feedback_primary'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  // Playable 2A-6「6-7章」——severityが高いほど、一目で
                  // 目に入るようfont weight/sizeを底上げする（新しい
                  // derivationではなく、既に確定済みのTierを表示スタイル
                  // へ機械的にmapするだけ）。
                  fontSize: isDecisive ? 15 : 14,
                  fontWeight: isDecisive ? FontWeight.w900 : FontWeight.bold,
                  color: color,
                ),
              ),
              if (becameDown)
                const _MiniBadge(label: 'DOWN', color: _healthError),
            ],
          ),
          if (result.secondary != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                result.secondary!,
                key: const Key('combat_v1_playable_latest_feedback_secondary'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
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

/// Playable 2A-5「5・7章」——`findAction`/`onSubmit`の型（screen state側の
/// `_findLegalAction`/`_submitAction`と同じ形）。技のカード選択→使用、
/// discardのカード選択→確定を、いずれもhand近くのinline panelから直接
/// submitできるようにするため、`_MatchBody`以下へ伝搬する。
typedef _FindLegalAction =
    CombatV1LegalAction? Function(
      CombatV1LegalActionKind kind, {
      String? cardInstanceId,
    });

/// Playable 2A-5「1章 最重要方針」——「カードを選び、必要コストを理解し、
/// 技を出す」ことを画面の中心に戻すための分岐点。discard phase（手札を
/// 捨てる）とaction phase（技を選んで使う）は、どちらも「手札からカードを
/// 選ぶ」操作に見えるが意味が全く異なるため（design doc「2章 最重要
/// 問題」）、ここで明確に別のarea（`_DiscardSelectionArea`／
/// `_TechniqueSelectionArea`）へ分岐する——同じ`_HandCardTile`見た目を
/// 両方の文脈で使い回さない。
class _MatchBody extends StatelessWidget {
  const _MatchBody({
    required this.snapshot,
    required this.selectedCardInstanceId,
    required this.onSelectCard,
    required this.findAction,
    required this.onSubmit,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final String? selectedCardInstanceId;
  final ValueChanged<String> onSelectCard;
  final _FindLegalAction findAction;
  final ValueChanged<CombatV1LegalAction> onSubmit;

  bool get _isDown =>
      snapshot.human.posture == CombatV1WrestlerPosture.down &&
      snapshot.phase == CombatV1MatchPhase.action;

  bool get _isDiscardPhase =>
      snapshot.phase == CombatV1MatchPhase.discard &&
      snapshot.isHumanInputRequired;

  @override
  Widget build(BuildContext context) {
    if (_isDown) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: _DownIndicator(),
      );
    }
    if (_isDiscardPhase) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _DiscardSelectionArea(
          hand: snapshot.human.hand,
          selectedCardInstanceId: selectedCardInstanceId,
          onSelectCard: onSelectCard,
          findAction: findAction,
          onSubmit: onSubmit,
          submissionHpThreshold: snapshot.submissionHpThreshold,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _TechniqueSelectionArea(
        snapshot: snapshot,
        selectedCardInstanceId: selectedCardInstanceId,
        onSelectCard: onSelectCard,
      ),
    );
  }
}

/// Playable 2A-5「6章 Energy Readability」——Tier 2情報（Technique
/// 使用判断に必要な情報）の一部として、Energyをhandのすぐ上へ常時表示
/// する。以前は画面最下段（Human status panelの下、Primary actions bar
/// の上）に独立して置かれ、Technique handへ割り当てられる縦方向の
/// 空間を圧迫していた（design doc Playable 2A-5追記「4章」参照）。
/// legality判定は一切行わない——既存`_EnergyPanel`をそのまま流用する。
class _TechniqueSelectionArea extends StatelessWidget {
  const _TechniqueSelectionArea({
    required this.snapshot,
    required this.selectedCardInstanceId,
    required this.onSelectCard,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final String? selectedCardInstanceId;
  final ValueChanged<String> onSelectCard;

  @override
  Widget build(BuildContext context) {
    final hand = snapshot.human.hand;
    final selectedCard = selectedCardInstanceId == null
        ? null
        : _firstWhereOrNull(
            hand,
            (card) => card.instanceId == selectedCardInstanceId,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EnergyPanel(human: snapshot.human),
        const SizedBox(height: 6),
        _HandRow(
          hand: hand,
          selectedCardInstanceId: selectedCardInstanceId,
          onSelectCard: onSelectCard,
          sharedHeat: snapshot.sharedHeat,
          finisherHeatThreshold: snapshot.finisherHeatThreshold,
          // Playable 1C.1「Card Cost Comparison」——通常Action中の
          // 手札には、返す先のpending攻撃が無い（`pendingAttack ==
          // null`）ため、COUNTERの動的必要量は表示しない
          // （`pendingEnergyCostTotal`は既定null）。
          availableEnergy: snapshot.human.availableEnergy,
          submissionHpThreshold: snapshot.submissionHpThreshold,
        ),
        if (selectedCard != null)
          _SelectedTechniquePanel(
            card: selectedCard,
            sharedHeat: snapshot.sharedHeat,
            finisherHeatThreshold: snapshot.finisherHeatThreshold,
            availableEnergy: snapshot.human.availableEnergy,
            submissionHpThreshold: snapshot.submissionHpThreshold,
          ),
      ],
    );
  }
}

/// Playable 2A-5「5章 Technique Selection → Action」——カードを選んだら
/// そのTechniqueの近く（handのすぐ下）で詳細を確認できるようにする。
/// 「使用可能／不可能」は`card.isUsable`（LegalAction SSOTからそのまま
/// 導出済み、`combat_v1_playable_match_controller.dart`参照）をそのまま
/// 表示するだけで、ここでlegalityを再計算しない。
///
/// Playable 2A-6「4章 Sticky Technique Action」——「技を使う」button
/// 自体はこのpanelから`_TechniqueStickyActionBar`（scrollしない固定
/// footer）へ移した。このpanelはscrollする詳細情報（badge/DMG/Energy/
/// posture/使用可否理由）のみを担当する——scroll可能領域の末尾まで
/// scrollしないと使用buttonへ到達できなかった問題（design doc Playable
/// 2A-6追記「4章」）を、button自体を常時可視な領域へ切り離すことで解決
/// する。
class _SelectedTechniquePanel extends StatelessWidget {
  const _SelectedTechniquePanel({
    required this.card,
    required this.sharedHeat,
    required this.finisherHeatThreshold,
    required this.availableEnergy,
    required this.submissionHpThreshold,
  });

  final CombatV1PlayableHandCard card;
  final int sharedHeat;
  final int finisherHeatThreshold;
  final Map<CombatV1EnergyAttribute, int> availableEnergy;
  final int submissionHpThreshold;

  @override
  Widget build(BuildContext context) {
    final technique = card.technique;
    if (technique == null) {
      // COUNTERカードを通常Action中に選択した場合——用途が違うことだけ
      // 明示し、Technique buttonは出さない（新しいlegality判定はしない、
      // 既存`_handCardDisabledMessage`と同じ安全な文言を再利用する）。
      return Container(
        key: const Key('combat_v1_playable_selected_counter_notice'),
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              card.displayName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _handCardDisabledMessage(
                card,
                sharedHeat: sharedHeat,
                finisherHeatThreshold: finisherHeatThreshold,
                availableEnergy: availableEnergy,
              ),
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      );
    }
    final disabled = !card.isUsable;
    return Container(
      key: const Key('combat_v1_playable_selected_technique_panel'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: disabled ? Colors.white24 : _pink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '使用する技',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
          Text(
            card.displayName,
            key: const Key('combat_v1_playable_selected_technique_name'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _TechniqueFactsBlock(
            technique: technique,
            submissionHpThreshold: submissionHpThreshold,
          ),
          const SizedBox(height: 8),
          _SelectedTechniqueEnergyBlock(
            technique: technique,
            availableEnergy: availableEnergy,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                disabled ? Icons.block : Icons.check_circle,
                size: 15,
                color: disabled ? _healthError : _teal,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  disabled
                      ? _handCardDisabledMessage(
                          card,
                          sharedHeat: sharedHeat,
                          finisherHeatThreshold: finisherHeatThreshold,
                          availableEnergy: availableEnergy,
                        )
                      : '使用可能',
                  key: const Key(
                    'combat_v1_playable_selected_technique_usable_status',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: disabled ? _healthError : _teal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Playable 2A-6「1・3・5章」——`_SelectedTechniquePanel`（Technique
/// 選択時の詳細）と、discard確認panel（`_DiscardConfirmPanel`「捨てる
/// カードの詳細」）が共通して必要とする「技の事実情報」（trait badge・
/// 属性full-word・DMG/HEAT・必要/結果posture）を1箇所へ集約する——両者で
/// 同じ情報行を重複実装しない（design doc Playable 2A-6追記「1章 Discard
/// UX」で明示された再利用方針）。legality判定・damage計算は一切行わない
/// ——既存`_TechniqueTraitBadges`・`combatV1Playable*Label`群が確定した
/// 値をそのまま並べるだけ。
class _TechniqueFactsBlock extends StatelessWidget {
  const _TechniqueFactsBlock({
    required this.technique,
    required this.submissionHpThreshold,
  });

  final CombatV1Technique technique;
  final int? submissionHpThreshold;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TechniqueTraitBadges(
          technique: technique,
          submissionHpThreshold: submissionHpThreshold,
        ),
        // Playable 2A-6「5章 Technique Identity Readability」——短縮形
        // （打／関／投／飛／ラフ）だけでなく、full-wordも並べて示す
        // （新しいcategorizationは作らない、既存enum値のfull-word表示）。
        Text(
          combatV1PlayableEnergyAttributeFullLabel(technique.attribute),
          key: const Key('combat_v1_playable_technique_attribute_full_label'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
        Text(
          '${technique.attribute.displayLabel} DMG ${technique.damage} '
          'HEAT ${technique.heatGain}',
          style: const TextStyle(fontSize: 13),
        ),
        if (technique.requiredOpponentState != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              combatV1PlayableRequiredOpponentStateLabel(
                technique.requiredOpponentState!,
              ),
              key: const Key('combat_v1_playable_card_required_posture'),
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ),
        if (technique.resultOpponentState != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              combatV1PlayableOpponentResultStateLabel(
                technique.resultOpponentState!,
              ),
              key: const Key('combat_v1_playable_card_result_posture'),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

/// Playable 2A-5「6章 Energy Readability」——「必要Energy」「現在Energy」を
/// 縦に並べて比較させる。ここで「使用可能」を判定・断定しない
/// （`card.isUsable`／LegalActionが唯一のSSOTのまま）——単に2つの公開
/// 数値を並べるだけの表示。
class _SelectedTechniqueEnergyBlock extends StatelessWidget {
  const _SelectedTechniqueEnergyBlock({
    required this.technique,
    required this.availableEnergy,
  });

  final CombatV1Technique technique;
  final Map<CombatV1EnergyAttribute, int> availableEnergy;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('combat_v1_playable_selected_technique_energy_block'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EnergyCompareRow(
            label: '必要 Energy',
            valueKey: const Key(
              'combat_v1_playable_selected_technique_required_energy',
            ),
            value: combatV1PlayableEnergyCostLabel(technique.energyCost.amounts),
          ),
          const SizedBox(height: 4),
          _EnergyCompareRow(
            label: '現在 Energy',
            valueKey: const Key(
              'combat_v1_playable_selected_technique_current_energy',
            ),
            value: combatV1PlayableEnergyAvailableLabel(
              technique.energyCost,
              availableEnergy,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnergyCompareRow extends StatelessWidget {
  const _EnergyCompareRow({
    required this.label,
    required this.valueKey,
    required this.value,
  });

  final String label;
  final Key valueKey;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ),
        Expanded(
          child: Text(
            value,
            key: valueKey,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// Playable 2A-5「7章 Technique使用とDiscardを明確に分離」／Playable
/// 2A-6「1章 Discard UX」——discard phase専用のarea。既存Core semantics
/// 調査結果（`combat_v1_legal_action_enumerator.dart`
/// `_enumerateDiscard`）どおり、手札の全カードが常に
/// `CombatV1DiscardAction`としてlegal（＝discard対象として選べる）で
/// あり、技としての使用可否とは無関係——そのため`_HandCardTile`を
/// discardMode（`discardMode: true`）で描画し、「捨てる」framingで
/// Technique modeと視覚的・文言的に区別する（「捨てるカードを選ぶ」と
/// 「技を選ぶ」を混同させないため、design doc Playable 2A-5追記
/// 「7章」）。
class _DiscardSelectionArea extends StatelessWidget {
  const _DiscardSelectionArea({
    required this.hand,
    required this.selectedCardInstanceId,
    required this.onSelectCard,
    required this.findAction,
    required this.onSubmit,
    required this.submissionHpThreshold,
  });

  final List<CombatV1PlayableHandCard> hand;
  final String? selectedCardInstanceId;
  final ValueChanged<String> onSelectCard;
  final _FindLegalAction findAction;
  final ValueChanged<CombatV1LegalAction> onSubmit;

  /// Playable 2A-6「1章」——「捨てるカードの詳細」panelが
  /// `_TechniqueFactsBlock`（trait badgeのTooltip）を再利用するために
  /// 必要な、公開済みのrule定数（`snapshot.submissionHpThreshold`）。
  final int submissionHpThreshold;

  @override
  Widget build(BuildContext context) {
    final selectedCard = selectedCardInstanceId == null
        ? null
        : _firstWhereOrNull(
            hand,
            (card) => card.instanceId == selectedCardInstanceId,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Column(
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
        const SizedBox(height: 8),
        _HandRow(
          hand: hand,
          selectedCardInstanceId: selectedCardInstanceId,
          onSelectCard: onSelectCard,
          discardMode: true,
        ),
        if (selectedCard != null)
          _DiscardConfirmPanel(
            card: selectedCard,
            submissionHpThreshold: submissionHpThreshold,
            action: findAction(
              CombatV1LegalActionKind.discard,
              cardInstanceId: selectedCard.instanceId,
            ),
            onSubmit: onSubmit,
          ),
      ],
    );
  }
}

/// Playable 2A-5「7章」／Playable 2A-6「1章 Discard UX」——「捨てるカード:
/// X」→「このカードを捨てて技を使う」ではなく（discard phaseは
/// Techniqueの追加コストではなく独立したフェーズのため、8章の実例を
/// そのまま実装しない）、「捨てるカード」を明示したうえで確定操作のみを
/// 提供する（「技を使う」style buttonは出さない）。別のカードをtapすると
/// 選択が切り替わる（`_onSelectCard`が既に持つtoggle/switch挙動をそのまま
/// 使う）ため、専用の「変更する」buttonは追加しない。
///
/// Playable 2A-6「1章」——確定buttonの前に「捨てるカードの詳細」panel
/// を追加した。`_SelectedTechniquePanel`が使う情報行
/// （`_TechniqueFactsBlock`：trait badge・属性full-word・DMG/HEAT・
/// 必要/結果posture）をそのまま再利用し、重複実装しない。
class _DiscardConfirmPanel extends StatelessWidget {
  const _DiscardConfirmPanel({
    required this.card,
    required this.submissionHpThreshold,
    required this.action,
    required this.onSubmit,
  });

  final CombatV1PlayableHandCard card;
  final int submissionHpThreshold;
  final CombatV1LegalAction? action;
  final ValueChanged<CombatV1LegalAction> onSubmit;

  @override
  Widget build(BuildContext context) {
    final technique = card.technique;
    final counter = card.counter;
    return Container(
      key: const Key('combat_v1_playable_discard_confirm_panel'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '捨てるカード',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
          Text(
            card.displayName,
            key: const Key('combat_v1_playable_discard_selected_card_name'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('combat_v1_playable_discard_card_detail'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '捨てるカードの詳細',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(height: 4),
                Text(
                  combatV1PlayableCategoryLabel(card.category),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                if (technique != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      // Playable 2A-6「1章」——「category/DMG/Energy/
                      // traits/posture」のうちEnergyは`_TechniqueFactsBlock`
                      // が持たない（Technique使用時の必要/現在Energy比較
                      // ＝`_SelectedTechniqueEnergyBlock`はTechnique
                      // 使用可否の文脈専用のため、discard詳細では必要
                      // Energyのみを示す既存`combatV1PlayableEnergyCostLabel`
                      // をそのまま使う）。
                      '必要Energy: '
                      '${combatV1PlayableEnergyCostLabel(technique.energyCost.amounts)}',
                      key: const Key(
                        'combat_v1_playable_discard_card_energy_cost_line',
                      ),
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _TechniqueFactsBlock(
                      technique: technique,
                      submissionHpThreshold: submissionHpThreshold,
                    ),
                  ),
                ] else if (counter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Cost属性 ${counter.attribute.displayLabel}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '別のカードをタップすると変更できます',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _ActionButton(
              key: const Key('combat_v1_playable_action_discard'),
              label: combatV1PlayableActionKindLabel(
                CombatV1LegalActionKind.discard,
              ),
              onPressed: action == null ? null : () => onSubmit(action!),
              primary: true,
            ),
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
            // 分かるよう、button前にそれぞれ短い説明を置く。Playable
            // 2A-5「8章 Japanese Primary Actions」——labelは実際のbutton
            // 文言（`combatV1PlayableActionKindLabel`）と一致させる。
            _ActionHint(
              key: const Key('combat_v1_playable_stand_up_hint'),
              label: combatV1PlayableActionKindLabel(
                CombatV1LegalActionKind.standUp,
              ),
              description: '立ち上がって、このターンの行動を続ける',
            ),
            const SizedBox(height: 4),
            _ActionHint(
              key: const Key('combat_v1_playable_rest_hint'),
              label: combatV1PlayableActionKindLabel(
                CombatV1LegalActionKind.rest,
              ),
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

/// 用語ヘルプdialog（`_showRulesHelp`）1件分の表示（用語 + 短い説明）。
class _RulesHelpEntry extends StatelessWidget {
  const _RulesHelpEntry({required this.term, required this.body});

  final String term;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(term, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(body, style: const TextStyle(fontSize: 12)),
        ],
      ),
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
    this.availableEnergy,
    this.submissionHpThreshold,
    this.discardMode = false,
  });

  final List<CombatV1PlayableHandCard> hand;
  final String? selectedCardInstanceId;
  final ValueChanged<String> onSelectCard;

  /// Playable 1C「Finisher Feedback」——finisher cardのHEAT要件表示用。
  /// COUNTER応答sheetなど、この文脈がない呼び出し元では`null`のままにする。
  final int? sharedHeat;
  final int? finisherHeatThreshold;

  /// Playable 1C.1「Card Cost Comparison」——Technique cardのCostと並べる、
  /// 現在Humanが使用可能なENERGY（属性別）。
  final Map<CombatV1EnergyAttribute, int>? availableEnergy;

  /// Playable 2A-3「SUBMISSION Wording」——SUBMISSION trait badgeの
  /// Tooltip文言に使う、公開済みのrule定数（`snapshot.submissionHpThreshold`）。
  final int? submissionHpThreshold;

  /// Playable 2A-5「7章」／Playable 2A-6「1章 Discard UX」——discard
  /// phase専用の表示modeへ切り替える。`true`の場合、`_HandCardTile`は
  /// 「捨てる」framing（別のverb label・色）で描画される。Playable 2A-5
  /// 時点ではTechnique文脈の情報（DMG/Energy/trait）を一切出さない設計
  /// だったが、実プレイテストで「情報が無さすぎて比較できない」問題が
  /// 判明したため、Playable 2A-6でCategory/必要Energy/DMG/主要trait
  /// chipを「技として使う場合の参考情報」として復元した——ただし
  /// 「技として使用可否」はdiscard自体の可否とは無関係であることを
  /// 明示し（discard phaseは手札の全カードが常にdiscard対象として
  /// legal）、「捨てるカードを選ぶ」と「技を選ぶ」の混同は引き続き防ぐ。
  final bool discardMode;

  @override
  Widget build(BuildContext context) {
    if (hand.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('手札がありません', style: TextStyle(color: Colors.white38)),
      );
    }
    // Playable 2A-5 Review Findings Fix「2〜4章 Hand Comparison」——
    // 初期5枚のTechnique handを横scroll無しで比較できるようにする。
    // 268px幅カードの横scroll listだった旧実装は、320〜390px幅では
    // 同時に2枚程度しか見えず、5枚を比較するために必ずscrollが必要
    // だった。`Wrap`で折り返す固定幅compact card
    // （`_HandCardTile(compactMode: true)`）へ置き換え、詳細
    // （DMG/HEAT/trait/posture/使用不可理由）は選択後に現れる
    // `_SelectedTechniquePanel`（`_TechniqueSelectionArea`側）が担当
    // する——「一覧＝比較」「詳細＝判断確認」の責務分離（design doc
    // Playable 2A-5 Review Findings Fix追記参照）。
    //
    // Playable 2A-6「1章 Discard UX」——discard phaseも同じ
    // `Wrap`パターンへ揃える。以前は横scroll `ListView`のままだった
    // （Playable 2A-5では「discard UXを流用・変更しない」方針だった）が、
    // 実プレイテストで「捨てる候補を比較しにくい」問題が新たに判明した
    // ため、5枚を横scroll無しで比較できるcompactな`Wrap`表示へ変更する
    // （`_HandCardTile._buildDiscardMode`側でTechnique modeとは異なる
    // 「捨てる」framingを明示し、混同を防ぐ）。
    return Wrap(
      key: const Key('combat_v1_playable_human_hand'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final card in hand)
          _HandCardTile(
            key: ValueKey('combat_v1_playable_hand_card_${card.instanceId}'),
            card: card,
            selected: card.instanceId == selectedCardInstanceId,
            onTap: () => onSelectCard(card.instanceId),
            sharedHeat: sharedHeat,
            finisherHeatThreshold: finisherHeatThreshold,
            availableEnergy: availableEnergy,
            submissionHpThreshold: submissionHpThreshold,
            discardMode: discardMode,
            compactMode: !discardMode,
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
    this.availableEnergy,
    this.pendingEnergyCostTotal,
    this.submissionHpThreshold,
    this.pendingAttackFamily,
    this.discardMode = false,
    this.compactMode = false,
  });

  final CombatV1PlayableHandCard card;
  final bool selected;
  final VoidCallback onTap;
  final int? sharedHeat;
  final int? finisherHeatThreshold;

  /// Playable 1C.1「Card Cost Comparison」——現在Humanが使用可能な
  /// ENERGY（属性別）。Technique cardのCostと並べて表示する。
  final Map<CombatV1EnergyAttribute, int>? availableEnergy;

  /// Playable 1C.1「COUNTER Dynamic Cost」——`counterResponsePending`中の
  /// pending攻撃のENERGY COST合計（`CombatV1EnergyCost.total`）。Counter
  /// cardのCostはこの値を、Counter自身の単一属性で支払う（docs 7章）。
  final int? pendingEnergyCostTotal;

  /// Playable 2A-3「SUBMISSION Wording」——SUBMISSION trait badgeの
  /// Tooltip文言用（`snapshot.submissionHpThreshold`をそのまま渡す）。
  /// この文脈が無い呼び出し元では`null`のままにする（Tooltip自体は
  /// 表示しても具体的な閾値行を出さない安全側フォールバック）。
  final int? submissionHpThreshold;

  /// Playable 2A-3「Counter Card Information」——`counterResponsePending`
  /// 中のpending攻撃のtechnique family（`CombatV1PlayablePendingAttackView.family`）。
  /// Counter card分岐でのみ使う——このCounterが現在のpending攻撃を
  /// family一致／group一致のどちらで返せるかを表示する。
  final CombatV1TechniqueFamily? pendingAttackFamily;

  /// Playable 2A-5「7章」——discard phase専用の簡略表示へ切り替える。
  /// discard phaseでは手札の全カードが常にdiscard対象としてlegalの
  /// ため（`combat_v1_legal_action_enumerator.dart` `_enumerateDiscard`
  /// 参照）、`card.isUsable`（Technique使用可否）をここでは参照しない
  /// ——参照すると「技として使えないカードだから捨てる対象にできない」
  /// ように誤読させてしまう。
  final bool discardMode;

  /// Playable 2A-5 Review Findings Fix「3章 Compact Hand」——hand一覧
  /// （比較段階）専用のcompact表示へ切り替える。DMG/HEAT/posture/traitの
  /// 全detailや使用不可の理由は出さない——それらは選択後に現れる
  /// `_SelectedTechniquePanel`（同じ`card`から独立に導出、詳細＝判断
  /// 確認の責務）が担当する。`_CounterPromptSheet`（Counter応答時の
  /// hand）はこのmodeを使わず、既存の詳細表示のまま維持する
  /// （Counter候補は通常1〜3枚程度で、2A-3で確立したreadabilityを
  /// 壊さないため）。
  final bool compactMode;

  @override
  Widget build(BuildContext context) {
    if (discardMode) {
      return _buildDiscardMode(context);
    }
    if (compactMode) {
      return _buildCompactMode(context);
    }
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
                    // Playable 2A-3「Technique Card — Decision Traits」
                    // （Tier 1: 勝敗ルート）——DMG/HEAT等の即時結果（Tier
                    // 2）より先に、成立後の勝敗ルート（DIRECT PIN/
                    // SUBMISSION/ROUGH/FINISHER決着方式）を示す。「今
                    // 使用可能か」（LegalAction）とは別概念であることは
                    // 各Tooltipの文言側で明示する（7〜11章）。
                    _TechniqueTraitBadges(technique: technique, submissionHpThreshold: submissionHpThreshold),
                    Text(
                      '${technique.attribute.displayLabel} DMG ${technique.damage} '
                      'HEAT ${technique.heatGain}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    // Playable 1C.1「Card Cost Comparison」——`Cost X`だけ
                    // ではなく、現在Humanが使用可能なENERGYと並べて表示
                    // する（`availableEnergy`が無い呼び出し元ではCostのみ
                    // の従来表示にfallbackする）。
                    Text(
                      availableEnergy != null
                          ? 'Energy ${combatV1PlayableEnergyComparisonLabel(technique.energyCost, availableEnergy!)}'
                          : 'Cost ${combatV1PlayableEnergyCostLabel(technique.energyCost.amounts)}',
                      key: const Key('combat_v1_playable_card_energy_line'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    // Playable 1C.1「Opponent Target Label」（section 19・
                    // 20・32）——requiredOpponentState/resultOpponentStateは
                    // いずれも常に「相手」を指す（技モデルに自分自身の
                    // postureを変える field は存在しない、section
                    // 21「Self-Down Possibility」調査結果）。対象を明示
                    // せず単独で`DOWN`/`STAND`とだけ表示することはしない。
                    if (technique.requiredOpponentState != null)
                      Text(
                        combatV1PlayableRequiredOpponentStateLabel(
                          technique.requiredOpponentState!,
                        ),
                        key: const Key(
                          'combat_v1_playable_card_required_posture',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    if (technique.resultOpponentState != null)
                      Text(
                        combatV1PlayableOpponentResultStateLabel(
                          technique.resultOpponentState!,
                        ),
                        key: const Key(
                          'combat_v1_playable_card_result_posture',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ] else if (counter != null) ...[
                    // Playable 1C.1「COUNTER Dynamic Cost」——pending攻撃の
                    // 文脈がある場合のみ具体的な必要量を示す（section
                    // 7章「返し必要コストは返される側のTECHNIQUEのENERGY
                    // COST総量と同値」）。通常Actionの手札表示では文脈が
                    // 無いため、必要量が固定でないことだけを説明する。
                    Text(
                      pendingEnergyCostTotal != null
                          ? 'Cost ${counter.attribute.displayLabel}$pendingEnergyCostTotal'
                          : 'Cost属性 ${counter.attribute.displayLabel}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    if (pendingEnergyCostTotal == null)
                      const Text(
                        '必要量は返す技によって変わります',
                        style: TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                    // Playable 2A-3「Counter Card Information」（Tier 4:
                    // advanced）——このCounterが現在のpending攻撃をどう
                    // 返せるか（family一致／group一致）。表示専用の
                    // 言い換えであり、legality判定自体はCore（既にこの
                    // Counterがusableとして表示されている前提）のまま。
                    if (pendingAttackFamily != null)
                      Builder(
                        builder: (context) {
                          final label = combatV1PlayableCounterFamilyMatchLabel(
                            counter,
                            pendingAttackFamily!,
                          );
                          if (label == null) return const SizedBox.shrink();
                          return Text(
                            '対応: $label',
                            key: const Key(
                              'combat_v1_playable_counter_family_match',
                            ),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white54,
                            ),
                          );
                        },
                      ),
                  ],
                  const SizedBox(height: 4),
                  if (card.category == CombatV1CardCategory.counter)
                    const Wrap(
                      spacing: 4,
                      children: [_MiniBadge(label: 'COUNTER', color: _gold)],
                    ),
                  // finisher要件hintとdisabledメッセージは、どちらもHEAT
                  // 要件について述べる内容が重複しうるため同時には出さない
                  // （disabled時は`_handCardDisabledMessage()`側がHEAT要件を
                  // 含む）。
                  if (!disabled &&
                      card.category == CombatV1CardCategory.finisher &&
                      threshold != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'HEAT $threshold以上で使用可',
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
                        _handCardDisabledMessage(
                          card,
                          sharedHeat: sharedHeat,
                          finisherHeatThreshold: finisherHeatThreshold,
                          availableEnergy: availableEnergy,
                        ),
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

  /// Playable 2A-5「7章 Technique使用とDiscardを明確に分離」／Playable
  /// 2A-6「1章 Discard UX」——discard phase専用のcompact tile。
  ///
  /// Playable 2A-5時点ではDMG/HEAT/Energy/trait badge/使用可否を一切
  /// 出さない設計だったが、実プレイテストで「情報が無さすぎて、捨てる
  /// カードを比較できない」問題が判明した（design doc Playable 2A-6
  /// 追記「3章」）。そのため、`_buildCompactMode`と同じ`_compactPrimaryTrait`
  /// を再利用しつつ、category/必要Energy/DMG/主要trait chipを表示する
  /// ——ただし「技として使う場合の参考情報」であることを明示し、
  /// 「捨てる」framing（verb label・色・selected文言）で終始
  /// `_buildCompactMode`（Technique用）と視覚的・文言的に区別する
  /// （色だけに依存しない、18章「Accessibility / Semantics」と同じ
  /// 方針）。
  ///
  /// `card.isUsable`をここでも参照するが、これは「捨てられるか」では
  /// なく「（参考として）現在Technique actionとしても legal か」を示す
  /// だけ——discard自体は手札の全カードが常にlegal（`combat_v1_legal_
  /// action_enumerator.dart` `_enumerateDiscard`）なので、新しいlegality
  /// 判定を作らずSSOTをそのまま読むだけで安全に表示できる。
  Widget _buildDiscardMode(BuildContext context) {
    final technique = card.technique;
    final counter = card.counter;
    final trait = technique == null ? null : _compactPrimaryTrait(technique);
    return Semantics(
      button: true,
      selected: selected,
      label: '${card.displayName}を捨てる',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          key: Key(
            'combat_v1_playable_discard_hand_card_${card.instanceId}',
          ),
          width: 96,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: _cardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _gold : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Playable 2A-6「1章」——「捨てる」framingを明示するlabel。
              // Technique compact tileには存在しない行のため、tap前でも
              // 一目で「これはdiscard用tileだ」と区別できる（色だけに
              // 頼らない）。
              const Text(
                '捨てる',
                key: Key('combat_v1_playable_discard_card_verb_label'),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: _gold,
                ),
              ),
              Text(
                card.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              Text(
                combatV1PlayableCategoryLabel(card.category),
                style: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
              if (technique != null) ...[
                const SizedBox(height: 3),
                Text(
                  combatV1PlayableEnergyCostLabel(
                    technique.energyCost.amounts,
                  ),
                  key: const Key('combat_v1_playable_discard_card_energy_line'),
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
                Text(
                  'DMG ${technique.damage}',
                  style: const TextStyle(fontSize: 9, color: Colors.white54),
                ),
                if (trait != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _MiniBadge(label: trait.label, color: trait.color),
                  ),
              ] else if (counter != null) ...[
                const SizedBox(height: 3),
                const Text(
                  'COUNTER',
                  style: TextStyle(fontSize: 9, color: Colors.white70),
                ),
              ],
              if (technique != null || counter != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Tooltip(
                    // Playable 2A-6「1章」——discard自体は常にlegalで
                    // あり、この行が示すのはあくまで「技として使う場合」
                    // の参考情報であることを明示する（discard可否とは
                    // 無関係）。
                    message:
                        'このカードを技として使用できるかの参考情報です。'
                        '捨てる操作自体は常に選べます',
                    child: Text(
                      '技として使用: ${card.isUsable ? '可' : '不可'}',
                      key: const Key(
                        'combat_v1_playable_discard_card_technique_usable_reference',
                      ),
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '捨てるカードとして選択中',
                    key: const Key(
                      'combat_v1_playable_discard_card_selected_marker',
                    ),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: _gold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Playable 2A-5 Review Findings Fix「3章A Compact Hand」——一覧
  /// （比較）専用のcompact tile。必須: 識別できる名前・required
  /// Energy・使用可能／不可能・selected state。可能な範囲でDMG・major
  /// trait（FINISHER/PIN/SUBMISSION/ROUGHのいずれか1つ、優先順位は
  /// `_TechniqueTraitBadges`と同じ）を追加する——全trait detail・
  /// posture・使用不可の具体的理由は選択後の`_SelectedTechniquePanel`
  /// （下記`_compactPrimaryTrait`と同じ優先度だが、そちらは複数trait
  /// 同時表示・Tooltip付きの完全版）に譲る。
  Widget _buildCompactMode(BuildContext context) {
    final technique = card.technique;
    final counter = card.counter;
    final disabled = !card.isUsable;
    final trait = technique == null ? null : _compactPrimaryTrait(technique);
    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: card.displayName,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 92,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? _pink : Colors.white24,
                width: selected ? 2 : 1,
              ),
            ),
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
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                if (technique != null) ...[
                  // Playable 2A-6「5章 Technique Identity Readability」
                  // ——短縮形（打／関／投／飛／ラフ、Energy行の中に埋め
                  // 込まれている）だけでなく、その技の種類をfull-wordで
                  // 明示する。新しいcategorizationは追加しない（既存
                  // `CombatV1EnergyAttribute`のfull-word表示のみ）。
                  Text(
                    combatV1PlayableEnergyAttributeFullLabel(
                      technique.attribute,
                    ),
                    key: const Key('combat_v1_playable_compact_card_attribute'),
                    style: const TextStyle(fontSize: 9, color: Colors.white54),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          combatV1PlayableEnergyCostLabel(
                            technique.energyCost.amounts,
                          ),
                          key: const Key('combat_v1_playable_card_energy_line'),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      Icon(
                        disabled ? Icons.block : Icons.check_circle,
                        key: const Key(
                          'combat_v1_playable_compact_card_usable_icon',
                        ),
                        size: 12,
                        color: disabled ? _healthError : _teal,
                      ),
                    ],
                  ),
                  Text(
                    'DMG ${technique.damage}',
                    style: const TextStyle(fontSize: 9, color: Colors.white54),
                  ),
                  if (trait != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _MiniBadge(label: trait.label, color: trait.color),
                    ),
                ] else if (counter != null) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'COUNTER',
                          style: TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                      ),
                      Icon(
                        disabled ? Icons.block : Icons.check_circle,
                        key: const Key(
                          'combat_v1_playable_compact_card_usable_icon',
                        ),
                        size: 12,
                        color: disabled ? _healthError : _teal,
                      ),
                    ],
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

/// Playable 2A-5 Review Findings Fix「3章A Compact Hand」——compact card
/// へ載せる、最大1つのmajor trait（FINISHER/PIN/SUBMISSION/ROUGH）。
/// `_TechniqueTraitBadges`と同じ優先度（FINISHER category＞DIRECT
/// PIN＞SUBMISSION、ROUGHは常に独立して判定）だが、compact cardは
/// スペースが限られるため、FINISHERの場合は"FINISHER · PIN"のような
/// 合成labelではなく単独の`FINISHER`のみを示す（ROUGHとの併記もしない）。
/// 全trait・詳細な合成labelは選択後の`_TechniqueTraitBadges`
/// （`_SelectedTechniquePanel`内）が引き続き担当する。新しいtrait判定
/// ロジックは追加しない——既存の`combat_v1_playable_technique_traits.dart`
/// pure functionをそのまま参照するだけ。
({String label, Color color})? _compactPrimaryTrait(
  CombatV1Technique technique,
) {
  if (technique.category == CombatV1CardCategory.finisher) {
    return (label: 'FINISHER', color: _pink);
  }
  if (combatV1PlayableTechniqueHasEffectiveDirectPin(technique)) {
    return (label: 'PIN', color: _pink);
  }
  if (combatV1PlayableTechniqueHasEffectiveSubmissionHold(technique)) {
    return (label: 'SUBMISSION', color: _submissionBadge);
  }
  if (combatV1PlayableTechniqueIsRough(technique)) {
    return (label: 'ROUGH', color: _roughBadge);
  }
  return null;
}

/// Playable 2A-3「Technique Card — Decision Traits」（5・6章）——
/// FINISHER決着方式・DIRECT PIN・SUBMISSION・ROUGHという、勝敗判断上
/// 重要なtraitを短いbadgeで示す。Combat rule判定は一切行わない——
/// `combat_v1_playable_technique_traits.dart`（pure derivation）が
/// 既に確定した値をbadge/Tooltipへ機械的にmapするだけ。
///
/// 色だけでtraitを区別しない（18章「Accessibility / Semantics」）——
/// 各badgeは常に文字labelを持つ。`Tooltip`で detail 文言（9〜11章の
/// 安全な言い回し）を補足する。
class _TechniqueTraitBadges extends StatelessWidget {
  const _TechniqueTraitBadges({
    required this.technique,
    this.submissionHpThreshold,
  });

  final CombatV1Technique technique;
  final int? submissionHpThreshold;

  @override
  Widget build(BuildContext context) {
    final isFinisher = technique.category == CombatV1CardCategory.finisher;
    final directPin = combatV1PlayableTechniqueHasEffectiveDirectPin(
      technique,
    );
    final submissionHold = combatV1PlayableTechniqueHasEffectiveSubmissionHold(
      technique,
    );
    final rough = combatV1PlayableTechniqueIsRough(technique);

    final badges = <Widget>[
      if (isFinisher)
        _TraitBadge(
          key: const Key('combat_v1_playable_card_finisher_resolution_badge'),
          label: combatV1PlayableFinisherResolutionBadgeLabel(
            technique.finisherType!,
          ),
          color: _pink,
          detail: switch (technique.finisherType!) {
            CombatV1FinisherType.normal =>
              'Shared HEAT解禁後に使用できるFINISHERです（成功後、決着方式は'
                  '固定されていません）',
            CombatV1FinisherType.directPin => combatV1PlayableDirectPinTraitDetail(),
            CombatV1FinisherType.submission => submissionHpThreshold == null
                ? '成立後、条件を満たすとSubmission判定に自動移行します'
                : combatV1PlayableSubmissionTraitDetail(submissionHpThreshold!),
          },
        )
      else ...[
        if (directPin)
          _TraitBadge(
            key: const Key('combat_v1_playable_card_direct_pin_badge'),
            label: 'DIRECT PIN',
            color: _pink,
            detail: combatV1PlayableDirectPinTraitDetail(),
          ),
        if (submissionHold)
          _TraitBadge(
            key: const Key('combat_v1_playable_card_submission_badge'),
            label: 'SUBMISSION',
            color: _submissionBadge,
            detail: submissionHpThreshold == null
                ? '成立後、条件を満たすとSubmission判定に自動移行します'
                : combatV1PlayableSubmissionTraitDetail(submissionHpThreshold!),
          ),
      ],
      if (rough)
        _TraitBadge(
          key: const Key('combat_v1_playable_card_rough_badge'),
          label: 'ROUGH',
          color: _roughBadge,
          detail: combatV1PlayableRoughTraitDetail(),
        ),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        key: const Key('combat_v1_playable_card_trait_badges'),
        spacing: 4,
        runSpacing: 4,
        children: badges,
      ),
    );
  }
}

class _TraitBadge extends StatelessWidget {
  const _TraitBadge({
    super.key,
    required this.label,
    required this.color,
    required this.detail,
  });

  final String label;
  final Color color;
  final String detail;

  @override
  Widget build(BuildContext context) =>
      Tooltip(message: detail, child: _MiniBadge(label: label, color: color));
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

/// Playable 2A-6「4章 Sticky Technique Action」——Technique選択時の
/// 「技を使う」action（またはそのdisabled状態＋理由）を、scrollしても
/// 必ず画面内へ残る固定footerとして提供する。
///
/// 経緯（design doc Playable 2A-6追記「4章」）: 以前は同じbuttonが
/// `_SelectedTechniquePanel`（`_TechniqueSelectionArea`側、hand＋詳細と
/// 同じscroll領域内）の末尾にあり、hand（`Wrap`、可変行数）＋詳細panelが
/// 短い画面で画面内へ収まりきらない場合、buttonへ到達するために
/// scrollが必要だった。この widget は`_TechniqueSelectionArea`を包む
/// `SingleChildScrollView`の**外側**（同じ`Expanded`領域内の兄弟）に
/// 置かれるため、常にvisible/hit-testableになる。
///
/// `_PrimaryActionsBar`（Stand Up/Rest/PIN/End Turn専用）とは意図的に
/// 統合しない——2A-5でTechnique使用とその他の行動を分離した設計判断
/// （「カードを選ぶ／選ばない」に依存する行動と依存しない行動を分ける）を
/// 維持する。legality判定は一切行わない——`card.isUsable`／
/// `findAction`（LegalAction SSOT）をそのまま読むだけ。
class _TechniqueStickyActionBar extends StatelessWidget {
  const _TechniqueStickyActionBar({
    required this.snapshot,
    required this.selectedCardInstanceId,
    required this.findAction,
    required this.onSubmit,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
  final String? selectedCardInstanceId;
  final _FindLegalAction findAction;
  final ValueChanged<CombatV1LegalAction> onSubmit;

  /// `_TechniqueSelectionArea`が実際にrenderされる条件
  /// （`_MatchBody._isDown`/`_isDiscardPhase`と同じ判定）と一致させる
  /// ——Technique選択panel自体が表示されない局面（DOWN／discard／CPU
  /// 手番／Counter応答）ではこのbuttonも出さない。
  bool get _isTechniquePhase =>
      snapshot.isHumanInputRequired &&
      snapshot.phase == CombatV1MatchPhase.action &&
      snapshot.human.posture != CombatV1WrestlerPosture.down;

  @override
  Widget build(BuildContext context) {
    if (!_isTechniquePhase) return const SizedBox.shrink();
    final instanceId = selectedCardInstanceId;
    if (instanceId == null) return const SizedBox.shrink();
    final card = _firstWhereOrNull(
      snapshot.human.hand,
      (c) => c.instanceId == instanceId,
    );
    final technique = card?.technique;
    // COUNTERカードが選択されている場合（`_SelectedTechniquePanel`が
    // 用途説明のみを表示するcase）はTechnique buttonを出さない——
    // COUNTERは相手の技への応答専用のため（既存`_handCardDisabledMessage`
    // と同じ理由）。
    if (card == null || technique == null) return const SizedBox.shrink();

    final disabled = !card.isUsable;
    final action = findAction(
      CombatV1LegalActionKind.technique,
      cardInstanceId: card.instanceId,
    );
    final reason = disabled
        ? _handCardDisabledMessage(
            card,
            sharedHeat: snapshot.sharedHeat,
            finisherHeatThreshold: snapshot.finisherHeatThreshold,
            availableEnergy: snapshot.human.availableEnergy,
          )
        : null;

    return Container(
      key: const Key('combat_v1_playable_technique_sticky_action_bar'),
      width: double.infinity,
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                // Playable 2A-6「4章」——disabled理由をbutton直上へ明示
                // する（例:「使用できません\nEnergyが不足しています\n
                // 必要 3 / 現在 2」に相当する情報——具体的な理由文言
                // 自体は既存`_handCardDisabledMessage`のSSOTをそのまま
                // 使い、新しい理由判定は作らない）。
                '使用できません\n$reason',
                key: const Key(
                  'combat_v1_playable_technique_sticky_disabled_reason',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: _healthError),
              ),
            ),
          _ActionButton(
            key: const Key('combat_v1_playable_action_technique'),
            label: combatV1PlayableActionKindLabel(
              CombatV1LegalActionKind.technique,
            ),
            onPressed: (disabled || action == null)
                ? null
                : () => onSubmit(action),
            primary: true,
          ),
        ],
      ),
    );
  }
}

/// Playable 2A-5「5・7章」・Playable 2A-6「4章」——Technique使用
/// （「技を使う」）は`_TechniqueStickyActionBar`（固定footer）へ、discard
/// （「手札を捨てる」）はカード選択と一体のinline panel
/// （`_DiscardConfirmPanel`、hand直下）へ、それぞれ独立して存在する。
/// この下部barはカード選択と無関係な行動（Stand Up/Rest/PIN/End Turn）
/// のみを扱う——「カードを選ぶ／選ばない」に依存しない行動だけがここに
/// 残る。
class _PrimaryActionsBar extends StatelessWidget {
  const _PrimaryActionsBar({
    required this.snapshot,
    required this.busy,
    required this.findAction,
    required this.onSubmit,
  });

  final CombatV1PlayableMatchSnapshot snapshot;
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
    if (snapshot.phase == CombatV1MatchPhase.discard) {
      // Playable 2A-5「7章」——discardの確定操作は`_DiscardConfirmPanel`
      // （hand直下）へ移動したため、この下部barには何も出さない。
      return const SizedBox(height: 8);
    }

    final kinds = snapshot.legalActions.map((a) => a.kind).toSet();
    final buttons = <Widget>[];

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
          label: combatV1PlayableActionKindLabel(CombatV1LegalActionKind.rest),
          onPressed: action == null ? null : () => onSubmit(action),
        ),
      );
    }
    if (kinds.contains(CombatV1LegalActionKind.pin)) {
      final action = findAction(CombatV1LegalActionKind.pin);
      buttons.add(
        // Playable 1C.1「PIN Action Condition Help」（section 25）——
        // このbuttonはLegalActionが実在する時にのみ表示される
        // （＝現在まさにPIN宣言条件を満たしている）。完全な条件の羅列
        // ではなく、短い説明をtooltipとして添える。
        Tooltip(
          message:
              'PINカードを1枚使ってDOWN中の相手にPINを仕掛けます'
              '（このターン中に技を成功させている場合のみ選択できます）',
          child: _ActionButton(
            key: const Key('combat_v1_playable_action_pin'),
            label: combatV1PlayableActionKindLabel(
              CombatV1LegalActionKind.pin,
            ),
            onPressed: action == null ? null : () => onSubmit(action),
          ),
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
  const _PendingAttackSummary({required this.pending, this.submissionHpThreshold});
  final CombatV1PlayablePendingAttackView pending;

  /// Playable 2A-3「SUBMISSION Wording」——SUBMISSION trait detailの
  /// Tooltip文言用（`snapshot.submissionHpThreshold`をそのまま渡す）。
  final int? submissionHpThreshold;

  @override
  Widget build(BuildContext context) {
    final directPin = combatV1PlayablePendingAttackHasEffectiveDirectPin(
      pending,
    );
    final submissionHold =
        combatV1PlayablePendingAttackHasEffectiveSubmissionHold(pending);
    final rough = combatV1PlayablePendingAttackIsRough(pending);
    final finisherType = pending.finisherType;
    final badges = <Widget>[
      if (finisherType != null)
        _TraitBadge(
          key: const Key('combat_v1_playable_pending_finisher_resolution_badge'),
          label: combatV1PlayableFinisherResolutionBadgeLabel(finisherType),
          color: _pink,
          detail: switch (finisherType) {
            CombatV1FinisherType.normal =>
              'Shared HEAT解禁後に使用できるFINISHERです',
            CombatV1FinisherType.directPin => combatV1PlayableDirectPinTraitDetail(),
            CombatV1FinisherType.submission => submissionHpThreshold == null
                ? '成立後、条件を満たすとSubmission判定に自動移行します'
                : combatV1PlayableSubmissionTraitDetail(submissionHpThreshold!),
          },
        )
      else ...[
        if (directPin)
          _TraitBadge(
            key: const Key('combat_v1_playable_pending_direct_pin_badge'),
            label: 'DIRECT PIN',
            color: _pink,
            detail: combatV1PlayableDirectPinTraitDetail(),
          ),
        if (submissionHold)
          _TraitBadge(
            key: const Key('combat_v1_playable_pending_submission_badge'),
            label: 'SUBMISSION',
            color: _submissionBadge,
            detail: submissionHpThreshold == null
                ? '成立後、条件を満たすとSubmission判定に自動移行します'
                : combatV1PlayableSubmissionTraitDetail(submissionHpThreshold!),
          ),
      ],
      if (rough)
        _TraitBadge(
          key: const Key('combat_v1_playable_pending_rough_badge'),
          label: 'ROUGH',
          color: _roughBadge,
          detail: combatV1PlayableRoughTraitDetail(),
        ),
    ];
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
            // Playable 1C.1「Opponent Target Label」——この技はCPU（相手）
            // が使用したものなので、resultOpponentStateの対象は防御側＝
            // Human自身になる（`combatV1PlayablePendingResultStateLabel`
            // 参照）。カード面（自分の技）とは向きが逆であることに注意。
            // Playable 2A-3「Counter Response — Incoming Attack Summary」
            // ——DMG/posture結果に加えてHEAT gainも公開する
            // （`pending.heatGain`は宣言時点の静的metadataなので、
            // hidden information違反にならない）。
            '${pending.attribute.displayLabel} ・ DMG ${pending.damage} ・ '
            'HEAT ${pending.heatGain} ・ '
            '${combatV1PlayablePendingResultStateLabel(pending.resultOpponentState)}',
            key: const Key('combat_v1_playable_pending_effect_line'),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              key: const Key('combat_v1_playable_pending_trait_badges'),
              spacing: 4,
              runSpacing: 4,
              children: badges,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            // Playable 2A-3「Counter Success Meaning」——Counterが成立
            // すると何を防げるかを明示する（`playCounter`実装コメントが
            // 確定させている「攻撃効果は無効、DMG/HEAT/posture変更なし」
            // semanticsと一致する文言、7.1章）。
            combatV1PlayableCounterPreventsSummary(
              directPin: directPin,
              submissionHold: submissionHold,
            ),
            key: const Key('combat_v1_playable_pending_counter_prevents_hint'),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          if (rough) ...[
            const SizedBox(height: 2),
            Text(
              // Playable 2A-3 Review Findings Fix（Minor）——ROUGHの
              // 2つの効果（宣言時点で確定するこのターンPIN不可／成立
              // ベースの次ターンTECHNIQUE制限）は判定基準が異なり、
              // Counterで防げるものと防げないものが混在する。「ROUGHの
              // 全効果を防げる」という誤解を避けるため、prevents hintとは
              // 別行で明示する（15.1章）。
              combatV1PlayableRoughCounterAsymmetryNote(),
              key: const Key('combat_v1_playable_pending_rough_counter_note'),
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            // Playable 1C.1「COUNTER Semantics」——COUNTERの必要ENERGYは
            // 固定costではなく「返される技のENERGY COST総量」であることを
            // 明示する（docs/combat_rules_v1.md 7章）。
            'COUNTERに必要なENERGY: 合計${pending.energyCostTotal}'
            '（COUNTERカード自身の属性1種で支払います）',
            key: const Key('combat_v1_playable_pending_counter_cost_hint'),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
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
            if (pending != null)
              _PendingAttackSummary(
                pending: pending,
                submissionHpThreshold: widget.snapshot.submissionHpThreshold,
              ),
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
                      // Playable 1C.1「COUNTER Dynamic Cost」——この文脈
                      // ではpending攻撃が確定しているため、具体的な必要
                      // ENERGY合計を示せる。
                      pendingEnergyCostTotal: pending?.energyCostTotal,
                      // Playable 2A-3「Counter Card Information」——
                      // このCounterがpending攻撃をどう返せるか
                      // （family/group一致）を表示する。
                      pendingAttackFamily: pending?.family,
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
                    child: Text(
                      combatV1PlayableActionKindLabel(
                        CombatV1LegalActionKind.counter,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('combat_v1_playable_counter_decline_button'),
                    onPressed: declineAction == null
                        ? null
                        : () => widget.onDecision(declineAction),
                    child: Text(
                      combatV1PlayableActionKindLabel(
                        CombatV1LegalActionKind.declineCounter,
                      ),
                    ),
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
    // Final Merge Gate Major fix「Terminal PIN / Submission Feedback
    // Visibility」——PIN/SUBMISSIONで決着した瞬間、同じsnapshotで
    // status==matchOverとなりResult overlayが全画面を覆うため、
    // `_ActorAndRecentPanel`側のbannerは（同じ土台Column上に残っては
    // いるが）overlayの下に完全に隠れて見えなくなる。決着させた
    // action自体のfeedback（PIN ATTEMPT→3 COUNT—MATCH OVER等）は
    // Playable 1Cの主目的そのものなので、Result overlayの中でも
    // 必ず見えるようにする——新しいPIN/SUBMISSION判定ロジックは
    // 追加せず、既存`snapshot.latestFeedback`（唯一のsource of
    // truth）をそのまま同じ`_LatestFeedbackBanner`で再表示するだけ。
    final terminalFeedback = snapshot.latestFeedback;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (terminalFeedback != null) ...[
          _LatestFeedbackBanner(
            key: const Key('combat_v1_playable_result_terminal_feedback'),
            feedback: terminalFeedback,
            humanPlayerIndex: CombatV1PlayableMatchController.humanPlayerIndex,
          ),
          const SizedBox(height: 16),
        ],
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
        const SizedBox(height: 4),
        // Playable 2A-6「8章 Match Finish Clarity — 決め技」——
        // `terminalFeedback`（`snapshot.latestFeedback`）は、controllerの
        // 記録タイミング（`_recordFeedback`直後・同一`_apply`呼び出し内で
        // terminal判定、間に他のfeedback recordを挟まない）により、
        // status==matchOverの瞬間は常に「試合を終わらせたそのaction」の
        // feedbackと一致する（`combat_v1_playable_match_controller.dart`
        // 参照）。ここから安全に技識別子を導出できる場合のみ「決め技」を
        // 名指しする——通常PIN宣言（technique cardを使わないaction）等、
        // 安全に判定できない場合は「決め技 不明」——推測しない。
        Text(
          '決め技: '
          '${combatV1PlayableTerminalFinishingTechniqueLabel(terminalFeedback) ?? '不明'}',
          key: const Key('combat_v1_playable_result_finishing_move'),
          style: const TextStyle(fontSize: 12, color: Colors.white54),
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
            // Playable 2A-5「8章 Japanese Primary Actions」——REMATCH→再戦。
            child: const Text('再戦'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            key: const Key('combat_v1_playable_result_back_button'),
            onPressed: onBack,
            // Playable 2A-5「8章 Japanese Primary Actions」——BACK→戻る。
            child: const Text('戻る'),
          ),
        ),
      ],
    );
  }
}
