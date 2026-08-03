import 'package:flutter/material.dart';

import 'editor_screens.dart' show MoveEditScreen;
import 'models.dart';
import 'repository.dart';

// ===== Ver.0.8.0：技マスタ（Technique Master）管理 =====

/// カテゴリ表示（NORMAL=通常技 / SIGNATURE=固有技 / FINISHER）。
String techniqueCategoryLabel(MoveCategory c) => switch (c) {
  MoveCategory.basic => '通常技',
  MoveCategory.normal => '固有技',
  MoveCategory.finisher => 'フィニッシャー',
  MoveCategory.counter => '返し技',
};

Color techniqueCategoryColor(MoveCategory c) => switch (c) {
  MoveCategory.basic => const Color(0xff5a8fd6),
  MoveCategory.normal => const Color(0xffe0a72e),
  MoveCategory.finisher => const Color(0xffe0417e),
  MoveCategory.counter => const Color(0xff8e8e5a),
};

/// タイプ表示（既存6属性を要望の呼称で）。
String techniqueTypeLabel(MoveAttribute a) => switch (a) {
  MoveAttribute.strike => '打撃',
  MoveAttribute.throwMove => '投げ',
  MoveAttribute.submission => '関節',
  MoveAttribute.aerial => '飛び技',
  MoveAttribute.rough => 'ラフ',
  MoveAttribute.counter => '返し',
};

Color techniqueTypeColor(MoveAttribute a) => switch (a) {
  MoveAttribute.strike => const Color(0xffe4443a),
  MoveAttribute.throwMove => const Color(0xff2f6df6),
  MoveAttribute.submission => const Color(0xff2ea44f),
  MoveAttribute.aerial => const Color(0xff9b5de5),
  MoveAttribute.rough => const Color(0xff3a3742),
  MoveAttribute.counter => const Color(0xffe8b23a),
};

/// 決着判定バッジ（PIN/SUB/KO＋強度）。
List<(String, Color)> techniqueFinishBadges(MoveDefinition m) {
  final out = <(String, Color)>[];
  if (m.canPin || m.pinPower > 0) {
    out.add(('PIN${m.pinPower > 0 ? m.pinPower : ""}', const Color(0xffe0a72e)));
  }
  if (m.canSubmit || m.submissionPower > 0) {
    out.add(('SUB${m.submissionPower > 0 ? m.submissionPower : ""}',
        const Color(0xff2ea44f)));
  }
  if (m.canKO) out.add(('KO', const Color(0xffe4443a)));
  return out;
}

enum _Sort { name, damage, speed }

/// 技マスタ一覧画面（検索・絞り込み・並べ替え・登録/編集/削除）。
class TechniqueListScreen extends StatefulWidget {
  const TechniqueListScreen({super.key, required this.repository});
  final LocalWrestlerRepository repository;

  @override
  State<TechniqueListScreen> createState() => _TechniqueListScreenState();
}

class _TechniqueListScreenState extends State<TechniqueListScreen> {
  String _query = '';
  MoveCategory? _category;
  MoveAttribute? _type;
  _Sort _sort = _Sort.name;
  Map<String, int> _usage = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    final wrestlers = await widget.repository.loadAll();
    final usage = <String, int>{};
    for (final w in wrestlers) {
      final ids = <String>{
        for (final lv in w.levels) ...[
          ...lv.moveIds,
          if (lv.finisherId != null) lv.finisherId!,
          if (lv.counterMoveId != null) lv.counterMoveId!,
        ],
        ...w.basicMoveIds.values,
      };
      for (final id in ids) {
        usage[id] = (usage[id] ?? 0) + 1;
      }
    }
    if (mounted) {
      setState(() {
        _usage = usage;
        _loading = false;
      });
    }
  }

  List<MoveDefinition> get _filtered {
    final list = widget.repository.moves.values.where((m) {
      if (_category != null && m.category != _category) return false;
      if (_type != null && m.attribute != _type) return false;
      if (_query.isNotEmpty &&
          !m.name.toLowerCase().contains(_query.toLowerCase()) &&
          !m.id.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _Sort.damage:
        list.sort((a, b) => b.power.compareTo(a.power));
      case _Sort.speed:
        list.sort((a, b) => b.speed.compareTo(a.speed));
    }
    return list;
  }

  Future<void> _create() async {
    final now = DateTime.now().microsecondsSinceEpoch;
    final move = MoveDefinition(
      id: 'tech_$now',
      name: '',
      category: MoveCategory.normal,
      attribute: MoveAttribute.strike,
      power: 0,
      heat: 0,
      requiredCards: {for (final v in MoveAttribute.values) v: 0},
      discardAfterUse: {for (final v in MoveAttribute.values) v: 0},
    );
    await _openEditor(move);
  }

  Future<void> _openEditor(MoveDefinition move) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MoveEditScreen(
          initial: move,
          onSaved: (saved) => widget.repository.saveMove(saved),
        ),
      ),
    );
    if (mounted) {
      setState(() {}); // moves マップは即時反映
      await _refreshUsage();
    }
  }

  Future<void> _delete(MoveDefinition m) async {
    final count = _usage[m.id] ?? 0;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${m.name}」は$count人が使用中のため削除できません')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('「${m.name}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repository.deleteMove(m.id);
    if (mounted) {
      setState(() {});
      await _refreshUsage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('技一覧（技マスタ）'),
        actions: [
          PopupMenuButton<_Sort>(
            icon: const Icon(Icons.sort),
            tooltip: '並べ替え',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.name, child: Text('名前順')),
              PopupMenuItem(value: _Sort.damage, child: Text('ダメージ順')),
              PopupMenuItem(value: _Sort.speed, child: Text('速度順')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('新しい技'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _filters(),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('該当する技がありません'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _card(items[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
    child: Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '技名で検索',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _catChip('全カテゴリ', null),
              for (final c in const [
                MoveCategory.basic,
                MoveCategory.normal,
                MoveCategory.finisher,
                MoveCategory.counter,
              ])
                _catChip(techniqueCategoryLabel(c), c),
              const SizedBox(width: 8),
              _typeDropdown(),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _catChip(String label, MoveCategory? c) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _category == c,
      onSelected: (_) => setState(() => _category = c),
    ),
  );

  Widget _typeDropdown() => DropdownButton<MoveAttribute?>(
    value: _type,
    hint: const Text('全タイプ', style: TextStyle(fontSize: 12)),
    items: [
      const DropdownMenuItem(value: null, child: Text('全タイプ')),
      for (final a in MoveAttribute.values)
        DropdownMenuItem(value: a, child: Text(techniqueTypeLabel(a))),
    ],
    onChanged: (v) => setState(() => _type = v),
  );

  Widget _card(MoveDefinition m) {
    final usage = _usage[m.id] ?? 0;
    final finishes = techniqueFinishBadges(m);
    return Card(
      child: InkWell(
        onTap: () => _openEditor(m),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('★' * m.rank.clamp(1, 5),
                      style: const TextStyle(
                          color: Color(0xffffc857), fontSize: 13)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m.name.isEmpty ? '(名称未設定)' : m.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text('${m.displayDeckPoints}P',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white54)),
                  IconButton(
                    tooltip: '削除',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _delete(m),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
              if (m.energyCost.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      const Text('必要E',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white54)),
                      for (final e in m.energyCost.entries)
                        _badge('${techniqueTypeLabel(e.key)}×${e.value}',
                            techniqueTypeColor(e.key)),
                    ],
                  ),
                ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _badge(techniqueCategoryLabel(m.category),
                      techniqueCategoryColor(m.category)),
                  _badge(techniqueTypeLabel(m.attribute),
                      techniqueTypeColor(m.attribute)),
                  _stat('Dmg', '${m.power}'),
                  _stat('Spd', '${m.speed}'),
                  _badge('HEAT${m.displayHeatCost}', const Color(0xff9b5de5)),
                  if (m.heat != 0)
                    _stat('増減', '${m.heat >= 0 ? "+" : ""}${m.heat}'),
                  for (final f in finishes) _badge(f.$1, f.$2),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (m.requiredPreviousState != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('条件: ${m.requiredPreviousState}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white60)),
                    ),
                  const Spacer(),
                  Icon(Icons.groups,
                      size: 14,
                      color: usage > 0 ? Colors.white70 : Colors.white24),
                  const SizedBox(width: 3),
                  Text('使用 $usage人',
                      style: TextStyle(
                          fontSize: 11,
                          color: usage > 0 ? Colors.white70 : Colors.white38)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.8)),
    ),
    child: Text(text,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.bold)),
  );

  Widget _stat(String label, String value) => Text('$label $value',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600));
}

/// 技選択ダイアログ（レスラー編集の「＋追加」で使用）。
/// [allowedCategory] を指定するとそのカテゴリのみ表示。[multi] で複数選択。
class TechniquePickerScreen extends StatefulWidget {
  const TechniquePickerScreen({
    super.key,
    required this.repository,
    this.allowedCategory,
    this.multi = true,
    this.preselected = const {},
  });
  final LocalWrestlerRepository repository;
  final MoveCategory? allowedCategory;
  final bool multi;
  final Set<String> preselected;

  @override
  State<TechniquePickerScreen> createState() => _TechniquePickerScreenState();
}

class _TechniquePickerScreenState extends State<TechniquePickerScreen> {
  String _query = '';
  MoveAttribute? _type;
  late final Set<String> _selected = {...widget.preselected};

  List<MoveDefinition> get _filtered {
    return widget.repository.moves.values.where((m) {
      if (widget.allowedCategory != null &&
          m.category != widget.allowedCategory) {
        return false;
      }
      if (_type != null && m.attribute != _type) return false;
      if (_query.isNotEmpty &&
          !m.name.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _toggle(String id) {
    setState(() {
      if (widget.multi) {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      } else {
        _selected
          ..clear()
          ..add(id);
        Navigator.pop(context, _selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final title = widget.allowedCategory == null
        ? '技を選択'
        : '${techniqueCategoryLabel(widget.allowedCategory!)}を選択';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.multi)
            TextButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: const Text('決定'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '技名で検索',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<MoveAttribute?>(
                    value: _type,
                    hint: const Text('全タイプ'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('全タイプ')),
                      for (final a in MoveAttribute.values)
                        DropdownMenuItem(
                            value: a, child: Text(techniqueTypeLabel(a))),
                    ],
                    onChanged: (v) => setState(() => _type = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final m = items[i];
                final selected = _selected.contains(m.id);
                return CheckboxListTile(
                  value: selected,
                  dense: true,
                  onChanged: (_) => _toggle(m.id),
                  title: Text(m.name.isEmpty ? '(名称未設定)' : m.name),
                  subtitle: Text(
                    '${techniqueCategoryLabel(m.category)} / '
                    '${techniqueTypeLabel(m.attribute)} / '
                    'Dmg ${m.power} / Spd ${m.speed}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
