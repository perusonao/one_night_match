import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens.dart' show TitleScreen;
import '../game.dart' show GameCatalog;
import '../wrestler_editor/models.dart';
import '../wrestler_editor/repository.dart';
import 'level_match_cost_preview.dart';
import 'level_match_deck_builder.dart';
import 'level_match_engine.dart';
import 'level_match_finish_models.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);

/// Ver.0.3 演出：CPUターンの進行速度。ルールには影響しない。
enum MatchSpeed { fast, normal, slow, manual }

String matchSpeedLabel(MatchSpeed s) => switch (s) {
  MatchSpeed.fast => '高速',
  MatchSpeed.normal => '通常（推奨）',
  MatchSpeed.slow => 'ゆっくり',
  MatchSpeed.manual => '手動送り',
};

const _speedPrefKey = 'onm_match_speed';

/// 1ステップあたりの基本ウェイト。
Duration matchStepDelay(MatchSpeed s) => switch (s) {
  MatchSpeed.fast => const Duration(milliseconds: 130),
  MatchSpeed.normal => const Duration(milliseconds: 560),
  MatchSpeed.slow => const Duration(milliseconds: 950),
  MatchSpeed.manual => Duration.zero,
};

/// 山場（フォール/キックアウト/解放）で追加する“ため”。
const _dramaticActions = {
  'attackDeclared',
  'pinAttempt',
  'kickOut',
  'threeCount',
  'submissionAttempt',
  'submissionEscape',
  'submissionFinish',
  'unlockLevel',
  'clashResolution',
};

String finishReasonLabel(LevelFinishReason? reason) => switch (reason) {
  LevelFinishReason.pinfall => '3カウント',
  LevelFinishReason.submission => 'ギブアップ',
  LevelFinishReason.exhaustion => '消耗の果て',
  LevelFinishReason.deckOut => 'デッキ切れ(旧仕様)',
  LevelFinishReason.hpZero => 'HP0(旧仕様)',
  null => '-',
};

class LevelMatchIntroScreen extends StatelessWidget {
  const LevelMatchIntroScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('レベルカードマッチ Ver.0.7')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.layers, size: 64, color: _pink),
            const Text(
              '技をつなぎ、消耗させ、\n3カウントかギブアップを奪え。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            for (final line in const [
              '毎ターン、技カードを1枚セット',
              'セット属性で各Levelの技が解放',
              '全Levelの技コストを確認できる',
              'レスラーごとに30枚デッキを自動生成',
              '手札は「単体技」で直接使用も可能（コスト不要）',
              '決着（フォール/ギブアップ/KO）は固有技のみ',
              '技を宣言 → 相手が対応（速い技・返し・受ける）',
              '速い技が先に命中し、遅い技を潰す',
              '返し技は対応する相手技があるときだけ使える',
              'HPは消耗の指標（0でも試合は続く）',
              'キックアウトは返すほど重くなる',
              '山札切れは敗北でなく“疲労”（毎ターンHP減）',
            ])
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: _gold),
                  title: Text(line),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LevelMatchSelectScreen(),
                ),
              ),
              icon: const Icon(Icons.sports_mma),
              label: const Padding(
                padding: EdgeInsets.all(14),
                child: Text('レスラーを選ぶ'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LevelMatchSelectScreen extends StatefulWidget {
  const LevelMatchSelectScreen({super.key, this.repository});
  final LocalWrestlerRepository? repository;

  @override
  State<LevelMatchSelectScreen> createState() => _LevelMatchSelectScreenState();
}

class _LevelMatchSelectScreenState extends State<LevelMatchSelectScreen> {
  late final LocalWrestlerRepository repository =
      widget.repository ?? LocalWrestlerRepository();
  List<WrestlerDefinition>? wrestlers;

  @override
  void initState() {
    super.initState();
    repository.loadAll().then((items) {
      if (mounted) setState(() => wrestlers = items);
    });
  }

  List<String> _problems(WrestlerDefinition wrestler) {
    final errors = <String>[];
    if (wrestler.maxHp < 1) errors.add('最大HPが不正');
    final level1 = wrestler.levels.where((item) => item.level == 1);
    if (level1.isEmpty) return [...errors, 'Level 1がありません'];
    if (level1.first.moveIds.isEmpty) errors.add('Level 1に通常技がありません');
    for (final id in level1.first.moveIds) {
      final move = repository.moves[id];
      if (move == null) {
        errors.add('技ID $id が見つかりません');
      } else if (move.requiredCards.values.any((value) => value < 0)) {
        errors.add('${move.name}の必要カードが不正');
      }
    }
    return errors;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ver.0.7 レスラー選択')),
    body: wrestlers == null
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: wrestlers!.length,
            itemBuilder: (_, index) {
              final wrestler = wrestlers![index];
              final errors = _problems(wrestler);
              final level1 = wrestler.levels
                  .where((item) => item.level == 1)
                  .firstOrNull;
              final level3 = wrestler.levels
                  .where((item) => item.level == 3)
                  .firstOrNull;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wrestler.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        wrestler.subtitle,
                        style: const TextStyle(color: _gold),
                      ),
                      Text(
                        'MAX HP ${wrestler.maxHp} / Level ${wrestler.levels.length}',
                      ),
                      if (level1 != null)
                        Text(
                          'Lv.1技 ${level1.moveIds.map((id) => repository.moves[id]?.name ?? id).join(" / ")}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      Text(
                        'フィニッシャー ${repository.moves[level3?.finisherId]?.name ?? "なし"}'
                        '${_finisherKind(repository.moves[level3?.finisherId])}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        errors.isEmpty ? '✓ 対戦可能' : '× ${errors.join(" / ")}',
                        style: TextStyle(
                          color: errors.isEmpty
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => _showDeckPreview(wrestler),
                            icon: const Icon(Icons.style, size: 18),
                            label: const Text('デッキ確認'),
                          ),
                          const SizedBox(width: 6),
                          FilledButton(
                            onPressed: errors.isEmpty
                                ? () => _start(wrestler)
                                : null,
                            child: const Text('このレスラーで開始'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );

  String _finisherKind(MoveDefinition? move) {
    if (move == null) return '';
    if (move.offersSubmission) return '（ギブアップ）';
    if (move.offersPin) return '（フォール）';
    return '';
  }

  void _showDeckPreview(WrestlerDefinition wrestler) {
    final deck = const LevelMatchDeckBuilder().build(
      wrestler: wrestler,
      moves: repository.moves,
      owner: 'preview',
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                '${wrestler.name} 自動生成デッキ',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '合計 ${deck.cards.length} 枚'
                '${deck.usedFallback ? "（フォールバック）" : ""}',
                style: const TextStyle(color: _gold),
              ),
              const Divider(),
              for (final attribute in MoveAttribute.values)
                if ((deck.counts[attribute] ?? 0) > 0 ||
                    deck.usedAttributes.contains(attribute))
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(moveAttributeLabel(attribute)),
                    ),
                    title: Text(
                      '${moveAttributeLabel(attribute)}属性 ${deck.counts[attribute] ?? 0} 枚',
                    ),
                    subtitle: Text(
                      deck.attributeReasons[attribute]!.isEmpty
                          ? '—'
                          : deck.attributeReasons[attribute]!.join(' / '),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              if (deck.failureReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    deck.failureReason!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _start(WrestlerDefinition player) {
    final candidates = wrestlers!
        .where((item) => item.id != player.id && _problems(item).isEmpty)
        .toList();
    final cpu = candidates.isEmpty ? player : candidates.first;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LevelMatchBattleScreen(
          engine: LevelMatchEngine.create(
            playerWrestler: player,
            cpuWrestler: cpu,
            moves: repository.moves,
            playerStarts: true,
          ),
        ),
      ),
    );
  }
}

class LevelMatchBattleScreen extends StatefulWidget {
  const LevelMatchBattleScreen({super.key, required this.engine});
  final LevelMatchEngine engine;
  @override
  State<LevelMatchBattleScreen> createState() => _LevelMatchBattleScreenState();
}

class _LevelMatchBattleScreenState extends State<LevelMatchBattleScreen> {
  LevelMatchEngine get engine => widget.engine;
  LevelMatchState get state => engine.state;
  bool _driving = false;

  // Ver.0.3 演出用の状態（ルールには影響しない）。
  MatchSpeed _speed = MatchSpeed.normal;
  Completer<void>? _manualGate;
  String? _commentary; // 実況テキスト
  String? _cpuThought; // CPUの思考

  LevelMatchCostPreview get _preview => LevelMatchCostPreview(
    wrestler: state.player.wrestler,
    moves: engine.moves,
  );

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final raw = prefs.getString(_speedPrefKey);
      final loaded = MatchSpeed.values
          .cast<MatchSpeed?>()
          .firstWhere((s) => s!.name == raw, orElse: () => null);
      if (mounted && loaded != null) setState(() => _speed = loaded);
      WidgetsBinding.instance.addPostFrameCallback((_) => _drive());
    });
  }

  Future<void> _pickSpeed() async {
    final chosen = await showModalBottomSheet<MatchSpeed>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '演出速度',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            for (final s in MatchSpeed.values)
              ListTile(
                leading: Icon(
                  s == _speed ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: s == _speed ? _pink : null,
                ),
                title: Text(matchSpeedLabel(s)),
                onTap: () => Navigator.pop(context, s),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() => _speed = chosen);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_speedPrefKey, chosen.name);
    // 手動待機中に高速へ切替えたら解除して再開。
    if (chosen != MatchSpeed.manual) _manualGate?.complete();
  }

  @override
  Widget build(BuildContext context) {
    final player = state.player;
    final cpu = state.cpu;
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEVEL CARD MATCH'),
        actions: [
          TextButton.icon(
            onPressed: _pickSpeed,
            icon: const Icon(Icons.speed, size: 18),
            label: Text(
              matchSpeedLabel(_speed).replaceAll('（推奨）', ''),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'ログ全文',
            onPressed: _showLogs,
            icon: Badge(
              label: Text('${state.logs.length}'),
              child: const Icon(Icons.receipt_long),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              _fighterPanel(cpu, isCpu: true),
              _matchCenter(),
              _commentaryBanner(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 120),
                  children: [
                    _fighterPanel(player, isCpu: false),
                    if (!state.isGameOver) _interactionArea(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fighterPanel(
    PlayerLevelMatchState fighter, {
    required bool isCpu,
  }) => Card(
    margin: const EdgeInsets.fromLTRB(10, 5, 10, 2),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${isCpu ? "CPU  " : ""}${fighter.wrestler.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (fighter.isDown)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text(
                    'DOWN',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (fighter.isExhausted)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text(
                    '疲労',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Text(
                'Lv.${fighter.currentLevel}  HP ${fighter.currentHp}/${fighter.wrestler.maxHp}',
              ),
            ],
          ),
          LinearProgressIndicator(
            value: fighter.wrestler.maxHp == 0
                ? 0
                : fighter.currentHp / fighter.wrestler.maxHp,
            color: isCpu ? Colors.purple : _pink,
          ),
          const SizedBox(height: 5),
          Text(
            '解放 ${fighter.unlockedLevels.toList()..sort()}  '
            '山札 ${fighter.deck.length}  手札 ${fighter.hand.length}  '
            'FIN ${fighter.finisherUsed ? "USED" : "READY"}',
            style: const TextStyle(fontSize: 11),
          ),
          Text(
            'KO ${fighter.kickOutCards}  RB ${fighter.ropeBreakCards}'
            '${fighter.hpZeroReachedTurn != null ? "  ⚑HP0継続中" : ""}',
            style: const TextStyle(fontSize: 11, color: _gold),
          ),
          InkWell(
            onTap: () => _showSetCards(fighter),
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'SET ${_attributeCounts(fighter.setAttributeCounts)}',
                style: const TextStyle(color: _gold),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _matchCenter() => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff4a1237), Color(0xff1c1224)],
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Text('TURN ${state.turnNumber}'),
            Text(
              'HEAT ${state.sharedHeat}',
              style: const TextStyle(
                color: _gold,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _phaseLabel(state.phase),
              style: const TextStyle(color: _pink),
            ),
          ],
        ),
        if (state.unlockNotice != null)
          Text(
            state.unlockNotice!,
            style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
          ),
        // Ver.0.7: 相手の前ターン技を常時表示（読み合いの土台）。
        if (state.cpu.lastUsedMoveName != null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '相手の技: ${state.cpu.lastUsedMoveName}'
              '（速度${state.cpu.lastUsedMoveSpeed ?? "-"}）',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (state.lastMove != null)
          Text('${state.lastMove} / ${state.lastDamage} DAMAGE'),
        if (state.logs.isNotEmpty)
          Text(
            state.logs.last.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
      ],
    ),
  );

  Widget _commentaryBanner() {
    final showThought = _cpuThought != null && _driving;
    final manual = _manualGate != null;
    if (_commentary == null && !_driving && !manual) {
      return const SizedBox.shrink();
    }
    // 山場の演出：フォールカウントを強調。
    final isCount = _commentary != null &&
        (_commentary!.contains('ONE') ||
            _commentary!.contains('THREE') ||
            _commentary!.contains('2.9'));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCount ? _pink.withValues(alpha: 0.22) : Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCount ? _pink : Colors.white24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_commentary != null)
            Text(
              _commentary!,
              style: TextStyle(
                fontSize: isCount ? 22 : 14,
                fontWeight: isCount ? FontWeight.w900 : FontWeight.w600,
                color: isCount ? _gold : Colors.white,
              ),
            ),
          if (showThought)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '🤖 CPU: $_cpuThought',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
          if (manual)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {
                  _manualGate?.complete();
                },
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('次へ'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _interactionArea() {
    final pin = state.pendingPin;
    final sub = state.pendingSubmission;
    final atk = state.pendingAttack;
    if (state.phase == LevelMatchPhase.responseSelection &&
        atk?.defenderId == 'player') {
      return _responseCard(atk!);
    }
    if (state.phase == LevelMatchPhase.pinDecision &&
        pin?.attackerId == 'player') {
      return _pinDeclareCard(pin!);
    }
    if (state.phase == LevelMatchPhase.kickOutDecision &&
        pin?.defenderId == 'player') {
      return _kickOutCard(pin!);
    }
    if (state.phase == LevelMatchPhase.submissionDecision &&
        sub?.defenderId == 'player') {
      return _submissionCard(sub!);
    }
    if (state.activePlayerId == 'player') {
      return switch (state.phase) {
        LevelMatchPhase.setCard => _setCardPhase(state.player),
        LevelMatchPhase.levelChange => _levelPhase(state.player),
        LevelMatchPhase.chooseMove => _movePhase(state.player),
        _ => _waiting(),
      };
    }
    return _waiting();
  }

  Widget _responseCard(PendingAttack atk) {
    final player = state.player;
    final attackMove = engine.moves[atk.moveId]!;
    // 応答候補（固有技＋手札の単体技）。
    final signatures = [
      for (final m in engine.currentMoves(player))
        if (engine.responseAvailability(player, m, isBasic: false).usable) m,
    ];
    (String, Color) badge(MoveDefinition m) =>
        switch (engine.clashBetween(attackMove, m)) {
          ClashOutcome.counter => ('🔄返し成立', _gold),
          ClashOutcome.speedWin => ('⚡速度勝ち', Colors.greenAccent),
          ClashOutcome.speedLoss => ('🐢速度負け', Colors.white38),
          ClashOutcome.neutral => ('＝互角(攻撃側優先)', Colors.white60),
        };
    return Card(
      color: const Color(0xff3a1030),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '相手の攻撃：${attackMove.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${moveAttributeLabel(attackMove.attribute)} / 威力${attackMove.power} / 速度${attackMove.speed}'
              '${attackMove.offersPin && !atk.isBasic ? "  ▶フォール技" : ""}'
              '${attackMove.offersSubmission && !atk.isBasic ? "  ▶ギブアップ技" : ""}',
              style: const TextStyle(color: Colors.orangeAccent),
            ),
            const Divider(),
            const Text('対応を選択', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final m in signatures)
              Builder(
                builder: (_) {
                  final (label, color) = badge(m);
                  return ListTile(
                    dense: true,
                    title: Text('${m.name}（速度${m.speed}）'),
                    subtitle: Text(
                      label,
                      style: TextStyle(color: color, fontWeight: FontWeight.bold),
                    ),
                    trailing: FilledButton(
                      onPressed: () =>
                          _act(() => engine.respondWithMove('player', m.id)),
                      child: const Text('対応'),
                    ),
                  );
                },
              ),
            const SizedBox(height: 6),
            const Text('単体技で対応（手札）', style: TextStyle(color: Colors.white70)),
            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final card in player.hand)
                    Builder(
                      builder: (_) {
                        final basic = engine.basicMoveFor(card.attribute);
                        if (basic == null) return const SizedBox.shrink();
                        final (label, color) = badge(basic);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: CircleAvatar(
                              child: Text(moveAttributeLabel(card.attribute)),
                            ),
                            label: SizedBox(
                              width: 96,
                              child: Text(
                                '${basic.name}\n速${basic.speed} $label',
                                style: TextStyle(fontSize: 10, color: color),
                              ),
                            ),
                            onPressed: () => _act(
                              () => engine.respondWithBasic(
                                'player',
                                card.instanceId,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _act(() => engine.respondTake('player')),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('受ける（攻撃を通す）'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _waiting() => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Center(child: Text('CPU思考中…')),
    ),
  );

  // ===== セットフェイズ（技コスト表示・セット後予測） =====

  Widget _setCardPhase(PlayerLevelMatchState player) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '1枚セット（任意）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showCostSheet(player),
                icon: const Icon(Icons.list_alt, size: 18),
                label: const Text('全Levelコスト'),
              ),
            ],
          ),
          Text(
            'SET ${_attributeCounts(player.setAttributeCounts)}',
            style: const TextStyle(fontSize: 12, color: _gold),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final card in player.hand)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: CircleAvatar(
                        child: Text(moveAttributeLabel(card.attribute)),
                      ),
                      label: SizedBox(width: 64, child: Text(card.name)),
                      onPressed: () => _previewThenSet(card),
                    ),
                  ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _act(() => engine.skipSetCard('player')),
            child: const Text('セットしない'),
          ),
        ],
      ),
    ),
  );

  Future<void> _previewThenSet(TechniqueResourceCard card) async {
    final player = state.player;
    final prediction = _preview.predictSet(
      attribute: card.attribute,
      counts: player.setAttributeCounts,
      unlockedLevels: player.unlockedLevels,
      finisherUsed: player.finisherUsed,
    );
    final changes = prediction.changes.take(6).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「${moveAttributeLabel(card.attribute)}」をセットすると'),
        content: SizedBox(
          width: 320,
          child: changes.isEmpty
              ? const Text('この属性を必要とする技はありません。')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final change in changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${change.moveName}\n'
                          '${moveAttributeLabel(change.attribute)}'
                          '${change.beforeCount}/${change.requiredForAttribute}'
                          ' → '
                          '${moveAttributeLabel(change.attribute)}'
                          '${change.afterCount}/${change.requiredForAttribute}'
                          '${change.becameUsable ? "  使用可能に！" : change.remainingAfter > 0 ? "  あと${moveAttributeLabel(change.attribute)}${change.remainingAfter}" : ""}',
                          style: TextStyle(
                            fontSize: 12,
                            color: change.becameUsable ? _gold : null,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('セットする'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _setCard(card);
  }

  void _showCostSheet(PlayerLevelMatchState player) {
    final views = _preview.allLevelViews(
      counts: player.setAttributeCounts,
      unlockedLevels: player.unlockedLevels,
      currentLevel: player.currentLevel,
      finisherUsed: player.finisherUsed,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                '${player.wrestler.name} 全Level技コスト',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '現在 SET ${_attributeCounts(player.setAttributeCounts)}',
                style: const TextStyle(fontSize: 12, color: _gold),
              ),
              const Divider(),
              for (final level in views)
                _LevelCostTile(level: level, key: ValueKey(level.level)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _levelPhase(PlayerLevelMatchState player) => Card(
    child: ListTile(
      title: Text('現在 Level ${player.currentLevel}'),
      subtitle: const Text('解放済みレベルへ変更できます（飛び級可）。'),
      trailing: const Icon(Icons.swap_horiz),
      onTap: _showLevels,
      contentPadding: const EdgeInsets.all(12),
      leading: OutlinedButton(
        onPressed: () => _act(() => engine.skipLevelChange('player')),
        child: const Text('維持'),
      ),
    ),
  );

  Widget _movePhase(PlayerLevelMatchState player) {
    final moveList = engine.currentMoves(player);
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 4, top: 4, bottom: 2),
            child: Text(
              '固有技（セット消費・決着可）',
              style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
            ),
          ),
        ),
        for (final move in moveList)
          Builder(
            builder: (_) {
              final availability = engine.evaluateMove(player, move);
              final isCounter = move.isCounterMove && !move.canUseAsNormalMove;
              final tags = <String>[
                if (move.offersPin) 'フォール',
                if (move.offersSubmission) 'ギブアップ',
                if (move.causesDown) 'ダウン',
                if (move.category == MoveCategory.finisher) 'FINISHER',
                if (isCounter) '返し(対応専用)',
              ];
              return Card(
                child: ListTile(
                  title: Text(
                    '${move.name}${tags.isEmpty ? "" : "  [${tags.join("/")}]"}',
                  ),
                  subtitle: Text(
                    '${moveAttributeLabel(move.attribute)} / 攻撃 ${move.power} / 速度 ${move.speed} / HEAT ${move.heat >= 0 ? "+" : ""}${move.heat}\n'
                    '必要 ${_attributeCounts(move.requiredCards)} / 現在 ${_attributeCounts(player.setAttributeCounts)}\n'
                    '${availability.usable ? "使用可能" : "使用不可: ${availability.reasons.join(" / ")}"}',
                  ),
                  isThreeLine: true,
                  trailing: FilledButton(
                    onPressed: (availability.usable && !isCounter)
                        ? () => _useMove(move)
                        : null,
                    child: Text(isCounter ? '対応専用' : '使用'),
                  ),
                  onTap: () => _showMove(move, availability),
                ),
              );
            },
          ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 4, top: 8, bottom: 2),
            child: Text(
              '単体技（手札から直接・コスト不要・決着不可）',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final card in player.hand)
                Builder(
                  builder: (_) {
                    final basic = engine.basicMoveFor(card.attribute);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: CircleAvatar(
                          child: Text(moveAttributeLabel(card.attribute)),
                        ),
                        label: SizedBox(
                          width: 92,
                          child: Text(
                            basic == null
                                ? card.name
                                : '${basic.name}\n威力${basic.power} 速${basic.speed}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        onPressed: basic == null
                            ? null
                            : () => _act(
                                () => engine.useBasicMove(
                                  'player',
                                  card.instanceId,
                                ),
                              ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: () => _act(() => engine.skipMove('player')),
          child: const Text('技を使わず終了'),
        ),
      ],
    );
  }

  // ===== フォール／ギブアップ 対応UI =====

  Widget _pinDeclareCard(PendingPin pin) => Card(
    color: const Color(0xff3a1030),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'フォールしますか？',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text('技: ${pin.moveName}'),
          Text('フォール強度 ${pin.strength.total}'
              '（技${pin.strength.base}+ダメージ${pin.strength.damage}'
              '${pin.strength.finisherBonus > 0 ? "+FIN${pin.strength.finisherBonus}" : ""}'
              '${pin.strength.fatigueBonus > 0 ? "+消耗${pin.strength.fatigueBonus}" : ""}'
              '${pin.strength.downBonus > 0 ? "+ダウン${pin.strength.downBonus}" : ""}）'),
          Text('相手HP ${state.byId(pin.defenderId).currentHp} / '
              '想定キックアウトHP ${pin.hpKickOutCost}'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _act(() => engine.declarePin('player')),
                  child: const Text('フォールする'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _act(() => engine.declinePin('player')),
                  child: const Text('試合を続ける'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _kickOutCard(PendingPin pin) {
    final me = state.player;
    final canHp = me.currentHp > 0 && me.currentHp >= pin.hpKickOutCost;
    return Card(
      color: const Color(0xff3a1030),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'フォールされています！',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text('${pin.moveName}  フォール強度 ${pin.strength.total}'),
            Text('現在HP ${me.currentHp}  →  HP消費後 '
                '${(me.currentHp - pin.hpKickOutCost).clamp(0, me.currentHp)}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: me.kickOutCards > 0
                      ? () => _act(
                          () => engine.kickOut('player', DefenseMethod.card),
                        )
                      : null,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text('キックアウトカード(${me.kickOutCards}) HEAT+5'),
                ),
                FilledButton.icon(
                  onPressed: canHp
                      ? () => _act(
                          () => engine.kickOut('player', DefenseMethod.hp),
                        )
                      : null,
                  icon: const Icon(Icons.favorite, size: 18),
                  label: Text('HPを${pin.hpKickOutCost}消費'),
                ),
                OutlinedButton(
                  onPressed: () => _act(
                    () => engine.kickOut('player', DefenseMethod.accept),
                  ),
                  child: const Text('敗北を受け入れる'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _submissionCard(PendingSubmission sub) {
    final me = state.player;
    final canHp = me.currentHp > 0 && me.currentHp >= sub.hpEscapeCost;
    return Card(
      color: const Color(0xff30203a),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '関節技が極まっています！',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text('${sub.moveName}  ギブアップ強度 ${sub.strength.total}'),
            Text('関節耐性による軽減 -${sub.strength.resistanceReduction}'),
            Text('現在HP ${me.currentHp}  →  HP消費後 '
                '${(me.currentHp - sub.hpEscapeCost).clamp(0, me.currentHp)}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: me.ropeBreakCards > 0
                      ? () => _act(
                          () => engine.escapeSubmission(
                            'player',
                            DefenseMethod.card,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.horizontal_rule, size: 18),
                  label: Text('ロープブレイク(${me.ropeBreakCards}) HEAT+3'),
                ),
                FilledButton.icon(
                  onPressed: canHp
                      ? () => _act(
                          () => engine.escapeSubmission(
                            'player',
                            DefenseMethod.hp,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.favorite, size: 18),
                  label: Text('HPを${sub.hpEscapeCost}消費して耐える'),
                ),
                OutlinedButton(
                  onPressed: () => _act(
                    () => engine.escapeSubmission(
                      'player',
                      DefenseMethod.accept,
                    ),
                  ),
                  child: const Text('ギブアップ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setCard(TechniqueResourceCard card) async {
    String? replacement;
    if (state.player.setCards.length >= 6) {
      replacement = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('セットカードを交換'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('捨てるカードを選択してください'),
              for (final old in state.player.setCards)
                ListTile(
                  title: Text(old.name),
                  onTap: () => Navigator.pop(context, old.instanceId),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      );
      if (replacement == null) return;
    }
    _act(
      () => engine.setTechniqueCard(
        'player',
        card.instanceId,
        replaceInstanceId: replacement,
      ),
    );
  }

  Future<void> _showLevels() async {
    final player = state.player;
    final changed = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'LEVEL CHANGE',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            for (final level in player.wrestler.levels)
              Builder(
                builder: (_) {
                  final unlocked = player.unlockedLevels.contains(level.level);
                  final evaluation = engine.evaluateUnlockCondition(
                    player,
                    level,
                  );
                  return Card(
                    child: ListTile(
                      title: Text(
                        'Level ${level.level} ${unlocked ? "UNLOCKED" : "LOCKED"}',
                      ),
                      subtitle: Text(
                        '技 ${level.moveIds.map((id) => engine.moves[id]?.name ?? id).join(" / ")}\n'
                        '条件 ${evaluation.details.join(" / ")}${evaluation.supported ? "" : "（未対応）"}',
                      ),
                      onTap: unlocked && level.level != player.currentLevel
                          ? () => Navigator.pop(context, level.level)
                          : null,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
    if (changed != null) _act(() => engine.changeLevel('player', changed));
  }

  Future<void> _useMove(MoveDefinition move) async {
    // Ver.0.7.1: 技は「宣言」。相手（CPU）が自動でレスポンスして解決する。
    _act(() => engine.useMove('player', move.id));
  }

  void _act(VoidCallback action, {bool continueCpu = true}) {
    try {
      setState(action);
      if (state.isGameOver) {
        _finish();
      } else if (continueCpu) {
        _drive();
      }
    } on Object catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// CPUの判断を1ステップずつ、速度設定に応じて演出しながら進める。
  Future<void> _drive() async {
    if (_driving || !mounted || state.isGameOver) return;
    _driving = true;
    while (mounted && engine.cpuActionPending && !state.isGameOver) {
      await _pace();
      if (!mounted) break;
      final before = state.logs.length;
      setState(engine.autoAdvance);
      _updateCommentary(before);
      await _dramaticPause(before);
    }
    _driving = false;
    if (mounted) setState(() {});
    if (state.isGameOver && mounted) await _finish();
  }

  Future<void> _pace() async {
    if (_speed == MatchSpeed.manual) {
      final gate = Completer<void>();
      setState(() => _manualGate = gate);
      await gate.future;
      if (mounted) setState(() => _manualGate = null);
    } else {
      await Future<void>.delayed(matchStepDelay(_speed));
    }
  }

  void _updateCommentary(int fromIndex) {
    if (fromIndex >= state.logs.length) return;
    final fresh = state.logs.sublist(fromIndex);
    for (final log in fresh.reversed) {
      if (log.action == 'cpuDecision') {
        _cpuThought = log.message;
      }
    }
    // 実況として最も意味のある行を選ぶ（cpuDecisionは思考欄へ）。
    final headline = fresh.lastWhere(
      (l) => l.action != 'cpuDecision',
      orElse: () => fresh.last,
    );
    setState(() => _commentary = headline.message);
  }

  Future<void> _dramaticPause(int fromIndex) async {
    if (_speed == MatchSpeed.manual || _speed == MatchSpeed.fast) return;
    if (fromIndex >= state.logs.length) return;
    final fresh = state.logs.sublist(fromIndex);
    if (fresh.any((l) => _dramaticActions.contains(l.action))) {
      await Future<void>.delayed(matchStepDelay(_speed));
    }
  }

  Future<void> _finish() async {
    await LevelMatchHistoryStore().save(state);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LevelMatchResultScreen(state: state, moves: engine.moves),
      ),
    );
  }

  void _showSetCards(PlayerLevelMatchState fighter) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fighter.wrestler.name} SET AREA',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(_attributeCounts(fighter.setAttributeCounts)),
                const Divider(),
                if (fighter.setCards.isEmpty) const Text('セットカードなし'),
                for (final card in fighter.setCards)
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(moveAttributeLabel(card.attribute)),
                    ),
                    title: Text(card.name),
                  ),
              ],
            ),
          ),
        ),
      );

  void _showMove(
    MoveDefinition move,
    MoveAvailability availability,
  ) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(move.name),
      content: Text(
        '属性 ${moveAttributeLabel(move.attribute)}\n攻撃力 ${move.power}\nHEAT ${move.heat}\n'
        '必要 ${_attributeCounts(move.requiredCards)}\n破棄 ${_attributeCounts(move.discardAfterUse)}\n'
        '${move.offersPin ? "フォール強度(基礎) ${move.pinPower}\n" : ""}'
        '${move.offersSubmission ? "ギブアップ強度(基礎) ${move.submissionPower}\n" : ""}'
        '追加判定 ${move.additionalChecks.map(additionalCheckLabel).join(", ")}\n'
        '${availability.usable ? "使用可能" : availability.reasons.join("\n")}',
      ),
    ),
  );

  void _showLogs() {
    // ターンごとにグルーピングした試合ログ。
    final byTurn = <int, List<LevelMatchLogEntry>>{};
    for (final log in state.logs) {
      byTurn.putIfAbsent(log.turn, () => []).add(log);
    }
    final turns = byTurn.keys.toList()..sort((a, b) => b.compareTo(a));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              '試合ログ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            for (final turn in turns)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TURN $turn',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _gold,
                        ),
                      ),
                      for (final log in byTurn[turn]!)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '・${log.message}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LevelCostTile extends StatelessWidget {
  const _LevelCostTile({required this.level, super.key});
  final LevelCostView level;

  @override
  Widget build(BuildContext context) => Card(
    color: level.isCurrentLevel ? const Color(0xff2a1c33) : null,
    child: ExpansionTile(
      initiallyExpanded: level.isCurrentLevel,
      title: Text(
        'Level ${level.level}'
        '${level.isCurrentLevel ? "  ◀ 現在" : ""}'
        '${level.unlocked ? "" : "  🔒未解放"}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: level.isCurrentLevel ? _gold : null,
        ),
      ),
      children: [
        for (final move in level.allMoves)
          ListTile(
            dense: true,
            leading: Text(
              move.symbol,
              style: TextStyle(
                fontSize: 20,
                color: move.symbol == '✓'
                    ? Colors.greenAccent
                    : move.symbol == '△'
                    ? _gold
                    : Colors.white38,
              ),
            ),
            title: Text(
              '${move.name}'
              '${move.isFinisher ? "  [FINISHER]" : ""}'
              '${move.offersPin ? "  ▶フォール" : ""}'
              '${move.offersSubmission ? "  ▶ギブアップ" : ""}',
            ),
            subtitle: Text(
              '必要 ${_attributeCounts(move.requiredCards)}\n'
              '現在 ${_attributeCounts(move.currentCounts)}'
              '${move.hasShortage ? "\n不足 ${_shortageText(move.shortages)}" : ""}',
              style: const TextStyle(fontSize: 11),
            ),
            isThreeLine: move.hasShortage,
          ),
      ],
    ),
  );
}

class LevelMatchResultScreen extends StatelessWidget {
  const LevelMatchResultScreen({
    super.key,
    required this.state,
    required this.moves,
  });
  final LevelMatchState state;
  final Map<String, MoveDefinition> moves;
  @override
  Widget build(BuildContext context) {
    final winner = state.winnerId == 'player' ? state.player : state.cpu;
    final loser = state.winnerId == 'player' ? state.cpu : state.player;
    final json = const JsonEncoder.withIndent('  ').convert(state.toJson());
    return Scaffold(
      appBar: AppBar(title: const Text('LEVEL MATCH RESULT')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Icon(Icons.emoji_events, color: _gold, size: 72),
          Text(
            '${winner.wrestler.name} WIN',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          _result('敗者', loser.wrestler.name),
          _result('決着方法', finishReasonLabel(state.finishReason)),
          _result('決着技', state.finishingMove ?? state.lastMove ?? 'なし'),
          _result(
            '最終HP',
            '${state.player.wrestler.name} ${state.player.currentHp} / ${state.cpu.wrestler.name} ${state.cpu.currentHp}',
          ),
          _result('総ターン', '${state.turnNumber}'),
          _result('最終HEAT', '${state.sharedHeat}'),
          _result('フォール試行', '${state.pinAttemptCount}'),
          _result('キックアウト', '${state.kickOutTotalCount}'),
          _result('ギブアップ判定', '${state.submissionAttemptCount}'),
          _result('ギブアップ回避', '${state.submissionEscapeTotalCount}'),
          _result('ロープブレイク', '${state.ropeBreakTotalCount}'),
          _result('フィニッシャー返し', '${state.finisherKickOutTotalCount}'),
          _result(
            'HP0到達ターン',
            'あなた ${state.player.hpZeroReachedTurn ?? "-"} / '
                'CPU ${state.cpu.hpZeroReachedTurn ?? "-"}',
          ),
          _result(
            'フィニッシャー使用',
            'あなた ${state.player.finisherUsed ? "有" : "無"} / '
                'CPU ${state.cpu.finisherUsed ? "有" : "無"}',
          ),
          FilledButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: json)),
            icon: const Icon(Icons.copy),
            label: const Text('試合JSONをコピー'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => LevelMatchBattleScreen(
                  engine: LevelMatchEngine.create(
                    playerWrestler: state.player.wrestler,
                    cpuWrestler: state.cpu.wrestler,
                    moves: moves,
                  ),
                ),
              ),
            ),
            child: const Text('再戦'),
          ),
          TextButton(
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => TitleScreen(catalog: GameCatalog.standard()),
              ),
              (_) => false,
            ),
            child: const Text('タイトルへ'),
          ),
        ],
      ),
    );
  }
}

Widget _result(String label, String value) => Card(
  child: ListTile(title: Text(label), trailing: Text(value)),
);

String _attributeCounts(Map<MoveAttribute, int> values) => MoveAttribute.values
    .where((attribute) => (values[attribute] ?? 0) != 0)
    .map(
      (attribute) =>
          '${moveAttributeLabel(attribute)}${values[attribute] ?? 0}',
    )
    .join(' ')
    .ifEmptyText();

String _shortageText(Map<MoveAttribute, int> values) => MoveAttribute.values
    .where((attribute) => (values[attribute] ?? 0) > 0)
    .map(
      (attribute) =>
          '${moveAttributeLabel(attribute)}${values[attribute] ?? 0}',
    )
    .join(' ');

extension _EmptyText on String {
  String ifEmptyText() => trim().isEmpty ? '—' : this;
}

String _phaseLabel(LevelMatchPhase phase) => switch (phase) {
  LevelMatchPhase.setCard => 'CARD SET',
  LevelMatchPhase.levelChange => 'LEVEL CHANGE',
  LevelMatchPhase.chooseMove => 'MOVE SELECT',
  LevelMatchPhase.resolveMove => 'DAMAGE',
  LevelMatchPhase.pinDecision => 'FALL?',
  LevelMatchPhase.kickOutDecision => 'KICK OUT?',
  LevelMatchPhase.submissionDecision => 'SUBMISSION?',
  LevelMatchPhase.gameOver => 'GAME OVER',
  _ => phase.name.toUpperCase(),
};
