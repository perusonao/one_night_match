// Balance Dashboard 1B: widget test
// （lib/src/combat_v1/dashboard/combat_v1_balance_dashboard_screen.dart）。
//
// docs/design/combat_v1_balance_dashboard_1b.md「Test — Stale Result /
// Reentrancy / Last Run Metadata / Matchup Detail / Mobile Detail /
// Analysis Confirm」（60〜65章）を検証する。`runFunction`を常にfakeへ
// 差し替え、16,000等の大規模real simulationは実行しない（66章「Test
// Injection」）。
//
// pumpWidgetの前に、テストのsurface heightを十分大きく取る
// （[_pumpDashboard]）——`ListView`のchild virtualization（viewport +
// cache extent外のwidgetはElement化されない）により、default 800×600の
// test surfaceではconfig cardより下のwidget（Run button・result
// sections等）がbuildされず`find`が届かないため。widthのみ狭めて
// mobile幅（320px）のresponsive/overflow挙動を検証する。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_dashboard_screen.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_dashboard_view_model.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_simulation_service.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';

import 'combat_v1_balance_dashboard_test_fixtures.dart';

/// run functionへ渡されたconfigを記録しつつ、その値を反映したsynthetic
/// outputを返すfake。「last run metadataがdraft configではなく実際に
/// 渡されたconfigを表示する」ことを確認するために使う。
class _RunRecorder {
  final calls = <CombatV1BatchSimulationConfig>[];

  Future<CombatV1BalanceRunOutput> runImmediate(
    CombatV1BatchSimulationConfig config,
  ) async {
    calls.add(config);
    return CombatV1BalanceRunOutput(
      viewModel: CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(config: config),
      ),
      runtime: const Duration(milliseconds: 1234),
      ranAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
  }

  Future<CombatV1BalanceRunOutput> Function(CombatV1BatchSimulationConfig)
  pending(Completer<CombatV1BalanceRunOutput> completer) => (config) {
    calls.add(config);
    return completer.future;
  };
}

Future<CombatV1BalanceRunOutput> _fakeRunFailure(
  CombatV1BatchSimulationConfig config,
) async {
  throw StateError('synthetic simulation failure');
}

const double _mobileWidth = 320;
const double _desktopWidth = 800;
// ListView virtualization対策——page全体（config card + result
// sections）がbuild範囲に収まるよう十分な高さを確保する。
const double _tallSurfaceHeight = 6000;

/// surfaceを設定した上でDashboard画面をpumpする共通helper。
Future<void> _pumpDashboard(
  WidgetTester tester, {
  required CombatV1BalanceRunFunction runFunction,
  double width = _desktopWidth,
}) async {
  tester.view.physicalSize = Size(width, _tallSurfaceHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(home: CombatV1BalanceDashboardScreen(runFunction: runFunction)),
  );
}

void main() {
  group('Idle state', () {
    testWidgets('title・config card（editable）・total matches・Runボタンを表示する', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      expect(find.text('Combat V1 Balance Dashboard'), findsOneWidget);
      expect(find.textContaining('Simulation Config'), findsOneWidget);
      expect(find.textContaining('4 wrestlers'), findsOneWidget);
      // default draft: Quick(100) → 16 × 100 = 1600。
      expect(find.textContaining('1600 total matches'), findsOneWidget);
      expect(find.text('Run Simulation'), findsOneWidget);
      // idle時点ではまだ結果sectionが出ていない。
      expect(find.text('Summary'), findsNothing);
      // runはまだ一度も呼ばれていない（No Auto Run、53章）。
      expect(recorder.calls, isEmpty);
    });

    testWidgets('preset chip・policy dropdown・advanced（max actions）が存在する', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_smoke')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_quick')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_analysis')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_custom')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_player_a_policy_field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_player_b_policy_field')),
        findsOneWidget,
      );
      expect(find.text('Advanced'), findsOneWidget);
      // Advanced（max actions）は展開するまでfield自体は存在しない。
      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_max_actions_field')),
        findsNothing,
      );
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_max_actions_field')),
        findsOneWidget,
      );
    });
  });

  group('Config editing — presets（59章「Test — Config」）', () {
    testWidgets('Smoke presetへ切り替えるとtotal matchesが320になる', (tester) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_smoke')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('320 total matches'), findsOneWidget);
    });

    testWidgets('Analysis presetへ切り替えるとtotal matchesが16000でperformance warning', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_analysis')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('16000 total matches'), findsOneWidget);
      expect(
        find.text('Large runs may temporarily freeze the browser.'),
        findsOneWidget,
      );
    });

    testWidgets('Customへ切り替えるとcustom fieldが出現し、valid値でtotalが更新される', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_custom')),
      );
      await tester.pumpAndSettle();

      final customField = find.byKey(
        const Key('combat_v1_balance_dashboard_custom_matches_field'),
      );
      expect(customField, findsOneWidget);

      await tester.enterText(customField, '250');
      await tester.pumpAndSettle();

      expect(find.textContaining('4000 total matches'), findsOneWidget);
    });

    testWidgets('custom invalid（0）はerror textを表示し、Runボタンをdisabledにする', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_custom')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('combat_v1_balance_dashboard_custom_matches_field')),
        '0',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Must be between 1 and 1000'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('combat_v1_balance_dashboard_run_button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('custom invalid（1001）はhard maxを超えてerror', (tester) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_custom')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('combat_v1_balance_dashboard_custom_matches_field')),
        '1001',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Must be between 1 and 1000'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('combat_v1_balance_dashboard_run_button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('invalid seed（空欄）はRunボタンをdisabledにし、error textがpersistentに見える', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.enterText(
        find.byKey(const Key('combat_v1_balance_dashboard_seed_field')),
        '',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Seed cannot be blank'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('combat_v1_balance_dashboard_run_button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('invalid maxActions（0）はRunボタンをdisabledにする', (tester) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('combat_v1_balance_dashboard_max_actions_field')),
        '0',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Must be at least 1'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('combat_v1_balance_dashboard_run_button')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('Running state / Reentrancy（18・61章）', () {
    testWidgets('buttonがdisabledになり、config controlsもdisabledになる', (tester) async {
      final recorder = _RunRecorder();
      final completer = Completer<CombatV1BalanceRunOutput>();
      await _pumpDashboard(tester, runFunction: recorder.pending(completer));

      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      // frame yield（endOfFrame）1回分 + setStateの反映をpumpする。
      await tester.pump();
      await tester.pump();

      expect(find.text('実行中…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Running 1,600 simulations…'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('combat_v1_balance_dashboard_run_button')),
      );
      expect(button.onPressed, isNull);

      final seedField = tester.widget<TextField>(
        find.byKey(const Key('combat_v1_balance_dashboard_seed_field')),
      );
      expect(seedField.enabled, isFalse);

      final policyA = tester.widget<DropdownButtonFormField<Object?>>(
        find.byKey(const Key('combat_v1_balance_dashboard_player_a_policy_field')),
      );
      expect(policyA.onChanged, isNull);

      final presetChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_smoke')),
      );
      expect(presetChip.onSelected, isNull);

      // 二重run禁止（duplicate runなし）——running中に再度tapしても
      // runFunctionは1回しか呼ばれない。
      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pump();
      expect(recorder.calls, hasLength(1));

      completer.complete(await recorder.runImmediate(recorder.calls.single));
      await tester.pumpAndSettle();
    });

    testWidgets('runningになるとAdvanced内のmax actions fieldもdisabledになる', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      final completer = Completer<CombatV1BalanceRunOutput>();
      await _pumpDashboard(tester, runFunction: recorder.pending(completer));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pump();
      await tester.pump();

      final maxActionsField = tester.widget<TextField>(
        find.byKey(const Key('combat_v1_balance_dashboard_max_actions_field')),
      );
      expect(maxActionsField.enabled, isFalse);

      completer.complete(await recorder.runImmediate(recorder.calls.single));
      await tester.pumpAndSettle();
    });
  });

  group('Success state', () {
    testWidgets(
      'summary・4 wrestler rows・4×4 matrix・seat・mirror・lengthを表示する',
      (tester) async {
        final recorder = _RunRecorder();
        await _pumpDashboard(tester, runFunction: recorder.runImmediate);

        await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
        await tester.pumpAndSettle();

        expect(find.text('Summary'), findsOneWidget);
        expect(find.text('Total Matches'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('Player A Win Rate'), findsWidgets);
        expect(find.text('Player B Win Rate'), findsWidgets);
        expect(find.text('Safety Limit Rate'), findsWidgets);
        expect(find.text('Invariant Violation Rate'), findsWidgets);

        expect(find.text('豪田ミサキ'), findsWidgets);
        expect(find.text('黒蝶ジャック'), findsWidgets);
        expect(find.text('火神アカリ'), findsWidgets);
        expect(find.text('白銀レイナ'), findsWidgets);

        expect(find.text('Matchup Matrix'), findsOneWidget);
        final matrixFinder = find.byKey(
          const Key('combat_v1_balance_dashboard_matrix_table'),
        );
        expect(matrixFinder, findsOneWidget);
        final table = tester.widget<Table>(matrixFinder);
        expect(table.children, hasLength(5)); // header row + 4 wrestler rows

        expect(find.text('Player A / B'), findsOneWidget);
        expect(find.text('Mirror Matches'), findsOneWidget);
        expect(find.text('Match Length'), findsOneWidget);
        expect(find.text('Actions'), findsWidgets);
        expect(find.text('Final Turn'), findsWidgets);

        expect(find.textContaining('ms'), findsWidgets);
      },
    );

    testWidgets('null値は—表示になる（reinaのwin rate）', (tester) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
    });
  });

  group('Error state', () {
    testWidgets('persistentなerror panelを表示し、既存resultがあれば保持する', (tester) async {
      final recorder = _RunRecorder();
      var useFailure = false;
      Future<CombatV1BalanceRunOutput> runFn(
        CombatV1BatchSimulationConfig config,
      ) => useFailure ? _fakeRunFailure(config) : recorder.runImmediate(config);

      await _pumpDashboard(tester, runFunction: runFn);

      // 1回目: 成功させてresultを表示させる。
      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();
      expect(find.text('Summary'), findsOneWidget);

      // 2回目: 失敗させる。
      useFailure = true;
      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      expect(find.text('Simulation failed'), findsOneWidget);
      expect(find.textContaining('synthetic simulation failure'), findsOneWidget);
      // 既存の成功resultは保持される（43章「Error」）。
      expect(find.text('Summary'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('combat_v1_balance_dashboard_run_button')),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('Stale Result UX（60章「Test — Stale Result」）', () {
    testWidgets('run成功後にconfigを変更するとstale indicatorが出て、再runで消える', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      expect(find.text('Run Simulation'), findsOneWidget);
      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_stale_banner')),
        findsNothing,
      );
      expect(find.text('Run Again'), findsOneWidget);

      // draft configを変更（Smoke presetへ）。
      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_smoke')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_stale_banner')),
        findsOneWidget,
      );
      expect(
        find.text('Settings changed — run again to refresh results.'),
        findsOneWidget,
      );
      expect(find.text('Run Updated Simulation'), findsOneWidget);

      // 再runするとstale indicatorが消える。
      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_stale_banner')),
        findsNothing,
      );
      expect(find.text('Run Again'), findsOneWidget);
    });
  });

  group('Last Run Metadata（62章「Test — Last Run Metadata」）', () {
    testWidgets('run後にdraft seedを変更しても、metadataはrun時点のseedを表示する', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      expect(find.text('12345'), findsWidgets); // metadata + draft field双方。

      await tester.enterText(
        find.byKey(const Key('combat_v1_balance_dashboard_seed_field')),
        '999',
      );
      await tester.pumpAndSettle();

      // run metadata panel（'Seed'ラベルの隣）は依然12345のまま
      // （lastRunConfigのsnapshotを表示、draftではない）。
      final seedRow = find.ancestor(
        of: find.text('Seed'),
        matching: find.byType(Row),
      );
      expect(find.descendant(of: seedRow, matching: find.text('12345')), findsOneWidget);
      expect(find.descendant(of: seedRow, matching: find.text('999')), findsNothing);
      expect(recorder.calls.single.masterSeed, 12345);
    });
  });

  group('Matchup Detail（24〜27・63章「Test — Matchup Detail」）', () {
    testWidgets('desktop幅でcellをtapするとinline detail panelに詳細が出る', (tester) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      // 選択前はplaceholderのみ。
      expect(find.textContaining('tap a matrix cell'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_matrix_cell_misaki_jack')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('tap a matrix cell'), findsNothing);
      expect(find.text('豪田ミサキ vs 黒蝶ジャック'), findsOneWidget);
      expect(find.text('Terminal Causes'), findsOneWidget);
      expect(find.text('Normal PIN'), findsOneWidget);
      expect(find.text('Direct PIN'), findsOneWidget);
      expect(find.text('Submission'), findsOneWidget);
      expect(find.text('Submission Finisher'), findsOneWidget);

      // 別cellをtapすると詳細が切り替わる。
      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_matrix_cell_akari_akari')),
      );
      await tester.pumpAndSettle();
      expect(find.text('火神アカリ vs 火神アカリ'), findsOneWidget);
    });

    testWidgets('run成功後にrunし直しても同じmatchup keyのselectionが維持される', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_matrix_cell_misaki_jack')),
      );
      await tester.pumpAndSettle();
      expect(find.text('豪田ミサキ vs 黒蝶ジャック'), findsOneWidget);

      // 再run（wrestler setはcanonical固定のため同じmatchup keyが存在する）。
      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      expect(find.text('豪田ミサキ vs 黒蝶ジャック'), findsOneWidget);
    });
  });

  group('Mobile（45〜47・64章「Test — Mobile Detail」）', () {
    testWidgets('320pxでoverflowなし、matrixはhorizontal scroll、bottom sheetでdetail表示', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(
        tester,
        runFunction: recorder.runImmediate,
        width: _mobileWidth,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // matrixはSingleChildScrollView(horizontal)でラップされている。
      expect(
        find.ancestor(
          of: find.byKey(const Key('combat_v1_balance_dashboard_matrix_table')),
          matching: find.byWidgetPredicate(
            (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
          ),
        ),
        findsOneWidget,
      );

      // mobile幅ではinline detail panelを描画しない。
      expect(
        find.byKey(const Key('combat_v1_balance_dashboard_matchup_detail_panel')),
        findsNothing,
      );

      // 320px幅では最初の列（misaki vs misaki、row header直後）のみが
      // scroll無しで画面内に収まるため、mirror cellをtapする。
      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_matrix_cell_misaki_misaki')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // bottom sheetとしてdetailが表示される。
      expect(find.text('豪田ミサキ vs 豪田ミサキ'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);

      // bottom sheetを閉じる（barrierをtap）。
      await tester.tapAt(const Offset(160, 50));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Analysis Confirmation（21・65章「Test — Analysis Confirm」）', () {
    testWidgets('Analysis presetでRunすると確認dialogが出て、Cancelするとrunnerは未実行', (
      tester,
    ) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_analysis')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      expect(find.text('Large Simulation'), findsOneWidget);
      expect(find.textContaining('simulations will run'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Large Simulation'), findsNothing);
      expect(recorder.calls, isEmpty);
      // idle状態のまま——resultは表示されない。
      expect(find.text('Summary'), findsNothing);
    });

    testWidgets('確認dialogでRunを選ぶとrunnerが実行される', (tester) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(tester, runFunction: recorder.runImmediate);

      await tester.tap(
        find.byKey(const Key('combat_v1_balance_dashboard_preset_analysis')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(recorder.calls, hasLength(1));
      expect(recorder.calls.single.matchesPerMatchup, 1000);
      expect(find.text('Summary'), findsOneWidget);
    });
  });

  group('Responsive smoke', () {
    testWidgets('狭幅画面でoverflow exceptionが出ない', (tester) async {
      final recorder = _RunRecorder();
      await _pumpDashboard(
        tester,
        runFunction: recorder.runImmediate,
        width: _mobileWidth,
      );
      await tester.tap(find.byKey(const Key('combat_v1_balance_dashboard_run_button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
