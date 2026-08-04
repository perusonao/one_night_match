import 'package:flutter/material.dart';

import '../wrestler_editor/models.dart'
    show WrestlerDefinition, moveAttributeLabel;
import '../wrestler_editor/repository.dart';
import 'technique_deck_deck.dart';
import 'technique_deck_defaults.dart';
import 'technique_deck_generator.dart';
import 'technique_deck_models.dart';
import 'technique_deck_storage.dart';
import 'technique_match_state.dart';

/// Technique Deck Rules Phase 3〜5: 最初のプレイアブル画面「Technique Match」。
///
/// スタンド／ダウン／疲労・休息・ターン進行・HP／HEAT表示・手札／山札・
/// エネルギーセット・技の応酬（攻撃宣言→返技判定→成功なら攻守交代して連続
/// 攻撃）を扱う。フォール／ギブアップ・フィニッシャーの決着処理・
/// キックアウト・エスケープカード・CPUは実装しない（Phase 6以降）。
/// エネルギーセットはラリー中は行えない（ラリー外の行動として扱う）。
/// 現行のclassic／energyモード・Deck Simulator・レスラーエディタ・
/// Technique Deck Builderの挙動には一切影響しない。
class TechniqueMatchScreen extends StatefulWidget {
  const TechniqueMatchScreen({
    super.key,
    this.wrestlerRepository,
    this.deckRepository,
    this.catalog,
  });

  final LocalWrestlerRepository? wrestlerRepository;
  final TechniqueDeckRepository? deckRepository;
  final TechniqueDeckCardCatalog? catalog;

  @override
  State<TechniqueMatchScreen> createState() => _TechniqueMatchScreenState();
}

const _bg = Color(0xff211527);
const _gold = Color(0xffffc857);
const _green = Color(0xff5cd68b);
const _orange = Color(0xffffab5c);
const _red = Color(0xffff5c5c);

class _TechniqueMatchScreenState extends State<TechniqueMatchScreen> {
  late final LocalWrestlerRepository wrestlerRepository =
      widget.wrestlerRepository ?? LocalWrestlerRepository();
  late final TechniqueDeckRepository deckRepository =
      widget.deckRepository ?? LocalTechniqueDeckRepository();
  late final TechniqueDeckCardCatalog catalog =
      widget.catalog ?? buildProvisionalTechniqueDeckCatalog();

  List<WrestlerDefinition>? wrestlers;
  WrestlerDefinition? wrestlerA;
  WrestlerDefinition? wrestlerB;
  TechniqueMatchState? matchState;
  bool starting = false;
  String? deckSourceNoteA;
  String? deckSourceNoteB;

  @override
  void initState() {
    super.initState();
    wrestlerRepository.loadAll().then((items) {
      if (!mounted) return;
      setState(() {
        wrestlers = items;
        if (items.isNotEmpty) wrestlerA = items.first;
        if (items.length > 1) wrestlerB = items[1];
      });
    });
  }

  Future<(TechniqueDeckDefinition, String)> _resolveDeck(
    WrestlerDefinition wrestler,
  ) async {
    final saved = await deckRepository.loadAll();
    final match = saved.where((r) => r.wrestlerId == wrestler.id).toList();
    if (match.isNotEmpty) {
      return (
        match.first.toDeckDefinition(),
        '保存済みデッキ「${match.first.name}」を使用',
      );
    }
    final result =
        TechniqueDeckAutoGenerator(
          config: TechniqueDeckGenerationConfig(
            seed: DateTime.now().millisecondsSinceEpoch,
          ),
        ).generate(
          catalog: catalog,
          wrestlerId: wrestler.id,
          deckId:
              '${wrestler.id}_temp_${DateTime.now().millisecondsSinceEpoch}',
          deckName: '${wrestler.name} 仮デッキ（自動生成）',
        );
    return (result.deck, '保存済みデッキが無いため仮デッキを自動生成');
  }

  Future<void> _startMatch() async {
    final a = wrestlerA;
    final b = wrestlerB;
    if (a == null || b == null) return;
    setState(() => starting = true);
    final (deckA, noteA) = await _resolveDeck(a);
    final (deckB, noteB) = await _resolveDeck(b);
    if (!mounted) return;
    setState(() {
      deckSourceNoteA = noteA;
      deckSourceNoteB = noteB;
      matchState = TechniqueMatchEngine.start(
        wrestlerAId: a.id,
        wrestlerAName: a.name,
        wrestlerAMaxHp: a.maxHp,
        deckA: deckA,
        wrestlerBId: b.id,
        wrestlerBName: b.name,
        wrestlerBMaxHp: b.maxHp,
        deckB: deckB,
      );
      starting = false;
    });
  }

  void _goDown() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.goDown(state));
  }

  void _setEnergy(TechniqueDeckEntry entry) {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.setEnergy(state, entry, catalog);
    setState(() => matchState = result.state);
  }

  Future<void> _declareAttack(TechniqueDeckEntry entry) async {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.declareAttack(state, entry, catalog);
    setState(() => matchState = result.state);
    if (result.success) {
      await _showDefenseDecisionDialog();
    }
  }

  void _counterAttack() {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.counterAttack(state, catalog);
    setState(() => matchState = result.state);
  }

  void _resolveHit() {
    final state = matchState;
    if (state == null) return;
    setState(
      () => matchState = TechniqueMatchEngine.resolveHit(state, catalog),
    );
  }

  void _endRally() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.endRally(state));
  }

  /// 攻撃が宣言され防御側の返技判定を待っている間、決定するまで閉じられない
  /// ダイアログを表示する（読み合いの核: 返技エネルギーが足りていても
  /// 「返技しない」選択が常にできる）。
  Future<void> _showDefenseDecisionDialog() async {
    final state = matchState;
    final pending = state?.pendingAttack;
    if (state == null || pending == null) return;
    final card = catalog.findTechniqueById(pending.cardId);
    if (card == null) return;
    final attacker = state.playerAt(pending.attackerIndex);
    final defender = state.playerAt(1 - pending.attackerIndex);
    final check = TechniqueMatchEngine.checkCounterEligibility(state, catalog);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('[Chain ${pending.chain}] ${defender.wrestlerName}の返技判定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${attacker.wrestlerName}が「${card.name}」を使用'),
            Text(
              '威力: ${card.power} ・ HEAT+${card.heatDelta}'
              '${card.causesDown ? " ・ 成立するとダウン" : ""}',
            ),
            if (card.reversalEnergyCost.values.any((v) => v > 0))
              Text(
                '返技に必要なエネルギー: ${card.reversalEnergyCost.entries.where((e) => e.value > 0).map((e) => '${moveAttributeLabel(e.key)}${e.value}').join('・')}',
              )
            else
              const Text('この技には返技エネルギーの設定がありません（返技不可）。'),
            const SizedBox(height: 8),
            const Text(
              '返技すると攻守が交代し、ダメージ・HEAT・ダウンは一切発生しません。'
              '返技しないと技が成立し、ラリーはここで終了します。',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            if (!check.canCounter)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  check.reason ?? '返技できません。',
                  style: const TextStyle(color: _red),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _resolveHit();
              Navigator.pop(dialogContext);
            },
            child: const Text('返技しない'),
          ),
          FilledButton(
            onPressed: check.canCounter
                ? () {
                    _counterAttack();
                    Navigator.pop(dialogContext);
                  }
                : null,
            child: const Text('返技する'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHandCardSheet(TechniqueDeckEntry entry) async {
    final state = matchState;
    if (state == null) return;
    final technique = catalog.findTechniqueById(entry.cardId);
    final energy = catalog.findEnergyById(entry.cardId);

    if (energy != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(energy.name),
          content: Text(
            '「${energy.name}」（${moveAttributeLabel(energy.attribute)}）を'
            'エネルギーとしてセットします。手札から出ると捨て札には入らず、'
            '以後ずっと使用可能な資源として残ります。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                _setEnergy(entry);
                Navigator.pop(dialogContext);
              },
              child: const Text('セットする'),
            ),
          ],
        ),
      );
      return;
    }

    if (technique != null) {
      final check = TechniqueMatchEngine.canDeclareAttack(
        state,
        entry,
        catalog,
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(technique.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('威力: ${technique.power} ・ HEAT: ${technique.heatDelta}'),
              Text(
                '必要レベル: Lv.${technique.minimumLevel} ・ '
                '対象状態: ${_targetStateLabel(technique.targetState)}',
              ),
              if (technique.attackEnergyCost.values.any((v) => v > 0))
                Text(
                  '必要エネルギー: ${technique.attackEnergyCost.entries.where((e) => e.value > 0).map((e) => '${moveAttributeLabel(e.key)}${e.value}').join('・')}',
                ),
              if (technique.reversalEnergyCost.values.any((v) => v > 0))
                Text(
                  '相手の返技に必要なエネルギー: ${technique.reversalEnergyCost.entries.where((e) => e.value > 0).map((e) => '${moveAttributeLabel(e.key)}${e.value}').join('・')}',
                ),
              if (technique.causesDown) const Text('成立すると相手をダウンさせます。'),
              const SizedBox(height: 8),
              if (!check.canUse)
                Text(
                  check.reason ?? '使用できません。',
                  style: const TextStyle(color: _red),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: check.canUse
                  ? () {
                      Navigator.pop(dialogContext);
                      _declareAttack(entry);
                    }
                  : null,
              child: const Text('使用する'),
            ),
          ],
        ),
      );
    }
  }

  String _targetStateLabel(TechniqueTargetState state) => switch (state) {
    TechniqueTargetState.any => '指定なし',
    TechniqueTargetState.stand => '相手がスタンド中のみ',
    TechniqueTargetState.down => '相手がダウン中のみ',
  };

  void _rest() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.rest(state));
  }

  void _endTurn() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.endTurn(state));
  }

  void _resetMatch() {
    setState(() {
      matchState = null;
      deckSourceNoteA = null;
      deckSourceNoteB = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loading = wrestlers == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Technique Match'),
        actions: [
          if (matchState != null)
            IconButton(
              tooltip: '新しい試合',
              icon: const Icon(Icons.refresh),
              onPressed: _resetMatch,
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : matchState == null
          ? _setupView()
          : _battleView(matchState!),
    );
  }

  Widget _devBanner() => Card(
    color: Colors.amber.shade900,
    child: const Padding(
      padding: EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '開発中：Technique Deck Rules Phase 5',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '技の応酬（返技・連続攻撃）が動作します'
            '（フォール／ギブアップ・フィニッシャー決着・CPUは未実装）',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _setupView() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _devBanner(),
      const SizedBox(height: 12),
      Card(
        color: _bg,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Player A',
                style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
              ),
              DropdownButtonFormField<WrestlerDefinition>(
                initialValue: wrestlerA,
                items: [
                  for (final w in wrestlers!)
                    DropdownMenuItem(value: w, child: Text(w.name)),
                ],
                onChanged: (w) => setState(() => wrestlerA = w),
              ),
              const SizedBox(height: 16),
              const Text(
                'Player B',
                style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
              ),
              DropdownButtonFormField<WrestlerDefinition>(
                initialValue: wrestlerB,
                items: [
                  for (final w in wrestlers!)
                    DropdownMenuItem(value: w, child: Text(w.name)),
                ],
                onChanged: (w) => setState(() => wrestlerB = w),
              ),
              const SizedBox(height: 8),
              const Text(
                '保存済みのテクニックデッキがあればそれを使用します。無い場合は'
                '暫定自動生成で仮デッキを組んで試合を開始します。',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: (wrestlerA == null || wrestlerB == null || starting)
            ? null
            : _startMatch,
        icon: starting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_circle),
        label: Text(starting ? '準備中…' : '試合開始'),
      ),
    ],
  );

  Widget _battleView(TechniqueMatchState state) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _devBanner(),
      const SizedBox(height: 12),
      Card(
        color: _bg,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ターン${state.turnNumber} ・ ${state.active.wrestlerName}の手番 '
                '・ フェーズ: ${_phaseLabel(state.phase)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (state.isRallyActive)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Chain ${state.rallyChain} ・ '
                    '${state.playerAt(state.rallyAttackerIndex!).wrestlerName}が攻撃側'
                    '${state.pendingAttack != null ? "（返技判定待ち）" : "（次の技を選択、または終了）"}',
                    style: const TextStyle(color: _gold, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      _playerCard(state, 0),
      const SizedBox(height: 8),
      _playerCard(state, 1),
      const SizedBox(height: 8),
      Card(
        color: _bg,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: state.isRallyActive
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (state.pendingAttack == null)
                      OutlinedButton.icon(
                        onPressed: _endRally,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('ラリーを終了する'),
                      )
                    else
                      const Text(
                        '返技判定中です…',
                        style: TextStyle(color: Colors.white70),
                      ),
                  ],
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: state.active.posture == WrestlerPosture.stand
                          ? _goDown
                          : null,
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('ダウンする'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: state.active.posture == WrestlerPosture.down
                          ? _rest
                          : null,
                      icon: const Icon(Icons.self_improvement),
                      label: const Text('休息'),
                    ),
                    FilledButton.icon(
                      onPressed: _endTurn,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('ターン終了'),
                    ),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 8),
      _logSection(state),
    ],
  );

  String _phaseLabel(TechniqueMatchPhase phase) => switch (phase) {
    TechniqueMatchPhase.start => '開始',
    TechniqueMatchPhase.draw => 'ドロー',
    TechniqueMatchPhase.energySet => 'エネルギーセット（行動可能）',
    TechniqueMatchPhase.end => '終了',
  };

  String _postureLabel(WrestlerPosture posture) => posture.displayLabel;

  Color _postureColor(WrestlerPosture posture) => switch (posture) {
    WrestlerPosture.stand => _green,
    WrestlerPosture.down => _orange,
    WrestlerPosture.fatigued => _red,
  };

  Widget _playerCard(TechniqueMatchState state, int playerIndex) {
    final player = state.playerAt(playerIndex);
    final isTurnOwner = playerIndex == state.activePlayerIndex;
    final effectiveAttackerIndex =
        state.rallyAttackerIndex ?? state.activePlayerIndex;
    final isEffectiveAttacker = playerIndex == effectiveAttackerIndex;
    final isPendingDefender =
        state.pendingAttack != null &&
        playerIndex == 1 - state.pendingAttack!.attackerIndex;
    // 手札をタップして攻撃を宣言できるのは、返技判定待ちが無く、かつ
    // 現在の実質的な攻撃側であるプレイヤーのみ。
    final canDeclare = state.pendingAttack == null && isEffectiveAttacker;
    final isPlayerA = playerIndex == 0;
    final hpRatio = player.maxHp == 0 ? 0.0 : player.hp / player.maxHp;
    final note = isPlayerA ? deckSourceNoteA : deckSourceNoteB;
    final roleLabel = isPendingDefender
        ? '返技判定待ち'
        : (state.isRallyActive && isEffectiveAttacker ? '攻撃側' : null);
    return Card(
      color: isEffectiveAttacker || isPendingDefender
          ? const Color(0xff2a1c33)
          : _bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${player.wrestlerName}'
                    '${isTurnOwner ? "（手番）" : ""}'
                    '${roleLabel != null ? " ・ $roleLabel" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _postureColor(
                      player.posture,
                    ).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _postureLabel(player.posture),
                    style: TextStyle(
                      color: _postureColor(player.posture),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: hpRatio.clamp(0, 1),
                minHeight: 8,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(
                  hpRatio > 0.5 ? _green : (hpRatio > 0.2 ? _gold : _red),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'HP ${player.hp} / ${player.maxHp} ・ HEAT ${player.heat} ・ '
              'Lv.${player.level}',
            ),
            Text(
              '手札 ${player.hand.length}枚 ・ 山札 ${player.drawPile.length}枚 ・ '
              '捨て札 ${player.discardPile.length}枚',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            if (player.energyPool.isNotEmpty)
              Text(
                'エネルギー: ${player.energyPool.entries.map((e) => '${moveAttributeLabel(e.key)}${player.availableEnergyFor(e.key)}/${e.value}').join('・')}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            if (note != null)
              Text(
                note,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in player.hand)
                  Builder(
                    builder: (context) {
                      final isEnergyCard =
                          catalog.findEnergyById(entry.cardId) != null;
                      // エネルギーセットはラリー外（ターンの行動選択時）
                      // のみ行える。技の宣言は現在の実質的な攻撃側のみ。
                      final tappable = isEnergyCard
                          ? (canDeclare && !state.isRallyActive)
                          : canDeclare;
                      return ActionChip(
                        label: Text(
                          catalog.findTechniqueById(entry.cardId)?.name ??
                              catalog.findEnergyById(entry.cardId)?.name ??
                              catalog.findDefenseCardById(entry.cardId)?.name ??
                              entry.cardId,
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: isEnergyCard
                            ? _gold.withValues(alpha: 0.2)
                            : null,
                        onPressed: tappable
                            ? () => _showHandCardSheet(entry)
                            : null,
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _logSection(TechniqueMatchState state) => Card(
    color: _bg,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '進行ログ',
            style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
          ),
          const SizedBox(height: 6),
          for (final line in state.log.reversed.take(20))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    ),
  );
}
