import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'repository.dart';
import 'technique_master_screens.dart';
import 'validator.dart';

const _editorPink = Color(0xffff477e);
const _editorGold = Color(0xffffc857);

class WrestlerEditorListScreen extends StatefulWidget {
  const WrestlerEditorListScreen({super.key, this.repository});
  final LocalWrestlerRepository? repository;

  @override
  State<WrestlerEditorListScreen> createState() =>
      _WrestlerEditorListScreenState();
}

class _WrestlerEditorListScreenState extends State<WrestlerEditorListScreen> {
  late final LocalWrestlerRepository repository =
      widget.repository ?? LocalWrestlerRepository();
  List<WrestlerDefinition> wrestlers = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final loaded = await repository.loadAll();
    if (mounted) {
      setState(() {
        wrestlers = loaded;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('レスラーカードエディタ'),
          Text('ONE NIGHT MATCH Ver.0.3', style: TextStyle(fontSize: 11)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '技一覧（技マスタ）',
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TechniqueListScreen(repository: repository),
              ),
            );
            if (mounted) _reload();
          },
          icon: const Icon(Icons.sports_martial_arts),
        ),
        IconButton(
          tooltip: 'JSON読込',
          onPressed: _showImport,
          icon: const Icon(Icons.file_download_outlined),
        ),
        IconButton(
          tooltip: '初期データへ戻す',
          onPressed: _confirmReset,
          icon: const Icon(Icons.restart_alt),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('新規作成'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : wrestlers.isEmpty
        ? const Center(child: Text('レスラーがありません'))
        : RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: wrestlers.length,
              itemBuilder: (_, index) => _WrestlerTile(
                wrestler: wrestlers[index],
                onEdit: () => _openEditor(wrestlers[index]),
                onPreview: () => _showPreview(wrestlers[index]),
                onDuplicate: () async {
                  await repository.duplicate(wrestlers[index].id);
                  await _reload();
                },
                onExport: () => _showExport(wrestlers[index]),
                onDelete: () => _confirmDelete(wrestlers[index]),
              ),
            ),
          ),
  );

  Future<void> _create() async {
    final now = DateTime.now().toUtc();
    final draft = WrestlerDefinition(
      id: 'wrestler_${now.millisecondsSinceEpoch}',
      name: '',
      subtitle: '',
      type: EditorWrestlerType.other,
      maxHp: 100,
      themeColor: '#E91E63',
      levels: [
        for (var level = 1; level <= 3; level++)
          WrestlerLevelDefinition(
            level: level,
            displayName: 'Level $level',
            unlockCondition: level == 1
                ? null
                : const UnlockConditionGroup(
                    operator: ConditionOperator.and,
                    conditions: [
                      UnlockCondition(
                        type: UnlockConditionType.previousLevelUnlocked,
                      ),
                    ],
                  ),
            resistances: {
              for (final attribute in MoveAttribute.values) attribute: 0,
            },
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await _openEditor(draft);
  }

  Future<void> _openEditor(WrestlerDefinition wrestler) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            WrestlerEditScreen(initial: wrestler, repository: repository),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _showPreview(WrestlerDefinition wrestler) => showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
        child: WrestlerCardPreview(wrestler: wrestler, repository: repository),
      ),
    ),
  );

  Future<void> _showExport(WrestlerDefinition wrestler) async {
    final text = await repository.exportJson(wrestler.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${wrestler.name} JSON'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('コピー'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImport() async {
    final controller = TextEditingController();
    WrestlerDefinition? preview;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('レスラーJSON読込'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    minLines: 8,
                    maxLines: 16,
                    decoration: const InputDecoration(
                      labelText: 'JSONを貼り付け',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 12),
                    Text('レスラー名: ${preview!.name}'),
                    Text('レベル数: ${preview!.levels.length}'),
                    Text('データバージョン: ${preview!.dataVersion}'),
                    Text(
                      '上書き対象: ${wrestlers.any((w) => w.id == preview!.id) ? preview!.id : "なし"}',
                    ),
                    const Text(
                      'バリデーション: OK',
                      style: TextStyle(color: Colors.green),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  final item = await repository.importJson(controller.text);
                  setDialogState(() {
                    preview = item;
                    error = null;
                  });
                } on Object catch (e) {
                  setDialogState(() {
                    preview = null;
                    error = '$e';
                  });
                }
              },
              child: const Text('検証'),
            ),
            if (preview != null) ...[
              TextButton(
                onPressed: () async {
                  await repository.save(preview!);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('上書き'),
              ),
              FilledButton(
                onPressed: () async {
                  final now = DateTime.now().toUtc();
                  await repository.save(
                    preview!.copyWith(
                      id: '${preview!.id}_${now.millisecondsSinceEpoch}',
                      name: '${preview!.name} コピー',
                      createdAt: now,
                      updatedAt: now,
                    ),
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('別IDで複製'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    await _reload();
  }

  Future<void> _confirmDelete(WrestlerDefinition wrestler) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('レスラーを削除'),
        content: Text('「${wrestler.name}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await repository.delete(wrestler.id);
      await _reload();
    }
  }

  Future<void> _confirmReset() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('初期データへ戻す'),
        content: const Text('すべての編集内容が失われます。続けますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('初期化'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await repository.resetToDefaults();
      await _reload();
    }
  }
}

class _WrestlerTile extends StatelessWidget {
  const _WrestlerTile({
    required this.wrestler,
    required this.onEdit,
    required this.onPreview,
    required this.onDuplicate,
    required this.onExport,
    required this.onDelete,
  });
  final WrestlerDefinition wrestler;
  final VoidCallback onEdit, onPreview, onDuplicate, onExport, onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _parseColor(wrestler.themeColor),
            child: Text(wrestler.name.isEmpty ? '?' : wrestler.name[0]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wrestler.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  wrestler.subtitle,
                  style: const TextStyle(color: _editorGold),
                ),
                Text(
                  '${wrestlerTypeLabel(wrestler.type)}  HP ${wrestler.maxHp}  Lv.${wrestler.levels.length}',
                ),
                Text(
                  '更新 ${wrestler.updatedAt.toLocal().toString().split('.').first}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      tooltip: '編集',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: 'プレビュー',
                      onPressed: onPreview,
                      icon: const Icon(Icons.visibility),
                    ),
                    IconButton(
                      tooltip: '複製',
                      onPressed: onDuplicate,
                      icon: const Icon(Icons.copy),
                    ),
                    IconButton(
                      tooltip: 'JSON出力',
                      onPressed: onExport,
                      icon: const Icon(Icons.data_object),
                    ),
                    IconButton(
                      tooltip: '削除',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
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

class WrestlerEditScreen extends StatefulWidget {
  const WrestlerEditScreen({
    super.key,
    required this.initial,
    required this.repository,
  });
  final WrestlerDefinition initial;
  final LocalWrestlerRepository repository;

  @override
  State<WrestlerEditScreen> createState() => _WrestlerEditScreenState();
}

class _WrestlerEditScreenState extends State<WrestlerEditScreen>
    with SingleTickerProviderStateMixin {
  late final id = TextEditingController(text: widget.initial.id);
  late final name = TextEditingController(text: widget.initial.name);
  late final subtitle = TextEditingController(text: widget.initial.subtitle);
  late final hp = TextEditingController(text: '${widget.initial.maxHp}');
  late final description = TextEditingController(
    text: widget.initial.description,
  );
  late final color = TextEditingController(text: widget.initial.themeColor);
  late final image = TextEditingController(
    text: widget.initial.imagePath ?? '',
  );
  late final tags = TextEditingController(text: widget.initial.tags.join(', '));
  late EditorWrestlerType type = widget.initial.type;
  late List<WrestlerLevelDefinition> levels = List.of(widget.initial.levels);
  // Ver.0.7.7: レスラー固有の通常技（属性→技ID）。
  late Map<MoveAttribute, String> basicMoveIds =
      Map.of(widget.initial.basicMoveIds);
  int selectedLevel = 0;
  List<String> errors = const [];

  WrestlerDefinition get draft => widget.initial.copyWith(
    id: id.text.trim(),
    name: name.text.trim(),
    subtitle: subtitle.text.trim(),
    type: type,
    maxHp: int.tryParse(hp.text) ?? 0,
    description: description.text.trim(),
    themeColor: color.text.trim(),
    imagePath: image.text.trim().isEmpty ? null : image.text.trim(),
    tags: tags.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(),
    levels: levels,
    basicMoveIds: basicMoveIds,
    updatedAt: DateTime.now().toUtc(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(name.text.isEmpty ? '新規レスラー' : name.text),
      actions: [
        IconButton(
          tooltip: 'プレビュー',
          onPressed: _preview,
          icon: const Icon(Icons.visibility),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: FilledButton.icon(
          key: const Key('saveWrestler'),
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('検証して保存'),
          ),
        ),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (errors.isNotEmpty)
              Card(
                color: Colors.red.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '保存できません',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final error in errors) Text('• $error'),
                    ],
                  ),
                ),
              ),
            _EditorSection(
              title: '1. 基本情報',
              child: Column(
                children: [
                  _field(id, 'レスラーID', key: const Key('wrestlerId')),
                  _field(name, 'リングネーム', key: const Key('wrestlerName')),
                  _field(subtitle, '二つ名'),
                  DropdownButtonFormField(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'タイプ'),
                    items: EditorWrestlerType.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(wrestlerTypeLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => type = value!),
                  ),
                  _field(hp, '最大HP', number: true),
                  _field(description, '説明', lines: 3),
                  _field(color, 'テーマカラー（#RRGGBB）'),
                  _field(image, '画像パス'),
                  _field(tags, 'タグ（カンマ区切り）'),
                ],
              ),
            ),
            _EditorSection(
              title: '2. レベル構成（1〜6）',
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < levels.length; i++)
                          ButtonSegment(
                            value: i,
                            label: Text('Lv.${levels[i].level}'),
                          ),
                      ],
                      selected: {selectedLevel.clamp(0, levels.length - 1)},
                      onSelectionChanged: (value) =>
                          setState(() => selectedLevel = value.first),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: levels.length < 6 ? _addLevel : null,
                        icon: const Icon(Icons.add),
                        label: const Text('追加'),
                      ),
                      TextButton.icon(
                        onPressed:
                            levels.length > 1 &&
                                levels[selectedLevel].level != 1
                            ? _removeLevel
                            : null,
                        icon: const Icon(Icons.remove),
                        label: const Text('削除'),
                      ),
                      IconButton(
                        onPressed: selectedLevel > 0
                            ? () => _moveLevel(-1)
                            : null,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      IconButton(
                        onPressed: selectedLevel < levels.length - 1
                            ? () => _moveLevel(1)
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (levels.isNotEmpty)
              LevelEditor(
                key: ValueKey(
                  '${levels[selectedLevel].level}-${levels[selectedLevel].hashCode}',
                ),
                level: levels[selectedLevel],
                repository: widget.repository,
                onChanged: (value) =>
                    setState(() => levels[selectedLevel] = value),
              ),
            _basicMovesSection(),
            _EditorSection(
              title: '9. プレビュー・JSON',
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _preview,
                    icon: const Icon(Icons.preview),
                    label: const Text('カードプレビュー'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async => Clipboard.setData(
                      ClipboardData(text: draft.toPrettyJson()),
                    ),
                    icon: const Icon(Icons.copy),
                    label: const Text('編集中JSONをコピー'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // Ver.0.7.7: 通常技（技カード1枚で使用）を属性別にセットする画面。
  Widget _basicMovesSection() => _EditorSection(
    title: '通常技（技カード1枚で使用・属性別）',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '手札のカード1枚をそのまま出せる技です。未設定の属性は共通の通常技を使います。',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
        for (final attr in MoveAttribute.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    moveAttributeLabel(attr),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: basicMoveIds[attr],
                    decoration: const InputDecoration(labelText: '通常技'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('共通の通常技'),
                      ),
                      ...widget.repository.moves.values
                          .where(
                            (m) =>
                                m.category == MoveCategory.basic &&
                                m.attribute == attr,
                          )
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name),
                            ),
                          ),
                    ],
                    onChanged: (id) => setState(() {
                      if (id == null) {
                        basicMoveIds.remove(attr);
                      } else {
                        basicMoveIds[attr] = id;
                      }
                    }),
                  ),
                ),
                IconButton(
                  tooltip: '通常技を編集／新規作成',
                  onPressed: () => _openBasicMove(attr, basicMoveIds[attr]),
                  icon: const Icon(Icons.edit),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Future<void> _openBasicMove(MoveAttribute attr, String? existingId) async {
    final existing =
        existingId == null ? null : widget.repository.moves[existingId];
    final now = DateTime.now().microsecondsSinceEpoch;
    // 共通技(basic_*)と衝突しないよう nt_ 接頭辞で作成。
    final move = existing ??
        MoveDefinition(
          id: 'nt_${attr.name}_$now',
          name: '',
          category: MoveCategory.basic,
          attribute: attr,
          power: 0,
          heat: 0,
          requiredCards: {for (final v in MoveAttribute.values) v: 0},
          discardAfterUse: {for (final v in MoveAttribute.values) v: 0},
          consumesSetCards: false,
        );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MoveEditScreen(
          initial: move,
          onSaved: (saved) {
            widget.repository.moves[saved.id] = saved;
            setState(() => basicMoveIds[saved.attribute] = saved.id);
          },
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
    int lines = 1,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: key,
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    ),
  );

  void _addLevel() {
    final used = levels.map((item) => item.level).toSet();
    final next = List.generate(
      6,
      (i) => i + 1,
    ).firstWhere((value) => !used.contains(value));
    setState(() {
      levels.add(
        WrestlerLevelDefinition(
          level: next,
          displayName: '${name.text} Level $next',
          unlockCondition: const UnlockConditionGroup(
            operator: ConditionOperator.and,
            conditions: [
              UnlockCondition(type: UnlockConditionType.previousLevelUnlocked),
            ],
          ),
          resistances: {for (final value in MoveAttribute.values) value: 0},
        ),
      );
      levels.sort((a, b) => a.level.compareTo(b.level));
      selectedLevel = levels.indexWhere((item) => item.level == next);
    });
  }

  void _removeLevel() => setState(() {
    levels.removeAt(selectedLevel);
    selectedLevel = selectedLevel.clamp(0, levels.length - 1);
  });

  void _moveLevel(int delta) => setState(() {
    final target = selectedLevel + delta;
    final item = levels.removeAt(selectedLevel);
    levels.insert(target, item);
    selectedLevel = target;
  });

  Future<void> _save() async {
    final result = const WrestlerValidator().validate(
      draft,
      moves: widget.repository.moves,
      abilities: widget.repository.abilities,
    );
    setState(() => errors = result.errors);
    if (!result.isValid) return;
    await widget.repository.save(draft);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _preview() => showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
        child: WrestlerCardPreview(
          wrestler: draft,
          repository: widget.repository,
        ),
      ),
    ),
  );
}

class LevelEditor extends StatefulWidget {
  const LevelEditor({
    super.key,
    required this.level,
    required this.repository,
    required this.onChanged,
  });
  final WrestlerLevelDefinition level;
  final LocalWrestlerRepository repository;
  final ValueChanged<WrestlerLevelDefinition> onChanged;

  @override
  State<LevelEditor> createState() => _LevelEditorState();
}

class _LevelEditorState extends State<LevelEditor> {
  late WrestlerLevelDefinition value = widget.level;

  void update({
    UnlockConditionGroup? unlock,
    bool clearUnlock = false,
    Map<MoveAttribute, int>? resistances,
    List<String>? moves,
    String? counter,
    bool clearCounter = false,
    String? ability,
    bool clearAbility = false,
    String? finisher,
    bool clearFinisher = false,
    String? flavor,
  }) {
    value = WrestlerLevelDefinition(
      level: value.level,
      displayName: value.displayName,
      unlockCondition: clearUnlock ? null : unlock ?? value.unlockCondition,
      resistances: resistances ?? value.resistances,
      moveIds: moves ?? value.moveIds,
      counterMoveId: clearCounter ? null : counter ?? value.counterMoveId,
      abilityId: clearAbility ? null : ability ?? value.abilityId,
      finisherId: clearFinisher ? null : finisher ?? value.finisherId,
      imagePath: value.imagePath,
      flavorText: flavor ?? value.flavorText,
    );
    widget.onChanged(value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (value.level > 1) _unlockEditor(),
      _EditorSection(
        title: '4. 受け耐性',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final attribute in MoveAttribute.values)
              SizedBox(
                width: 104,
                child: TextFormField(
                  initialValue: '${value.resistances[attribute] ?? 0}',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '${moveAttributeLabel(attribute)}耐性',
                  ),
                  onChanged: (text) {
                    final map = Map<MoveAttribute, int>.from(value.resistances);
                    map[attribute] = int.tryParse(text) ?? -1;
                    update(resistances: map);
                  },
                ),
              ),
          ],
        ),
      ),
      _EditorSection(
        title: '5. 固有技（技カードをセットして使用・最大2種類）',
        child: Column(
          children: [
            for (var index = 0; index < 2; index++)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: index < value.moveIds.length
                          ? value.moveIds[index]
                          : null,
                      decoration: InputDecoration(
                        labelText: '固有技 ${index + 1}',
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('未設定')),
                        ...widget.repository.moves.values
                            .where(
                              (move) => move.category == MoveCategory.normal,
                            )
                            .map(
                              (move) => DropdownMenuItem(
                                value: move.id,
                                child: Text(move.name),
                              ),
                            ),
                      ],
                      onChanged: (id) {
                        final moves = List<String>.from(value.moveIds);
                        while (moves.length <= index) {
                          moves.add('');
                        }
                        moves[index] = id ?? '';
                        moves.removeWhere((item) => item.isEmpty);
                        update(moves: moves);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: '技を編集',
                    onPressed: index < value.moveIds.length
                        ? () => _editMove(value.moveIds[index])
                        : () => _newMove(MoveCategory.normal),
                    icon: const Icon(Icons.edit),
                  ),
                ],
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _pickSignatures,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('技一覧から追加'),
                ),
                TextButton.icon(
                  onPressed: () => _newMove(MoveCategory.normal),
                  icon: const Icon(Icons.add),
                  label: const Text('新規技作成'),
                ),
              ],
            ),
          ],
        ),
      ),
      _singleMove(
        '6. 返し技',
        MoveCategory.counter,
        value.counterMoveId,
        (id) => update(counter: id, clearCounter: id == null),
      ),
      _EditorSection(
        title: '7. 固有能力',
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: value.abilityId,
                decoration: const InputDecoration(labelText: '固有能力（0〜1）'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('未設定')),
                  ...widget.repository.abilities.values.map(
                    (ability) => DropdownMenuItem(
                      value: ability.id,
                      child: Text(ability.name),
                    ),
                  ),
                ],
                onChanged: (id) =>
                    update(ability: id, clearAbility: id == null),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AbilityEditScreen(
                    initial: value.abilityId == null
                        ? null
                        : widget.repository.abilities[value.abilityId],
                    repository: widget.repository,
                    onSaved: (ability) => update(ability: ability.id),
                  ),
                ),
              ),
              icon: const Icon(Icons.edit_note),
            ),
          ],
        ),
      ),
      _singleMove(
        '8. フィニッシャー（最大1）',
        MoveCategory.finisher,
        value.finisherId,
        (id) => update(finisher: id, clearFinisher: id == null),
        onPick: _pickFinisher,
      ),
      _EditorSection(
        title: 'カードテキスト',
        child: TextFormField(
          initialValue: value.flavorText,
          decoration: const InputDecoration(labelText: 'フレーバーテキスト'),
          onChanged: (text) => update(flavor: text),
        ),
      ),
    ],
  );

  Widget _unlockEditor() {
    final group =
        value.unlockCondition ??
        const UnlockConditionGroup(
          operator: ConditionOperator.and,
          conditions: [],
        );
    return _EditorSection(
      title: '3. 解放条件',
      child: Column(
        children: [
          SegmentedButton<ConditionOperator>(
            segments: const [
              ButtonSegment(value: ConditionOperator.and, label: Text('AND')),
              ButtonSegment(value: ConditionOperator.or, label: Text('OR')),
            ],
            selected: {group.operator},
            onSelectionChanged: (selected) => update(
              unlock: UnlockConditionGroup(
                operator: selected.first,
                conditions: group.conditions,
              ),
            ),
          ),
          for (var i = 0; i < group.conditions.length; i++)
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<UnlockConditionType>(
                    initialValue: group.conditions[i].type,
                    items: UnlockConditionType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(_unlockLabel(type)),
                          ),
                        )
                        .toList(),
                    onChanged: (type) {
                      final conditions = List<UnlockCondition>.from(
                        group.conditions,
                      );
                      conditions[i] = UnlockCondition(
                        type: type!,
                        value: _needsValue(type) ? 1 : null,
                      );
                      update(
                        unlock: UnlockConditionGroup(
                          operator: group.operator,
                          conditions: conditions,
                        ),
                      );
                    },
                  ),
                ),
                if (_needsValue(group.conditions[i].type))
                  SizedBox(
                    width: 70,
                    child: TextFormField(
                      initialValue: '${group.conditions[i].value ?? 1}',
                      keyboardType: TextInputType.number,
                      onChanged: (text) {
                        final conditions = List<UnlockCondition>.from(
                          group.conditions,
                        );
                        final old = conditions[i];
                        conditions[i] = UnlockCondition(
                          type: old.type,
                          value: int.tryParse(text),
                          attribute: old.attribute,
                        );
                        update(
                          unlock: UnlockConditionGroup(
                            operator: group.operator,
                            conditions: conditions,
                          ),
                        );
                      },
                    ),
                  ),
                IconButton(
                  onPressed: () {
                    final conditions = List<UnlockCondition>.from(
                      group.conditions,
                    )..removeAt(i);
                    update(
                      unlock: UnlockConditionGroup(
                        operator: group.operator,
                        conditions: conditions,
                      ),
                    );
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          TextButton.icon(
            onPressed: () => update(
              unlock: UnlockConditionGroup(
                operator: group.operator,
                conditions: [
                  ...group.conditions,
                  const UnlockCondition(
                    type: UnlockConditionType.heatAtLeast,
                    value: 1,
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('条件追加'),
          ),
        ],
      ),
    );
  }

  Widget _singleMove(
    String title,
    MoveCategory category,
    String? selected,
    ValueChanged<String?> onChanged, {
    VoidCallback? onPick,
  }) => _EditorSection(
    title: title,
    child: Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: selected,
            decoration: const InputDecoration(labelText: '0〜1種類'),
            items: [
              const DropdownMenuItem(value: null, child: Text('未設定')),
              ...widget.repository.moves.values
                  .where((move) => move.category == category)
                  .map(
                    (move) => DropdownMenuItem(
                      value: move.id,
                      child: Text(move.name),
                    ),
                  ),
            ],
            onChanged: onChanged,
          ),
        ),
        if (onPick != null)
          IconButton(
            tooltip: '技一覧から選択',
            onPressed: onPick,
            icon: const Icon(Icons.playlist_add),
          ),
        IconButton(
          tooltip: selected == null ? '新規作成' : '編集',
          onPressed: selected == null
              ? () => _newMove(category)
              : () => _editMove(selected),
          icon: const Icon(Icons.edit),
        ),
      ],
    ),
  );

  Future<void> _pickSignatures() async {
    final result = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => TechniquePickerScreen(
          repository: widget.repository,
          allowedCategory: MoveCategory.normal,
          preselected: value.moveIds.toSet(),
        ),
      ),
    );
    if (result == null) return;
    var ids = result.toList();
    if (ids.length > 2) {
      ids = ids.take(2).toList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('固有技は各レベル最大2つです（先頭2つを設定）')),
        );
      }
    }
    update(moves: ids);
  }

  Future<void> _pickFinisher() async {
    final result = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => TechniquePickerScreen(
          repository: widget.repository,
          allowedCategory: MoveCategory.finisher,
          multi: false,
          preselected: value.finisherId == null ? {} : {value.finisherId!},
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    update(finisher: result.first);
  }

  Future<void> _newMove(MoveCategory category) async {
    final now = DateTime.now().microsecondsSinceEpoch;
    final move = MoveDefinition(
      id: 'move_$now',
      name: '',
      category: category,
      attribute: category == MoveCategory.counter
          ? MoveAttribute.counter
          : MoveAttribute.strike,
      power: 0,
      heat: 0,
      requiredCards: {for (final value in MoveAttribute.values) value: 0},
      discardAfterUse: {for (final value in MoveAttribute.values) value: 0},
      usageLimit: category == MoveCategory.finisher ? 1 : null,
      markUsedAfterUse: category == MoveCategory.finisher,
    );
    await _openMove(move);
  }

  Future<void> _editMove(String id) async {
    final move = widget.repository.moves[id];
    if (move != null) await _openMove(move);
  }

  Future<void> _openMove(MoveDefinition move) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MoveEditScreen(
        initial: move,
        onSaved: (saved) {
          widget.repository.moves[saved.id] = saved;
          switch (saved.category) {
            case MoveCategory.normal:
              final ids = value.moveIds.contains(saved.id)
                  ? value.moveIds
                  : [...value.moveIds.take(1), saved.id];
              update(moves: ids);
            case MoveCategory.counter:
              update(counter: saved.id);
            case MoveCategory.finisher:
              update(finisher: saved.id);
            case MoveCategory.basic:
              break; // 単体技はレベルへ登録しない
          }
        },
      ),
    ),
  );
}

class MoveEditScreen extends StatefulWidget {
  const MoveEditScreen({
    super.key,
    required this.initial,
    required this.onSaved,
  });
  final MoveDefinition initial;
  final ValueChanged<MoveDefinition> onSaved;
  @override
  State<MoveEditScreen> createState() => _MoveEditScreenState();
}

class _MoveEditScreenState extends State<MoveEditScreen> {
  late final id = TextEditingController(text: widget.initial.id);
  late final name = TextEditingController(text: widget.initial.name);
  late final power = TextEditingController(text: '${widget.initial.power}');
  late final heat = TextEditingController(text: '${widget.initial.heat}');
  late final successRate = TextEditingController(
    text: widget.initial.successRate?.toString() ?? '',
  );
  late final usageLimit = TextEditingController(
    text: widget.initial.usageLimit?.toString() ?? '',
  );
  late final success = TextEditingController(
    text: widget.initial.successEffects.join('\n'),
  );
  late final failure = TextEditingController(
    text: widget.initial.failureEffects.join('\n'),
  );
  late final description = TextEditingController(
    text: widget.initial.description,
  );
  late final image = TextEditingController(
    text: widget.initial.imagePath ?? '',
  );
  late MoveCategory category = widget.initial.category;
  late MoveAttribute attribute = widget.initial.attribute;
  late AdditionalCheckType check =
      widget.initial.additionalChecks.firstOrNull ?? AdditionalCheckType.none;
  late Map<MoveAttribute, int> required = Map.of(widget.initial.requiredCards);
  late Map<MoveAttribute, int> discard = Map.of(widget.initial.discardAfterUse);
  late bool markUsed = widget.initial.markUsedAfterUse;
  late bool canReset = widget.initial.canResetUsedState;
  // Ver.0.7.7: 新モデルの主要フィールドも編集可能に。
  late final speed = TextEditingController(text: '${widget.initial.speed}');
  late final pinPower =
      TextEditingController(text: '${widget.initial.pinPower}');
  late final submissionPower =
      TextEditingController(text: '${widget.initial.submissionPower}');
  late bool canPin = widget.initial.canPin;
  late bool canSubmit = widget.initial.canSubmit;
  late bool canKO = widget.initial.canKO;
  late final heatCost =
      TextEditingController(text: '${widget.initial.heatCost}');
  late int rank = widget.initial.rank.clamp(1, 5);
  late final deckPoints =
      TextEditingController(text: '${widget.initial.deckPoints}');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('技編集')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _text(id, '技ID'),
            _text(name, '技名', key: const Key('moveName')),
            DropdownButtonFormField(
              initialValue: category,
              decoration: const InputDecoration(labelText: '技分類'),
              items: MoveCategory.values
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(_categoryLabel(v)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => category = v!),
            ),
            DropdownButtonFormField(
              initialValue: attribute,
              decoration: const InputDecoration(labelText: '技属性'),
              items: MoveAttribute.values
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text('${moveAttributeLabel(v)}  ${v.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => attribute = v!),
            ),
            _text(power, '攻撃力（0以上）', number: true),
            _text(heat, 'HEAT増減（負数可）', signed: true),
            _text(speed, '速度（大きいほど速い）', number: true),
            _text(heatCost, 'HEATコスト（0=カテゴリから自動）', number: true),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Text('技ランク: '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: rank,
                    items: [
                      for (var r = 1; r <= 5; r++)
                        DropdownMenuItem(
                          value: r,
                          child: Text('${'★' * r}（★$r）'),
                        ),
                    ],
                    onChanged: (v) => setState(() => rank = v ?? 1),
                  ),
                  const Spacer(),
                  Expanded(
                    child: _text(deckPoints, 'デッキP（0=ランク値）', number: true),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(child: _text(pinPower, 'フォール強度', number: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: _text(submissionPower, 'ギブアップ強度', number: true)),
              ],
            ),
            SwitchListTile(
              value: canPin,
              dense: true,
              title: const Text('フォール可能（投げ技など）'),
              onChanged: (v) => setState(() => canPin = v),
            ),
            SwitchListTile(
              value: canSubmit,
              dense: true,
              title: const Text('ギブアップ可能（関節技など）'),
              onChanged: (v) => setState(() => canSubmit = v),
            ),
            SwitchListTile(
              value: canKO,
              dense: true,
              title: const Text('ダウンを奪える（打撃など）'),
              onChanged: (v) => setState(() => canKO = v),
            ),
            const _GuideText(),
            _cardCounts('必要技カード（＝固有技のセットコスト）', required,
                (map) => required = map),
            _text(successRate, '成功率（0〜100、未設定可）', number: true),
            DropdownButtonFormField(
              initialValue: check,
              decoration: const InputDecoration(labelText: '追加判定'),
              items: AdditionalCheckType.values
                  .map(
                    (v) =>
                        DropdownMenuItem(value: v, child: Text(_checkLabel(v))),
                  )
                  .toList(),
              onChanged: (v) => setState(() => check = v!),
            ),
            _text(success, '成功時効果（1行1件）', lines: 3),
            _text(failure, '失敗時効果（1行1件）', lines: 3),
            _text(usageLimit, '使用回数制限（未設定可）', number: true),
            _cardCounts('使用後に破棄するカード', discard, (map) => discard = map),
            SwitchListTile(
              value: markUsed,
              onChanged: (v) => setState(() => markUsed = v),
              title: const Text('使用後に使用済み'),
            ),
            SwitchListTile(
              value: canReset,
              onChanged: (v) => setState(() => canReset = v),
              title: const Text('使用済み状態を解除可能'),
            ),
            _text(description, '説明', lines: 3),
            _text(image, '画像パス'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('技を保存'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _text(
    TextEditingController controller,
    String label, {
    bool number = false,
    bool signed = false,
    int lines = 1,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: key,
      controller: controller,
      keyboardType: number || signed
          ? const TextInputType.numberWithOptions(signed: true)
          : TextInputType.text,
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _cardCounts(
    String title,
    Map<MoveAttribute, int> map,
    ValueChanged<Map<MoveAttribute, int>> onChange,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final attr in MoveAttribute.values)
            Row(
              children: [
                SizedBox(width: 42, child: Text(moveAttributeLabel(attr))),
                Expanded(
                  child: TextFormField(
                    initialValue: '${map[attr] ?? 0}',
                    keyboardType: TextInputType.number,
                    onChanged: (text) {
                      map[attr] = int.tryParse(text) ?? -1;
                      onChange(Map.of(map));
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  void _save() {
    // copyWith で UI 未対応フィールド（cannotCounter・consumesSetCards 等）を保持。
    final move = widget.initial.copyWith(
      id: id.text.trim(),
      name: name.text.trim(),
      category: category,
      attribute: attribute,
      power: int.tryParse(power.text) ?? -1,
      heat: int.tryParse(heat.text) ?? 0,
      requiredCards: required,
      additionalChecks: [check],
      successRate: successRate.text.isEmpty
          ? null
          : int.tryParse(successRate.text),
      usageLimit: usageLimit.text.isEmpty
          ? null
          : int.tryParse(usageLimit.text),
      successEffects: success.text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList(),
      failureEffects: failure.text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList(),
      discardAfterUse: discard,
      description: description.text,
      imagePath: image.text.isEmpty ? null : image.text,
      markUsedAfterUse: markUsed,
      canResetUsedState: canReset,
      speed: int.tryParse(speed.text) ?? widget.initial.speed,
      pinPower: int.tryParse(pinPower.text) ?? 0,
      submissionPower: int.tryParse(submissionPower.text) ?? 0,
      canPin: canPin,
      canSubmit: canSubmit,
      canKO: canKO,
      canAttemptPin: canPin,
      canAttemptSubmission: canSubmit,
      heatCost: int.tryParse(heatCost.text) ?? 0,
      rank: rank,
      deckPoints: int.tryParse(deckPoints.text) ?? 0,
    );
    final problems = <String>[
      if (move.id.isEmpty) '技IDは必須です',
      if (move.name.isEmpty) '技名は必須です',
      if (move.power < 0) '攻撃力は0以上です',
      if (move.successRate != null &&
          (move.successRate! < 0 || move.successRate! > 100))
        '成功率は0〜100です',
      if (move.usageLimit != null && move.usageLimit! < 1) '使用回数制限は1以上です',
      if (move.requiredCards.values.any((v) => v < 0) ||
          move.discardAfterUse.values.any((v) => v < 0))
        'カード枚数は0以上です',
      if (move.category == MoveCategory.finisher && move.usageLimit == null)
        'フィニッシャーには使用回数制限が必要です',
    ];
    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problems.join('\n'))));
      return;
    }
    widget.onSaved(move);
    Navigator.pop(context);
  }
}

class AbilityEditScreen extends StatefulWidget {
  const AbilityEditScreen({
    super.key,
    this.initial,
    required this.repository,
    required this.onSaved,
  });
  final AbilityDefinition? initial;
  final LocalWrestlerRepository repository;
  final ValueChanged<AbilityDefinition> onSaved;
  @override
  State<AbilityEditScreen> createState() => _AbilityEditScreenState();
}

class _AbilityEditScreenState extends State<AbilityEditScreen> {
  late final id = TextEditingController(
    text:
        widget.initial?.id ??
        'ability_${DateTime.now().microsecondsSinceEpoch}',
  );
  late final name = TextEditingController(text: widget.initial?.name ?? '');
  late final description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late final successRate = TextEditingController(
    text: widget.initial?.successRate?.toString() ?? '',
  );
  late final success = TextEditingController(
    text: widget.initial?.successEffects.join('\n') ?? '',
  );
  late final failure = TextEditingController(
    text: widget.initial?.failureEffects.join('\n') ?? '',
  );
  late final usage = TextEditingController(
    text: widget.initial?.usageLimit?.toString() ?? '',
  );
  late AbilityTiming timing = widget.initial?.timing ?? AbilityTiming.turnStart;
  late bool automatic = widget.initial?.isAutomatic ?? true;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('能力編集')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: id,
          decoration: const InputDecoration(labelText: '能力ID'),
        ),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: '能力名'),
        ),
        TextField(
          controller: description,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '説明'),
        ),
        DropdownButtonFormField(
          initialValue: timing,
          decoration: const InputDecoration(labelText: '発動タイミング'),
          items: AbilityTiming.values
              .map(
                (v) => DropdownMenuItem(value: v, child: Text(_timingLabel(v))),
              )
              .toList(),
          onChanged: (v) => setState(() => timing = v!),
        ),
        TextField(
          controller: successRate,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '成功率（未設定可）'),
        ),
        TextField(
          controller: success,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '成功時効果'),
        ),
        TextField(
          controller: failure,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '失敗時効果'),
        ),
        TextField(
          controller: usage,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '使用回数制限'),
        ),
        SwitchListTile(
          value: automatic,
          onChanged: (v) => setState(() => automatic = v),
          title: Text(automatic ? '自動発動' : '任意発動'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final ability = AbilityDefinition(
              id: id.text.trim(),
              name: name.text.trim(),
              description: description.text,
              timing: timing,
              successRate: successRate.text.isEmpty
                  ? null
                  : int.tryParse(successRate.text),
              usageLimit: usage.text.isEmpty ? null : int.tryParse(usage.text),
              successEffects: success.text
                  .split('\n')
                  .where((e) => e.isNotEmpty)
                  .toList(),
              failureEffects: failure.text
                  .split('\n')
                  .where((e) => e.isNotEmpty)
                  .toList(),
              isAutomatic: automatic,
            );
            widget.repository.abilities[ability.id] = ability;
            widget.onSaved(ability);
            Navigator.pop(context);
          },
          child: const Text('能力を保存'),
        ),
      ],
    ),
  );
}

class WrestlerCardPreview extends StatelessWidget {
  const WrestlerCardPreview({
    super.key,
    required this.wrestler,
    required this.repository,
  });
  final WrestlerDefinition wrestler;
  final LocalWrestlerRepository repository;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: wrestler.levels.length,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_parseColor(wrestler.themeColor), const Color(0xff120d19)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _editorGold, width: 2),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  child: Text(
                    wrestler.name.isEmpty ? '?' : wrestler.name[0],
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
                Text(
                  wrestler.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  wrestler.subtitle,
                  style: const TextStyle(color: _editorGold),
                ),
                Text(
                  '${wrestlerTypeLabel(wrestler.type)}  MAX HP ${wrestler.maxHp}',
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabs: [
              for (final level in wrestler.levels)
                Tab(text: 'LEVEL ${level.level}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final level in wrestler.levels)
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final attr in MoveAttribute.values)
                            Chip(
                              label: Text(
                                '${moveAttributeLabel(attr)} ${level.resistances[attr] ?? 0}',
                              ),
                            ),
                        ],
                      ),
                      const Divider(),
                      _previewLine(
                        '通常技',
                        level.moveIds
                            .map((id) => repository.moves[id]?.name ?? id)
                            .join(' / '),
                      ),
                      for (final id in level.moveIds)
                        if (repository.moves[id] case final move?)
                          _previewLine(
                            '  ${move.name}',
                            '必要 ${_cost(move.requiredCards)} / 攻撃 ${move.power} / HEAT ${move.heat >= 0 ? "+" : ""}${move.heat}',
                          ),
                      _previewLine(
                        '返し技',
                        repository.moves[level.counterMoveId]?.name ?? 'なし',
                      ),
                      _previewLine(
                        '固有能力',
                        repository.abilities[level.abilityId]?.name ?? 'なし',
                      ),
                      _previewLine(
                        'フィニッシャー',
                        repository.moves[level.finisherId]?.name ?? 'なし',
                      ),
                      _previewLine(
                        '解放条件',
                        _unlockSummary(level.unlockCondition),
                      ),
                      const Divider(),
                      Text(
                        level.flavorText,
                        style: const TextStyle(fontStyle: FontStyle.italic),
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

class _EditorSection extends StatelessWidget {
  const _EditorSection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _editorPink,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _GuideText extends StatelessWidget {
  const _GuideText();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(10),
      child: Text(
        '属性ガイド（固定ルールではありません）\n'
        '打: KO判定 / 関: ギブアップ / 投: フォール / 凶: 流血\n'
        '返: 対応成功判定 / 飛: 高HEAT・位置条件を想定',
        style: TextStyle(fontSize: 12, color: Colors.white70),
      ),
    ),
  );
}

Color _parseColor(String source) {
  final cleaned = source.replaceFirst('#', '');
  return Color(int.tryParse('FF$cleaned', radix: 16) ?? 0xffe91e63);
}

String _categoryLabel(MoveCategory value) => switch (value) {
  MoveCategory.normal => '通常技',
  MoveCategory.counter => '返し技',
  MoveCategory.finisher => 'フィニッシャー',
  MoveCategory.basic => '単体技',
};

String _checkLabel(AdditionalCheckType value) => switch (value) {
  AdditionalCheckType.none => 'なし',
  AdditionalCheckType.knockout => 'KO判定',
  AdditionalCheckType.submission => 'ギブアップ判定',
  AdditionalCheckType.pinfall => 'フォール判定',
  AdditionalCheckType.bleeding => '流血判定',
  AdditionalCheckType.counterSuccess => '返し成功判定',
  AdditionalCheckType.down => 'ダウン判定',
};

String _timingLabel(AbilityTiming value) => switch (value) {
  AbilityTiming.turnStart => '自分のターン開始時',
  AbilityTiming.cardSet => '技カードをセットしたとき',
  AbilityTiming.beforeMove => '技を使用する前',
  AbilityTiming.afterMoveSuccess => '技が成功した後',
  AbilityTiming.beforeDamage => 'ダメージを受ける前',
  AbilityTiming.afterDamage => 'ダメージを受けた後',
  AbilityTiming.checkStart => '各種判定開始時',
  AbilityTiming.kickOut => 'キックアウト時',
  AbilityTiming.levelChange => 'レベル変更時',
  AbilityTiming.turnEnd => 'ターン終了時',
};

String _unlockLabel(UnlockConditionType value) => switch (value) {
  UnlockConditionType.hpAtMost => '残りHPが指定値以下',
  UnlockConditionType.hpAtLeast => '残りHPが指定値以上',
  UnlockConditionType.heatAtLeast => 'HEATが指定値以上',
  UnlockConditionType.turnAtLeast => '経過ターンが指定値以上',
  UnlockConditionType.damageGivenAtLeast => '与えたダメージ回数',
  UnlockConditionType.damageReceivedAtLeast => '受けたダメージ回数',
  UnlockConditionType.attributeSuccessAtLeast => '特定属性の技成功',
  UnlockConditionType.kickOutCountAtLeast => 'キックアウト成功回数',
  UnlockConditionType.bleeding => '流血状態',
  UnlockConditionType.eventOccurred => '特定イベント発生済み',
  UnlockConditionType.previousLevelUnlocked => '前レベル解放済み',
  UnlockConditionType.specificLevelUsedAtLeast => '特定Levelの使用回数',
  UnlockConditionType.specificLevelMoveSuccessAtLeast => '特定Levelでの技成功回数',
  UnlockConditionType.currentLevelIs => '現在Levelが指定値',
  UnlockConditionType.levelChangeCountAtLeast => 'レベル変更回数',
  UnlockConditionType.pinKickOutCountAtLeast => 'キックアウト成功回数',
  UnlockConditionType.submissionEscapeCountAtLeast => 'ギブアップ回避回数',
  UnlockConditionType.finisherKickOutCountAtLeast => 'フィニッシャー返し回数',
};

bool _needsValue(UnlockConditionType type) => !{
  UnlockConditionType.bleeding,
  UnlockConditionType.previousLevelUnlocked,
}.contains(type);

String _cost(Map<MoveAttribute, int> values) => values.entries
    .where((entry) => entry.value > 0)
    .map((entry) => '${moveAttributeLabel(entry.key)}×${entry.value}')
    .join(' ');

String _unlockSummary(UnlockConditionGroup? group) {
  if (group == null) return 'なし';
  return group.conditions
      .map((item) {
        final value = item.value == null ? '' : ' ${item.value}';
        return '${_unlockLabel(item.type)}$value';
      })
      .join(group.operator == ConditionOperator.and ? ' AND ' : ' OR ');
}

Widget _previewLine(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Text('$label: ${value.isEmpty ? "なし" : value}'),
);
