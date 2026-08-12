/// Combat Ver.1 Playable 2A-1 — Match Guidance
/// （docs/design/combat_v1_playable_match_ui.md「68章 Match Guidance」）。
///
/// 「今何が押せるか」（既存LegalAction/Widget）だけでなく、「なぜその行動を
/// 選ぶのか」「次に何を狙うべき状態なのか」を、既存`CombatV1PlayableMatchSnapshot`
/// から安全に導出できる情報だけを使って短い文章へ変換する、pure
/// derivationレイヤー。
///
/// このfileはCombat ruleを一切再実装しない——legality判定は常に
/// `snapshot.legalActions`（唯一のSSOT）をそのまま参照するだけで、独自の
/// 合法性判定・damage計算・CPU AI・hidden情報の推測は行わない
/// （`combat_v1_playable_ui_formatters.dart`と同じ「pure UI formatting
/// helpers」方針、副作用なし・Flutter widget treeを構築しない）。
///
/// 攻略AIではない——「このカードを使え」「Counterした方が得」のような
/// recommendationは一切生成しない。既存ルールから確実に導ける
/// rule-aware contextのみを返す（design doc「68章 Guidance Priority」）。
library;

import '../combat_v1_enums.dart';
import '../combat_v1_legal_action.dart';
import '../playable/combat_v1_playable_match_snapshot.dart';

/// [CombatV1PlayableMatchGuidance.primary]が属する大まかな段階
/// （design doc「68章 Current Action Guidance」）。Widget側が
/// `is`/`switch`によるCombat rule再実装を行わずに済むよう、値そのものは
/// 表示スタイル分岐（強調色など）専用の識別子として扱う——優先順位判定
/// ロジック自体はこのenumではなく[combatV1PlayableDeriveMatchGuidance]へ
/// 集約する。
enum CombatV1PlayableGuidanceKind {
  /// 強制discard待ち（`phase == discard`）。
  discard,

  /// COUNTER応答待ち（`phase == counterResponsePending`、防御側がHuman）。
  counterResponse,

  /// DOWN状態でのStand Up / Rest選択待ち（`phase == action`、Human DOWN）。
  downDecision,

  /// 通常のaction phase（Human STAND、Technique/PIN/End Turnの選択）。
  action,
}

/// [combatV1PlayableDeriveMatchGuidance]の出力——Widget-oriented UI model
/// （design doc「68章 Architecture」）。
///
/// 「1行primary + 必要時のみ1行secondary」を維持するため、[primary]は
/// 常に1文、[secondary]は最大1文のみ（複数のcontext hintを同時に返さない
/// ——優先順位は導出関数側で1件へ絞り込み済み）。
class CombatV1PlayableMatchGuidance {
  const CombatV1PlayableMatchGuidance({
    required this.kind,
    required this.primary,
    this.secondary,
  });

  final CombatV1PlayableGuidanceKind kind;

  /// 「今プレイヤーが何をする段階なのか」（Current Action Guidance）。
  final String primary;

  /// 「その状態にはどういう意味があるのか」（Context Hint）。該当する
  /// context hintが無い場合は`null`（Widget側は何も表示しない）。
  final String? secondary;
}

/// [snapshot]からHuman向けの[CombatV1PlayableMatchGuidance]を導出する
/// （design doc「68章」）。
///
/// Human入力待ちでない場合（CPU処理中・試合終了）は`null`を返す——
/// CPU行動中にHuman向けの操作案内を誤って表示しないため（design doc
/// 「Opponent / CPU processing」）、また試合終了後はResult overlayが
/// 全画面を覆い、既存`_ActorAndRecentPanel`の"試合終了"表示で十分なため
/// （重複表示を避ける）。
CombatV1PlayableMatchGuidance? combatV1PlayableDeriveMatchGuidance(
  CombatV1PlayableMatchSnapshot snapshot, {
  required int humanPlayerIndex,
}) {
  if (snapshot.status != CombatV1PlayableControllerStatus.active) {
    return null;
  }
  if (!snapshot.isHumanInputRequired) {
    return null;
  }

  switch (snapshot.phase) {
    case CombatV1MatchPhase.discard:
      return _discardGuidance(snapshot);
    case CombatV1MatchPhase.counterResponsePending:
      return _counterResponseGuidance(snapshot, humanPlayerIndex);
    case CombatV1MatchPhase.action:
      return snapshot.human.posture == CombatV1WrestlerPosture.down
          ? _downDecisionGuidance()
          : _actionGuidance(snapshot, humanPlayerIndex);
    case CombatV1MatchPhase.setup:
    case CombatV1MatchPhase.turnEnd:
      // Command APIが返す`phase`にはこの2値は現れない（Playable 1A
      // snapshot doc「setup/turnEndは概念上のフェーズ」参照）。到達しない
      // 防御的ケースとして何も案内しない。
      return null;
  }
}

/// Discard phase（design doc「68章 Discard」）。強制discardであることを
/// 明示する。Human DOWN（前ターンの被弾でまだStand Up/Restしていない）の
/// 場合は、Discard中に「今すぐStand Upできる」と誤解させないよう、実際の
/// phase順序（Draw → 強制Discard → DOWN decision）に沿った文言にする。
CombatV1PlayableMatchGuidance _discardGuidance(
  CombatV1PlayableMatchSnapshot snapshot,
) {
  final isDown = snapshot.human.posture == CombatV1WrestlerPosture.down;
  return CombatV1PlayableMatchGuidance(
    kind: CombatV1PlayableGuidanceKind.discard,
    primary: '手札から1枚選んで捨ててください',
    secondary: isDown
        ? 'DOWN中 — 次の行動前にStand UpまたはRestが必要です'
        : '残したカードは攻撃やCounterに使用できます',
  );
}

/// COUNTER応答待ち（design doc「68章 Counter response」）。Counter
/// outcome詳細・pending攻撃のHEAT・Direct PIN/Submission/Finisher
/// type・unusable Counter理由は今回のscope外（Playable 2A-4予定）。
CombatV1PlayableMatchGuidance _counterResponseGuidance(
  CombatV1PlayableMatchSnapshot snapshot,
  int humanPlayerIndex,
) {
  final hasUsableCounter = snapshot.legalActions.any(
    (action) =>
        action.kind == CombatV1LegalActionKind.counter &&
        action.actorPlayerIndex == humanPlayerIndex,
  );
  return CombatV1PlayableMatchGuidance(
    kind: CombatV1PlayableGuidanceKind.counterResponse,
    primary: 'Counterするか、技を受けるか選択してください',
    // legalActions（SSOT）にCounter actionが実在する場合のみ、ルール上
    // 確実な効果を補足する。使用できるCounterが無い場合に「無効化
    // できます」と案内すると誤解させるため出さない。
    secondary: hasUsableCounter ? 'Counterすると攻撃を無効化できます' : null,
  );
}

/// DOWN状態でのStand Up / Rest選択待ち（design doc「68章 DOWN — Stand
/// Up / Rest」）。REST回復量（`CombatV1RulesConfig.restHpRecovery`）は
/// Playable snapshotに公開されていないため、具体的な数値をUI側で複製
/// しない——既存`_ActionHint`（Rest: 'HPを回復してターン終了'）と同じ方針。
/// 文言も既存`_ActionHint`と完全一致させない（同じ意味の情報を別々の
/// 場所へ一字一句重複表示しない、design doc「68章 UI / Mobile」）。
CombatV1PlayableMatchGuidance _downDecisionGuidance() {
  return const CombatV1PlayableMatchGuidance(
    kind: CombatV1PlayableGuidanceKind.downDecision,
    primary: 'DOWN中です。Stand Upして攻撃を続けるか、Restできます',
    secondary: 'Rest — HP回復・ターン終了',
  );
}

/// 通常のaction phase（design doc「68章 Action phase」）。primaryは
/// `snapshot.legalActions`（唯一のSSOT）に実在するkindだけを列挙する
/// ——PIN/Techniqueが合法でない場合にそれらを案内してはいけない。
/// secondaryは、優先順位（design doc「68章 Guidance Priority」）に沿って
/// 最大1件のcontext hintのみを返す。
CombatV1PlayableMatchGuidance _actionGuidance(
  CombatV1PlayableMatchSnapshot snapshot,
  int humanPlayerIndex,
) {
  final humanKinds = <CombatV1LegalActionKind>{
    for (final action in snapshot.legalActions)
      if (action.actorPlayerIndex == humanPlayerIndex) action.kind,
  };
  return CombatV1PlayableMatchGuidance(
    kind: CombatV1PlayableGuidanceKind.action,
    primary: _actionPhasePrimary(humanKinds),
    secondary: _actionPhaseContextHint(snapshot, humanPlayerIndex, humanKinds),
  );
}

String _actionPhasePrimary(Set<CombatV1LegalActionKind> humanKinds) {
  final labels = <String>[
    if (humanKinds.contains(CombatV1LegalActionKind.technique)) 'Technique',
    if (humanKinds.contains(CombatV1LegalActionKind.pin)) 'PIN',
    if (humanKinds.contains(CombatV1LegalActionKind.endTurn)) 'End Turn',
  ];
  if (labels.isEmpty) {
    // 通常到達しない防御的ケース（action phase・STAND・Human入力待ちなら
    // 少なくともEnd Turnは合法になるはず）。Combat ruleを推測せず、
    // 汎用文言に留める。
    return '選択できる行動を確認してください';
  }
  if (labels.length == 1) {
    return '${labels.single}を選択できます';
  }
  final head = labels.sublist(0, labels.length - 1).join('、');
  return '$head、または${labels.last}を選択できます';
}

/// Guidance Priority（design doc「68章」、優先順位4〜7）に沿って、
/// action phase中の最大1件のcontext hintを選ぶ。複数該当しても1件のみ
/// 返す——画面を説明文だらけにしないため（design doc「Guidance
/// Priority」）。
String? _actionPhaseContextHint(
  CombatV1PlayableMatchSnapshot snapshot,
  int humanPlayerIndex,
  Set<CombatV1LegalActionKind> humanKinds,
) {
  // 4. PIN opportunity — legalActionsにPINが実在する場合のみ「PIN可能」と
  // 断定する（design doc「68章 PIN opportunity」、LegalAction SSOT）。
  if (humanKinds.contains(CombatV1LegalActionKind.pin)) {
    return 'PIN可能 — 相手のKOCを削り、決着を狙えます';
  }

  // 5. Shared HEAT near / at Finisher unlock — 閾値はsnapshot自身の
  // `finisherHeatThreshold`を参照する（UI側にmagic number 200を複製
  // しない、design doc「68章 Shared HEAT」）。
  if (snapshot.sharedHeat >= snapshot.finisherHeatThreshold) {
    return 'FINISHER解禁 — Shared HEATなので双方が使用条件を満たせます';
  }

  // 6. Opponent DOWN significance — PINがlegalでない場合のみ、ルール上
  // 安全な一般的表現に留める（「PINできます」と断定しない、design doc
  // 「68章 Opponent DOWN」）。
  if (snapshot.cpu.posture == CombatV1WrestlerPosture.down) {
    return '相手はDOWN中 — PINや一部Techniqueにつながる重要な状態です';
  }

  // 7. Remaining Energy / continued attack — 既にこのターン中に
  // Techniqueを1回使用しており、かつ現在もTechniqueが合法な場合のみ
  // 表示する（「1ターン1Technique」という誤解を防ぐ。design doc「68章
  // Remaining Energy」）。合法性そのものはlegalActions（SSOT）から判定
  // するため、ENERGY残量を独自に再計算しない。
  if (humanKinds.contains(CombatV1LegalActionKind.technique) &&
      _hasUsedTechniqueThisTurn(snapshot, humanPlayerIndex)) {
    return '残りEnergyがあれば、このターンはさらにTechniqueを使用できます';
  }

  return null;
}

/// [snapshot.recentObservations]（bounded、hidden-safeなpublic
/// observation）から、現在のターン中にHumanが既にTechniqueを使用したかを
/// 判定する。Human自身の行動履歴のみを見るため、hidden information
/// 違反にならない。
bool _hasUsedTechniqueThisTurn(
  CombatV1PlayableMatchSnapshot snapshot,
  int humanPlayerIndex,
) {
  for (final observation in snapshot.recentObservations) {
    if (observation.turnNumber == snapshot.turnNumber &&
        observation.actorPlayerIndex == humanPlayerIndex &&
        observation.action.kind == CombatV1LegalActionKind.technique) {
      return true;
    }
  }
  return false;
}
