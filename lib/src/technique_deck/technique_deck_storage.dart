import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'technique_deck_deck.dart';

/// Technique Deck Rules Phase 2後半: デッキの永続化。
///
/// 既存の保存キー（例: `lib/src/wrestler_editor/repository.dart` の
/// `one_night_match_wrestler_editor_v04`）とは衝突しない専用の名前空間
/// （`technique_deck_definitions_v1`）を使う。既存のclassic/energyモードの
/// 保存データには一切触れない。

/// 現在の自動生成アルゴリズムのバージョン識別子（暫定）。
const techniqueDeckGeneratorVersion = 'phase2-tentative-v1';

const Object _unset = Object();

/// 保存されるTechnique Deck 1件分（[TechniqueDeckDefinition] に保存用の
/// メタ情報を加えたもの）。
class TechniqueDeckSaveRecord {
  const TechniqueDeckSaveRecord({
    required this.deckId,
    required this.name,
    required this.wrestlerId,
    required this.createdAt,
    required this.updatedAt,
    this.entries = const [],
    this.schemaVersion = 1,
    this.generatorVersion,
    this.notes = '',
  });

  final String deckId;
  final String name;
  final String wrestlerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TechniqueDeckEntry> entries;

  /// 将来のマイグレーションに備えた必須のスキーマバージョン。
  final int schemaVersion;

  /// 自動生成で作られた場合のアルゴリズムバージョン（手動編集時はnull）。
  final String? generatorVersion;
  final String notes;

  TechniqueDeckDefinition toDeckDefinition() => TechniqueDeckDefinition(
    id: deckId,
    wrestlerId: wrestlerId,
    name: name,
    entries: entries,
  );

  factory TechniqueDeckSaveRecord.fromDeckDefinition(
    TechniqueDeckDefinition deck, {
    required DateTime createdAt,
    required DateTime updatedAt,
    String? generatorVersion,
    String notes = '',
  }) => TechniqueDeckSaveRecord(
    deckId: deck.id,
    name: deck.name,
    wrestlerId: deck.wrestlerId,
    createdAt: createdAt,
    updatedAt: updatedAt,
    entries: deck.entries,
    generatorVersion: generatorVersion,
    notes: notes,
  );

  TechniqueDeckSaveRecord copyWith({
    String? deckId,
    String? name,
    String? wrestlerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<TechniqueDeckEntry>? entries,
    int? schemaVersion,
    Object? generatorVersion = _unset,
    String? notes,
  }) => TechniqueDeckSaveRecord(
    deckId: deckId ?? this.deckId,
    name: name ?? this.name,
    wrestlerId: wrestlerId ?? this.wrestlerId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    entries: entries ?? this.entries,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    generatorVersion: identical(generatorVersion, _unset)
        ? this.generatorVersion
        : generatorVersion as String?,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'deckId': deckId,
    'name': name,
    'wrestlerId': wrestlerId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'schemaVersion': schemaVersion,
    if (generatorVersion != null) 'generatorVersion': generatorVersion,
    'notes': notes,
  };

  factory TechniqueDeckSaveRecord.fromJson(Map<String, dynamic> json) {
    final deckId = json['deckId'];
    final name = json['name'];
    final wrestlerId = json['wrestlerId'];
    final generatorVersion = json['generatorVersion'];
    final notes = json['notes'];
    return TechniqueDeckSaveRecord(
      deckId: deckId is String && deckId.isNotEmpty ? deckId : '',
      name: name is String ? name : '',
      wrestlerId: wrestlerId is String ? wrestlerId : '',
      createdAt: _dateTimeOrNow(json['createdAt']),
      updatedAt: _dateTimeOrNow(json['updatedAt']),
      entries: (json['entries'] as List? ?? const [])
          .map(
            (item) =>
                TechniqueDeckEntry.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      schemaVersion: json['schemaVersion'] is num
          ? (json['schemaVersion'] as num).toInt()
          : 1,
      generatorVersion: generatorVersion is String ? generatorVersion : null,
      notes: notes is String ? notes : '',
    );
  }

  @override
  String toString() =>
      'TechniqueDeckSaveRecord(deckId: $deckId, name: $name, wrestlerId: $wrestlerId, cardCount: ${entries.length})';
}

DateTime _dateTimeOrNow(Object? raw) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
  }
  return DateTime.now();
}

/// Technique Deck保存領域のインターフェース（テスト時に差し替え可能にする）。
abstract class TechniqueDeckRepository {
  Future<List<TechniqueDeckSaveRecord>> loadAll();
  Future<void> save(TechniqueDeckSaveRecord record);
  Future<void> delete(String deckId);
}

/// SharedPreferencesを使った実装。既存の保存キーとは衝突しない専用の
/// 名前空間（[storageKey]）を使う。
class LocalTechniqueDeckRepository implements TechniqueDeckRepository {
  static const storageKey = 'technique_deck_definitions_v1';

  Future<SharedPreferences> get _preferences =>
      SharedPreferences.getInstance();

  @override
  Future<List<TechniqueDeckSaveRecord>> loadAll() async {
    try {
      final raw = (await _preferences).getString(storageKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map(
            (item) => TechniqueDeckSaveRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on Object {
      return [];
    }
  }

  @override
  Future<void> save(TechniqueDeckSaveRecord record) async {
    final all = await loadAll();
    final index = all.indexWhere((r) => r.deckId == record.deckId);
    if (index >= 0) {
      all[index] = record;
    } else {
      all.add(record);
    }
    await _persist(all);
  }

  @override
  Future<void> delete(String deckId) async {
    final all = await loadAll();
    all.removeWhere((r) => r.deckId == deckId);
    await _persist(all);
  }

  Future<void> _persist(List<TechniqueDeckSaveRecord> records) async {
    final prefs = await _preferences;
    await prefs.setString(
      storageKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }
}
