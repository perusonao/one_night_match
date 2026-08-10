// Combat Ver.1 Phase 4 Codexレビュー指摘H4: CombatV1ActionCheck /
// CombatV1CounterActionCheckが矛盾したlegal/reasonCodeの組み合わせを
// release buildでも構築できないことの検証。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';

void main() {
  group('CombatV1ActionCheck — 矛盾state防止', () {
    test('success()は常にlegal=true・reasonCode=legal', () {
      const check = CombatV1ActionCheck.success('ok');
      expect(check.legal, isTrue);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.legal);
    });

    test('failure()は常にlegal=false', () {
      final check = CombatV1ActionCheck.failure(
        'ng',
        CombatV1TechniqueLegalityReasonCode.wrongPhase,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.wrongPhase);
    });

    test('failure()にreasonCode=legalを渡すとassertではなくArgumentErrorで拒否される'
        '（release buildでも有効、H4対応）', () {
      expect(
        () => CombatV1ActionCheck.failure(
          '矛盾したcheck',
          CombatV1TechniqueLegalityReasonCode.legal,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CombatV1CounterActionCheck — 矛盾state防止', () {
    test('success()は常にlegal=true・reasonCode=legal', () {
      const check = CombatV1CounterActionCheck.success('ok');
      expect(check.legal, isTrue);
      expect(check.reasonCode, CombatV1CounterLegalityReasonCode.legal);
    });

    test('failure()は常にlegal=false', () {
      final check = CombatV1CounterActionCheck.failure(
        'ng',
        CombatV1CounterLegalityReasonCode.wrongPhase,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1CounterLegalityReasonCode.wrongPhase);
    });

    test('failure()にreasonCode=legalを渡すとassertではなくArgumentErrorで拒否される'
        '（release buildでも有効、H4対応）', () {
      expect(
        () => CombatV1CounterActionCheck.failure(
          '矛盾したcheck',
          CombatV1CounterLegalityReasonCode.legal,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
