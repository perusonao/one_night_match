import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_wrestler_catalog.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;

/// Technique Deck Rules Phase 7A（①レスラーカード）で追加した
/// [buildTechniqueDeckWrestlerCatalog] の検証。
void main() {
  group('buildTechniqueDeckWrestlerCatalog', () {
    test('4人分のレスラーカードが揃っている', () {
      final catalog = buildTechniqueDeckWrestlerCatalog();
      expect(
        catalog.map((w) => w.wrestlerId).toSet(),
        {'wrestler_akari', 'wrestler_misaki', 'wrestler_reina', 'wrestler_jack'},
      );
    });

    test('各レスラーカードが必須フィールドをすべて持つ', () {
      final catalog = buildTechniqueDeckWrestlerCatalog();
      for (final wrestler in catalog) {
        expect(wrestler.name, isNotEmpty, reason: wrestler.wrestlerId);
        expect(wrestler.hp, greaterThan(0), reason: wrestler.wrestlerId);
        expect(wrestler.recoveryPower, greaterThan(0), reason: wrestler.wrestlerId);
        expect(wrestler.passiveAbility, isNotEmpty, reason: wrestler.wrestlerId);
        expect(wrestler.description, isNotEmpty, reason: wrestler.wrestlerId);
        expect(wrestler.imagePath, isNotNull, reason: wrestler.wrestlerId);
        expect(wrestler.themeColor, isNotNull, reason: wrestler.wrestlerId);
        expect(wrestler.attributeBonus, isNotEmpty, reason: wrestler.wrestlerId);
      }
    });

    test('火神アカリは打撃・飛びに補正が高い', () {
      final akari = buildTechniqueDeckWrestlerCatalog()
          .firstWhere((w) => w.wrestlerId == 'wrestler_akari');
      expect(akari.attributeBonus[MoveAttribute.strike], greaterThan(0));
      expect(akari.attributeBonus[MoveAttribute.aerial], greaterThan(0));
    });

    test('白銀レイナは関節に補正が高い', () {
      final reina = buildTechniqueDeckWrestlerCatalog()
          .firstWhere((w) => w.wrestlerId == 'wrestler_reina');
      expect(reina.attributeBonus[MoveAttribute.submission], greaterThan(0));
    });

    test('立ち絵パスはtechniqueWrestlerPortraitsと一致する', () {
      final catalog = buildTechniqueDeckWrestlerCatalog();
      for (final wrestler in catalog) {
        expect(
          wrestler.imagePath,
          'assets/images/wrestlers/${wrestler.wrestlerId.replaceFirst('wrestler_', '')}.png',
        );
      }
    });
  });
}
