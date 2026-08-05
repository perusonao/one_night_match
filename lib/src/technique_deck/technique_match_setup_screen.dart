import 'package:flutter/material.dart';

import '../wrestler_editor/models.dart' show WrestlerDefinition;
import '../wrestler_editor/repository.dart';
import 'technique_deck_model_decks.dart';
import 'technique_deck_storage.dart';
import 'technique_match_cpu.dart';
import 'technique_match_screen.dart';

/// 【ゲームサイクル整理ラウンド 優先度10】トップページからTechnique Match
/// を始めるためのセットアップ画面。
///
/// これまでTechnique Matchは「Debug分析」画面を経由しないと開始できず、
/// 一般プレイヤー向けの導線が存在しなかった。この画面で
/// ①モード選択（CPU対戦／2人対戦）②自分のレスラー選択③自分のデッキ
/// （保存済み優先・無ければモデルデッキ）④CPUレスラー選択（ランダム／
/// 指定）⑤CPU難易度（現状Normalのみ）を選び、「試合開始」で
/// [TechniqueMatchScreen] へ渡す。AutoGeneratorは呼び出さない
/// （デッキの解決自体は[TechniqueMatchScreen]側の既存ロジック
/// ―保存済み→モデルデッキ→やむを得ない場合のみAutoGenerator―を
/// そのまま使う。このロジック自体は今回変更していない）。
class TechniqueMatchSetupScreen extends StatefulWidget {
  const TechniqueMatchSetupScreen({super.key, this.wrestlerRepository});

  final LocalWrestlerRepository? wrestlerRepository;

  @override
  State<TechniqueMatchSetupScreen> createState() => _TechniqueMatchSetupScreenState();
}

enum _OpponentMode { cpu, human }

enum _CpuWrestlerChoice { random, specified }

class _TechniqueMatchSetupScreenState extends State<TechniqueMatchSetupScreen> {
  late final LocalWrestlerRepository wrestlerRepository =
      widget.wrestlerRepository ?? LocalWrestlerRepository();
  late final TechniqueDeckRepository deckRepository = LocalTechniqueDeckRepository();

  List<WrestlerDefinition>? wrestlers;
  WrestlerDefinition? myWrestler;
  WrestlerDefinition? cpuWrestler;
  _OpponentMode mode = _OpponentMode.cpu; // 標準はCPU対戦。
  _CpuWrestlerChoice cpuChoice = _CpuWrestlerChoice.random;
  String? myDeckNote;

  @override
  void initState() {
    super.initState();
    wrestlerRepository.loadAll().then((items) async {
      if (!mounted) return;
      setState(() {
        wrestlers = items;
        if (items.isNotEmpty) myWrestler = items.first;
        if (items.length > 1) cpuWrestler = items[1];
      });
      await _refreshDeckNote();
    });
  }

  Future<void> _refreshDeckNote() async {
    final wrestler = myWrestler;
    if (wrestler == null) return;
    final saved = await deckRepository.loadAll();
    final match = saved.where((r) => r.wrestlerId == wrestler.id).toList();
    if (!mounted) return;
    setState(() {
      if (match.isNotEmpty) {
        myDeckNote = '保存済みデッキ「${match.first.name}」を使用します';
      } else if (findTechniquePhase7AModelDeck(wrestler.id) != null) {
        myDeckNote = 'モデルデッキを使用します（保存済みデッキがまだありません）';
      } else {
        myDeckNote = '保存済みデッキ・モデルデッキが無いため仮デッキを自動生成します';
      }
    });
  }

  WrestlerDefinition _resolveCpuWrestler(List<WrestlerDefinition> items) {
    if (cpuChoice == _CpuWrestlerChoice.specified && cpuWrestler != null) {
      return cpuWrestler!;
    }
    final candidates = items.where((w) => w.id != myWrestler?.id).toList();
    final pool = candidates.isNotEmpty ? candidates : items;
    pool.shuffle();
    return pool.first;
  }

  void _startMatch() {
    final items = wrestlers;
    final self = myWrestler;
    if (items == null || self == null) return;
    final opponent = mode == _OpponentMode.cpu
        ? _resolveCpuWrestler(items)
        : (cpuWrestler ?? items.firstWhere((w) => w.id != self.id, orElse: () => self));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TechniqueMatchScreen(
          wrestlerRepository: wrestlerRepository,
          vsCpu: mode == _OpponentMode.cpu,
          cpuLevel: TechniqueCpuLevel.normal,
          initialWrestlerAId: self.id,
          initialWrestlerBId: opponent.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = wrestlers;
    return Scaffold(
      appBar: AppBar(title: const Text('試合を始める')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '① モード選択',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SegmentedButton<_OpponentMode>(
                  segments: const [
                    ButtonSegment(
                      value: _OpponentMode.cpu,
                      label: Text('CPU対戦'),
                      icon: Icon(Icons.smart_toy_outlined),
                    ),
                    ButtonSegment(
                      value: _OpponentMode.human,
                      label: Text('2人対戦'),
                      icon: Icon(Icons.people_outline),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setState(() => mode = s.first),
                ),
                const SizedBox(height: 20),
                const Text(
                  '② 自分のレスラー',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<WrestlerDefinition>(
                  initialValue: myWrestler,
                  items: [
                    for (final w in items) DropdownMenuItem(value: w, child: Text(w.name)),
                  ],
                  onChanged: (w) {
                    setState(() => myWrestler = w);
                    _refreshDeckNote();
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  '③ 自分のデッキ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  myDeckNote ?? '確認中…',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 20),
                if (mode == _OpponentMode.cpu) ...[
                  const Text(
                    '④ CPUレスラー',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_CpuWrestlerChoice>(
                    segments: const [
                      ButtonSegment(value: _CpuWrestlerChoice.random, label: Text('ランダム')),
                      ButtonSegment(value: _CpuWrestlerChoice.specified, label: Text('指定')),
                    ],
                    selected: {cpuChoice},
                    onSelectionChanged: (s) => setState(() => cpuChoice = s.first),
                  ),
                  if (cpuChoice == _CpuWrestlerChoice.specified) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<WrestlerDefinition>(
                      initialValue: cpuWrestler,
                      items: [
                        for (final w in items)
                          DropdownMenuItem(value: w, child: Text(w.name)),
                      ],
                      onChanged: (w) => setState(() => cpuWrestler = w),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    '⑤ CPU難易度',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  // 将来Hard/Expert等を追加する場合はここへ選択肢を足す
                  // （TechniqueCpuLevel enumを拡張する構造にしてある）。
                  const Chip(label: Text('Normal（唯一の実装レベル）')),
                ] else ...[
                  const Text(
                    '④ 対戦相手のレスラー（同じ画面で操作します）',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<WrestlerDefinition>(
                    initialValue: cpuWrestler,
                    items: [
                      for (final w in items) DropdownMenuItem(value: w, child: Text(w.name)),
                    ],
                    onChanged: (w) => setState(() => cpuWrestler = w),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  icon: const Icon(Icons.play_circle),
                  label: const Text('試合開始'),
                  onPressed: myWrestler == null ? null : _startMatch,
                ),
              ],
            ),
    );
  }
}
