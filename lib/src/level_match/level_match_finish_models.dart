import 'dart:math';

import '../wrestler_editor/models.dart';

/// Ver.0.5: 3カウント／ギブアップ決着に関するモデルと純粋計算ロジック。
///
/// ルール判定は必ずここ（と Engine）へ集約し、UI からは呼び出すだけにする。

/// レスポンスカードの種類（イベントカード最小実装）。
enum ResponseCardType { kickOut, ropeBreak }

String responseCardLabel(ResponseCardType type) => switch (type) {
  ResponseCardType.kickOut => 'キックアウト',
  ResponseCardType.ropeBreak => 'ロープブレイク',
};

/// フォール／ギブアップに対する防御側の対応手段。
enum DefenseMethod { card, hp, accept }

/// フォール強度の内訳。ログ・UI 表示にそのまま使う。
class PinStrength {
  const PinStrength({
    required this.total,
    required this.base,
    required this.damage,
    required this.finisherBonus,
    required this.fatigueBonus,
    required this.downBonus,
  });

  final int total;
  final int base;
  final int damage;
  final int finisherBonus;
  final int fatigueBonus;
  final int downBonus;

  Map<String, dynamic> toJson() => {
    'total': total,
    'base': base,
    'damage': damage,
    'finisherBonus': finisherBonus,
    'fatigueBonus': fatigueBonus,
    'downBonus': downBonus,
  };
}

/// ギブアップ強度の内訳。
class SubmissionStrength {
  const SubmissionStrength({
    required this.total,
    required this.base,
    required this.damage,
    required this.finisherBonus,
    required this.fatigueBonus,
    required this.resistanceReduction,
  });

  final int total;
  final int base;
  final int damage;
  final int finisherBonus;
  final int fatigueBonus;
  final int resistanceReduction;

  Map<String, dynamic> toJson() => {
    'total': total,
    'base': base,
    'damage': damage,
    'finisherBonus': finisherBonus,
    'fatigueBonus': fatigueBonus,
    'resistanceReduction': resistanceReduction,
  };
}

/// 相手HPから算出する消耗ボーナス（フォール・ギブアップ共通）。
int fatigueBonusForHp(int targetHp) {
  var bonus = 0;
  if (targetHp <= 50) bonus += 5;
  if (targetHp <= 20) bonus += 5;
  if (targetHp <= 0) bonus += 10;
  return bonus;
}

/// フォール強度を算出する。
PinStrength computePinStrength({
  required MoveDefinition move,
  required int finalDamage,
  required int targetHp,
  required bool fromFinisher,
  required bool targetWasDown,
}) {
  final base = move.pinPower;
  final finisherBonus = fromFinisher
      ? (move.pinBonusOnFinisher > 0 ? move.pinBonusOnFinisher : 15)
      : 0;
  final fatigue = fatigueBonusForHp(targetHp);
  final downBonus = targetWasDown ? 5 : 0;
  final total = max(0, base + finalDamage + finisherBonus + fatigue + downBonus);
  return PinStrength(
    total: total,
    base: base,
    damage: finalDamage,
    finisherBonus: finisherBonus,
    fatigueBonus: fatigue,
    downBonus: downBonus,
  );
}

/// ギブアップ強度を算出する。
SubmissionStrength computeSubmissionStrength({
  required MoveDefinition move,
  required int finalDamage,
  required int targetHp,
  required bool fromFinisher,
  required int targetSubmissionResistance,
}) {
  final base = move.submissionPower;
  final finisherBonus = fromFinisher
      ? (move.submissionBonusOnFinisher > 0
            ? move.submissionBonusOnFinisher
            : 15)
      : 0;
  final fatigue = fatigueBonusForHp(targetHp);
  // 耐性は一部だけを軽減値として使い、ダメージ計算との二重取りを避ける。
  final reduction = (targetSubmissionResistance / 2).floor();
  final total = max(
    0,
    base + finalDamage + finisherBonus + fatigue - reduction,
  );
  return SubmissionStrength(
    total: total,
    base: base,
    damage: finalDamage,
    finisherBonus: finisherBonus,
    fatigueBonus: fatigue,
    resistanceReduction: reduction,
  );
}

/// 強度から必要HP消費量を算出する（フォール耐え・ギブアップ耐え共通）。
int requiredHpCostFor(int strength) => max(5, (strength / 2).ceil());

/// 進行中のフォール判定。
class PendingPin {
  PendingPin({
    required this.attackerId,
    required this.defenderId,
    required this.moveId,
    required this.moveName,
    required this.strength,
    required this.hpKickOutCost,
    required this.fromFinisher,
    required this.targetWasDown,
  });

  final String attackerId;
  final String defenderId;
  final String moveId;
  final String moveName;
  final PinStrength strength;
  final int hpKickOutCost;
  final bool fromFinisher;
  final bool targetWasDown;

  Map<String, dynamic> toJson() => {
    'attackerId': attackerId,
    'defenderId': defenderId,
    'moveId': moveId,
    'moveName': moveName,
    'pinStrength': strength.total,
    'pinComponents': strength.toJson(),
    'hpKickOutCost': hpKickOutCost,
    'fromFinisher': fromFinisher,
    'targetWasDown': targetWasDown,
  };
}

/// 進行中のギブアップ判定。
class PendingSubmission {
  PendingSubmission({
    required this.attackerId,
    required this.defenderId,
    required this.moveId,
    required this.moveName,
    required this.strength,
    required this.hpEscapeCost,
    required this.fromFinisher,
    required this.targetSubmissionResistance,
  });

  final String attackerId;
  final String defenderId;
  final String moveId;
  final String moveName;
  final SubmissionStrength strength;
  final int hpEscapeCost;
  final bool fromFinisher;
  final int targetSubmissionResistance;

  Map<String, dynamic> toJson() => {
    'attackerId': attackerId,
    'defenderId': defenderId,
    'moveId': moveId,
    'moveName': moveName,
    'submissionStrength': strength.total,
    'submissionComponents': strength.toJson(),
    'hpEscapeCost': hpEscapeCost,
    'fromFinisher': fromFinisher,
    'targetSubmissionResistance': targetSubmissionResistance,
  };
}
