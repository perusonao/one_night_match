import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'defaults.dart';
import 'models.dart';
import 'validator.dart';

abstract class WrestlerRepository {
  Future<List<WrestlerDefinition>> loadAll();
  Future<WrestlerDefinition?> loadById(String id);
  Future<void> save(WrestlerDefinition wrestler);
  Future<void> delete(String id);
  Future<void> resetToDefaults();
  Future<String> exportJson(String id);
  Future<WrestlerDefinition> importJson(String json);
}

class LocalWrestlerRepository implements WrestlerRepository {
  LocalWrestlerRepository({
    this.validator = const WrestlerValidator(),
    Map<String, MoveDefinition>? moves,
    Map<String, AbilityDefinition>? abilities,
  }) : moves = moves ?? {for (final item in defaultEditorMoves) item.id: item},
       abilities =
           abilities ??
           {for (final item in defaultEditorAbilities) item.id: item};

  static const storageKey = 'one_night_match_wrestler_editor_v03';
  static const moveStorageKey = 'one_night_match_move_editor_v03';
  static const abilityStorageKey = 'one_night_match_ability_editor_v03';
  final WrestlerValidator validator;
  final Map<String, MoveDefinition> moves;
  final Map<String, AbilityDefinition> abilities;
  bool _catalogLoaded = false;

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<List<WrestlerDefinition>> loadAll() async {
    await _loadCatalogs();
    final raw = (await _preferences).getString(storageKey);
    if (raw == null) return _loadDefaults();
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map(
            (item) =>
                WrestlerDefinition.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on Object {
      return List.of(defaultEditorWrestlers);
    }
  }

  Future<List<WrestlerDefinition>> _loadDefaults() async {
    try {
      final source = await rootBundle.loadString('assets/data/wrestlers.json');
      return (jsonDecode(source) as List)
          .map(
            (item) =>
                WrestlerDefinition.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on Object {
      return List.of(defaultEditorWrestlers);
    }
  }

  @override
  Future<WrestlerDefinition?> loadById(String id) async {
    final all = await loadAll();
    return all.cast<WrestlerDefinition?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
  }

  @override
  Future<void> save(WrestlerDefinition wrestler) async {
    final result = validator.validate(
      wrestler,
      moves: moves,
      abilities: abilities,
    );
    if (!result.isValid) throw FormatException(result.errors.join('\n'));
    final all = await loadAll();
    final index = all.indexWhere((item) => item.id == wrestler.id);
    if (index < 0) {
      all.add(wrestler);
    } else {
      all[index] = wrestler;
    }
    await _writeCatalogs();
    await _write(all);
  }

  @override
  Future<void> delete(String id) async {
    final all = await loadAll()
      ..removeWhere((item) => item.id == id);
    await _write(all);
  }

  @override
  Future<void> resetToDefaults() async {
    final preferences = await _preferences;
    await preferences.remove(storageKey);
    await preferences.remove(moveStorageKey);
    await preferences.remove(abilityStorageKey);
    moves
      ..clear()
      ..addEntries(defaultEditorMoves.map((item) => MapEntry(item.id, item)));
    abilities
      ..clear()
      ..addEntries(
        defaultEditorAbilities.map((item) => MapEntry(item.id, item)),
      );
    _catalogLoaded = true;
  }

  @override
  Future<String> exportJson(String id) async {
    final wrestler = await loadById(id);
    if (wrestler == null) throw StateError('レスラー「$id」が見つかりません');
    return wrestler.toPrettyJson();
  }

  @override
  Future<WrestlerDefinition> importJson(String source) async {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) throw const FormatException('JSONオブジェクトが必要です');
      final wrestler = WrestlerDefinition.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final result = validator.validate(
        wrestler,
        moves: moves,
        abilities: abilities,
      );
      if (!result.isValid) throw FormatException(result.errors.join('\n'));
      return wrestler;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('JSONを読み込めません: $error');
    }
  }

  Future<WrestlerDefinition> duplicate(String id) async {
    final source = await loadById(id);
    if (source == null) throw StateError('複製元が見つかりません');
    final now = DateTime.now().toUtc();
    var newId = '${source.id}_copy';
    final all = await loadAll();
    var suffix = 2;
    while (all.any((item) => item.id == newId)) {
      newId = '${source.id}_copy$suffix';
      suffix++;
    }
    final copy = source.copyWith(
      id: newId,
      name: '${source.name} コピー',
      createdAt: now,
      updatedAt: now,
    );
    await save(copy);
    return copy;
  }

  Future<void> _write(List<WrestlerDefinition> wrestlers) async {
    await (await _preferences).setString(
      storageKey,
      jsonEncode(wrestlers.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _loadCatalogs() async {
    if (_catalogLoaded) return;
    final preferences = await _preferences;
    try {
      final moveSource = preferences.getString(moveStorageKey);
      if (moveSource != null) {
        final decoded = jsonDecode(moveSource) as List;
        moves
          ..clear()
          ..addEntries(
            decoded.map((item) {
              final move = MoveDefinition.fromJson(
                Map<String, dynamic>.from(item),
              );
              return MapEntry(move.id, move);
            }),
          );
      }
      final abilitySource = preferences.getString(abilityStorageKey);
      if (abilitySource != null) {
        final decoded = jsonDecode(abilitySource) as List;
        abilities
          ..clear()
          ..addEntries(
            decoded.map((item) {
              final ability = AbilityDefinition.fromJson(
                Map<String, dynamic>.from(item),
              );
              return MapEntry(ability.id, ability);
            }),
          );
      }
    } on Object {
      moves
        ..clear()
        ..addEntries(defaultEditorMoves.map((item) => MapEntry(item.id, item)));
      abilities
        ..clear()
        ..addEntries(
          defaultEditorAbilities.map((item) => MapEntry(item.id, item)),
        );
    }
    _catalogLoaded = true;
  }

  Future<void> _writeCatalogs() async {
    final preferences = await _preferences;
    await preferences.setString(
      moveStorageKey,
      jsonEncode(moves.values.map((item) => item.toJson()).toList()),
    );
    await preferences.setString(
      abilityStorageKey,
      jsonEncode(abilities.values.map((item) => item.toJson()).toList()),
    );
  }
}
