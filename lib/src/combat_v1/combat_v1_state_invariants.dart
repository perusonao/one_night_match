/// Match State不変条件の検証（Phase 3、docs/combat_rules_v1.md 5章。Phase
/// 4でpendingAttack/MatchState間の整合性検証を追加、Codexレビュー指摘H1）。
///
/// [CombatV1EnergyPool]/[CombatV1EnergyCost]/[CombatV1Technique]の静的データ
/// validation（`isValid`/`isStaticDataValid`）とは別に、試合が進行した後の
/// `CombatV1PlayerState`/`CombatV1MatchState`スナップショットが不変条件を
/// 満たしているかを検証する読み取り専用ヘルパー。
///
/// immutableモデルのコンストラクタに重いruntime validationを持たせる方針は
/// 取らない（`combat_v1_energy.dart`のコンストラクタコメント参照）。この
/// ファイルの関数の大半（[validatePlayerStateInvariants]、
/// [validateMatchStateInvariants]）は、CPU/Simulator/テストなど必要な
/// 箇所からオプトインで呼び出す想定で、Engine本体のCommand
/// APIには自動配線しない。例外は[pendingStructuralConsistencyViolation]・
/// [pendingAttackOwnershipViolation]・[pinStateConsistencyViolation]
/// —— pending/state間の構造整合性、pendingが所有する1枚のカードのゾーン
/// 所有権チェック、およびPIN Commandが操作するattacker/defenderのPIN
/// カード・KOC最小限チェック（Phase 5）のみを`CombatV1Engine`のCommand
/// 実行前ガードとして直接利用する（両player全体のinstanceId重複スキャン等、
/// より重い検証は含まないため、毎Command呼び出しでも許容できるコストに
/// 留めている）。
library;

import 'combat_v1_enums.dart';
import 'combat_v1_match_state.dart';
import 'combat_v1_pending_attack.dart';
import 'combat_v1_rules_config.dart';

/// [validatePlayerStateInvariants]のエラー種別。
enum CombatV1PlayerStateInvariantErrorCode {
  /// spentEnergy（今サイクルの使用済みENERGY）が、対応する属性の
  /// energyPool（保有ENERGY）を超えている。
  spentExceedsPool,

  /// spentEnergyの値が負数（Phase 4、Phase 3 Codexレビュー指摘「10-1」）。
  /// defenderが自ターン外にCOUNTER ENERGYを消費するようになるため、
  /// spentEnergyの不正な負値を検出できることがPhase 4以降より重要になる。
  negativeSpentEnergy,

  /// [CombatV1PlayerState.energyPool]自体が[CombatV1EnergyPool.isValid]
  /// でない（負数のENERGY量を含む、Phase 4、Phase 3 Codexレビュー指摘
  /// 「10-1」）。
  invalidEnergyPool,

  /// `koc`が負数（Phase 5、docs/combat_rules_v1.md 9章「koc >= 0」）。
  /// PIN解決は支払い可能性を先に判定してから差し引くため（15章）、
  /// 正規のCommand経路では発生しないはずだが、防御的に検証する。
  negativeKoc,

  /// `pinCardsHeld`が1未満（Phase 5、docs/combat_rules_v1.md 8.1章
  /// 「最低1枚保証」）。
  pinCardsHeldBelowMinimum,
}

/// [validatePlayerStateInvariants]の1件のエラー。
class CombatV1PlayerStateInvariantError {
  const CombatV1PlayerStateInvariantError({
    required this.code,
    required this.message,
  });

  final CombatV1PlayerStateInvariantErrorCode code;

  /// 人間可読な説明（ログ・簡易UI用）。
  final String message;

  @override
  String toString() => message;
}

/// [validatePlayerStateInvariants]の結果。
class CombatV1PlayerStateInvariantResult {
  const CombatV1PlayerStateInvariantResult(this.errors);

  final List<CombatV1PlayerStateInvariantError> errors;

  bool get isValid => errors.isEmpty;
}

/// [player]の`spentEnergy`/`energyPool`/`koc`/`pinCardsHeld`が不変条件を
/// 満たしているか検証する（docs/combat_rules_v1.md 5・8・9章、Phase
/// 4でnegativeSpentEnergy/invalidEnergyPoolを追加、Phase
/// 5でnegativeKoc/pinCardsHeldBelowMinimumを追加）。
CombatV1PlayerStateInvariantResult validatePlayerStateInvariants(
  CombatV1PlayerState player,
) {
  final errors = <CombatV1PlayerStateInvariantError>[];

  if (!player.energyPool.isValid) {
    errors.add(
      CombatV1PlayerStateInvariantError(
        code: CombatV1PlayerStateInvariantErrorCode.invalidEnergyPool,
        message: '${player.wrestlerName}のenergyPoolに負数のENERGY量が'
            '含まれています',
      ),
    );
  }

  if (player.koc < 0) {
    errors.add(
      CombatV1PlayerStateInvariantError(
        code: CombatV1PlayerStateInvariantErrorCode.negativeKoc,
        message: '${player.wrestlerName}のkocが負数です（koc:${player.koc}）',
      ),
    );
  }

  if (player.pinCardsHeld < 1) {
    errors.add(
      CombatV1PlayerStateInvariantError(
        code: CombatV1PlayerStateInvariantErrorCode.pinCardsHeldBelowMinimum,
        message: '${player.wrestlerName}のpinCardsHeldが最低1枚を'
            '下回っています（pinCardsHeld:${player.pinCardsHeld}）',
      ),
    );
  }

  for (final attribute in CombatV1EnergyAttribute.values) {
    final spent = player.spentEnergy[attribute] ?? 0;

    if (spent < 0) {
      errors.add(
        CombatV1PlayerStateInvariantError(
          code: CombatV1PlayerStateInvariantErrorCode.negativeSpentEnergy,
          message:
              '${player.wrestlerName}の${attribute.displayLabel}ENERGYの'
              'spentEnergyが負数です（spent:$spent）',
        ),
      );
      continue;
    }

    final pool = player.energyPool.amountFor(attribute);
    if (spent > pool) {
      errors.add(
        CombatV1PlayerStateInvariantError(
          code: CombatV1PlayerStateInvariantErrorCode.spentExceedsPool,
          message:
              '${player.wrestlerName}の${attribute.displayLabel}ENERGYが'
              'Poolを超えて使用されています（spent:$spent, pool:$pool）',
        ),
      );
    }
  }

  return CombatV1PlayerStateInvariantResult(errors);
}

/// PIN Commandが操作する[attacker]/[defender]がPhase 5の最低限のstate
/// invariantを満たしているかを検証する軽量チェック（Phase 5 Codexレビュー
/// 指摘H1対応）。
///
/// [pendingStructuralConsistencyViolation]・[pendingAttackOwnershipViolation]
/// と同じ位置付け——`validateMatchStateInvariants`／`validatePlayerStateInvariants`
/// のような重い全件診断ではなく、PIN Command（`declarePin`／DIRECT PIN自動
/// 遷移）が実行前に必ず検証すべき最小限のチェックのみに限定する:
///
/// - `attacker.pinCardsHeld >= 1`
/// - `defender.pinCardsHeld >= 1`
/// - `attacker.pinCardsHeld + defender.pinCardsHeld == rules.totalPinCards`
/// - `attacker.koc >= 0`
/// - `defender.koc >= 0`
///
/// これらが崩れたstateでPINカード移動／KOC消費を計算すると、「移動なし」
/// 「KOC不足」「3カウント」等の正常な結果として誤って解釈されてしまう
/// （docs/combat_rules_v1.md 8章）。`CombatV1Engine.checkPinLegality`・
/// DIRECT PIN自動遷移（`_resolvePendingAttack`、Technique成功のstate commit
/// より前）の両方から、実際にPINカード／KOCを操作する前に呼び出す。
///
/// 不整合があれば人間可読な理由を、無ければ`null`を返す。
String? pinStateConsistencyViolation({
  required CombatV1PlayerState attacker,
  required CombatV1PlayerState defender,
  required CombatV1RulesConfig rules,
}) {
  if (attacker.pinCardsHeld < 1) {
    return '攻撃側のpinCardsHeldが最低1枚を下回っています'
        '（pinCardsHeld:${attacker.pinCardsHeld}）';
  }
  if (defender.pinCardsHeld < 1) {
    return '防御側のpinCardsHeldが最低1枚を下回っています'
        '（pinCardsHeld:${defender.pinCardsHeld}）';
  }
  final total = attacker.pinCardsHeld + defender.pinCardsHeld;
  if (total != rules.totalPinCards) {
    return 'PINカードの合計が${rules.totalPinCards}と一致しません（合計:$total）';
  }
  if (attacker.koc < 0) {
    return '攻撃側のkocが負数です（koc:${attacker.koc}）';
  }
  if (defender.koc < 0) {
    return '防御側のkocが負数です（koc:${defender.koc}）';
  }
  return null;
}

/// SUBMISSION自動遷移（`_resolvePendingAttack`、Technique成功のstate commit
/// より前）が操作する[defender]がPhase 6の最低限のstate invariantを満たして
/// いるかを検証する軽量チェック（[pinStateConsistencyViolation]と同じ位置
/// 付け）。
///
/// - `defender.koc >= 0`
///
/// これが崩れたstateでKOC消費（ESCAPE）を計算すると、正常な結果として誤って
/// 解釈されてしまう（docs/combat_rules_v1.md 10.1章）。
///
/// 不整合があれば人間可読な理由を、無ければ`null`を返す。
String? submissionStateConsistencyViolation({
  required CombatV1PlayerState defender,
}) {
  if (defender.koc < 0) {
    return '防御側のkocが負数です（koc:${defender.koc}）';
  }
  return null;
}

/// pending/state間の構造的整合性（`phase`と`pendingAttack`存在の整合性、
/// `attackerPlayerIndex`/`defenderPlayerIndex`の整合性）を検証する軽量
/// チェック（Phase 4 Codexレビュー指摘H1対応）。
///
/// カードゾーンの走査（hand/drawPile/discardPileの全件スキャン）は含まない
/// —— この関数は`CombatV1Engine`のCommand実行前ガードとしても使われる
/// ため、意図的に安価な検証のみに限定している（毎Commandで全30枚を重く
/// validateする設計にはしない）。カードゾーン走査を含む完全な診断は
/// [validateMatchStateInvariants]を使う。
///
/// 不整合があれば人間可読な理由を、無ければ`null`を返す。
String? pendingStructuralConsistencyViolation(CombatV1MatchState state) {
  final pending = state.pendingAttack;
  final isPendingPhase = state.phase == CombatV1MatchPhase.counterResponsePending;

  if (isPendingPhase && pending == null) {
    return 'phase==counterResponsePendingですが、pendingAttackが存在しません';
  }
  if (!isPendingPhase && pending != null) {
    return 'pendingAttackが存在しますが、phase==counterResponsePendingでは'
        'ありません（現在: ${state.phase.name}）';
  }
  if (pending == null) return null;

  final validIndex =
      (pending.attackerPlayerIndex == 0 || pending.attackerPlayerIndex == 1) &&
      (pending.defenderPlayerIndex == 0 || pending.defenderPlayerIndex == 1);
  if (!validIndex) {
    return 'pendingAttackのattackerPlayerIndex'
        '(${pending.attackerPlayerIndex})/defenderPlayerIndex'
        '(${pending.defenderPlayerIndex})が0/1の範囲外です';
  }
  if (pending.attackerPlayerIndex == pending.defenderPlayerIndex) {
    return 'pendingAttackのattackerPlayerIndexとdefenderPlayerIndexが'
        '同じです（${pending.attackerPlayerIndex}）';
  }
  if (pending.attackerPlayerIndex != state.activePlayerIndex) {
    return 'pendingAttack.attackerPlayerIndex(${pending.attackerPlayerIndex})が'
        'state.activePlayerIndex(${state.activePlayerIndex})と一致しません';
  }
  final expectedDefender = state.activePlayerIndex == 0 ? 1 : 0;
  if (pending.defenderPlayerIndex != expectedDefender) {
    return 'pendingAttack.defenderPlayerIndex(${pending.defenderPlayerIndex})が'
        '期待値($expectedDefender)と一致しません';
  }
  return null;
}

/// [validateMatchStateInvariants]のエラー種別（Phase 4 Codexレビュー指摘
/// H1対応）。
enum CombatV1MatchStateInvariantErrorCode {
  /// `phase == counterResponsePending`と`pendingAttack != null`の整合性が
  /// 崩れている。
  pendingPhaseMismatch,

  /// `pendingAttack.attackerPlayerIndex`/`defenderPlayerIndex`が0/1の
  /// 範囲外。
  pendingPlayerIndexOutOfRange,

  /// `pendingAttack.attackerPlayerIndex == defenderPlayerIndex`。
  pendingAttackerEqualsDefender,

  /// `pendingAttack.attackerPlayerIndex`が`state.activePlayerIndex`と
  /// 一致しない。
  pendingAttackerIndexMismatch,

  /// `pendingAttack.defenderPlayerIndex`が期待値（`1 -
  /// activePlayerIndex`）と一致しない。
  pendingDefenderIndexMismatch,

  /// pendingが所有するはずの攻撃カードが、攻撃側のhand/drawPile/
  /// discardPileのいずれかにも同時に存在する（カード保存則違反）。
  pendingCardStillInAttackerZone,

  /// pendingが所有する攻撃カードのinstanceIdが、防御側のhand/drawPile/
  /// discardPileのいずれかにも存在する。
  pendingCardInDefenderZone,

  /// 同一instanceIdが、両player全ゾーン（＋pending）を通じて重複している。
  duplicateCardInstanceId,

  /// `pendingAttack.attackCardInstance.category`が
  /// `pendingAttack.category`と一致しない。
  pendingCardCategoryMismatch,

  /// `playerA.pinCardsHeld + playerB.pinCardsHeld`が
  /// [CombatV1RulesConfig.totalPinCards]と一致しない（Phase 5、
  /// docs/combat_rules_v1.md 8.1章「PINカードは共有4枚」）。
  pinCardsTotalMismatch,

  /// `winnerPlayerIndex`が`null`/`0`/`1`のいずれでもない（Phase 5 Codex
  /// レビュー指摘H2）。
  winnerPlayerIndexOutOfRange,

  /// 非手番プレイヤー（`state.opponent`）の`roughTechniqueLimitActive`が
  /// trueになっている（Phase 8、docs/combat_rules_v1.md 15章）。この制限は
  /// 「次の自ターン」限定の制約で、`_advanceTurnAfterEnd`が手番を渡す瞬間に
  /// のみ手番プレイヤー側へセットし、そのターンの終了時に必ず解除する。
  /// 非手番側でtrueのまま残ることは構造的に不整合。
  roughTechniqueLimitActiveOnInactivePlayer,
}

/// [validateMatchStateInvariants]の1件のエラー。
class CombatV1MatchStateInvariantError {
  const CombatV1MatchStateInvariantError({
    required this.code,
    required this.message,
  });

  final CombatV1MatchStateInvariantErrorCode code;

  /// 人間可読な説明（ログ・簡易UI用）。
  final String message;

  @override
  String toString() => message;
}

/// [validateMatchStateInvariants]の結果。
class CombatV1MatchStateInvariantResult {
  const CombatV1MatchStateInvariantResult(this.errors);

  final List<CombatV1MatchStateInvariantError> errors;

  bool get isValid => errors.isEmpty;
}

/// [pendingAttackOwnershipViolation]・[validateMatchStateInvariants]の両方が
/// 参照する、pendingが所有するカードのゾーン所有権判定（Phase 4 Codex再
/// レビュー指摘H1残件対応）。カードゾーン走査ロジックを1箇所にまとめ、
/// 安価なCommandガードと重い全体診断とで同じ判定条件を重複実装しない。
class _PendingOwnershipStatus {
  const _PendingOwnershipStatus({
    required this.categoryMismatch,
    required this.inAttackerZone,
    required this.inDefenderZone,
  });

  final bool categoryMismatch;
  final bool inAttackerZone;
  final bool inDefenderZone;

  bool get isValid => !categoryMismatch && !inAttackerZone && !inDefenderZone;
}

_PendingOwnershipStatus _pendingOwnershipStatus(
  CombatV1MatchState state,
  CombatV1PendingAttack pending,
) {
  final attacker = pending.attackerPlayerIndex == 0 ? state.playerA : state.playerB;
  final defender = pending.defenderPlayerIndex == 0 ? state.playerA : state.playerB;
  final pendingId = pending.attackCardInstance.instanceId;

  final inAttackerZone =
      attacker.hand.any((e) => e.instanceId == pendingId) ||
      attacker.drawPile.any((e) => e.instanceId == pendingId) ||
      attacker.discardPile.any((e) => e.instanceId == pendingId);
  final inDefenderZone =
      defender.hand.any((e) => e.instanceId == pendingId) ||
      defender.drawPile.any((e) => e.instanceId == pendingId) ||
      defender.discardPile.any((e) => e.instanceId == pendingId);

  return _PendingOwnershipStatus(
    categoryMismatch: pending.attackCardInstance.category != pending.category,
    inAttackerZone: inAttackerZone,
    inDefenderZone: inDefenderZone,
  );
}

/// pendingが所有するはずの攻撃カードの所有権（攻撃側/防御側のいずれの
/// hand/drawPile/discardPileにも存在しないこと、
/// `attackCardInstance.category`が`pending.category`と一致すること）を
/// 検証する軽量チェック（Phase 4 Codex再レビュー指摘H1残件対応）。
///
/// [pendingStructuralConsistencyViolation]と同じ位置付け——カードゾーンの
/// 全件重複スキャン（[validateMatchStateInvariants]の
/// `duplicateCardInstanceId`）は行わず、pendingが所有する1枚のカードに
/// 関する所有権のみを判定する。malformedなpending
/// card ownership state（宣言時に本来除去されるはずの攻撃カードが手札等に
/// 残ったまま、または他ゾーンのカードとinstanceIdが衝突している状態）を
/// `playCounter`/`declineCounter`/`checkCounterLegality`が処理しないよう、
/// これらのCommand実行前ガードとして直接呼び出す。
///
/// [pendingStructuralConsistencyViolation]で有効と確認されたindexを前提に
/// するため、先にそちらを呼んでいない場合はindex不整合の理由を返す
/// （内部で呼び出し、null以外ならそのまま返す）。
///
/// 不整合があれば人間可読な理由を、無ければ`null`を返す。
String? pendingAttackOwnershipViolation(CombatV1MatchState state) {
  final pending = state.pendingAttack;
  if (pending == null) return null;

  final structuralViolation = pendingStructuralConsistencyViolation(state);
  if (structuralViolation != null) return structuralViolation;

  final status = _pendingOwnershipStatus(state, pending);
  if (status.categoryMismatch) {
    return 'pendingAttack.attackCardInstance.category'
        '(${pending.attackCardInstance.category.name})がpending.category'
        '(${pending.category.name})と一致しません';
  }
  if (status.inAttackerZone) {
    return 'pendingAttackが所有するはずのカード'
        '(${pending.attackCardInstance.instanceId})が、攻撃側の'
        'hand/drawPile/discardPileにも存在します';
  }
  if (status.inDefenderZone) {
    return 'pendingAttackが所有するカード'
        '(${pending.attackCardInstance.instanceId})のinstanceIdが、'
        '防御側のhand/drawPile/discardPileにも存在します';
  }
  return null;
}

/// [state]全体（`pendingAttack`とplayerA/playerBのカードゾーン）の整合性を
/// 検証する読み取り専用の診断ヘルパー（Phase 4 Codexレビュー指摘H1対応）。
///
/// [pendingStructuralConsistencyViolation]（Engine Commandガードにも使う
/// 安価なチェック）に加え、カードゾーンの全件スキャンを要する検証
/// （pending cardの二重所持、instanceIdの重複、pending
/// カードのcategory整合性）を行う。コストが高いため、Engine本体のCommand
/// APIには自動配線しない——CPU/Simulator/テストからオプトインで呼び出す
/// 想定（`validatePlayerStateInvariants`と同じ方針）。
CombatV1MatchStateInvariantResult validateMatchStateInvariants(
  CombatV1MatchState state, {
  CombatV1RulesConfig rules = const CombatV1RulesConfig(),
}) {
  final errors = <CombatV1MatchStateInvariantError>[];
  final pending = state.pendingAttack;

  final pinCardsTotal = state.playerA.pinCardsHeld + state.playerB.pinCardsHeld;
  if (pinCardsTotal != rules.totalPinCards) {
    errors.add(
      CombatV1MatchStateInvariantError(
        code: CombatV1MatchStateInvariantErrorCode.pinCardsTotalMismatch,
        message: 'playerA.pinCardsHeld + playerB.pinCardsHeldが'
            '${rules.totalPinCards}と一致しません（合計:$pinCardsTotal）',
      ),
    );
  }

  final winner = state.winnerPlayerIndex;
  if (winner != null && winner != 0 && winner != 1) {
    errors.add(
      CombatV1MatchStateInvariantError(
        code: CombatV1MatchStateInvariantErrorCode.winnerPlayerIndexOutOfRange,
        message: 'winnerPlayerIndexがnull/0/1のいずれでもありません'
            '（winnerPlayerIndex:$winner）',
      ),
    );
  }

  if (state.opponent.roughTechniqueLimitActive) {
    errors.add(
      CombatV1MatchStateInvariantError(
        code: CombatV1MatchStateInvariantErrorCode
            .roughTechniqueLimitActiveOnInactivePlayer,
        message: '非手番プレイヤー（playerIndex:'
            '${state.activePlayerIndex == 0 ? 1 : 0}）の'
            'roughTechniqueLimitActiveがtrueです',
      ),
    );
  }

  final isPendingPhase = state.phase == CombatV1MatchPhase.counterResponsePending;

  if (isPendingPhase != (pending != null)) {
    errors.add(
      CombatV1MatchStateInvariantError(
        code: CombatV1MatchStateInvariantErrorCode.pendingPhaseMismatch,
        message: pendingStructuralConsistencyViolation(state) ??
            'phaseとpendingAttackの整合性が崩れています',
      ),
    );
  }

  bool validIndex = false;
  if (pending != null) {
    validIndex =
        (pending.attackerPlayerIndex == 0 || pending.attackerPlayerIndex == 1) &&
        (pending.defenderPlayerIndex == 0 || pending.defenderPlayerIndex == 1);
    if (!validIndex) {
      errors.add(
        CombatV1MatchStateInvariantError(
          code: CombatV1MatchStateInvariantErrorCode.pendingPlayerIndexOutOfRange,
          message: 'pendingAttackのplayerIndexが0/1の範囲外です'
              '（attacker:${pending.attackerPlayerIndex}, '
              'defender:${pending.defenderPlayerIndex}）',
        ),
      );
    } else {
      if (pending.attackerPlayerIndex == pending.defenderPlayerIndex) {
        errors.add(
          const CombatV1MatchStateInvariantError(
            code: CombatV1MatchStateInvariantErrorCode.pendingAttackerEqualsDefender,
            message: 'pendingAttackのattackerPlayerIndexとdefenderPlayerIndexが'
                '同じです',
          ),
        );
      }
      if (pending.attackerPlayerIndex != state.activePlayerIndex) {
        errors.add(
          CombatV1MatchStateInvariantError(
            code: CombatV1MatchStateInvariantErrorCode.pendingAttackerIndexMismatch,
            message: 'pendingAttack.attackerPlayerIndexがstate.'
                'activePlayerIndexと一致しません',
          ),
        );
      }
      final expectedDefender = state.activePlayerIndex == 0 ? 1 : 0;
      if (pending.defenderPlayerIndex != expectedDefender) {
        errors.add(
          CombatV1MatchStateInvariantError(
            code: CombatV1MatchStateInvariantErrorCode.pendingDefenderIndexMismatch,
            message: 'pendingAttack.defenderPlayerIndexが期待値と一致しません',
          ),
        );
      }
      // pending所有カードのzone/category判定は[_pendingOwnershipStatus]
      // （[pendingAttackOwnershipViolation]と共通）に委譲し、判定ロジックの
      // 重複を避ける（Phase 4 Codex再レビュー指摘H1残件対応）。
      final ownership = _pendingOwnershipStatus(state, pending);
      if (ownership.categoryMismatch) {
        errors.add(
          const CombatV1MatchStateInvariantError(
            code: CombatV1MatchStateInvariantErrorCode.pendingCardCategoryMismatch,
            message: 'pendingAttack.attackCardInstance.categoryがpending.'
                'categoryと一致しません',
          ),
        );
      }
      if (ownership.inAttackerZone) {
        errors.add(
          const CombatV1MatchStateInvariantError(
            code: CombatV1MatchStateInvariantErrorCode.pendingCardStillInAttackerZone,
            message: 'pendingAttackが所有するはずのカードが、攻撃側の'
                'hand/drawPile/discardPileにも存在します',
          ),
        );
      }
      if (ownership.inDefenderZone) {
        errors.add(
          const CombatV1MatchStateInvariantError(
            code: CombatV1MatchStateInvariantErrorCode.pendingCardInDefenderZone,
            message: 'pendingAttackが所有するカードのinstanceIdが、防御側の'
                'hand/drawPile/discardPileにも存在します',
          ),
        );
      }
    }
  }

  final allIds = <String>[
    ...state.playerA.hand.map((e) => e.instanceId),
    ...state.playerA.drawPile.map((e) => e.instanceId),
    ...state.playerA.discardPile.map((e) => e.instanceId),
    ...state.playerB.hand.map((e) => e.instanceId),
    ...state.playerB.drawPile.map((e) => e.instanceId),
    ...state.playerB.discardPile.map((e) => e.instanceId),
    if (pending != null) pending.attackCardInstance.instanceId,
  ];
  if (allIds.toSet().length != allIds.length) {
    errors.add(
      const CombatV1MatchStateInvariantError(
        code: CombatV1MatchStateInvariantErrorCode.duplicateCardInstanceId,
        message: '両playerの全カードゾーン（およびpending）を通じて'
            'instanceIdが重複しています',
      ),
    );
  }

  return CombatV1MatchStateInvariantResult(errors);
}
