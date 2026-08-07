import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_cpu_presentation_timing.dart';

/// Phase 8.5A-2 ⑪: CPU演出速度の倍率計算と、CPUの意思決定/シミュレーション層
/// から演出タイミングが完全に切り離されていることのテスト。
void main() {
  group('TechniqueCpuPresentationSpeed.scale', () {
    test('標準(normal)は倍率1.0でそのまま', () {
      expect(
        TechniqueCpuPresentationSpeed.normal.scale(TechniqueCpuPresentationTiming.think),
        TechniqueCpuPresentationTiming.think,
      );
    });

    test('ゆっくり(slow)は1.5倍', () {
      expect(
        TechniqueCpuPresentationSpeed.slow.scale(const Duration(milliseconds: 1000)),
        const Duration(milliseconds: 1500),
      );
    });

    test('高速(fast)は0.5倍', () {
      expect(
        TechniqueCpuPresentationSpeed.fast.scale(const Duration(milliseconds: 1000)),
        const Duration(milliseconds: 500),
      );
    });

    test('全ての速度設定でも待ち時間は負にならない', () {
      for (final speed in TechniqueCpuPresentationSpeed.values) {
        for (final base in [
          TechniqueCpuPresentationTiming.think,
          TechniqueCpuPresentationTiming.energySet,
          TechniqueCpuPresentationTiming.attackDeclared,
          TechniqueCpuPresentationTiming.counterUsed,
          TechniqueCpuPresentationTiming.hitResolved,
          TechniqueCpuPresentationTiming.fallOrSubmissionStart,
          TechniqueCpuPresentationTiming.kickOutOrRopeBreak,
          TechniqueCpuPresentationTiming.finisherDeclared,
          TechniqueCpuPresentationTiming.finisherResolved,
          TechniqueCpuPresentationTiming.passTurn,
        ]) {
          expect(speed.scale(base).isNegative, isFalse);
        }
      }
    });
  });

  group('演出タイミングとCPU意思決定/シミュレーション層の分離（Phase 8.5A-2 ⑪）', () {
    test('technique_match_cpu.dart（意思決定ロジック）はTechniqueCpuPresentationTimingを参照しない', () {
      final content = File(
        'lib/src/technique_deck/technique_match_cpu.dart',
      ).readAsStringSync();
      expect(
        content.contains('TechniqueCpuPresentationTiming'),
        isFalse,
        reason: 'CPUの意思決定ロジックが演出タイミングに依存すると、'
            'CPU対CPUの一括シミュレーション（playFullMatch）が遅くなってしまう',
      );
    });

    test('technique_match_state.dart（純粋関数エンジン）もTechniqueCpuPresentationTimingを参照しない', () {
      final content = File(
        'lib/src/technique_deck/technique_match_state.dart',
      ).readAsStringSync();
      expect(content.contains('TechniqueCpuPresentationTiming'), isFalse);
    });
  });
}
