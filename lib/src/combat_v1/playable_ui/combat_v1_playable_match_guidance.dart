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
import 'combat_v1_playable_ui_formatters.dart';

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
  // Playable 2A-6「10章 Guidance Label Consistency」——action名
  // （Stand Up/Rest）を独自の英語一文字列として複製せず、既存の
  // `combatV1PlayableActionKindLabel`（button labelそのもののSSOT）を
  // そのまま参照する。
  final standUpLabel = combatV1PlayableActionKindLabel(
    CombatV1LegalActionKind.standUp,
  );
  final restLabel = combatV1PlayableActionKindLabel(
    CombatV1LegalActionKind.rest,
  );
  return CombatV1PlayableMatchGuidance(
    kind: CombatV1PlayableGuidanceKind.discard,
    primary: '手札から1枚選んで捨ててください',
    secondary: isDown
        ? 'DOWN中 — 次の行動前に$standUpLabelまたは$restLabelが必要です'
        : '残したカードは攻撃やCounterに使用できます',
  );
}

/// COUNTER応答待ち（design doc「68章 Counter response」）。pending
/// 攻撃のHEAT・Direct PIN/Submission/Finisher typeは、Playable
/// 2A-3でCounter Prompt Sheet側（`_PendingAttackSummary`）へ追加した
/// ——このguidance panel（primary/secondary 1行ずつ）自体は簡潔さを
/// 維持し、具体的なtrait詳細はsheet側に譲る。unusable Counter理由の
/// 完全な列挙は引き続きscope外（Playable 2A-3「16章 Counter Card
/// Information」Non-Must）。
///
/// Review Findings Fix（Major）: `legalActions`（SSOT）にCounter
/// actionが実在しない場合（＝`CombatV1DeclineCounterAction`のみが
/// legal）、primary自体も「技を受ける」一本の進行のみを案内する——
/// 存在しないCounterという選択肢を「Counterするか」のように提示しては
/// いけない（design doc「68章 Action guidanceは実際に存在する
/// LegalActionだけを案内する」原則）。
CombatV1PlayableMatchGuidance _counterResponseGuidance(
  CombatV1PlayableMatchSnapshot snapshot,
  int humanPlayerIndex,
) {
  final hasUsableCounter = snapshot.legalActions.any(
    (action) =>
        action.kind == CombatV1LegalActionKind.counter &&
        action.actorPlayerIndex == humanPlayerIndex,
  );
  if (!hasUsableCounter) {
    return const CombatV1PlayableMatchGuidance(
      kind: CombatV1PlayableGuidanceKind.counterResponse,
      primary: '使用できるCounterがありません。技を受けます',
    );
  }
  return const CombatV1PlayableMatchGuidance(
    kind: CombatV1PlayableGuidanceKind.counterResponse,
    primary: 'Counterするか、技を受けるか選択してください',
    secondary: 'Counterすると攻撃を無効化できます',
  );
}

/// DOWN状態でのStand Up / Rest選択待ち（design doc「68章 DOWN — Stand
/// Up / Rest」）。REST回復量（`CombatV1RulesConfig.restHpRecovery`）は
/// Playable snapshotに公開されていないため、具体的な数値をUI側で複製
/// しない——既存`_ActionHint`（Rest: 'HPを回復してターン終了'）と同じ方針。
/// 文言も既存`_ActionHint`と完全一致させない（同じ意味の情報を別々の
/// 場所へ一字一句重複表示しない、design doc「68章 UI / Mobile」）。
CombatV1PlayableMatchGuidance _downDecisionGuidance() {
  // Playable 2A-6「10章 Guidance Label Consistency」——「Stand Up」/
  // 「Rest」という英語一文字列を独自に複製せず、button labelそのものの
  // SSOT（`combatV1PlayableActionKindLabel`）をそのまま参照する
  // （既存`_ActionHint`が使うlabelと必ず一致させる）。
  final standUpLabel = combatV1PlayableActionKindLabel(
    CombatV1LegalActionKind.standUp,
  );
  final restLabel = combatV1PlayableActionKindLabel(
    CombatV1LegalActionKind.rest,
  );
  return CombatV1PlayableMatchGuidance(
    kind: CombatV1PlayableGuidanceKind.downDecision,
    primary: 'DOWN中です。$standUpLabelか$restLabelかを選んでください',
    secondary: '$restLabel — HP回復・ターン終了',
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

/// Playable 2A-6「10章 Guidance Label Consistency」——以前はaction kind
/// ごとに独自の英語一文字列（'Technique'/'End Turn'）を複製していたが、
/// これは実際のbutton labelと表記が一致しない（button側は既に日本語
/// 「技を使う」「ターン終了」）うえ、プレイヤー向け操作文言は日本語を
/// 基本とする方針（design doc「Playable 2A-5 8章」）にも反していた。
/// 新しい行動名を作らず、既存`combatV1PlayableActionKindLabel`（button
/// labelそのもののSSOT）をそのまま列挙する。
String _actionPhasePrimary(Set<CombatV1LegalActionKind> humanKinds) {
  final labels = <String>[
    if (humanKinds.contains(CombatV1LegalActionKind.technique))
      combatV1PlayableActionKindLabel(CombatV1LegalActionKind.technique),
    if (humanKinds.contains(CombatV1LegalActionKind.pin))
      combatV1PlayableActionKindLabel(CombatV1LegalActionKind.pin),
    if (humanKinds.contains(CombatV1LegalActionKind.endTurn))
      combatV1PlayableActionKindLabel(CombatV1LegalActionKind.endTurn),
  ];
  if (labels.isEmpty) {
    // 通常到達しない防御的ケース（action phase・STAND・Human入力待ちなら
    // 少なくともEnd Turnは合法になるはず）。Combat ruleを推測せず、
    // 汎用文言に留める。
    return '選択できる行動を確認してください';
  }
  // labelの品詞が混在する（動詞句「技を使う」／名詞「PIN」「ターン終了」）
  // ため、「〜を選択できます」を後置して1文に合成すると不自然になる
  // （例:「技を使うを選択できます」）。button labelをそのまま列挙する
  // 表示に留める。
  return '選べる行動: ${labels.join(' ・ ')}';
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
  //
  // Review Findings Fix（Minor）: 満たされているのはFinisherのHEAT
  // 条件のみ——Finisher card所持・Energy・posture・その他LegalAction
  // 条件、CPU側のhidden hand内容までは断定できないため、「双方が
  // 使用条件を満たせます」（Finisherを実際に使用できるかのように
  // 誤読されうる）ではなく、HEAT条件についてのみ述べる。
  if (snapshot.sharedHeat >= snapshot.finisherHeatThreshold) {
    return 'FINISHER HEAT到達 — Shared HEATなので双方がHEAT条件を満たしています';
  }

  // 6. Opponent DOWN significance — PINがlegalでない場合のみ、ルール上
  // 安全な一般的表現に留める（「PINできます」と断定しない、design doc
  // 「68章 Opponent DOWN」）。
  if (snapshot.cpu.posture == CombatV1WrestlerPosture.down) {
    // Playable 2A-6「10章」——「Technique」という英語一文字列を、
    // 他の場所と同じ既存の日本語表記「技」に置き換える（新しい訳語を
    // 発明しない——`_SelectedTechniquePanel`の「使用する技」等、この
    // fileの外でも既に一貫して使われている表記）。
    return '相手はDOWN中 — PINや一部の技につながる重要な状態です';
  }

  // 7. Remaining Energy / continued attack — 既にこのターン中に
  // Techniqueを1回使用しており、かつ現在もTechniqueが合法な場合のみ
  // 表示する（「1ターン1Technique」という誤解を防ぐ。design doc「68章
  // Remaining Energy」）。合法性そのものはlegalActions（SSOT）から判定
  // するため、ENERGY残量を独自に再計算しない。
  if (humanKinds.contains(CombatV1LegalActionKind.technique) &&
      _hasUsedTechniqueThisTurn(snapshot, humanPlayerIndex)) {
    // Playable 2A-6「10章」——「Technique」という英語一文字列を独自に
    // 複製せず、button labelそのもののSSOT
    // （`combatV1PlayableActionKindLabel`＝「技を使う」）をそのまま
    // 名詞化して使う（「〜ことができます」で自然な文にする）。
    final techniqueLabel = combatV1PlayableActionKindLabel(
      CombatV1LegalActionKind.technique,
    );
    return '残りEnergyがあれば、このターンはさらに$techniqueLabelことができます';
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
