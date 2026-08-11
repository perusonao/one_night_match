/// Combat Ver.1 Playable 1B — Match Session（Playable 1A controllerへの
/// 最小adapter）と、UI/application層専用のseed生成
/// （docs/design/combat_v1_playable_match_ui.md Playable 1B追記）。
///
/// [CombatV1PlayableMatchSession]は`CombatV1PlayableMatchController`
/// public APIのうち`CombatV1PlayableMatchScreen`が実際に必要とする
/// 部分だけを抽出したinterfaceで、ロジックは一切追加しない（純粋な
/// delegationのみ）。目的はテスト時に実Engineを回さず、scriptedな
/// fake session（`CombatV1PlayableMatchSession`実装）をwidget testへ
/// injectできるようにすること（design doc「74章 Runner Injection」）。
/// Playable 1A production file（`combat_v1_playable_match_controller.dart`
/// 等）は一切変更しない。
library;

import 'dart:math';

import '../combat_v1_legal_action.dart';
import '../playable/combat_v1_playable_match_config.dart';
import '../playable/combat_v1_playable_match_controller.dart';
import '../playable/combat_v1_playable_match_result.dart';
import '../playable/combat_v1_playable_match_snapshot.dart';

/// `CombatV1PlayableMatchScreen`が依存する、controllerの最小public
/// surface。実装は[CombatV1PlayableMatchController]への薄いdelegation
/// （[_RealPlayableMatchSession]）か、widget test専用のscripted fakeの
/// いずれか。
abstract interface class CombatV1PlayableMatchSession {
  CombatV1PlayableMatchSnapshot get snapshot;

  /// `status`が`matchOver`/`safetyLimit`/`invariantViolation`のいずれかに
  /// なった時点で非null（Playable 1A 18章）。
  CombatV1PlayableMatchResult? get result;

  CombatV1PlayableSubmitResult submitHumanAction({
    required int expectedRevision,
    required CombatV1LegalAction action,
  });

  CombatV1PlayableAdvanceResult advanceCpuOneAction();
}

/// [CombatV1PlayableMatchController]をそのまま[CombatV1PlayableMatchSession]
/// へ委譲する、production既定の実装。
class CombatV1PlayableRealMatchSession implements CombatV1PlayableMatchSession {
  CombatV1PlayableRealMatchSession(CombatV1PlayableMatchConfig config)
    : _controller = CombatV1PlayableMatchController(config);

  final CombatV1PlayableMatchController _controller;

  @override
  CombatV1PlayableMatchSnapshot get snapshot => _controller.snapshot;

  @override
  CombatV1PlayableMatchResult? get result => _controller.result;

  @override
  CombatV1PlayableSubmitResult submitHumanAction({
    required int expectedRevision,
    required CombatV1LegalAction action,
  }) => _controller.submitHumanAction(
    expectedRevision: expectedRevision,
    action: action,
  );

  @override
  CombatV1PlayableAdvanceResult advanceCpuOneAction() =>
      _controller.advanceCpuOneAction();
}

/// [CombatV1PlayableMatchConfig]から[CombatV1PlayableMatchSession]を
/// 構築するfactoryのシグネチャ（design doc「74章 Runner Injection」）。
/// productionは[combatV1PlayableDefaultSessionFactory]、widget testは
/// scripted fakeを返すfactoryを注入する。
typedef CombatV1PlayableSessionFactory =
    CombatV1PlayableMatchSession Function(CombatV1PlayableMatchConfig config);

CombatV1PlayableMatchSession combatV1PlayableDefaultSessionFactory(
  CombatV1PlayableMatchConfig config,
) => CombatV1PlayableRealMatchSession(config);

/// Match開始・Rematch毎に呼び出す、UI/application層専用のRandom seed
/// 生成（docs/design/combat_v1_playable_match_ui.md「12章 Seed
/// Strategy」）。Controller/Engine内部へは`DateTime.now()`を一切
/// 持ち込まない——ここ（UI層）でだけ1回生成し、
/// [CombatV1PlayableMatchConfig.engineSeed]/`.cpuPolicySeed`へ明示的に
/// 渡す。`Random()`（seedなし）はDartのnative/web両方で利用可能な
/// システムentropy由来のRandomのため、`DateTime.now()`を直接読む方式より
/// 単純かつ衝突しにくい（同一microsecondでの2回呼び出しでも異なる値に
/// なる）。
typedef CombatV1PlayableSeedPair = ({int engineSeed, int cpuPolicySeed});

/// [combatV1PlayableGenerateSeeds]のシグネチャ（widget test向けdeterministic
/// injection用、design doc「73章 CPU Loop Testability」と同じ思想）。
typedef CombatV1PlayableSeedGenerator = CombatV1PlayableSeedPair Function();

CombatV1PlayableSeedPair combatV1PlayableGenerateSeeds() {
  final source = Random();
  final engineSeed = source.nextInt(1 << 31);
  var cpuPolicySeed = source.nextInt(1 << 31);
  // engineSeedとcpuPolicySeedがEngine RNG/CPU Policy RNGの分離
  // （design doc「11章 CPU Policy RNG」）と混同されないよう、稀な偶然の
  // 一致だけは避けておく（正しさに必須ではない、デバッグ表示上の紛らわしさ
  // 回避のための最小限の配慮）。
  if (cpuPolicySeed == engineSeed) {
    cpuPolicySeed = (cpuPolicySeed + 1) & 0x7fffffff;
  }
  return (engineSeed: engineSeed, cpuPolicySeed: cpuPolicySeed);
}
