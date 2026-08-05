import 'package:flutter/material.dart';

import '../wrestler_editor/models.dart'
    show MoveAttribute, WrestlerDefinition, moveAttributeLabel;
import '../wrestler_editor/repository.dart';
import 'technique_deck_deck.dart';
import 'technique_deck_defaults.dart';
import 'technique_deck_generator.dart';
import 'technique_deck_model_decks.dart';
import 'technique_deck_models.dart';
import 'technique_deck_storage.dart';
import 'technique_match_state.dart';
import 'technique_wrestler_portraits.dart';

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
/// 【UI全面リデザイン Ver.3（プレイフィール最優先、ルール・エンジンは無変更）】
/// Ver.2（リング演出・立ち絵）に続き、ユーザー提示のモックアップ
/// （「改善後の試合画面イメージ」）に基づき、①初見30秒で分かる／②毎ターン
/// 迷わない／③操作する楽しさ、の3点を最優先に以下を追加した。ロジックは
/// 一切変更していない（`TechniqueMatchEngine`の呼び出しパターンは従来の
/// まま）。
/// - **「STEP N」表示**: これまでの1文の指示に加え、常に「STEP N」の番号を
///   明示し、今何をすべき段階かを一目で分かるようにした（5アイコンの
///   ステッパー行は情報過多のため廃止し、STEP表示1つに集約した）
/// - **状態バッジを大型化・英語ラベル化**: STAND/DOWN/PIN/SUBMISSION/
///   FINISHERの5種を、状態に応じて色分けした大きなバッジで表示する
///   （フォール危機＝PIN、ギブアップ危機＝SUBMISSION、フィニッシャー
///   危機＝FINISHERを新設。従来はダウン状態のみの表示だった）
/// - **HEATを炎アイコンの行で表示**（バーに加えて視覚的に直感化）
/// - **エネルギードットを属性ごとに色分け**（打撃=赤・投げ=金・関節=青・
///   飛び=緑・ラフ=紫。属性を色で覚えられるようにした）
/// - **手札カードを約1.5倍に拡大**（幅112→168等）。カードを見せることを
///   優先し、情報は技名・コスト・威力・属性・対象状態のみに絞った
/// - **リングパネルを拡大・強調**し、両者の立ち絵をリング背景に薄く配置。
///   ハイライト演出のフォント・アニメーションをより大きく／力強くした
/// - **「新しい試合」に確認ダイアログを追加**（デッキリセット相当の
///   取り消せない操作のため。フィニッシャー宣言・降参と合わせ、確認が
///   必要な操作として明示的に残した３つのうちの１つ）
/// - ログ見出しを「バトルログ」→「最新ログ」に変更し、直近のラリー数・
///   ターン数を並べて表示する簡易ステータス行を追加
///
/// ダイアログの文言・ボタンウィジェット型（`FilledButton`/`OutlinedButton`）
/// は既存テストが依存しているため、返技判定・回避判定・フィニッシャー
/// 判定の4種のダイアログ自体は維持している（これらは「今まさに選ぶべき
/// こと」そのものであり、削減対象の“余分な確認”ではないと判断した）。
/// 手札カードのタップ→選択→確認ボタンの2段階操作もVer.2から維持（誤操作
/// 防止と、モックアップ画像でカードが選択状態＋確認ボタンの組で描かれて
/// いることに基づく）。カード操作フローの変更に伴い、
/// `test/technique_match_screen_test.dart`はユーザー指示により更新した
/// （`technique_match_state_test.dart`等のゲームロジックのテストは無改修）。
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
// 色の役割を統一（Ver.2で再整理）: 緑=使用可能／スタンド、
// オレンジ=ダウン、赤=危険・不可、金=フィニッシャー専用、
// 青=現在の手番、グレー=補助・不可。
// ============================================================
const _bg = Color(0xff1c1420);
const _panelBg = Color(0xff251b2c);
const _gold = Color(0xffffc857);
const _green = Color(0xff5cd68b);
const _orange = Color(0xffffab5c);
const _red = Color(0xffff5c5c);
const _blue = Color(0xff5cb8ff);
const _purple = Color(0xffb388ff);

/// Ver.3: エネルギードット・カード枠を属性ごとに色分けするための対応表
/// （打撃=赤・投げ=金・関節=青・飛び=緑・ラフ=紫・返し=無彩色）。
Color _attributeColor(MoveAttribute attribute) => switch (attribute) {
  MoveAttribute.strike => _red,
  MoveAttribute.throwMove => _gold,
  MoveAttribute.submission => _blue,
  MoveAttribute.aerial => _green,
  MoveAttribute.rough => _purple,
  MoveAttribute.counter => Colors.white54,
};

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
  TechniqueDeckEntry? _selectedEntry;

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
    // Technique Deck Rules Phase 7A: 保存済みデッキが無い場合、AutoGenerator
    // による仮デッキよりも先に正式なモデルデッキ（存在すれば）を優先する
    // （仕様書「⑥Technique Match」: 保存済みデッキ→モデルデッキ→
    // AutoGenerator）。TechniqueMatchEngine自体には手を加えていない。
    final modelDeck = findTechniquePhase7AModelDeck(wrestler.id);
    if (modelDeck != null) {
      return (modelDeck, 'モデルデッキ「${modelDeck.name}」を使用');
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
    setState(() {
      matchState = result.state;
      _selectedEntry = null;
    });
  }

  Future<void> _declareAttack(TechniqueDeckEntry entry) async {
    final state = matchState;
    if (state == null) return;
    final result = TechniqueMatchEngine.declareAttack(state, entry, catalog);
    setState(() {
      matchState = result.state;
      _selectedEntry = null;
    });
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
        // Ver.3.1（UI/UX改善+CPU実装ラウンド優先度5）: 説明文を削り、
        // 「技名／必要エネルギー／所持」の3行だけに絞った簡潔な表示にした。
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              '${attacker.wrestlerName}が使用 ・ 威力${card.power}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 10),
            if (card.reversalEnergyCost.values.any((v) => v > 0)) ...[
              const Text('必要エネルギー', style: TextStyle(fontSize: 11, color: Colors.white54)),
              for (final e in card.reversalEnergyCost.entries.where((e) => e.value > 0))
                Text(
                  '${moveAttributeLabel(e.key)} ×${e.value}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 8),
              const Text('所持', style: TextStyle(fontSize: 11, color: Colors.white54)),
              for (final e in card.reversalEnergyCost.entries.where((e) => e.value > 0))
                Text('${moveAttributeLabel(e.key)} ×${defender.availableEnergyFor(e.key)}'),
            ] else
              const Text(
                '返技不可（返技エネルギー設定なし）',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            if (!check.canCounter)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  check.reason ?? '返技できません。',
                  style: const TextStyle(color: _red, fontSize: 12),
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
    setState(() {
      matchState = result.state;
      _selectedEntry = null;
    });
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
      _selectedEntry = null;
    });
  }

  /// Ver.3 ⑧: 「新しい試合」（進行中の試合を破棄する取り消せない操作）は
  /// フィニッシャー宣言・降参と並ぶ「確認が必要な操作」として、確認
  /// ダイアログを経由してから実行する。
  Future<void> _confirmResetMatch() async {
    if (matchState == null) {
      _resetMatch();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新しい試合を始めますか？'),
        content: const Text('進行中の試合内容は破棄されます。この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('新しい試合を始める'),
          ),
        ],
      ),
    );
    if (confirmed == true) _resetMatch();
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
              onPressed: _confirmResetMatch,
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
  // Ver.3 ①②: 「今やること」をSTEP番号＋1文で常に1つだけ表示する。
  // Ver.2の5アイコンステッパー行は情報過多と判断し廃止した（STEP番号の
  // 明示1つに集約）。
  // ============================================================

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

  /// STEP見出しの下に添える短い補足ヒント（何が選べない／なぜかを一言で）。
  String? _currentStepHint(TechniqueMatchState state) {
    if (state.isOver) return null;
    if (state.pendingFinisher != null || state.pendingEscape != null) {
      return null; // ダイアログ側に詳細説明がある。
    }
    if (state.pendingAttack != null || state.isRallyActive) return null;
    final hasEnergyInHand = state.active.hand.any(
      (e) => catalog.findEnergyById(e.cardId) != null,
    );
    return hasEnergyInHand
        ? 'エネルギーカードをタップして選んでください'
        : 'エネルギーが足りない技は選択できません';
  }

  /// Ver.3: 「STEP N」の番号バッジ＋1文の指示のみを表示する（5アイコンの
  /// ステッパー行は情報過多のため廃止）。
  Widget _actionHeader(TechniqueMatchState state) {
    final stepNumber = _currentStageIndex(state) + 1;
    final hint = _currentStepHint(state);
    return Card(
      color: _panelBg,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _blue.withValues(alpha: 0.6)),
              ),
              child: Text(
                'STEP $stepNumber',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentActionText(state),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        hint,
                        style: const TextStyle(fontSize: 10, color: Colors.white54),
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

  // ============================================================
  // ⑤ ⑩ リング演出パネル（中央、直近の攻防をハイライト表示）
  // ============================================================

  static final _damagePattern = RegExp('に(\\d+)ダメージ');

  static final _highlightRules = <(RegExp, String Function(RegExpMatch), Color)>[
    (RegExp('「(.+?)」を宣言した（フィニッシャー）'), (m) => '${m.group(1)}!!', _gold),
    (RegExp('が「(.+?)」を返技した'), (m) => '返した！', _green),
    (RegExp('「(.+?)」が成立した'), (m) => '「${m.group(1)}」ヒット！', Colors.white),
    (RegExp('「(.+?)」を宣言した'), (m) => '${m.group(1)}！', Colors.white),
    (RegExp('がダウンした'), (m) => 'ダウン！！', _orange),
    (RegExp('はフォールの危機'), (m) => 'フォール！！', _red),
    (RegExp('はギブアップの危機'), (m) => 'ギブアップ！！', _red),
    (RegExp('を使用し、(フォール|ギブアップ)を回避した'), (m) => '${m.group(1)}回避！', _green),
    (RegExp('の発動をキャンセルした'), (m) => 'キャンセル！', _green),
    (RegExp('に主導権が移った'), (m) => '主導権交代！', _gold),
    (RegExp('から脱出した'), (m) => '脱出成功！', _green),
    (RegExp('の.*勝利！'), (m) => '勝利！！！', _gold),
    (RegExp('引き分け'), (m) => '引き分け…', Colors.white54),
  ];

  ({String main, String? sub, Color color})? _highlightFor(List<String> log) {
    if (log.isEmpty) return null;
    final window = log.length <= 8 ? log : log.sublist(log.length - 8);
    for (final line in window.reversed) {
      for (final (pattern, build, color) in _highlightRules) {
        final match = pattern.firstMatch(line);
        if (match == null) continue;
        String? sub;
        if (pattern.pattern.contains('が成立した')) {
          for (final other in window) {
            final dmg = _damagePattern.firstMatch(other);
            if (dmg != null) {
              sub = '${dmg.group(1)} DAMAGE';
              break;
            }
          }
        } else if (pattern.pattern.contains('フィニッシャー')) {
          sub = '必殺技発動！';
        }
        return (main: build(match), sub: sub, color: color);
      }
    }
    return null;
  }

  /// Ver.3 ④: リングを画面の主役として拡大し、両者の立ち絵をリング背景に
  /// 薄く配置する（仕様書⑫「立ち絵は試合画面の主役になるよう配置」）。
  /// 直近のログから攻防のハイライトを抽出し、より大きく・力強いアニメー
  /// ションで表示する。
  Widget _ringPanel(TechniqueMatchState state) {
    final highlight = _highlightFor(state.log);
    final effectiveAttackerIndex = state.rallyAttackerIndex ?? state.activePlayerIndex;
    final attackerName = state.playerAt(effectiveAttackerIndex).wrestlerName;
    final portraitA = techniqueWrestlerPortraits[state.playerA.wrestlerId];
    final portraitB = techniqueWrestlerPortraits[state.playerB.wrestlerId];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      // 優先度1（縦1画面化）: 相手・自分カードと手札・ボタンを画面内に
      // 収めるため、Ver.3の190→130へ縮小した。
      constraints: const BoxConstraints(minHeight: 130),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff17101d), Color(0xff0e0a12)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight != null
              ? highlight.color.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.14),
          width: highlight != null ? 2.2 : 1.5,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // リング背景にレスラー立ち絵を薄く配置（試合演出エリアの主役化）。
          if (portraitA != null)
            Positioned(
              left: -6,
              bottom: -18,
              child: Opacity(
                opacity: 0.16,
                child: Image.asset(portraitA, height: 130, fit: BoxFit.cover),
              ),
            ),
          if (portraitB != null)
            Positioned(
              right: -6,
              bottom: -18,
              child: Opacity(
                opacity: 0.16,
                child: Image.asset(portraitB, height: 130, fit: BoxFit.cover),
              ),
            ),
          // リングロープ風の装飾（単純な横線）。
          Positioned(
            left: 0,
            right: 0,
            top: 10,
            child: Container(height: 2, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Container(height: 2, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!state.isOver && !state.isDraw)
                Text(
                  '← $attackerNameが攻撃中',
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.7, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: highlight == null
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
                    : Column(
                        key: ValueKey('${state.log.length}-${highlight.main}'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            highlight.main,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: highlight.color,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              height: 1.2,
                            ),
                          ),
                          if (highlight.sub != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                highlight.sub!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ],
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

    // 優先度1（縦1画面化）: 相手→リング→自分→STEP→手札→操作ボタンの
    // コア部分をスクロールなしで収めることを目標に、各要素の余白・
    // サイズを縮小した。ログ・ラリー統計は既定で折りたたみ、コアの下に
    // 最小限（1行）だけ表示する。
    return ListView(
      padding: EdgeInsets.all(isNarrow ? 6 : 8),
      children: [
        if (state.winnerIndex != null) ...[
          _winBanner(state),
          const SizedBox(height: 6),
        ] else if (state.isDraw) ...[
          _drawBanner(state),
          const SizedBox(height: 6),
        ],
        // Ver.3 ⑫⑬: 相手カード→リング→自分カード→STEP→手札の縦構成
        // （ユーザー提示モックアップの並び順に合わせた）。
        _compactPlayerCard(state, 0),
        _ringPanel(state),
        _compactPlayerCard(state, 1),
        _actionHeader(state),
        if (canDeclare && actingPlayer.hand.isNotEmpty) _handScroller(state, actingPlayer),
        if (_selectedEntry != null) _selectionBar(state),
        const SizedBox(height: 6),
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

  Color _postureColor(WrestlerPosture posture) => switch (posture) {
    WrestlerPosture.stand => _green,
    WrestlerPosture.down => _orange,
    WrestlerPosture.fatigued => _red,
  };

  /// Ver.3 ⑤: STAND/DOWN/PIN/SUBMISSION/FINISHERの5種の大型状態バッジ。
  /// フォール／ギブアップ／フィニッシャーの危機に陥っている側だけ専用の
  /// バッジへ切り替わり、それ以外はスタンド／ダウンで表示する。
  (String, IconData, Color) _statusBadge(TechniqueMatchState state, int playerIndex) {
    final finisher = state.pendingFinisher;
    if (finisher != null && finisher.defenderIndex == playerIndex) {
      return ('FINISHER', Icons.star, _gold);
    }
    final escape = state.pendingEscape;
    if (escape != null && escape.defenderIndex == playerIndex) {
      return escape.kind == TechniqueEscapeKind.fall
          ? ('PIN', Icons.warning_amber, _red)
          : ('SUBMISSION', Icons.link, _purple);
    }
    final posture = state.playerAt(playerIndex).posture;
    return posture == WrestlerPosture.stand
        ? ('STAND', Icons.accessibility_new, _green)
        : ('DOWN', Icons.arrow_downward, _orange);
  }

  // ============================================================
  // ① プレイヤーカードのコンパクト化（常時表示は名前・HP・HEAT・Lv・
  // スタンド／ダウン・エネルギー概要のみ。山札等は折りたたみ）
  // ============================================================

  /// レスラー立ち絵（バストアップ）またはアイコン代替枠。ダウン／疲労状態
  /// では暗く・傾けて表示し、状態を一目で分かるようにする。
  ///
  /// UI/UX改善+CPU実装ラウンドの優先度3対応: `BoxFit.cover`で小さな枠へ
  /// 詰め込むと顔が見切れる問題があったため、試合画面専用のバストアップ
  /// 画像（[techniqueWrestlerBustPortraits]）を`BoxFit.contain`＋
  /// `Alignment.topCenter`基準で表示し、レスラーごとの
  /// `portraitScale`/`portraitOffsetX`/`portraitOffsetY`
  /// （[TechniquePortraitAdjustment]）で個別調整できるようにした。
  Widget _portraitBox(TechniqueMatchPlayerState player) {
    const width = 52.0;
    const height = 68.0;
    final path = techniqueWrestlerBustPortraits[player.wrestlerId] ??
        techniqueWrestlerPortraits[player.wrestlerId];
    final adjustment = techniquePortraitAdjustmentFor(player.wrestlerId);
    final isDownLike = player.posture != WrestlerPosture.stand;
    final isFatigued = player.posture == WrestlerPosture.fatigued;
    final postureColor = _postureColor(player.posture);

    final Widget content = path != null
        ? Transform.scale(
            scale: adjustment.scale,
            child: Align(
              alignment: Alignment(adjustment.offsetX, -1.0 + adjustment.offsetY),
              child: Image.asset(path, fit: BoxFit.contain),
            ),
          )
        : Container(
            color: Colors.white.withValues(alpha: 0.06),
            child: Icon(Icons.person, size: width * 0.55, color: Colors.white24),
          );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDownLike ? postureColor : Colors.white24,
          width: isDownLike ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Transform.rotate(
          angle: isDownLike ? -0.13 : 0,
          child: Opacity(
            opacity: isFatigued ? 0.45 : (isDownLike ? 0.65 : 1.0),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  content,
                  if (isDownLike) Container(color: Colors.black.withValues(alpha: 0.22)),
                  if (isDownLike)
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: Icon(
                        isFatigued ? Icons.dangerous : Icons.bedtime,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
    final (badgeLabel, badgeIcon, badgeColor) = _statusBadge(state, playerIndex);
    // ⑧ 「現在の手番」を示す強調色は青に統一（金はフィニッシャー専用）。
    final highlighted = isEffectiveAttacker || isPendingDefender;

    return Card(
      color: _panelBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: highlighted
            ? const BorderSide(color: _blue, width: 1.6)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _portraitBox(player),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${player.wrestlerName}'
                          '${isTurnOwner ? "（手番）" : ""}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: badgeColor.withValues(alpha: 0.7)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, size: 10, color: badgeColor),
                            const SizedBox(width: 2),
                            Text(
                              badgeLabel,
                              style: TextStyle(
                                color: badgeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
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
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const SizedBox(width: 24, child: Text('HP', style: TextStyle(fontSize: 9))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: hpRatio.clamp(0, 1),
                            minHeight: 6,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation(
                              hpRatio > 0.5 ? _green : (hpRatio > 0.2 ? _gold : _red),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('${player.hp}/${player.maxHp}', style: const TextStyle(fontSize: 9)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const SizedBox(width: 24, child: Text('HEAT', style: TextStyle(fontSize: 9))),
                      _heatFlameRow(heatRatio),
                      const SizedBox(width: 5),
                      Text('${player.heat}', style: const TextStyle(fontSize: 9)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  // ⑨ エネルギーを属性ごとの横一列（ラベル＋ドット）で表示。
                  for (final attribute in player.energyPool.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: _energyAttributeRow(
                        attribute,
                        player.availableEnergyFor(attribute),
                        player.energyPool[attribute] ?? 0,
                      ),
                    ),
                  if (expanded) ...[
                    const Divider(height: 12, color: Colors.white12),
                    Text(
                      'Lv.${player.level}',
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
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
          ],
        ),
      ),
    );
  }

  /// Ver.3: HEATを炎アイコン6個の行で直感的に表示する（バーの数値表示に
  /// 加えて視覚化。ルール上のHEAT上限は未決定のため、表示専用の目安）。
  static const _heatFlameCount = 6;

  Widget _heatFlameRow(double heatRatio) {
    final filled = (heatRatio * _heatFlameCount).round().clamp(0, _heatFlameCount);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _heatFlameCount; i++)
          Icon(
            Icons.local_fire_department,
            size: 10,
            color: i < filled ? _gold : Colors.white24,
          ),
      ],
    );
  }

  /// 属性ごとの横一列表示（属性ラベル＋ドット）。例: 「打 ●●○」。
  /// Ver.3: ドットの色を属性ごとに色分けした（打撃=赤・投げ=金・関節=青・
  /// 飛び=緑・ラフ=紫）。使用可能=塗り、未セット（total中の残り）=縁取りのみ。
  Widget _energyAttributeRow(MoveAttribute attribute, int available, int total) {
    if (total <= 0) return const SizedBox.shrink();
    final color = _attributeColor(attribute);
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            moveAttributeLabel(attribute),
            style: const TextStyle(fontSize: 8, color: Colors.white54),
          ),
        ),
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < available ? color : Colors.transparent,
                border: Border.all(
                  color: i < available ? color : Colors.white30,
                  width: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // ② 手札を画面下部に横スクロールで大きく表示 ＋ ③ タップで選択→確認
  // ============================================================

  Widget _handScroller(TechniqueMatchState state, TechniqueMatchPlayerState actingPlayer) {
    final canDeclare =
        state.pendingAttack == null &&
        state.pendingEscape == null &&
        state.pendingFinisher == null &&
        !state.isOver;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${actingPlayer.wrestlerName}の手札',
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
        const SizedBox(height: 2),
        SizedBox(
          // 優先度2: 常時3枚程度見える密度へ縮小（幅120〜136・高さ160〜180）。
          height: 176,
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
      ],
    );
  }

  /// ③ 手札カードの種別ラベル（技／ENERGY／DEFENSE／FINISHER）。
  String _cardCategoryLabel({
    required bool isEnergyCard,
    required bool isDefenseCard,
    required bool isFinisher,
  }) {
    if (isFinisher) return 'FINISHER';
    if (isEnergyCard) return 'ENERGY';
    if (isDefenseCard) return 'DEFENSE';
    return '技';
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
    final isFinisher = technique?.hasFinisherEffect ?? false;

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
    } else if (isEnergyCard && state.energySetThisTurn) {
      // 技エネルギーは1ターンに1枚のみセット可能（エンジンレベルで強制、
      // UI側でも既にセット済みならこのターンは選択不可であることを示す）。
      cardEligible = false;
      reason = 'このターンは既に技エネルギーをセットしています（1ターンに1枚まで）。';
    }

    final tappable = playerLevelTappable &&
        (isEnergyCard ? !isRallyActive && cardEligible : true) &&
        !isDefenseCard;
    final visuallyDim = !tappable || (technique != null && !cardEligible);
    final selected = _selectedEntry == entry;

    Color borderColor;
    if (isFinisher) {
      borderColor = _gold;
    } else if (!cardEligible) {
      borderColor = Colors.white24;
    } else if (isEnergyCard) {
      borderColor = _green.withValues(alpha: 0.7);
    } else if (technique != null && (technique.hasPinEffect || technique.hasSubmissionEffect)) {
      borderColor = _orange;
    } else {
      borderColor = Colors.white24;
    }
    if (selected) borderColor = _blue;

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

    final costText = technique?.attackEnergyCost.entries
        .where((e) => e.value > 0)
        .map((e) => '${moveAttributeLabel(e.key)}${e.value}')
        .join('・');

    return Opacity(
      opacity: visuallyDim && !selected ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          // ③ タップは選択のトグルのみ（同じカードを再タップで選択解除）。
          // 実行は下に現れる確認バーのボタンから行う。長押しは常に詳細
          // ダイアログ（従来の`_showHandCardSheet`）を開く。
          onTap: !tappable
              ? null
              : () => setState(() {
                  _selectedEntry = selected ? null : entry;
                }),
          onLongPress: () => _showHandCardSheet(entry),
          // 優先度2: 選択中のカードだけ少し拡大して分かりやすくする。
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: selected ? 1.06 : 1.0,
            child: Container(
              // 優先度2: 幅120〜136・高さ160〜180程度、常時3枚程度見える密度へ
              // 縮小（技名・コスト・威力・属性・対象のみを表示し、説明文は
              // 表示しない。詳細は長押し）。
              width: 128,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? _blue.withValues(alpha: 0.14) : const Color(0xff1a1120),
                border: Border.all(color: borderColor, width: selected ? 2.5 : 1.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _miniBadge(
                        _cardCategoryLabel(
                          isEnergyCard: isEnergyCard,
                          isDefenseCard: isDefenseCard,
                          isFinisher: isFinisher,
                        ),
                        isFinisher
                            ? _gold
                            : (technique != null
                                ? _attributeColor(technique.attribute)
                                : Colors.white54),
                      ),
                      const Spacer(),
                      if (selected)
                        const Icon(Icons.check_circle, size: 15, color: _blue)
                      else if (isFinisher)
                        const Icon(Icons.star, size: 13, color: _gold)
                      else
                        Icon(iconData, size: 13, color: Colors.white54),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  if (technique != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      (costText?.isNotEmpty ?? false) ? 'コスト $costText' : 'コスト なし',
                      style: const TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                    Row(
                      children: [
                        Text(
                          '威力${technique.power}',
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                        const Spacer(),
                        Text(
                          _targetShortLabel(technique.targetState),
                          style: const TextStyle(fontSize: 10, color: Colors.white38),
                        ),
                      ],
                    ),
                  ],
                  if (!cardEligible && reason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 11, color: _red),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              // カード上はアイコン＋短い定型ラベルのみ（詳細な
                              // 理由文は選択時の確認バー／長押しダイアログに
                              // 表示される）。
                              _shortReason(reason),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9, color: _red),
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
      ),
    );
  }

  /// ③ 選択中カードの確認バー（タップ→選択→ここで確定実行）。
  Widget _selectionBar(TechniqueMatchState state) {
    final entry = _selectedEntry;
    if (entry == null) return const SizedBox.shrink();
    final technique = catalog.findTechniqueById(entry.cardId);
    final energy = catalog.findEnergyById(entry.cardId);
    final name = technique?.name ?? energy?.name ?? entry.cardId;

    bool eligible;
    String? reason;
    String buttonLabel;
    VoidCallback? onConfirm;
    if (energy != null) {
      // 技エネルギーは1ターンに1枚のみセット可能（エンジンレベルで強制）。
      eligible = !state.energySetThisTurn;
      reason = eligible
          ? null
          : 'このターンは既に技エネルギーをセットしています（1ターンに1枚まで）。';
      buttonLabel = 'セットする';
      onConfirm = eligible ? () => _setEnergy(entry) : null;
    } else if (technique != null && technique.hasFinisherEffect) {
      final check = TechniqueMatchEngine.canDeclareFinisher(state, entry, catalog);
      eligible = check.canDeclare;
      reason = check.reason;
      buttonLabel = '宣言する';
      onConfirm = eligible ? () => _declareFinisher(entry) : null;
    } else if (technique != null) {
      final check = TechniqueMatchEngine.canDeclareAttack(state, entry, catalog);
      eligible = check.canUse;
      reason = check.reason;
      buttonLabel = '使用する';
      onConfirm = eligible ? () => _declareAttack(entry) : null;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.1),
        border: Border.all(color: _blue.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                if (!eligible && reason != null)
                  Text(
                    reason,
                    style: const TextStyle(fontSize: 10, color: _red),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onConfirm, child: Text(buttonLabel)),
        ],
      ),
    );
  }

  /// エンジンが返す詳細な不可理由文（`check.reason`）を、カード上に表示する
  /// 短い定型ラベルへ要約する（②「使用不可理由はアイコン程度」）。詳細な
  /// 理由文そのものはタップ／長押し後のダイアログに引き続き表示される。
  String _shortReason(String reason) {
    if (reason.contains('1ターンに1枚')) return 'セット済み(1/turn)';
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
    // ⑥ ボタン内へ補足サブテキストを追加（「休息」「ターン終了」自体は
    // 既存テストが検証する厳密な文字列のため、別のTextとして維持する）。
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: _handleRest,
            icon: const Icon(Icons.self_improvement),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('休息', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('HP回復・ダウンして終了', style: TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _endTurn,
            icon: const Icon(Icons.skip_next),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('ターン終了', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('何もしない', style: TextStyle(fontSize: 9)),
              ],
            ),
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

  /// Ver.3: ログ見出し下に添えるラリー数・ターン数の簡易ステータス行。
  /// 「残り時間」はTechnique Deck Rulesでは未実装のため「―」表示のみ
  /// （仕様上のダミー、ロジックには接続しない）。
  Widget _matchStatsRow(TechniqueMatchState state) {
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          stat('ラリー数', '${state.rallyChain}'),
          stat('ターン数', '${state.turnNumber}'),
          stat('残り時間', '―'),
        ],
      ),
    );
  }

  /// 優先度1（縦1画面化）: ログ・ラリー統計は既定では折りたたみ、ヘッダー
  /// 1行のみを常時表示する（旧Ver.3では3行プレビュー＋統計行が常時表示
  /// されていたが、画面を圧迫するため展開時のみ表示するよう変更した）。
  Widget _logSection(TechniqueMatchState state) {
    final lines = state.log.reversed.toList();
    final shown = _logExpanded ? lines.take(20).toList() : const <String>[];
    return Card(
      color: _panelBg,
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const ValueKey('logToggle'),
              onTap: () => setState(() => _logExpanded = !_logExpanded),
              child: Row(
                children: [
                  Icon(
                    _logExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: _gold,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '最新ログ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: _gold, fontSize: 11),
                  ),
                  if (!_logExpanded && lines.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lines.first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_logExpanded) ...[
              const SizedBox(height: 6),
              _matchStatsRow(state),
            ],
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
