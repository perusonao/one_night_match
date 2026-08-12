/// Combat Ver.1 Playable 2A-2 — Win Path / Match Direction
/// （docs/design/combat_v1_playable_match_ui.md「70章 Match Direction」）。
///
/// Playable 2A-1の`combat_v1_playable_match_guidance.dart`が「今何を
/// 選べるか」（Current Action Guidance）を扱うのに対し、このfileは
/// 「なぜそれをするのか」「どこまで勝利に近づいているのか」（Win Path /
/// Match Direction）を、既存`CombatV1PlayableMatchSnapshot`から安全に
/// 導出できる情報だけを使って短い文章へ変換する、pure derivationレイヤー
/// （同じ「pure UI formatting helpers」方針——Combat ruleを一切再実装
/// しない・legality判定は常に`snapshot.legalActions`をそのまま参照する
/// だけ・独自のdamage計算やhidden情報の推測は行わない）。
///
/// Guidanceとの違い（責務分離）:
/// - Guidance: phase／pending state／postureから「今この瞬間に何を選べる
///   か」を導出する。Human入力待ちでない（CPU処理中）場合は`null`。
/// - Direction: HP／KOC／Posture／Shared HEATという「試合全体の状態」から
///   「勝利までの道筋のどこにいるか」を導出する。Human/CPUどちらの手番
///   かには依存しない（試合が`active`である限り、CPU処理中でも表示して
///   よい情報——「今何をするか」ではなく「この試合がどこへ向かっている
///   か」を示すため）。
library;

import '../combat_v1_enums.dart';
import '../combat_v1_legal_action.dart';
import '../playable/combat_v1_playable_match_snapshot.dart';

/// [CombatV1PlayableMatchDirection.primary]が属する大まかな種別
/// （design doc「70章 Direction Priority」）。Widget側が`is`/`switch`に
/// よるCombat rule再実装を行わずに済むよう、値そのものは表示スタイル分岐
/// （強調色など）専用の識別子として扱う——優先順位判定ロジック自体は
/// このenumではなく[combatV1PlayableDeriveMatchDirection]へ集約する。
enum CombatV1PlayableMatchDirectionKind {
  /// 相手KOCが0——次に成立するPIN／SUBMISSIONで決着する状態（最優先）。
  decisiveKoc,

  /// legalActionsにPINが実在する（今すぐPINを狙える）。
  pinOpportunity,

  /// 相手HPが[CombatV1PlayableMatchSnapshot.submissionHpThreshold]以下
  /// （0より大きい）——SUBMISSIONルートが視野に入っている。
  submissionRoute,

  /// 相手HPが0——ただしHP0だけでは決着しないことを明示する
  /// （design doc「7章 HP Communication」）。
  hpZeroClarify,

  /// 相手がDOWN中（PINがまだlegalでない場合）。
  opponentDownRoute,

  /// Human自身がDOWN中——相手のPIN条件の一部を満たしてしまう状態。
  humanDownRisk,

  /// Shared HEATがFinisher解禁閾値に到達済み。
  finisherRoute,

  /// 上記のいずれにも該当しない、試合序盤などの中立状態。
  neutral,
}

/// [combatV1PlayableDeriveMatchDirection]の出力——Widget-oriented UI model
/// （design doc「70章 Architecture」）。
///
/// Guidanceと同じく「primary 1文 + 必要時のみsecondary 1文」を維持する。
class CombatV1PlayableMatchDirection {
  const CombatV1PlayableMatchDirection({
    required this.kind,
    required this.primary,
    this.secondary,
  });

  final CombatV1PlayableMatchDirectionKind kind;

  /// 「勝利までの道筋のどこにいるか」（Win Path context）。
  final String primary;

  /// [primary]を補足する短い1文。該当する補足が無い場合は`null`。
  final String? secondary;
}

/// [snapshot]からHuman向けの[CombatV1PlayableMatchDirection]を導出する
/// （design doc「70章」）。
///
/// 試合が`active`でない場合（matchOver／safetyLimit／invariantViolation／
/// error）は`null`を返す——Result overlayが既に決着を説明するため、重複
/// 表示しない。Guidanceと異なり、CPU処理中（`isHumanInputRequired ==
/// false`）でも`null`にしない——「今何をするか」ではなく「この試合が
/// どこへ向かっているか」はHuman/CPUどちらの手番かに関係なく意味を持つ
/// 情報のため。
CombatV1PlayableMatchDirection? combatV1PlayableDeriveMatchDirection(
  CombatV1PlayableMatchSnapshot snapshot, {
  required int humanPlayerIndex,
}) {
  if (snapshot.status != CombatV1PlayableControllerStatus.active) {
    return null;
  }

  // 1. 相手KOCが0——`determinePinCountResult`/`determineSubmissionOutcome`
  // （`combat_v1_pin_rules.dart`/`combat_v1_submission_rules.dart`）は
  // KOC 0では支払い可能なcostが1件も無いため、次に成立したPIN／
  // SUBMISSIONは決着（3カウント／GIVE UP）になる。ここだけは「0」という
  // KOCの構造的な下限（負のKOCが存在しない）を根拠にした判定であり、
  // rules configのcost値（1/2/3）を複製するものではない。「必ず決着する」
  // と読める言い切りは避け、PIN／SUBMISSIONが実際に成立することを前提と
  // した表現にとどめる（Review Findings Fix、8章「Documentation
  // Wording」）——KOC 0はあくまで「PIN／SUBMISSIONが成立した場合に防御側
  // が耐えられない」状態であり、それ自体が試合を終わらせるわけではない。
  if (snapshot.cpu.koc <= 0) {
    return const CombatV1PlayableMatchDirection(
      kind: CombatV1PlayableMatchDirectionKind.decisiveKoc,
      primary: '相手はKOCを使い果たしています',
      secondary: '次に成立したPINまたはSubmissionで決着します',
    );
  }

  // 2. PIN opportunity——legalActionsにPINが実在する場合のみ断定する
  // （design doc「70章 LegalAction SSOT」）。
  //
  // Review Findings Fix（Minor）: 当初の文言「PINで相手のKOCを削り
  // ましょう」/「KOCが尽きると、PINやSubmissionで決着します」は、
  // Guidanceの「PIN可能 — 相手のKOCを削り、決着を狙えます」とほぼ同じ
  // 内容を繰り返していた。Guidanceは「今できること」（PINが選べる、
  // というlegal action SSOTに基づく事実）を担当するので、Directionは
  // 同じ事実を言い換えて反復せず、「KOCというresourceが何を意味するか
  // ／勝利までの位置づけ」（なぜPINが勝ち筋になるのか）だけを述べる。
  // PINのlegalityそのものはlegalActions（SSOT）のまま再計算しない。
  if (snapshot.isHumanInputRequired &&
      snapshot.phase == CombatV1MatchPhase.action &&
      snapshot.legalActions.any(
        (action) =>
            action.kind == CombatV1LegalActionKind.pin &&
            action.actorPlayerIndex == humanPlayerIndex,
      )) {
    return const CombatV1PlayableMatchDirection(
      kind: CombatV1PlayableMatchDirectionKind.pinOpportunity,
      primary: '相手のKOCを削るチャンスです',
      secondary: 'KOCが尽きると、成立したPINやSubmissionで決着します',
    );
  }

  // 3. Submission route——相手HPが公開済みの閾値
  // （`submissionHpThreshold`、Core実装は`submissionEligible`
  // `combat_v1_submission_rules.dart`）以下（かつ0より大きい）の場合。
  // HP0は次の4.で別途扱う（14章「HP0の扱い」、10.2章のFinisher
  // Submission特例と混同しない——ここではSUBMISSION自体への突入条件の
  // みを述べ、KOCによるESCAPE/GIVE UP判定は断定しない）。
  if (snapshot.cpu.hp > 0 && snapshot.cpu.hp <= snapshot.submissionHpThreshold) {
    return const CombatV1PlayableMatchDirection(
      kind: CombatV1PlayableMatchDirectionKind.submissionRoute,
      primary: '相手のHPが低下し、Submissionが視野に入っています',
      secondary: '成立してもKOC次第でEscapeされる場合があります',
    );
  }

  // 4. HP0 clarify——「HP 0 = 即敗北」という誤解を防ぐ（design doc「7章
  // HP Communication」）。通常決着にはPIN／Submissionの成立が必要
  // （HP0自体はSUBMISSION FINISHER特例10.2章の入力の一つに過ぎず、
  // 通常決着条件そのものではない）。
  if (snapshot.cpu.hp <= 0) {
    return const CombatV1PlayableMatchDirection(
      kind: CombatV1PlayableMatchDirectionKind.hpZeroClarify,
      primary: '相手のHPは0ですが、これだけでは決着しません',
      secondary: 'PINまたはSubmissionの成立が必要です',
    );
  }

  // 5. Opponent DOWN——PINがまだlegalでない場合（このターンでまだ技を
  // 成功させていない、またはCPUの手番でlegalActionsが非公開など）のみ
  // このrouteを述べる。2.のPIN opportunityと同時に成立する場合は2.が
  // 優先されるため、ここへは届かない。Playable 2A-1の「相手はDOWN中 —
  // PINや一部Techniqueにつながる重要な状態です」（現在の状態説明）とは
  // 文言を分け、ここでは「勝利への道筋」として述べる（design doc「11章
  // DOWN」の重複回避要件）。
  if (snapshot.cpu.posture == CombatV1WrestlerPosture.down) {
    return const CombatV1PlayableMatchDirection(
      kind: CombatV1PlayableMatchDirectionKind.opponentDownRoute,
      primary: 'DOWNからPINへ繋げれば、決着に近づきます',
    );
  }

  // 6. Human自身のDOWN——相手のPIN条件（相手がDOWN中であること）を
  // 満たしてしまう状態であることを述べる。PINの他の条件
  // （そのターン中の技成功・ROUGH不使用）までは断定しない。
  if (snapshot.human.posture == CombatV1WrestlerPosture.down) {
    return const CombatV1PlayableMatchDirection(
      kind: CombatV1PlayableMatchDirectionKind.humanDownRisk,
      primary: 'DOWNは、相手がPINを狙うための条件の一つです',
    );
  }

  // 7. Shared HEAT——Finisher解禁閾値は`snapshot.finisherHeatThreshold`を
  // そのまま参照する（UI側にmagic number 200を複製しない、design doc
  // 「68章」と同じ方針）。Playable 2A-1と重複させないよう、「HEAT到達」
  // ではなく「決着ルートが広がる」という勝ち筋の観点でのみ述べる。
  if (snapshot.sharedHeat >= snapshot.finisherHeatThreshold) {
    return const CombatV1PlayableMatchDirection(
      kind: CombatV1PlayableMatchDirectionKind.finisherRoute,
      primary: 'FINISHERが解禁 — 決着ルートの選択肢が広がります',
    );
  }

  // 8. Neutral——上記のいずれにも該当しない試合序盤など。win pathの全体像
  // （design doc「5章 Win Path Concept」の図）を一度だけ簡潔に示す。
  return const CombatV1PlayableMatchDirection(
    kind: CombatV1PlayableMatchDirectionKind.neutral,
    primary: 'Techniqueで攻めてDOWNを作り、決着を目指しましょう',
  );
}
