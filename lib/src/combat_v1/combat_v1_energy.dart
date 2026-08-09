/// ENERGY Pool / Cost モデルと支払い解決ロジック（docs/combat_rules_v1.md 5章）。
library;

import 'combat_v1_enums.dart';

/// レスラーが保持する固定ENERGY量（「持っているENERGY」）。
///
/// ターン開始時の全回復は [CombatV1PlayerState.spentEnergy]
/// （lib/src/combat_v1/combat_v1_match_state.dart）を空へ戻すだけで、この
/// プール自体の値は変化しない（docs/design/combat_v1_phase1_design.md 5章）。
class CombatV1EnergyPool {
  const CombatV1EnergyPool(this.amounts);

  final Map<CombatV1EnergyAttribute, int> amounts;

  int amountFor(CombatV1EnergyAttribute attribute) => amounts[attribute] ?? 0;
}

/// TECHNIQUE/COUNTERが要求するENERGYコスト（「技が要求するENERGY」）。
///
/// [CombatV1EnergyPool] とは別モデルにする（ユーザー要求、
/// docs/combat_rules_v1.md 5章）。wildはコスト側には現れない前提とする
/// （具体属性の不足分を補う支払い側専用の概念のため、コストとして要求
/// することはできない）。
///
/// 注: この不変条件はコンストラクタでは検証しない。`Map`の添字アクセス
/// （`amounts[...]`）はDartのconst式として評価できないため、const
/// コンストラクタの`assert`に含めると`const CombatV1EnergyCost(...)`を
/// 使う全箇所がコンパイルエラーになる（技カタログを`const`で定義できなく
/// なるため）。技データ側の作成規約として扱う。
class CombatV1EnergyCost {
  const CombatV1EnergyCost(this.amounts);

  final Map<CombatV1EnergyAttribute, int> amounts;

  int amountFor(CombatV1EnergyAttribute attribute) => amounts[attribute] ?? 0;

  static const CombatV1EnergyCost zero = CombatV1EnergyCost({});
}

/// ENERGY支払い判定の結果。
class CombatV1EnergyPaymentResult {
  const CombatV1EnergyPaymentResult.success(this.updatedSpent)
    : failureReason = null;

  const CombatV1EnergyPaymentResult.failure(this.failureReason)
    : updatedSpent = null;

  final Map<CombatV1EnergyAttribute, int>? updatedSpent;
  final String? failureReason;

  bool get isSuccess => updatedSpent != null;
}

/// ENERGY支払いを解決する（docs/combat_rules_v1.md 5.1章）。
///
/// 手順:
/// 1. 各具体属性（打/関/投/飛/ラフ）についてコストと残量を比較し、不足分を求める。
/// 2. 不足分を属性横断で合算する。
/// 3. 合算した合計不足分が、保有する＊(wild)の残量以下であれば支払い成立。
///    属性ごとに個別のワイルド消費順序は設けない（＊は属性を跨いで融通できる
///    共有資源として扱う）。
///
/// [allowWildSubstitution] はCOUNTER実装（Phase 4）で別ポリシーへ差し替え
/// られるようにするための引数（Phase 1のTECHNIQUE支払いは常にtrue、
/// docs/design/combat_v1_open_questions.md 5番）。
CombatV1EnergyPaymentResult resolveEnergyPayment({
  required CombatV1EnergyPool pool,
  required Map<CombatV1EnergyAttribute, int> spent,
  required CombatV1EnergyCost cost,
  required bool allowWildSubstitution,
}) {
  final updatedSpent = Map<CombatV1EnergyAttribute, int>.from(spent);
  var totalShortfall = 0;

  for (final attribute in CombatV1EnergyAttribute.values) {
    if (attribute == CombatV1EnergyAttribute.wild) continue;
    final required = cost.amountFor(attribute);
    if (required <= 0) continue;

    final available = pool.amountFor(attribute) - (spent[attribute] ?? 0);
    if (available >= required) {
      updatedSpent[attribute] = (updatedSpent[attribute] ?? 0) + required;
      continue;
    }

    final usableFromAttribute = available > 0 ? available : 0;
    // usableFromAttributeが0でも明示的にキーを設定する（コストに含まれる
    // 属性は常にupdatedSpentへ反映し、「未設定=0」と「明示的に0」を
    // 区別しない呼び出し側の実装との整合を保つ）。
    updatedSpent[attribute] =
        (updatedSpent[attribute] ?? 0) + usableFromAttribute;
    totalShortfall += required - usableFromAttribute;
  }

  if (totalShortfall == 0) {
    return CombatV1EnergyPaymentResult.success(updatedSpent);
  }

  if (!allowWildSubstitution) {
    return const CombatV1EnergyPaymentResult.failure(
      'ENERGYが不足しています（ワイルドENERGYでの補完は許可されていません）',
    );
  }

  final availableWild =
      pool.amountFor(CombatV1EnergyAttribute.wild) -
      (spent[CombatV1EnergyAttribute.wild] ?? 0);
  if (availableWild < totalShortfall) {
    return const CombatV1EnergyPaymentResult.failure('ENERGYが不足しています');
  }

  updatedSpent[CombatV1EnergyAttribute.wild] =
      (updatedSpent[CombatV1EnergyAttribute.wild] ?? 0) + totalShortfall;
  return CombatV1EnergyPaymentResult.success(updatedSpent);
}
