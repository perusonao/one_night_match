/// Balance Dashboard 1B — Editable Run Config
/// （docs/design/combat_v1_balance_dashboard_1b.md 7〜16章）。
///
/// [CombatV1BalanceDashboardRunConfig]は、Dashboard 1BのUI入力を保持する
/// pure immutable value object。責務は3つのみ（38章「Config Types」）:
///
/// - UI入力（preset選択・custom text・seed text・policy・maxActions
///   text）の保持
/// - inline validation（field単位のerror message導出）
/// - 検証済み値からdomainの`CombatV1BatchSimulationConfig`への変換
///   （[toBatchConfig]）
///
/// domain configのrule engineを再実装しない——wrestler set（canonical 4人）
/// とrules（`const CombatV1RulesConfig()`）はDashboard 1Bでは常に固定で、
/// このfileも編集可能にしない（7・14章「Rules」）。
///
/// engineやFlutter widgetへは依存しない、pure Dart classとして実装する
/// （ただしtext field表示用にString rawをそのまま保持するため、UI層との
/// 結合は自然に発生する）。
library;

import '../simulation/batch/combat_v1_batch_matchup.dart';
import '../simulation/batch/combat_v1_batch_simulation_config.dart';
import '../simulation/combat_v1_simulation_policy.dart';

/// matchesPerMatchupのpreset（8章「Matches Per Matchup」）。
///
/// Custom以外は固定値を持ち、custom text fieldの入力を無視する。
enum CombatV1BalanceDashboardMatchesPreset {
  /// 20 matches/matchup（development smoke run）。
  smoke,

  /// 100 matches/matchup（default、既存Dashboard 1Aのfixed defaultと同値）。
  quick,

  /// 1000 matches/matchup（16,000 total、確認dialog対象、21章）。
  analysis,

  /// custom text fieldの値をそのまま使う。
  custom;

  /// このpresetの固定matchesPerMatchup値。[custom]は`null`
  /// （custom text fieldから読み取る）。
  int? get fixedValue => switch (this) {
    CombatV1BalanceDashboardMatchesPreset.smoke => 20,
    CombatV1BalanceDashboardMatchesPreset.quick => 100,
    CombatV1BalanceDashboardMatchesPreset.analysis => 1000,
    CombatV1BalanceDashboardMatchesPreset.custom => null,
  };

  String get label => switch (this) {
    CombatV1BalanceDashboardMatchesPreset.smoke => 'Smoke (20)',
    CombatV1BalanceDashboardMatchesPreset.quick => 'Quick (100)',
    CombatV1BalanceDashboardMatchesPreset.analysis => 'Analysis (1000)',
    CombatV1BalanceDashboardMatchesPreset.custom => 'Custom',
  };
}

/// Dashboard 1BのUI draft/last-run configが共有するvalidated value bundle。
///
/// [CombatV1BalanceDashboardRunConfig.toBatchConfig]がこれを最終的な
/// `CombatV1BatchSimulationConfig`へ変換する前段として使う——UI側の
/// raw text入力とdomain configの間に、常にこのpure classを挟む。
class CombatV1BalanceDashboardRunConfig {
  const CombatV1BalanceDashboardRunConfig({
    required this.matchesPreset,
    required this.customMatchesPerMatchupText,
    required this.masterSeedText,
    required this.playerAPolicy,
    required this.playerBPolicy,
    required this.maxActionsText,
  });

  /// Dashboard 1Bの初期draft（54章「Default Draft」）。1Aのfixed default
  /// と同一値: canonical 4 wrestlers・100/matchup・seed 12345・
  /// RandomLegal/RandomLegal・maxActions 500・default rules。
  factory CombatV1BalanceDashboardRunConfig.initial() =>
      const CombatV1BalanceDashboardRunConfig(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.quick,
        customMatchesPerMatchupText: '100',
        masterSeedText: '12345',
        playerAPolicy: CombatV1SimulationPolicyKind.randomLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
        maxActionsText: '500',
      );

  /// Dashboard UI上のhard max（10章）。domain
  /// `CombatV1BatchSimulationConfig`へ新しい上限を追加しない——これは
  /// Dashboard guardのみ。
  static const int hardMaxMatchesPerMatchup = 1000;

  /// これを超えるとdevelopment performance warningを表示する（9章）。
  static const int performanceWarningThreshold = 100;

  final CombatV1BalanceDashboardMatchesPreset matchesPreset;

  /// [matchesPreset] == [CombatV1BalanceDashboardMatchesPreset.custom]の
  /// 場合のみ参照されるraw text入力。
  final String customMatchesPerMatchupText;

  final String masterSeedText;
  final CombatV1SimulationPolicyKind playerAPolicy;
  final CombatV1SimulationPolicyKind playerBPolicy;
  final String maxActionsText;

  CombatV1BalanceDashboardRunConfig copyWith({
    CombatV1BalanceDashboardMatchesPreset? matchesPreset,
    String? customMatchesPerMatchupText,
    String? masterSeedText,
    CombatV1SimulationPolicyKind? playerAPolicy,
    CombatV1SimulationPolicyKind? playerBPolicy,
    String? maxActionsText,
  }) => CombatV1BalanceDashboardRunConfig(
    matchesPreset: matchesPreset ?? this.matchesPreset,
    customMatchesPerMatchupText:
        customMatchesPerMatchupText ?? this.customMatchesPerMatchupText,
    masterSeedText: masterSeedText ?? this.masterSeedText,
    playerAPolicy: playerAPolicy ?? this.playerAPolicy,
    playerBPolicy: playerBPolicy ?? this.playerBPolicy,
    maxActionsText: maxActionsText ?? this.maxActionsText,
  );

  int? get _parsedCustomMatchesPerMatchup =>
      int.tryParse(customMatchesPerMatchupText.trim());

  /// 現在有効なmatchesPerMatchup値（presetの固定値、またはcustom入力の
  /// parse結果）。custom入力がinvalidな場合は`null`。
  int? get matchesPerMatchup =>
      matchesPreset.fixedValue ?? _parsedCustomMatchesPerMatchup;

  int? get masterSeed => int.tryParse(masterSeedText.trim());

  int? get maxActions => int.tryParse(maxActionsText.trim());

  /// matchesPerMatchup fieldのinline validation error（37章「Config
  /// Validation」）。presetが[CombatV1BalanceDashboardMatchesPreset.custom]
  /// 以外の場合は常に`null`（presetは常にvalid range内の固定値のため）。
  String? get matchesPerMatchupError {
    if (matchesPreset != CombatV1BalanceDashboardMatchesPreset.custom) {
      return null;
    }
    final text = customMatchesPerMatchupText.trim();
    if (text.isEmpty) {
      return 'Enter a whole number from 1 to $hardMaxMatchesPerMatchup.';
    }
    final value = int.tryParse(text);
    if (value == null) {
      return 'Enter a whole number.';
    }
    if (value < 1 || value > hardMaxMatchesPerMatchup) {
      return 'Must be between 1 and $hardMaxMatchesPerMatchup.';
    }
    return null;
  }

  /// masterSeed fieldのinline validation error（11章「Master Seed」）。
  String? get masterSeedError {
    final text = masterSeedText.trim();
    if (text.isEmpty) return 'Seed cannot be blank.';
    if (int.tryParse(text) == null) return 'Enter a whole number.';
    return null;
  }

  /// maxActions fieldのinline validation error（13章「Max Actions」）。
  String? get maxActionsError {
    final text = maxActionsText.trim();
    if (text.isEmpty) return 'Max actions cannot be blank.';
    final value = int.tryParse(text);
    if (value == null) return 'Enter a whole number.';
    if (value < 1) return 'Must be at least 1.';
    return null;
  }

  /// いずれかのfieldがinvalidならfalse（37章「Run button disabled時」）。
  bool get isValid =>
      matchesPerMatchupError == null &&
      masterSeedError == null &&
      maxActionsError == null;

  /// `16 × matchesPerMatchup`（8章「Total Matches表示」）。matchesPerMatchup
  /// がinvalidな場合は0。
  int get totalMatches {
    final matches = matchesPerMatchup;
    if (matches == null) return 0;
    return combatV1DefaultBatchWrestlerIds.length *
        combatV1DefaultBatchWrestlerIds.length *
        matches;
  }

  /// matchesPerMatchup > 100（9章「Performance Warning」）。
  bool get showsPerformanceWarning =>
      (matchesPerMatchup ?? 0) > performanceWarningThreshold;

  /// Analysis preset（1000/matchup、16,000 total）実行前の確認dialogが
  /// 必要かどうか（21章「Analysis Preset Confirmation」）。hard maxと同値
  /// のため、custom入力で1000を直接指定した場合も対象にする。
  bool get requiresRunConfirmation =>
      (matchesPerMatchup ?? 0) >= hardMaxMatchesPerMatchup;

  /// 検証済み値からdomainの`CombatV1BatchSimulationConfig`を組み立てる
  /// （38章）。[isValid]がfalseの場合は呼び出さないこと（assert）——Run
  /// buttonがinvalid時disabledになるため、UI経由では到達しない。
  CombatV1BatchSimulationConfig toBatchConfig() {
    assert(isValid, 'invalid draft configからtoBatchConfigは呼べない');
    return CombatV1BatchSimulationConfig(
      wrestlerIds: combatV1DefaultBatchWrestlerIds,
      matchesPerMatchup: matchesPerMatchup!,
      masterSeed: masterSeed!,
      pairing: CombatV1PolicyPairing(
        playerAPolicy: playerAPolicy,
        playerBPolicy: playerBPolicy,
      ),
      maxActions: maxActions!,
      // rules: default（`const CombatV1RulesConfig()`固定、14章）。
    );
  }
}
