import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens.dart' show TitleScreen;
import '../game.dart' show GameCatalog;
import '../wrestler_editor/models.dart';
import '../wrestler_editor/repository.dart';
import 'level_match_engine.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);

class LevelMatchIntroScreen extends StatelessWidget {
  const LevelMatchIntroScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('レベルカードマッチ Ver.0.4')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.layers, size: 64, color: _pink),
            const Text(
              '技カードをセットして、\nレスラーを進化させろ。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            for (final line in const [
              '毎ターン、技カードを1枚セット',
              'セットした属性で技が解放',
              '条件を満たすと上位Levelが解放',
              '自分のターンに1回Level変更',
              '現在Levelに書かれた技だけ使用可能',
              'フィニッシャーは原則1試合1回',
              '相手HPを0にすると勝利',
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
    appBar: AppBar(title: const Text('Ver.0.4 レスラー選択')),
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
                          'Lv.1耐性 ${_attributeCounts(level1.resistances)}\n'
                          'Lv.1技 ${level1.moveIds.map((id) => repository.moves[id]?.name ?? id).join(" / ")}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      Text(
                        'Lv.3フィニッシャー ${repository.moves[level3?.finisherId]?.name ?? "なし"}',
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: errors.isEmpty
                              ? () => _start(wrestler)
                              : null,
                          child: const Text('このレスラーで開始'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );

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
  bool cpuBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _continueCpu());
  }

  @override
  Widget build(BuildContext context) {
    final player = state.player;
    final cpu = state.cpu;
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEVEL CARD MATCH'),
        actions: [
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 120),
                  children: [
                    _fighterPanel(player, isCpu: false),
                    if (state.activePlayerId == 'player' && !state.isGameOver)
                      _playerActions(),
                    if (state.activePlayerId == 'cpu' && !state.isGameOver)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(child: Text('CPU思考中…')),
                        ),
                      ),
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
              Text(
                'Lv.${fighter.currentLevel}  HP ${fighter.currentHp}/${fighter.wrestler.maxHp}',
              ),
            ],
          ),
          LinearProgressIndicator(
            value: fighter.currentHp / fighter.wrestler.maxHp,
            color: isCpu ? Colors.purple : _pink,
          ),
          const SizedBox(height: 5),
          Text(
            '解放 ${fighter.unlockedLevels.toList()..sort()}  山札 ${fighter.deck.length}  手札 ${fighter.hand.length}  FIN ${fighter.finisherUsed ? "USED" : "READY"}',
            style: const TextStyle(fontSize: 11),
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

  Widget _playerActions() {
    final player = state.player;
    return switch (state.phase) {
      LevelMatchPhase.setCard => _setCardPhase(player),
      LevelMatchPhase.levelChange => _levelPhase(player),
      LevelMatchPhase.chooseMove => _movePhase(player),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _setCardPhase(PlayerLevelMatchState player) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '1枚セットしてください（任意）',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 86,
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
                      onPressed: () => _setCard(card),
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

  Widget _levelPhase(PlayerLevelMatchState player) => Card(
    child: ListTile(
      title: Text('現在 Level ${player.currentLevel}'),
      subtitle: const Text('解放済みレベルへ変更できます。変更後も技を使用可能。'),
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
        for (final move in moveList)
          Builder(
            builder: (_) {
              final availability = engine.evaluateMove(player, move);
              return Card(
                child: ListTile(
                  title: Text(move.name),
                  subtitle: Text(
                    '${moveAttributeLabel(move.attribute)} / 攻撃 ${move.power} / HEAT ${move.heat >= 0 ? "+" : ""}${move.heat}\n'
                    '必要 ${_attributeCounts(move.requiredCards)} / 現在 ${_attributeCounts(player.setAttributeCounts)}\n'
                    '${availability.usable ? "使用可能" : "使用不可: ${availability.reasons.join(" / ")}"}',
                  ),
                  isThreeLine: true,
                  trailing: FilledButton(
                    onPressed: availability.usable
                        ? () => _useMove(move)
                        : null,
                    child: const Text('使用'),
                  ),
                  onTap: () => _showMove(move, availability),
                ),
              );
            },
          ),
        OutlinedButton(
          onPressed: () => _act(() => engine.skipMove('player')),
          child: const Text('技を使わず終了'),
        ),
      ],
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
                        '耐性 ${_attributeCounts(level.resistances)}\n'
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
    final finisher = move.category == MoveCategory.finisher;
    _act(() => engine.useMove('player', move.id), continueCpu: !finisher);
    if (finisher && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog.fullscreen(
          backgroundColor: Colors.black.withValues(alpha: 0.94),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'FINISHER',
                  style: TextStyle(color: _pink, letterSpacing: 6),
                ),
                Text(
                  move.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: _gold,
                  ),
                ),
                Text(
                  '${state.lastDamage} DAMAGE',
                  style: const TextStyle(fontSize: 22),
                ),
                const Text('SFX EVENT: finisher'),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('続行'),
                ),
              ],
            ),
          ),
        ),
      );
      if (mounted) {
        if (state.isGameOver) {
          await _finish();
        } else {
          _continueCpu();
        }
      }
    }
  }

  void _act(VoidCallback action, {bool continueCpu = true}) {
    try {
      setState(action);
      if (state.isGameOver) {
        _finish();
      } else if (continueCpu) {
        _continueCpu();
      }
    } on Object catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _continueCpu() async {
    if (cpuBusy || state.activePlayerId != 'cpu' || state.isGameOver) return;
    cpuBusy = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    while (mounted && state.activePlayerId == 'cpu' && !state.isGameOver) {
      setState(engine.runCpuTurn);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    cpuBusy = false;
    if (state.isGameOver && mounted) await _finish();
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
        '追加判定 ${move.additionalChecks.map((item) => item.name).join(", ")}\n'
        'Ver.0.4 ${availability.usable ? "対応・使用可能" : availability.reasons.join("\n")}',
      ),
    ),
  );

  void _showLogs() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        children: [
          for (final log in state.logs.reversed)
            ListTile(
              title: Text('T${log.turn} ${log.message}'),
              subtitle: Text('${log.phase} / ${log.action}'),
            ),
        ],
      ),
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
          _result('決着理由', state.finishReason?.name ?? ''),
          _result('最後の技', state.lastMove ?? 'なし'),
          _result(
            '最終HP',
            '${state.player.wrestler.name} ${state.player.currentHp} / ${state.cpu.wrestler.name} ${state.cpu.currentHp}',
          ),
          _result('総ターン', '${state.turnNumber}'),
          _result('最終HEAT', '${state.sharedHeat}'),
          _result('Level 2到達', '${state.player.level2UnlockedTurn ?? "-"}'),
          _result('Level 3到達', '${state.player.level3UnlockedTurn ?? "-"}'),
          _result('フィニッシャー使用', '${state.player.finisherUsedTurn ?? "-"}'),
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
    .map(
      (attribute) =>
          '${moveAttributeLabel(attribute)} ${values[attribute] ?? 0}',
    )
    .join('  ');

String _phaseLabel(LevelMatchPhase phase) => switch (phase) {
  LevelMatchPhase.setCard => 'CARD SET',
  LevelMatchPhase.levelChange => 'LEVEL CHANGE',
  LevelMatchPhase.chooseMove => 'MOVE SELECT',
  LevelMatchPhase.resolveMove => 'DAMAGE',
  LevelMatchPhase.gameOver => 'GAME OVER',
  _ => phase.name.toUpperCase(),
};
