/// Phase 10B Codexレビュー指摘（P2）対応の統合テスト。
///
/// GitHub Codexレビュー指摘: Production Catalogに、WrestlerとそのWrestler用
/// Deckの組み合わせを検証する仕組みがなく、`CombatV1Engine.start(wrestlerA:
/// jackWrestler, deckA: buildMisakiDeck(...), ...)`のような取り違えを
/// 防止できなかった（`lib/src/combat_v1/combat_v1_production_catalog.dart`）。
///
/// 対応方針:
/// - `validateDeck`（`combat_v1_deck_validation.dart`）に任意の`wrestlerId`
///   引数を追加し、非nullかつ`deck.wrestlerId`と不一致なら
///   `wrestlerMismatch`エラーとして拒否する（省略時は既存挙動を維持）。
/// - `CombatV1Engine.start`が、それぞれ`wrestlerA.id`/`wrestlerB.id`を
///   `validateDeck`へ渡すよう変更し、直接`Engine.start`を呼ぶ経路でも
///   取り違えを確実に拒否する。
/// - Misaki/Jack等の固有IDはハードコードしない（Core Engine側は
///   `CombatV1Wrestler.id`と`CombatV1DeckDefinition.wrestlerId`という
///   汎用フィールド同士の文字列比較のみを行う）。
/// - `ownerId`（physical instance namespace専用、Phase 10A）とは独立した
///   概念のまま維持する。
///
/// 本ファイルはCore Engine（`combat_v1_engine.dart`）とProduction Data
/// （Misaki／Jack）を横断して検証する統合テストであり、責務が異なる既存の
/// `combat_v1_deck_validation_test.dart`（`validateDeck`単体）・
/// `combat_v1_production_misaki_test.dart`・
/// `combat_v1_production_jack_test.dart`（各レスラー単体のProduction Data）
/// とは別ファイルとして新設した。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_catalog_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decks.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_wrestler_catalog.dart';

const CombatV1RulesConfig rules = CombatV1RulesConfig();

/// 両playerの全カードゾーン＋pendingが所有する攻撃カードのinstanceIdを
/// すべて集めたリスト（`combat_v1_production_jack_test.dart`の
/// `_allInstanceIds`と同じ方針）。
List<String> _allInstanceIds(CombatV1MatchState state) {
  final pending = state.pendingAttack;
  return [
    ...state.playerA.hand.map((e) => e.instanceId),
    ...state.playerA.drawPile.map((e) => e.instanceId),
    ...state.playerA.discardPile.map((e) => e.instanceId),
    ...state.playerB.hand.map((e) => e.instanceId),
    ...state.playerB.drawPile.map((e) => e.instanceId),
    ...state.playerB.discardPile.map((e) => e.instanceId),
    if (pending != null) pending.attackCardInstance.instanceId,
  ];
}

void main() {
  group('A/B. 正常系: 同じレスラーのProduction Deckを渡すとEngine.startが成功する', () {
    test('A. Misaki wrestler + Misaki Production Deck → valid', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-a'),
        wrestlerB: misakiWrestler,
        deckB: buildMisakiDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      expect(state.playerA.wrestlerId, 'misaki');
      expect(state.playerB.wrestlerId, 'misaki');
      expect(state.phase, CombatV1MatchPhase.discard);
    });

    test('B. Jack wrestler + Jack Production Deck → valid', () {
      final state = CombatV1Engine.start(
        wrestlerA: jackWrestler,
        deckA: buildJackDeck(ownerId: 'player-a'),
        wrestlerB: jackWrestler,
        deckB: buildJackDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      expect(state.playerA.wrestlerId, 'jack');
      expect(state.playerB.wrestlerId, 'jack');
      expect(state.phase, CombatV1MatchPhase.discard);
    });
  });

  group('C. mismatch: 別レスラーのProduction Deckを渡すとEngine.startが拒否する（片側のみ・両側同時を網羅）', () {
    // Codexレビュー指摘（Minor）: 旧「両者同時に取り違えても拒否される」テストは、
    // 実際にはplayerB（wrestlerB: jackWrestler, deckB: buildJackDeck(...)）が
    // 正しい組み合わせのままで、playerA側のみがmismatchしていた
    // （テスト名と実体が一致していなかった）。加えて、旧C/Dテストは名前上
    // 「片側のみのmismatch」に見えるが、実際にはいずれもwrestlerA/wrestlerB
    // 双方が同時にmismatchしていた。ここでは「playerAのみ」「playerBのみ」
    // 「両者同時」の3パターンを、テスト名と実体が一致する形で明示的に分離する
    // （既存の検証パラメータ自体は削除せず、正確な名前の下へ再配置した）。

    test('A. playerAのみmismatch（playerBは正しい組み合わせ）→ Engine.start拒否', () {
      expect(
        () => CombatV1Engine.start(
          wrestlerA: misakiWrestler,
          deckA: buildJackDeck(ownerId: 'player-a'), // playerA: Misaki wrestler + Jack deck（mismatch）
          wrestlerB: jackWrestler,
          deckB: buildJackDeck(ownerId: 'player-b'), // playerB: Jack wrestler + Jack deck（正しい組み合わせ）
          rules: rules,
          catalog: productionCardCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('B. playerBのみmismatch（playerAは正しい組み合わせ）→ Engine.start拒否', () {
      expect(
        () => CombatV1Engine.start(
          wrestlerA: misakiWrestler,
          deckA: buildMisakiDeck(ownerId: 'player-a'), // playerA: Misaki wrestler + Misaki deck（正しい組み合わせ）
          wrestlerB: jackWrestler,
          deckB: buildMisakiDeck(ownerId: 'player-b'), // playerB: Jack wrestler + Misaki deck（mismatch）
          rules: rules,
          catalog: productionCardCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('C. 両者同時にmismatch（オリエンテーション1: Misaki wrestler+Jack deck / Jack wrestler+Misaki deck）→ Engine.start拒否', () {
      expect(
        () => CombatV1Engine.start(
          wrestlerA: misakiWrestler,
          deckA: buildJackDeck(ownerId: 'player-a'), // playerA: Misaki wrestler + Jack deck（mismatch）
          wrestlerB: jackWrestler,
          deckB: buildMisakiDeck(ownerId: 'player-b'), // playerB: Jack wrestler + Misaki deck（mismatch）
          rules: rules,
          catalog: productionCardCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('D. 両者同時にmismatch（オリエンテーション2: Jack wrestler+Misaki deck / Misaki wrestler+Jack deck）→ Engine.start拒否', () {
      expect(
        () => CombatV1Engine.start(
          wrestlerA: jackWrestler,
          deckA: buildMisakiDeck(ownerId: 'player-a'), // playerA: Jack wrestler + Misaki deck（mismatch）
          wrestlerB: misakiWrestler,
          deckB: buildJackDeck(ownerId: 'player-b'), // playerB: Misaki wrestler + Jack deck（mismatch）
          rules: rules,
          catalog: productionCardCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test(
      '不正なEngine.startはMatchStateを一切生成せず、開始前に例外となる'
      '（Dartの関数は例外送出時に値を返せないため、部分的にcommitされた'
      'MatchStateが外部から観測される余地が構造的に存在しないことを、'
      '例外の型と、直後の再呼び出しが同じ例外を再現することで確認する）',
      () {
        Object? firstError;
        try {
          CombatV1Engine.start(
            wrestlerA: misakiWrestler,
            deckA: buildJackDeck(ownerId: 'player-a'),
            wrestlerB: jackWrestler,
            deckB: buildMisakiDeck(ownerId: 'player-b'),
            rules: rules,
            catalog: productionCardCatalog,
          );
        } catch (e) {
          firstError = e;
        }
        expect(firstError, isA<CombatV1IllegalActionException>());

        // 同じ不正な組み合わせを再度呼んでも、決定的に同じ例外になる
        // （事前のCommandで内部stateが汚染され挙動が変化する、といった
        // 副作用が無いことの間接的な確認）。
        expect(
          () => CombatV1Engine.start(
            wrestlerA: misakiWrestler,
            deckA: buildJackDeck(ownerId: 'player-a'),
            wrestlerB: jackWrestler,
            deckB: buildMisakiDeck(ownerId: 'player-b'),
            rules: rules,
            catalog: productionCardCatalog,
          ),
          throwsA(isA<CombatV1IllegalActionException>()),
        );
      },
    );
  });

  group('E. owner namespace独立性（ownerIdとwrestlerIdの混同がないことを直接確認）', () {
    test('Misaki wrestler + Misaki deck(ownerId: player-a) → valid', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-a'),
        wrestlerB: misakiWrestler,
        deckB: buildMisakiDeck(ownerId: 'opponent'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      expect(state.playerA.wrestlerId, 'misaki');
    });

    test('Misaki wrestler + Misaki deck(ownerId: player-b) → valid（ownerId自体は任意の値でよい）', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-b'),
        wrestlerB: misakiWrestler,
        deckB: buildMisakiDeck(ownerId: 'opponent-2'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      expect(state.playerA.wrestlerId, 'misaki');
    });

    test(
      'buildMisakiDeck/buildJackDeckが生成するCombatV1DeckDefinition.wrestlerIdは'
      'ownerIdの値に関わらず常にmisaki/jackのまま変化しない'
      '（ownerId==player wrestlerIdを要求する設計にしていないことの直接確認）',
      () {
        for (final ownerId in ['player-a', 'player-b', 'anything', 'x']) {
          expect(buildMisakiDeck(ownerId: ownerId).wrestlerId, 'misaki');
          expect(buildJackDeck(ownerId: ownerId).wrestlerId, 'jack');
        }
      },
    );
  });

  group('F. mirror match regression（従来どおりvalid、instanceId 60枚一意）', () {
    test('Misaki vs Misaki mirror matchは引き続き成功する', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-a'),
        wrestlerB: misakiWrestler,
        deckB: buildMisakiDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
      expect(_allInstanceIds(state).toSet().length, 60);
    });

    test('Jack vs Jack mirror matchは引き続き成功する', () {
      final state = CombatV1Engine.start(
        wrestlerA: jackWrestler,
        deckA: buildJackDeck(ownerId: 'player-a'),
        wrestlerB: jackWrestler,
        deckB: buildJackDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
      expect(_allInstanceIds(state).toSet().length, 60);
    });
  });

  group('G. Misaki vs Jack cross-wrestler（正しい組み合わせ）', () {
    test('Misaki(player-a) vs Jack(player-b) → valid、各自正しいProduction Deckを使用', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-a'),
        wrestlerB: jackWrestler,
        deckB: buildJackDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      expect(state.playerA.wrestlerId, 'misaki');
      expect(state.playerB.wrestlerId, 'jack');
      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
      expect(_allInstanceIds(state).toSet().length, 60);

      final totalA =
          state.playerA.hand.length +
          state.playerA.drawPile.length +
          state.playerA.discardPile.length;
      final totalB =
          state.playerB.hand.length +
          state.playerB.drawPile.length +
          state.playerB.discardPile.length;
      expect(totalA, 30);
      expect(totalB, 30);
    });
  });

  group('H. 既存validationの回帰なし', () {
    test('productionCardCatalog（ミサキ+ジャック）はvalidateCatalogを通過する', () {
      final result = validateCatalog(productionCardCatalog);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });

    test('buildMisakiDeck()/buildJackDeck()はいずれもvalidateDeck（wrestlerId省略）を通過する', () {
      final misakiResult = validateDeck(
        buildMisakiDeck(ownerId: 'player-a'),
        catalog: productionCardCatalog,
        rules: rules,
      );
      expect(misakiResult.isValid, isTrue, reason: misakiResult.errors.join(' / '));

      final jackResult = validateDeck(
        buildJackDeck(ownerId: 'player-a'),
        catalog: productionCardCatalog,
        rules: rules,
      );
      expect(jackResult.isValid, isTrue, reason: jackResult.errors.join(' / '));
    });

    test('buildMisakiDeck()はwrestlerId=misakiを明示しても引き続きvalid', () {
      final result = validateDeck(
        buildMisakiDeck(ownerId: 'player-a'),
        catalog: productionCardCatalog,
        rules: rules,
        wrestlerId: misakiWrestler.id,
      );
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });

    test('buildMisakiDeck()にwrestlerId=jackを渡すとwrestlerMismatchでinvalid', () {
      final result = validateDeck(
        buildMisakiDeck(ownerId: 'player-a'),
        catalog: productionCardCatalog,
        rules: rules,
        wrestlerId: jackWrestler.id,
      );
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.wrestlerMismatch),
      );
    });

    test('正しい組み合わせのMisaki vs JackはcardconservationとmatchInvariantを維持する', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-a'),
        wrestlerB: jackWrestler,
        deckB: buildJackDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });
  });
}
