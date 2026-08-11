/// Balance Dashboard 1A — Formatting Helpers
/// （docs/design/combat_v1_balance_dashboard_1a.md 9章「Formatting」）。
///
/// Dashboard UI全体で使うpureなformatting関数群。ViewModel
/// （`combat_v1_balance_dashboard_view_model.dart`）はraw値
/// （`double?`/`int`/`int?`）のみを保持し、文字列化は常にこのfile経由で
/// 行う——ViewModel自体に文字列整形ロジックを持たせない（責務分離）。
///
/// engineやFlutter widgetへは一切依存しない、pure Dart関数のみ。
library;

/// Dashboard全体で使うnull表示の唯一の定義元。
///
/// `N/A`・`未計測`等の別表記を混在させない（18章「Null Format」）。
const String combatV1DashboardNullPlaceholder = '—';

/// `0.637` → `"63.7%"`（小数点1桁固定）。
///
/// `null`は[combatV1DashboardNullPlaceholder]（`"—"`）。`100%`は`"100.0%"`、
/// `0`は`"0.0%"`に統一する（17章「Percent Format」）。
String combatV1FormatPercent(double? value) {
  if (value == null) return combatV1DashboardNullPlaceholder;
  return '${(value * 100).toStringAsFixed(1)}%';
}

/// 常に存在するint countの表示（そのまま文字列化するだけの薄いhelper——
/// 呼び出し側での書式統一のために用意する）。
String combatV1FormatCount(int value) => '$value';

/// nullable intの表示。`null`は[combatV1DashboardNullPlaceholder]。
String combatV1FormatNullableCount(int? value) =>
    value == null ? combatV1DashboardNullPlaceholder : '$value';

/// nullable doubleの表示（小数点[decimals]桁固定、既定1桁）。`null`は
/// [combatV1DashboardNullPlaceholder]。
String combatV1FormatNullableNumber(double? value, {int decimals = 1}) =>
    value == null
    ? combatV1DashboardNullPlaceholder
    : value.toStringAsFixed(decimals);

/// [executedMatchCount]と[runtime]から`matches/sec`を計算して表示する
/// （28章「Matches / Sec」、SHOULD・development indicator——performance
/// guaranteeではない）。
///
/// `runtime`が0以下（計測不能）の場合は[combatV1DashboardNullPlaceholder]。
String combatV1FormatMatchesPerSecond(int executedMatchCount, Duration runtime) {
  final seconds = runtime.inMicroseconds / Duration.microsecondsPerSecond;
  if (seconds <= 0) return combatV1DashboardNullPlaceholder;
  return (executedMatchCount / seconds).toStringAsFixed(1);
}
