import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/i18n/l10n.dart';
import 'package:transasim_mobile/modules/catalog/domain/catalog.dart';
import 'package:transasim_mobile/modules/catalog/presentation/destination_screen.dart';

import '../core/brand_config_test.dart' show validJson;

/// A pack's title is its offer, from its own fields (docs/APPROVALS.md,
/// 2026-10-17); the backend's name only when the pack says nothing else.
void main() {
  final en = L10n(brand: BrandConfig.parse(validJson(), expectedSlug: 'acme').config as BrandConfig, language: 'en');
  Pack pack({int? kb, int? days, List<String> codes = const ['DNK']}) => Pack(
        id: 1,
        name: 'One-off EU28PLUS 500MB 2 day(s)',
        description: null,
        data: DataAllowance(kilobytes: kb, unlimited: false),
        validity: Validity(amount: days, unit: 'days'),
        price: null,
        tags: const [],
        countryCodes: codes,
        coverImageUrl: null,
      );

  test('the offer, from the size and the duration', () {
    expect(packOffer(en, pack(kb: 500 * 1024, days: 2)), '500 MB · 2 days');
    expect(packOffer(en, pack(kb: 10 * 1024 * 1024, days: 1)), '10 GB · 1 day');
    expect(packOffer(en, pack(kb: 500 * 1024)), '500 MB', reason: 'no duration: the size alone');
    expect(packOffer(en, pack()), 'One-off EU28PLUS 500MB 2 day(s)', reason: 'neither: the backend name');
  });

  test('the coverage: the country, or how many', () {
    expect(packCoverage(en, 'en', pack()), 'Denmark');
    expect(packCoverage(en, 'en', pack(codes: ['FRA', 'ITA', 'ESP'])), '3 countries');
    expect(packCoverage(en, 'en', pack(codes: []), destinationCode: 'NOR'), 'Norway');
    expect(packCoverage(en, 'en', pack(codes: [])), '', reason: 'nothing to name');
  });
}
