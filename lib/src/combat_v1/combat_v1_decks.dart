/// Production 30枚Deck定義（docs/combat_rules_v1.md 3・21章、Phase 10A/10B）。
///
/// Phase 10Aで豪田ミサキ、Phase 10Bで黒蝶ジャックの正式30枚デッキを追加した
/// （火神アカリ・白銀レイナは今回実装しない）。ミサキの配分は`combat_rules_v1.md`21章の方針
/// （基本NORMAL×3・その他NORMAL×2、SIGNATURE各×2、FINISHER各×1、COUNTER各×2）を
/// そのまま正式採用した（docs/design/combat_v1_phase10_production_data.md 5章）。
///
/// physical instanceIdは、`CombatV1MatchState`のinvariant
/// （`combat_v1_state_invariants.dart`の`duplicateCardInstanceId`：
/// 両playerの全カードゾーン＋pendingを通じて一意）を満たす必要がある。
/// cardId（Technique/Counterの安定definition
/// id）はplayer間で同一でよい（同じレスラー同士のミラーマッチも正常な
/// ユースケース）が、instanceIdはmatch内でplayerを跨いで一意でなければ
/// ならないため、Production Deck
/// builderは呼び出し側から[ownerId]（どちらのplayer向けに生成したデッキかを
/// 表す識別子）を必ず受け取る（docs/design/combat_v1_phase10_production_data.md
/// 7章）。
library;

import 'combat_v1_deck.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_wrestler_catalog.dart';

/// [ownerId]・[spec]（cardId／category／枚数）から物理カード
/// （[CombatV1DeckEntry]）のリストを組み立てる。instanceIdは
/// `<ownerId>_<cardId>_#<連番>`で一意にする。
///
/// [ownerId]はphysical instanceId生成専用の識別子であり、Technique/Counterの
/// 安定definition id（[cardId]）とは独立した概念（cardId自体は変更しない）。
List<CombatV1DeckEntry> _buildEntries(
  String ownerId,
  List<(String cardId, CombatV1CardCategory category, int count)> spec,
) {
  if (ownerId.trim().isEmpty) {
    throw ArgumentError.value(
      ownerId,
      'ownerId',
      'ownerIdを空にすることはできません（player間でinstanceIdが衝突する'
          '原因になるため、Production Deck builderは呼び出しごとに一意な'
          'ownerIdを必須とする）',
    );
  }
  final entries = <CombatV1DeckEntry>[];
  var seq = 0;
  for (final (cardId, category, count) in spec) {
    for (var i = 0; i < count; i++) {
      entries.add(
        CombatV1DeckEntry(
          instanceId: '${ownerId}_${cardId}_#${seq++}',
          cardId: cardId,
          category: category,
        ),
      );
    }
  }
  return entries;
}

/// 豪田ミサキ Production Deck 30枚の内訳
/// （NORMAL18・SIGNATURE4・FINISHER2・COUNTER6、
/// docs/design/combat_v1_phase10_production_data.md 5章）。
const List<(String, CombatV1CardCategory, int)> misakiDeckSpec = [
  // NORMAL 18枚: 基本技（逆水平チョップ・ボディスラム）×3、その他×2。
  ('misaki_reverse_chop', CombatV1CardCategory.normal, 3),
  ('misaki_body_slam', CombatV1CardCategory.normal, 3),
  ('misaki_shoulder_tackle', CombatV1CardCategory.normal, 2),
  ('misaki_brainbuster', CombatV1CardCategory.normal, 2),
  ('misaki_backdrop', CombatV1CardCategory.normal, 2),
  ('misaki_power_slam', CombatV1CardCategory.normal, 2),
  ('misaki_lariat', CombatV1CardCategory.normal, 2),
  ('misaki_guillotine_drop', CombatV1CardCategory.normal, 2),

  // SIGNATURE 4枚: 2種×2枚。
  ('misaki_mighty_backdrop', CombatV1CardCategory.signature, 2),
  ('misaki_strong_arm_lariat', CombatV1CardCategory.signature, 2),

  // FINISHER 2枚: 2種×1枚。
  ('misaki_goda_bomb', CombatV1CardCategory.finisher, 1),
  ('misaki_goda_driver', CombatV1CardCategory.finisher, 1),

  // COUNTER 6枚: 3種×2枚。
  ('counter_strike_guard', CombatV1CardCategory.counter, 2),
  ('counter_suplex_reversal', CombatV1CardCategory.counter, 2),
  ('counter_powerbomb_escape', CombatV1CardCategory.counter, 2),
];

/// 豪田ミサキ Production Deck（30枚）。
///
/// [ownerId]は、このデッキがどちらのplayerへ配られるかを表す識別子で、
/// physical instanceIdの生成にのみ使う（必須・デフォルト値なし——呼び出し側が
/// 指定を省略して同一デッキを両playerへそのまま渡し、instanceIdが衝突する
/// ミラーマッチ事故を構造的に防ぐため）。[CombatV1DeckDefinition.wrestlerId]
/// は引き続き常に[misakiWrestler.id]（"misaki"）を指す
/// ——「どのレスラーのデッキか」と「どちらのplayerが使うか」は別概念であり、
/// [ownerId]はwrestlerId／cardId／stable IDのいずれにも影響しない。
CombatV1DeckDefinition buildMisakiDeck({required String ownerId}) =>
    CombatV1DeckDefinition(
      wrestlerId: misakiWrestler.id,
      entries: _buildEntries(ownerId, misakiDeckSpec),
    );

/// 黒蝶ジャック Production Deck 30枚の内訳
/// （NORMAL18・SIGNATURE4・FINISHER2・COUNTER6、
/// docs/design/combat_v1_phase10_production_data.md Phase 10B節）。
/// ROUGH技の枚数（チョーク攻撃×1・顔面かきむしり×1・黒蝶クラッシュ×2・
/// 黒蝶ドライバー×1＝計5枚）は`combat_rules_v1.md`20章の確定値をそのまま採用した。
const List<(String, CombatV1CardCategory, int)> jackDeckSpec = [
  // NORMAL 18枚: ROUGH2種は20章の確定枚数（×1）、残り6種はPhase
  // 10Bで新規確定した配分（基本4種×3、投/関の各1種×2）。
  ('jack_choke_attack', CombatV1CardCategory.normal, 1),
  ('jack_face_claw', CombatV1CardCategory.normal, 1),
  ('jack_sneak_kick', CombatV1CardCategory.normal, 3),
  ('jack_elbow', CombatV1CardCategory.normal, 3),
  ('jack_sneak_lariat', CombatV1CardCategory.normal, 3),
  ('jack_suplex', CombatV1CardCategory.normal, 2),
  ('jack_armlock', CombatV1CardCategory.normal, 2),
  ('jack_finishing_stomp', CombatV1CardCategory.normal, 3),

  // SIGNATURE 4枚: 2種×2枚。
  ('jack_kurocho_crash', CombatV1CardCategory.signature, 2),
  ('jack_knee_drop', CombatV1CardCategory.signature, 2),

  // FINISHER 2枚: 2種×1枚。
  ('jack_kurocho_driver', CombatV1CardCategory.finisher, 1),
  ('jack_black_jack', CombatV1CardCategory.finisher, 1),

  // COUNTER 6枚: 3種×2枚。
  ('counter_jack_sneak_guard', CombatV1CardCategory.counter, 2),
  ('counter_jack_reversal', CombatV1CardCategory.counter, 2),
  ('counter_jack_choke_break', CombatV1CardCategory.counter, 2),
];

/// 黒蝶ジャック Production Deck（30枚）。
///
/// [ownerId]は、このデッキがどちらのplayerへ配られるかを表す識別子で、
/// physical instanceIdの生成にのみ使う（必須・デフォルト値なし、
/// `buildMisakiDeck`と同じ設計方針——docs/design/combat_v1_phase10_production_data.md
/// 7章参照）。[CombatV1DeckDefinition.wrestlerId]は引き続き常に[jackWrestler.id]
/// （"jack"）を指す。
CombatV1DeckDefinition buildJackDeck({required String ownerId}) =>
    CombatV1DeckDefinition(
      wrestlerId: jackWrestler.id,
      entries: _buildEntries(ownerId, jackDeckSpec),
    );
