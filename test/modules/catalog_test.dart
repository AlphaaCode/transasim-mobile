import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/modules/catalog/data/catalog_dto.dart';
import 'package:transasim_mobile/modules/catalog/domain/catalog.dart';
import 'package:transasim_mobile/modules/catalog/domain/pack_filter.dart';
import 'package:transasim_mobile/modules/catalog/domain/region.dart';
import 'package:transasim_mobile/modules/catalog/presentation/catalog_controllers.dart';

Map<String, dynamic> packJson({
  Object? id = 1,
  Object? name = 'One-off France 10GB 7 day(s)',
  Object? status = 'AVAILABLE',
  Object? dataValue = 10 * 1024 * 1024,
  Object? countries = const [
    {'code': 'FR', 'name': 'France'}
  ],
  Object? prices,
  Object? tags,
}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'status': status,
      'dataValue': dataValue,
      'validityDuration': 7,
      'validityDurationUnit': 'DAY',
      'countries': countries,
      'tags': tags,
      'prices': prices ??
          const [
            {
              'sabilyAmount': 9.99,
              'amount': 4.0,
              'currency': {'code': 'EUR', 'symbol': '€'}
            }
          ],
    };

void main() {
  group('a malformed row never takes the catalogue down with it', () {
    // The old app asserted `a.countries!.length` while sorting, so ONE pack row
    // with a null countries array killed the entire catalogue parse
    // (ANALYSE-EXISTANT.md §2.2). Every one of these returns null instead.

    test('null countries', () {
      expect(PackParser.parse(packJson(countries: null), currencyCode: 'EUR')?.countryCodes,
          isEmpty);
    });

    test('missing id, missing name, wrong type', () {
      expect(PackParser.parse(packJson(id: null), currencyCode: 'EUR'), isNull);
      expect(PackParser.parse(packJson(name: null), currencyCode: 'EUR'), isNull);
      expect(PackParser.parse('not a pack', currencyCode: 'EUR'), isNull);
      expect(PackParser.parse(null, currencyCode: 'EUR'), isNull);
    });

    test('a pack that is not sellable is dropped', () {
      for (final status in ['DELETED', 'DISABLED', 'RELEASED']) {
        expect(PackParser.parse(packJson(status: status), currencyCode: 'EUR'), isNull,
            reason: '$status must not be offered for sale');
      }
    });

    test('status casing does not decide the outcome', () {
      // The API spells them upper-case; the old client compared to lower-case
      // literals. Both spellings must work.
      for (final status in ['AVAILABLE', 'available', 'Enabled']) {
        expect(PackParser.parse(packJson(status: status), currencyCode: 'EUR'), isNotNull);
      }
    });
  });

  group('price selection', () {
    test('prefers the customer-facing field over the cost basis', () {
      final pack = PackParser.parse(packJson(), currencyCode: 'EUR')!;
      expect(pack.price!.wireAmount, '9.99');
    });

    test('falls back to amount when the customer field is absent', () {
      final pack = PackParser.parse(
        packJson(prices: const [
          {
            'amount': 4.5,
            'currency': {'code': 'EUR'}
          }
        ]),
        currencyCode: 'EUR',
      )!;
      expect(pack.price!.wireAmount, '4.5');
    });

    test('a pack with no price in the brand currency is not purchasable', () {
      // The old currency selector displayed a converted price and charged the
      // base one. A pack priced only in USD is simply not offered to a EUR
      // brand rather than being shown at the wrong number.
      final pack = PackParser.parse(
        packJson(prices: const [
          {
            'sabilyAmount': 12.0,
            'currency': {'code': 'USD'}
          }
        ]),
        currencyCode: 'EUR',
      )!;
      expect(pack.price, isNull);
      expect(pack.isPurchasable, isFalse);
    });

    test('the exact decimal survives parsing — this is the R1 guard', () {
      // ANALYSE-EXISTANT.md §7.2: `double.parse(x).toInt()` turned a €9.99 pack
      // into a €9.00 charge, and the backend then refused to provision because
      // the captured amount did not match the price. Money is carried, never
      // recomputed.
      for (final raw in [9.99, '9.99']) {
        final pack = PackParser.parse(
          packJson(prices: [
            {
              'sabilyAmount': raw,
              'currency': {'code': 'EUR'}
            }
          ]),
          currencyCode: 'EUR',
        )!;
        expect(pack.price!.wireAmount, '9.99',
            reason: 'the string sent to /payments/init must not lose its cents');
      }
    });
  });

  group('formatting', () {
    test('data size yields a number and an unnamed unit, never a Latin literal', () {
      // The domain must not produce "10 GB": a hardcoded Latin unit rendered as
      // "GB 5" in Arabic. The unit is named by the presentation layer from the
      // dictionary.
      DataAllowance kb(int v) => DataAllowance(kilobytes: v, unlimited: false);

      expect(kb(10 * 1024 * 1024).size.amount, '10');
      expect(kb(10 * 1024 * 1024).size.unit, DataUnit.gigabyte);

      expect(kb(512 * 1024).size.amount, '512');
      expect(kb(512 * 1024).size.unit, DataUnit.megabyte);

      expect(kb(1536 * 1024).size.amount, '1.5');
      expect(kb(1536 * 1024).size.unit, DataUnit.gigabyte);

      expect(const DataAllowance(kilobytes: null, unlimited: true).size.unit,
          DataUnit.unlimited);
      expect(const DataAllowance(kilobytes: 0, unlimited: false).size.unit, DataUnit.none);
    });

    test('money formats to two decimals with the symbol', () {
      expect(const Money(wireAmount: '9.99', currencyCode: 'EUR', symbol: '€').format('en'), '€9.99');
      expect(const Money(wireAmount: '8', currencyCode: 'EUR').format('en'), '€8.00');
      // The live backend sends symbol "EUR". It must not reach the screen.
      expect(const Money(wireAmount: '6.0', currencyCode: 'EUR', symbol: 'EUR').format('fr'),
          '6,00 €');
      // Every language the socle ships formats without throwing.
      for (final locale in ['en', 'fr', 'ar', 'es', 'de', 'sl', 'sq']) {
        expect(const Money(wireAmount: '21', currencyCode: 'EUR').format(locale), contains('€'),
            reason: locale);
      }
    });
  });

  group('destination aggregation', () {
    Pack pack(String amount, int gb) => Pack(
          id: gb,
          name: '${gb}GB',
          description: null,
          data: DataAllowance(kilobytes: gb * 1024 * 1024, unlimited: false),
          validity: const Validity(amount: 7, unit: 'DAY'),
          price: Money(wireAmount: amount, currencyCode: 'EUR', symbol: '€'),
          tags: const [],
          countryCodes: const ['FR'],
          coverImageUrl: null,
        );

    test('cheapest price and best per-GB rate', () {
      final d = Destination(
        code: 'FR',
        name: 'France',
        packs: [pack('16.00', 25), pack('8.00', 10)],
      );
      expect(d.cheapestPrice!.wireAmount, '8.00');
      // 16/25 = 0.64 beats 8/10 = 0.80
      expect(d.bestPricePerGigabyte, closeTo(0.64, 0.001));
    });

    test('an unpriced pack contributes no rate rather than a zero one', () {
      final d = Destination(code: 'FR', name: 'France', packs: [
        Pack(
          id: 1,
          name: 'x',
          description: null,
          data: const DataAllowance(kilobytes: 1024 * 1024, unlimited: false),
          validity: const Validity(amount: 1, unit: 'DAY'),
          price: null,
          tags: const [],
          countryCodes: const ['FR'],
          coverImageUrl: null,
        )
      ]);
      expect(d.cheapestPrice, isNull);
      expect(d.bestPricePerGigabyte, isNull);
    });

    test('an unlimited pack has no per-GB rate — no division by zero', () {
      final p = Pack(
        id: 1,
        name: 'Unlimited',
        description: null,
        data: const DataAllowance(kilobytes: null, unlimited: true),
        validity: const Validity(amount: 30, unit: 'DAY'),
        price: const Money(wireAmount: '30.00', currencyCode: 'EUR'),
        tags: const [],
        countryCodes: const ['FR'],
        coverImageUrl: null,
      );
      expect(p.pricePerGigabyte, isNull);
    });
  });

  group('no client host is ever synthesised', () {
    test('a pack without cover art has none — nothing is invented', () {
      // The old model built `sabily.fr/wp-content/uploads/{productId}.png`
      // inside the data layer (§4.6). Absent means absent.
      final pack = PackParser.parse(packJson(), currencyCode: 'EUR')!;
      expect(pack.coverImageUrl, isNull);
    });
  });

  group('the popular badge comes from the API, not from a hardcoded list', () {
    test('recognises a tag, case-insensitively', () {
      expect(PackParser.parse(packJson(tags: const ['POPULAR']), currencyCode: 'EUR')!.isPopular,
          isTrue);
      expect(PackParser.parse(packJson(tags: null), currencyCode: 'EUR')!.isPopular, isFalse);
    });
  });

  group('the region filter works on destinations', () {
    Destination d(String code, String name) => Destination(code: code, name: name, packs: const []);
    final all = [d('FRA', 'France'), d('SAU', 'Saudi Arabia'), d('DZA', 'Algeria'), d('USA', 'United States')];

    test('All is every destination; a region is only its own', () {
      expect(CatalogReady(destinations: all).visible, hasLength(4));
      expect(CatalogReady(destinations: all, region: Region.africa).visible.map((x) => x.code), ['DZA']);
      expect(CatalogReady(destinations: all, region: Region.asia).visible.map((x) => x.code), ['SAU']);
    });

    test('search and region narrow together', () {
      final s = CatalogReady(destinations: all, region: Region.europe, query: 'saudi');
      expect(s.visible, isEmpty);
      expect(CatalogReady(destinations: all, region: Region.europe, query: 'fra').visible, hasLength(1));
    });

    test('only regions the catalogue sells into get a chip, in template order', () {
      // No Oceania destination in this catalogue, so no Oceania chip.
      expect(CatalogReady(destinations: all).regions,
          [Region.europe, Region.asia, Region.americas, Region.africa]);
    });

    test('a capital finds its country, accents and punctuation aside', () {
      final more = [...all, d('COL', 'Colombia'), d('YEM', 'Yemen'), d('GBR', 'United Kingdom')];
      List<String> find(String q) =>
          CatalogReady(destinations: more, query: q).visible.map((x) => x.code).toList();
      expect(find('Paris'), ['FRA']);
      expect(find('riyadh'), ['SAU']);
      expect(find('Bogotá'), ['COL']);
      expect(find('bogota'), ['COL']);
      expect(find('sanaa'), ['YEM']);
      expect(find('  LONDON '), ['GBR']);
      // The name still works, and a capital query respects the region chip.
      expect(find('france'), ['FRA']);
      expect(CatalogReady(destinations: more, query: 'paris', region: Region.asia).visible, isEmpty);
    });

    test('an unknown code has no region rather than a guessed one', () {
      expect(regionOf('ATA'), isNull);
      expect(regionOf('ZZZ'), isNull);
      expect(regionOf('cyp'), Region.europe);
    });
  });

  group('pack filters work over what each pack already says', () {
    Pack p(int id, {int? kb, bool unlimited = false, int days = 7, String unit = 'days'}) => Pack(
          id: id,
          name: 'p$id',
          description: null,
          data: DataAllowance(kilobytes: kb, unlimited: unlimited),
          validity: Validity(amount: days, unit: unit),
          price: const Money(wireAmount: '5', currencyCode: 'EUR'),
          tags: const [],
          countryCodes: const ['SAU'],
          coverImageUrl: null,
        );
    const gb = 1024 * 1024;
    final packs = [
      p(1, kb: gb, days: 7),
      p(2, kb: gb, days: 30),
      p(3, kb: 10 * gb, days: 30),
      p(4, unlimited: true, days: 12, unit: 'months'),
      p(5, kb: 500 * 1024, days: 360),
    ];

    test('the live unit spelling is understood', () {
      // Live sends `months`; matching `MONTH` exactly made this "12 days".
      expect(const Validity(amount: 12, unit: 'months').kind, ValidityUnit.month);
      expect(const Validity(amount: 7, unit: 'days').kind, ValidityUnit.day);
      expect(const Validity(amount: 1, unit: 'DAY').kind, ValidityUnit.day);
    });

    test('options are distinct and ordered, unlimited last', () {
      expect(durationOptions(packs).map((v) => '${v.amount} ${v.kind.name}'),
          ['7 day', '30 day', '360 day', '12 month']);
      expect(dataOptions(packs).map((d) => d.unlimited ? 'U' : '${d.kilobytes}'),
          ['${500 * 1024}', '$gb', '${10 * gb}', 'U']);
    });

    test('selections narrow together; null is all', () {
      final thirty = packs[1].validity;
      final oneGb = packs[0].data;
      expect(filterPacks(packs).map((x) => x.id), [1, 2, 3, 4, 5]);
      expect(filterPacks(packs, duration: thirty).map((x) => x.id), [2, 3]);
      expect(filterPacks(packs, data: oneGb).map((x) => x.id), [1, 2]);
      expect(filterPacks(packs, duration: thirty, data: oneGb).map((x) => x.id), [2]);
      expect(filterPacks(packs, duration: packs[3].validity, data: oneGb), isEmpty);
    });
  });
}
