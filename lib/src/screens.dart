import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game.dart';
import 'wrestler_editor/editor_screens.dart';
import 'level_match/level_match_screens.dart';
import 'level_match/level_match_engine.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);
const _ink = Color(0xff090910);

class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key, required this.catalog});
  final GameCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.35,
            colors: [Color(0xff651636), Color(0xff180d1b), _ink],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sports_mma, size: 70, color: _pink),
                const SizedBox(height: 14),
                Text(
                  'ONE NIGHT',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    letterSpacing: 5,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                Text(
                  'MATCH',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _pink,
                    letterSpacing: 3,
                  ),
                ),
                const Text('女子プロレスカードバトル  Ver.0.3'),
                const SizedBox(height: 10),
                const Text(
                  '技をつなぎ、観客を沸かせ、3カウントを奪え。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 42),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                    child: Text('クラシックマッチ  Ver.0.2'),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WrestlerSelectScreen(catalog: catalog),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.layers),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                    child: Text('レベルカードマッチ  Ver.0.4'),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LevelMatchIntroScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.style),
                      label: const Text('レスラーカードエディタ'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WrestlerEditorListScreen(),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.menu_book),
                      label: const Text('遊び方'),
                      onPressed: () => _showRules(context),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Debug分析'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DebugScreen()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRules(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '3分でわかる遊び方',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _Rule('1', '技を出す', '場に技がなければ、好きな技からラリー開始。'),
            _Rule('2', '技を返す', '相手より強い技、または有利属性でラリーを返します。'),
            _Rule('3', 'ダメージ', '返せないと、最後の技から防御を引いたダメージを受けます。'),
            _Rule('4', 'フォール', 'ダメージ後にフォール。カードかHPでキックアウトできます。'),
            _Rule('HEAT', '観客を沸かせる', '属性有利、長いラリー、キックアウトでHEAT上昇。勝敗とは別の評価です。'),
          ],
        ),
      ),
    ),
  );
}

class _Rule extends StatelessWidget {
  const _Rule(this.number, this.title, this.body);
  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: _pink,
          child: Text(number, style: const TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(body, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    ),
  );
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
          final wrestler = catalog.wrestlers[index];
          return _WrestlerCard(
            wrestler: wrestler,
            onTap: () {
              final opponents = catalog.wrestlers
                  .where((item) => item.id != wrestler.id)
                  .toList();
              final cpu = opponents[(index + 1) % opponents.length];
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => BattleScreen(
                    catalog: catalog,
                    wrestler: wrestler,
                    cpu: cpu,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _WrestlerCard extends StatelessWidget {
  const _WrestlerCard({required this.wrestler, required this.onTap});
  final Wrestler wrestler;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = wrestler.colors.map(Color.new).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.first.withAlpha(100), const Color(0xff191923)],
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 88,
                height: 130,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: colors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.female,
                  size: 66,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wrestler.name,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      wrestler.subtitle,
                      style: const TextStyle(color: _gold),
                    ),
                    Text('${styleLabel(wrestler.style)}  HP ${wrestler.maxHp}'),
                    const SizedBox(height: 7),
                    Text(
                      '打撃 ${wrestler.attack[Attribute.strike]}/${wrestler.defense[Attribute.strike]}  '
                      '投げ ${wrestler.attack[Attribute.throwMove]}/${wrestler.defense[Attribute.throwMove]}  '
                      '関節 ${wrestler.attack[Attribute.submission]}/${wrestler.defense[Attribute.submission]}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      wrestler.ability,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      'FINISHER：${wrestler.finisher.name}',
                      style: const TextStyle(fontSize: 12, color: _pink),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
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
  String? overlayTitle;
  String? overlayDetail;
  Color overlayColor = _pink;
  bool overlayDark = false;

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
    await _showCues();
    await Future<void>.delayed(const Duration(milliseconds: 260));
    while (mounted &&
        engine.phase != MatchPhase.gameOver &&
        (!engine.playerActive ||
            (engine.phase == MatchPhase.followUp && !engine.playerActive) ||
            (engine.phase == MatchPhase.kickOutDecision &&
                engine.playerActive))) {
      setState(engine.cpuStep);
      await _showCues();
      await Future<void>.delayed(const Duration(milliseconds: 380));
    }
    if (!mounted) return;
    setState(() => busy = false);
    if (engine.phase == MatchPhase.gameOver) {
      await MatchHistoryStore().save(engine);
      if (mounted) _showResult();
    }
  }

  Future<void> _showCues() async {
    while (engine.cues.isNotEmpty && mounted) {
      final cue = engine.cues.removeAt(0);
      if (cue.type == CueType.pin) {
        for (final count in const ['ONE', 'TWO', 'THREE']) {
          if (!mounted) return;
          setState(() {
            overlayDark = false;
            overlayColor = Colors.white;
            overlayTitle = count;
            overlayDetail = 'COUNT';
          });
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        if (mounted) setState(() => overlayTitle = null);
        continue;
      }
      final duration = cue.type == CueType.pin ? 1050 : 650;
      setState(() {
        overlayDark = cue.type == CueType.finisher;
        overlayColor = cue.type == CueType.heat ? _gold : _pink;
        overlayTitle = cue.type == CueType.heat
            ? '${cue.value >= 0 ? '+' : ''}${cue.value} HEAT'
            : cue.title;
        overlayDetail = cue.type == CueType.heat ? cue.title : cue.detail;
      });
      await Future<void>.delayed(Duration(milliseconds: duration));
      if (mounted) setState(() => overlayTitle = null);
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
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _gold.withAlpha(35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                'HEAT ${engine.heat}',
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _fighterBar(engine.cpu, cpu: true),
                if (engine.rallyGuide != null)
                  _RallyGuidePanel(guide: engine.rallyGuide!),
                Expanded(child: _ring()),
                _decisionArea(canAct),
                _fighterBar(engine.player, cpu: false),
                _hand(canAct),
              ],
            ),
          ),
          if (overlayTitle != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: 1,
                  child: Container(
                    color: overlayDark ? Colors.black87 : Colors.black45,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          overlayTitle!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: overlayColor,
                            shadows: const [Shadow(blurRadius: 18)],
                          ),
                        ),
                        if (overlayDetail?.isNotEmpty == true)
                          Text(
                            overlayDetail!,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ring() => Container(
    width: double.infinity,
    margin: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff2d2233), Color(0xff17151e)],
      ),
      border: Border.all(color: _pink.withAlpha(100), width: 3),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _phaseText(),
          style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (engine.rally.isEmpty)
          const Text('RING\n技を繰り出せ！', textAlign: TextAlign.center)
        else
          ...engine.rally.reversed
              .take(3)
              .map(
                (played) => Card(
                  color: played.byPlayer
                      ? const Color(0xff7f1d3f)
                      : const Color(0xff293273),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      '${played.card.name}  ${attributeLabel(played.card.attribute)}  威力${played.power}',
                    ),
                  ),
                ),
              ),
        Text(
          'ラリー ${engine.rally.length} / 最大 ${engine.maxRally}',
          style: const TextStyle(color: Colors.white60),
        ),
      ],
    ),
  );

  Widget _decisionArea(bool canAct) {
    if (canAct && engine.phase == MatchPhase.followUp) {
      return FilledButton.icon(
        icon: const Icon(Icons.sports),
        label: const Text('フォール判断'),
        onPressed: _showPinDialog,
      );
    }
    if (canAct && engine.phase == MatchPhase.kickOutDecision) {
      return FilledButton.icon(
        icon: const Icon(Icons.flash_on),
        label: const Text('キックアウト判断'),
        onPressed: _showKickOutDialog,
      );
    }
    if (canAct &&
        engine.phase == MatchPhase.rallyResponse &&
        engine.rally.isNotEmpty) {
      return OutlinedButton(
        onPressed: () => act(engine.declineResponse),
        child: const Text('対応しない（ダメージを受ける）'),
      );
    }
    return Text(busy ? 'CPU THINKING...' : 'カードをタップして詳細を確認');
  }

  Future<void> _showPinDialog() async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('フォールしますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('直前のダメージ：${engine.lastDamage}'),
            const SizedBox(height: 10),
            const ListTile(
              leading: Icon(Icons.local_fire_department, color: _gold),
              title: Text('試合を続ける'),
              subtitle: Text('HEAT+1\n次のラリーは自分から開始'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'continue'),
            child: const Text('試合を続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'pin'),
            child: const Text('フォールする'),
          ),
        ],
      ),
    );
    if (action == 'pin') await act(engine.declarePin);
    if (action == 'continue') await act(engine.declinePin);
  }

  Future<void> _showKickOutDialog() async {
    final cost = engine.kickOutCost(engine.lastDamage);
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('フォールされています！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OptionInfo(
              title: 'カードでキックアウト',
              detail: 'HP消費 0 / HEAT+${engine.lastWasFinisher ? 4 : 2}',
              enabled: engine.hasKickOutCard,
            ),
            _OptionInfo(
              title: 'HPでキックアウト',
              detail:
                  'HPを$cost消費  ${engine.defender.hp}→${engine.kickOutHpAfter}\nHEAT+${engine.lastWasFinisher ? 4 : 2}',
              enabled: engine.canHpKickOut,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'lose'),
            child: const Text('敗北を受け入れる'),
          ),
          TextButton(
            onPressed: engine.canHpKickOut
                ? () => Navigator.pop(context, 'hp')
                : null,
            child: const Text('HPで返す'),
          ),
          FilledButton(
            onPressed: engine.hasKickOutCard
                ? () => Navigator.pop(context, 'card')
                : null,
            child: const Text('カードで返す'),
          ),
        ],
      ),
    );
    if (action == 'card') await act(() => engine.kickOut(withCard: true));
    if (action == 'hp') await act(() => engine.kickOut(withCard: false));
    if (action == 'lose') await act(engine.acceptDefeat);
  }

  Widget _hand(bool canAct) => SizedBox(
    height: 158,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      children: [
        if (!engine.player.finisherUsed)
          _TechniqueCard(
            card: engine.player.wrestler.finisher,
            power: engine.power(engine.player, engine.player.wrestler.finisher),
            availability: engine.availability(
              engine.player,
              engine.player.wrestler.finisher,
              finisher: true,
            ),
            finisher: true,
            enabled: canAct,
            onTap: () => _showCardDetail(
              engine.player.wrestler.finisher,
              finisher: true,
            ),
          ),
        ...engine.player.hand.map(
          (card) => _TechniqueCard(
            card: card,
            power: engine.power(engine.player, card),
            availability: engine.availability(engine.player, card),
            enabled: canAct,
            onTap: () => _showCardDetail(card),
          ),
        ),
      ],
    ),
  );

  Future<void> _showCardDetail(Technique card, {bool finisher = false}) async {
    final attack = engine.player.wrestler.attack[card.attribute] ?? 0;
    final availability = engine.availability(
      engine.player,
      card,
      finisher: finisher,
    );
    final use = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 130,
                width: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: finisher
                        ? [_gold, _pink]
                        : [_pink, const Color(0xff6d28d9)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(finisher ? Icons.bolt : Icons.sports_mma, size: 62),
              ),
              const SizedBox(height: 12),
              Text(
                card.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${attributeLabel(card.attribute)} / ${finisher ? "フィニッシャー" : "技カード"}',
              ),
              const Divider(),
              _detailRow('基本攻撃力', '${card.basePower}'),
              _detailRow('レスラー補正', '+$attack'),
              _detailRow(
                '実攻撃力',
                '${engine.power(engine.player, card)}',
                strong: true,
              ),
              _detailRow(
                '満足度',
                '${card.heat >= 0 ? "+" : ""}${card.heat} HEAT',
              ),
              ListTile(
                title: const Text('効果'),
                subtitle: Text(card.description),
              ),
              ListTile(
                leading: Icon(
                  availability.usable ? Icons.check_circle : Icons.cancel,
                  color: availability.usable
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
                title: Text(availability.usable ? '使用可能' : '使用不可'),
                subtitle: Text(availability.reason),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: availability.usable
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('この技を使う'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (use == true) {
      await act(() => engine.play(engine.player, card, finisher: finisher));
    }
  }

  Widget _fighterBar(FighterState fighter, {required bool cpu}) {
    final fraction = fighter.hp / fighter.wrestler.maxHp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Color(fighter.wrestler.colors.first),
                child: const Icon(Icons.female, size: 18),
              ),
              const SizedBox(width: 7),
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
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            color: fraction <= .25 ? Colors.red : _pink,
          ),
        ],
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
}

class _RallyGuidePanel extends StatelessWidget {
  const _RallyGuidePanel({required this.guide});
  final RallyGuide guide;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xff251a2b),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: _gold.withAlpha(90)),
    ),
    child: Row(
      children: [
        const Icon(Icons.route, color: _gold),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '相手技：${guide.cardName} / ${attributeLabel(guide.attribute)} / 実攻撃力${guide.power}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '返す条件：実攻撃力${guide.directPower}以上  または  ${guide.advantageAttribute == null ? "有利属性なし" : "${attributeLabel(guide.advantageAttribute!)}・実攻撃力${guide.advantageMinimumPower}以上"}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TechniqueCard extends StatelessWidget {
  const _TechniqueCard({
    required this.card,
    required this.power,
    required this.availability,
    required this.enabled,
    required this.onTap,
    this.finisher = false,
  });
  final Technique card;
  final int power;
  final CardAvailability availability;
  final bool enabled;
  final VoidCallback onTap;
  final bool finisher;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 118,
    child: Card(
      color: finisher ? const Color(0xff6b4310) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(
                    finisher ? 'FINISHER' : attributeLabel(card.attribute),
                    style: const TextStyle(fontSize: 10, color: _gold),
                  ),
                  const Spacer(),
                  Text(
                    card.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text('実攻 $power  HEAT ${card.heat}'),
                  if (!availability.usable && enabled)
                    Text(
                      '× ${availability.reason}',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.redAccent,
                      ),
                    ),
                ],
              ),
            ),
            if (!availability.usable || !enabled)
              Positioned.fill(child: Container(color: Colors.black38)),
          ],
        ),
      ),
    ),
  );
}

class _OptionInfo extends StatelessWidget {
  const _OptionInfo({
    required this.title,
    required this.detail,
    required this.enabled,
  });
  final String title;
  final String detail;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: enabled,
    leading: Icon(enabled ? Icons.check_circle : Icons.block),
    title: Text(title),
    subtitle: Text(detail),
  );
}

Widget _detailRow(String label, String value, {bool strong = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Text(label),
      const Spacer(),
      Text(
        value,
        style: TextStyle(
          fontWeight: strong ? FontWeight.w900 : FontWeight.normal,
          fontSize: strong ? 20 : 14,
          color: strong ? _gold : null,
        ),
      ),
    ],
  ),
);

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.engine});
  final MatchEngine engine;

  @override
  Widget build(BuildContext context) {
    final result = engine.result!;
    final winner = result.playerWon
        ? engine.player.wrestler.name
        : engine.cpu.wrestler.name;
    return Scaffold(
      appBar: AppBar(title: const Text('試合結果')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.emoji_events, size: 68, color: _gold),
          Text(
            result.playerWon ? 'VICTORY' : 'DEFEAT',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          Text(
            engine.matchTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              color: _pink,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          _resultRow('勝者', winner),
          _resultRow('決着技', result.finishingMove),
          _resultRow(
            '決着方法',
            result.method == FinishMethod.pin ? 'フォール' : result.method.name,
          ),
          _resultRow('試合時間', '${engine.turn}ターン'),
          _resultRow('最大ラリー', '${engine.maxRally}'),
          _resultRow('キックアウト', '${engine.totalKickOuts}回'),
          _resultRow('HEAT', '${engine.heat}'),
          Center(
            child: Text(
              engine.rank,
              style: const TextStyle(
                fontSize: 70,
                fontWeight: FontWeight.w900,
                color: _gold,
              ),
            ),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('試合JSONをコピー'),
            onPressed: () => _copy(context, engine.toPrettyJson()),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.analytics),
            label: const Text('Debug分析を見る'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DebugScreen()),
            ),
          ),
          const Divider(height: 32),
          const Text(
            '試合ログ',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          ...engine.logs.reversed.map(
            (line) => ListTile(
              dense: true,
              leading: const Icon(Icons.chevron_right),
              title: Text(line),
            ),
          ),
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
}

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  List<Map<String, dynamic>>? matches;
  List<Map<String, dynamic>>? levelMatches;

  @override
  void initState() {
    super.initState();
    MatchHistoryStore().load().then((value) {
      if (mounted) setState(() => matches = value);
    });
    LevelMatchHistoryStore().load().then((value) {
      if (mounted) setState(() => levelMatches = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = matches;
    final analytics = data == null ? null : MatchAnalytics(data);
    final levelData = levelMatches;
    final levelAnalytics = levelData == null
        ? null
        : LevelMatchAnalytics(levelData);
    return Scaffold(
      appBar: AppBar(title: const Text('Debug / MATCH ANALYTICS')),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _metric('総試合数', '${analytics!.totalMatches}'),
                _metric('プレイヤー勝率', _percent(analytics.playerWinRate)),
                _metric(
                  '平均ターン数',
                  analytics.averageOf('turns').toStringAsFixed(1),
                ),
                _metric(
                  '平均HEAT',
                  analytics.averageOf('finalHeat').toStringAsFixed(1),
                ),
                _metric('平均最大ラリー', analytics.averageRally.toStringAsFixed(1)),
                _metric('フィニッシャー使用率', _percent(analytics.finisherUseRate)),
                _metric('フォール成功率', _percent(analytics.pinSuccessRate)),
                _metric('HPキックアウト率', _percent(analytics.hpKickOutRate)),
                const SizedBox(height: 18),
                const Text(
                  'レスラー別勝率',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (analytics.wrestlerWinRates.isEmpty)
                  const Text('試合データがありません')
                else
                  ...analytics.wrestlerWinRates.entries.map(
                    (entry) => _metric(entry.key, _percent(entry.value)),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: data.isEmpty
                      ? null
                      : () => _copy(
                          context,
                          const JsonEncoder.withIndent('  ').convert(data.last),
                        ),
                  icon: const Icon(Icons.copy),
                  label: const Text('最新試合JSONをコピー'),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Ver.0.4 LEVEL CARD MATCH',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _pink,
                  ),
                ),
                if (levelAnalytics == null)
                  const LinearProgressIndicator()
                else ...[
                  _metric('総試合数', '${levelAnalytics.totalMatches}'),
                  _metric('プレイヤー勝率', _percent(levelAnalytics.playerWinRate)),
                  _metric(
                    '平均ターン数',
                    levelAnalytics.averageGame('turns').toStringAsFixed(1),
                  ),
                  _metric(
                    '平均最終HEAT',
                    levelAnalytics.averageGame('finalHeat').toStringAsFixed(1),
                  ),
                  _metric(
                    'Level 2到達率',
                    _percent(
                      levelAnalytics.playerMetricRate('level2UnlockedTurn'),
                    ),
                  ),
                  _metric(
                    'Level 3到達率',
                    _percent(
                      levelAnalytics.playerMetricRate('level3UnlockedTurn'),
                    ),
                  ),
                  _metric(
                    'Level 2平均到達ターン',
                    levelAnalytics
                        .averagePlayerTurn('level2UnlockedTurn')
                        .toStringAsFixed(1),
                  ),
                  _metric(
                    'Level 3平均到達ターン',
                    levelAnalytics
                        .averagePlayerTurn('level3UnlockedTurn')
                        .toStringAsFixed(1),
                  ),
                  _metric(
                    'フィニッシャー使用率',
                    _percent(levelAnalytics.playerMetricRate('finisherUsed')),
                  ),
                  _metric(
                    'フィニッシャー平均使用ターン',
                    levelAnalytics
                        .averagePlayerTurn('finisherUsedTurn')
                        .toStringAsFixed(1),
                  ),
                  _metric(
                    '平均セット交換回数',
                    levelAnalytics.averageSetReplacements.toStringAsFixed(1),
                  ),
                  _metric('山札切れ率', _percent(levelAnalytics.deckOutRate)),
                  const SizedBox(height: 12),
                  const Text(
                    'レスラー別勝率',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final entry in levelAnalytics.wrestlerWinRates.entries)
                    _metric(entry.key, _percent(entry.value)),
                  const Text(
                    '属性別技使用率',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final entry
                      in levelAnalytics.attributeMoveUseRates.entries)
                    _metric(entry.key, _percent(entry.value)),
                  FilledButton.icon(
                    onPressed: levelData!.isEmpty
                        ? null
                        : () => _copy(
                            context,
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(levelData.last),
                          ),
                    icon: const Icon(Icons.copy),
                    label: const Text('最新Ver.0.4試合JSONをコピー'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _metric(String label, String value) => Card(
    child: ListTile(
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: _gold,
        ),
      ),
    ),
  );
}

Widget _resultRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    children: [
      Text(label),
      const Spacer(),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    ],
  ),
);

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

Future<void> _copy(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('JSONをコピーしました')));
  }
}
