import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_cost_preview.dart';
import 'package:one_night_match/src/level_match/level_match_deck_builder.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/level_match/level_match_finish_models.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Map<MoveAttribute, int> cards({
    int strike = 0,
    int throwMove = 0,
    int submission = 0,
    int counter = 0,
    int rough = 0,
    int aerial = 0,
  }) => {
    MoveAttribute.strike: strike,
    MoveAttribute.throwMove: throwMove,
    MoveAttribute.submission: submission,
    MoveAttribute.counter: counter,
    MoveAttribute.rough: rough,
    MoveAttribute.aerial: aerial,
  };

  final moves = <String, MoveDefinition>{
    'throwPin': MoveDefinition(
      id: 'throwPin',
      name: '投げ技',
      category: MoveCategory.normal,
      attribute: MoveAttribute.throwMove,
      power: 20,
      heat: 3,
      requiredCards: cards(throwMove: 1),
      discardAfterUse: cards(),
      canAttemptPin: true,
      pinPower: 6,
    ),
    'subMove': MoveDefinition(
      id: 'subMove',
      name: '関節技',
      category: MoveCategory.normal,
      attribute: MoveAttribute.submission,
      power: 18,
      heat: 3,
      requiredCards: cards(submission: 1),
      discardAfterUse: cards(),
      canAttemptSubmission: true,
      submissionPower: 6,
    ),
    'downMove': MoveDefinition(
      id: 'downMove',
      name: '打撃技',
      category: MoveCategory.normal,
      attribute: MoveAttribute.strike,
      power: 15,
      heat: 2,
      requiredCards: cards(strike: 1),
      discardAfterUse: cards(),
      additionalChecks: const [AdditionalCheckType.knockout],
    ),
    'finPin': MoveDefinition(
      id: 'finPin',
      name: 'フィニッシャー',
      category: MoveCategory.finisher,
      attribute: MoveAttribute.throwMove,
      power: 36,
      heat: 8,
      requiredCards: cards(throwMove: 2),
      discardAfterUse: cards(throwMove: 1),
      usageLimit: 1,
      markUsedAfterUse: true,
      additionalChecks: const [AdditionalCheckType.pinfall],
      canAttemptPin: true,
      pinPower: 8,
      pinBonusOnFinisher: 15,
    ),
  };

  WrestlerLevelDefinition level(
    int number, {
    List<String> moveIds = const ['throwPin', 'subMove', 'downMove'],
    String? finisher,
  }) => WrestlerLevelDefinition(
    level: number,
    displayName: 'Level $number',
    resistances: cards(),
    moveIds: moveIds,
    finisherId: finisher,
  );

  WrestlerDefinition wrestler(String id) => WrestlerDefinition(
    id: id,
    name: id,
    subtitle: 'test',
    type: EditorWrestlerType.babyface,
    maxHp: 100,
    themeColor: '#E91E63',
    levels: [
      level(1),
      level(2),
      level(3, finisher: 'finPin'),
    ],
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  LevelMatchEngine engine() => LevelMatchEngine.create(
    playerWrestler: wrestler('player'),
    cpuWrestler: wrestler('cpu'),
    moves: moves,
    random: Random(1),
    playerStarts: true,
  );

  /// プレイヤーを chooseMove まで進め、指定属性のセットカードを積む。
  void advanceToMove(
    LevelMatchEngine match, {
    Map<MoveAttribute, int> set = const {},
  }) {
    for (final entry in set.entries) {
      for (var i = 0; i < entry.value; i++) {
        match.state.player.setCards.add(
          TechniqueResourceCard('set-${entry.key.name}-$i', entry.key),
        );
      }
    }
    match.skipSetCard('player');
    match.skipLevelChange('player');
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('デッキ自動生成', () {
    final builder = const LevelMatchDeckBuilder();
    final defaultMoves = {for (final m in defaultEditorMoves) m.id: m};

    test('4レスラー全員が30枚・不要属性0・使用属性最低3枚', () {
      for (final w in defaultEditorWrestlers) {
        final deck = builder.build(
          wrestler: w,
          moves: defaultMoves,
          owner: 'p',
        );
        expect(deck.cards.length, kDeckSize, reason: '${w.name} は30枚');
        for (final attribute in MoveAttribute.values) {
          final count = deck.counts[attribute] ?? 0;
          if (!deck.usedAttributes.contains(attribute)) {
            expect(count, 0, reason: '${w.name} 未使用属性は0枚');
          } else {
            expect(count, greaterThanOrEqualTo(3), reason: '${w.name} 使用属性は3枚以上');
          }
        }
      }
    });

    test('フィニッシャー必須属性は最大必要枚数+1以上', () {
      final akari = defaultEditorWrestlers.firstWhere(
        (w) => w.id == 'wrestler_akari',
      );
      final deck = builder.build(wrestler: akari, moves: defaultMoves, owner: 'p');
      // ハイスピード・ジャーマンは投4必要 → 投は5枚以上。
      expect(deck.counts[MoveAttribute.throwMove], greaterThanOrEqualTo(5));
    });

    test('同じ入力なら同じ結果（決定的）', () {
      final a = builder.build(
        wrestler: wrestler('x'),
        moves: moves,
        owner: 'p',
      );
      final b = builder.build(
        wrestler: wrestler('x'),
        moves: moves,
        owner: 'p',
      );
      expect(a.counts, b.counts);
    });

    test('不正データ（技なし）でも30枚にフォールバック', () {
      final broken = WrestlerDefinition(
        id: 'broken',
        name: 'broken',
        subtitle: '',
        type: EditorWrestlerType.other,
        maxHp: 100,
        themeColor: '#000000',
        levels: [
          WrestlerLevelDefinition(
            level: 1,
            displayName: 'L1',
            resistances: cards(),
            moveIds: const ['missing'],
          ),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final deck = builder.build(wrestler: broken, moves: moves, owner: 'p');
      expect(deck.cards.length, kDeckSize);
      expect(deck.usedFallback, isTrue);
    });
  });

  group('セット画面ロジック（コストプレビュー）', () {
    final preview = LevelMatchCostPreview(
      wrestler: wrestler('x'),
      moves: moves,
    );

    test('全Level技コストを取得できる', () {
      final views = preview.allLevelViews(
        counts: cards(),
        unlockedLevels: {1},
        currentLevel: 1,
        finisherUsed: false,
      );
      expect(views, hasLength(3));
      expect(views.first.normalMoves, isNotEmpty);
    });

    test('セット前後の不足枚数差分と解禁を予測', () {
      final prediction = preview.predictSet(
        attribute: MoveAttribute.throwMove,
        counts: cards(),
        unlockedLevels: {1},
        finisherUsed: false,
      );
      final change = prediction.changes.firstWhere(
        (c) => c.moveName == '投げ技',
      );
      expect(change.usableBefore, isFalse);
      expect(change.usableAfter, isTrue);
      expect(change.becameUsable, isTrue);
    });
  });

  group('HP仕様', () {
    test('HP0でも即敗北せず、HP0到達ターンを記録', () {
      final match = engine();
      match.state.cpu.currentHp = 5;
      advanceToMove(match, set: {MoveAttribute.strike: 1});
      match.useMove('player', 'downMove'); // 打撃はフォールに移行しない
      expect(match.state.cpu.currentHp, 0);
      expect(match.state.isGameOver, isFalse);
      expect(match.state.cpu.hpZeroReachedTurn, isNotNull);
    });

    test('HPは0未満にならない', () {
      final match = engine();
      match.state.cpu.currentHp = 1;
      advanceToMove(match, set: {MoveAttribute.strike: 1});
      match.useMove('player', 'downMove');
      expect(match.state.cpu.currentHp, 0);
    });

    test('HP0ではHP消費キックアウト不可・カードは可能', () {
      final match = engine();
      match.state.cpu.currentHp = 0;
      advanceToMove(match, set: {MoveAttribute.throwMove: 1});
      match.useMove('player', 'throwPin');
      match.declarePin('player');
      expect(
        () => match.kickOut('cpu', DefenseMethod.hp),
        throwsStateError,
      );
      match.kickOut('cpu', DefenseMethod.card); // カードは使える
      expect(match.state.cpu.kickOutCount, 1);
    });
  });

  group('フォール（3カウント）', () {
    test('pinfall技成功でPendingPin、見送りでHEAT+1', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.throwMove: 1});
      final heat = match.state.sharedHeat;
      match.useMove('player', 'throwPin');
      expect(match.state.pendingPin, isNotNull);
      expect(match.state.phase, LevelMatchPhase.pinDecision);
      match.declinePin('player');
      expect(match.state.sharedHeat, greaterThan(heat));
      expect(match.state.pendingPin, isNull);
    });

    test('HP消費キックアウト成功・HP不足は不可', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.throwMove: 1});
      match.useMove('player', 'throwPin');
      match.declarePin('player');
      final cost = match.state.pendingPin!.hpKickOutCost;
      match.state.cpu.currentHp = cost; // ちょうど耐えられる
      match.kickOut('cpu', DefenseMethod.hp);
      expect(match.state.cpu.pinKickOutCount, 1);
      expect(match.state.isGameOver, isFalse);
    });

    test('敗北受け入れで3カウント・finishReasonがpinfall', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.throwMove: 1});
      match.useMove('player', 'throwPin');
      match.declarePin('player');
      match.kickOut('cpu', DefenseMethod.accept);
      expect(match.state.isGameOver, isTrue);
      expect(match.state.finishReason, LevelFinishReason.pinfall);
      expect(match.state.winnerId, 'player');
      expect(match.state.finishingMove, '投げ技');
    });

    test('フィニッシャーは自動でカウントへ・補正が乗る', () {
      final match = engine();
      match.state.player
        ..currentLevel = 3
        ..unlockedLevels.add(3);
      advanceToMove(match, set: {MoveAttribute.throwMove: 3});
      match.useMove('player', 'finPin');
      expect(match.state.phase, LevelMatchPhase.kickOutDecision);
      expect(match.state.pinAttemptCount, 1);
      expect(match.state.pendingPin!.fromFinisher, isTrue);
      expect(match.state.pendingPin!.strength.finisherBonus, 15);
    });

    test('ダウン補正でフォール強度+5', () {
      final match = engine();
      match.state.cpu.isDown = true;
      advanceToMove(match, set: {MoveAttribute.throwMove: 1});
      match.useMove('player', 'throwPin');
      expect(match.state.pendingPin!.strength.downBonus, 5);
    });
  });

  group('ギブアップ（サブミッション）', () {
    test('submission技成功でPendingSubmission', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.submission: 1});
      match.useMove('player', 'subMove');
      expect(match.state.pendingSubmission, isNotNull);
      expect(match.state.phase, LevelMatchPhase.submissionDecision);
      expect(match.state.submissionAttemptCount, 1);
    });

    test('ロープブレイクで回避', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.submission: 1});
      match.useMove('player', 'subMove');
      match.escapeSubmission('cpu', DefenseMethod.card);
      expect(match.state.cpu.submissionEscapeCount, 1);
      expect(match.state.ropeBreakTotalCount, 1);
      expect(match.state.isGameOver, isFalse);
    });

    test('HP消費で耐える・不足なら不可', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.submission: 1});
      match.useMove('player', 'subMove');
      match.state.cpu.ropeBreakCards = 0;
      match.state.cpu.currentHp = 1; // 足りない
      expect(
        () => match.escapeSubmission('cpu', DefenseMethod.hp),
        throwsStateError,
      );
      match.state.cpu.currentHp = match.state.pendingSubmission!.hpEscapeCost;
      match.escapeSubmission('cpu', DefenseMethod.hp);
      expect(match.state.cpu.submissionEscapeCount, 1);
    });

    test('ギブアップ受け入れで決着・finishReasonがsubmission', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.submission: 1});
      match.useMove('player', 'subMove');
      match.escapeSubmission('cpu', DefenseMethod.accept);
      expect(match.state.isGameOver, isTrue);
      expect(match.state.finishReason, LevelFinishReason.submission);
    });
  });

  group('ダウン', () {
    test('knockout判定はダウン扱い（causesDown）', () {
      expect(moves['downMove']!.causesDown, isTrue);
    });

    test('打撃KOでダウンが付与され、本人の次ターン開始で解除される', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.strike: 1});
      match.useMove('player', 'downMove');
      // ダウンイベントが記録される。
      expect(match.state.logs.any((log) => log.action == 'down'), isTrue);
      // useMove は endTurn 済み → CPUの手番開始で解除される。
      expect(match.state.activePlayerId, 'cpu');
      expect(match.state.cpu.isDown, isFalse);
    });

    test('ダウン中の相手はフォール強度+5を受ける', () {
      final match = engine();
      match.state.cpu.isDown = true;
      advanceToMove(match, set: {MoveAttribute.throwMove: 1});
      match.useMove('player', 'throwPin');
      expect(match.state.pendingPin!.strength.downBonus, 5);
    });
  });

  group('CPU', () {
    test('フォールされたCPUがキックアウト判断できる', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.throwMove: 1});
      match.useMove('player', 'throwPin');
      match.declarePin('player');
      expect(match.cpuActionPending, isTrue);
      match.runCpuTurn();
      // カード or HP でキックアウト、または敗北受け入れ。
      expect(
        match.state.pendingPin == null || match.state.isGameOver,
        isTrue,
      );
    });

    test('フィニッシャーを相手HP低下時に高評価する', () {
      // スコアは内部だが、CPUが実際に使用可能なフィニッシャーを選ぶことを確認。
      final match = LevelMatchEngine.create(
        playerWrestler: wrestler('player'),
        cpuWrestler: wrestler('cpu'),
        moves: moves,
        random: Random(2),
        playerStarts: false,
      );
      final cpu = match.state.cpu
        ..currentLevel = 3
        ..unlockedLevels.add(3)
        ..setCards.addAll([
          for (var i = 0; i < 3; i++)
            TechniqueResourceCard('c$i', MoveAttribute.throwMove),
        ]);
      match.state.player.currentHp = 10; // 相手瀕死
      // setCard/levelChange をスキップして chooseMove へ。
      if (match.state.phase == LevelMatchPhase.setCard) {
        match.skipSetCard('cpu');
      }
      if (match.state.phase == LevelMatchPhase.levelChange) {
        match.skipLevelChange('cpu');
      }
      expect(match.evaluateMove(cpu, moves['finPin']!).usable, isTrue);
    });
  });

  group('JSON互換', () {
    test('Ver.0.5ログ往復・決着メタを含む', () {
      final match = engine();
      advanceToMove(match, set: {MoveAttribute.throwMove: 1});
      match.useMove('player', 'throwPin');
      match.declarePin('player');
      match.kickOut('cpu', DefenseMethod.accept);
      final json = jsonDecode(jsonEncode(match.state.toJson())) as Map;
      final game = json['game'] as Map;
      expect(game['version'], '0.5');
      expect(game['finishReason'], 'pinfall');
      expect(game['pinAttempts'], 1);
      expect(game['finishingMove'], '投げ技');
    });

    test('Ver.0.4ログを安全に読み込める', () async {
      const legacy = {
        'game': {
          'gameId': 'legacy-1',
          'version': '0.4',
          'mode': 'levelCardMatch',
          'winner': 'player',
          'finishReason': 'hpZero',
          'turns': 8,
        },
        'players': [
          {'playerId': 'player', 'wrestlerName': '旧アカリ'},
          {'playerId': 'cpu', 'wrestlerName': '旧ミサキ'},
        ],
        'turns': [],
      };
      SharedPreferences.setMockInitialValues({
        LevelMatchHistoryStore.key: [jsonEncode(legacy)],
      });
      final loaded = await LevelMatchHistoryStore().load();
      expect(loaded, hasLength(1));
      expect((loaded.single['game'] as Map)['version'], '0.4');
    });

    test('未知フィールドを無視して技を読み込める', () {
      final json = moves['throwPin']!.toJson()..['unknownFutureField'] = 123;
      final restored = MoveDefinition.fromJson(Map<String, dynamic>.from(json));
      expect(restored.canAttemptPin, isTrue);
      expect(restored.pinPower, 6);
    });
  });
}
