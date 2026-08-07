/// アプリ全体のバージョン・改修履歴の単一情報源（Phase 8.5A-2）。
///
/// 【設計メモ】`pubspec.yaml`の`version`（`1.0.0+1`）はFlutter標準の
/// セマンティックバージョニング（数値のみ）を要求するため、本プロジェクトの
/// フェーズ表記（例: `0.8.5A-2`）とは表記体系が異なり、`pubspec.yaml`側から
/// 直接この文字列を導出することはできない。二重管理を避けるため、
/// アプリ内で使う「フェーズバージョン」はこの[AppBuildInfo]を唯一の
/// 定義元とし、画面表示・JSON試合ログの双方がここを参照する
/// （値を画面ごとに直接書かない）。
class AppBuildInfo {
  const AppBuildInfo._();

  /// 画面・JSONログ双方で表示するフェーズバージョン。
  static const String version = '0.9.0';

  /// 今回のビルドの一言ラベル。
  static const String buildLabel = 'Playtest Analytics Phase A';

  /// リリース日（表示用、YYYY-MM-DD）。
  static const String releasedAt = '2026-08-07';

  /// JSON試合ログの`game.gameVersion`に使う識別子（例:
  /// `version` = `'0.8.5A-2'` → `'phase8.5A-2'`）。画面表示の[version]と
  /// 常に一致させるため、固定リテラルではなく[version]から導出する
  /// （`phase8.2`のような古い固定値が残って画面とJSONが食い違う、という
  /// 過去のバグの再発防止）。先頭の`'0.'`（メジャーバージョン未達を示す
  /// プレフィックス）だけ取り除き、大文字小文字はそのまま保持する。
  static String get gameVersionId {
    final trimmed = version.startsWith('0.') ? version.substring(2) : version;
    return 'phase$trimmed';
  }

  /// トップ画面の「更新内容」ボタンで表示する改修履歴（最新が先頭）。
  /// 3〜5件程度を目安に、直近のリリースのみを保持する。
  static const List<AppChangelogEntry> changelog = [
    AppChangelogEntry(
      version: '0.9.0',
      items: [
        'Playtest Analytics Phase Aを追加（試合終了時に自動診断・自動保存）',
        'Debug分析からPlaytest Analytics画面へ遷移可能に',
        'CPU Decision Traceの診断フィールド（legalMoveCount等）を追加',
      ],
    ),
    AppChangelogEntry(
      version: '0.8.5A-2',
      items: [
        'CPUが合法な技を持っているのに攻撃しない問題を修正',
        '返技後にCPUが攻撃を継続できるよう修正',
        'CPUの行動演出速度を調整',
        'ターン数を試合時間へ換算して表示',
      ],
    ),
    AppChangelogEntry(
      version: '0.8.5A',
      items: [
        'Combo Speedを追加',
        '1ターンで複数技を使用可能に変更',
        '休息と30秒ターンタイマーを廃止',
      ],
    ),
  ];
}

/// [AppBuildInfo.changelog]の1バージョン分。
class AppChangelogEntry {
  const AppChangelogEntry({required this.version, required this.items});

  final String version;
  final List<String> items;
}
