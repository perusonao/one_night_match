// Combat Ver.1 Playable 2A-5 Review Findings Fix — Hand Comparison /
// Mobile Readability widget test
// （lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart）。
//
// 独立レビュー指摘（Major: 初期手札5枚を比較するために横scrollが必要）
// の修正を検証する。目的は「5枚すべての詳細カードを画面内へ押し込む」
// ことではなく、「5枚の候補をscrollせず比較し、使うカードを決められる」
// ことなので、ここでは:
//
// - compact hand（一覧＝比較）が5枚同時にscroll無しで認識できること
// - compact card自体のtap targetが実際にhit-testできること
// - Technique A→B→解除という選択の切り替わりが正しく反映されること
// - Energyのexact boundary（required==available）でusable/unusableが
//   正しく切り替わること
// - 選択後detail（選択後にhand直下へ現れる`_SelectedTechniquePanel`）が
//   320/360/390pxで（必要なら縦scrollを許容して）読めること
// - compact card tap → detail確認 → 「技を使う」tap → 正しいLegalAction
//   がsubmitされるところまでを実際のtapで検証すること
//
// を検証する。既存2A-1〜2A-4・2A-5 approved good behavior（Energy
// visibility／Technique-discard分離／日本語化／LegalAction SSOT／
// Counter flow）は他ファイルの既存testで引き続き検証されており、ここで
// 重複しない。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
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

bool _isEnabled(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
  return button.onPressed != null;
}

Future<void> _withViewport(
  WidgetTester tester,
  Future<void> Function() body, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await body();
}

// 5枚の識別可能な技（required Energy属性・値をそれぞれ変える）。
const CombatV1Technique _techA = CombatV1Technique(
  id: 'test_review_fix_a',
  name: 'テスト技A',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
  damage: 15,
  heatGain: 10,
  family: CombatV1TechniqueFamily.elbow,
);
const CombatV1Technique _techB = CombatV1Technique(
  id: 'test_review_fix_b',
  name: 'テスト技B',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
  damage: 12,
  heatGain: 8,
  family: CombatV1TechniqueFamily.armbar,
);
const CombatV1Technique _techC = CombatV1Technique(
  id: 'test_review_fix_c',
  name: 'テスト技C',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.throwing,
  // 使用可能量を超える高cost——常にunusableな代表カード。
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 9}),
  damage: 25,
  heatGain: 20,
  family: CombatV1TechniqueFamily.slam,
);
const CombatV1Technique _techD = CombatV1Technique(
  id: 'test_review_fix_d',
  name: 'テスト技D',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.aerial,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.aerial: 1}),
  damage: 18,
  heatGain: 12,
  family: CombatV1TechniqueFamily.dropKick,
);
const CombatV1Technique _techE = CombatV1Technique(
  id: 'test_review_fix_e',
  name: 'テスト技E',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.rough,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 2}),
  damage: 40,
  heatGain: 30,
  family: CombatV1TechniqueFamily.choke,
  finisherType: CombatV1FinisherType.normal,
);

/// docs/combat_rules_v1.md 5章のアカリEnergy配分例に、5枚が使用可能な
/// 属性（`_techA`〜`_techD`分＋finisher `_techE`用のラフ）を加えた
/// テスト専用pool。`_techC`（投9）だけは意図的に不足させる。
const CombatV1EnergyPool _fiveCardPool = CombatV1EnergyPool({
  CombatV1EnergyAttribute.strike: 5,
  CombatV1EnergyAttribute.joint: 1,
  CombatV1EnergyAttribute.throwing: 2,
  CombatV1EnergyAttribute.aerial: 2,
  CombatV1EnergyAttribute.rough: 2,
  CombatV1EnergyAttribute.wild: 1,
});

List<CombatV1PlayableHandCard> _fiveCardHand({
  bool techCUsable = false,
  bool techEUsable = true,
}) => [
  testTechniqueCard(instanceId: 'a', technique: _techA, isUsable: true),
  testTechniqueCard(instanceId: 'b', technique: _techB, isUsable: true),
  testTechniqueCard(
    instanceId: 'c',
    technique: _techC,
    isUsable: techCUsable,
  ),
  testTechniqueCard(instanceId: 'd', technique: _techD, isUsable: true),
  testTechniqueCard(
    instanceId: 'e',
    technique: _techE,
    isUsable: techEUsable,
  ),
];

CombatV1PlayableHumanStatus _fiveCardHumanStatus({
  bool techCUsable = false,
  bool techEUsable = true,
}) => testHumanStatus(
  hand: _fiveCardHand(techCUsable: techCUsable, techEUsable: techEUsable),
  energyPool: _fiveCardPool,
  availableEnergy: {
    for (final attribute in CombatV1EnergyAttribute.values)
      attribute: _fiveCardPool.amountFor(attribute),
  },
);

void main() {
  group('A/B/C. Technique A→B→解除（8章）', () {
    testWidgets('Aをtap→A selected、Bをtap→B selectedへ切り替わりA解除、detail/Energyが'
        'Bへ更新される', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: _fiveCardHumanStatus(),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'b'),
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'd'),
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'e'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      final nameKey = const Key(
        'combat_v1_playable_selected_technique_name',
      );

      // Aをtap → A selected。
      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_a')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(nameKey)).data, _techA.name);
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_required_energy',
                ),
              ),
            )
            .data,
        contains('打1'),
      );

      // Bをtap → B selected（Aは解除）。
      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_b')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(nameKey)).data, _techB.name);
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_required_energy',
                ),
              ),
            )
            .data,
        contains('関1'),
      );
      // panelは1つだけ（Aの内容が残っていない）。
      expect(find.byKey(nameKey), findsOneWidget);
    });

    testWidgets('選択中のカードを再tapすると選択解除され、panelが閉じる', (tester) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: _fiveCardHumanStatus(),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      final cardFinder = find.byKey(const Key('combat_v1_playable_hand_card_a'));
      await tester.tap(cardFinder);
      await tester.pump();
      expect(
        find.byKey(const Key('combat_v1_playable_selected_technique_panel')),
        findsOneWidget,
      );

      await tester.tap(cardFinder);
      await tester.pump();
      expect(
        find.byKey(const Key('combat_v1_playable_selected_technique_panel')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('combat_v1_playable_action_technique')),
        findsNothing,
      );
    });
  });

  group('D/E. usable ⇄ unusable selection change（8章）', () {
    testWidgets('usable（A）→unusable（C）でbuttonがdisabledへ切り替わる', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: _fiveCardHumanStatus(),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      const techniqueKey = Key('combat_v1_playable_action_technique');
      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_a')));
      await tester.pump();
      expect(_isEnabled(tester, techniqueKey), isTrue);

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_c')));
      await tester.pump();
      expect(_isEnabled(tester, techniqueKey), isFalse);
    });

    testWidgets('unusable（C）→usable（A）へ切り替えると、正しいLegalActionだけ'
        'submit可能になる', (tester) async {
      final snapshot = testSnapshot(
        revision: 3,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: _fiveCardHumanStatus(),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      const techniqueKey = Key('combat_v1_playable_action_technique');

      // Cを選択 → button disabled、tapしても何も起きない。
      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_c')));
      await tester.pump();
      expect(_isEnabled(tester, techniqueKey), isFalse);

      // Aへ切り替え → button enabled。
      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_a')));
      await tester.pump();
      expect(_isEnabled(tester, techniqueKey), isTrue);

      await tester.ensureVisible(find.byKey(techniqueKey));
      await tester.tap(find.byKey(techniqueKey));
      await tester.pump();

      expect(session.submitCalls, hasLength(1));
      expect(
        session.submitCalls.single.action,
        const CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
      );
    });
  });

  group('Energy Exact Boundary（9章）', () {
    testWidgets('required Energy == available Energy: usable・button enabled・'
        '正しいLegalActionがsubmitされる', (tester) async {
      const technique = CombatV1Technique(
        id: 'test_boundary_exact',
        name: 'テスト境界技',
        category: CombatV1CardCategory.normal,
        attribute: CombatV1EnergyAttribute.strike,
        energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 3}),
        damage: 20,
        heatGain: 10,
        family: CombatV1TechniqueFamily.elbow,
      );
      final snapshot = testSnapshot(
        revision: 11,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: technique,
              isUsable: true,
            ),
          ],
          energyPool: const CombatV1EnergyPool({
            CombatV1EnergyAttribute.strike: 3,
          }),
          availableEnergy: const {CombatV1EnergyAttribute.strike: 3},
        ),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_usable_status',
                ),
              ),
            )
            .data,
        '使用可能',
      );
      expect(find.textContaining('Energy不足'), findsNothing);

      const techniqueKey = Key('combat_v1_playable_action_technique');
      expect(_isEnabled(tester, techniqueKey), isTrue);

      await tester.ensureVisible(find.byKey(techniqueKey));
      await tester.tap(find.byKey(techniqueKey));
      await tester.pump();

      expect(session.submitCalls, hasLength(1));
      expect(session.submitCalls.single.expectedRevision, 11);
      expect(
        session.submitCalls.single.action,
        const CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
      );
    });

    testWidgets('required Energy > available Energy（1超過）: unusable・Energy不足'
        '表示・button disabled・submitされない', (tester) async {
      const technique = CombatV1Technique(
        id: 'test_boundary_over',
        name: 'テスト境界超過技',
        category: CombatV1CardCategory.normal,
        attribute: CombatV1EnergyAttribute.strike,
        energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 4}),
        damage: 20,
        heatGain: 10,
        family: CombatV1TechniqueFamily.elbow,
      );
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: technique,
              isUsable: false,
            ),
          ],
          energyPool: const CombatV1EnergyPool({
            CombatV1EnergyAttribute.strike: 3,
          }),
          availableEnergy: const {CombatV1EnergyAttribute.strike: 3},
        ),
        legalActions: const [CombatV1EndTurnAction(actorPlayerIndex: 0)],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
      await tester.pump();

      // Playable 2A-6「4章 Sticky Technique Action」——同じ理由が選択中
      // panelとsticky action barの両方に現れるため`findsWidgets`
      // （1件以上）で検証する。
      expect(find.textContaining('Energy不足: 打4 / 3'), findsWidgets);

      const techniqueKey = Key('combat_v1_playable_action_technique');
      expect(_isEnabled(tester, techniqueKey), isFalse);

      await tester.ensureVisible(find.byKey(techniqueKey));
      await tester.tap(find.byKey(techniqueKey));
      await tester.pump();

      expect(session.submitCalls, isEmpty);
    });
  });

  group('Large Hand Mobile — 5枚scroll無し比較（10章）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 844);

      testWidgets(
        '${width.toInt()}px: 5枚全ての識別名・required Energy・usable/unusableが'
        'scroll前に実座標でviewport内にある',
        (tester) async {
          await _withViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              human: _fiveCardHumanStatus(),
              legalActions: const [
                CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
                CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'b'),
                CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'd'),
                CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'e'),
                CombatV1EndTurnAction(actorPlayerIndex: 0),
              ],
            );
            await tester.pumpWidget(
              _wrap(_screen(FakePlayableMatchSession(snapshot))),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            final viewportRect = tester.getRect(
              find.byKey(
                const Key('combat_v1_playable_technique_area_scroll'),
              ),
            );

            for (final entry in const [
              ('a', _techA),
              ('b', _techB),
              ('c', _techC),
              ('d', _techD),
              ('e', _techE),
            ]) {
              final (instanceId, technique) = entry;
              final cardFinder = find.byKey(
                Key('combat_v1_playable_hand_card_$instanceId'),
              );
              expect(cardFinder, findsOneWidget, reason: '$instanceIdが見つからない');
              final cardRect = tester.getRect(cardFinder);
              expect(
                cardRect.overlaps(viewportRect),
                isTrue,
                reason:
                    'カード$instanceId（${technique.name}）がscroll前に'
                    'viewport内にない: card=$cardRect, viewport=$viewportRect',
              );

              // 名前・required Energyが実際にtap targetの矩形内にある
              // ことも合わせて確認する（compact card自体の情報、3章A）。
              final nameFinder = find.descendant(
                of: cardFinder,
                matching: find.text(technique.name),
              );
              expect(nameFinder, findsOneWidget);
              expect(
                tester.getRect(nameFinder).overlaps(viewportRect),
                isTrue,
              );
            }
          }, size: size);
        },
      );

      testWidgets(
        '${width.toInt()}px: 5枚それぞれのcompact card tap targetへ実際に'
        'hit-testでき、選択状態が切り替わる',
        (tester) async {
          await _withViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              human: _fiveCardHumanStatus(),
              legalActions: const [
                CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
                CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'b'),
                CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'd'),
                CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'e'),
                CombatV1EndTurnAction(actorPlayerIndex: 0),
              ],
            );
            await tester.pumpWidget(
              _wrap(_screen(FakePlayableMatchSession(snapshot))),
            );
            await tester.pump();

            final viewportRect = tester.getRect(
              find.byKey(
                const Key('combat_v1_playable_technique_area_scroll'),
              ),
            );

            const expectedNames = {
              'a': _techA,
              'b': _techB,
              'd': _techD,
              'e': _techE,
            };
            for (final instanceId in const ['a', 'b', 'd', 'e']) {
              final cardFinder = find.byKey(
                Key('combat_v1_playable_hand_card_$instanceId'),
              );
              final cardRect = tester.getRect(cardFinder);
              final visibleRect = cardRect.intersect(viewportRect);
              expect(visibleRect.width, greaterThan(0));
              expect(visibleRect.height, greaterThan(0));
              await tester.tapAt(visibleRect.center);
              await tester.pump();
              expect(tester.takeException(), isNull);

              // 実際にtapしたcardが選択状態になり、detail panelの名前が
              // 一致することを確認する（widget存在だけで判定しない）。
              expect(
                tester
                    .widget<Text>(
                      find.byKey(
                        const Key(
                          'combat_v1_playable_selected_technique_name',
                        ),
                      ),
                    )
                    .data,
                expectedNames[instanceId]!.name,
              );
            }
          }, size: size);
        },
      );
    }
  });

  group('Playable 2A-6「1章 Discard UX」— 5枚discard handのscroll無し比較', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 844);

      testWidgets(
        '${width.toInt()}px: discard phaseの5枚全てが横scroll無しでviewport内へ'
        '届き、比較できる（15章 A/R）',
        (tester) async {
          await _withViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.discard,
              isHumanInputRequired: true,
              human: _fiveCardHumanStatus(),
              legalActions: const [
                CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
                CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'b'),
                CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'c'),
                CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'd'),
                CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'e'),
              ],
            );
            await tester.pumpWidget(
              _wrap(_screen(FakePlayableMatchSession(snapshot))),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            final viewportRect = tester.getRect(
              find.byKey(
                const Key('combat_v1_playable_technique_area_scroll'),
              ),
            );

            for (final entry in const [
              ('a', _techA),
              ('b', _techB),
              ('c', _techC),
              ('d', _techD),
              ('e', _techE),
            ]) {
              final (instanceId, technique) = entry;
              final tileFinder = find.byKey(
                Key('combat_v1_playable_discard_hand_card_$instanceId'),
              );
              expect(tileFinder, findsOneWidget, reason: '$instanceIdが見つからない');
              final tileRect = tester.getRect(tileFinder);
              expect(
                tileRect.overlaps(viewportRect),
                isTrue,
                reason:
                    'discard card$instanceId（${technique.name}）がscroll前に'
                    'viewport内にない: tile=$tileRect, viewport=$viewportRect',
              );

              final nameFinder = find.descendant(
                of: tileFinder,
                matching: find.text(technique.name),
              );
              expect(nameFinder, findsOneWidget);
              expect(tester.getRect(nameFinder).overlaps(viewportRect), isTrue);
            }

            // discard phaseでは横scroll cue自体が存在しない（Playable
            // 2A-6でTechnique modeと同じWrap表示へ揃えたため）。
            expect(
              find.byKey(const Key('combat_v1_playable_hand_scroll_hint')),
              findsNothing,
            );
          }, size: size);
        },
      );
    }

    testWidgets('discard: Aをtap→選択、Bをtap→Bへ切り替わりAは解除、同じBを再tapで解除', (
      tester,
    ) async {
      final snapshot = testSnapshot(
        phase: CombatV1MatchPhase.discard,
        isHumanInputRequired: true,
        human: _fiveCardHumanStatus(),
        legalActions: const [
          CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
          CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'b'),
        ],
      );
      await tester.pumpWidget(
        _wrap(_screen(FakePlayableMatchSession(snapshot))),
      );
      await tester.pump();

      final nameKey = const Key('combat_v1_playable_discard_selected_card_name');

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_a')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(nameKey)).data, _techA.name);

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_b')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(nameKey)).data, _techB.name);
      expect(find.byKey(nameKey), findsOneWidget);

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_b')));
      await tester.pump();
      expect(
        find.byKey(const Key('combat_v1_playable_discard_confirm_panel')),
        findsNothing,
      );
    });

    testWidgets(
      'discard tileをtapすると「捨てるカードの詳細」にcategory/DMG/Energy/'
      'traits/postureが表示される（15章 C）',
      (tester) async {
        // 「捨てるカードの詳細」がposture行（required/result）も表示する
        // ことを検証するため、両方を持つtest技を専用に用意する
        // （`_techA`〜`_techE`はいずれもposture未設定のため）。
        const techWithPosture = CombatV1Technique(
          id: 'test_review_fix_posture',
          name: 'テスト技（posture付き）',
          category: CombatV1CardCategory.finisher,
          attribute: CombatV1EnergyAttribute.rough,
          energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 2}),
          damage: 40,
          heatGain: 30,
          family: CombatV1TechniqueFamily.choke,
          finisherType: CombatV1FinisherType.normal,
          requiredOpponentState: CombatV1WrestlerPosture.stand,
          resultOpponentState: CombatV1WrestlerPosture.down,
        );
        final snapshot = testSnapshot(
          phase: CombatV1MatchPhase.discard,
          isHumanInputRequired: true,
          sharedHeat: 0,
          finisherHeatThreshold: 200,
          human: testHumanStatus(
            hand: [
              testTechniqueCard(instanceId: 'h1', technique: techWithPosture),
            ],
          ),
          legalActions: const [
            CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          ],
        );
        await tester.pumpWidget(
          _wrap(_screen(FakePlayableMatchSession(snapshot))),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_h1')));
        await tester.pump();

        final detailFinder = find.byKey(
          const Key('combat_v1_playable_discard_card_detail'),
        );
        expect(detailFinder, findsOneWidget);
        expect(find.text('捨てるカードの詳細'), findsOneWidget);
        // category。
        expect(
          find.descendant(
            of: detailFinder,
            matching: find.text('FINISHER'),
          ),
          findsWidgets,
        );
        // DMG/HEAT行（`_TechniqueFactsBlock`）。
        expect(
          find.descendant(
            of: detailFinder,
            matching: find.textContaining('DMG ${techWithPosture.damage}'),
          ),
          findsOneWidget,
        );
        // Energy（cost）。
        expect(
          find.descendant(
            of: detailFinder,
            matching: find.byKey(
              const Key('combat_v1_playable_discard_card_energy_cost_line'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: detailFinder,
            matching: find.textContaining('ラフ2'),
          ),
          findsOneWidget,
        );
        // trait badge（FINISHERはnormal typeなので"FINISHER"合成badge）。
        expect(
          find.descendant(
            of: detailFinder,
            matching: find.byKey(
              const Key('combat_v1_playable_card_finisher_resolution_badge'),
            ),
          ),
          findsOneWidget,
        );
        // posture（required/result両方）。
        expect(
          find.descendant(
            of: detailFinder,
            matching: find.byKey(
              const Key('combat_v1_playable_card_required_posture'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: detailFinder,
            matching: find.byKey(
              const Key('combat_v1_playable_card_result_posture'),
            ),
          ),
          findsOneWidget,
        );
        // 属性full-word label（Playable 2A-6「5章」）。
        expect(
          find.descendant(
            of: detailFinder,
            matching: find.byKey(
              const Key('combat_v1_playable_technique_attribute_full_label'),
            ),
          ),
          findsOneWidget,
        );
        // 「技を使う」style buttonはここには出さない。
        expect(
          find.byKey(const Key('combat_v1_playable_action_technique')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('combat_v1_playable_action_discard')),
          findsOneWidget,
        );
      },
    );
  });

  group('Selected Detail Reachability（11章）', () {
    for (final width in [320.0, 360.0, 390.0]) {
      final size = Size(width, 780);

      testWidgets(
        '${width.toInt()}px: compact cardをtapした後、選択detail（name/DMG/HEAT/'
        'Energy/traits/unusable reason）へ縦scroll込みで到達でき、'
        '技を使うbuttonはscroll不要で最初から到達できる（Playable 2A-6「4章」）',
        (tester) async {
          await _withViewport(tester, () async {
            final snapshot = testSnapshot(
              phase: CombatV1MatchPhase.action,
              isHumanInputRequired: true,
              sharedHeat: 0,
              finisherHeatThreshold: 200,
              human: testHumanStatus(
                hand: [
                  testTechniqueCard(
                    instanceId: 'h1',
                    technique: _techE,
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

            final cardFinder = find.byKey(
              const Key('combat_v1_playable_hand_card_h1'),
            );
            await tester.ensureVisible(cardFinder);
            await tester.pumpAndSettle();
            await tester.tap(cardFinder);
            await tester.pump();

            final scrollAreaFinder = find.byKey(
              const Key('combat_v1_playable_technique_area_scroll'),
            );
            final scrollableFinder = find
                .descendant(
                  of: scrollAreaFinder,
                  matching: find.byType(Scrollable),
                )
                .first;

            Future<void> expectReachable(Finder finder, String label) async {
              expect(finder, findsOneWidget, reason: '$labelが見つからない');
              var viewportRect = tester.getRect(scrollAreaFinder);
              var rect = tester.getRect(finder);
              if (!rect.overlaps(viewportRect)) {
                await tester.scrollUntilVisible(
                  finder,
                  50,
                  scrollable: scrollableFinder,
                );
                await tester.pumpAndSettle();
                viewportRect = tester.getRect(scrollAreaFinder);
                rect = tester.getRect(finder);
              }
              expect(
                rect.overlaps(viewportRect),
                isTrue,
                reason: '$labelへ到達できない: rect=$rect, viewport=$viewportRect',
              );
            }

            final panelFinder = find.byKey(
              const Key('combat_v1_playable_selected_technique_panel'),
            );
            expect(panelFinder, findsOneWidget);

            await expectReachable(
              find.byKey(
                const Key('combat_v1_playable_selected_technique_name'),
              ),
              'Technique name',
            );
            await expectReachable(
              find.descendant(
                of: panelFinder,
                matching: find.textContaining('DMG ${_techE.damage}'),
              ),
              'DMG/HEAT line',
            );
            await expectReachable(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_required_energy',
                ),
              ),
              '必要Energy',
            );
            await expectReachable(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_current_energy',
                ),
              ),
              '現在Energy',
            );
            await expectReachable(
              find.byKey(
                const Key('combat_v1_playable_card_finisher_resolution_badge'),
              ),
              'FINISHER trait badge',
            );
            await expectReachable(
              find.byKey(
                const Key(
                  'combat_v1_playable_selected_technique_usable_status',
                ),
              ),
              'unusable reason',
            );

            // Playable 2A-6「4章 Sticky Technique Action」——
            // 「技を使う」button自体はもう`_SelectedTechniquePanel`
            // （scrollする詳細領域）の中には無く、`_TechniqueStickyActionBar`
            // （scroll領域の外側、常時固定表示）へ移動した。ここまで
            // 一切scrollしていない時点（`expectReachable`が内部で
            // scrollした可能性はあるが、button自体はそのscroll位置に
            // 依存せず常に画面内にあるはず）で、button自体が実座標で
            // hit-testableであることを確認する。
            final buttonFinder = find.byKey(
              const Key('combat_v1_playable_action_technique'),
            );
            expect(buttonFinder, findsOneWidget);
            final screenRect =
                Offset.zero &
                (tester.view.physicalSize / tester.view.devicePixelRatio);
            final buttonRect = tester.getRect(buttonFinder);
            final visibleButtonRect = buttonRect.intersect(screenRect);
            expect(
              visibleButtonRect.width,
              greaterThan(0),
              reason: '技を使うbuttonがscroll無しでviewport内にない: rect=$buttonRect',
            );
            expect(visibleButtonRect.height, greaterThan(0));
          }, size: size);
        },
      );
    }
  });

  group('Compact Hand → Detail → 技を使う（12章 Action Hit-Test）', () {
    testWidgets('compact Technique Bをtap→selected detail=B→技を使うtap→'
        'submitted LegalAction==B', (tester) async {
      final snapshot = testSnapshot(
        revision: 21,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        human: _fiveCardHumanStatus(),
        legalActions: const [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a'),
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'b'),
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'd'),
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'e'),
          CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );
      final session = FakePlayableMatchSession(snapshot);
      await tester.pumpWidget(_wrap(_screen(session)));
      await tester.pump();

      await tester.tap(find.byKey(const Key('combat_v1_playable_hand_card_b')));
      await tester.pump();

      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('combat_v1_playable_selected_technique_name'),
              ),
            )
            .data,
        _techB.name,
      );

      final techniqueButton = find.byKey(
        const Key('combat_v1_playable_action_technique'),
      );
      await tester.ensureVisible(techniqueButton);
      await tester.tap(techniqueButton);
      await tester.pump();

      expect(session.submitCalls, hasLength(1));
      expect(session.submitCalls.single.expectedRevision, 21);
      expect(
        session.submitCalls.single.action,
        const CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'b'),
      );
    });
  });

  group(
    'Playable 2A-6 Review Findings Fix（Critical、4.2章）— '
    '低height viewportでの技action bar到達可能性',
    () {
      // レビュー指摘の再現条件: Shared HEATがFINISHER閾値へ到達すると
      // `_MatchGuidancePanel`へ「FINISHER HEAT到達」の行が追加され
      // （`combat_v1_playable_match_guidance.dart`）、かつユーザーが
      // 「▼ 試合の詳細」（`_ActorAndRecentPanel._detailExpanded`）を
      // 展開すると、固定表示のはずの技action bar
      // （`_TechniqueStickyActionBar`）が320×568のような低height
      // viewportでは`_PrimaryActionsBar`（ターン終了等）と重なる
      // RenderFlex overflowを起こしていた（Root cause: 両者を同居させて
      // いた内側`Column`の高さ予算が、外側`Expanded`の縮小によって
      // 技action bar自身の必要高さを下回っていたため）。
      CombatV1PlayableMatchSnapshot finisherThresholdSnapshot({
        required bool cardUsable,
      }) => testSnapshot(
        revision: 42,
        phase: CombatV1MatchPhase.action,
        isHumanInputRequired: true,
        sharedHeat: 250,
        finisherHeatThreshold: 200,
        human: testHumanStatus(
          hand: [
            testTechniqueCard(
              instanceId: 'h1',
              technique: testNormalTechnique,
              isUsable: cardUsable,
            ),
          ],
        ),
        legalActions: [
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
          const CombatV1EndTurnAction(actorPlayerIndex: 0),
        ],
      );

      Future<void> selectCardAndExpandDetail(WidgetTester tester) async {
        final cardFinder = find.byKey(
          const Key('combat_v1_playable_hand_card_h1'),
        );
        await tester.ensureVisible(cardFinder);
        await tester.pumpAndSettle();
        await tester.tap(cardFinder);
        await tester.pump();

        final toggleFinder = find.byKey(
          const Key('combat_v1_playable_detail_toggle'),
        );
        await tester.ensureVisible(toggleFinder);
        await tester.pumpAndSettle();
        await tester.tap(toggleFinder);
        await tester.pump();
      }

      testWidgets(
        'reviewer repro: 320×568・FINISHER HEAT到達・詳細展開・カード選択済み'
        'の状態でRenderFlex overflowが起きず、技action barがEnd Turnと'
        '重ならず、実tapが技action bar自体へ届く',
        (tester) async {
          await _withViewport(
            tester,
            () async {
              final snapshot = finisherThresholdSnapshot(cardUsable: true);
              final session = FakePlayableMatchSession(snapshot);
              await tester.pumpWidget(_wrap(_screen(session)));
              await tester.pump();

              await selectCardAndExpandDetail(tester);

              // (a) overflow例外が一切発生していないこと。
              expect(tester.takeException(), isNull);

              final techniqueFinder = find.byKey(
                const Key('combat_v1_playable_action_technique'),
              );
              final endTurnFinder = find.byKey(
                const Key('combat_v1_playable_action_end_turn'),
              );
              expect(techniqueFinder, findsOneWidget);
              expect(endTurnFinder, findsOneWidget);

              final techniqueRect = tester.getRect(techniqueFinder);
              final endTurnRect = tester.getRect(endTurnFinder);

              // (b) 技action barの矩形がEnd Turn buttonの矩形と重ならない
              // こと（誤tap hazardの直接的な検証）。
              expect(
                techniqueRect.overlaps(endTurnRect),
                isFalse,
                reason:
                    '技action bar($techniqueRect)がEnd Turn'
                    'button($endTurnRect)と重なっている',
              );

              // (c) 実際にtechnique button中心をtapすると、正しく
              // technique buttonがhitし、End Turnではなく正しい
              // LegalActionがsubmitされること（hit-test警告が出ない
              // ことも含めて検証——warnIfMissedは既定でtrueのため、
              // ここで実際に外れているとFlutter test frameworkの
              // warningとして検出される）。
              await tester.tap(techniqueFinder);
              await tester.pump();

              expect(session.submitCalls, hasLength(1));
              expect(session.submitCalls.single.expectedRevision, 42);
              expect(
                session.submitCalls.single.action,
                const CombatV1TechniqueAction(
                  actorPlayerIndex: 0,
                  cardInstanceId: 'h1',
                ),
              );
            },
            size: const Size(320, 568),
          );
        },
      );

      // 一般化した低height viewport sweep — 320×568以外の短い高さでも
      // 同じ誘発条件（FINISHER HEAT到達＋詳細展開）でoverflow/重なりが
      // 起きないことを確認する。
      for (final size in const [
        Size(320, 568),
        Size(360, 600),
        Size(390, 640),
      ]) {
        testWidgets(
          '${size.width.toInt()}x${size.height.toInt()}: FINISHER HEAT到達＋'
          '詳細展開でも技action barが overflow/End Turnとの重なりを起こさない',
          (tester) async {
            await _withViewport(
              tester,
              () async {
                final snapshot = finisherThresholdSnapshot(cardUsable: false);
                await tester.pumpWidget(
                  _wrap(_screen(FakePlayableMatchSession(snapshot))),
                );
                await tester.pump();

                await selectCardAndExpandDetail(tester);

                expect(tester.takeException(), isNull);

                final techniqueFinder = find.byKey(
                  const Key('combat_v1_playable_action_technique'),
                );
                final endTurnFinder = find.byKey(
                  const Key('combat_v1_playable_action_end_turn'),
                );
                expect(techniqueFinder, findsOneWidget);
                expect(endTurnFinder, findsOneWidget);

                expect(
                  tester
                      .getRect(techniqueFinder)
                      .overlaps(tester.getRect(endTurnFinder)),
                  isFalse,
                );
              },
              size: size,
            );
          },
        );
      }
    },
  );
}
