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
/// 【UI改修（プレイフィール改善、ルール・エンジンは無変更）】ユーザー指示に
/// より、ロジックは一切変更せず見た目のみを刷新した。手札をミニカード表示に
/// し、使用可否の理由をカード上に表示する・エネルギープールをドット表示で
/// 可視化する・ダウン状態を一目で分かるようにする・ターンの進行段階を
/// ステッパーで示す・技の成立などの見せ場を画面中央付近に短時間強調表示する・
/// レスラー情報をカード風に集約する・進行ログにアイコンと色を付ける、の
/// 各点を対応した。ボタンのラベル文字列・ダイアログの文言・ウィジェット型
/// （`FilledButton`／`OutlinedButton`等）は既存テストが厳密に依存しているため
/// 一切変更していない（`test/technique_match_screen_test.dart`参照）。
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

const _bg = Color(0xff211527);
const _cardBg = Color(0xff2a1c33);
const _gold = Color(0xffffc857);
const _green = Color(0xff5cd68b);
const _orange = Color(0xffffab5c);
const _red = Color(0xffff5c5c);
const _dim = Colors.white38;

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

  void _goDown() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.goDown(state));
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
    TechniqueTargetState.any => 'ANY',
    TechniqueTargetState.stand => 'STAND',
    TechniqueTargetState.down => 'DOWN',
  };

  void _rest() {
    final state = matchState;
    if (state == null) return;
    setState(() => matchState = TechniqueMatchEngine.rest(state));
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
    });
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
  // ④ ターン進行の可視化: エネルギー→技選択→ラリー→決着判定→ターン終了
  // ============================================================

  // 最後の段階は既存の「ターン終了」ボタン文字列と衝突しないよう
  // 「手番終了」という別表記にする（既存テストが `find.text('ターン終了')`
  // を厳密に使っているため）。
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

  Widget _phaseStepper(TechniqueMatchState state) {
    final current = _currentStageIndex(state);
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          for (var i = 0; i < _phaseStageLabels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: i <= current ? _gold : Colors.white24,
                ),
              ),
            _phaseStageChip(_phaseStageLabels[i], active: i == current, done: i < current),
          ],
        ],
      ),
    );
  }

  Widget _phaseStageChip(String label, {required bool active, required bool done}) {
    final color = active ? _gold : (done ? Colors.white70 : _dim);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: active ? _gold.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(color: color, width: active ? 1.4 : 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // ============================================================
  // ⑤ ラリー演出（見せ場のハイライトを短時間強調表示）
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

  Widget _highlightBanner(TechniqueMatchState state) {
    final text = _highlightFor(state.log);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.15),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: text == null
          ? const SizedBox(key: ValueKey('none'), height: 0)
          : Container(
              key: ValueKey('${state.log.length}-$text'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.14),
                border: Border.all(color: _gold.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  height: 1.2,
                ),
              ),
            ),
    );
  }

  Widget _battleView(TechniqueMatchState state) {
    final isNarrow = MediaQuery.sizeOf(context).width < 420;
    return ListView(
      padding: EdgeInsets.all(isNarrow ? 8 : 12),
      children: [
        _devBanner(),
        const SizedBox(height: 12),
        if (state.winnerIndex != null) ...[
          _winBanner(state),
          const SizedBox(height: 12),
        ] else if (state.isDraw) ...[
          _drawBanner(state),
          const SizedBox(height: 12),
        ],
        Card(
          color: _bg,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ターン${state.turnNumber} ・ ${state.active.wrestlerName}の手番 '
                  '・ フェーズ: ${_phaseLabel(state.phase)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (state.isRallyActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Chain ${state.rallyChain} ・ '
                      '${state.playerAt(state.rallyAttackerIndex!).wrestlerName}が攻撃側'
                      '${state.pendingAttack != null ? "（返技判定待ち）" : "（次の技を選択、または終了）"}',
                      style: const TextStyle(color: _gold, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 8),
                _phaseStepper(state),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _highlightBanner(state),
        _playerCard(state, 0, isNarrow: isNarrow),
        const SizedBox(height: 8),
        _playerCard(state, 1, isNarrow: isNarrow),
        const SizedBox(height: 8),
        Card(
          color: _bg,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'その他の行動',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _gold),
                ),
                const SizedBox(height: 6),
                state.isOver
                    ? const Text(
                        '試合は終了しました。右上の更新アイコンから新しい試合を始められます。',
                        style: TextStyle(color: Colors.white70),
                      )
                    : state.pendingEscape != null
                    ? const Text(
                        '決着判定中です…',
                        style: TextStyle(color: Colors.white70),
                      )
                    : state.pendingFinisher != null
                    ? const Text(
                        'フィニッシャー判定中です…',
                        style: TextStyle(color: Colors.white70),
                      )
                    : state.isRallyActive
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (state.pendingAttack == null)
                            OutlinedButton.icon(
                              onPressed: _endRally,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('ラリーを終了する'),
                            )
                          else
                            const Text(
                              '返技判定中です…',
                              style: TextStyle(color: Colors.white70),
                            ),
                        ],
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: state.active.posture == WrestlerPosture.stand
                                ? _goDown
                                : null,
                            icon: const Icon(Icons.arrow_downward),
                            label: const Text('ダウンする'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: state.active.posture == WrestlerPosture.down
                                ? _rest
                                : null,
                            icon: const Icon(Icons.self_improvement),
                            label: const Text('休息'),
                          ),
                          FilledButton.icon(
                            onPressed: _endTurn,
                            icon: const Icon(Icons.skip_next),
                            label: const Text('ターン終了'),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
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

  String _phaseLabel(TechniqueMatchPhase phase) => switch (phase) {
    TechniqueMatchPhase.start => '開始',
    TechniqueMatchPhase.draw => 'ドロー',
    TechniqueMatchPhase.energySet => 'エネルギーセット（行動可能）',
    TechniqueMatchPhase.end => '終了',
  };

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
  // ⑥ プレイヤー情報カード ＋ ② エネルギープール可視化 ＋ ③ ダウン強調
  // ============================================================

  Widget _playerCard(TechniqueMatchState state, int playerIndex, {required bool isNarrow}) {
    final player = state.playerAt(playerIndex);
    final isTurnOwner = playerIndex == state.activePlayerIndex;
    final effectiveAttackerIndex =
        state.rallyAttackerIndex ?? state.activePlayerIndex;
    final isEffectiveAttacker = playerIndex == effectiveAttackerIndex;
    final isPendingDefender =
        state.pendingAttack != null &&
        playerIndex == 1 - state.pendingAttack!.attackerIndex;
    // 手札をタップして攻撃を宣言できるのは、返技判定待ち・決着判定待ちが
    // 無く、試合が終了しておらず、かつ現在の実質的な攻撃側であるプレイヤーのみ。
    final canDeclare =
        state.pendingAttack == null &&
        state.pendingEscape == null &&
        state.pendingFinisher == null &&
        !state.isOver &&
        isEffectiveAttacker;
    final isPlayerA = playerIndex == 0;
    final hpRatio = player.maxHp == 0 ? 0.0 : player.hp / player.maxHp;
    final note = isPlayerA ? deckSourceNoteA : deckSourceNoteB;
    final roleLabel = isPendingDefender
        ? '返技判定待ち'
        : (state.isRallyActive && isEffectiveAttacker ? '攻撃側' : null);
    final isDownLike = player.posture != WrestlerPosture.stand;
    final postureColor = _postureColor(player.posture);

    return Card(
      color: isEffectiveAttacker || isPendingDefender ? _cardBg : _bg,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ③ ダウン状態の左端カラーバー（スタンド時は薄い緑）。
            Container(
              width: 5,
              color: isDownLike ? postureColor : postureColor.withValues(alpha: 0.35),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${player.wrestlerName}'
                            '${isTurnOwner ? "（手番）" : ""}'
                            '${roleLabel != null ? " ・ $roleLabel" : ""}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: postureColor.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                            border: isDownLike
                                ? Border.all(color: postureColor, width: 1)
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_postureIcon(player.posture), size: 12, color: postureColor),
                              const SizedBox(width: 3),
                              Text(
                                _postureLabel(player.posture),
                                style: TextStyle(
                                  color: postureColor,
                                  fontSize: 12,
                                  fontWeight: isDownLike ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.favorite, size: 12, color: _red),
                        const SizedBox(width: 3),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: hpRatio.clamp(0, 1),
                              minHeight: 8,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation(
                                hpRatio > 0.5 ? _green : (hpRatio > 0.2 ? _gold : _red),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${player.hp}/${player.maxHp}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'HEAT ${player.heat} ・ Lv.${player.level} ・ '
                      '手札${player.hand.length} ・ 山札${player.drawPile.length} ・ '
                      '捨て札${player.discardPile.length}'
                      '${player.removedPile.isNotEmpty ? " ・ 除外${player.removedPile.length}" : ""}'
                      '${player.reshuffleCount > 0 ? " ・ 再構築${player.reshuffleCount}/$maxDeckReshuffles" : ""}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    if (player.energyPool.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final attribute in player.energyPool.keys)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: _energyAttributeRow(
                            attribute,
                            player.energyPool[attribute] ?? 0,
                            player.spentEnergy[attribute] ?? 0,
                          ),
                        ),
                    ],
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          note,
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (player.hand.isNotEmpty)
                      Text(
                        canDeclare ? '手札をタップしてエネルギーセット／技を使用' : '相手の判定待ち…',
                        style: const TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry in player.hand)
                          _handCardTile(
                            state,
                            entry,
                            playerLevelTappable: canDeclare,
                            isRallyActive: state.isRallyActive,
                            compact: isNarrow,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ② エネルギープールをドット表示で可視化する（使用済み＝暗い縁取り、
  /// 使用可能＝金色の塗りつぶし）。
  Widget _energyAttributeRow(MoveAttribute attribute, int total, int spent) {
    final available = (total - spent).clamp(0, total);
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            moveAttributeLabel(attribute),
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
        ),
        for (var i = 0; i < spent; i++) _energyDot(filled: false),
        for (var i = 0; i < available; i++) _energyDot(filled: true),
        const SizedBox(width: 4),
        Text(
          '$available/$total',
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _energyDot({required bool filled}) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? _gold : Colors.transparent,
        border: Border.all(color: filled ? _gold : Colors.white30, width: 1),
      ),
    ),
  );

  // ============================================================
  // ① 手札のミニカード表示（使用可否・理由をカード上に表示）
  // ============================================================

  Widget _handCardTile(
    TechniqueMatchState state,
    TechniqueDeckEntry entry, {
    required bool playerLevelTappable,
    required bool isRallyActive,
    required bool compact,
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
    final visuallyDim = !tappable || (technique != null && !cardEligible);

    final width = compact ? 84.0 : 96.0;

    Color borderColor;
    Color? fillColor;
    if (technique?.hasFinisherEffect ?? false) {
      borderColor = _gold;
      fillColor = _gold.withValues(alpha: 0.10);
    } else if (isEnergyCard) {
      borderColor = _gold.withValues(alpha: 0.6);
      fillColor = _gold.withValues(alpha: 0.08);
    } else if (technique != null && (technique.hasPinEffect || technique.hasSubmissionEffect)) {
      borderColor = _orange;
      fillColor = null;
    } else {
      borderColor = Colors.white24;
      fillColor = null;
    }

    return Opacity(
      opacity: visuallyDim ? 0.5 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: tappable ? () => _showHandCardSheet(entry) : null,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: fillColor ?? const Color(0xff1a1120),
              border: Border.all(color: borderColor, width: 1.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (technique != null || energy != null)
                  Row(
                    children: [
                      _miniBadge(
                        moveAttributeLabel(technique?.attribute ?? energy!.attribute),
                        _gold,
                      ),
                      const Spacer(),
                      if (isEnergyCard)
                        const Icon(Icons.bolt, size: 12, color: _gold)
                      else if (technique != null)
                        Text(
                          '${technique.power}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  )
                else
                  _miniBadge(_defenseTypeLabel(defense), Colors.white54),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                if (technique != null) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      _miniBadge(_targetShortLabel(technique.targetState), Colors.white54),
                      if (technique.hasFinisherEffect)
                        _miniBadge('必殺', _gold)
                      else ...[
                        if (technique.hasPinEffect) _miniBadge('フォール', _orange),
                        if (technique.hasSubmissionEffect) _miniBadge('ギブアップ', _orange),
                      ],
                    ],
                  ),
                ],
                if (technique != null && technique.attackEnergyCost.values.any((v) => v > 0))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      technique.attackEnergyCost.entries
                          .where((e) => e.value > 0)
                          .map((e) => '${moveAttributeLabel(e.key)}${e.value}')
                          .join('・'),
                      style: const TextStyle(fontSize: 9, color: Colors.white54),
                    ),
                  ),
                if (technique != null && !cardEligible && reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      // カード上は短い定型ラベルのみ表示する（詳細な理由文は
                      // タップ後のダイアログに表示される。同じ文言をカードにも
                      // そのまま出すと、ダイアログが開いた状態で文言が重複し
                      // `find.textContaining` の一致対象があいまいになるため、
                      // あえて別の短い言い回しにしている）。
                      _shortReason(reason),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: _red),
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
  /// 短い定型ラベルへ要約する（①「使用できない理由を小さく表示」）。詳細な
  /// 理由文そのものはタップ後のダイアログに引き続き表示される。
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

  String _defenseTypeLabel(TechniqueDefenseCard? defense) => switch (defense?.type) {
    TechniqueDeckCardType.escape => 'エスケープ',
    TechniqueDeckCardType.reversal => 'リバーサル',
    TechniqueDeckCardType.kickOut => '防御札',
    TechniqueDeckCardType.ropeBreak => '防御札',
    _ => '防御札',
  };

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
  // ⑧ 進行ログにアイコン・色・強調文字を追加
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

  Widget _logSection(TechniqueMatchState state) => Card(
    color: _bg,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '進行ログ',
            style: TextStyle(fontWeight: FontWeight.bold, color: _gold),
          ),
          const SizedBox(height: 6),
          for (final line in state.log.reversed.take(20))
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
