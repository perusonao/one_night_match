import 'package:flutter/material.dart';

import '../wrestler_editor/models.dart' show WrestlerDefinition;
import '../wrestler_editor/repository.dart';
import 'technique_deck_deck.dart';
import 'technique_deck_defaults.dart';
import 'technique_deck_generator.dart';
import 'technique_deck_models.dart';
import 'technique_deck_storage.dart';
import 'technique_match_state.dart';

/// Technique Deck Rules Phase 3: 最初のプレイアブル画面「Technique Match」。
///
/// スタンド／ダウン／疲労・休息・ターン進行・HP／HEAT表示・手札5枚・
/// 山札／捨て札のみを扱う。技の使用・ダメージ・返技・連続攻撃・
/// フォール／ギブアップ・フィニッシャー・CPUは実装しない（Phase 4以降）。
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
      return (match.first.toDeckDefinition(), '保存済みデッキ「${match.first.name}」を使用');
    }
    final result = TechniqueDeckAutoGenerator(
      config: TechniqueDeckGenerationConfig(
        seed: DateTime.now().millisecondsSinceEpoch,
      ),
    ).generate(
      catalog: catalog,
      wrestlerId: wrestler.id,
      deckId: '${wrestler.id}_temp_${DateTime.now().millisecondsSinceEpoch}',
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
            '開発中：Technique Deck Rules Phase 3',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            'まだ技は使えません。スタンド／ダウン／休息とターン進行のみの試作です',
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
          child: Text(
            'ターン${state.turnNumber} ・ ${state.active.wrestlerName}の手番 '
            '・ フェーズ: ${_phaseLabel(state.phase)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      const SizedBox(height: 8),
      _playerCard(state, isActive: true),
      const SizedBox(height: 8),
      _playerCard(state, isActive: false),
      const SizedBox(height: 8),
      Card(
        color: _bg,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
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

  Widget _playerCard(TechniqueMatchState state, {required bool isActive}) {
    final player = isActive ? state.active : state.inactive;
    final isPlayerA = player.wrestlerId == state.playerA.wrestlerId;
    final hpRatio = player.maxHp == 0 ? 0.0 : player.hp / player.maxHp;
    final note = isPlayerA ? deckSourceNoteA : deckSourceNoteB;
    return Card(
      color: isActive ? const Color(0xff2a1c33) : _bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${player.wrestlerName}${isActive ? "（手番）" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _postureColor(player.posture).withValues(alpha: 0.25),
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
            Text('HP ${player.hp} / ${player.maxHp} ・ HEAT ${player.heat}'),
            Text(
              '手札 ${player.hand.length}枚 ・ 山札 ${player.drawPile.length}枚 ・ '
              '捨て札 ${player.discardPile.length}枚',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            if (note != null)
              Text(note, style: const TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in player.hand)
                  Chip(
                    label: Text(
                      catalog.findTechniqueById(entry.cardId)?.name ??
                          catalog.findEnergyById(entry.cardId)?.name ??
                          catalog.findDefenseCardById(entry.cardId)?.name ??
                          entry.cardId,
                      style: const TextStyle(fontSize: 11),
                    ),
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
