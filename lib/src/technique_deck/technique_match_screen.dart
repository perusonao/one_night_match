import 'package:flutter/material.dart';

import '../wrestler_editor/models.dart'
    show MoveAttribute, WrestlerDefinition, moveAttributeLabel;
import '../wrestler_editor/repository.dart';
import 'technique_deck_deck.dart';
import 'technique_deck_defaults.dart';
import 'technique_deck_generator.dart';
import 'technique_deck_models.dart';
import 'technique_deck_storage.dart';
import 'technique_match_state.dart';

/// Technique Deck Rules Phase 3〜7: 最初のプレイアブル画面「Technique Match」。
///
/// スタンド／ダウン／疲労・休息・ターン進行・HP／HEAT表示・手札／山札・
/// エネルギーセット・技の応酬（攻撃宣言→返技判定→成功なら攻守交代して連続
/// 攻撃）・フォール／ギブアップの回避判定（キックアウト／ロープブレイク
/// カード・HP消費・諦めによる決着。返技エネルギーはラリー中の返技専用の
/// リソースで、決着回避には使えない）・フィニッシャー（発動条件を満たした
/// 場合のみ宣言可能→防御側のエスケープ／リバーサルによる発動キャンセル→
/// 成立→特殊キックアウトによる脱出、いずれも失敗すれば残りHPに関係なく
/// 即勝利）を扱う。CPUは実装しない（Phase 8）。エネルギーセットはラリー中・
/// 決着判定待ち・フィニッシャー判定待ちの間は行えない。現行のclassic／energy
/// モード・Deck Simulator・レスラーエディタ・Technique Deck Builderの挙動には
/// 一切影響しない。
///
/// 【UI全面リデザイン（プレイフィール改善、ルール・エンジンは無変更）】
/// ユーザー指示により「デバッグ画面」から「ゲーム画面」への全面リデザインを
/// 行った。ロジックは一切変更していない（`TechniqueMatchEngine`の呼び出し
/// パターンは従来のまま）。主な変更点:
/// - 手札カードをタップで即実行（技エネルギー不足など個別に使用不可な
///   カードのみ、詳細ダイアログ（従来の`_showHandCardSheet`）を経由する。
///   長押しでは常に詳細ダイアログを開ける）
/// - 「ダウンする」ボタンを廃止し、「休息」1つに統合（スタンド中に休息を
///   押すと`goDown`→`rest`を内部で連続実行する。エンジン側の`goDown`/
///   `rest`メソッドはどちらも無変更で、呼び出し方のみUI側で変えている）
/// - プレイヤーカードをコンパクト化し、詳細情報（山札・捨て札・除外・
///   デッキ由来メモ）は折りたたみ式にした
/// - 現在すべき行動を1文で画面上部に大きく表示し、5段階ステッパーは補助
///   表示に縮小した
/// - 中央に「リング」パネルを設け、直近の技成立・返技・攻守交代等を
///   ハイライト表示する
/// - 進行ログを折りたたみ式にした（初期状態は直近数件のプレビューのみ）
/// - 色の役割を統一（緑=使用可能／スタンド、オレンジ=ダウン、赤=危険、
///   金=フィニッシャー・強調、グレー=使用不可・補助情報）
/// - 開発中バナー・デッキ由来メモ等のデバッグ表示は試合画面から除去し
///   （デッキ由来メモは折りたたみ内へ移動）、セットアップ画面にのみ残した
///
/// ダイアログの文言・ボタンウィジェット型（`FilledButton`/`OutlinedButton`）
/// は既存テストが依存しているため維持している。カードタップ操作の変更に
/// 伴い、`test/technique_match_screen_test.dart`はユーザー指示により
/// 新しい操作フローに合わせて更新した（`technique_match_state_test.dart`
/// 等のゲームロジックのテストは無改修）。
class TechniqueMatchScreen extends StatefulWidget {
  const TechniqueMatchScreen({
    super.key,
    this.wrestlerRepository,
    this.deckRepository,
    this.catalog,
  });

  final LocalWrestlerRepository? wrestlerRepository;
  final TechniqueDeckRepository? deckRepository;
  final TechniqueDeckCardCatalog? catalog;

  @override
  State<TechniqueMatchScreen> createState() => _TechniqueMatchScreenState();
}

// ============================================================
// 色の役割を統一（⑧）: 緑=使用可能／スタンド、オレンジ=ダウン、
// 赤=危険・不可、金=フィニッシャー・強調、グレー=補助・不可。
// ============================================================
const _bg = Color(0xff1c1420);
const _panelBg = Color(0xff251b2c);
const _gold = Color(0xffffc857);
const _green = Color(0xff5cd68b);
const _orange = Color(0xffffab5c);
const _red = Color(0xffff5c5c);
const _dim = Colors.white38;

/// HEATバーの表示専用の目安上限（仕様上のHEAT上限は未決定、open questions
/// 11番）。ルール上の意味は持たない、UIのバー表示のためだけの定数。
const _heatVisualMax = 100;

class _TechniqueMatchScreenState extends State<TechniqueMatchScreen> {
  late final LocalWrestlerRepository wrestlerRepository =
      widget.wrestlerRepository ?? LocalWrestlerRepository();
  late final TechniqueDeckRepository deckRepository =
      widget.deckRepository ?? LocalTechniqueDeckRepository();
  late final TechniqueDeckCardCatalog catalog =
      widget.catalog ?? buildProvisionalTechniqueDeckCatalog();

  List<WrestlerDefinition>? wrestlers;
  WrestlerDefinition? wrestlerA;
  WrestlerDefinition? wrestlerB;
  TechniqueMatchState? matchState;
  bool starting = false;
  String? deckSourceNoteA;
  String? deckSourceNoteB;

  bool _detailExpandedA = false;
  bool _detailExpandedB = false;
  bool _logExpanded = false;

  @override
  void initState() {
    super.initState();
    wrestlerRepository.loadAll().then((items) {
      if (!mounted) return;
      setState(() {
        wrestlers = items;
        if (items.isNotEmpty) wrestlerA = items.first;
        if (items.length > 1) wrestlerB = items[1];
      });
    });
  }

  Future<(TechniqueDeckDefinition, String)> _resolveDeck(
    WrestlerDefinition wrestler,
  ) async {
    final saved = await deckRepository.loadAll();
    final match = saved.where((r) => r.wrestlerId == wrestler.id).toList();
    if (match.isNotEmpty) {
      return (
        match.first.toDeckDefinition(),
        '保存済みデッキ「${match.first.name}」を使用',
      );
    }
    final result =
        TechniqueDeckAutoGenerator(
          config: TechniqueDeckGenerationConfig(
            seed: DateTime.now().millisecondsSinceEpoch,
          ),
        ).generate(
          catalog: catalog,
          wrestlerId: wrestler.id,
          deckId:
              '${wrestler.id}_temp_${DateTime.now().millisecondsSinceEpoch}',
          deckName: '${wrestler.name} 仮デッキ（自動生成）',
        );
    return (result.deck, '保存済みデッキが無いため仮デッキを自動生成');
  }

  Future<void> _startMatch() async {
    final a = wrestlerA;
    final b = wrestlerB;
    if (a == null || b == null) return;
    setState(() => starting = true);
    final (deckA, noteA) = await _resolveDeck(a);
    final (deckB, noteB) = await _resolveDeck(b);
    if (!mounted) return;
    setState(() {
      deckSourceNoteA = noteA;
      deckSourceNoteB = noteB;
      matchState = TechniqueMatchEngine.start(
        wrestlerAId: a.id,
        wrestlerAName: a.name,
        wrestlerAMaxHp: a.maxHp,
        deckA: deckA,
        wrestlerBId: b.id,
        wrestlerBName: b.name,
        wrestlerBMaxHp: b.maxHp,
        deckB: deckB,
      );
      starting = false;
    });
  }

  void _setEnergy(TechniqueDeckEntry entry) {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.setEnergy(state, entry, catalog);
    setState(() => matchState = result.state);
  }

  Future<void> _declareAttack(TechniqueDeckEntry entry) async {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.declareAttack(state, entry, catalog);
    setState(() => matchState = result.state);
    if (result.success) {
      await _showDefenseDecisionDialog();
    }
  }

  void _counterAttack() {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.counterAttack(state, catalog);
    setState(() => matchState = result.state);
  }

  Future<void> _resolveHit() async {
    final state = matchState;
    if (state == null) return;
    final resolved = TechniqueMatchEngine.resolveHit(state, catalog);
    setState(() => matchState = resolved);
    if (resolved.pendingEscape != null) {
      await _showEscapeDecisionDialog();
    }
  }

  void _endRally() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.endRally(state));
  }

  /// 攻撃が宣言され防御側の返技判定を待っている間、決定するまで閉じられない
  /// ダイアログを表示する（読み合いの核: 返技エネルギーが足りていても
  /// 「返技しない」選択が常にできる）。
  Future<void> _showDefenseDecisionDialog() async {
    final state = matchState;
    final pending = state?.pendingAttack;
    if (state == null || pending == null) return;
    final card = catalog.findTechniqueById(pending.cardId);
    if (card == null) return;
    final attacker = state.playerAt(pending.attackerIndex);
    final defender = state.playerAt(1 - pending.attackerIndex);
    final check = TechniqueMatchEngine.checkCounterEligibility(state, catalog);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('[Chain ${pending.chain}] ${defender.wrestlerName}の返技判定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${attacker.wrestlerName}が「${card.name}」を使用'),
            Text(
              '威力: ${card.power} ・ HEAT+${card.heatDelta}'
              '${card.causesDown ? " ・ 成立するとダウン" : ""}',
            ),
            if (card.reversalEnergyCost.values.any((v) => v > 0))
              Text(
                '返技に必要なエネルギー: ${card.reversalEnergyCost.entries.where((e) => e.value > 0).map((e) => '${moveAttributeLabel(e.key)}${e.value}').join('・')}',
              )
            else
              const Text('この技には返技エネルギーの設定がありません（返技不可）。'),
            const SizedBox(height: 8),
            const Text(
              '返技すると攻守が交代し、ダメージ・HEAT・ダウンは一切発生しません。'
              '返技しないと技が成立し、ラリーはここで終了します。',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            if (!check.canCounter)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  check.reason ?? '返技できません。',
                  style: const TextStyle(color: _red),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _resolveHit();
            },
            child: const Text('返技しない'),
          ),
          FilledButton(
            onPressed: check.canCounter
                ? () {
                    _counterAttack();
                    Navigator.pop(dialogContext);
                  }
                : null,
            child: const Text('返技する'),
          ),
        ],
      ),
    );
  }

  void _escapeWithDefenseCard(TechniqueDeckEntry entry) {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.escapeWithDefenseCard(
      state,
      entry,
      catalog,
    );
    setState(() => matchState = result.state);
  }

  void _escapeWithHp() {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.escapeWithHp(state, catalog);
    setState(() => matchState = result.state);
  }

  void _concede() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.concede(state));
  }

  Future<void> _declareFinisher(TechniqueDeckEntry entry) async {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.declareFinisher(state, entry, catalog);
    setState(() => matchState = result.state);
    if (result.success) {
      await _showFinisherResponseDialog();
    }
  }

  void _cancelFinisher(TechniqueDeckEntry entry) {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.cancelFinisher(state, entry, catalog);
    setState(() => matchState = result.state);
  }

  Future<void> _resolveFinisher() async {
    final state = matchState;
    if (state == null) return;
    final resolved = TechniqueMatchEngine.resolveFinisher(state, catalog);
    setState(() => matchState = resolved);
    if (resolved.pendingFinisher?.stage == TechniqueFinisherStage.escapePending) {
      await _showFinisherEscapeDialog();
    }
  }

  void _escapeFinisherWithCard(TechniqueDeckEntry entry) {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.escapeFinisher(state, entry, catalog);
    setState(() => matchState = result.state);
  }

  void _concedeFinisher() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.concedeFinisher(state));
  }

  /// フィニッシャーが宣言され、防御側の発動キャンセル判定を待っている間、
  /// 決定するまで閉じられないダイアログを表示する。エスケープ／リバーサル
  /// カードのいずれかでキャンセルするか、キャンセルしない（成立させる）かを
  /// 選ぶ。通常の返技エネルギーではキャンセルできない（ユーザー指示）。
  Future<void> _showFinisherResponseDialog() async {
    final state = matchState;
    final pending = state?.pendingFinisher;
    if (state == null ||
        pending == null ||
        pending.stage != TechniqueFinisherStage.responsePending) {
      return;
    }
    final card = catalog.findTechniqueById(pending.entry.cardId);
    if (card == null) return;
    final attacker = state.playerAt(pending.attackerIndex);
    final defender = state.playerAt(pending.defenderIndex);

    final cancelEntries = defender.hand
        .where(
          (entry) =>
              TechniqueMatchEngine.canCancelFinisher(state, entry, catalog).canCancel,
        )
        .toList();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('${defender.wrestlerName}の発動キャンセル判定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${attacker.wrestlerName}が「${card.name}」を宣言！フィニッシャー発動！'),
            Text('威力: ${card.power} ・ HEAT+${card.heatDelta}'),
            const SizedBox(height: 4),
            const Text(
              '通常の返技エネルギーではキャンセルできません。エスケープ／'
              'リバーサルカードが無い（または使わない）場合は成立し、'
              '特殊キックアウトカードでの脱出判定に進みます。',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (cancelEntries.isNotEmpty) ...[
              const Text(
                'エスケープ／リバーサルカードを使う:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in cancelEntries)
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _cancelFinisher(entry);
                      },
                      child: Text(
                        catalog.findDefenseCardById(entry.cardId)?.name ??
                            entry.cardId,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _resolveFinisher();
              },
              child: const Text('キャンセルしない'),
            ),
          ],
        ),
      ),
    );
  }

  /// フィニッシャーが成立し、防御側の脱出判定を待っている間、決定するまで
  /// 閉じられないダイアログを表示する。特殊キックアウトカードでのみ脱出でき、
  /// 脱出できなければ残りHPに関係なく攻撃側の即勝利になる。
  Future<void> _showFinisherEscapeDialog() async {
    final state = matchState;
    final pending = state?.pendingFinisher;
    if (state == null ||
        pending == null ||
        pending.stage != TechniqueFinisherStage.escapePending) {
      return;
    }
    final card = catalog.findTechniqueById(pending.entry.cardId);
    if (card == null) return;
    final defender = state.playerAt(pending.defenderIndex);

    final escapeEntries = defender.hand
        .where(
          (entry) =>
              TechniqueMatchEngine.canEscapeFinisher(state, entry, catalog).canEscape,
        )
        .toList();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('${defender.wrestlerName}の脱出判定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${card.name}」が成立した！脱出できなければ敗北する。'),
            const SizedBox(height: 4),
            const Text(
              '特殊キックアウトカードでのみ脱出できます。通常キックアウト・'
              'ロープブレイク・HP消費・返技エネルギーはいずれも使えません。',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (escapeEntries.isNotEmpty) ...[
              const Text(
                '特殊キックアウトカードを使う:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in escapeEntries)
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _escapeFinisherWithCard(entry);
                      },
                      child: Text(
                        catalog.findDefenseCardById(entry.cardId)?.name ??
                            entry.cardId,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _concedeFinisher();
              },
              child: const Text('諦める（敗北を認める）'),
            ),
          ],
        ),
      ),
    );
  }

  /// 技が成立しフォール／ギブアップの回避判定待ちの間、決定するまで閉じられ
  /// ないダイアログを表示する。キックアウト／ロープブレイクカード・HP消費の
  /// いずれかで回避するか、諦めて敗北を認めるかを選ぶ（返技エネルギーは
  /// ラリー中の返技専用のリソースであり、決着回避には使えない。ユーザー指示
  /// によるPhase 6完了後の仕様変更）。
  Future<void> _showEscapeDecisionDialog() async {
    final state = matchState;
    final pending = state?.pendingEscape;
    if (state == null || pending == null) return;
    final card = catalog.findTechniqueById(pending.cardId);
    if (card == null) return;
    final attacker = state.playerAt(pending.attackerIndex);
    final defender = state.playerAt(pending.defenderIndex);
    final kindLabel = pending.kind == TechniqueEscapeKind.fall ? 'フォール' : 'ギブアップ';

    final defenseEntries = defender.hand
        .where(
          (entry) =>
              TechniqueMatchEngine.canEscapeWithDefenseCard(
                state,
                entry,
                catalog,
              ).canEscape,
        )
        .toList();
    final hpCheck = TechniqueMatchEngine.canEscapeWithHp(state, catalog);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('${defender.wrestlerName}の$kindLabel回避判定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${attacker.wrestlerName}の「${card.name}」が成立！$kindLabelの危機。'),
            const SizedBox(height: 4),
            const Text(
              'いずれの方法でも回避できない（または選ばない）場合は諦めるしかありません。',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (defenseEntries.isNotEmpty) ...[
              Text(
                pending.kind == TechniqueEscapeKind.fall
                    ? 'キックアウトカードを使う:'
                    : 'ロープブレイクカードを使う:',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in defenseEntries)
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _escapeWithDefenseCard(entry);
                      },
                      child: Text(
                        catalog.findDefenseCardById(entry.cardId)?.name ??
                            entry.cardId,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: hpCheck.canEscape
                  ? () {
                      Navigator.pop(dialogContext);
                      _escapeWithHp();
                    }
                  : null,
              child: const Text('HPを消費して耐える'),
            ),
            if (!hpCheck.canEscape)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  hpCheck.reason ?? '',
                  style: const TextStyle(fontSize: 11, color: _red),
                ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _concede();
              },
              child: const Text('諦める（敗北を認める）'),
            ),
          ],
        ),
      ),
    );
  }

  /// カードの詳細ダイアログ（従来のタップ時ダイアログ）。ワンタップ実行が
  /// できない（個別に使用不可、または防御札等の受動カード）場合の主タップ、
  /// および常設の長押し操作から呼ばれる。
  Future<void> _showHandCardSheet(TechniqueDeckEntry entry) async {
    final state = matchState;
    if (state == null) return;
    final technique = catalog.findTechniqueById(entry.cardId);
    final energy = catalog.findEnergyById(entry.cardId);

    if (energy != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(energy.name),
          content: Text(
            '「${energy.name}」（${moveAttributeLabel(energy.attribute)}）を'
            'エネルギーとしてセットします。手札から出ると捨て札には入らず、'
            '以後ずっと使用可能な資源として残ります。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                _setEnergy(entry);
                Navigator.pop(dialogContext);
              },
              child: const Text('セットする'),
            ),
          ],
        ),
      );
      return;
    }

    if (technique != null && technique.hasFinisherEffect) {
      final check = TechniqueMatchEngine.canDeclareFinisher(state, entry, catalog);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${technique.name}（フィニッシャー）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '威力: ${technique.power} ・ HEAT: ${technique.heatDelta}',
                style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
              ),
              Text('対象状態: ${_targetStateLabel(technique.targetState)}'),
              if (technique.attackEnergyCost.values.any((v) => v > 0))
                Text(
                  '必要エネルギー: ${technique.attackEnergyCost.entries.where((e) => e.value > 0).map((e) => '${moveAttributeLabel(e.key)}${e.value}').join('・')}',
                ),
              const SizedBox(height: 8),
              const Text(
                '通常の返技エネルギーでは止められません。防御側はエスケープ／'
                'リバーサルカードで発動をキャンセルするか、成立後は特殊'
                'キックアウトカードで脱出するしかありません。脱出できなければ'
                '残りHPに関係なく即勝利します。',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              if (!check.canDeclare)
                Text(
                  check.reason ?? '宣言できません。',
                  style: const TextStyle(color: _red),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: check.canDeclare
                  ? () {
                      Navigator.pop(dialogContext);
                      _declareFinisher(entry);
                    }
                  : null,
              child: const Text('宣言する'),
            ),
          ],
        ),
      );
      return;
    }

    if (technique != null) {
      final check = TechniqueMatchEngine.canDeclareAttack(
        state,
        entry,
        catalog,
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(technique.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('威力: ${technique.power} ・ HEAT: ${technique.heatDelta}'),
              Text(
                '必要レベル: Lv.${technique.minimumLevel} ・ '
                '対象状態: ${_targetStateLabel(technique.targetState)}',
              ),
              if (technique.attackEnergyCost.values.any((v) => v > 0))
                Text(
                  '必要エネルギー: ${technique.attackEnergyCost.entries.where((e) => e.value > 0).map((e) => '${moveAttributeLabel(e.key)}${e.value}').join('・')}',
                ),
              if (technique.reversalEnergyCost.values.any((v) => v > 0))
                Text(
                  '相手の返技に必要なエネルギー: ${technique.reversalEnergyCost.entries.where((e) => e.value > 0).map((e) => '${moveAttributeLabel(e.key)}${e.value}').join('・')}',
                ),
              if (technique.causesDown) const Text('成立すると相手をダウンさせます。'),
              // hasFinisherEffectを持つ技はこのダイアログには到達しない
              // （上のフィニッシャー専用ブロックで処理される）。
              if (technique.hasPinEffect && technique.hasSubmissionEffect)
                const Text(
                  '成立するとフォール判定が発生します'
                  '（ギブアップ効果も持ちますが、フォールが優先されます）。',
                  style: TextStyle(color: _gold, fontSize: 12),
                )
              else if (technique.hasPinEffect)
                const Text(
                  '成立するとフォール判定が発生します（キックアウトカード／'
                  'HP消費で回避されなければ、そのまま勝敗が決まります）。',
                  style: TextStyle(color: _gold, fontSize: 12),
                )
              else if (technique.hasSubmissionEffect)
                const Text(
                  '成立するとギブアップ判定が発生します（ロープブレイクカード／'
                  'HP消費で回避されなければ、そのまま勝敗が決まります）。',
                  style: TextStyle(color: _gold, fontSize: 12),
                ),
              const SizedBox(height: 8),
              if (!check.canUse)
                Text(
                  check.reason ?? '使用できません。',
                  style: const TextStyle(color: _red),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: check.canUse
                  ? () {
                      Navigator.pop(dialogContext);
                      _declareAttack(entry);
                    }
                  : null,
              child: const Text('使用する'),
            ),
          ],
        ),
      );
    }
  }

  String _targetStateLabel(TechniqueTargetState state) => switch (state) {
    TechniqueTargetState.any => '指定なし',
    TechniqueTargetState.stand => '相手がスタンド中のみ',
    TechniqueTargetState.down => '相手がダウン中のみ',
  };

  String _targetShortLabel(TechniqueTargetState state) => switch (state) {
    TechniqueTargetState.any => 'ALL',
    TechniqueTargetState.stand => 'STAND',
    TechniqueTargetState.down => 'DOWN',
  };

  /// ③ 技使用のワンタップ化 ＋ ⑥「ダウンする」廃止に伴う統合休息。
  ///
  /// スタンド中に休息を選んだ場合、`goDown`→`rest`を連続で呼ぶ（エンジンの
  /// 2メソッドはどちらも無変更。呼び出し方をUI側でまとめただけ）。
  void _handleRest() {
    final state = matchState;
    if (state == null) return;
    var next = state;
    if (next.active.posture == WrestlerPosture.stand) {
      next = TechniqueMatchEngine.goDown(next);
    }
    final rested = TechniqueMatchEngine.rest(next);
    setState(() => matchState = rested);
  }

  void _endTurn() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.endTurn(state));
  }

  void _resetMatch() {
    setState(() {
      matchState = null;
      deckSourceNoteA = null;
      deckSourceNoteB = null;
      _detailExpandedA = false;
      _detailExpandedB = false;
      _logExpanded = false;
    });
  }

  /// ③ 手札カードのタップ即実行ディスパッチ（使用可能な場合のみ）。
  void _directUse(TechniqueDeckEntry entry) {
    final technique = catalog.findTechniqueById(entry.cardId);
    final energy = catalog.findEnergyById(entry.cardId);
    if (energy != null) {
      _setEnergy(entry);
      return;
    }
    if (technique == null) return;
    if (technique.hasFinisherEffect) {
      _declareFinisher(entry);
      return;
    }
    _declareAttack(entry);
  }

  @override
  Widget build(BuildContext context) {
    final loading = wrestlers == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Technique Match'),
        actions: [
          if (matchState != null)
            IconButton(
              tooltip: '新しい試合',
              icon: const Icon(Icons.refresh),
              onPressed: _resetMatch,
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : matchState == null
          ? _setupView()
          : _battleView(matchState!),
    );
  }

  Widget _devBanner() => Card(
    color: Colors.amber.shade900,
    child: const Padding(
      padding: EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '開発中：Technique Deck Rules Phase 7.5',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '技の応酬（返技・連続攻撃）・フォール／ギブアップ・フィニッシャーの'
            '決着判定が動作します（CPUは未実装）',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _setupView() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _devBanner(),
      const SizedBox(height: 12),
      Card(
        color: _bg,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Player A',
                style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
              ),
              DropdownButtonFormField<WrestlerDefinition>(
                initialValue: wrestlerA,
                items: [
                  for (final w in wrestlers!)
                    DropdownMenuItem(value: w, child: Text(w.name)),
                ],
                onChanged: (w) => setState(() => wrestlerA = w),
              ),
              const SizedBox(height: 16),
              const Text(
                'Player B',
                style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
              ),
              DropdownButtonFormField<WrestlerDefinition>(
                initialValue: wrestlerB,
                items: [
                  for (final w in wrestlers!)
                    DropdownMenuItem(value: w, child: Text(w.name)),
                ],
                onChanged: (w) => setState(() => wrestlerB = w),
              ),
              const SizedBox(height: 8),
              const Text(
                '保存済みのテクニックデッキがあればそれを使用します。無い場合は'
                '暫定自動生成で仮デッキを組んで試合を開始します。',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: (wrestlerA == null || wrestlerB == null || starting)
            ? null
            : _startMatch,
        icon: starting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_circle),
        label: Text(starting ? '準備中…' : '試合開始'),
      ),
    ],
  );

  // ============================================================
  // ④ 現在すべき行動を1文で大きく表示 ＋ 5段階ステッパー（補助表示）
  // ============================================================

  static const _phaseStageLabels = ['エネルギー', '技選択', 'ラリー', '決着判定', '手番終了'];

  int _currentStageIndex(TechniqueMatchState state) {
    if (state.isOver) return 4;
    if (state.pendingFinisher != null || state.pendingEscape != null) return 3;
    if (state.isRallyActive) return 2;
    final hasEnergyInHand = state.active.hand.any(
      (e) => catalog.findEnergyById(e.cardId) != null,
    );
    return hasEnergyInHand ? 0 : 1;
  }

  /// 「今何をすればいいか」を1文にまとめる。Chain数・攻撃側名など、既存
  /// テストが検証してきた文言要素もこの1文の中に含める。
  String _currentActionText(TechniqueMatchState state) {
    if (state.isOver) return '決着しました';
    final pendingFinisher = state.pendingFinisher;
    if (pendingFinisher != null) {
      return pendingFinisher.stage == TechniqueFinisherStage.responsePending
          ? 'フィニッシャー発動！キャンセル判定です'
          : 'フィニッシャー成立！脱出判定です';
    }
    if (state.pendingEscape != null) {
      final kind = state.pendingEscape!.kind == TechniqueEscapeKind.fall
          ? 'フォール'
          : 'ギブアップ';
      return '$kind判定です';
    }
    if (state.pendingAttack != null) {
      final defender = state.playerAt(1 - state.pendingAttack!.attackerIndex);
      return '${defender.wrestlerName}が返技を選択しています'
          '（Chain ${state.pendingAttack!.chain}）';
    }
    if (state.isRallyActive) {
      final attacker = state.playerAt(state.rallyAttackerIndex!);
      return '${attacker.wrestlerName}が攻撃側・Chain ${state.rallyChain}'
          '：続けて技を選ぶか、ラリーを終了してください';
    }
    final hasEnergyInHand = state.active.hand.any(
      (e) => catalog.findEnergyById(e.cardId) != null,
    );
    return hasEnergyInHand ? 'エネルギーをセットしてください' : '技を選択してください';
  }

  Widget _actionHeader(TechniqueMatchState state) {
    final current = _currentStageIndex(state);
    return Card(
      color: _panelBg,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ターン${state.turnNumber}',
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${state.active.wrestlerName}の手番',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _currentActionText(state),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _phaseStepper(current),
          ],
        ),
      ),
    );
  }

  Widget _phaseStepper(int current) => SizedBox(
    height: 22,
    child: Row(
      children: [
        for (var i = 0; i < _phaseStageLabels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1.5,
                color: i <= current ? _gold.withValues(alpha: 0.6) : Colors.white12,
              ),
            ),
          _phaseStageChip(_phaseStageLabels[i], active: i == current, done: i < current),
        ],
      ],
    ),
  );

  Widget _phaseStageChip(String label, {required bool active, required bool done}) {
    final color = active ? _gold : (done ? Colors.white54 : _dim);
    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        color: color,
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  // ============================================================
  // ⑤ ⑩ リング演出パネル（中央、直近の攻防をハイライト表示）
  // ============================================================

  static final _highlightRules = <(RegExp, String? Function(RegExpMatch))>[
    (RegExp('「(.+?)」を宣言した（フィニッシャー）'), (m) => '${m.group(1)}!!\n必殺技発動！'),
    (RegExp('「(.+?)」を宣言した'), (m) => '${m.group(1)}！'),
    (RegExp('が「(.+?)」を返技した'), (m) => '返した！'),
    (RegExp('「(.+?)」が成立した'), (m) => '「${m.group(1)}」ヒット！'),
    (RegExp('がダウンした'), (m) => 'ダウン！'),
    (RegExp('はフォールの危機'), (m) => 'フォール！！'),
    (RegExp('はギブアップの危機'), (m) => 'ギブアップ！！'),
    (RegExp('を使用し、(フォール|ギブアップ)を回避した'), (m) => '${m.group(1)}回避！'),
    (RegExp('の発動をキャンセルした'), (m) => 'キャンセル！'),
    (RegExp('に主導権が移った'), (m) => '主導権交代！'),
    (RegExp('から脱出した'), (m) => '脱出成功！'),
    (RegExp('の.*勝利！'), (m) => '勝利！！！'),
    (RegExp('引き分け'), (m) => '引き分け…'),
  ];

  String? _highlightFor(List<String> log) {
    if (log.isEmpty) return null;
    final window = log.length <= 6 ? log : log.sublist(log.length - 6);
    for (final line in window.reversed) {
      for (final (pattern, build) in _highlightRules) {
        final match = pattern.firstMatch(line);
        if (match != null) return build(match);
      }
    }
    return null;
  }

  Widget _ringPanel(TechniqueMatchState state) {
    final text = _highlightFor(state.log);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xff130d18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: text == null
              ? Text(
                  '${state.playerA.wrestlerName}  VS  ${state.playerB.wrestlerName}',
                  key: const ValueKey('idle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Text(
                  text,
                  key: ValueKey('${state.log.length}-$text'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    height: 1.3,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _battleView(TechniqueMatchState state) {
    final isNarrow = MediaQuery.sizeOf(context).width < 420;
    final effectiveAttackerIndex = state.rallyAttackerIndex ?? state.activePlayerIndex;
    final actingPlayer = state.playerAt(effectiveAttackerIndex);
    final canDeclare =
        state.pendingAttack == null &&
        state.pendingEscape == null &&
        state.pendingFinisher == null &&
        !state.isOver;

    return ListView(
      padding: EdgeInsets.all(isNarrow ? 8 : 12),
      children: [
        if (state.winnerIndex != null) ...[
          _winBanner(state),
          const SizedBox(height: 10),
        ] else if (state.isDraw) ...[
          _drawBanner(state),
          const SizedBox(height: 10),
        ],
        _actionHeader(state),
        _ringPanel(state),
        _compactPlayerCard(state, 0),
        const SizedBox(height: 6),
        _compactPlayerCard(state, 1),
        const SizedBox(height: 10),
        if (canDeclare && actingPlayer.hand.isNotEmpty) _handScroller(state, actingPlayer),
        const SizedBox(height: 8),
        _actionButtons(state),
        const SizedBox(height: 8),
        _logSection(state),
      ],
    );
  }

  Widget _winBanner(TechniqueMatchState state) {
    final winner = state.playerAt(state.winnerIndex!);
    return Card(
      color: _gold.withValues(alpha: 0.18),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.emoji_events, color: _gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${winner.wrestlerName}の勝利！（${state.winReason ?? "決着"}）',
                style: const TextStyle(fontWeight: FontWeight.bold, color: _gold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawBanner(TechniqueMatchState state) => Card(
    color: Colors.white24,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.hourglass_disabled, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '引き分け（${state.winReason ?? "時間切れ"}）',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  String _postureLabel(WrestlerPosture posture) => posture.displayLabel;

  Color _postureColor(WrestlerPosture posture) => switch (posture) {
    WrestlerPosture.stand => _green,
    WrestlerPosture.down => _orange,
    WrestlerPosture.fatigued => _red,
  };

  IconData _postureIcon(WrestlerPosture posture) => switch (posture) {
    WrestlerPosture.stand => Icons.accessibility_new,
    WrestlerPosture.down => Icons.arrow_downward,
    WrestlerPosture.fatigued => Icons.dangerous,
  };

  // ============================================================
  // ① プレイヤーカードのコンパクト化（常時表示は名前・HP・HEAT・Lv・
  // スタンド／ダウン・エネルギー概要のみ。山札等は折りたたみ）
  // ============================================================

  Widget _compactPlayerCard(TechniqueMatchState state, int playerIndex) {
    final player = state.playerAt(playerIndex);
    final isTurnOwner = playerIndex == state.activePlayerIndex;
    final effectiveAttackerIndex = state.rallyAttackerIndex ?? state.activePlayerIndex;
    final isEffectiveAttacker = playerIndex == effectiveAttackerIndex;
    final isPendingDefender =
        state.pendingAttack != null &&
        playerIndex == 1 - state.pendingAttack!.attackerIndex;
    final isPlayerA = playerIndex == 0;
    final hpRatio = player.maxHp == 0 ? 0.0 : player.hp / player.maxHp;
    final heatRatio = (player.heat / _heatVisualMax).clamp(0.0, 1.0);
    final note = isPlayerA ? deckSourceNoteA : deckSourceNoteB;
    final expanded = isPlayerA ? _detailExpandedA : _detailExpandedB;
    final isDownLike = player.posture != WrestlerPosture.stand;
    final postureColor = _postureColor(player.posture);
    final highlighted = isEffectiveAttacker || isPendingDefender;

    return Card(
      color: _panelBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: highlighted
            ? const BorderSide(color: _gold, width: 1.4)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_postureIcon(player.posture), size: 14, color: postureColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${player.wrestlerName}'
                    '${isTurnOwner ? "（手番）" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: postureColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _postureLabel(player.posture),
                    style: TextStyle(
                      color: postureColor,
                      fontSize: 10,
                      fontWeight: isDownLike ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                InkWell(
                  key: ValueKey('playerDetailToggle$playerIndex'),
                  onTap: () => setState(() {
                    if (isPlayerA) {
                      _detailExpandedA = !_detailExpandedA;
                    } else {
                      _detailExpandedB = !_detailExpandedB;
                    }
                  }),
                  child: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 26, child: Text('HP', style: TextStyle(fontSize: 10))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: hpRatio.clamp(0, 1),
                      minHeight: 7,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(
                        hpRatio > 0.5 ? _green : (hpRatio > 0.2 ? _gold : _red),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${player.hp}/${player.maxHp}', style: const TextStyle(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                const SizedBox(width: 26, child: Text('HEAT', style: TextStyle(fontSize: 10))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: heatRatio,
                      minHeight: 7,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(_gold),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${player.heat}', style: const TextStyle(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Lv.${player.level}', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final attribute in player.energyPool.keys)
                        _energySummaryChip(
                          attribute,
                          player.availableEnergyFor(attribute),
                          player.energyPool[attribute] ?? 0,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const Divider(height: 14, color: Colors.white12),
              Text(
                '手札${player.hand.length} ・ 山札${player.drawPile.length} ・ '
                '捨て札${player.discardPile.length}'
                '${player.removedPile.isNotEmpty ? " ・ 除外${player.removedPile.length}" : ""}'
                '${player.reshuffleCount > 0 ? " ・ 再構築${player.reshuffleCount}/$maxDeckReshuffles" : ""}',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    note,
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _energySummaryChip(MoveAttribute attribute, int available, int total) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      '${moveAttributeLabel(attribute)}$available/$total',
      style: const TextStyle(fontSize: 10, color: Colors.white70),
    ),
  );

  // ============================================================
  // ② 手札を画面下部に横スクロールで大きく表示 ＋ ③ ワンタップ実行
  // ============================================================

  Widget _handScroller(TechniqueMatchState state, TechniqueMatchPlayerState actingPlayer) {
    final canDeclare =
        state.pendingAttack == null &&
        state.pendingEscape == null &&
        state.pendingFinisher == null &&
        !state.isOver;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${actingPlayer.wrestlerName}の手札',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: actingPlayer.hand.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _handCardTile(
              state,
              actingPlayer.hand[index],
              playerLevelTappable: canDeclare,
              isRallyActive: state.isRallyActive,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'カードをタップで使用　長押しで詳細',
          style: TextStyle(fontSize: 10, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _handCardTile(
    TechniqueMatchState state,
    TechniqueDeckEntry entry, {
    required bool playerLevelTappable,
    required bool isRallyActive,
  }) {
    final technique = catalog.findTechniqueById(entry.cardId);
    final energy = catalog.findEnergyById(entry.cardId);
    final defense = catalog.findDefenseCardById(entry.cardId);
    final name = technique?.name ?? energy?.name ?? defense?.name ?? entry.cardId;
    final isEnergyCard = energy != null;
    final isDefenseCard = defense != null;

    bool cardEligible = true;
    String? reason;
    if (technique != null) {
      if (technique.hasFinisherEffect) {
        final check = TechniqueMatchEngine.canDeclareFinisher(state, entry, catalog);
        cardEligible = check.canDeclare;
        reason = check.reason;
      } else {
        final check = TechniqueMatchEngine.canDeclareAttack(state, entry, catalog);
        cardEligible = check.canUse;
        reason = check.reason;
      }
    }

    final tappable = playerLevelTappable &&
        (isEnergyCard ? !isRallyActive : true) &&
        !isDefenseCard;
    // ③ 使用可能なカードはタップで即実行。使用不可なカードは、タップ・
    // 長押しどちらでも理由を示す詳細ダイアログを開く（従来の
    // `_showHandCardSheet`を流用）。
    final directUsable = tappable && (isEnergyCard || (technique != null && cardEligible));
    final visuallyDim = !tappable || (technique != null && !cardEligible);

    Color borderColor;
    if (technique?.hasFinisherEffect ?? false) {
      borderColor = _gold;
    } else if (!cardEligible && technique != null) {
      borderColor = Colors.white24;
    } else if (isEnergyCard) {
      borderColor = _green.withValues(alpha: 0.7);
    } else if (technique != null && (technique.hasPinEffect || technique.hasSubmissionEffect)) {
      borderColor = _orange;
    } else {
      borderColor = Colors.white24;
    }

    final iconData = isEnergyCard
        ? Icons.bolt
        : switch (technique?.attribute) {
            MoveAttribute.strike => Icons.sports_mma,
            MoveAttribute.throwMove => Icons.swap_calls,
            MoveAttribute.submission => Icons.link,
            MoveAttribute.counter => Icons.repeat,
            MoveAttribute.rough => Icons.warning_amber,
            MoveAttribute.aerial => Icons.flight,
            null => Icons.shield,
          };

    return Opacity(
      opacity: visuallyDim ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: !tappable
              ? null
              : directUsable
              ? () => _directUse(entry)
              : () => _showHandCardSheet(entry),
          onLongPress: () => _showHandCardSheet(entry),
          child: Container(
            width: 108,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xff1a1120),
              border: Border.all(color: borderColor, width: 1.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (technique != null && technique.attackEnergyCost.values.any((v) => v > 0))
                      _miniBadge(
                        '${technique.attackEnergyCost.entries.where((e) => e.value > 0).map((e) => e.value).fold<int>(0, (a, b) => a + b)}',
                        Colors.white70,
                      ),
                    const Spacer(),
                    if (technique?.hasFinisherEffect ?? false)
                      const Icon(Icons.star, size: 13, color: _gold)
                    else
                      Icon(iconData, size: 13, color: Colors.white54),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: Icon(
                      iconData,
                      size: 34,
                      color: (technique?.hasFinisherEffect ?? false)
                          ? _gold.withValues(alpha: 0.55)
                          : borderColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                if (technique != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Text(
                          '威力${technique.power}',
                          style: const TextStyle(fontSize: 9, color: Colors.white60),
                        ),
                        const Spacer(),
                        Text(
                          _targetShortLabel(technique.targetState),
                          style: const TextStyle(fontSize: 8, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                if (technique != null && !cardEligible && reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 10, color: _red),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            // カード上はアイコン＋短い定型ラベルのみ（詳細な
                            // 理由文はダイアログ側に表示。同じ文言をカードに
                            // そのまま出すとダイアログ表示中に重複し
                            // `find.textContaining`があいまいになるため、
                            // あえて別の短い言い回しにしている）。
                            _shortReason(reason),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 8, color: _red),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// エンジンが返す詳細な不可理由文（`check.reason`）を、カード上に表示する
  /// 短い定型ラベルへ要約する（②「使用不可理由はアイコン程度」）。詳細な
  /// 理由文そのものはタップ／長押し後のダイアログに引き続き表示される。
  String _shortReason(String reason) {
    if (reason.contains('エネルギーが不足')) return 'エネルギー不足';
    if (reason.contains('スタンド状態でないと')) return '相手がダウン中';
    if (reason.contains('ダウン状態でないと')) return '相手がスタンド中';
    if (reason.contains('必要レベル')) return 'レベル不足';
    if (reason.contains('HEATが')) return 'HEAT不足';
    if (reason.contains('相手のHPが')) return '相手HP条件未達';
    if (reason.contains('自分のHPが')) return '自分HP条件未達';
    if (reason.contains('使用できません')) return '使用不可';
    return '使用不可';
  }

  Widget _miniBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.bold),
    ),
  );

  // ============================================================
  // ⑥ 行動ボタン（「ダウンする」廃止、休息＋ターン終了のみ）
  // ============================================================

  Widget _actionButtons(TechniqueMatchState state) {
    if (state.isOver) return const SizedBox.shrink();
    if (state.pendingEscape != null || state.pendingFinisher != null) {
      return const SizedBox.shrink();
    }
    if (state.isRallyActive) {
      if (state.pendingAttack != null) return const SizedBox.shrink();
      return Center(
        child: OutlinedButton.icon(
          onPressed: _endRally,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('ラリーを終了する'),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: _handleRest,
            icon: const Icon(Icons.self_improvement),
            label: const Text('休息'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _endTurn,
            icon: const Icon(Icons.skip_next),
            label: const Text('ターン終了'),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ⑦ ログを折りたたみ ＋ アイコン・色分け
  // ============================================================

  (IconData, Color) _logIconFor(String line) {
    if (line.contains('フィニッシャー')) return (Icons.whatshot, _gold);
    if (line.contains('ダウンした')) return (Icons.arrow_downward, _orange);
    if (line.contains('フォール')) return (Icons.sports_mma, _red);
    if (line.contains('ギブアップ')) return (Icons.back_hand, _red);
    if (line.contains('キックアウト') || line.contains('を回避した')) {
      return (Icons.shield, _green);
    }
    if (line.contains('リバーサル') || line.contains('主導権')) {
      return (Icons.swap_horiz, _gold);
    }
    if (line.contains('返技した')) return (Icons.repeat, _green);
    if (line.contains('を使用した') || line.contains('を宣言した')) {
      return (Icons.flash_on, Colors.white70);
    }
    if (line.contains('勝利') || line.contains('引き分け')) {
      return (Icons.emoji_events, _gold);
    }
    return (Icons.circle, Colors.white38);
  }

  Widget _logSection(TechniqueMatchState state) {
    final lines = state.log.reversed.toList();
    final preview = lines.take(4).toList();
    final shown = _logExpanded ? lines.take(20).toList() : preview;
    return Card(
      color: _panelBg,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const ValueKey('logToggle'),
              onTap: () => setState(() => _logExpanded = !_logExpanded),
              child: Row(
                children: [
                  Icon(
                    _logExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: _gold,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'バトルログ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: _gold, fontSize: 12),
                  ),
                  if (!_logExpanded) ...[
                    const SizedBox(width: 6),
                    Text(
                      '（タップで展開・最新${preview.length}件）',
                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            for (final line in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (context) {
                        final (icon, color) = _logIconFor(line);
                        return Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(icon, size: 12, color: color),
                        );
                      },
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(
                          fontSize: 12,
                          color: _logIconFor(line).$2 == Colors.white38
                              ? Colors.white70
                              : _logIconFor(line).$2,
                          fontWeight: _logIconFor(line).$2 == Colors.white38
                              ? FontWeight.normal
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
