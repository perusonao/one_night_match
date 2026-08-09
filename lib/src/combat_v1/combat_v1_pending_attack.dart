/// TECHNIQUE宣言〜COUNTER応答待ちの間、攻撃内容を保持するpublic immutable
/// Domain model（docs/combat_rules_v1.md 7章、Phase 4）。
///
/// Phase 3の`_PreparedTechniqueUse`（private、`combat_v1_engine.dart`）を
/// そのまま`CombatV1MatchState`へ保存すると、Engine内部実装の都合が
/// Domain stateへ漏れてしまうため、Phase 4で独立したpublicモデルへ昇格した。
library;

import 'combat_v1_deck.dart';
import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';

/// 宣言済みだがまだ解決していない攻撃TECHNIQUE1件（docs/combat_rules_v1.md
/// 7.1章「PendingAttack・counterResponsePending」）。
///
/// [attackCardInstance]（物理カード）は、宣言時点でhand/drawPile/discardPile
/// のいずれからも取り除かれ、このpendingが所有する（カード保存則は
/// docs/combat_rules_v1.md 16章「山札切れ・手札循環」の延長として、
/// drawPile+hand+discardPile+owned pending card=30で維持する）。TECHNIQUE
/// 解決に必要な値はCatalog参照ではなく宣言時点のスナップショットとして
/// 保持し、外部Catalogの変更やMapのmutationで攻撃内容が後から変わらない
/// ようにする（[energyCost]は[CombatV1EnergyCost.amounts]を防御的に
/// コピーして保持する）。
class CombatV1PendingAttack {
  CombatV1PendingAttack({
    required this.attackerPlayerIndex,
    required this.defenderPlayerIndex,
    required this.attackCardInstance,
    required this.category,
    required this.attribute,
    required this.family,
    required CombatV1EnergyCost energyCost,
    required this.damage,
    required this.heatGain,
    this.requiredOpponentState,
    this.resultOpponentState,
  }) : energyCost = CombatV1EnergyCost(
         Map.unmodifiable(energyCost.amounts),
       );

  /// 宣言時点の`CombatV1MatchState.activePlayerIndex`（攻撃側）。
  final int attackerPlayerIndex;

  /// 攻撃を受ける側のplayerIndex（`1 - attackerPlayerIndex`）。
  final int defenderPlayerIndex;

  /// pendingが所有する物理カード（宣言時点でhand/drawPile/discardPileの
  /// いずれからも除去済み）。
  final CombatV1DeckEntry attackCardInstance;

  /// 攻撃TECHNIQUEのカード定義ID（`attackCardInstance.cardId`と同じ値だが、
  /// 呼び出し側がCatalogを介さず参照できるよう明示的に公開する）。
  String get attackCardId => attackCardInstance.cardId;

  final CombatV1CardCategory category;
  final CombatV1EnergyAttribute attribute;
  final CombatV1TechniqueFamily family;

  /// 宣言時点のTechnique定義から防御的コピーしたENERGY COST
  /// （COUNTER側の動的必要量算出——`combat_v1_counter_rules.dart`の
  /// `counterSyntheticCost`——にも使う）。
  final CombatV1EnergyCost energyCost;

  final int damage;
  final int heatGain;
  final CombatV1WrestlerPosture? requiredOpponentState;
  final CombatV1WrestlerPosture? resultOpponentState;
}
