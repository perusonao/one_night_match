// Combat Ver.1 Playable 2A-3 — Technique / Counter Decision Readability
// widget test（lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart）。
//
// 「Techniqueを選ぶ時点、およびCounterする時点で、そのカード/攻撃が試合の
// 勝ち筋にどう関係するか理解できる」ことを、実Engineを経由しないscripted
// snapshot（`combat_v1_playable_ui_test_fixtures.dart`）で検証する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: child,
);

CombatV1PlayableMatchScreen _screen(
  FakePlayableMatchSession session, {
  String humanWrestlerId = 'akari',
  String cpuWrestlerId = 'reina',
}) => CombatV1PlayableMatchScreen(
  humanWrestlerId: humanWrestlerId,
  cpuWrestlerId: cpuWrestlerId,
  cpuDelay: Duration.zero,
  sessionFactory: (_) => session,
);

const CombatV1Technique _directPinTechnique = CombatV1Technique(
  id: 'test_2a3_direct_pin',
  name: 'テストダイレクトピン技',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
  damage: 20,
  heatGain: 20,
  family: CombatV1TechniqueFamily.slam,
  directPin: true,
);

const CombatV1Technique _submissionHoldTechnique = CombatV1Technique(
  id: 'test_2a3_submission_hold',
  name: 'テストアームキャッチ',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
  damage: 10,
  heatGain: 10,
  family: CombatV1TechniqueFamily.armbar,
  submissionHold: true,
);

const CombatV1Technique _roughTechnique = CombatV1Technique(
  id: 'test_2a3_rough',
  name: 'テストチョーク攻撃',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.rough,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 1}),
  damage: 10,
  heatGain: 20,
  family: CombatV1TechniqueFamily.choke,
);

const CombatV1Technique _directPinFinisher = CombatV1Technique(
  id: 'test_2a3_finisher_direct_pin',
  name: 'テストダイレクトピンフィニッシャー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 3}),
  damage: 30,
  heatGain: 40,
  family: CombatV1TechniqueFamily.powerbomb,
  finisherType: CombatV1FinisherType.directPin,
);

const CombatV1Technique _submissionFinisher = CombatV1Technique(
  id: 'test_2a3_finisher_submission',
  name: 'テストサブミッションフィニッシャー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 3}),
  damage: 30,
  heatGain: 40,
  family: CombatV1TechniqueFamily.legLock,
  finisherType: CombatV1FinisherType.submission,
);

void main() {
  group('Technique Card — Decision Traits（5〜11章）', () {
    testWidgets('DIRECT PIN技はDIRECT PIN badgeを表示する', (tester) async {
      final snapshot = testSnapshot(
        human: testHumanStatus(
          hand: [
            testTechniqueCard(instanceId: 'h1', technique: _directPinTechnique),
          ],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_card_direct_pin_badge')),
        findsOneWidget,
      );
      expect(find.text('DIRECT PIN'), findsOneWidget);
      expect(
        find.byKey(const Key('combat_v1_playable_card_submission_badge')),
        findsNothing,
      );
    });

    testWidgets('Submission Hold技はSUBMISSION badgeを表示する', (tester) async {
      final snapshot = testSnapshot(
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: _submissionHoldTechnique,
            ),
          ],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_card_submission_badge')),
        findsOneWidget,
      );
      expect(find.text('SUBMISSION'), findsOneWidget);
    });

    testWidgets('ROUGH技はROUGH badgeを表示する', (tester) async {
      final snapshot = testSnapshot(
        human: testHumanStatus(
          hand: [testTechniqueCard(instanceId: 'h1', technique: _roughTechnique)],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_card_rough_badge')),
        findsOneWidget,
      );
      expect(find.text('ROUGH'), findsOneWidget);
    });

    testWidgets('Direct PIN FINISHERは"FINISHER · PIN"合成badgeを表示する（単独の'
        'DIRECT PIN badgeは重複表示しない）', (tester) async {
      final snapshot = testSnapshot(
        sharedHeat: 200,
        finisherHeatThreshold: 200,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(instanceId: 'h1', technique: _directPinFinisher),
          ],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(
          const Key('combat_v1_playable_card_finisher_resolution_badge'),
        ),
        findsOneWidget,
      );
      expect(find.text('FINISHER · PIN'), findsOneWidget);
      expect(
        find.byKey(const Key('combat_v1_playable_card_direct_pin_badge')),
        findsNothing,
      );
    });

    testWidgets('Submission FINISHERは"FINISHER · SUBMISSION"合成badgeを表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        sharedHeat: 200,
        finisherHeatThreshold: 200,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: _submissionFinisher,
            ),
          ],
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(find.text('FINISHER · SUBMISSION'), findsOneWidget);
    });

    testWidgets(
      'trait badgeは使用可否（isUsable）と独立して表示される——unusableな'
      'FINISHERでもFINISHER · SUBMISSION badgeは表示され続ける（Finisher HEAT '
      '未到達時にtraitが消えない、22章「trait表示とusable/unusableの混同'
      '防止」）',
      (tester) async {
        final snapshot = testSnapshot(
          sharedHeat: 0,
          finisherHeatThreshold: 200,
          human: testHumanStatus(
            hand: [
              testTechniqueCard(
                instanceId: 'h1',
                technique: _submissionFinisher,
                isUsable: false,
              ),
            ],
          ),
          legalActions: const [],
        );
        await tester.pumpWidget(
          _wrap(_screen(FakePlayableMatchSession(snapshot))),
        );
        await tester.pump();

        // HEAT未到達で使用不可でも、trait badge自体は成立後の性質を
        // 示すものなので表示され続ける。
        expect(find.text('FINISHER · SUBMISSION'), findsOneWidget);
        // 一方、使用不可の理由（HEAT要件）は別途disabledメッセージ側で
        // 説明される。
        expect(
          find.byKey(const Key('combat_v1_playable_card_disabled_message')),
          findsOneWidget,
        );
      },
    );

    testWidgets('通常技はtrait badgeを一切表示しない', (tester) async {
      final snapshot = testSnapshot(
        human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1')]),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('combat_v1_playable_card_trait_badges')),
        findsNothing,
      );
    });
  });

  group('Counter Response — Incoming Attack Summary（13章）', () {
    testWidgets('Counter available: DMG・HEAT・posture結果・decline optionが読める', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testCounterCard(instanceId: 'c1'),
            testTechniqueCard(instanceId: 'h1'),
          ],
        ),
        pendingAttack: testPendingAttack(),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pumpAndSettle();

      final effectLine = tester.widget<Text>(
        find.byKey(const Key('combat_v1_playable_pending_effect_line')),
      );
      expect(effectLine.data, contains('DMG'));
      expect(effectLine.data, contains('HEAT'));
      expect(
        find.byKey(const Key('combat_v1_playable_pending_counter_prevents_hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_playable_counter_decline_button')),
        findsOneWidget,
      );
    });

    testWidgets('Direct PIN incoming: DIRECT PIN badgeとPIN防止hintを表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testCounterCard(instanceId: 'c1'),
            testTechniqueCard(instanceId: 'h1'),
          ],
        ),
        pendingAttack: testPendingAttack(technique: _directPinTechnique),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_playable_pending_direct_pin_badge')),
        findsOneWidget,
      );
      final hint = tester.widget<Text>(
        find.byKey(const Key('combat_v1_playable_pending_counter_prevents_hint')),
      );
      expect(hint.data, contains('自動PINへの移行'));
    });

    testWidgets('Submission incoming: SUBMISSION badgeとSubmission防止hintを表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testCounterCard(instanceId: 'c1'),
            testTechniqueCard(instanceId: 'h1'),
          ],
        ),
        pendingAttack: testPendingAttack(technique: _submissionHoldTechnique),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_playable_pending_submission_badge')),
        findsOneWidget,
      );
      final hint = tester.widget<Text>(
        find.byKey(const Key('combat_v1_playable_pending_counter_prevents_hint')),
      );
      expect(hint.data, contains('Submission'));
    });

    testWidgets('Finisher incoming: FINISHER合成badgeを表示する', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testCounterCard(instanceId: 'c1'),
            testTechniqueCard(instanceId: 'h1'),
          ],
        ),
        pendingAttack: testPendingAttack(technique: _submissionFinisher),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('combat_v1_playable_pending_finisher_resolution_badge'),
        ),
        findsOneWidget,
      );
      expect(find.text('FINISHER · SUBMISSION'), findsOneWidget);
    });

    testWidgets(
      'Counter unavailable: Counter選択を案内せず、incoming attack情報は'
      '読め、declineへの進行が明確（Playable 2A-1 regression、15章）',
      (tester) async {
        final snapshot = testSnapshot(
          phase: CombatV1MatchPhase.counterResponsePending,
          isHumanInputRequired: true,
          human: testHumanStatus(hand: [testTechniqueCard(instanceId: 'h1')]),
          pendingAttack: testPendingAttack(technique: _directPinFinisher),
          legalActions: const [
            CombatV1DeclineCounterAction(actorPlayerIndex: 0),
          ],
        );
        await tester.pumpWidget(
          _wrap(_screen(FakePlayableMatchSession(snapshot))),
        );
        await tester.pumpAndSettle();

        // 存在しないCounter選択を案内しない。
        expect(find.text('使用できるCOUNTERカードがありません'), findsOneWidget);
        expect(
          find.byKey(const Key('combat_v1_playable_counter_hand')),
          findsNothing,
        );
        // Play Counter button自体はdisabledで存在するが、有効な選択肢
        // としては機能しない。
        final playButton = tester.widget<FilledButton>(
          find.byKey(const Key('combat_v1_playable_counter_play_button')),
        );
        expect(playButton.onPressed, isNull);
        // incoming attack情報（trait badge含む）は引き続き読める。
        expect(find.text('FINISHER · PIN'), findsOneWidget);
        // decline（技を受ける）は明確に選択可能。
        final declineButton = tester.widget<OutlinedButton>(
          find.byKey(const Key('combat_v1_playable_counter_decline_button')),
        );
        expect(declineButton.onPressed, isNotNull);
      },
    );
  });

  group('Counter Card Information（16章 family/group match）', () {
    testWidgets('usable Counter cardはpending攻撃との対応系統を表示する', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.counterResponsePending,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testCounterCard(instanceId: 'c1'),
            testTechniqueCard(instanceId: 'h1'),
          ],
        ),
        // testNormalTechnique.family == elbow、testCounter.counterableFamilies
        // == [elbow]（`combat_v1_playable_ui_test_fixtures.dart`）。
        pendingAttack: testPendingAttack(),
        legalActions: const [
          CombatV1CounterAction(actorPlayerIndex: 0, cardInstanceId: 'c1'),
          CombatV1DeclineCounterAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_playable_counter_family_match')),
        findsOneWidget,
      );
      expect(find.textContaining('対応: Elbow'), findsOneWidget);
    });
  });
}
