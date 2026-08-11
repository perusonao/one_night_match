// Balance Dashboard 1A: widget test
// （lib/src/combat_v1/dashboard/combat_v1_balance_dashboard_screen.dart）。
//
// docs/design/combat_v1_balance_dashboard_1a.md 16章「Test Strategy」の
// widget test要件を検証する。`runFunction`を常にfakeへ差し替え、1,600
// real simulationは実行しない（25章「Test Injection」）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_dashboard_screen.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_dashboard_view_model.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_simulation_service.dart';

import 'combat_v1_balance_dashboard_test_fixtures.dart';

CombatV1BalanceRunOutput _syntheticOutput() => CombatV1BalanceRunOutput(
  viewModel: CombatV1BalanceDashboardViewModel.fromResult(
    combatV1DashboardTestResult(),
  ),
  runtime: const Duration(milliseconds: 1234),
  ranAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
);

/// 即座にsynthetic outputを返すfake run function。
Future<CombatV1BalanceRunOutput> _fakeRunImmediate() async => _syntheticOutput();

/// [completer]が完了するまで待つfake run function
/// （running state中のUIを確認するために使う）。
Future<CombatV1BalanceRunOutput> Function() _fakeRunPending(
  Completer<CombatV1BalanceRunOutput> completer,
) => () => completer.future;

/// 常にthrowするfake run function（error stateを確認するために使う）。
Future<CombatV1BalanceRunOutput> _fakeRunFailure() async {
  throw StateError('synthetic simulation failure');
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('Idle state', () {
    testWidgets('title・config summary・Runボタンを表示する', (tester) async {
      await tester.pumpWidget(
        _wrap(CombatV1BalanceDashboardScreen(runFunction: _fakeRunImmediate)),
      );

      expect(find.text('Combat V1 Balance Dashboard'), findsOneWidget);
      expect(find.textContaining('Default Run 設定'), findsOneWidget);
      expect(find.textContaining('4 wrestlers'), findsOneWidget);
      expect(find.textContaining('1600 total matches'), findsOneWidget);
      expect(find.textContaining('Seed 12345'), findsOneWidget);
      expect(find.text('Run Default Simulation'), findsOneWidget);
      // idle時点ではまだ結果sectionが出ていない。
      expect(find.text('Summary'), findsNothing);
    });
  });

  group('Running state', () {
    testWidgets('buttonがdisabledになり、progress表示・running textが出る', (
      tester,
    ) async {
      final completer = Completer<CombatV1BalanceRunOutput>();
      await tester.pumpWidget(
        _wrap(
          CombatV1BalanceDashboardScreen(runFunction: _fakeRunPending(completer)),
        ),
      );

      await tester.tap(find.text('Run Default Simulation'));
      // frame yield（endOfFrame）1回分 + setStateの反映をpumpする。
      await tester.pump();
      await tester.pump();

      expect(find.text('実行中…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Running 1,600 simulations…'), findsOneWidget);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      completer.complete(_syntheticOutput());
      await tester.pumpAndSettle();
    });
  });

  group('Success state', () {
    testWidgets(
      'summary・4 wrestler rows・4×4 matrix・seat・mirror・lengthを表示する',
      (tester) async {
        await tester.pumpWidget(
          _wrap(CombatV1BalanceDashboardScreen(runFunction: _fakeRunImmediate)),
        );

        await tester.tap(find.text('Run Default Simulation'));
        await tester.pumpAndSettle();

        expect(find.text('Summary'), findsOneWidget);
        expect(find.text('Total Matches'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        // 以下のlabelはSummary card・wrestler table・mirror/seat panelなど
        // 複数箇所に意図的に再掲される（各panelで分母/文脈が異なるため）。
        expect(find.text('Player A Win Rate'), findsWidgets);
        expect(find.text('Player B Win Rate'), findsWidgets);
        expect(find.text('Safety Limit Rate'), findsWidgets);
        expect(find.text('Invariant Violation Rate'), findsWidgets);

        // 4 wrestler rows（displayName）。
        expect(find.text('豪田ミサキ'), findsWidgets);
        expect(find.text('黒蝶ジャック'), findsWidgets);
        expect(find.text('火神アカリ'), findsWidgets);
        expect(find.text('白銀レイナ'), findsWidgets);

        // 4×4 matrix（DataTableも内部でTableを使うため、専用Keyで特定する）。
        expect(find.text('Matchup Matrix'), findsOneWidget);
        final matrixFinder = find.byKey(
          const Key('combat_v1_balance_dashboard_matrix_table'),
        );
        expect(matrixFinder, findsOneWidget);
        final table = tester.widget<Table>(matrixFinder);
        expect(table.children, hasLength(5)); // header row + 4 wrestler rows

        // seat / mirror / length panel。
        expect(find.text('Player A / B'), findsOneWidget);
        expect(find.text('Mirror Matches'), findsOneWidget);
        expect(find.text('Match Length'), findsOneWidget);
        expect(find.text('Actions'), findsOneWidget);
        expect(find.text('Final Turn'), findsOneWidget);

        // Run metadata。
        expect(find.textContaining('ms'), findsWidgets);
      },
    );

    testWidgets('null値は—表示になる（reinaのwin rate）', (tester) async {
      await tester.pumpWidget(
        _wrap(CombatV1BalanceDashboardScreen(runFunction: _fakeRunImmediate)),
      );

      await tester.tap(find.text('Run Default Simulation'));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
    });
  });

  group('Error state', () {
    testWidgets('persistentなerror panelを表示する', (tester) async {
      await tester.pumpWidget(
        _wrap(CombatV1BalanceDashboardScreen(runFunction: _fakeRunFailure)),
      );

      await tester.tap(find.text('Run Default Simulation'));
      await tester.pumpAndSettle();

      expect(find.text('Simulation failed'), findsOneWidget);
      expect(find.textContaining('synthetic simulation failure'), findsOneWidget);

      // errorになってもbuttonは再度押せる状態へ戻る（再run可能）。
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });
  });

  group('Responsive smoke', () {
    testWidgets('狭幅画面でoverflow exceptionが出ない', (tester) async {
      final originalSize = tester.view.physicalSize;
      final originalRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalRatio;
      });

      await tester.pumpWidget(
        _wrap(CombatV1BalanceDashboardScreen(runFunction: _fakeRunImmediate)),
      );
      await tester.tap(find.text('Run Default Simulation'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
