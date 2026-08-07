/// Technique Match: CPU行動の「見せ方」タイミング（Phase 8.5A-2 ⑪）。
///
/// 【重要】ここで定義する`Duration`は、UI層（[TechniqueMatchScreen]）が
/// CPUの行動をユーザーに見せるための演出上の待ち時間にすぎない。
/// CPUの意思決定ロジック（`TechniqueMatchCpu`）や、CPU対CPUの一括
/// シミュレーション（`playFullMatch`）は一切これを参照しない＝常に
/// 即時実行のまま。演出速度設定（[TechniqueCpuPresentationSpeed]）で
/// 変わるのは「待つ長さ」だけで、CPUの強さ・選択ロジックには絶対に
/// 影響しない。
library;

/// 各局面での基準ウェイト（[TechniqueCpuPresentationSpeed.normal]の場合の値）。
class TechniqueCpuPresentationTiming {
  const TechniqueCpuPresentationTiming._();

  static const Duration think = Duration(milliseconds: 600);
  static const Duration energySet = Duration(milliseconds: 800);
  static const Duration attackDeclared = Duration(milliseconds: 1200);
  static const Duration counterUsed = Duration(milliseconds: 1500);
  static const Duration hitResolved = Duration(milliseconds: 1500);
  static const Duration fallOrSubmissionStart = Duration(milliseconds: 1500);
  static const Duration kickOutOrRopeBreak = Duration(milliseconds: 1500);
  static const Duration finisherDeclared = Duration(milliseconds: 2000);
  static const Duration finisherResolved = Duration(milliseconds: 2000);
  static const Duration passTurn = Duration(milliseconds: 500);
}

/// CPU設定画面（[TechniqueMatchSetupScreen]）で選ぶ「CPU演出速度」。
/// [multiplier]を[TechniqueCpuPresentationTiming]の各`Duration`へ掛けて
/// 実際の待ち時間を算出する。CPUの意思決定には一切関与しない。
enum TechniqueCpuPresentationSpeed {
  slow('ゆっくり', 1.5),
  normal('標準', 1.0),
  fast('高速', 0.5);

  const TechniqueCpuPresentationSpeed(this.label, this.multiplier);

  final String label;
  final double multiplier;

  Duration scale(Duration base) =>
      Duration(microseconds: (base.inMicroseconds * multiplier).round());
}
