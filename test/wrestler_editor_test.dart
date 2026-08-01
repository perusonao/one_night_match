import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/editor_screens.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:one_night_match/src/wrestler_editor/repository.dart';
import 'package:one_night_match/src/wrestler_editor/validator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final moves = {for (final item in defaultEditorMoves) item.id: item};
  final abilities = {for (final item in defaultEditorAbilities) item.id: item};
  const validator = WrestlerValidator();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('WrestlerDefinition JSON往復と未知フィールドを許容', () {
    final source = defaultEditorWrestlers.first.toJson()
      ..['futureField'] = 'ignored';
    final restored = WrestlerDefinition.fromJson(
      jsonDecode(jsonEncode(source)) as Map<String, dynamic>,
    );
    expect(restored.toJson(), defaultEditorWrestlers.first.toJson());
  });

  test('MoveDefinition JSON往復', () {
    final source = defaultEditorMoves.first;
    expect(MoveDefinition.fromJson(source.toJson()).toJson(), source.toJson());
  });

  test('AbilityDefinition JSON往復', () {
    final source = defaultEditorAbilities.first;
    expect(
      AbilityDefinition.fromJson(source.toJson()).toJson(),
      source.toJson(),
    );
  });

  test('必須フィールド欠落は明確なエラー', () {
    expect(
      () => WrestlerDefinition.fromJson(const {'id': 'x'}),
      throwsA(isA<FormatException>()),
    );
  });

  group('バリデーション', () {
    WrestlerValidationResult check(WrestlerDefinition wrestler) =>
        validator.validate(wrestler, moves: moves, abilities: abilities);

    test('正常なレスラー定義は保存可能', () {
      expect(check(defaultEditorWrestlers.first).isValid, isTrue);
    });

    test('Level 1解放条件、レベル重複、通常技3件、負数耐性を検出', () {
      final base = defaultEditorWrestlers.first;
      final level = base.levels.first;
      final broken = WrestlerLevelDefinition(
        level: 1,
        displayName: level.displayName,
        unlockCondition: const UnlockConditionGroup(
          operator: ConditionOperator.and,
          conditions: [
            UnlockCondition(type: UnlockConditionType.heatAtLeast, value: 1),
          ],
        ),
        resistances: {...level.resistances, MoveAttribute.strike: -1},
        moveIds: const ['dropkick', 'arm_drag', 'running_knee'],
      );
      final result = check(
        base.copyWith(levels: [broken, broken, ...base.levels.skip(1)]),
      );
      expect(result.errors.any((e) => e.contains('解放条件')), isTrue);
      expect(result.errors.any((e) => e.contains('重複')), isTrue);
      expect(result.errors.any((e) => e.contains('最大2種類')), isTrue);
      expect(result.errors.any((e) => e.contains('耐性')), isTrue);
    });

    test('成功率101と存在しない技IDを検出', () {
      final invalidMove = MoveDefinition(
        id: 'invalid',
        name: 'invalid',
        category: MoveCategory.normal,
        attribute: MoveAttribute.strike,
        power: 1,
        heat: 0,
        requiredCards: const {},
        discardAfterUse: const {},
        successRate: 101,
      );
      final customMoves = {...moves, invalidMove.id: invalidMove};
      final wrestler = defaultEditorWrestlers.first.copyWith(
        levels: [
          WrestlerLevelDefinition(
            level: 1,
            displayName: 'Level 1',
            resistances: const {},
            moveIds: const ['missing'],
          ),
        ],
      );
      final result = validator.validate(
        wrestler,
        moves: customMoves,
        abilities: abilities,
      );
      expect(result.errors.any((e) => e.contains('成功率')), isTrue);
      expect(result.errors.any((e) => e.contains('存在しない技ID')), isTrue);
    });

    test('フィニッシャーの回数制限未設定を検出', () {
      final finisher = MoveDefinition(
        id: 'bad_finisher',
        name: 'bad',
        category: MoveCategory.finisher,
        attribute: MoveAttribute.throwMove,
        power: 10,
        heat: 1,
        requiredCards: const {},
        discardAfterUse: const {},
      );
      final customMoves = {...moves, finisher.id: finisher};
      final base = defaultEditorWrestlers.first;
      final last = base.levels.last;
      final changed = WrestlerLevelDefinition(
        level: last.level,
        displayName: last.displayName,
        unlockCondition: last.unlockCondition,
        resistances: last.resistances,
        moveIds: last.moveIds,
        finisherId: finisher.id,
      );
      final result = validator.validate(
        base.copyWith(levels: [...base.levels.take(2), changed]),
        moves: customMoves,
        abilities: abilities,
      );
      expect(result.errors.any((e) => e.contains('使用回数制限')), isTrue);
    });
  });

  test('Repositoryで保存・更新・削除・複製・初期化・不正JSON拒否', () async {
    final repository = LocalWrestlerRepository();
    final base = defaultEditorWrestlers.first.copyWith(id: 'test_wrestler');
    await repository.save(base);
    expect((await repository.loadById(base.id))?.name, base.name);
    await repository.save(base.copyWith(name: '更新済み'));
    expect((await repository.loadById(base.id))?.name, '更新済み');
    repository.moves['custom_move'] = MoveDefinition(
      id: 'custom_move',
      name: 'カスタム技',
      category: MoveCategory.normal,
      attribute: MoveAttribute.aerial,
      power: 10,
      heat: 2,
      requiredCards: const {},
      discardAfterUse: const {},
    );
    await repository.save(base.copyWith(name: 'カタログ保存'));
    final restarted = LocalWrestlerRepository();
    await restarted.loadAll();
    expect(restarted.moves['custom_move']?.name, 'カスタム技');
    final duplicated = await repository.duplicate(base.id);
    expect(duplicated.id, isNot(base.id));
    await repository.delete(base.id);
    expect(await repository.loadById(base.id), isNull);
    expect(() => repository.importJson('{}'), throwsA(isA<FormatException>()));
    await repository.resetToDefaults();
    expect(await repository.loadAll(), hasLength(4));
  });

  testWidgets('一覧から新規作成画面を開き入力エラーを表示できる', (tester) async {
    SharedPreferences.setMockInitialValues({
      LocalWrestlerRepository.storageKey: jsonEncode(
        defaultEditorWrestlers.map((item) => item.toJson()).toList(),
      ),
    });
    final repository = LocalWrestlerRepository();
    await tester.pumpWidget(
      MaterialApp(home: WrestlerEditorListScreen(repository: repository)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('火神アカリ'), findsOneWidget);
    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wrestlerName')), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveWrestler')));
    await tester.pump();
    expect(find.text('保存できません'), findsOneWidget);
  });
}
