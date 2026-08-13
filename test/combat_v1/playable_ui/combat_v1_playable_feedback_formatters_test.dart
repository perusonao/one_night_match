// Combat Ver.1 Playable 2A-4 — Match Flow / Result Feedback Readability
// pure derivation test
// （lib/src/combat_v1/playable_ui/combat_v1_playable_feedback_formatters.dart）。
//
// Widgetを一切構築しない、pure functionのみを対象とするtest
// （`combat_v1_playable_technique_traits_test.dart`と同じ方針）。synthetic
// `CombatV1PlayableActionFeedback`（`testActionFeedback`）だけを使い、
// Core Engineは一切経由しない。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_action_feedback.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_feedback_formatters.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

const int _humanPlayerIndex = 0;

void main() {
  group('Severity（情報階層Tier）', () {
    test('通常のTechnique成功はTier 3（techniqueResult）', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        damage: 12,
        hpOwnerPlayerIndex: 1,
        hpBefore: 68,
        hpAfter: 56,
      );
      expect(
        combatV1PlayableFeedbackSeverity(feedback),
        CombatV1PlayableFeedbackSeverity.techniqueResult,
      );
    });

    test('相手をDOWNさせたTechnique成功はTier 2（majorStateChange）', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        damage: 20,
        postureOwnerPlayerIndex: 1,
        postureBefore: CombatV1WrestlerPosture.stand,
        postureAfter: CombatV1WrestlerPosture.down,
      );
      expect(
        combatV1PlayableFeedbackSeverity(feedback),
        CombatV1PlayableFeedbackSeverity.majorStateChange,
      );
    });

    test('FINISHER成立（Match Over未満）はTier 1（matchDecisive）', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        damage: 60,
        isFinisher: true,
      );
      expect(
        combatV1PlayableFeedbackSeverity(feedback),
        CombatV1PlayableFeedbackSeverity.matchDecisive,
      );
    });

    test('PIN 3-count（matchOver）はTier 1', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.pinResolved,
        kocOwnerPlayerIndex: 1,
        kocBefore: 0,
        kocAfter: 0,
        pinOutcome: CombatV1PlayablePinFeedbackOutcome.matchOver,
      );
      expect(
        combatV1PlayableFeedbackSeverity(feedback),
        CombatV1PlayableFeedbackSeverity.matchDecisive,
      );
    });

    test('PIN kick outはTier 2', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.pinResolved,
        kocOwnerPlayerIndex: 1,
        kocBefore: 10,
        kocAfter: 7,
        pinOutcome: CombatV1PlayablePinFeedbackOutcome.kickOut,
      );
      expect(
        combatV1PlayableFeedbackSeverity(feedback),
        CombatV1PlayableFeedbackSeverity.majorStateChange,
      );
    });

    test('SUBMISSION GIVE UP（matchOver）はTier 1', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        submissionOutcome: CombatV1PlayableSubmissionFeedbackOutcome.matchOver,
      );
      expect(
        combatV1PlayableFeedbackSeverity(feedback),
        CombatV1PlayableFeedbackSeverity.matchDecisive,
      );
    });

    test('COUNTER成立はTier 2', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.counterPlayed,
      );
      expect(
        combatV1PlayableFeedbackSeverity(feedback),
        CombatV1PlayableFeedbackSeverity.majorStateChange,
      );
    });

    test('discard/standUp/rest/endTurn/宣言はTier 4（minorEvent）', () {
      for (final kind in [
        CombatV1PlayableFeedbackKind.discard,
        CombatV1PlayableFeedbackKind.standUp,
        CombatV1PlayableFeedbackKind.rest,
        CombatV1PlayableFeedbackKind.endTurn,
        CombatV1PlayableFeedbackKind.techniqueDeclared,
      ]) {
        final feedback = testActionFeedback(kind: kind);
        expect(
          combatV1PlayableFeedbackSeverity(feedback),
          CombatV1PlayableFeedbackSeverity.minorEvent,
          reason: 'kind: $kind',
        );
      }
    });
  });

  group('Latest Result — Primary / Secondary（Technique）', () {
    test('通常成功: primaryにdamage、secondaryにHP/HEAT/posture', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        actorPlayerIndex: 0,
        actionDisplayName: 'ドロップキック',
        damage: 12,
        hpOwnerPlayerIndex: 1,
        hpBefore: 68,
        hpAfter: 56,
        postureOwnerPlayerIndex: 1,
        postureBefore: CombatV1WrestlerPosture.stand,
        postureAfter: CombatV1WrestlerPosture.down,
        heatBefore: 100,
        heatAfter: 120,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );

      expect(result.primary, contains('ドロップキック'));
      expect(result.primary, contains('12 DAMAGE'));
      expect(result.secondary, isNotNull);
      expect(result.secondary, contains('HP 68 → 56'));
      expect(result.secondary, contains('HEAT +20'));
      expect(result.secondary, contains('STAND'));
      expect(result.secondary, contains('DOWN'));
      // primaryにHP/HEATの生値は含めない（primary/secondaryの責務分離）。
      expect(result.primary, isNot(contains('HEAT')));
    });

    test('HEATが変化しない場合、secondaryにHEAT行を含めない（推測で埋めない）', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        damage: 15,
        heatBefore: 10,
        heatAfter: 10,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary ?? '', isNot(contains('HEAT')));
    });

    test('FINISHER成立: primaryに(FINISHER)を明示する', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        actionDisplayName: 'テストフィニッシャー',
        damage: 60,
        isFinisher: true,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.primary, contains('テストフィニッシャー'));
      expect(result.primary, contains('FINISHER'));
      expect(result.severity, CombatV1PlayableFeedbackSeverity.matchDecisive);
    });

    test('Direct PIN自動移行（KICK OUT）: secondaryにPIN ATTEMPT結果を追記', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        damage: 30,
        kocOwnerPlayerIndex: 1,
        kocBefore: 10,
        kocAfter: 7,
        pinOutcome: CombatV1PlayablePinFeedbackOutcome.kickOut,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary, contains('PIN ATTEMPT'));
      expect(result.secondary, contains('KICK OUT'));
      expect(result.secondary, contains('KOC 10 → 7'));
      expect(result.secondary, isNot(contains('MATCH OVER')));
    });

    test('Direct PINだがDOWN条件を満たさない境界（pinOutcome無し）: '
        'PIN ATTEMPT文言を出さない', () {
      // Engine側は「成立後、相手がDOWNの場合のみ」自動PINへ移行する
      // （`combatV1PlayableDirectPinTraitDetail`と同じ条件）。DOWNに
      // ならなかった場合、controllerはpinOutcomeをnullのままにする
      // ——feedback derivationはこの境界を「推測で埋めない」。
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        damage: 10,
        postureOwnerPlayerIndex: 1,
        postureBefore: CombatV1WrestlerPosture.stand,
        postureAfter: CombatV1WrestlerPosture.stand,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary ?? '', isNot(contains('PIN ATTEMPT')));
      expect(
        combatV1PlayableFeedbackSeverity(feedback),
        CombatV1PlayableFeedbackSeverity.techniqueResult,
      );
    });

    test('SUBMISSION ESCAPE: secondaryにSUBMISSION結果とKOC変化', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        damage: 10,
        kocOwnerPlayerIndex: 1,
        kocBefore: 5,
        kocAfter: 3,
        submissionOutcome: CombatV1PlayableSubmissionFeedbackOutcome.escaped,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary, contains('SUBMISSION'));
      expect(result.secondary, contains('ESCAPED'));
      expect(result.secondary, contains('KOC 5 → 3'));
      expect(result.secondary, isNot(contains('GIVE UP')));
    });

    test('SUBMISSION GIVE UP（matchOver）: 推測countを一切含めない', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.techniqueResolved,
        damage: 10,
        submissionOutcome: CombatV1PlayableSubmissionFeedbackOutcome.matchOver,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary, contains('SUBMISSION'));
      expect(result.secondary, contains('GIVE UP'));
      expect(result.secondary, contains('MATCH OVER'));
    });
  });

  group('Latest Result — PIN（通常宣言）', () {
    test('KICK OUT: primaryにPIN ATTEMPT + 結果、secondaryにKOC変化', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.pinResolved,
        actionDisplayName: null,
        kocOwnerPlayerIndex: 1,
        kocBefore: 10,
        kocAfter: 7,
        pinOutcome: CombatV1PlayablePinFeedbackOutcome.kickOut,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.primary, contains('PIN ATTEMPT'));
      expect(result.primary, contains('KICK OUT'));
      expect(result.primary, isNot(contains('MATCH OVER')));
      expect(result.secondary, contains('KOC 10 → 7'));
    });

    test('3 COUNT（matchOver）: 「1」「2」「2.9」等の推測countを含めない', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.pinResolved,
        actionDisplayName: null,
        kocOwnerPlayerIndex: 1,
        kocBefore: 0,
        kocAfter: 0,
        pinOutcome: CombatV1PlayablePinFeedbackOutcome.matchOver,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.primary, contains('PIN ATTEMPT'));
      expect(result.primary, contains('3 COUNT'));
      expect(result.primary, contains('MATCH OVER'));
      expect(result.primary, isNot(contains('1 COUNT')));
      expect(result.primary, isNot(contains('2 COUNT')));
      expect(result.primary, isNot(contains('2.9')));
    });
  });

  group('Latest Result — COUNTER', () {
    test('通常のCounter成立: DMG/HEAT/状態変化を防いだことをsecondaryへ記載', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.counterPlayed,
        actionDisplayName: 'テストカウンター',
        relatedActionDisplayName: 'テストストライク',
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.primary, contains('テストカウンター'));
      expect(result.secondary, contains('テストストライク'));
      expect(result.secondary, contains('DMG'));
      expect(result.secondary, contains('HEAT'));
      expect(result.secondary, isNot(contains('PIN')));
    });

    test('Direct PIN技へのCounter成立: 自動PIN移行も防いだことを追記', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.counterPlayed,
        relatedActionDisplayName: 'テストダイレクトピン技',
        preventedDirectPin: true,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary, contains('PIN'));
    });

    test('Submission Hold技へのCounter成立: SUBMISSION移行条件も防いだことを追記', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.counterPlayed,
        relatedActionDisplayName: 'テストアームキャッチ',
        preventedSubmissionHold: true,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary, contains('SUBMISSION'));
    });

    // Playable 2A-4 Review Findings Fix（Major、negative assertion）——
    // `preventedDirectPin == false`は「DIRECT PIN traitはあったが、
    // Counterしなくても自動PIN移行は起きなかった」ケースを含む
    // （projection側の修正後、trait単独では`true`にならない）。この
    // 場合、formatterは「自動PIN移行を防いだ」と断定する文言
    // （`combatV1PlayableWouldTransitionToDirectPin`が実際に使う
    // wording「automatic PIN transition」）を一切出力してはならない。
    test(
      'preventedDirectPin == false: DIRECT PIN traitがあっても'
      '「自動PIN移行を防いだ」とは表示しない',
      () {
        final feedback = testActionFeedback(
          kind: CombatV1PlayableFeedbackKind.counterPlayed,
          relatedActionDisplayName: 'テストダイレクトピン技',
          preventedDirectPin: false,
        );
        final result = combatV1PlayableDeriveMatchFeedback(
          feedback,
          humanPlayerIndex: _humanPlayerIndex,
        );
        expect(result.secondary, isNot(contains('PIN')));
        expect(result.secondary, isNot(contains('automatic PIN transition')));
      },
    );

    // Playable 2A-4 Review Findings Fix（Major、negative assertion）——
    // `preventedSubmissionHold == false`は「SUBMISSION traitはあったが、
    // Counterしなくても実際にSUBMISSION resolutionへは移行しなかった」
    // ケースを含む。この場合、formatterは「SUBMISSION移行条件を防いだ」
    // と断定する文言（「the SUBMISSION transition condition」）を一切
    // 出力してはならない。
    test(
      'preventedSubmissionHold == false: SUBMISSION traitがあっても'
      '「SUBMISSION移行条件を防いだ」とは表示しない',
      () {
        final feedback = testActionFeedback(
          kind: CombatV1PlayableFeedbackKind.counterPlayed,
          relatedActionDisplayName: 'テストアームキャッチ',
          preventedSubmissionHold: false,
        );
        final result = combatV1PlayableDeriveMatchFeedback(
          feedback,
          humanPlayerIndex: _humanPlayerIndex,
        );
        expect(result.secondary, isNot(contains('SUBMISSION')));
        expect(
          result.secondary,
          isNot(contains('the SUBMISSION transition condition')),
        );
      },
    );

    test(
      'preventedDirectPin/preventedSubmissionHoldが両方falseでも、'
      'DMG/HEAT/state changesを防いだことは通常通り表示する',
      () {
        final feedback = testActionFeedback(
          kind: CombatV1PlayableFeedbackKind.counterPlayed,
          relatedActionDisplayName: 'テスト通常技',
          preventedDirectPin: false,
          preventedSubmissionHold: false,
        );
        final result = combatV1PlayableDeriveMatchFeedback(
          feedback,
          humanPlayerIndex: _humanPlayerIndex,
        );
        expect(result.secondary, contains('DMG'));
        expect(result.secondary, contains('HEAT'));
        expect(result.secondary, contains('state changes'));
      },
    );

    test('ROUGH技へのCounter成立: 非対称性（宣言時点で確定したPIN不可は取り消'
        'されない／次ターン制限は防げる）を明示する', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.counterPlayed,
        relatedActionDisplayName: 'テストラフ技',
        preventedIsRough: true,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary, contains('cannot PIN this turn'));
      expect(result.secondary, contains('next-turn TECHNIQUE limit'));
    });
  });

  group('Latest Result — 補助イベント（Tier 4）', () {
    test('Stand Up: primaryのみ', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.standUp,
        postureOwnerPlayerIndex: 0,
        postureBefore: CombatV1WrestlerPosture.down,
        postureAfter: CombatV1WrestlerPosture.stand,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.primary, contains('stood up'));
    });

    test('Rest: secondaryにHP回復を表示', () {
      final feedback = testActionFeedback(
        kind: CombatV1PlayableFeedbackKind.rest,
        hpOwnerPlayerIndex: 0,
        hpBefore: 40,
        hpAfter: 55,
      );
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.secondary, contains('HP 40 → 55'));
    });

    test('discard: hidden情報（card名等）を一切含めない', () {
      final feedback = testActionFeedback(kind: CombatV1PlayableFeedbackKind.discard);
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.primary, contains('discarded a card'));
      expect(result.secondary, isNull);
    });

    test('end turn', () {
      final feedback = testActionFeedback(kind: CombatV1PlayableFeedbackKind.endTurn);
      final result = combatV1PlayableDeriveMatchFeedback(
        feedback,
        humanPlayerIndex: _humanPlayerIndex,
      );
      expect(result.primary, contains('ended the turn'));
    });
  });
}
