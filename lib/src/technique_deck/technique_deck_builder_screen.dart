import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../level_match/report_export.dart';
import '../wrestler_editor/models.dart'
    show MoveAttribute, WrestlerDefinition, moveAttributeLabel;
import '../wrestler_editor/repository.dart';
import 'technique_deck_deck.dart';
import 'technique_deck_defaults.dart';
import 'technique_deck_file_io.dart';
import 'technique_deck_generator.dart';
import 'technique_deck_models.dart';
import 'technique_deck_storage.dart';
import 'technique_deck_validation.dart';

/// Technique Deck Builder（テクニックデッキ）: Technique Deck Rules Phase 2
/// のデッキプレビュー・検証・JSON入出力・暫定自動生成を行う管理画面。
///
/// 新ルールの試合エンジンには接続しない（Phase 3以降）。現行のclassic／
/// energyモード、Deck Simulator、レスラーエディタの挙動には一切影響しない。
class TechniqueDeckBuilderScreen extends StatefulWidget {
  const TechniqueDeckBuilderScreen({
    super.key,
    this.wrestlerRepository,
    this.deckRepository,
    this.catalog,
  });

  final LocalWrestlerRepository? wrestlerRepository;
  final TechniqueDeckRepository? deckRepository;

  /// テスト用にカタログを差し替え可能にする。省略時は
  /// [buildProvisionalTechniqueDeckCatalog] の暫定サンプルを使う。
  final TechniqueDeckCardCatalog? catalog;

  @override
  State<TechniqueDeckBuilderScreen> createState() =>
      _TechniqueDeckBuilderScreenState();
}

const _gold = Color(0xffffc857);
const _red = Color(0xffff5c5c);
const _green = Color(0xff5cd68b);
const _bg = Color(0xff211527);

const _sameNameLimitDescription =
    '通常技3・固有技1・フィニッシャー1（合計3・同名不可）・技エネルギー無制限・'
    'エスケープ2・リバーサル2・通常キックアウト2・特殊キックアウト1（合計3）・'
    'ロープブレイク2・アクション3';

class _CategoryInfo {
  const _CategoryInfo(this.type, this.label, {this.kickOutCategory});
  final TechniqueDeckCardType type;
  final String label;
  final KickOutCardCategory? kickOutCategory;
}

const _categories = [
  _CategoryInfo(TechniqueDeckCardType.energy, '技エネルギー'),
  _CategoryInfo(TechniqueDeckCardType.technique, '通常技'),
  _CategoryInfo(TechniqueDeckCardType.technique, '固有技'),
  _CategoryInfo(TechniqueDeckCardType.technique, 'フィニッシャー'),
  _CategoryInfo(TechniqueDeckCardType.escape, 'エスケープ'),
  _CategoryInfo(TechniqueDeckCardType.reversal, 'リバーサル'),
  _CategoryInfo(
    TechniqueDeckCardType.kickOut,
    '通常キックアウト',
    kickOutCategory: KickOutCardCategory.normal,
  ),
  _CategoryInfo(
    TechniqueDeckCardType.kickOut,
    'フィニッシャーエスケープ',
    kickOutCategory: KickOutCardCategory.finisherEscape,
  ),
  _CategoryInfo(TechniqueDeckCardType.ropeBreak, 'ロープブレイク'),
  _CategoryInfo(TechniqueDeckCardType.action, 'アクション'),
];

class _TechniqueDeckBuilderScreenState
    extends State<TechniqueDeckBuilderScreen> {
  late final LocalWrestlerRepository wrestlerRepository =
      widget.wrestlerRepository ?? LocalWrestlerRepository();
  late final TechniqueDeckRepository deckRepository =
      widget.deckRepository ?? LocalTechniqueDeckRepository();
  late final TechniqueDeckCardCatalog catalog =
      widget.catalog ?? buildProvisionalTechniqueDeckCatalog();
  final TechniqueDeckValidator validator = const TechniqueDeckValidator();

  List<WrestlerDefinition>? wrestlers;
  WrestlerDefinition? selectedWrestler;

  String deckId = '';
  final TextEditingController nameController = TextEditingController(
    text: 'テクニックデッキ',
  );

  /// cardId → 枚数。デッキの実体。
  final Map<String, int> cardCounts = {};
  bool dirty = false;
  List<String> generationNotes = [];

  @override
  void initState() {
    super.initState();
    wrestlerRepository.loadAll().then((items) {
      if (!mounted) return;
      setState(() {
        wrestlers = items;
        selectedWrestler = items.isNotEmpty ? items.first : null;
      });
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  // ============================================================
  // デッキの導出・検証
  // ============================================================

  TechniqueDeckCardType _typeOf(String cardId) {
    if (catalog.findTechniqueById(cardId) != null) {
      return TechniqueDeckCardType.technique;
    }
    if (catalog.findEnergyById(cardId) != null) {
      return TechniqueDeckCardType.energy;
    }
    return catalog.findDefenseCardById(cardId)?.type ??
        TechniqueDeckCardType.technique;
  }

  TechniqueDeckDefinition get _currentDeck {
    final builder = TechniqueDeckBuilder(
      wrestlerId: selectedWrestler?.id ?? '',
      id: deckId,
      name: nameController.text,
    );
    cardCounts.forEach((cardId, count) {
      if (count > 0) builder.addCard(cardId, _typeOf(cardId), count: count);
    });
    return builder.build();
  }

  TechniqueDeckBuildResult get _validation =>
      validator.validate(_currentDeck, catalog);

  int get _totalCount =>
      cardCounts.values.fold<int>(0, (sum, count) => sum + count);

  bool _isUsableForSelectedWrestler(TechniqueDeckTechniqueCard card) {
    if (card.category == TechniqueCardCategory.normal) return true;
    final wrestler = selectedWrestler;
    if (wrestler == null) return false;
    return card.allowedWrestlerIds.contains(wrestler.id);
  }

  int _sameNameLimitFor(_CategoryInfo info, TechniqueCardCategory? techniqueCategory) {
    switch (info.type) {
      case TechniqueDeckCardType.technique:
        return switch (techniqueCategory) {
          TechniqueCardCategory.normal => 3,
          TechniqueCardCategory.signature => 1,
          TechniqueCardCategory.finisher => 1,
          null => 3,
        };
      case TechniqueDeckCardType.energy:
        return 0;
      case TechniqueDeckCardType.escape:
      case TechniqueDeckCardType.reversal:
      case TechniqueDeckCardType.ropeBreak:
        return 2;
      case TechniqueDeckCardType.kickOut:
        return info.kickOutCategory == KickOutCardCategory.finisherEscape
            ? 1
            : 2;
      case TechniqueDeckCardType.action:
        return 3;
    }
  }

  bool _canIncrement(_CategoryInfo info, String cardId) {
    final technique = catalog.findTechniqueById(cardId);
    if (technique != null && !_isUsableForSelectedWrestler(technique)) {
      return false;
    }
    final limit = _sameNameLimitFor(info, technique?.category);
    final current = cardCounts[cardId] ?? 0;
    if (limit > 0 && current >= limit) return false;
    if (technique?.category == TechniqueCardCategory.finisher) {
      final totalFinishers = cardCounts.entries
          .where(
            (e) => catalog.findTechniqueById(e.key)?.category ==
                TechniqueCardCategory.finisher,
          )
          .fold<int>(0, (sum, e) => sum + e.value);
      if (totalFinishers >= validator.maxFinisherCount) return false;
    }
    if (info.type == TechniqueDeckCardType.kickOut &&
        info.kickOutCategory == KickOutCardCategory.finisherEscape) {
      final totalSpecial = cardCounts.entries
          .where(
            (e) =>
                catalog.findDefenseCardById(e.key)?.kickOutCategory ==
                KickOutCardCategory.finisherEscape,
          )
          .fold<int>(0, (sum, e) => sum + e.value);
      if (totalSpecial >= validator.maxSpecialKickOutCount) return false;
    }
    return true;
  }

  void _increment(_CategoryInfo info, String cardId) {
    if (!_canIncrement(info, cardId)) return;
    setState(() {
      cardCounts[cardId] = (cardCounts[cardId] ?? 0) + 1;
      dirty = true;
    });
  }

  void _decrement(String cardId) {
    final current = cardCounts[cardId] ?? 0;
    if (current <= 0) return;
    setState(() {
      if (current <= 1) {
        cardCounts.remove(cardId);
      } else {
        cardCounts[cardId] = current - 1;
      }
      dirty = true;
    });
  }

  Future<bool> _confirmIfDirty(String message) async {
    if (!dirty) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未保存の変更があります'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('続行'),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  // ============================================================
  // レスラー選択
  // ============================================================

  Future<void> _onWrestlerChanged(WrestlerDefinition? wrestler) async {
    if (wrestler == null || wrestler == selectedWrestler) return;
    final ok = await _confirmIfDirty(
      'レスラーを変更すると、現在使用できているカードが使用不能になる場合があります。続行しますか？',
    );
    if (!ok) return;
    setState(() {
      selectedWrestler = wrestler;
      dirty = true;
    });
  }

  // ============================================================
  // 自動生成
  // ============================================================

  Future<void> _runAutoGenerate() async {
    final wrestler = selectedWrestler;
    if (wrestler == null) return;
    final ok = await _confirmIfDirty('自動生成すると、現在のデッキ内容は上書きされます。続行しますか？');
    if (!ok) return;

    final result = TechniqueDeckAutoGenerator(
      config: TechniqueDeckGenerationConfig(
        seed: DateTime.now().millisecondsSinceEpoch,
      ),
      validator: validator,
    ).generate(
      catalog: catalog,
      wrestlerId: wrestler.id,
      deckId: deckId.isEmpty
          ? '${wrestler.id}_${DateTime.now().millisecondsSinceEpoch}'
          : deckId,
      deckName: nameController.text,
    );

    setState(() {
      deckId = result.deck.id;
      cardCounts
        ..clear()
        ..addEntries(
          result.deck.entries
              .fold<Map<String, int>>({}, (map, entry) {
                map[entry.cardId] = (map[entry.cardId] ?? 0) + 1;
                return map;
              })
              .entries,
        );
      generationNotes = result.notes;
      dirty = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success ? '暫定デッキを生成しました（${wrestler.name}用）。' : '生成しましたが検証エラーが残っています。',
        ),
      ),
    );
  }

  // ============================================================
  // 保存
  // ============================================================

  Future<void> _saveCurrentDeck() async {
    final wrestler = selectedWrestler;
    if (wrestler == null) return;
    final now = DateTime.now().toUtc();
    if (deckId.isEmpty) {
      deckId = '${wrestler.id}_${now.millisecondsSinceEpoch}';
    }
    final existing = (await deckRepository.loadAll())
        .where((r) => r.deckId == deckId)
        .toList();
    final record = TechniqueDeckSaveRecord(
      deckId: deckId,
      name: nameController.text,
      wrestlerId: wrestler.id,
      createdAt: existing.isNotEmpty ? existing.first.createdAt : now,
      updatedAt: now,
      entries: _currentDeck.entries,
      generatorVersion:
          generationNotes.isNotEmpty ? techniqueDeckGeneratorVersion : null,
      notes: generationNotes.join('\n'),
    );
    await deckRepository.save(record);
    if (!mounted) return;
    setState(() => dirty = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('デッキを保存しました。')));
  }

  Future<void> _showSavedDecks() async {
    final records = await deckRepository.loadAll();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存済みテクニックデッキ'),
        content: SizedBox(
          width: 480,
          child: records.isEmpty
              ? const Text('保存されているデッキはありません。')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final record in records)
                        ListTile(
                          title: Text(record.name.isEmpty ? '(無題)' : record.name),
                          subtitle: Text(
                            '${record.wrestlerId} ・ ${record.entries.length}枚 ・ '
                            '更新: ${record.updatedAt.toLocal()}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '読込',
                                icon: const Icon(Icons.file_open),
                                onPressed: () async {
                                  final proceed = await _confirmIfDirty(
                                    'このデッキを読み込むと、現在の内容は上書きされます。続行しますか？',
                                  );
                                  if (!proceed) return;
                                  _loadRecord(record);
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                },
                              ),
                              IconButton(
                                tooltip: '削除',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: dialogContext,
                                    builder: (c) => AlertDialog(
                                      title: const Text('削除確認'),
                                      content: Text('「${record.name}」を削除しますか？'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c, false),
                                          child: const Text('キャンセル'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          child: const Text('削除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await deckRepository.delete(record.deckId);
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext);
                                      _showSavedDecks();
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _loadRecord(TechniqueDeckSaveRecord record) {
    setState(() {
      deckId = record.deckId;
      nameController.text = record.name;
      final match = wrestlers?.where((w) => w.id == record.wrestlerId);
      if (match != null && match.isNotEmpty) selectedWrestler = match.first;
      cardCounts
        ..clear()
        ..addEntries(
          record.entries
              .fold<Map<String, int>>({}, (map, entry) {
                map[entry.cardId] = (map[entry.cardId] ?? 0) + 1;
                return map;
              })
              .entries,
        );
      generationNotes = record.notes.isEmpty ? [] : record.notes.split('\n');
      dirty = false;
    });
  }

  // ============================================================
  // JSON入出力
  // ============================================================

  String get _prettyDeckJson =>
      const JsonEncoder.withIndent('  ').convert(_currentDeck.toJson());

  Future<void> _openJsonDialog() async {
    final pasteController = TextEditingController();
    TechniqueDeckDefinition? preview;
    String? previewError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('テクニックデッキ JSON'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('現在のデッキ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SelectableText(
                    _prettyDeckJson,
                    style: const TextStyle(fontSize: 11),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('コピー'),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _prettyDeckJson),
                          );
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('ファイル出力'),
                        onPressed: () async {
                          final name =
                              'technique_deck_${deckId.isEmpty ? "untitled" : deckId}.json';
                          final ok = await downloadTextFile(
                            name,
                            _prettyDeckJson,
                          );
                          if (!ok) {
                            await Clipboard.setData(
                              ClipboardData(text: _prettyDeckJson),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text('JSON読込', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: pasteController,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'JSONを貼り付け',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('ファイルから読込'),
                        onPressed: () async {
                          final content = await pickAndReadTextFile();
                          if (content != null) {
                            pasteController.text = content;
                          } else if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text('この環境ではファイル選択に未対応です。貼り付けをご利用ください。'),
                              ),
                            );
                          }
                        },
                      ),
                      TextButton(
                        onPressed: () {
                          try {
                            final decoded = jsonDecode(pasteController.text);
                            final deck = TechniqueDeckDefinition.fromJson(
                              Map<String, dynamic>.from(decoded as Map),
                            );
                            setDialogState(() {
                              preview = deck;
                              previewError = null;
                            });
                          } on Object catch (e) {
                            setDialogState(() {
                              preview = null;
                              previewError = 'JSONの読み込みに失敗しました: $e';
                            });
                          }
                        },
                        child: const Text('検証'),
                      ),
                    ],
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 8),
                    Text('デッキ名: ${preview!.name}'),
                    Text('レスラーID: ${preview!.wrestlerId}'),
                    Text('枚数: ${preview!.entries.length}'),
                    Builder(
                      builder: (context) {
                        final result = validator.validate(preview!, catalog);
                        return Text(
                          result.isValid
                              ? 'バリデーション: OK'
                              : 'バリデーション: エラー${result.errors.length}件・警告${result.warnings.length}件',
                          style: TextStyle(
                            color: result.isValid ? _green : _red,
                          ),
                        );
                      },
                    ),
                  ],
                  if (previewError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        previewError!,
                        style: const TextStyle(color: _red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (preview != null) ...[
              TextButton(
                onPressed: () async {
                  final proceed = await _confirmIfDirty(
                    '現在編集中のデッキに未保存の変更があります。JSONの内容で上書きしますか？',
                  );
                  if (!proceed) return;
                  _applyDeckDefinition(preview!);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('現在デッキへ上書き'),
              ),
              FilledButton(
                onPressed: () {
                  final now = DateTime.now().toUtc();
                  _applyDeckDefinition(
                    preview!.copyWith(
                      id: '${preview!.id}_${now.millisecondsSinceEpoch}',
                      name: '${preview!.name} コピー',
                    ),
                  );
                  Navigator.pop(dialogContext);
                },
                child: const Text('別名複製'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    );
    pasteController.dispose();
  }

  void _applyDeckDefinition(TechniqueDeckDefinition deck) {
    setState(() {
      deckId = deck.id;
      nameController.text = deck.name;
      final match = wrestlers?.where((w) => w.id == deck.wrestlerId);
      if (match != null && match.isNotEmpty) selectedWrestler = match.first;
      cardCounts
        ..clear()
        ..addEntries(
          deck.entries
              .fold<Map<String, int>>({}, (map, entry) {
                map[entry.cardId] = (map[entry.cardId] ?? 0) + 1;
                return map;
              })
              .entries,
        );
      generationNotes = [];
      dirty = true;
    });
  }

  // ============================================================
  // build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final loading = wrestlers == null;
    final validation = loading ? null : _validation;
    return Scaffold(
      appBar: AppBar(
        title: const Text('テクニックデッキ'),
        actions: [
          IconButton(
            tooltip: '保存済みデッキ',
            icon: const Icon(Icons.folder),
            onPressed: loading ? null : _showSavedDecks,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _devBanner(),
                const SizedBox(height: 12),
                _header(validation!),
                const SizedBox(height: 12),
                if (generationNotes.isNotEmpty) _generationNotesCard(),
                if (generationNotes.isNotEmpty) const SizedBox(height: 12),
                for (final info in _categories) ...[
                  _categorySection(info),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                _diagnosisSection(validation),
                const SizedBox(height: 8),
                _attributeBalanceSection(),
                const SizedBox(height: 8),
                _usableUnusableSection(),
                const SizedBox(height: 24),
              ],
            ),
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
            '開発中：Technique Deck Rules Phase 2',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('このデッキはまだ試合では使用されません', style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );

  Widget _generationNotesCard() => Card(
    color: _bg,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '自動生成の根拠',
            style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
          ),
          const SizedBox(height: 4),
          for (final note in generationNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('・$note', style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    ),
  );

  Widget _header(TechniqueDeckBuildResult validation) {
    final total = _totalCount;
    final totalColor = total == 30 ? _green : (total > 30 ? _red : _gold);
    return Card(
      color: _bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<WrestlerDefinition>(
              initialValue: selectedWrestler,
              decoration: const InputDecoration(labelText: 'レスラー選択'),
              items: [
                for (final w in wrestlers!)
                  DropdownMenuItem(value: w, child: Text(w.name)),
              ],
              onChanged: (w) => _onWrestlerChanged(w),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'デッキ名'),
              onChanged: (_) => setState(() => dirty = true),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '合計枚数 $total / 30',
                  style: TextStyle(fontWeight: FontWeight.bold, color: totalColor),
                ),
                Chip(
                  label: Text('エラー ${validation.errors.length}件'),
                  backgroundColor: validation.errors.isEmpty
                      ? null
                      : _red.withValues(alpha: 0.25),
                ),
                Chip(
                  label: Text('警告 ${validation.warnings.length}件'),
                  backgroundColor: validation.warnings.isEmpty
                      ? null
                      : _gold.withValues(alpha: 0.25),
                ),
                Text(
                  dirty ? '未保存の変更があります' : '保存済み',
                  style: TextStyle(
                    color: dirty ? _gold : _green,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.fact_check),
                  label: const Text('検証'),
                ),
                FilledButton.tonalIcon(
                  onPressed: selectedWrestler == null ? null : _runAutoGenerate,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('自動生成'),
                ),
                OutlinedButton.icon(
                  onPressed: _openJsonDialog,
                  icon: const Icon(Icons.data_object),
                  label: const Text('JSON'),
                ),
                FilledButton.icon(
                  onPressed: selectedWrestler == null ? null : _saveCurrentDeck,
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // カード種別セクション
  // ============================================================

  List<Object> _candidatesFor(_CategoryInfo info) {
    switch (info.type) {
      case TechniqueDeckCardType.technique:
        final category = info.label == '通常技'
            ? TechniqueCardCategory.normal
            : info.label == '固有技'
            ? TechniqueCardCategory.signature
            : TechniqueCardCategory.finisher;
        return catalog.techniques.where((c) => c.category == category).toList();
      case TechniqueDeckCardType.energy:
        return catalog.energies;
      case TechniqueDeckCardType.kickOut:
        return catalog.defenseCards
            .where(
              (c) =>
                  c.type == TechniqueDeckCardType.kickOut &&
                  c.kickOutCategory == info.kickOutCategory,
            )
            .toList();
      case TechniqueDeckCardType.escape:
      case TechniqueDeckCardType.reversal:
      case TechniqueDeckCardType.ropeBreak:
      case TechniqueDeckCardType.action:
        return catalog.defenseCards.where((c) => c.type == info.type).toList();
    }
  }

  Widget _categorySection(_CategoryInfo info) {
    final candidates = _candidatesFor(info);
    final categoryCount = candidates
        .map((c) => cardCounts[_idOf(c)] ?? 0)
        .fold<int>(0, (sum, c) => sum + c);
    final suffix = info.label == 'フィニッシャー'
        ? '$categoryCount/${validator.maxFinisherCount}枚'
        : info.label == 'フィニッシャーエスケープ'
        ? '$categoryCount/${validator.maxSpecialKickOutCount}枚'
        : '$categoryCount枚';
    return Card(
      color: _bg,
      child: ExpansionTile(
        title: Text('${info.label} $suffix'),
        children: candidates.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('カタログに候補がありません。', style: TextStyle(fontSize: 12)),
                ),
              ]
            : [for (final card in candidates) _cardRow(info, card)],
      ),
    );
  }

  String _idOf(Object card) => switch (card) {
    TechniqueDeckTechniqueCard c => c.id,
    TechniqueEnergyCard c => c.id,
    TechniqueDefenseCard c => c.id,
    _ => '',
  };

  String _nameOf(Object card) => switch (card) {
    TechniqueDeckTechniqueCard c => c.name,
    TechniqueEnergyCard c => c.name,
    TechniqueDefenseCard c => c.name,
    _ => '',
  };

  List<String> _detailLines(Object card) {
    if (card is TechniqueDeckTechniqueCard) {
      final attack = card.attackEnergyCost.entries
          .where((e) => e.value > 0)
          .map((e) => '${moveAttributeLabel(e.key)}${e.value}')
          .join('・');
      final reversal = card.reversalEnergyCost.entries
          .where((e) => e.value > 0)
          .map((e) => '${moveAttributeLabel(e.key)}${e.value}')
          .join('・');
      return [
        'ID: ${card.id}',
        '属性: ${moveAttributeLabel(card.attribute)} ・ 必要レベル: ${card.minimumLevel}',
        '攻撃コスト: ${attack.isEmpty ? "なし" : attack} ・ 返技コスト: ${reversal.isEmpty ? "なし" : reversal}',
        '威力: ${card.power} ・ HEAT: ${card.heatDelta}',
        '対象状態: ${card.targetState.name} ・ ダウン効果: ${card.causesDown ? "あり" : "なし"}',
        'フォール: ${card.hasPinEffect ? "あり" : "なし"} ・ ギブアップ: ${card.hasSubmissionEffect ? "あり" : "なし"} ・ '
            'フィニッシャー効果: ${card.hasFinisherEffect ? "あり" : "なし"}',
        '使用可能レスラー: ${card.allowedWrestlerIds.isEmpty ? "全レスラー" : card.allowedWrestlerIds.join("、")}',
      ];
    }
    if (card is TechniqueEnergyCard) {
      final count = cardCounts[card.id] ?? 0;
      final total = _totalCount;
      final ratio = total == 0 ? 0.0 : count / total;
      return [
        'ID: ${card.id}',
        '属性: ${moveAttributeLabel(card.attribute)}',
        '枚数: $count ・ デッキ内比率: ${(ratio * 100).toStringAsFixed(1)}%',
      ];
    }
    if (card is TechniqueDefenseCard) {
      return [
        'ID: ${card.id}',
        '種別: ${card.type.name}'
            '${card.kickOutCategory != null ? " (${card.kickOutCategory!.name})" : ""}',
        '条件: ${card.requirements.isEmpty ? "なし" : card.requirements.toString()}',
        '効果概要: ${card.effects.isEmpty ? "未設定" : card.effects.toString()}',
        card.description,
      ];
    }
    return const [];
  }

  Widget _cardRow(_CategoryInfo info, Object card) {
    final id = _idOf(card);
    final name = _nameOf(card);
    final count = cardCounts[id] ?? 0;
    final technique = card is TechniqueDeckTechniqueCard ? card : null;
    final usable = technique == null || _isUsableForSelectedWrestler(technique);
    final validation = _validation;
    final issuesForCard = validation.issues.where((i) => i.cardId == id).toList();
    final hasError = issuesForCard.any((i) => i.severity == ValidationSeverity.error);
    final hasWarning = issuesForCard.any(
      (i) => i.severity == ValidationSeverity.warning,
    );

    return ExpansionTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(color: usable ? null : Colors.grey),
            ),
          ),
          if (hasError)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.error, color: _red, size: 18),
            ),
          if (!hasError && hasWarning)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.warning_amber, color: _gold, size: 18),
            ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: count > 0 ? () => _decrement(id) : null,
          ),
          Text('$count'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _canIncrement(info, id) ? () => _increment(info, id) : null,
          ),
        ],
      ),
      children: [
        if (!usable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '使用不可：${selectedWrestler?.name ?? "選択中のレスラー"}専用ではありません',
              style: const TextStyle(color: _red, fontSize: 12),
            ),
          ),
        for (final line in _detailLines(card))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(line, style: const TextStyle(fontSize: 12)),
          ),
        for (final issue in issuesForCard)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              '${issue.severity == ValidationSeverity.error ? "エラー" : "警告"}: ${issue.message}',
              style: TextStyle(
                fontSize: 12,
                color: issue.severity == ValidationSeverity.error ? _red : _gold,
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ============================================================
  // デッキ診断
  // ============================================================

  String? _suggestionFor(String code) => switch (code) {
    'deckSizeMismatch' => '技・エネルギー・防御カードを追加または削除して30枚に調整してください。',
    'unknownCardId' => 'このカードはカタログに存在しません。削除してください。',
    'duplicateInstanceId' => '内部エラーです。デッキを読み込み直してください。',
    'sameNameLimitExceeded' => '同名カードの枚数を上限まで減らしてください（$_sameNameLimitDescription）。',
    'finisherCountExceeded' => 'フィニッシャーを${validator.maxFinisherCount}枚以下に減らしてください。',
    'duplicateFinisherName' => '同名のフィニッシャーを1枚に減らすか、別のフィニッシャーに差し替えてください。',
    'wrestlerMismatch' => 'このカードを削除するか、選択中のレスラーに変更してください。',
    'emptyAllowedWrestlerIds' => 'カード側にallowedWrestlerIdsの設定が必要です（カタログの修正が必要）。',
    'cardTypeMismatch' => '内部エラーです。デッキを読み込み直してください。',
    'noEnergyCards' => '技エネルギーカードを1枚以上追加してください。',
    'noFinisherCards' => 'フィニッシャーを1枚以上追加することを検討してください。',
    'noSpecialKickOutCards' => 'フィニッシャーエスケープカードを1枚以上追加することを検討してください。',
    'missingAttackEnergyCoverage' =>
      '対応する属性の技エネルギーカードを1枚以上追加してください。または、その属性を必要とする技を削除してください。',
    'missingReversalEnergyCoverage' =>
      '対応する属性の技エネルギーカードを1枚以上追加してください。または、その技を削除してください。',
    'tooFewTechniqueCards' => '通常技・固有技・フィニッシャーを追加することを検討してください。',
    'extremeEnergyRatio' => '技エネルギーカードの枚数を調整することを検討してください。',
    'allTechniquesUnusableLevel' => 'minimumLevelが1の技を1枚以上採用することを検討してください。',
    _ => null,
  };

  Widget _diagnosisSection(TechniqueDeckBuildResult validation) => Card(
    color: _bg,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'デッキ診断',
            style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
          ),
          const SizedBox(height: 8),
          if (validation.isValid && validation.warnings.isEmpty)
            const Text('問題は見つかりませんでした。', style: TextStyle(color: _green)),
          for (final issue in validation.errors) _issueTile(issue, isError: true),
          for (final issue in validation.warnings) _issueTile(issue, isError: false),
        ],
      ),
    ),
  );

  Widget _issueTile(TechniqueDeckValidationIssue issue, {required bool isError}) {
    final suggestion = _suggestionFor(issue.code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error : Icons.warning_amber,
            color: isError ? _red : _gold,
            size: 18,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isError ? "エラー" : "警告"}：${issue.message}',
                  style: TextStyle(color: isError ? _red : _gold, fontSize: 13),
                ),
                if (suggestion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      suggestion,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 属性バランス
  // ============================================================

  Widget _attributeBalanceSection() {
    final deck = _currentDeck;
    final energyByAttribute = <MoveAttribute, int>{};
    for (final entry in deck.entries) {
      final energy = catalog.findEnergyById(entry.cardId);
      if (energy != null) {
        energyByAttribute[energy.attribute] =
            (energyByAttribute[energy.attribute] ?? 0) + 1;
      }
    }
    final attackDemand = <MoveAttribute, int>{};
    final reversalDemand = <MoveAttribute, int>{};
    final requiringCount = <MoveAttribute, int>{};
    final maxSingle = <MoveAttribute, int>{};
    for (final entry in deck.entries) {
      final technique = catalog.findTechniqueById(entry.cardId);
      if (technique == null) continue;
      final attrs = <MoveAttribute>{};
      for (final e in technique.attackEnergyCost.entries) {
        if (e.value <= 0) continue;
        attackDemand[e.key] = (attackDemand[e.key] ?? 0) + e.value;
        maxSingle[e.key] = (maxSingle[e.key] ?? 0) < e.value
            ? e.value
            : maxSingle[e.key]!;
        attrs.add(e.key);
      }
      for (final e in technique.reversalEnergyCost.entries) {
        if (e.value <= 0) continue;
        reversalDemand[e.key] = (reversalDemand[e.key] ?? 0) + e.value;
        maxSingle[e.key] = (maxSingle[e.key] ?? 0) < e.value
            ? e.value
            : maxSingle[e.key]!;
        attrs.add(e.key);
      }
      for (final attr in attrs) {
        requiringCount[attr] = (requiringCount[attr] ?? 0) + 1;
      }
    }

    return Card(
      color: _bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '属性バランス（参考値。エラーにはなりません）',
              style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
            ),
            const SizedBox(height: 8),
            for (final attribute in MoveAttribute.values)
              _attributeRow(
                attribute,
                energyByAttribute[attribute] ?? 0,
                attackDemand[attribute] ?? 0,
                reversalDemand[attribute] ?? 0,
                requiringCount[attribute] ?? 0,
                maxSingle[attribute] ?? 0,
              ),
          ],
        ),
      ),
    );
  }

  Widget _attributeRow(
    MoveAttribute attribute,
    int energyCount,
    int attackTotal,
    int reversalTotal,
    int requiringCount,
    int maxSingleCost,
  ) {
    String? hint;
    Color hintColor = Colors.white70;
    if (requiringCount > 0 && energyCount < maxSingleCost) {
      hint = '不足の可能性あり';
      hintColor = _red;
    } else if (requiringCount > 0 && energyCount > (attackTotal + reversalTotal) * 2) {
      hint = '過剰の可能性あり';
      hintColor = _gold;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${moveAttributeLabel(attribute)} エネルギー$energyCount枚',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${moveAttributeLabel(attribute)}を必要とする技: $requiringCount枚 ・ '
            '最大必要コスト: ${moveAttributeLabel(attribute)}$maxSingleCost'
            '${hint != null ? " ・ $hint" : ""}',
            style: TextStyle(fontSize: 12, color: hintColor),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 使用可能・使用不能カード
  // ============================================================

  Widget _usableUnusableSection() {
    final wrestler = selectedWrestler;
    final usable = <String>[];
    final unusable = <(String, String)>[];
    for (final card in catalog.techniques) {
      if (card.category == TechniqueCardCategory.normal) {
        usable.add(card.name);
        continue;
      }
      if (wrestler != null && card.allowedWrestlerIds.contains(wrestler.id)) {
        usable.add(card.name);
      } else {
        unusable.add((card.name, '使用不可：${wrestler?.name ?? "レスラー未選択"}専用ではありません'));
      }
    }
    for (final card in catalog.energies) {
      usable.add(card.name);
    }
    for (final card in catalog.defenseCards) {
      usable.add(card.name);
    }

    return Card(
      color: _bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '使用可能・使用不能カード',
              style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
            ),
            const SizedBox(height: 8),
            Text('使用可能 (${usable.length})', style: const TextStyle(color: _green)),
            Text(usable.join('、'), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text('使用不能 (${unusable.length})', style: const TextStyle(color: _red)),
            for (final (name, reason) in unusable)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$name\n$reason',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
