import '../wrestler_editor/models.dart';
import 'battle_audio.dart';
import 'level_match_engine.dart';

/// Ver.0.9 演出システム：1つの試合ログから導かれる「演出のひとコマ」。
///
/// エンジン（level_match_engine.dart）は完全に同期的な決定論ステートマシンの
/// ままとし、一切変更しない。演出はログストリーム（LevelMatchState.logs）を
/// 後から読み解いて生成する“表示専用”のレイヤーとして実装する。
enum BattleBeatKind {
  announce, // 技名宣言
  finisherCutin, // 必殺技カットイン
  response, // 相手の対応（受ける／迎撃）
  clash, // 速度判定・返し成立
  hit, // ヒット・ダメージ
  heat, // HEAT増加
  down, // ダウン
  pinDeclare, // フォール宣言
  pinCount, // ONE!/TWO!/THREE!!（演出側で合成）
  kickOutResult, // キックアウト成立
  pinResult, // 3カウント成立
  submissionDeclare, // ギブアップ判定開始
  submissionResult, // ギブアップ／耐えた
  unlock, // レベル解放
  info, // その他の軽い進行ログ
}

class BattleEvent {
  const BattleEvent({
    required this.kind,
    required this.text,
    this.subtitle,
    this.hold = const Duration(milliseconds: 260),
    this.hitStop = Duration.zero,
    this.shakeIntensity = 0,
    this.shakeDuration = Duration.zero,
    this.se,
  });

  final BattleBeatKind kind;
  final String text;
  final String? subtitle;
  final Duration hold;
  final Duration hitStop;
  final double shakeIntensity;
  final Duration shakeDuration;
  final SeKind? se;
}

/// ログエントリ列から演出イベント列を組み立てる。
///
/// 攻防1回分の解決（宣言→対応→速度判定→ヒット→ダメージ→HEAT→フォール→
/// カウント）は、エンジン内では同期的に一括処理されログが一気に積まれる。
/// このクラスはそのログ列を読み、段階的に見せるためのイベント列へ変換する。
class BattleEventQueue {
  const BattleEventQueue();

  List<BattleEvent> build(
    List<LevelMatchLogEntry> logs,
    LevelMatchState state,
    Map<String, MoveDefinition> moves,
  ) {
    final events = <BattleEvent>[];
    for (var i = 0; i < logs.length; i++) {
      events.addAll(_eventsFor(logs[i], state, moves));
    }
    return events;
  }

  String _actorName(LevelMatchLogEntry log, LevelMatchState state) =>
      state.byId(log.playerId).wrestler.name;

  List<BattleEvent> _eventsFor(
    LevelMatchLogEntry log,
    LevelMatchState state,
    Map<String, MoveDefinition> moves,
  ) {
    switch (log.action) {
      case 'draw':
        return _draw(log, state, moves);
      case 'setEnergy':
        return [
          BattleEvent(
            kind: BattleBeatKind.info,
            text: '${_actorName(log, state)}がエネルギーをセット',
            subtitle: log.message,
            hold: const Duration(milliseconds: 220),
          ),
        ];
      case 'setCard':
        return [
          BattleEvent(
            kind: BattleBeatKind.info,
            text: '${_actorName(log, state)}がカードをセット',
            subtitle: log.message,
            hold: const Duration(milliseconds: 220),
          ),
        ];
      case 'skipSet':
        return [
          BattleEvent(
            kind: BattleBeatKind.info,
            text: '${_actorName(log, state)}はセットを見送った',
            hold: const Duration(milliseconds: 180),
          ),
        ];
      case 'changeLevel':
        return [
          BattleEvent(
            kind: BattleBeatKind.info,
            text: '${_actorName(log, state)}: ${log.message}',
            hold: const Duration(milliseconds: 260),
          ),
        ];
      case 'skipMove':
        return [
          BattleEvent(
            kind: BattleBeatKind.info,
            text: '${_actorName(log, state)}は技を使わず終了',
            hold: const Duration(milliseconds: 180),
          ),
        ];
      case 'attackDeclared':
        return _attackDeclared(log, state, moves);
      case 'responseTake':
        return [
          BattleEvent(
            kind: BattleBeatKind.response,
            text: '${_actorName(log, state)}は受ける',
            hold: const Duration(milliseconds: 220),
          ),
        ];
      case 'respondEnergyConsumed':
        return _respondEnergyConsumed(log, state, moves);
      case 'clashResolution':
        return _clashResolution(log, state);
      case 'moveResolved':
        return _moveResolved(log, state);
      case 'down':
        return [
          BattleEvent(
            kind: BattleBeatKind.down,
            text: log.message,
            hold: const Duration(milliseconds: 320),
            shakeIntensity: 3,
            shakeDuration: const Duration(milliseconds: 90),
          ),
        ];
      case 'pinAttempt':
        return [
          BattleEvent(
            kind: BattleBeatKind.pinDeclare,
            text: 'フォール！',
            hold: const Duration(milliseconds: 380),
            se: SeKind.pin,
          ),
          const BattleEvent(
            kind: BattleBeatKind.pinCount,
            text: 'ONE!',
            hold: Duration(milliseconds: 340),
          ),
          const BattleEvent(
            kind: BattleBeatKind.pinCount,
            text: 'TWO!!',
            hold: Duration(milliseconds: 340),
          ),
        ];
      case 'kickOut':
        return [
          const BattleEvent(
            kind: BattleBeatKind.pinCount,
            text: 'TH...!?',
            hold: Duration(milliseconds: 260),
          ),
          BattleEvent(
            kind: BattleBeatKind.kickOutResult,
            text: 'キックアウト！！',
            subtitle: '${_actorName(log, state)}が2.9で返した',
            hold: const Duration(milliseconds: 520),
            hitStop: const Duration(milliseconds: 70),
            shakeIntensity: 6,
            shakeDuration: const Duration(milliseconds: 110),
            se: SeKind.kickOut,
          ),
        ];
      case 'threeCount':
        return [
          const BattleEvent(
            kind: BattleBeatKind.pinCount,
            text: 'THREE!!',
            hold: Duration(milliseconds: 420),
          ),
          BattleEvent(
            kind: BattleBeatKind.pinResult,
            text: '3カウント！',
            subtitle: '決着！',
            hold: const Duration(milliseconds: 620),
            hitStop: const Duration(milliseconds: 90),
            shakeIntensity: 10,
            shakeDuration: const Duration(milliseconds: 150),
            se: SeKind.win,
          ),
        ];
      case 'submissionAttempt':
        return [
          BattleEvent(
            kind: BattleBeatKind.submissionDeclare,
            text: 'ギブアップ判定！',
            hold: const Duration(milliseconds: 380),
            se: SeKind.pin,
          ),
        ];
      case 'submissionEscape':
        return [
          BattleEvent(
            kind: BattleBeatKind.submissionResult,
            text: '${_actorName(log, state)}が耐えた！',
            hold: const Duration(milliseconds: 460),
            shakeIntensity: 5,
            shakeDuration: const Duration(milliseconds: 100),
            se: SeKind.kickOut,
          ),
        ];
      case 'submissionFinish':
        return [
          const BattleEvent(
            kind: BattleBeatKind.submissionResult,
            text: 'ギブアップ！！',
            subtitle: '決着！',
            hold: Duration(milliseconds: 620),
            hitStop: Duration(milliseconds: 90),
            shakeIntensity: 10,
            shakeDuration: Duration(milliseconds: 150),
            se: SeKind.win,
          ),
        ];
      case 'unlockLevel':
        return [
          BattleEvent(
            kind: BattleBeatKind.unlock,
            text: log.message,
            hold: const Duration(milliseconds: 300),
          ),
        ];
      default:
        return const [];
    }
  }

  List<BattleEvent> _attackDeclared(
    LevelMatchLogEntry log,
    LevelMatchState state,
    Map<String, MoveDefinition> moves,
  ) {
    final moveId = log.details['moveId'] as String?;
    final move = moveId == null ? null : moves[moveId];
    final name = move?.name ?? state.lastMove ?? '技';
    final actor = _actorName(log, state);
    final isFinisher = move?.category == MoveCategory.finisher;
    final events = <BattleEvent>[];
    if (isFinisher) {
      events.add(
        BattleEvent(
          kind: BattleBeatKind.finisherCutin,
          text: name,
          subtitle: actor,
          hold: const Duration(milliseconds: 1050),
          se: SeKind.pin,
        ),
      );
    }
    events.add(
      BattleEvent(
        kind: BattleBeatKind.announce,
        text: '$actorの$name！',
        subtitle: _energyCostSubtitle(log),
        hold: const Duration(milliseconds: 320),
      ),
    );
    return events;
  }

  /// Ver.0.9: どのエネルギーを何枚消費したかを分かりやすく1行にする。
  String? _energyCostSubtitle(LevelMatchLogEntry log) {
    final cost = log.details['energyCost'];
    if (cost is! Map) return null;
    final parts = <String>[];
    for (final entry in cost.entries) {
      final amount = (entry.value as num?)?.toInt() ?? 0;
      if (amount <= 0) continue;
      final attribute = MoveAttribute.values
          .cast<MoveAttribute?>()
          .firstWhere((a) => a?.name == entry.key, orElse: () => null);
      if (attribute == null) continue;
      parts.add('${moveAttributeLabel(attribute)}×$amount');
    }
    if (parts.isEmpty) return null;
    return 'エネルギー消費: ${parts.join(' ')}';
  }

  List<BattleEvent> _draw(
    LevelMatchLogEntry log,
    LevelMatchState state,
    Map<String, MoveDefinition> moves,
  ) {
    final drawn = log.details['drawnCard'];
    String? cardName;
    if (drawn is Map) {
      final techId = drawn['techniqueMoveId'] as String?;
      if (techId != null) {
        cardName = moves[techId]?.name;
      } else {
        final attribute = MoveAttribute.values
            .cast<MoveAttribute?>()
            .firstWhere(
                (a) => a?.name == drawn['attribute'], orElse: () => null);
        cardName =
            attribute != null ? '${moveAttributeLabel(attribute)}カード' : null;
      }
    }
    return [
      BattleEvent(
        kind: BattleBeatKind.info,
        text: '${_actorName(log, state)}がドロー',
        subtitle: cardName,
        hold: const Duration(milliseconds: 200),
      ),
    ];
  }

  List<BattleEvent> _respondEnergyConsumed(
    LevelMatchLogEntry log,
    LevelMatchState state,
    Map<String, MoveDefinition> moves,
  ) {
    final moveId = log.details['moveId'] as String?;
    final move = moveId == null ? null : moves[moveId];
    final isCounter = log.details['isCounterMove'] as bool? ?? false;
    final actor = _actorName(log, state);
    return [
      BattleEvent(
        kind: BattleBeatKind.response,
        text: '$actorが${move?.name ?? "技"}で${isCounter ? "返し技" : "迎撃"}！',
        subtitle: _energyCostSubtitle(log),
        hold: const Duration(milliseconds: 300),
      ),
    ];
  }

  List<BattleEvent> _clashResolution(
    LevelMatchLogEntry log,
    LevelMatchState state,
  ) {
    final outcome = log.details['outcome'] as String?;
    final actor = _actorName(log, state);
    final (text, se, shake) = switch (outcome) {
      'counter' => ('$actorが返し成立！！', SeKind.counter, 7.0),
      'speedWin' => ('$actorが速度勝ち！', SeKind.counter, 4.0),
      'speedLoss' => ('速度負け…', null, 0.0),
      _ => ('同速勝負…', null, 0.0),
    };
    return [
      BattleEvent(
        kind: BattleBeatKind.clash,
        text: text,
        hold: const Duration(milliseconds: 320),
        shakeIntensity: shake,
        shakeDuration: const Duration(milliseconds: 90),
        se: se,
      ),
    ];
  }

  List<BattleEvent> _moveResolved(
    LevelMatchLogEntry log,
    LevelMatchState state,
  ) {
    final damage = (log.details['finalDamage'] as num?)?.toInt() ?? 0;
    final heatDelta = (log.details['heatDelta'] as num?)?.toInt() ?? 0;
    final attribute = log.details['moveAttribute'] as String?;
    final isCounter = log.details['isCounter'] as bool? ?? false;
    final se = switch (attribute) {
      'strike' => SeKind.hitStrike,
      _ => SeKind.hitThrow,
    };
    final events = <BattleEvent>[
      BattleEvent(
        kind: BattleBeatKind.hit,
        text: damage > 0 ? '$damageダメージ！' : 'ヒット！',
        subtitle: isCounter ? 'カウンターヒット！' : null,
        hold: const Duration(milliseconds: 340),
        hitStop: Duration(milliseconds: damage >= 20 ? 90 : 55),
        shakeIntensity: (damage / 3).clamp(2, 12).toDouble(),
        shakeDuration: const Duration(milliseconds: 110),
        se: se,
      ),
    ];
    if (heatDelta > 0) {
      events.add(
        BattleEvent(
          kind: BattleBeatKind.heat,
          text: 'HEAT +$heatDelta',
          hold: const Duration(milliseconds: 220),
        ),
      );
    }
    return events;
  }
}
