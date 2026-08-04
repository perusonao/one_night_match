import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens.dart' show TitleScreen;
import '../game.dart' show GameCatalog;
import '../wrestler_editor/models.dart';
import '../wrestler_editor/repository.dart';
import 'battle_audio.dart';
import 'battle_presentation.dart';
import 'level_match_cost_preview.dart';
import 'level_match_deck_builder.dart';
import 'level_match_engine.dart';
import 'level_match_finish_models.dart';
import 'report_export.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);

// ===== Ver.0.7.2 UI改善：属性カラー統一（⑩） =====
/// 技属性の識別色（カード・アイコン・ラベルで共通利用）。
Color attributeColor(MoveAttribute a) => switch (a) {
  MoveAttribute.strike => const Color(0xffe4443a), // 🟥 打撃
  MoveAttribute.throwMove => const Color(0xff2f6df6), // 🟦 投げ
  MoveAttribute.submission => const Color(0xff2ea44f), // 🟩 関節
  MoveAttribute.aerial => const Color(0xff9b5de5), // 🟪 飛び
  MoveAttribute.rough => const Color(0xff3a3742), // ⚫ ラフ
  MoveAttribute.counter => const Color(0xffe8b23a), // 🟨 返し
};

/// 属性のフル表記（技カードのサブラベル用）。
String attributeFullLabel(MoveAttribute a) => switch (a) {
  MoveAttribute.strike => '打撃',
  MoveAttribute.throwMove => '投技',
  MoveAttribute.submission => '関節技',
  MoveAttribute.aerial => '飛技',
  MoveAttribute.rough => 'ラフ',
  MoveAttribute.counter => '返し技',
};

/// 属性バッジ（丸に一文字＋属性色）。
Widget attributeBadge(MoveAttribute a, {double size = 34}) => Container(
  width: size,
  height: size,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: attributeColor(a),
    shape: BoxShape.circle,
    boxShadow: [
      BoxShadow(color: attributeColor(a).withValues(alpha: 0.5), blurRadius: 6),
    ],
  ),
  child: Text(
    moveAttributeLabel(a),
    style: TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w900,
      fontSize: size * 0.42,
    ),
  ),
);

const _recommendPrefKey = 'onm_show_recommend';

/// 対応フェイズの選択肢の種別。
enum _RespKind { signature, basic, techniqueCard, take }

/// 対応フェイズで提示する1つの選択肢（返し技／単体技／受ける）。
class _RespOption {
  _RespOption({
    required this.kind,
    required this.label,
    required this.speed,
    required this.outcome,
    required this.score,
    this.move,
    this.cardId,
    this.attribute,
  });
  final _RespKind kind;
  final String label;
  final int speed;
  final ClashOutcome? outcome; // take は null
  final int score; // 並べ替え用（勝てる手ほど高い）
  final MoveDefinition? move;
  final String? cardId;
  final MoveAttribute? attribute;

  bool get isTake => kind == _RespKind.take;
  bool get wins =>
      outcome == ClashOutcome.counter || outcome == ClashOutcome.speedWin;
  String get key => switch (kind) {
    _RespKind.take => 'take',
    _RespKind.basic => 'basic:$cardId',
    _RespKind.techniqueCard => 'tech:$cardId',
    _RespKind.signature => 'sig:${move!.id}',
  };
}

/// Ver.0.3 演出：CPUターンの進行速度。ルールには影響しない。
enum MatchSpeed { fast, normal, slow, manual }

String matchSpeedLabel(MatchSpeed s) => switch (s) {
  MatchSpeed.fast => '高速',
  MatchSpeed.normal => '通常（推奨）',
  MatchSpeed.slow => 'ゆっくり',
  MatchSpeed.manual => '手動送り',
};

const _speedPrefKey = 'onm_match_speed';

/// 1ステップあたりの基本ウェイト。
Duration matchStepDelay(MatchSpeed s) => switch (s) {
  MatchSpeed.fast => const Duration(milliseconds: 130),
  MatchSpeed.normal => const Duration(milliseconds: 560),
  MatchSpeed.slow => const Duration(milliseconds: 950),
  MatchSpeed.manual => Duration.zero,
};

String finishReasonLabel(LevelFinishReason? reason) => switch (reason) {
  LevelFinishReason.pinfall => '3カウント',
  LevelFinishReason.submission => 'ギブアップ',
  LevelFinishReason.exhaustion => '引き分け（消耗の果て）',
  LevelFinishReason.decision => '時間切れ判定(旧仕様)',
  LevelFinishReason.draw => '引き分け（時間切れ）',
  LevelFinishReason.deckOut => 'デッキ切れ(旧仕様)',
  LevelFinishReason.hpZero => 'HP0(旧仕様)',
  null => '-',
};

class LevelMatchIntroScreen extends StatelessWidget {
  const LevelMatchIntroScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('レベルカードマッチ Ver.0.7')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.layers, size: 64, color: _pink),
            const Text(
              '技をつなぎ、消耗させ、\n3カウントかギブアップを奪え。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            for (final line in const [
              '毎ターン、技エネルギーカードを1枚セット（場に残り続ける）',
              '自分のターン開始時にエネルギーは全回復（アンタップ）',
              'エネルギーが貯まった属性の固有技・技カードが使える',
              '固有技＝レスラー専用（決着＝フォール/ギブアップ可）',
              '技カード＝手札のカードをそのまま繰り出す（使うと捨て札）',
              'レスラーごとに30枚デッキを自動生成',
              '技を宣言 → 相手が対応（固有技で迎撃・返し技・受ける）',
              '速い技が先に命中し、遅い技を潰す',
              '返し技は対応する相手技があるときだけ使える',
              'HPは消耗の指標（0でも試合は続く）',
              'キックアウトは返すほど重くなる',
              '山札切れは敗北でなく“疲労”（毎ターンHP減）',
              '決着は3カウントかギブアップのみ。時間切れは引き分け',
            ])
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: _gold),
                  title: Text(line),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LevelMatchSelectScreen(),
                ),
              ),
              icon: const Icon(Icons.sports_mma),
              label: const Padding(
                padding: EdgeInsets.all(14),
                child: Text('レスラーを選ぶ'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LevelMatchSelectScreen extends StatefulWidget {
  const LevelMatchSelectScreen({super.key, this.repository});
  final LocalWrestlerRepository? repository;

  @override
  State<LevelMatchSelectScreen> createState() => _LevelMatchSelectScreenState();
}

class _LevelMatchSelectScreenState extends State<LevelMatchSelectScreen> {
  late final LocalWrestlerRepository repository =
      widget.repository ?? LocalWrestlerRepository();
  List<WrestlerDefinition>? wrestlers;

  @override
  void initState() {
    super.initState();
    repository.loadAll().then((items) {
      if (mounted) setState(() => wrestlers = items);
    });
  }

  List<String> _problems(WrestlerDefinition wrestler) {
    final errors = <String>[];
    if (wrestler.maxHp < 1) errors.add('最大HPが不正');
    final level1 = wrestler.levels.where((item) => item.level == 1);
    if (level1.isEmpty) return [...errors, 'Level 1がありません'];
    if (level1.first.moveIds.isEmpty) errors.add('Level 1に通常技がありません');
    for (final id in level1.first.moveIds) {
      final move = repository.moves[id];
      if (move == null) {
        errors.add('技ID $id が見つかりません');
      } else if (move.requiredCards.values.any((value) => value < 0)) {
        errors.add('${move.name}の必要カードが不正');
      }
    }
    return errors;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ver.0.7 レスラー選択')),
    body: wrestlers == null
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: wrestlers!.length,
            itemBuilder: (_, index) {
              final wrestler = wrestlers![index];
              final errors = _problems(wrestler);
              final level1 = wrestler.levels
                  .where((item) => item.level == 1)
                  .firstOrNull;
              final level3 = wrestler.levels
                  .where((item) => item.level == 3)
                  .firstOrNull;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wrestler.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        wrestler.subtitle,
                        style: const TextStyle(color: _gold),
                      ),
                      Text(
                        'MAX HP ${wrestler.maxHp} / Level ${wrestler.levels.length}',
                      ),
                      if (level1 != null)
                        Text(
                          'Lv.1技 ${level1.moveIds.map((id) => repository.moves[id]?.name ?? id).join(" / ")}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      Text(
                        'フィニッシャー ${repository.moves[level3?.finisherId]?.name ?? "なし"}'
                        '${_finisherKind(repository.moves[level3?.finisherId])}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        errors.isEmpty ? '✓ 対戦可能' : '× ${errors.join(" / ")}',
                        style: TextStyle(
                          color: errors.isEmpty
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => _showDeckPreview(wrestler),
                            icon: const Icon(Icons.style, size: 18),
                            label: const Text('デッキ確認'),
                          ),
                          const SizedBox(width: 6),
                          FilledButton(
                            onPressed: errors.isEmpty
                                ? () => _start(wrestler)
                                : null,
                            child: const Text('このレスラーで開始'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );

  String _finisherKind(MoveDefinition? move) {
    if (move == null) return '';
    if (move.offersSubmission) return '（ギブアップ）';
    if (move.offersPin) return '（フォール）';
    return '';
  }

  void _showDeckPreview(WrestlerDefinition wrestler) {
    final deck = const LevelMatchDeckBuilder().buildEnergyMode(
      wrestler: wrestler,
      moves: repository.moves,
      owner: 'preview',
    );
    final techCount = deck.cards.where((c) => !c.isEnergyOnly).length;
    final energyCount = deck.cards.length - techCount;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                '${wrestler.name} 自動生成デッキ',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '合計 ${deck.cards.length} 枚'
                '${deck.usedFallback ? "（フォールバック）" : ""}'
                '　🥊技カード $techCount / ⚡エネルギーカード $energyCount',
                style: const TextStyle(color: _gold),
              ),
              const Divider(),
              for (final attribute in MoveAttribute.values)
                if ((deck.counts[attribute] ?? 0) > 0 ||
                    deck.usedAttributes.contains(attribute))
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(moveAttributeLabel(attribute)),
                    ),
                    title: Text(
                      '${moveAttributeLabel(attribute)}属性 ${deck.counts[attribute] ?? 0} 枚'
                      '（技${deck.cards.where((c) => c.attribute == attribute && !c.isEnergyOnly).length}'
                      ' / エネ${deck.cards.where((c) => c.attribute == attribute && c.isEnergyOnly).length}）',
                    ),
                    subtitle: Text(
                      deck.attributeReasons[attribute]!.isEmpty
                          ? '—'
                          : deck.attributeReasons[attribute]!.join(' / '),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              if (deck.failureReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    deck.failureReason!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start(WrestlerDefinition player) async {
    // Ver.0.9: 旧ルール（クラシック）は廃止。エネルギールールのみで開始する。
    final seconds = await _pickMatchTime();
    if (seconds == null || !mounted) return;
    final candidates = wrestlers!
        .where((item) => item.id != player.id && _problems(item).isEmpty)
        .toList();
    final cpu = candidates.isEmpty ? player : candidates.first;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LevelMatchBattleScreen(
          engine: LevelMatchEngine.create(
            playerWrestler: player,
            cpuWrestler: cpu,
            moves: repository.moves,
            playerStarts: true,
            matchTimeSeconds: seconds,
            resourceMode: MatchResourceMode.energy,
          ),
        ),
      ),
    );
  }

  Future<int?> _pickMatchTime() => showModalBottomSheet<int>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('試合時間を選択',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          for (final option in const [
            ('無制限', 0),
            ('15分一本勝負', 900),
            ('30分一本勝負', 1800),
            ('60分一本勝負', 3600),
          ])
            ListTile(
              leading: Icon(
                option.$2 == 0 ? Icons.all_inclusive : Icons.timer_outlined,
              ),
              title: Text(option.$1),
              subtitle: option.$2 == 0
                  ? const Text('時間切れなし')
                  : Text('${option.$2 ~/ 30}ターン / 1ターン=30秒'),
              onTap: () => Navigator.pop(context, option.$2),
            ),
        ],
      ),
    ),
  );
}

class LevelMatchBattleScreen extends StatefulWidget {
  const LevelMatchBattleScreen({super.key, required this.engine});
  final LevelMatchEngine engine;
  @override
  State<LevelMatchBattleScreen> createState() => _LevelMatchBattleScreenState();
}

class _LevelMatchBattleScreenState extends State<LevelMatchBattleScreen>
    with SingleTickerProviderStateMixin {
  LevelMatchEngine get engine => widget.engine;
  LevelMatchState get state => engine.state;
  bool _driving = false;

  // Ver.0.3 演出用の状態（ルールには影響しない）。
  MatchSpeed _speed = MatchSpeed.normal;
  Completer<void>? _manualGate;
  String? _commentary; // 実況テキスト

  // Ver.0.7.2 UI改善用。
  bool _showRecommend = true; // おすすめ表示（⑤）
  String? _selResponseKey; // 現在フォーカス中の対応（⑥⑦）

  // Ver.0.7.5：CPU思考の実況ローテーション（⑦）。
  Timer? _thinkTimer;
  int _thinkTick = 0;

  // ===== Ver.0.9 演出システム：BattleEventQueue / 演出制御 =====
  // エンジン（level_match_engine.dart）には一切手を加えず、試合ログの
  // 差分から演出イベント列を組み立てて段階的に見せる“表示専用”レイヤー。
  final BattleAudio _audio = BattleAudio();
  static const BattleEventQueue _eventQueue = BattleEventQueue();
  BattleEvent? _currentEvent; // 現在表示中の演出（技名/対応/ヒット/HEAT等）
  BattleEvent? _finisherEvent; // 必殺技カットイン（フルスクリーン演出）
  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  Animation<Offset> _shakeAnim = const AlwaysStoppedAnimation(Offset.zero);

  LevelMatchCostPreview get _preview => LevelMatchCostPreview(
    wrestler: state.player.wrestler,
    moves: engine.moves,
  );

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final raw = prefs.getString(_speedPrefKey);
      final loaded = MatchSpeed.values
          .cast<MatchSpeed?>()
          .firstWhere((s) => s!.name == raw, orElse: () => null);
      final rec = prefs.getBool(_recommendPrefKey) ?? true;
      if (mounted) {
        setState(() {
          if (loaded != null) _speed = loaded;
          _showRecommend = rec;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _drive());
    });
    // CPU思考中の“実況ざわめき”をローテーション表示（ルール非干渉）。
    _thinkTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted || state.isGameOver) return;
      if (engine.decisionOwnerId() == 'cpu') {
        setState(() => _thinkTick++);
      }
    });
  }

  @override
  void dispose() {
    _thinkTimer?.cancel();
    _shakeController.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Stack(
            children: [
              _unified(),
              if (_currentEvent != null) _beatBanner(_currentEvent!),
              if (_finisherEvent != null) _finisherCutinOverlay(_finisherEvent!),
            ],
          ),
        ),
      ),
    ),
  );

  // ===== Ver.0.9 演出システム：ヒットバナー／必殺技カットイン =====
  Color _beatColor(BattleBeatKind kind) => switch (kind) {
    BattleBeatKind.announce => _gold,
    BattleBeatKind.finisherCutin => _gold,
    BattleBeatKind.response => Colors.white70,
    BattleBeatKind.clash => Colors.lightBlueAccent,
    BattleBeatKind.hit => Colors.redAccent,
    BattleBeatKind.heat => _gold,
    BattleBeatKind.down => Colors.orangeAccent,
    BattleBeatKind.pinDeclare => _pink,
    BattleBeatKind.pinCount => Colors.white,
    BattleBeatKind.kickOutResult => Colors.greenAccent,
    BattleBeatKind.pinResult => _gold,
    BattleBeatKind.submissionDeclare => _pink,
    BattleBeatKind.submissionResult => _gold,
    BattleBeatKind.unlock => Colors.purpleAccent,
    BattleBeatKind.info => Colors.white54,
  };

  Widget _beatBanner(BattleEvent event) {
    const bigKinds = {
      BattleBeatKind.pinCount,
      BattleBeatKind.pinResult,
      BattleBeatKind.submissionResult,
      BattleBeatKind.kickOutResult,
    };
    final big = bigKinds.contains(event.kind);
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -0.32),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: big ? 22 : 16, vertical: big ? 12 : 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _beatColor(event.kind), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: big ? 30 : 18,
                      fontWeight: FontWeight.w900,
                      color: _beatColor(event.kind)),
                ),
                if (event.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(event.subtitle!,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _finisherCutinOverlay(BattleEvent event) => Positioned.fill(
    child: IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (event.subtitle != null)
              Text(event.subtitle!,
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                      fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              event.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w900, color: _gold),
            ),
            const SizedBox(height: 4),
            const Text('！！',
                style: TextStyle(
                    fontSize: 28,
                    color: _gold,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    ),
  );

  void _triggerShake(double intensity, Duration duration) {
    if (intensity <= 0 || duration <= Duration.zero) return;
    _shakeController.duration = duration;
    final seq = TweenSequence<Offset>([
      TweenSequenceItem(
          tween: Tween(begin: Offset.zero, end: Offset(intensity, 0)),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(
              begin: Offset(intensity, 0), end: Offset(-intensity * 0.7, 0)),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(
              begin: Offset(-intensity * 0.7, 0),
              end: Offset(intensity * 0.4, 0)),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Offset(intensity * 0.4, 0), end: Offset.zero),
          weight: 1),
    ]);
    _shakeAnim = seq.animate(_shakeController);
    _shakeController.forward(from: 0);
  }

  Widget _ringShake(Widget child) => AnimatedBuilder(
    animation: _shakeController,
    builder: (_, c) => Transform.translate(offset: _shakeAnim.value, child: c),
    child: child,
  );

  // ===== Ver.0.7.5：全フェーズ共通レイアウト（①） =====
  // 相手情報 → 現在の状況 → 行動エリア → 直前ログ → 自分情報 → 次の操作。
  // 中央（現在の状況／行動）だけがフェーズで切り替わる。
  // Ver.0.7.6：縦1画面・スクロールなし。固定の枠（相手/状況/自分/操作）の間で、
  // 行動エリアだけが残りの高さを埋める（内部スクロールは保険で、通常は出ない）。
  Widget _unified() => Column(
    children: [
      _topBarSlim(),
      _stepIndicator(),
      _ringShake(
        Column(
          children: [
            _fighterPanelV2(state.cpu, isCpu: true),
            _statusRow(),
            _centerFor(),
          ],
        ),
      ),
      Expanded(
        child: state.isGameOver
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: _actionFor(),
              ),
      ),
      _fighterPanelV2(state.player, isCpu: false),
      _nextActionHint(),
      _controlBar(),
    ],
  );

  Widget _topBarSlim() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
    child: Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '戻る',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        const Text('LEVEL CARD MATCH',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'ログ全文',
          onPressed: _showLogs,
          icon: Badge(
            label: Text('${state.logs.length}'),
            child: const Icon(Icons.receipt_long, size: 20),
          ),
        ),
      ],
    ),
  );

  // ===== Ver.0.9 UX改善④：現在のフェーズをSTEPで明示 =====
  // 「今何をすればいいか」を一目で分かるようにする常設インジケーター。
  // ルールには一切影響しない表示専用のもの。
  static const _classicStepLabels = ['カード', 'レベル', '技', '対応', '結果'];
  static const _energyStepLabels = ['エネルギー', 'レベル', '技', '対応', '結果'];

  int _currentStepIndex() => switch (state.phase) {
    LevelMatchPhase.setup ||
    LevelMatchPhase.draw ||
    LevelMatchPhase.setCard => 0,
    LevelMatchPhase.unlockCheck || LevelMatchPhase.levelChange => 1,
    LevelMatchPhase.chooseMove => 2,
    LevelMatchPhase.responseSelection ||
    LevelMatchPhase.resolveMove ||
    LevelMatchPhase.pinDecision ||
    LevelMatchPhase.kickOutDecision ||
    LevelMatchPhase.submissionDecision => 3,
    LevelMatchPhase.turnEnd || LevelMatchPhase.gameOver => 4,
  };

  Widget _stepIndicator() {
    if (state.isGameOver) return const SizedBox.shrink();
    final labels = _isEnergyMode ? _energyStepLabels : _classicStepLabels;
    final current = _currentStepIndex();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 3),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: SizedBox(
                  height: 20,
                  child: Center(
                    child: Container(
                      height: 2,
                      color: i <= current
                          ? _pink.withValues(alpha: 0.6)
                          : Colors.white12,
                    ),
                  ),
                ),
              ),
            _stepDot(i, labels[i], current),
          ],
        ],
      ),
    );
  }

  Widget _stepDot(int index, String label, int current) {
    final isCurrent = index == current;
    final isDone = index < current;
    final ringColor = isCurrent
        ? _pink
        : (isDone ? Colors.white54 : Colors.white24);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isCurrent ? 20 : 14,
          height: isCurrent ? 20 : 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCurrent
                ? _pink
                : (isDone ? Colors.white38 : Colors.transparent),
            border: Border.all(color: ringColor, width: isCurrent ? 2 : 1),
          ),
          child: isDone
              ? const Icon(Icons.check, size: 9, color: Colors.black)
              : (isCurrent
                    ? Text(
                        '${index + 1}',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white),
                      )
                    : null),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
              fontSize: 8.5,
              fontWeight: isCurrent ? FontWeight.w900 : FontWeight.normal,
              color: isCurrent ? _pink : Colors.white38),
        ),
      ],
    );
  }

  Color _themeColor(PlayerLevelMatchState f) =>
      Color(int.parse(f.wrestler.themeColor.replaceFirst('#', '0xff')));

  // ===== 相手／自分の共通パネル（③） =====
  Widget _fighterPanelV2(PlayerLevelMatchState f, {required bool isCpu}) {
    final color = _themeColor(f);
    final ready = !f.finisherUsed;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.22), Colors.black26],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color,
            child: Text(
              f.wrestler.name.isEmpty ? '?' : f.wrestler.name.substring(0, 1),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isCpu)
                      const Text('CPU ',
                          style: TextStyle(
                              color: _pink,
                              fontWeight: FontWeight.w900,
                              fontSize: 11)),
                    Flexible(
                      child: Text(f.wrestler.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    Text('Lv.${f.currentLevel}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                    const SizedBox(width: 8),
                    Text('HP ${f.currentHp}/${f.wrestler.maxHp}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: f.wrestler.maxHp == 0
                        ? 0
                        : f.currentHp / f.wrestler.maxHp,
                    backgroundColor: Colors.white12,
                    color: isCpu ? Colors.purpleAccent : _pink,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    GestureDetector(
                      onTap: isCpu ? null : () => _showHandSheet(f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (isCpu ? Colors.white24 : _pink)
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('手札 ${f.hand.length}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: isCpu ? Colors.white70 : _pink,
                                    fontWeight: FontWeight.bold)),
                            if (!isCpu) ...[
                              const SizedBox(width: 2),
                              const Icon(Icons.visibility,
                                  size: 11, color: _pink),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (state.resourceMode == MatchResourceMode.energy)
                      _chip(
                        'EN ${f.energyZone.where((e) => e.ready).length}/${f.energyZone.length}',
                        color: Colors.lightBlueAccent,
                      )
                    else
                      _chip('セット ${f.setCards.length}'),
                    const SizedBox(width: 6),
                    _chip(ready ? 'FIN○' : 'FIN✕',
                        color: ready ? Colors.greenAccent : Colors.white38),
                    const Spacer(),
                    InkWell(
                      onTap: _showDetailSheet,
                      child: const Row(
                        children: [
                          Text('詳細',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white70)),
                          Icon(Icons.keyboard_arrow_down,
                              size: 14, color: Colors.white70),
                        ],
                      ),
                    ),
                  ],
                ),
                if (state.resourceMode == MatchResourceMode.energy)
                  _energyZoneRow(f),
                if (!isCpu) _finisherPips(f),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: (color ?? Colors.white24).withValues(alpha: 0.6)),
    ),
    child: Text(text,
        style: TextStyle(
            fontSize: 10.5,
            color: color ?? Colors.white70,
            fontWeight: FontWeight.bold)),
  );

  // ===== Ver.0.8.0 energyモード：エネルギーゾーン（属性別 Ready/Used） =====
  Widget _energyZoneRow(PlayerLevelMatchState f) {
    final ready = f.readyEnergyCounts;
    final used = <MoveAttribute, int>{};
    for (final e in f.energyZone) {
      if (!e.ready) used[e.attribute] = (used[e.attribute] ?? 0) + 1;
    }
    final attrs = MoveAttribute.values
        .where((a) => (ready[a] ?? 0) > 0 || (used[a] ?? 0) > 0)
        .toList();
    if (attrs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final a in attrs)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: attributeColor(a).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: attributeColor(a)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  attributeBadge(a, size: 16),
                  const SizedBox(width: 3),
                  Text(
                    '${ready[a] ?? 0}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.greenAccent),
                  ),
                  if ((used[a] ?? 0) > 0)
                    Text(
                      '+${used[a]}済',
                      style: const TextStyle(
                          fontSize: 9, color: Colors.white38),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _finisherPips(PlayerLevelMatchState f) {
    final info = _finisherHeatInfo(f);
    if (!info.has) return const SizedBox.shrink();
    final ready = info.unlocked || info.remaining == 0;
    const pips = 6;
    final filled = info.threshold == 0
        ? 0
        : ((state.sharedHeat / info.threshold) * pips)
            .clamp(0, pips)
            .round();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Text('FINISHER',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: _gold)),
          const SizedBox(width: 6),
          for (var i = 0; i < pips; i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(
                i < filled ? Icons.hexagon : Icons.hexagon_outlined,
                size: 12,
                color: i < filled ? _gold : Colors.white24,
              ),
            ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              ready ? '使用可能！' : 'あと${info.remaining}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 9,
                  color: ready ? Colors.greenAccent : Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  // ===== TURN + 試合の流れ + HEAT（⑨） =====
  Widget _statusRow() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff3a1330), Color(0xff1a1120)],
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Column(
          children: [
            const Text('TURN',
                style: TextStyle(fontSize: 9, color: Colors.white54)),
            Text('${state.turnNumber}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900)),
          ],
        ),
        if (state.isTimed) ...[
          const SizedBox(width: 10),
          _timeDisplay(),
        ],
        const SizedBox(width: 10),
        Expanded(flex: 5, child: _matchFlowGauge()),
        const SizedBox(width: 10),
        Expanded(flex: 6, child: _heatGauge()),
      ],
    ),
  );

  Widget _timeDisplay() {
    final secs = state.remainingSeconds ?? 0;
    final mm = (secs ~/ 60).toString();
    final ss = (secs % 60).toString().padLeft(2, '0');
    final low = secs <= 60;
    final warn = secs <= 180;
    final color = low
        ? Colors.redAccent
        : (warn ? _gold : Colors.white);
    return Column(
      children: [
        Text('TIME',
            style: TextStyle(
                fontSize: 9,
                color: low ? Colors.redAccent : Colors.white54)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (warn)
              Icon(Icons.alarm,
                  size: 13, color: color.withValues(alpha: low ? 1 : 0.8)),
            Text('$mm:$ss',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color)),
          ],
        ),
      ],
    );
  }

  double _matchProgress() {
    final p = state.player, c = state.cpu;
    final turnP = (state.turnNumber / 24).clamp(0.0, 1.0);
    final minHp = [
      p.wrestler.maxHp == 0 ? 1.0 : p.currentHp / p.wrestler.maxHp,
      c.wrestler.maxHp == 0 ? 1.0 : c.currentHp / c.wrestler.maxHp,
    ].reduce((a, b) => a < b ? a : b);
    final dmgP = (1 - minHp).clamp(0.0, 1.0);
    final heatP = (state.sharedHeat / 60).clamp(0.0, 1.0);
    return (turnP * 0.4 + dmgP * 0.4 + heatP * 0.2).clamp(0.0, 1.0);
  }

  Widget _matchFlowGauge() {
    final prog = _matchProgress();
    final (label, color) = prog < 0.34
        ? ('序盤', Colors.lightBlueAccent)
        : prog < 0.67
            ? ('中盤', _gold)
            : ('終盤', Colors.redAccent);
    const segments = 8;
    final filled = (prog * segments).clamp(0, segments).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('試合の流れ',
                style: TextStyle(fontSize: 10, color: Colors.white54)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (var i = 0; i < segments; i++)
              Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: i < filled
                        ? Color.lerp(Colors.lightBlueAccent, Colors.redAccent,
                            i / segments)!
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ===== 現在の状況（②）＋実況（⑫）：縦1画面用コンパクト版 =====
  Widget _centerFor() {
    final atk = state.pendingAttack;
    if (!state.isGameOver &&
        state.phase == LevelMatchPhase.responseSelection &&
        atk?.defenderId == 'player') {
      final m = engine.moves[atk!.moveId]!;
      final offersPin = m.offersPin && !atk.isBasic;
      final offersSub = m.offersSubmission && !atk.isBasic;
      final accent = attributeColor(m.attribute);
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.25), Colors.black26]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            attributeBadge(m.attribute, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('相手の攻撃！',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: _pink)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('${state.cpu.wrestler.name}の${m.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _statChip('威力', '${m.power}', Colors.redAccent),
                      const SizedBox(width: 12),
                      _statChip('速度', '${m.speed}', Colors.lightBlueAccent),
                      const SizedBox(width: 10),
                      if (offersPin || offersSub)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _gold.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _gold),
                          ),
                          child: Text(offersPin ? 'フォール技' : 'ギブアップ技',
                              style: const TextStyle(
                                  color: _gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final (head, sub, color) = _situation();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xff241a30), Color(0xff140f1c)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(head,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: color)),
                if (sub.isNotEmpty)
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text('🎤 ${_commentaryLines().first}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ),
        ],
      ),
    );
  }

  (String, String, Color) _situation() {
    final atk = state.pendingAttack;
    final pin = state.pendingPin;
    final sub = state.pendingSubmission;
    if (state.phase == LevelMatchPhase.pinDecision &&
        pin?.attackerId == 'player') {
      return ('フォールのチャンス！', '3カウントを奪いにいける！', _gold);
    }
    if (state.phase == LevelMatchPhase.kickOutDecision &&
        pin?.defenderId == 'player') {
      return ('ピンチ！ 押さえ込まれた', 'キックアウトするか選択', Colors.redAccent);
    }
    if (state.phase == LevelMatchPhase.submissionDecision &&
        sub?.defenderId == 'player') {
      return ('ギブアップの危機！', '耐えるか選択', Colors.redAccent);
    }
    if (atk?.defenderId == 'cpu' &&
        state.phase == LevelMatchPhase.responseSelection) {
      return ('${state.cpu.wrestler.name}が対応中…', '相手がどう返すか！？', Colors.purpleAccent);
    }
    if (engine.decisionOwnerId() == 'cpu' || state.activePlayerId == 'cpu') {
      return ('${state.cpu.wrestler.name}の手番', '相手の出方をうかがう…', Colors.purpleAccent);
    }
    return switch (state.phase) {
      LevelMatchPhase.setCard => _isEnergyMode
          ? ('エネルギーセット', 'エネルギーカードを1枚セット（永続・毎ターン回復）', _gold)
          : ('カードセット', 'このターンに備えるカードを1枚セット', _gold),
      LevelMatchPhase.levelChange => ('レベルチェンジ', '上げるレベルを選ぶ（維持も可）', _gold),
      LevelMatchPhase.chooseMove => ('あなたの攻撃', '繰り出す技を選んでください', _pink),
      _ => ('試合進行中', '', _pink),
    };
  }

  List<String> _commentaryLines() {
    // CPU思考中は“ざわめき”をローテーション（⑦）。
    if (engine.decisionOwnerId() == 'cpu' && !state.isGameOver) {
      final name = state.cpu.wrestler.name;
      final pool = <List<String>>[
        ['$nameが間合いを計っている…', '会場がざわめく…'],
        ['$nameが次の一手を読んでいる…', '緊張が高まっていく…'],
        ['$nameが仕掛けどきを探る…', '観客が固唾を飲む…'],
        ['$nameがじりっと詰め寄る！', 'どう出る！？'],
      ];
      return pool[_thinkTick % pool.length];
    }
    final lines = <String>[];
    if (_commentary != null) lines.add(_commentary!);
    if (state.logs.isNotEmpty) {
      final last = state.logs.last.message;
      if (last != _commentary) lines.add(last);
    }
    return lines.isEmpty ? const ['試合を進めよう！'] : lines;
  }

  // ===== 行動エリア（フェーズ別） =====
  Widget _actionFor() {
    final atk = state.pendingAttack;
    final pin = state.pendingPin;
    final sub = state.pendingSubmission;
    if (state.phase == LevelMatchPhase.responseSelection &&
        atk?.defenderId == 'player') {
      return _responseListV2(atk!);
    }
    if (state.phase == LevelMatchPhase.pinDecision &&
        pin?.attackerId == 'player') {
      return _pinDeclareCard(pin!);
    }
    if (state.phase == LevelMatchPhase.kickOutDecision &&
        pin?.defenderId == 'player') {
      return _kickOutCard(pin!);
    }
    if (state.phase == LevelMatchPhase.submissionDecision &&
        sub?.defenderId == 'player') {
      return _submissionCard(sub!);
    }
    if (state.activePlayerId == 'player') {
      return switch (state.phase) {
        LevelMatchPhase.setCard => _setCardPhase(state.player),
        LevelMatchPhase.levelChange => _levelPhase(state.player),
        LevelMatchPhase.chooseMove => _movePhase(state.player),
        _ => _waiting(),
      };
    }
    return _waiting();
  }

  // ===== 対応リスト（縦・⑥⑪） =====
  (int, String, Color, String) _successInfo(_RespOption o) {
    if (o.isTake) {
      return (1, '受ける（防御）', Colors.redAccent, 'ダメージを受けるリスクが高い…');
    }
    return switch (o.outcome!) {
      ClashOutcome.counter => (5, '返し成立！', Colors.greenAccent, '攻撃を無効化し反撃！'),
      ClashOutcome.speedWin =>
        (5, '速度勝ち！', Colors.greenAccent, '攻撃を無効化しダメージを与える！'),
      ClashOutcome.neutral => (3, '同速勝負', _gold, '成功すれば攻撃を無効化！'),
      ClashOutcome.speedLoss => (1, '速度負け…', Colors.redAccent, 'ダメージを与えられない'),
    };
  }

  Widget _responseListV2(PendingAttack atk) {
    final attackMove = engine.moves[atk.moveId]!;
    final options = _buildResponseOptions(atk);
    final recommended = options.firstWhere(
      (o) => o.wins,
      orElse: () => options.firstWhere((o) => o.isTake),
    );
    final selectedKey = _selResponseKey ?? recommended.key;
    final selected = options.firstWhere(
      (o) => o.key == selectedKey,
      orElse: () => recommended,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Row(
            children: [
              const Text('あなたの対応を選択してください',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              TextButton.icon(
                onPressed: _showResponseHelp,
                icon: const Icon(Icons.help_outline, size: 15),
                label: const Text('ヘルプ', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        for (final o in options)
          _responseRow(
            o,
            attackMove,
            selected: o.key == selectedKey,
            recommended: _showRecommend && o.key == recommended.key,
          ),
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text('カードをタップすると詳細と予測が確認できます',
              style: TextStyle(fontSize: 10.5, color: Colors.white54)),
        ),
        _speedPredictBar(selected, attackMove),
      ],
    );
  }

  Widget _responseRow(
    _RespOption o,
    MoveDefinition attackMove, {
    required bool selected,
    required bool recommended,
  }) {
    final (stars, label, color, reason) = _successInfo(o);
    final dmg = o.isTake ? attackMove.power : (o.wins ? (o.move?.power ?? 0) : 0);
    final dmgLabel = o.isTake ? '予測被ダメ' : '予測ダメージ';
    return GestureDetector(
      onTap: () => setState(() => _selResponseKey = o.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: selected ? 0.22 : 0.1),
              Colors.black.withValues(alpha: 0.4),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _gold : color.withValues(alpha: 0.6),
            width: selected ? 2.4 : 1.2,
          ),
          boxShadow: selected
              ? [BoxShadow(color: _gold.withValues(alpha: 0.4), blurRadius: 10)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recommended)
              Container(
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('★ おすすめ！',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 11)),
              ),
            Row(
              children: [
                if (o.attribute != null)
                  attributeBadge(o.attribute!, size: 30)
                else
                  const Icon(Icons.shield, color: Colors.redAccent, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < 5; i++)
                            Icon(
                              i < stars ? Icons.star : Icons.star_border,
                              size: 13,
                              color: color,
                            ),
                        ],
                      ),
                      Text(o.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900)),
                      if (_isEnergyMode && o.move != null)
                        Text(
                          o.move!.energyModeRequiredCards.entries
                              .map((e) =>
                                  '${moveAttributeLabel(e.key)}×${e.value}')
                              .join(' '),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.lightBlueAccent),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(dmgLabel,
                        style: const TextStyle(
                            fontSize: 9, color: Colors.white54)),
                    Text('$dmg',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: o.isTake
                                ? Colors.redAccent
                                : (dmg > 0
                                    ? Colors.redAccent
                                    : Colors.white38))),
                  ],
                ),
                const SizedBox(width: 8),
                selected
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: o.isTake ? Colors.redAccent : _pink,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _commitResponse(o),
                        child: const Text('決定',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    : const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (!o.isTake)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('速度 ${o.speed}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 次の操作ヒント（⑩） =====
  (IconData, String) _hintFor() {
    if (state.isGameOver) return (Icons.flag, '試合終了');
    final atk = state.pendingAttack;
    final pin = state.pendingPin;
    final sub = state.pendingSubmission;
    if (state.phase == LevelMatchPhase.responseSelection &&
        atk?.defenderId == 'player') {
      return (Icons.touch_app, '対応するカードを選び「決定」');
    }
    if (state.phase == LevelMatchPhase.pinDecision &&
        pin?.attackerId == 'player') {
      return (Icons.sports_mma, 'フォールするか選んでください');
    }
    if (state.phase == LevelMatchPhase.kickOutDecision &&
        pin?.defenderId == 'player') {
      return (Icons.fitness_center, 'キックアウトするか選んでください');
    }
    if (state.phase == LevelMatchPhase.submissionDecision &&
        sub?.defenderId == 'player') {
      return (Icons.pan_tool, '耐えるか選んでください');
    }
    if (state.activePlayerId == 'player') {
      return switch (state.phase) {
        LevelMatchPhase.setCard => (Icons.touch_app, 'カードを1枚選ぶ、または「セットしない」'),
        LevelMatchPhase.levelChange => (Icons.arrow_upward, 'レベルを選ぶ、または「維持」'),
        LevelMatchPhase.chooseMove => (Icons.sports_kabaddi, '繰り出す技を選んでください'),
        _ => (Icons.hourglass_empty, '相手の行動を待っています'),
      };
    }
    return (Icons.hourglass_empty, '相手の行動を待っています…');
  }

  Widget _nextActionHint() {
    final (icon, text) = _hintFor();
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_pink.withValues(alpha: 0.28), Colors.black26],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _pink.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: _pink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('次の操作',
                    style: TextStyle(
                        fontSize: 10,
                        color: _pink,
                        fontWeight: FontWeight.w900)),
                Text(text,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== 下部コントロール（手動送り / オート / 設定） =====
  Widget _controlBar() {
    final manualWaiting = _manualGate != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: _ctrlBtn(
              manualWaiting ? Icons.play_arrow : Icons.skip_next,
              manualWaiting ? '次へ' : '手動送り',
              () async {
                if (manualWaiting) {
                  _manualGate?.complete();
                } else {
                  setState(() => _speed = MatchSpeed.manual);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(_speedPrefKey, MatchSpeed.manual.name);
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ctrlBtn(Icons.fast_forward, 'オート', () async {
              setState(() => _speed = MatchSpeed.normal);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_speedPrefKey, MatchSpeed.normal.name);
              _manualGate?.complete();
            }),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ctrlBtn(Icons.settings, '設定', _showSettings),
          ),
        ],
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  // ===== Ver.0.7.2 UI改善：対応フェイズ（中継風レイアウト） =====

  /// 対応候補を構築（返し技＞速い単体技＞受ける）。おすすめ計算にも使う。
  List<_RespOption> _buildResponseOptions(PendingAttack atk) {
    final player = state.player;
    final attackMove = engine.moves[atk.moveId]!;
    int scoreOf(ClashOutcome o, int power) => switch (o) {
      ClashOutcome.counter => 300 + power,
      ClashOutcome.speedWin => 200 + power,
      ClashOutcome.neutral => 20 + power,
      ClashOutcome.speedLoss => power,
    };
    final options = <_RespOption>[];
    // 返し技／固有技での対応。
    for (final m in engine.currentMoves(player)) {
      if (!engine.responseAvailability(player, m, isBasic: false).usable) {
        continue;
      }
      final o = engine.clashBetween(attackMove, m);
      options.add(_RespOption(
        kind: _RespKind.signature,
        label: m.name,
        speed: m.speed,
        outcome: o,
        score: scoreOf(o, m.power),
        move: m,
        attribute: m.attribute,
      ));
    }
    if (_isEnergyMode) {
      // Ver.0.8.0：技カード（手札）での迎撃。フィニッシャーには不可。
      if (!attackMove.ignoreNormalSpeed) {
        for (final card in player.hand) {
          if (card.isEnergyOnly) continue;
          final move = engine.moves[card.techniqueMoveId];
          if (move == null) continue;
          if (!_energyAffordable(player, move)) continue;
          final o = engine.clashBetween(attackMove, move);
          options.add(_RespOption(
            kind: _RespKind.techniqueCard,
            label: move.name,
            speed: move.speed,
            outcome: o,
            score: scoreOf(o, move.power) - 5, // 固有技をわずかに優先
            move: move,
            cardId: card.instanceId,
            attribute: card.attribute,
          ));
        }
      }
    } else {
      // 単体技（手札）での対応。属性ごとに1枚へ集約。
      final seen = <MoveAttribute>{};
      for (final card in player.hand) {
        if (!seen.add(card.attribute)) continue;
        final basic = engine.basicMoveFor(card.attribute, player);
        if (basic == null) continue;
        final o = engine.clashBetween(attackMove, basic);
        options.add(_RespOption(
          kind: _RespKind.basic,
          label: basic.name,
          speed: basic.speed,
          outcome: o,
          score: scoreOf(o, basic.power) - 5, // 固有技をわずかに優先
          move: basic,
          cardId: card.instanceId,
          attribute: card.attribute,
        ));
      }
    }
    // 勝てる手（返し・速度勝ち）を先頭に。
    options.sort((a, b) => b.score.compareTo(a.score));
    // 受けるは常に最後（⑪）。
    options.add(_RespOption(
      kind: _RespKind.take,
      label: '受ける',
      speed: 0,
      outcome: null,
      score: -1,
      attribute: null,
    ));
    return options;
  }

  Future<void> _toggleRecommend() async {
    setState(() => _showRecommend = !_showRecommend);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_recommendPrefKey, _showRecommend);
  }

  void _commitResponse(_RespOption opt) {
    _selResponseKey = null;
    switch (opt.kind) {
      case _RespKind.signature:
        _act(() => engine.respondWithMove('player', opt.move!.id));
      case _RespKind.basic:
        _act(() => engine.respondWithBasic('player', opt.cardId!));
      case _RespKind.techniqueCard:
        _act(() => engine.respondWithTechniqueCard('player', opt.cardId!));
      case _RespKind.take:
        _act(() => engine.respondTake('player'));
    }
  }

  Widget _statChip(String label, String value, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      const SizedBox(width: 3),
      Text(
        value,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    ],
  );

  Widget _speedPredictBar(_RespOption sel, MoveDefinition attackMove) {
    // 速度比較の色（勝ち=緑 / 分け=黄 / 負け=赤）。
    Color cmpColor;
    String yourSpeed;
    if (sel.isTake) {
      cmpColor = Colors.redAccent;
      yourSpeed = '-';
    } else {
      yourSpeed = '${sel.speed}';
      if (sel.outcome == ClashOutcome.counter ||
          sel.outcome == ClashOutcome.speedWin) {
        cmpColor = Colors.greenAccent;
      } else if (sel.speed == attackMove.speed) {
        cmpColor = _gold;
      } else {
        cmpColor = Colors.redAccent;
      }
    }
    // 結果予測（⑥）。
    final List<String> predict;
    if (sel.isTake) {
      predict = ['攻撃が通ります', 'ダメージ ${attackMove.power}', 'フォール阻止なし'];
    } else {
      switch (sel.outcome!) {
        case ClashOutcome.counter:
          predict = ['返し成立', 'ダメージ ${sel.move!.power}', '攻撃無効', 'フォール阻止'];
        case ClashOutcome.speedWin:
          predict = ['速度勝ち', 'ダメージ ${sel.move!.power}', '攻撃無効'];
        case ClashOutcome.neutral:
          predict = ['互角（攻撃側優先）', '攻撃が通ります'];
        case ClashOutcome.speedLoss:
          predict = ['速度負け', '攻撃が通ります'];
      }
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: _panelBox(
              title: '速度比較',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _speedSide('あなた', yourSpeed, cmpColor),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('VS', style: TextStyle(color: Colors.white54)),
                  ),
                  _speedSide('相手', '${attackMove.speed}',
                      Colors.lightBlueAccent),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: _panelBox(
              title: '結果予測',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    predict.first,
                    style: TextStyle(
                      color: cmpColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    predict.skip(1).join(' / '),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10.5, color: Colors.white70),
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

  Widget _speedSide(String label, String value, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      Text(
        value,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    ],
  );

  Widget _panelBox({required String title, required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: _gold)),
        const SizedBox(height: 2),
        child,
      ],
    ),
  );

  // ===== 上部バー：TURN + HEATゲージ + 詳細情報（①⑧⑨） =====
  ({bool unlocked, int remaining, int threshold, bool has}) _finisherHeatInfo(
    PlayerLevelMatchState p,
  ) {
    WrestlerLevelDefinition? finLevel;
    for (final l in p.wrestler.levels) {
      final id = l.finisherId;
      if (id != null && engine.moves[id]?.category == MoveCategory.finisher) {
        finLevel = l;
        break;
      }
    }
    if (finLevel == null) {
      return (unlocked: false, remaining: 0, threshold: 0, has: false);
    }
    var threshold = 20;
    for (final c in finLevel.unlockCondition?.conditions ?? const []) {
      if (c.type == UnlockConditionType.heatAtLeast) {
        threshold = c.value ?? threshold;
      }
    }
    final unlocked = p.unlockedLevels.contains(finLevel.level);
    final remaining = (threshold - state.sharedHeat).clamp(0, threshold);
    return (unlocked: unlocked, remaining: remaining, threshold: threshold, has: true);
  }

  Widget _heatGauge() {
    final info = _finisherHeatInfo(state.player);
    final max = info.has && info.threshold > 0 ? info.threshold : 20;
    final heat = state.sharedHeat;
    const segments = 10;
    final filled = ((heat / max) * segments).clamp(0, segments).round();
    final ready = info.has && (info.unlocked || info.remaining == 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('HEAT',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: _gold)),
            const SizedBox(width: 4),
            const Text('(共有)',
                style: TextStyle(fontSize: 8.5, color: Colors.white38)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('$heat / $max',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (var i = 0; i < segments; i++)
              Expanded(
                child: Container(
                  height: 9,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: i < filled
                        ? Color.lerp(_gold, _pink, i / segments)!
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
        if (info.has)
          Text(
            ready ? 'フィニッシャー解放！' : 'あと${info.remaining}でフィニッシャー解放',
            style: TextStyle(
              fontSize: 9.5,
              color: ready ? Colors.greenAccent : _gold,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  // ===== 自分レスラーの簡易パネル（⑨） =====
  // ===== 詳細情報シート（KO/RB/FIN/山札 等を集約） =====
  // ===== Ver.0.9 UX改善②：手札はいつでもタップして中身を確認できる =====
  void _showHandSheet(PlayerLevelMatchState f) {
    final energyCards = f.hand.where((c) => c.isEnergyOnly).toList();
    final techCards = f.hand.where((c) => !c.isEnergyOnly).toList();
    Widget cardRow(TechniqueResourceCard card) {
      final move = card.isEnergyOnly ? null : engine.moves[card.techniqueMoveId];
      return ListTile(
        dense: true,
        leading: attributeBadge(card.attribute, size: 26),
        title: Text(card.isEnergyOnly ? card.name : (move?.name ?? card.name)),
        subtitle: Text(
          card.isEnergyOnly
              ? '⚡ 場にセットする燃料になる（このカード自体は攻撃しない）'
              : '🥊 このまま攻撃に使える（使うと捨て札）'
                  '${move != null ? '　威力${move.power}/速度${move.speed}' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(14),
            children: [
              Text('あなたの手札（${f.hand.length}枚）',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('⚡ 技エネルギーカード（${energyCards.length}枚）',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
              if (energyCards.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('なし', style: TextStyle(color: Colors.white38)),
                )
              else
                for (final c in energyCards) cardRow(c),
              const Divider(),
              Text('🥊 技カード（手札から使う・使うと捨て札）（${techCards.length}枚）',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _pink)),
              if (techCards.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('なし', style: TextStyle(color: Colors.white38)),
                )
              else
                for (final c in techCards) cardRow(c),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetailSheet() {
    Widget stat(PlayerLevelMatchState f, bool isCpu) => Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${isCpu ? "CPU  " : ""}${f.wrestler.name}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Lv.${f.currentLevel}'),
                Text('HP ${f.currentHp}/${f.wrestler.maxHp}'),
                Text('解放 ${(f.unlockedLevels.toList()..sort()).join(",")}'),
                Text('山札 ${f.deck.length}'),
                Text('手札 ${f.hand.length}'),
                Text('KO ${f.kickOutCards}',
                    style: const TextStyle(color: _gold)),
                Text('RB ${f.ropeBreakCards}',
                    style: const TextStyle(color: _gold)),
                Text('FIN ${f.finisherUsed ? "USED" : "READY"}',
                    style: TextStyle(
                        color: f.finisherUsed
                            ? Colors.white38
                            : Colors.greenAccent)),
              ],
            ),
            const SizedBox(height: 4),
            Text('SET ${_attributeCounts(f.setAttributeCounts)}',
                style: const TextStyle(color: _gold, fontSize: 12)),
          ],
        ),
      ),
    );
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('詳細ステータス',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              stat(state.cpu, true),
              stat(state.player, false),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('設定',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              SwitchListTile(
                value: _showRecommend,
                title: const Text('おすすめ表示'),
                subtitle: const Text('最も有利な対応に「おすすめ！」を出す（初心者向け）'),
                onChanged: (_) {
                  _toggleRecommend();
                  setSheet(() {});
                },
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('演出速度',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              for (final s in MatchSpeed.values)
                ListTile(
                  dense: true,
                  leading: Icon(
                    s == _speed
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: s == _speed ? _pink : null,
                  ),
                  title: Text(matchSpeedLabel(s)),
                  onTap: () async {
                    setState(() => _speed = s);
                    setSheet(() {});
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(_speedPrefKey, s.name);
                    if (s != MatchSpeed.manual) _manualGate?.complete();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showResponseHelp() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('対応のしかた',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text('① 返し技：相手の技を切り返す。成功すれば攻撃無効＋反撃。'),
              SizedBox(height: 6),
              Text('② 対応技：速度が相手より速ければ攻撃をつぶせる（速度勝ち）。'),
              SizedBox(height: 6),
              Text('③ 受ける：何もせず攻撃を通す。最後の選択肢。'),
              SizedBox(height: 10),
              Text('カードをタップすると「速度比較」と「結果予測」が下に出ます。',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waiting() => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Center(child: Text('CPU思考中…')),
    ),
  );

  // ===== セットフェイズ（技コスト表示・セット後予測） =====

  Widget _setCardPhase(PlayerLevelMatchState player) {
    // Ver.0.8.0 energyモード：技カード（isEnergyOnly=false）はセット不可
    // （使用専用）。セット候補はエネルギーカードのみ。
    final setable = _isEnergyMode
        ? player.hand.where((c) => c.isEnergyOnly)
        : player.hand;
    final heldTechniqueCards =
        _isEnergyMode ? player.hand.where((c) => !c.isEnergyOnly).toList() : const [];
    // 同属性カードは ×N に集約（⑤）。
    final groups = <MoveAttribute, List<TechniqueResourceCard>>{};
    for (final c in setable) {
      groups.putIfAbsent(c.attribute, () => []).add(c);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                    _isEnergyMode
                        ? '⚡ エネルギーカードをセット（技を出す“燃料”・場に残り続ける）'
                        : 'カードをセット（固有技を組み立てる）',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              if (!_isEnergyMode)
                TextButton.icon(
                  onPressed: () => _showCostSheet(player),
                  icon: const Icon(Icons.list_alt, size: 16),
                  label: const Text('全コスト', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                _isEnergyMode
                    ? '現在のエネルギーゾーン ${_attributeCounts(player.readyEnergyCounts)}'
                    : '現在 SET ${_attributeCounts(player.setAttributeCounts)}',
                style: const TextStyle(fontSize: 11, color: _gold)),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in groups.entries)
              _handCardTile(
                entry.value.first,
                count: entry.value.length,
                onTap: () => _previewThenSet(entry.value.first),
              ),
          ],
        ),
        if (_isEnergyMode && heldTechniqueCards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
                '🥊 技カード${heldTechniqueCards.length}枚はここではセットできません。'
                '「技を選ぶ」フェイズでそのまま繰り出します（使うと捨て札）。',
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _act(() => engine.skipSetCard('player')),
          child: const Text('セットしない'),
        ),
      ],
    );
  }

  Widget _handCardTile(
    TechniqueResourceCard card, {
    required int count,
    required VoidCallback onTap,
  }) {
    final color = attributeColor(card.attribute);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.25), Colors.black26]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                attributeBadge(card.attribute, size: 26),
                if (count > 1)
                  Text('×$count',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 4),
            Text(card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                  color: _pink, borderRadius: BorderRadius.circular(6)),
              child: const Text('セット',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewThenSet(TechniqueResourceCard card) async {
    // Ver.0.8.0 energyモード：セットカードの「解放プレビュー」はclassic専用の
    // 計算（setAttributeCounts前提）のため、energyモードでは素通しでセットする。
    if (_isEnergyMode) {
      await _setCard(card);
      return;
    }
    final player = state.player;
    final prediction = _preview.predictSet(
      attribute: card.attribute,
      counts: player.setAttributeCounts,
      unlockedLevels: player.unlockedLevels,
      finisherUsed: player.finisherUsed,
    );
    final changes = prediction.changes.take(6).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「${moveAttributeLabel(card.attribute)}」をセットすると'),
        content: SizedBox(
          width: 320,
          child: changes.isEmpty
              ? const Text('この属性を必要とする技はありません。')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final change in changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${change.moveName}\n'
                          '${moveAttributeLabel(change.attribute)}'
                          '${change.beforeCount}/${change.requiredForAttribute}'
                          ' → '
                          '${moveAttributeLabel(change.attribute)}'
                          '${change.afterCount}/${change.requiredForAttribute}'
                          '${change.becameUsable ? "  使用可能に！" : change.remainingAfter > 0 ? "  あと${moveAttributeLabel(change.attribute)}${change.remainingAfter}" : ""}',
                          style: TextStyle(
                            fontSize: 12,
                            color: change.becameUsable ? _gold : null,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('セットする'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _setCard(card);
  }

  void _showCostSheet(PlayerLevelMatchState player) {
    final views = _preview.allLevelViews(
      counts: player.setAttributeCounts,
      unlockedLevels: player.unlockedLevels,
      currentLevel: player.currentLevel,
      finisherUsed: player.finisherUsed,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                '${player.wrestler.name} 全Level技コスト',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '現在 SET ${_attributeCounts(player.setAttributeCounts)}',
                style: const TextStyle(fontSize: 12, color: _gold),
              ),
              const Divider(),
              for (final level in views)
                _LevelCostTile(level: level, key: ValueKey(level.level)),
            ],
          ),
        ),
      ),
    );
  }

  // Ver.0.9 UX改善⑤：レベル選択はその場でタップして変更できるようにする
  // （旧: タイルをタップ→ボトムシートを開く→行を選ぶ、の2段階だった）。
  // Ver.0.9 UX改善：「維持」ボタンは末尾ではなくヘッダー直下に固定表示し、
  // タイル数が多くスクロールが必要な端末でも決定操作が隠れないようにする。
  Widget _levelPhase(PlayerLevelMatchState player) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
        child: Row(
          children: [
            const Expanded(
              child: Text('レベルを選ぶ（解放済みなら上下どちらへも変更可）',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: _gold, fontSize: 13)),
            ),
            OutlinedButton.icon(
              onPressed: () => _act(() => engine.skipLevelChange('player')),
              icon: const Icon(Icons.check, size: 16),
              label: Text('Level ${player.currentLevel}を維持'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final level in player.wrestler.levels) _levelTile(player, level),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget _levelTile(
    PlayerLevelMatchState player,
    WrestlerLevelDefinition level,
  ) {
    final unlocked = player.unlockedLevels.contains(level.level);
    final isCurrent = level.level == player.currentLevel;
    final evaluation = engine.evaluateUnlockCondition(player, level);
    final moveNames =
        level.moveIds.map((id) => engine.moves[id]?.name ?? id).join(' / ');
    final selectable = unlocked && !isCurrent;
    final accent = isCurrent ? _gold : Colors.white24;
    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: GestureDetector(
        onTap: selectable
            ? () => _act(() => engine.changeLevel('player', level.level))
            : null,
        child: Container(
          width: 172,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [accent.withValues(alpha: 0.22), Colors.black26]),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: accent, width: isCurrent ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Level ${level.level}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13)),
                  const Spacer(),
                  if (isCurrent)
                    const Text('現在',
                        style: TextStyle(
                            fontSize: 10,
                            color: _gold,
                            fontWeight: FontWeight.bold))
                  else
                    Icon(
                      unlocked ? Icons.lock_open : Icons.lock,
                      size: 14,
                      color: unlocked ? Colors.greenAccent : Colors.white38,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(moveNames,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
              const SizedBox(height: 4),
              Text(
                unlocked ? '解放済み' : evaluation.details.join(' / '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5,
                    color: unlocked ? Colors.greenAccent : Colors.white38),
              ),
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: selectable ? _pink : Colors.white12,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCurrent
                      ? '選択中'
                      : (unlocked ? 'このLevelにする' : 'ロック中'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: selectable ? Colors.white : Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⑪/#3：固有技（セット消費）と単体技（1枚使用）をカードで並べ、
  // どちらで攻めるかをその場で選べるようにする。スクロールなし（Wrapで収める）。
  Widget _movePhase(PlayerLevelMatchState player) {
    final signatures = engine
        .currentMoves(player)
        .where((m) => !(m.isCounterMove && !m.canUseAsNormalMove))
        .toList();
    // Ver.0.8.0 energyモード：無料の単体技(basic_*)は廃止。手札カードは
    // ①技エネルギーカード（場にセット専用）と②技カード（使用・使用後は捨て札）
    // の2種類に分かれる。攻撃は「固有技」または「技カード」のいずれか。
    final seen = <MoveAttribute>{};
    final basics = <TechniqueResourceCard>[];
    final techniqueCards = <TechniqueResourceCard>[];
    if (!_isEnergyMode) {
      for (final c in player.hand) {
        if (engine.basicMoveFor(c.attribute, player) != null &&
            seen.add(c.attribute)) {
          basics.add(c);
        }
      }
    } else {
      for (final c in player.hand) {
        if (!c.isEnergyOnly && engine.moves[c.techniqueMoveId] != null) {
          techniqueCards.add(c);
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          child: Text(
              _isEnergyMode
                  ? '🌟 固有技｜手札不要・エネルギーを消費して繰り出す（決着可）'
                  : '🌟 固有技｜セットしたカードを消費して繰り出す（決着可）',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: _gold, fontSize: 13)),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [for (final m in signatures) _signatureCard(player, m)],
        ),
        if (!_isEnergyMode) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Text('🥊 単体技｜カード1枚で使用（コスト不要・決着不可）',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    fontSize: 13)),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (final c in basics) _basicMoveCard(c)],
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Text('🥊 技カード｜手札のカードをそのまま繰り出す（使うと捨て札）',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    fontSize: 13)),
          ),
          if (techniqueCards.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('手札に技カードがありません',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in techniqueCards) _techniqueHandCard(c),
              ],
            ),
          if (signatures.every((m) => !engine.evaluateMove(player, m).usable) &&
              techniqueCards.every((c) =>
                  !_energyAffordable(player, engine.moves[c.techniqueMoveId]!)))
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('使用できる技がありません。エネルギーが貯まるまで待ちましょう。',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            ),
        ],
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton(
            onPressed: () => _act(() => engine.skipMove('player')),
            child: const Text('技を使わず終了'),
          ),
        ),
      ],
    );
  }

  // ===== Ver.0.9 UX改善⑦：技の説明は長押しで表示（一覧は情報を絞る） =====
  void _showMoveDescription(MoveDefinition move) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            attributeBadge(move.attribute, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(move.name,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _statChip('ダメージ', '${move.power}', Colors.redAccent),
                _statChip('速度', '${move.speed}', Colors.lightBlueAccent),
                _statChip('HEAT', '+${move.heat}', _gold),
                if (move.offersPin)
                  _statChip('フォール強度', '${move.pinPower}', Colors.greenAccent),
                if (move.offersSubmission)
                  _statChip(
                      'ギブアップ強度', '${move.submissionPower}', Colors.greenAccent),
              ],
            ),
            const SizedBox(height: 10),
            Text(move.description, style: const TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Widget _moveTile({
    required MoveAttribute attribute,
    required String name,
    required int damage,
    required int speed,
    required List<String> tags,
    required bool usable,
    String? lockedText,
    required Color ctaColor,
    required String ctaLabel,
    required VoidCallback? onTap,
    Map<MoveAttribute, int>? energyCost,
    VoidCallback? onLongPress,
  }) {
    final color = attributeColor(attribute);
    return Opacity(
      opacity: usable ? 1 : 0.55,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 158,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.22), Colors.black26]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  attributeBadge(attribute, size: 26),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                  if (onLongPress != null)
                    const Icon(Icons.info_outline,
                        size: 13, color: Colors.white38),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    _statChip('ダメージ', '$damage', Colors.redAccent),
                    const SizedBox(width: 10),
                    _statChip('速度', '$speed', Colors.lightBlueAccent),
                  ],
                ),
              ),
              if (energyCost != null && energyCost.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (final e in energyCost.entries)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: attributeColor(e.key)
                                .withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${moveAttributeLabel(e.key)}×${e.value}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: attributeColor(e.key)),
                          ),
                        ),
                    ],
                  ),
                ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(tags.join(' / '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9.5,
                          color: _gold,
                          fontWeight: FontWeight.bold)),
                ),
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: usable ? ctaColor : Colors.white12,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(usable ? ctaLabel : (lockedText ?? '使用不可'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: usable ? Colors.white : Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isEnergyMode => state.resourceMode == MatchResourceMode.energy;

  Widget _signatureCard(PlayerLevelMatchState player, MoveDefinition m) {
    final availability = engine.evaluateMove(player, m);
    final usable = availability.usable;
    final tags = <String>[
      if (m.offersPin) 'フォール',
      if (m.offersSubmission) 'ギブアップ',
      if (m.category == MoveCategory.finisher) 'FINISHER',
    ];
    String? locked;
    if (!usable) {
      if (_isEnergyMode) {
        final ready = player.readyEnergyCounts;
        final lacks = <String>[];
        for (final e in m.energyModeRequiredCards.entries) {
          final short = e.value - (ready[e.key] ?? 0);
          if (short > 0) lacks.add('${moveAttributeLabel(e.key)}あと$short');
        }
        locked = lacks.isEmpty ? 'エネルギー不足' : lacks.join(' ');
      } else {
        final counts = player.setAttributeCounts;
        final lacks = <String>[];
        for (final e in m.requiredCards.entries) {
          final short = e.value - (counts[e.key] ?? 0);
          if (short > 0) lacks.add('${moveAttributeLabel(e.key)}あと$short');
        }
        locked = lacks.isEmpty ? 'セットが必要' : lacks.join(' ');
      }
    }
    return _moveTile(
      attribute: m.attribute,
      name: m.name,
      damage: m.power,
      speed: m.speed,
      tags: tags,
      usable: usable,
      lockedText: locked,
      ctaColor: _gold,
      ctaLabel: 'この固有技を使う',
      onTap: usable ? () => _useMove(m) : null,
      energyCost: _isEnergyMode ? m.energyModeRequiredCards : null,
      onLongPress: () => _showMoveDescription(m),
    );
  }

  Widget _basicMoveCard(TechniqueResourceCard card) {
    final basic = engine.basicMoveFor(card.attribute, state.player)!;
    String? locked;
    if (_isEnergyMode && !_energyAffordable(state.player, basic)) {
      final ready = state.player.readyEnergyCounts;
      final lacks = <String>[];
      for (final e in basic.energyModeRequiredCards.entries) {
        final short = e.value - (ready[e.key] ?? 0);
        if (short > 0) lacks.add('${moveAttributeLabel(e.key)}あと$short');
      }
      locked = lacks.isEmpty ? 'エネルギー不足' : lacks.join(' ');
    }
    final affordable = !_isEnergyMode || _energyAffordable(state.player, basic);
    return _moveTile(
      attribute: card.attribute,
      name: basic.name,
      damage: basic.power,
      speed: basic.speed,
      tags: const [],
      usable: affordable,
      lockedText: locked,
      ctaColor: _pink,
      ctaLabel: 'この技で攻撃',
      onTap: affordable
          ? () => _act(() => engine.useBasicMove('player', card.instanceId))
          : null,
      energyCost: _isEnergyMode ? basic.energyModeRequiredCards : null,
      onLongPress: () => _showMoveDescription(basic),
    );
  }

  /// Ver.0.8.0 energyモード：技カード（手札から使用・使用後は捨て札）。
  Widget _techniqueHandCard(TechniqueResourceCard card) {
    final move = engine.moves[card.techniqueMoveId]!;
    final affordable = _energyAffordable(state.player, move);
    String? locked;
    if (!affordable) {
      final ready = state.player.readyEnergyCounts;
      final lacks = <String>[];
      for (final e in move.energyModeRequiredCards.entries) {
        final short = e.value - (ready[e.key] ?? 0);
        if (short > 0) lacks.add('${moveAttributeLabel(e.key)}あと$short');
      }
      locked = lacks.isEmpty ? 'エネルギー不足' : lacks.join(' ');
    }
    return _moveTile(
      attribute: move.attribute,
      name: move.name,
      damage: move.power,
      speed: move.speed,
      tags: const [],
      usable: affordable,
      lockedText: locked,
      ctaColor: _pink,
      ctaLabel: 'この技カードで攻撃',
      onTap: affordable
          ? () => _act(() => engine.useTechniqueCard('player', card.instanceId))
          : null,
      energyCost: move.energyModeRequiredCards,
      onLongPress: () => _showMoveDescription(move),
    );
  }

  bool _energyAffordable(PlayerLevelMatchState p, MoveDefinition m) {
    final ready = p.readyEnergyCounts;
    for (final e in m.energyModeRequiredCards.entries) {
      if ((ready[e.key] ?? 0) < e.value) return false;
    }
    return true;
  }

  // ===== フォール／ギブアップ 対応UI =====

  Widget _pinDeclareCard(PendingPin pin) => Card(
    color: const Color(0xff3a1030),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'フォールしますか？',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text('技: ${pin.moveName}'),
          Text('フォール強度 ${pin.strength.total}'
              '（技${pin.strength.base}+ダメージ${pin.strength.damage}'
              '${pin.strength.finisherBonus > 0 ? "+FIN${pin.strength.finisherBonus}" : ""}'
              '${pin.strength.fatigueBonus > 0 ? "+消耗${pin.strength.fatigueBonus}" : ""}'
              '${pin.strength.downBonus > 0 ? "+ダウン${pin.strength.downBonus}" : ""}）'),
          Text('相手HP ${state.byId(pin.defenderId).currentHp} / '
              '想定キックアウトHP ${pin.hpKickOutCost}'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _act(() => engine.declarePin('player')),
                  child: const Text('フォールする'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _act(() => engine.declinePin('player')),
                  child: const Text('試合を続ける'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _kickOutCard(PendingPin pin) {
    final me = state.player;
    final canHp = me.currentHp > 0 && me.currentHp >= pin.hpKickOutCost;
    return Card(
      color: const Color(0xff3a1030),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'フォールされています！',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text('${pin.moveName}  フォール強度 ${pin.strength.total}'),
            Text('現在HP ${me.currentHp}  →  HP消費後 '
                '${(me.currentHp - pin.hpKickOutCost).clamp(0, me.currentHp)}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: me.kickOutCards > 0
                      ? () => _act(
                          () => engine.kickOut('player', DefenseMethod.card),
                        )
                      : null,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text('キックアウトカード(${me.kickOutCards}) HEAT+5'),
                ),
                FilledButton.icon(
                  onPressed: canHp
                      ? () => _act(
                          () => engine.kickOut('player', DefenseMethod.hp),
                        )
                      : null,
                  icon: const Icon(Icons.favorite, size: 18),
                  label: Text('HPを${pin.hpKickOutCost}消費'),
                ),
                OutlinedButton(
                  onPressed: () => _act(
                    () => engine.kickOut('player', DefenseMethod.accept),
                  ),
                  child: const Text('敗北を受け入れる'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _submissionCard(PendingSubmission sub) {
    final me = state.player;
    final canHp = me.currentHp > 0 && me.currentHp >= sub.hpEscapeCost;
    return Card(
      color: const Color(0xff30203a),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '関節技が極まっています！',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text('${sub.moveName}  ギブアップ強度 ${sub.strength.total}'),
            Text('関節耐性による軽減 -${sub.strength.resistanceReduction}'),
            Text('現在HP ${me.currentHp}  →  HP消費後 '
                '${(me.currentHp - sub.hpEscapeCost).clamp(0, me.currentHp)}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: me.ropeBreakCards > 0
                      ? () => _act(
                          () => engine.escapeSubmission(
                            'player',
                            DefenseMethod.card,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.horizontal_rule, size: 18),
                  label: Text('ロープブレイク(${me.ropeBreakCards}) HEAT+3'),
                ),
                FilledButton.icon(
                  onPressed: canHp
                      ? () => _act(
                          () => engine.escapeSubmission(
                            'player',
                            DefenseMethod.hp,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.favorite, size: 18),
                  label: Text('HPを${sub.hpEscapeCost}消費して耐える'),
                ),
                OutlinedButton(
                  onPressed: () => _act(
                    () => engine.escapeSubmission(
                      'player',
                      DefenseMethod.accept,
                    ),
                  ),
                  child: const Text('ギブアップ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setCard(TechniqueResourceCard card) async {
    String? replacement;
    if (state.player.setCards.length >= 6) {
      replacement = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('セットカードを交換'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('捨てるカードを選択してください'),
              for (final old in state.player.setCards)
                ListTile(
                  title: Text(old.name),
                  onTap: () => Navigator.pop(context, old.instanceId),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      );
      if (replacement == null) return;
    }
    _act(
      () => engine.setTechniqueCard(
        'player',
        card.instanceId,
        replaceInstanceId: replacement,
      ),
    );
  }

  Future<void> _useMove(MoveDefinition move) async {
    // Ver.0.7.1: 技は「宣言」。相手（CPU）が自動でレスポンスして解決する。
    _act(() => engine.useMove('player', move.id));
  }

  void _act(VoidCallback action, {bool continueCpu = true}) {
    _audio.play(SeKind.button);
    final before = state.logs.length;
    try {
      setState(action);
    } on Object catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
      return;
    }
    _afterAct(before, continueCpu);
  }

  Future<void> _afterAct(int before, bool continueCpu) async {
    await _presentNewLogs(before);
    if (!mounted) return;
    if (state.isGameOver) {
      await _finish();
    } else if (continueCpu) {
      await _drive();
    }
  }

  /// CPUの判断を1ステップずつ、速度設定に応じて演出しながら進める。
  Future<void> _drive() async {
    if (_driving || !mounted || state.isGameOver) return;
    _driving = true;
    while (mounted && engine.cpuActionPending && !state.isGameOver) {
      await _pace();
      if (!mounted) break;
      final before = state.logs.length;
      setState(engine.autoAdvance);
      await _presentNewLogs(before);
    }
    _driving = false;
    if (mounted) setState(() {});
    if (state.isGameOver && mounted) await _finish();
  }

  Future<void> _pace() async {
    if (_speed == MatchSpeed.manual) {
      final gate = Completer<void>();
      setState(() => _manualGate = gate);
      await gate.future;
      if (mounted) setState(() => _manualGate = null);
    } else {
      await Future<void>.delayed(matchStepDelay(_speed));
    }
  }

  void _updateCommentary(int fromIndex) {
    if (fromIndex >= state.logs.length) return;
    final fresh = state.logs.sublist(fromIndex);
    // 実況として最も意味のある行を選ぶ（cpuDecisionは思考欄へ）。
    final headline = fresh.lastWhere(
      (l) => l.action != 'cpuDecision',
      orElse: () => fresh.last,
    );
    setState(() => _commentary = headline.message);
  }

  /// Ver.0.9 演出システム：新しく積まれたログをBattleEventQueueで
  /// イベント列に変換し、1つずつ段階的に見せる（技名→対応→速度判定→
  /// ヒット→ダメージ→HEAT→フォール→カウント）。
  /// エンジンの状態遷移そのものには一切関与しない（表示専用）。
  Future<void> _presentNewLogs(int fromIndex) async {
    if (fromIndex >= state.logs.length) return;
    final fresh = state.logs.sublist(fromIndex);
    _updateCommentary(fromIndex);
    if (_speed == MatchSpeed.manual && fresh.length < 2) {
      // 手動送りで進行ログが1件だけ（＝地味な進行）のときは、演出無しで
      // 即座に反映する（ステップ実行のテンポを優先）。
      return;
    }
    final events = _eventQueue.build(fresh, state, engine.moves);
    for (final event in events) {
      if (!mounted) return;
      if (event.se != null) _audio.play(event.se!);
      final hitStop = _scaled(event.hitStop, event.kind);
      if (hitStop > Duration.zero) {
        await Future<void>.delayed(hitStop);
        if (!mounted) return;
      }
      setState(() {
        if (event.kind == BattleBeatKind.finisherCutin) {
          _finisherEvent = event;
        } else {
          _currentEvent = event;
        }
      });
      if (event.shakeIntensity > 0) {
        _triggerShake(event.shakeIntensity, event.shakeDuration);
      }
      final hold = _scaled(event.hold, event.kind);
      if (hold > Duration.zero) {
        await Future<void>.delayed(hold);
        if (!mounted) return;
      }
      if (event.kind == BattleBeatKind.finisherCutin) {
        setState(() => _finisherEvent = null);
      }
    }
    if (mounted) setState(() => _currentEvent = null);
  }

  /// 山場（フォール／キックアウト／必殺技等）は速度設定によらず極端に
  /// 削らない。通常の技演出はテンポ優先で大きく短縮する。
  static const _importantBeatKinds = {
    BattleBeatKind.pinDeclare,
    BattleBeatKind.pinCount,
    BattleBeatKind.pinResult,
    BattleBeatKind.kickOutResult,
    BattleBeatKind.submissionDeclare,
    BattleBeatKind.submissionResult,
    BattleBeatKind.finisherCutin,
  };

  // Ver.0.9: 「オート」＝normal速度がメッセージを読み切る前に流れてしまう
  // との指摘を受け、通常/ゆっくりの基準倍率を底上げ（fast/manualは意図的に
  // 素早いままにする）。
  Duration _scaled(Duration base, BattleBeatKind kind) {
    if (base <= Duration.zero) return Duration.zero;
    final important = _importantBeatKinds.contains(kind);
    final factor = switch (_speed) {
      MatchSpeed.fast => important ? 0.6 : 0.18,
      MatchSpeed.normal => 1.4,
      MatchSpeed.slow => 2.0,
      MatchSpeed.manual => important ? 0.7 : 0.3,
    };
    return Duration(milliseconds: (base.inMilliseconds * factor).round());
  }

  Future<void> _finish() async {
    await LevelMatchHistoryStore().save(state);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LevelMatchResultScreen(state: state, moves: engine.moves),
      ),
    );
  }

  void _showLogs() {
    // ターンごとにグルーピングした試合ログ。
    final byTurn = <int, List<LevelMatchLogEntry>>{};
    for (final log in state.logs) {
      byTurn.putIfAbsent(log.turn, () => []).add(log);
    }
    final turns = byTurn.keys.toList()..sort((a, b) => b.compareTo(a));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              '試合ログ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            for (final turn in turns)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TURN $turn',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _gold,
                        ),
                      ),
                      for (final log in byTurn[turn]!)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '・${log.message}',
                            style: const TextStyle(fontSize: 12),
                          ),
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
}

class _LevelCostTile extends StatelessWidget {
  const _LevelCostTile({required this.level, super.key});
  final LevelCostView level;

  @override
  Widget build(BuildContext context) => Card(
    color: level.isCurrentLevel ? const Color(0xff2a1c33) : null,
    child: ExpansionTile(
      initiallyExpanded: level.isCurrentLevel,
      title: Text(
        'Level ${level.level}'
        '${level.isCurrentLevel ? "  ◀ 現在" : ""}'
        '${level.unlocked ? "" : "  🔒未解放"}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: level.isCurrentLevel ? _gold : null,
        ),
      ),
      children: [
        for (final move in level.allMoves)
          ListTile(
            dense: true,
            leading: Text(
              move.symbol,
              style: TextStyle(
                fontSize: 20,
                color: move.symbol == '✓'
                    ? Colors.greenAccent
                    : move.symbol == '△'
                    ? _gold
                    : Colors.white38,
              ),
            ),
            title: Text(
              '${move.name}'
              '${move.isFinisher ? "  [FINISHER]" : ""}'
              '${move.offersPin ? "  ▶フォール" : ""}'
              '${move.offersSubmission ? "  ▶ギブアップ" : ""}',
            ),
            subtitle: Text(
              '必要 ${_attributeCounts(move.requiredCards)}\n'
              '現在 ${_attributeCounts(move.currentCounts)}'
              '${move.hasShortage ? "\n不足 ${_shortageText(move.shortages)}" : ""}',
              style: const TextStyle(fontSize: 11),
            ),
            isThreeLine: move.hasShortage,
          ),
      ],
    ),
  );
}

class LevelMatchResultScreen extends StatelessWidget {
  const LevelMatchResultScreen({
    super.key,
    required this.state,
    required this.moves,
  });
  final LevelMatchState state;
  final Map<String, MoveDefinition> moves;
  @override
  Widget build(BuildContext context) {
    final isDraw = state.winnerId == null;
    final winner = state.winnerId == 'player' ? state.player : state.cpu;
    final loser = state.winnerId == 'player' ? state.cpu : state.player;
    final json = const JsonEncoder.withIndent('  ').convert(state.toJson());
    return Scaffold(
      appBar: AppBar(title: const Text('LEVEL MATCH RESULT')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Icon(
            isDraw ? Icons.handshake : Icons.emoji_events,
            color: isDraw ? Colors.white70 : _gold,
            size: 72,
          ),
          Text(
            isDraw
                ? 'DRAW'
                : '${winner.wrestler.name} WIN',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          if (isDraw)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                '決着つかず引き分け（3カウント・ギブアップのみが決着です）',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            )
          else
            _result('敗者', loser.wrestler.name),
          _result('決着方法', finishReasonLabel(state.finishReason)),
          _result('決着技', state.finishingMove ?? state.lastMove ?? 'なし'),
          _result(
            '最終HP',
            '${state.player.wrestler.name} ${state.player.currentHp} / ${state.cpu.wrestler.name} ${state.cpu.currentHp}',
          ),
          _result('総ターン', '${state.turnNumber}'),
          _result('最終HEAT', '${state.sharedHeat}'),
          _result('フォール試行', '${state.pinAttemptCount}'),
          _result('キックアウト', '${state.kickOutTotalCount}'),
          _result('ギブアップ判定', '${state.submissionAttemptCount}'),
          _result('ギブアップ回避', '${state.submissionEscapeTotalCount}'),
          _result('ロープブレイク', '${state.ropeBreakTotalCount}'),
          _result('フィニッシャー返し', '${state.finisherKickOutTotalCount}'),
          _result(
            'HP0到達ターン',
            'あなた ${state.player.hpZeroReachedTurn ?? "-"} / '
                'CPU ${state.cpu.hpZeroReachedTurn ?? "-"}',
          ),
          _result(
            'フィニッシャー使用',
            'あなた ${state.player.finisherUsed ? "有" : "無"} / '
                'CPU ${state.cpu.finisherUsed ? "有" : "無"}',
          ),
          FilledButton.icon(
            onPressed: () => _downloadReport(context, json, state),
            icon: const Icon(Icons.download),
            label: const Text('試合ログをファイルで保存'),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: json)),
            icon: const Icon(Icons.copy),
            label: const Text('試合JSONをコピー'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => LevelMatchBattleScreen(
                  engine: LevelMatchEngine.create(
                    playerWrestler: state.player.wrestler,
                    cpuWrestler: state.cpu.wrestler,
                    moves: moves,
                    matchTimeSeconds: state.matchTimeSeconds,
                    resourceMode: state.resourceMode,
                  ),
                ),
              ),
            ),
            child: const Text('再戦'),
          ),
          TextButton(
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => TitleScreen(catalog: GameCatalog.standard()),
              ),
              (_) => false,
            ),
            child: const Text('タイトルへ'),
          ),
        ],
      ),
    );
  }
}

Widget _result(String label, String value) => Card(
  child: ListTile(title: Text(label), trailing: Text(value)),
);

/// Ver.0.9 UX改善⑬：試合結果ログをファイルとしてダウンロードする
/// （Web以外や失敗時はクリップボードへフォールバック）。
Future<void> _downloadReport(
  BuildContext context,
  String json,
  LevelMatchState state,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-');
  final name = 'onm_match_$stamp.json';
  final ok = await downloadTextFile(name, json);
  if (ok) {
    messenger.showSnackBar(SnackBar(content: Text('$name を保存しました')));
  } else {
    await Clipboard.setData(ClipboardData(text: json));
    messenger.showSnackBar(
      const SnackBar(content: Text('このプラットフォームではダウンロード非対応のためクリップボードにコピーしました')),
    );
  }
}

String _attributeCounts(Map<MoveAttribute, int> values) => MoveAttribute.values
    .where((attribute) => (values[attribute] ?? 0) != 0)
    .map(
      (attribute) =>
          '${moveAttributeLabel(attribute)}${values[attribute] ?? 0}',
    )
    .join(' ')
    .ifEmptyText();

String _shortageText(Map<MoveAttribute, int> values) => MoveAttribute.values
    .where((attribute) => (values[attribute] ?? 0) > 0)
    .map(
      (attribute) =>
          '${moveAttributeLabel(attribute)}${values[attribute] ?? 0}',
    )
    .join(' ');

extension _EmptyText on String {
  String ifEmptyText() => trim().isEmpty ? '—' : this;
}

