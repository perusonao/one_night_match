import 'dart:async';

import 'package:flutter/material.dart';

import 'game.dart';

class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key, required this.catalog});
  final GameCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff3a1014), Color(0xff0c0d12)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sports_mma, size: 72, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                'ONE NIGHT',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              Text(
                'MATCH',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.redAccent,
                ),
              ),
              const Text('勝利か、伝説か。'),
              const SizedBox(height: 48),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text('ゲーム開始'),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WrestlerSelectScreen(catalog: catalog),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('ルール'),
                    content: Text(
                      'より強い技、または有利属性の技でラリーを返そう。\n'
                      '技が決まったらフォール。キックアウトできなければ勝利！',
                    ),
                  ),
                ),
                child: const Text('ルール'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WrestlerSelectScreen extends StatelessWidget {
  const WrestlerSelectScreen({super.key, required this.catalog});
  final GameCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レスラー選択')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: catalog.wrestlers.length,
        itemBuilder: (context, index) {
          final w = catalog.wrestlers[index];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.red.shade900,
                child: Text(w.name.substring(0, 1)),
              ),
              title: Text(
                w.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '${w.subtitle}\nHP ${w.maxHp}  '
                '打${w.attack[Attribute.strike]} / 投${w.attack[Attribute.throwMove]} / 関${w.attack[Attribute.submission]}\n'
                '必殺技：${w.finisher.name}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final opponents = catalog.wrestlers
                    .where((x) => x.id != w.id)
                    .toList();
                final cpu = opponents[(index + 1) % opponents.length];
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BattleScreen(catalog: catalog, wrestler: w, cpu: cpu),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    required this.catalog,
    required this.wrestler,
    required this.cpu,
  });
  final GameCatalog catalog;
  final Wrestler wrestler;
  final Wrestler cpu;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  late final MatchEngine engine;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    engine = MatchEngine(
      FighterState(widget.wrestler, widget.catalog.deckFor(widget.wrestler)),
      FighterState(widget.cpu, widget.catalog.deckFor(widget.cpu)),
    )..start();
  }

  Future<void> act(void Function() action) async {
    if (busy || engine.phase == MatchPhase.gameOver) return;
    setState(() {
      busy = true;
      action();
    });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    while (mounted &&
        engine.phase != MatchPhase.gameOver &&
        (!engine.playerActive ||
            (engine.phase == MatchPhase.followUp && !engine.playerActive) ||
            (engine.phase == MatchPhase.kickOutDecision &&
                engine.playerActive))) {
      setState(cpuStep);
      await Future<void>.delayed(const Duration(milliseconds: 550));
    }
    if (mounted) {
      setState(() => busy = false);
      if (engine.phase == MatchPhase.gameOver) _showResult();
    }
  }

  void cpuStep() {
    if (engine.phase == MatchPhase.main ||
        engine.phase == MatchPhase.rallyResponse) {
      final cpu = engine.active;
      if (engine.canUseFinisher(cpu)) {
        engine.play(cpu, cpu.wrestler.finisher, finisher: true);
        return;
      }
      final valid = cpu.hand.where((c) => engine.canCounter(cpu, c)).toList();
      if (valid.isEmpty) {
        engine.declineResponse();
      } else {
        valid.sort(
          (a, b) => engine.power(cpu, a).compareTo(engine.power(cpu, b)),
        );
        engine.play(cpu, valid.first);
      }
    } else if (engine.phase == MatchPhase.followUp) {
      engine.declarePin();
    } else if (engine.phase == MatchPhase.kickOutDecision) {
      if (engine.hasKickOutCard) {
        engine.kickOut(withCard: true);
      } else if (engine.canHpKickOut) {
        engine.kickOut(withCard: false);
      } else {
        engine.acceptDefeat();
      }
    }
  }

  void _showResult() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ResultScreen(engine: engine)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAct = engine.playerActive && !busy;
    return Scaffold(
      appBar: AppBar(
        title: Text('TURN ${engine.turn}'),
        actions: [Center(child: Text('満足度 ${engine.satisfaction}  '))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _fighterBar(engine.cpu, cpu: true),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xff242733),
                  border: Border.all(color: Colors.white24, width: 3),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _phaseText(),
                      style: const TextStyle(color: Colors.amber),
                    ),
                    const SizedBox(height: 12),
                    if (engine.rally.isEmpty)
                      const Text('RING\n技を繰り出せ！', textAlign: TextAlign.center)
                    else
                      ...engine.rally.reversed
                          .take(3)
                          .map(
                            (p) => Card(
                              color: p.byPlayer
                                  ? Colors.red.shade900
                                  : Colors.blue.shade900,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  '${p.card.name}  威力 ${p.power}${p.advantage ? "  有利+1" : ""}',
                                ),
                              ),
                            ),
                          ),
                    const SizedBox(height: 8),
                    Text('ラリー ${engine.rally.length} / 最大 ${engine.maxRally}'),
                  ],
                ),
              ),
            ),
            if (canAct && engine.phase == MatchPhase.followUp)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => act(engine.declarePin),
                    child: const Text('フォール'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => act(engine.declinePin),
                    child: const Text('続行'),
                  ),
                ],
              )
            else if (canAct && engine.phase == MatchPhase.kickOutDecision)
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: engine.hasKickOutCard
                        ? () => act(() => engine.kickOut(withCard: true))
                        : null,
                    child: const Text('カードで返す'),
                  ),
                  FilledButton(
                    onPressed: engine.canHpKickOut
                        ? () => act(() => engine.kickOut(withCard: false))
                        : null,
                    child: Text(
                      'HP${engine.kickOutCost(engine.lastDamage)}で返す',
                    ),
                  ),
                  TextButton(
                    onPressed: () => act(engine.acceptDefeat),
                    child: const Text('敗北を受け入れる'),
                  ),
                ],
              )
            else if (canAct &&
                engine.phase == MatchPhase.rallyResponse &&
                engine.rally.isNotEmpty)
              OutlinedButton(
                onPressed: () => act(engine.declineResponse),
                child: const Text('対応しない'),
              )
            else
              Text(busy ? 'CPU THINKING...' : 'カードを選択'),
            _fighterBar(engine.player, cpu: false),
            SizedBox(
              height: 152,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                children: [
                  if (!engine.player.finisherUsed)
                    _card(
                      engine.player.wrestler.finisher,
                      finisher: true,
                      enabled:
                          canAct &&
                          (engine.phase == MatchPhase.main ||
                              engine.phase == MatchPhase.rallyResponse) &&
                          engine.canUseFinisher(engine.player),
                    ),
                  ...engine.player.hand.map(
                    (card) => _card(
                      card,
                      enabled:
                          canAct &&
                          (engine.phase == MatchPhase.main ||
                              engine.phase == MatchPhase.rallyResponse) &&
                          engine.canCounter(engine.player, card),
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

  Widget _fighterBar(FighterState fighter, {required bool cpu}) {
    final fraction = fighter.hp / fighter.wrestler.maxHp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                cpu ? 'CPU  ${fighter.wrestler.name}' : fighter.wrestler.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'HP ${fighter.hp}/${fighter.wrestler.maxHp}  手札${fighter.hand.length}',
              ),
            ],
          ),
          LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            color: fraction <= .25 ? Colors.red : Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _card(Technique card, {bool finisher = false, required bool enabled}) {
    final p = engine.power(engine.player, card);
    return SizedBox(
      width: 112,
      child: Card(
        color: finisher ? const Color(0xff6b4310) : null,
        child: InkWell(
          onTap: enabled
              ? () => act(
                  () => engine.play(engine.player, card, finisher: finisher),
                )
              : null,
          child: Opacity(
            opacity: enabled ? 1 : .4,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(
                    finisher ? 'FINISHER' : _attribute(card.attribute),
                    style: const TextStyle(fontSize: 10, color: Colors.amber),
                  ),
                  const Spacer(),
                  Text(
                    card.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text('威力 $p  満足 ${card.satisfaction}'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _phaseText() => switch (engine.phase) {
    MatchPhase.main => engine.playerActive ? 'あなたの攻撃' : 'CPUの攻撃',
    MatchPhase.rallyResponse => engine.playerActive ? '技を返せ！' : 'CPUが応戦',
    MatchPhase.followUp => 'ダメージ ${engine.lastDamage}！',
    MatchPhase.kickOutDecision => 'フォール！ キックアウトせよ',
    MatchPhase.gameOver => '試合終了',
  };

  String _attribute(Attribute value) => switch (value) {
    Attribute.strike => '打撃',
    Attribute.throwMove => '投げ',
    Attribute.submission => '関節',
    Attribute.illegal => '反則',
  };
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.engine});
  final MatchEngine engine;

  @override
  Widget build(BuildContext context) {
    final result = engine.result!;
    return Scaffold(
      appBar: AppBar(title: const Text('試合結果')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            result.playerWon ? Icons.emoji_events : Icons.heart_broken,
            size: 72,
            color: result.playerWon ? Colors.amber : Colors.blueGrey,
          ),
          Text(
            result.playerWon ? 'VICTORY' : 'DEFEAT',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 16),
          _row(
            '勝者',
            result.playerWon
                ? engine.player.wrestler.name
                : engine.cpu.wrestler.name,
          ),
          _row('決着', result.method.name),
          _row('総ターン', '${engine.turn}'),
          _row('最大ラリー', '${engine.maxRally}'),
          _row(
            'キックアウト',
            '${engine.player.kickOutCount + engine.cpu.kickOutCount}回',
          ),
          _row('観客満足度', '${engine.satisfaction}'),
          Center(
            child: Text(
              engine.rank,
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w900,
                color: Colors.amber,
              ),
            ),
          ),
          const Divider(),
          const Text('試合ログ', style: TextStyle(fontSize: 20)),
          ...engine.logs.reversed.map(
            (line) => ListTile(
              dense: true,
              leading: const Icon(Icons.chevron_right),
              title: Text(line),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
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

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(label),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
