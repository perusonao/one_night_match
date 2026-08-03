import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Ver.0.9 演出システム：効果音（SE）再生サービス。
///
/// テスト環境や音声プラグイン未対応の環境ではプラットフォームチャンネルが
/// 存在せず例外が飛ぶため、常に握りつぶして無音フォールバックする
/// （ゲームルール・進行には一切影響させない）。
enum SeKind {
  button,
  hitStrike,
  hitThrow,
  counter,
  pin,
  kickOut,
  win,
}

const Map<SeKind, String> _seAssetPaths = {
  SeKind.button: 'audio/se_button.wav',
  SeKind.hitStrike: 'audio/se_hit_strike.wav',
  SeKind.hitThrow: 'audio/se_hit_throw.wav',
  SeKind.counter: 'audio/se_counter.wav',
  SeKind.pin: 'audio/se_pin.wav',
  SeKind.kickOut: 'audio/se_kickout.wav',
  SeKind.win: 'audio/se_win.wav',
};

class BattleAudio {
  BattleAudio();

  bool muted = false;

  final Map<SeKind, AudioPlayer> _players = {};

  AudioPlayer _playerFor(SeKind kind) =>
      _players.putIfAbsent(kind, () => AudioPlayer(playerId: 'se_${kind.name}'));

  /// 効果音を再生する。失敗しても無視（演出はベストエフォート）。
  ///
  /// audioplayersはプラットフォームチャンネル未対応環境（flutter test等）だと
  /// イベントストリームのリスナー内で非同期に例外を投げるため、通常の
  /// try/catchでは捕まらない。runZonedGuardedでゾーン全体を保護し、
  /// ゲーム進行に一切影響させない。
  void play(SeKind kind) {
    if (muted) return;
    final path = _seAssetPaths[kind];
    if (path == null) return;
    runZonedGuarded(() {
      Future<void>(() async {
        try {
          final player = _playerFor(kind);
          await player.stop();
          await player.play(AssetSource(path), volume: 0.7);
        } on Object {
          // 効果音はベストエフォート。失敗してもゲーム進行に影響させない。
        }
      });
    }, (error, stack) {
      // プラグイン未対応環境等での非同期エラーは無視する。
    });
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}
