// Conditional so Studio can run this parser on the plain Dart VM; under
// Flutter it is exactly `package:flutter/painting.dart`. See ../headless.dart
// for why the condition is `mirrors` and not `ui`.
import 'package:flutter/painting.dart' if (dart.library.mirrors) '../headless.dart' show Color;

import '../i18n/locales.dart';
import 'brand_validation.dart';

/// The complete brand contract. ARCHITECTURE-MOBILE.md §2.
///
/// Every value the app displays comes from here — never from a constant in a
/// widget. Adding a client is a folder under `brands/<slug>/`, with no change
/// to any file in `lib/`.
///
/// Immutable, validated, and injected (see `brand_providers.dart`). Never a
/// global mutable, and never a `Map` carried around the app: a global makes the
/// socle untestable and invites `if (brand == 'sabily')`.
class BrandConfig {
  final String slug;
  final String name;
  final Map<String, String> tagline;
  final String? domain;

  final BrandColors colors;
  final BrandThemeTokens theme;
  final BrandLogo logo;
  final BrandVisuals visuals;

  final List<String> locales;
  final String defaultLocale;
  final String currency;

  final BrandFeatures features;
  final BrandSupport support;
  final BrandLegal legal;
  final BrandMobile mobile;

  /// key -> language -> text. §2.8.
  final Map<String, Map<String, String>> texts;

  const BrandConfig({
    required this.slug,
    required this.name,
    required this.tagline,
    required this.domain,
    required this.colors,
    required this.theme,
    required this.logo,
    required this.visuals,
    required this.locales,
    required this.defaultLocale,
    required this.currency,
    required this.features,
    required this.support,
    required this.legal,
    required this.mobile,
    required this.texts,
  });

  bool get servesRtl => locales.any(isRtlLanguage);

  /// Resolve an asset path declared in the config to its bundle location.
  ///
  /// §2.4: no path in the codebase ever contains a client slug. The config
  /// holds a bare filename; this is the only place the slug is joined to it.
  String assetPath(String fileName) => 'brands/$slug/assets/$fileName';

  /// Parse and validate in ONE pass, reporting every problem.
  ///
  /// [expectedSlug] is the folder name. §2.1 requires `slug` to equal it —
  /// the JSON alone cannot check that, so the loader passes it in.
  static BrandValidation parse(
    Map<String, dynamic> json, {
    required String expectedSlug,
  }) {
    final p = BrandProblems();

    final slug = _string(json, 'slug', p, required: true) ?? '';
    if (slug.isNotEmpty && slug != expectedSlug) {
      p.error('slug', 'is "$slug" but the folder is "$expectedSlug"; they must match');
    }
    final name = _string(json, 'name', p, required: true) ?? '';
    final domain = _string(json, 'domain', p);
    final tagline = _langMap(json['tagline'], 'tagline', p);

    final colors = BrandColors._parse(_map(json, 'colors', p, required: true), p);
    final theme = BrandThemeTokens._parse(_map(json, 'theme', p), p);
    final logo = BrandLogo._parse(_map(json, 'logo', p, required: true), p);

    // locales / defaultLocale before visuals: the RTL visual check needs them.
    final locales = _stringList(json['locales'], 'locales', p, required: true);
    for (final l in locales) {
      if (!kSocleSupportedLanguages.contains(l)) {
        p.warn('locales', 'the socle has no dictionary for "$l"; it will be ignored');
      }
    }
    final defaultLocale = _string(json, 'defaultLocale', p, required: true) ?? '';
    if (defaultLocale.isNotEmpty && locales.isNotEmpty && !locales.contains(defaultLocale)) {
      p.error('defaultLocale', '"$defaultLocale" is not in locales $locales');
    }

    final servesRtl = locales.any(isRtlLanguage);
    final visuals = BrandVisuals._parse(_map(json, 'visuals', p), p, servesRtl: servesRtl);

    final currency = _string(json, 'currency', p, required: true) ?? '';
    if (currency.isNotEmpty && !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      p.error('currency', '"$currency" is not an ISO 4217 code');
    }

    final features = BrandFeatures._parse(_map(json, 'features', p), p);
    final support = BrandSupport._parse(_map(json, 'support', p, required: true), p);
    final legal = BrandLegal._parse(_map(json, 'legal', p, required: true), p);
    final mobile = BrandMobile._parse(_map(json, 'mobile', p, required: true), p);

    final texts = <String, Map<String, String>>{};
    final rawTexts = json['texts'];
    if (rawTexts is Map) {
      for (final entry in rawTexts.entries) {
        final key = entry.key.toString();
        texts[key] = _langMap(entry.value, 'texts.$key', p);
      }
    } else if (rawTexts != null) {
      p.error('texts', 'must be an object of key -> { language: text }');
    }

    if (p.hasErrors) {
      return BrandValidation(config: null, errors: p.errors, warnings: p.warnings);
    }

    return BrandValidation(
      config: BrandConfig(
        slug: slug,
        name: name,
        tagline: tagline,
        domain: domain,
        colors: colors!,
        theme: theme,
        logo: logo!,
        visuals: visuals,
        locales: locales,
        defaultLocale: defaultLocale,
        currency: currency,
        features: features,
        support: support!,
        legal: legal!,
        mobile: mobile!,
        texts: texts,
      ),
      errors: p.errors,
      warnings: p.warnings,
    );
  }
}

/// Five colours, defined by ROLE and never by hue. §2.2.
///
/// `primary` does not mean "green": it means "the anchor colour". The day a
/// client arrives in navy, nothing is called `sabilyGreen`.
///
/// Semantic colours (danger/success/warning) and structural greys are
/// deliberately NOT here — they are product decisions, not brand decisions, and
/// they live in the socle. They become configurable the day a client asks, not
/// before (§2.3).
class BrandColors {
  /// Anchor: strong text, dark fills, bars.
  final Color primary;

  /// Symbol, positive states, active elements.
  final Color accent;

  /// Brand background, tinted.
  final Color surface;

  /// Call to action. Strong contrast against [primary] is expected.
  final Color cta;

  /// Text sitting on a [cta] fill.
  final Color ctaText;

  const BrandColors({
    required this.primary,
    required this.accent,
    required this.surface,
    required this.cta,
    required this.ctaText,
  });

  static BrandColors? _parse(Map<String, dynamic>? json, BrandProblems p) {
    if (json == null) return null;
    Color? read(String key) => _color(json, key, 'colors.$key', p, required: true);
    final primary = read('primary');
    final accent = read('accent');
    final surface = read('surface');
    final cta = read('cta');
    final ctaText = read('ctaText');
    if (primary == null || accent == null || surface == null || cta == null || ctaText == null) {
      return null;
    }
    return BrandColors(
      primary: primary,
      accent: accent,
      surface: surface,
      cta: cta,
      ctaText: ctaText,
    );
  }
}

/// Optional token sets. §2.3 — "configurable does not mean uniform".
///
/// The premium block deliberately has a cream-and-gold register that detaches
/// it from the rest. A brand that writes nothing gets the socle's rendering,
/// token by token; a brand that wants "the same thing in blue" writes three
/// values.
class BrandThemeTokens {
  final Color? premiumSurface;
  final Color? premiumAccent;
  final Color? premiumText;

  /// The shop's own register: Store, a destination and its packs, My eSIMs.
  /// Keyed by [kShopTokens]; an absent key keeps the socle's rendering, so a
  /// brand that writes no `shop` block looks exactly as it did.
  final Map<String, Color> shop;

  const BrandThemeTokens({
    this.premiumSurface,
    this.premiumAccent,
    this.premiumText,
    this.shop = const {},
  });

  bool get hasPremiumOverrides =>
      premiumSurface != null || premiumAccent != null || premiumText != null;

  static BrandThemeTokens _parse(Map<String, dynamic>? json, BrandProblems p) {
    if (json == null) return const BrandThemeTokens();
    final premium = _tokenBlock(json, 'premium', const {'surface', 'accent', 'text'}, p);
    final shop = _tokenBlock(json, 'shop', kShopTokens, p);
    return BrandThemeTokens(
      premiumSurface: premium['surface'],
      premiumAccent: premium['accent'],
      premiumText: premium['text'],
      shop: shop,
    );
  }

  static Map<String, Color> _tokenBlock(
      Map<String, dynamic> json, String block, Set<String> known, BrandProblems p) {
    final raw = json[block];
    if (raw == null) return const {};
    if (raw is! Map) {
      p.error('theme.$block', 'must be an object');
      return const {};
    }
    final m = raw.cast<String, dynamic>();
    final out = <String, Color>{};
    for (final k in m.keys) {
      if (!known.contains(k)) {
        p.warn('theme.$block.$k', 'unknown $block token; it will be ignored');
        continue;
      }
      final c = _color(m, k, 'theme.$block.$k', p);
      if (c != null) out[k] = c;
    }
    return out;
  }
}

/// The shop's colour roles (`theme.shop`), by what they paint:
///
///  - `fill`, `fillEnd`: the destination header and the pack hero gradient,
///    the active filter chip, the usage bar and decorative glyphs;
///  - `onFill`: text on those fills;
///  - `display`: large titles and prices, the only text allowed the fill hue;
///  - `badge`, `onBadge`: pills (price per GB, eSIM status);
///  - `priceBadge`, `onPriceBadge`: a pack's price tag;
///  - `cta`, `ctaText`: the shop's secondary buttons (top-up);
///  - `buy`, `onBuy`: the buttons that lead to paying — a pack's "Buy", the
///    detail screen's buy bar, checkout's "Pay". `primary` unless the brand's
///    commerce buttons differ from its form buttons, as Acorn's amber does.
///
/// Everything else in those screens — names, specs, labels, the buy button —
/// stays on the brand's `primary`, so smaller text keeps its contrast.
const Set<String> kShopTokens = {
  'fill', 'fillEnd', 'onFill', 'display', 'badge', 'onBadge', //
  'priceBadge', 'onPriceBadge', 'cta', 'ctaText', 'buy', 'onBuy',
};

class BrandLogo {
  final String mark;
  final String full;

  /// Variant for dark backgrounds. Absent -> [full] is used, with a warning.
  final String? fullInverse;

  /// A short animated logo played once as the app's first moment, after the
  /// native splash. Optional: a brand without one goes straight in.
  final String? intro;

  /// The colour of [intro]'s own edges: painted around the video, and by the
  /// native launch window, so the hand over from the OS shows no flash.
  /// Absent -> `colors.surface`, which is what Sabily's cream-edged animation
  /// wants; an animation that opens on black says so here.
  final Color? introBackground;

  const BrandLogo({
    required this.mark,
    required this.full,
    this.fullInverse,
    this.intro,
    this.introBackground,
  });

  /// What to draw on a dark fill. Never null — degrades rather than crashes.
  String get onDark => fullInverse ?? full;

  static BrandLogo? _parse(Map<String, dynamic>? json, BrandProblems p) {
    if (json == null) return null;
    final mark = _string(json, 'mark', p, required: true, path: 'logo.mark');
    final full = _string(json, 'full', p, required: true, path: 'logo.full');
    final inverse = _string(json, 'fullInverse', p, path: 'logo.fullInverse');
    if (inverse == null) {
      p.warn('logo.fullInverse', 'absent; the light lockup will be used on dark fills');
    }
    final intro = _string(json, 'intro', p, path: 'logo.intro');
    final introBackground = _color(json, 'introBackground', 'logo.introBackground', p);
    if (mark == null || full == null) return null;
    return BrandLogo(
      mark: mark,
      full: full,
      fullInverse: inverse,
      intro: intro,
      introBackground: introBackground,
    );
  }
}

const Set<String> kPackImageRegions = {
  'mena', 'europe', 'asia', 'africa', 'americas', 'oceania', 'world',
};

Map<String, String> _packImages(Object? raw, BrandProblems p) {
  if (raw == null) return const {};
  if (raw is! Map) {
    p.error('visuals.packImages', 'must be an object of region -> file name');
    return const {};
  }
  final out = <String, String>{};
  for (final MapEntry(:key, :value) in raw.entries) {
    if (key is! String ||
        !(kPackImageRegions.contains(key) || RegExp(r'^[A-Z]{3}$').hasMatch(key))) {
      p.warn('visuals.packImages.$key',
          'unknown key; expected a region ($kPackImageRegions) or an ISO3 country code');
      continue;
    }
    if (value is! String || value.isEmpty) {
      p.error('visuals.packImages.$key', 'must be a file name');
      continue;
    }
    out[key] = value;
  }
  return out;
}

class BrandVisuals {
  final String? heroBackground;
  final String? heroBackgroundSmall;

  /// "How it works" artwork. §2.4 and brief §4.4: a mirrored composition is
  /// unreadable, so LTR and RTL are two RECOMPOSED images, not one flipped.
  final String? howItWorksLtr;
  final String? howItWorksRtl;

  /// Header photos for pack cards, used while the backend supplies none per
  /// pack. Keys are an image region (`mena`, `europe`, `asia`, `africa`,
  /// `americas`, `oceania`, `world`) or a destination's ISO 3166-1 alpha-3
  /// code, which overrides its region. `world` is the fallback. Absent: cards
  /// keep their plain branded wash.
  final Map<String, String> packImages;

  const BrandVisuals({
    this.heroBackground,
    this.heroBackgroundSmall,
    this.howItWorksLtr,
    this.howItWorksRtl,
    this.packImages = const {},
  });

  /// The image for a destination: its own override, else its region's image,
  /// else the `world` image.
  String? packImage({required String destinationCode, required String regionKey}) =>
      packImages[destinationCode.toUpperCase()] ?? packImages[regionKey] ?? packImages['world'];

  /// Small screens get the small file when there is one.
  String? hero({required bool small}) =>
      small ? (heroBackgroundSmall ?? heroBackground) : heroBackground;

  String? howItWorks({required bool rtl}) => rtl ? howItWorksRtl : howItWorksLtr;

  static BrandVisuals _parse(
    Map<String, dynamic>? json,
    BrandProblems p, {
    required bool servesRtl,
  }) {
    if (json == null) return const BrandVisuals();
    final hero = json['hero'] is Map ? (json['hero'] as Map).cast<String, dynamic>() : null;
    final hiw =
        json['howItWorks'] is Map ? (json['howItWorks'] as Map).cast<String, dynamic>() : null;

    final ltr = hiw == null ? null : _string(hiw, 'ltr', p, path: 'visuals.howItWorks.ltr');
    final rtl = hiw == null ? null : _string(hiw, 'rtl', p, path: 'visuals.howItWorks.rtl');

    if (servesRtl && rtl == null) {
      p.warn(
        'visuals.howItWorks.rtl',
        'this brand serves a right-to-left language but has no RTL artwork; '
            'a mirrored composition is unreadable, so the block will be hidden',
      );
    }

    return BrandVisuals(
      heroBackground:
          hero == null ? null : _string(hero, 'background', p, path: 'visuals.hero.background'),
      heroBackgroundSmall: hero == null
          ? null
          : _string(hero, 'backgroundSmall', p, path: 'visuals.hero.backgroundSmall'),
      howItWorksLtr: ltr,
      howItWorksRtl: rtl,
      packImages: _packImages(json['packImages'], p),
    );
  }
}

/// §2.6 — exactly one flag, because exactly one flag is read by the code.
///
/// The hygiene rule from the brief §2.5 is enforced here: nothing enters
/// `features` unless the code reads it. The web socle promised `vouchers`,
/// `topUp`, `citySearch`, `segments`, `analytics`, `social`, `apps` for months
/// — all declared, none read. They were removed.
///
/// `b2b` deliberately does not exist: mobile is BtoC only (ARCHITECTURE-MOBILE
/// §0). It will not be added "just in case" — a decorative flag is a delayed
/// lie.
class BrandFeatures {
  /// TransaPay. Off by default; the wallet module is not registered when false.
  final bool wallet;

  const BrandFeatures({this.wallet = false});

  static const Set<String> _known = {'wallet'};

  static BrandFeatures _parse(Map<String, dynamic>? json, BrandProblems p) {
    if (json == null) return const BrandFeatures();
    for (final k in json.keys) {
      if (!_known.contains(k)) {
        p.warn('features.$k', 'unknown flag; no code reads it, so it does nothing');
      }
    }
    final wallet = json['wallet'];
    if (wallet != null && wallet is! bool) {
      p.error('features.wallet', 'must be true or false');
    }
    return BrandFeatures(wallet: wallet is bool ? wallet : false);
  }
}

class BrandSupport {
  final String email;
  final Map<String, String> hours;

  /// Where a business applies to resell this brand. Optional: a brand without
  /// a partner programme simply shows no partner entry.
  final String? partnerUrl;

  const BrandSupport({required this.email, required this.hours, this.partnerUrl});

  static BrandSupport? _parse(Map<String, dynamic>? json, BrandProblems p) {
    if (json == null) return null;
    final email = _string(json, 'email', p, required: true, path: 'support.email');
    if (email != null && !email.contains('@')) {
      p.error('support.email', '"$email" is not an email address');
    }
    final hours = json['hours'] == null
        ? <String, String>{}
        : (json['hours'] is String
            ? <String, String>{'*': json['hours'] as String}
            : _langMap(json['hours'], 'support.hours', p));
    final partnerUrl = _url(json, 'partnerUrl', 'support.partnerUrl', p);
    if (email == null) return null;
    return BrandSupport(email: email, hours: hours, partnerUrl: partnerUrl);
  }
}

/// §2.7. Three decisions carried over from the web contract, not negotiable:
///
///  - `country` deliberately has NO default. Assuming "FR" would put French
///    obligations on a foreign client; a white-label socle does not decide that
///    on a client's behalf.
///  - Missing legal identifiers stay empty — none are invented. The screen
///    shows them even when empty, with a dash: their absence is an anomaly
///    better made visible than hidden.
///  - `termsUrl` / `privacyUrl` are URLs, never bundled files. Legal texts
///    bind the client and must change without a store submission.
class BrandLegal {
  final String companyName;
  final String? tradingAs;
  final String country;
  final String? legalForm;
  final String? siren;
  final String? siret;
  final String? vatNumber;
  final String? capital;
  final String? rcs;
  final String? ape;
  final String? address;
  final String? city;
  final String? director;
  final String? directorTitle;
  final String? jurisdiction;
  final String? textsLastUpdated;
  final String? host;
  final double? vatRate;
  final String termsUrl;
  final String privacyUrl;

  const BrandLegal({
    required this.companyName,
    required this.tradingAs,
    required this.country,
    required this.legalForm,
    required this.siren,
    required this.siret,
    required this.vatNumber,
    required this.capital,
    required this.rcs,
    required this.ape,
    required this.address,
    required this.city,
    required this.director,
    required this.directorTitle,
    required this.jurisdiction,
    required this.textsLastUpdated,
    required this.host,
    required this.vatRate,
    required this.termsUrl,
    required this.privacyUrl,
  });

  String get displayName => tradingAs ?? companyName;

  /// A legal identifier for display: the value, or a dash when absent.
  /// Never fabricated, never hidden.
  static String show(String? v) => (v == null || v.isEmpty) ? '—' : v;

  static BrandLegal? _parse(Map<String, dynamic>? json, BrandProblems p) {
    if (json == null) return null;
    String? s(String k) => _string(json, k, p, path: 'legal.$k');

    final companyName = _string(json, 'companyName', p, required: true, path: 'legal.companyName');
    final country = _string(json, 'country', p, required: true, path: 'legal.country');
    if (country != null && !RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      p.error('legal.country', '"$country" is not an ISO 3166-1 alpha-2 code');
    }
    final termsUrl = _url(json, 'termsUrl', 'legal.termsUrl', p, required: true);
    final privacyUrl = _url(json, 'privacyUrl', 'legal.privacyUrl', p, required: true);

    final rawVat = json['vatRate'];
    double? vatRate;
    if (rawVat == null) {
      p.warn('legal.vatRate', 'absent; invoices and price breakdowns cannot show a VAT line');
    } else if (rawVat is num) {
      vatRate = rawVat.toDouble();
    } else {
      p.error('legal.vatRate', 'must be a number');
    }

    // Identifiers a client has not supplied yet: shown as a dash (§2.7) and
    // listed here, so the gap is a known one rather than a silent blank.
    if (s('vatNumber') == null) {
      p.warn('legal.vatNumber', 'absent; the legal screen and invoices show no VAT number');
    }
    if (s('rcs') == null) {
      p.warn('legal.rcs', 'absent; no business registry number to show');
    }

    if (companyName == null || country == null || termsUrl == null || privacyUrl == null) {
      return null;
    }

    return BrandLegal(
      companyName: companyName,
      tradingAs: s('tradingAs'),
      country: country,
      legalForm: s('legalForm'),
      siren: s('siren'),
      siret: s('siret'),
      vatNumber: s('vatNumber'),
      capital: s('capital'),
      rcs: s('rcs'),
      ape: s('ape'),
      address: s('address'),
      city: s('city'),
      director: s('director'),
      directorTitle: s('directorTitle'),
      jurisdiction: s('jurisdiction'),
      textsLastUpdated: s('textsLastUpdated'),
      host: s('host'),
      vatRate: vatRate,
      termsUrl: termsUrl,
      privacyUrl: privacyUrl,
    );
  }
}

/// The registration fields the socle knows how to render. §2.9.
///
/// Deliberately a CLOSED set. The config picks which of these to show and in
/// what order; the socle owns each field's label, widget and validation.
/// This is not a form builder — adding a field TYPE stays a code change, and
/// that is the point: otherwise the config becomes a language.
const List<String> kKnownRegistrationFields = <String>[
  'email',
  'password',
  'title',
  'firstName',
  'lastName',
  'dateOfBirth',
  'address',
  'zipCode',
  'city',
  'country',
  'phoneNum',
  'language',
];

/// What the LIVE backend actually refuses to register without.
///
/// `SubscriberModel` in the deployed JAR carries `@NotNull` on eleven fields —
/// see the list that used to live here — but that is the model's paper
/// contract, not its runtime behaviour. Brief §8.4's request to cut
/// registration to four fields was tested directly against the dev backend on
/// 22/09/2026 (`claude/demandes-backend-mobile.md`, P1): a registration sent
/// with only `firstName`/`lastName`/`email`/`password` succeeded, and
/// `dateOfBirth`/`address`/`zipCode`/`city`/`country`/`language`/`title` all
/// came back `null` with no error. Whatever the annotation says on paper, the
/// route does not enforce it. This constant now tracks confirmed runtime
/// behaviour rather than the annotation; if that ever changes, this is the
/// single thing to edit, and the validation below immediately tells every
/// brand whether its config still fits.
const List<String> kServerRequiredRegistrationFields = <String>[
  'title',
  'email',
  'firstName',
  'lastName',
  'password',
];

/// Of those, one is supplied by the app rather than typed by a user:
///
///  - `title`    — a salutation. The live app sends `null` here, which the
///    deployed `@NotNull` should reject; the socle sends an empty string
///    instead, which satisfies the constraint under either reading. Flagged as
///    a backend question rather than guessed at.
///
/// `language` is not in `kServerRequiredRegistrationFields` above — the 22/09
/// test showed it comes back `null` with no error like the others — but the
/// socle still supplies it on every request regardless, since `Accept-Language`
/// (Q5) already carries the same information and sending it costs nothing.
const Set<String> kAppSuppliedRegistrationFields = <String>{'language', 'title'};

/// The three a person actually has to fill in, confirmed against the live dev
/// backend rather than assumed from the model annotations. A brand whose
/// `registration.fields` omits any of these cannot register anyone, so it is a
/// configuration ERROR rather than a 400 discovered in production.
final List<String> kUserRequiredRegistrationFields = kServerRequiredRegistrationFields
    .where((f) => !kAppSuppliedRegistrationFields.contains(f))
    .toList(growable: false);

/// The socle's default when a brand says nothing: exactly what the live backend
/// requires of a user, and nothing more.
///
/// `country` is NOT in here even though product wants it shown for every
/// brand as of the 24/09 precision on P1 — it stays a genuinely optional field
/// server-side (confirmed 22/09: `null` with no error), so a brand that wants
/// it collected states so explicitly in its own `registration.fields` rather
/// than it being forced on every brand by the default.
final List<String> kDefaultRegistrationFields = kUserRequiredRegistrationFields;

// ⚠️ Known backend bug, confirmed 22/09/2026, NOT fixed as of 24/09 — but see
// the 24/09 chat thread asking for this to be re-verified against whatever
// backend build is actually current before trusting this note further:
// `phoneNum`'s uniqueness constraint does not appear to exempt null/empty
// values — two registrations that both omit it fail the second with
// `error.subscriber phone number exists`. `phoneNum` is optional in every
// sense the socle can see (`kFieldSpecs['phoneNum']` in
// `account_controllers.dart`), so a brand is free to drop it from
// `registration.fields` entirely, but doing so means the SECOND person who
// ever signs up without a phone number on that brand hits this collision in
// production. Sabily's 24/09 field set (see `brands/sabily/brand.json`) does
// exactly this and ships anyway, because the field removal is a product
// decision already made — this is filed as a live backend defect to fix, not
// a reason to keep a field product asked to remove. See
// `claude/demandes-backend-mobile.md`, "constats additionnels du 22/09".

/// Password rules, mirrored from the deployed `SubscriberModel`:
/// `@Size(min: 8, message: "Password must be longer than 7 characters")` and
/// `@Pattern(^(?=.*[a-z])(?=.*[A-Z])(?=.*[^a-zA-Z0-9]).*$)`.
///
/// Mirrored client-side so a user is told before submitting rather than after
/// a round trip. The server stays the authority; this only avoids wasting the
/// user's time. Note it does NOT require a digit — matching the server exactly
/// matters more than matching a habit.
const int kPasswordMinLength = 8;
final RegExp kPasswordPattern = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*[^a-zA-Z0-9]).*$');

/// One page of a multi-step registration. §2.9.
///
/// Steps GROUP fields that `registration.fields` already declared. They never
/// add a field, never remove one, and never change how one is validated — the
/// deployed `SubscriberModel` decides that, and it does not care how many
/// screens the user crossed to fill the form in.
///
/// `title` is a dictionary key, resolved through the normal override chain, so
/// a client that wants its own wording puts it in `texts` rather than in a
/// string here (which would put one brand's copy in every brand's build).
class RegistrationStep {
  final String titleKey;
  final List<String> fields;

  const RegistrationStep({required this.titleKey, required this.fields});
}

class BrandMobile {
  final String applicationId;
  final String bundleIdentifier;
  final String displayName;
  final String deepLinkScheme;
  final List<String> universalLinkHosts;
  final String apiBaseUrl;
  final String stripePublishableKey;
  final String? merchantIdentifier;
  final String? merchantCountryCode;
  final String? remoteConfigUrl;
  final String? minimumSupportedVersion;

  /// The image behind a destination card's art, from this brand's own
  /// `assets/` folder.
  ///
  /// Per brand, never hardcoded: the card is shared by every white-label app
  /// and each one ships its own ground. Absent -> the card falls back to the
  /// painted colour wash, which is what a brand that has not supplied one
  /// should get rather than another client's picture.
  final String? cardBackground;

  /// The OAuth **web** client ID of the backend's Google project, which is
  /// what "Continue with Google" needs and what the ID token is minted for.
  ///
  /// Absent -> the button is not offered. Deliberate: on Android the SDK
  /// cannot produce an ID token at all without it, so a brand that has not
  /// been given one would show a button that always fails. Per brand, because
  /// two clients are two Google projects.
  final String? googleServerClientId;

  /// The destinations the Store shelf offers first, as alpha-3 codes.
  ///
  /// Empty -> the shelf falls back to the destinations carrying the most
  /// packs. That fallback is a proxy for coverage, NOT for popularity: for a
  /// pilgrimage brand it produced Denmark, Norway and Sweden under a heading
  /// that said "popular with pilgrims", which is worse than saying nothing.
  /// Which destinations a brand wants to push is the brand's decision, and
  /// no endpoint ranks them, so it lives here.
  final List<String> popularDestinations;

  final List<String> registrationFields;

  /// Empty means one page with every field on it — exactly the behaviour of
  /// every config written before steps existed.
  ///
  /// REQUIRED, deliberately. It began with a `const []` default, and the
  /// build-override path — which rebuilds this object field by field — simply
  /// never passed it. The wizard silently became a single form on every build
  /// carrying `--dart-define=API_BASE_URL`, which is every development build,
  /// and no test noticed because tests parse the config directly. A required
  /// parameter turns that into a compile error.
  final List<RegistrationStep> registrationSteps;

  /// Only the named fields change; everything else is carried over. The one
  /// safe way to derive a variant of this object. `null` means "leave it",
  /// which is what lets a build override one value without blanking the other.
  BrandMobile copyWith({String? apiBaseUrl, String? stripePublishableKey}) => BrandMobile(
        applicationId: applicationId,
        bundleIdentifier: bundleIdentifier,
        displayName: displayName,
        deepLinkScheme: deepLinkScheme,
        universalLinkHosts: universalLinkHosts,
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        stripePublishableKey: stripePublishableKey ?? this.stripePublishableKey,
        merchantIdentifier: merchantIdentifier,
        merchantCountryCode: merchantCountryCode,
        remoteConfigUrl: remoteConfigUrl,
        minimumSupportedVersion: minimumSupportedVersion,
        cardBackground: cardBackground,
        googleServerClientId: googleServerClientId,
        popularDestinations: popularDestinations,
        registrationFields: registrationFields,
        registrationSteps: registrationSteps,
      );

  const BrandMobile({
    required this.applicationId,
    required this.bundleIdentifier,
    required this.displayName,
    required this.deepLinkScheme,
    required this.universalLinkHosts,
    required this.apiBaseUrl,
    required this.stripePublishableKey,
    required this.merchantIdentifier,
    required this.merchantCountryCode,
    required this.remoteConfigUrl,
    required this.minimumSupportedVersion,
    required this.cardBackground,
    required this.googleServerClientId,
    required this.popularDestinations,
    required this.registrationFields,
    required this.registrationSteps,
  });

  /// Apple Pay only makes sense with both a merchant id and a country.
  bool get walletsAvailable => merchantIdentifier != null && merchantCountryCode != null;

  static BrandMobile? _parse(Map<String, dynamic>? json, BrandProblems p) {
    if (json == null) return null;
    String? req(String k) => _string(json, k, p, required: true, path: 'mobile.$k');

    final applicationId = req('applicationId');
    final bundleIdentifier = req('bundleIdentifier');
    final displayName = req('displayName');
    final deepLinkScheme = req('deepLinkScheme');
    final apiBaseUrl = _url(json, 'apiBaseUrl', 'mobile.apiBaseUrl', p, required: true);

    // §2.9 — the two lines that are worth more than an irreversible incident.
    final pk = _string(json, 'stripePublishableKey', p,
        required: true, path: 'mobile.stripePublishableKey');
    if (pk != null) {
      if (pk.startsWith('sk_')) {
        p.error(
          'mobile.stripePublishableKey',
          'this is a Stripe SECRET key. It must never ship in an app bundle — '
              'an .apk decompiles and an .ipa unpacks. Use the pk_ key.',
        );
      } else if (!pk.startsWith('pk_')) {
        p.error('mobile.stripePublishableKey', 'must start with "pk_"');
      }
    }

    final merchantId = _string(json, 'merchantIdentifier', p, path: 'mobile.merchantIdentifier');
    if (merchantId != null && !merchantId.startsWith('merchant.')) {
      p.error('mobile.merchantIdentifier', 'an Apple merchant id starts with "merchant."');
    }
    final merchantCountry =
        _string(json, 'merchantCountryCode', p, path: 'mobile.merchantCountryCode');
    if (merchantId != null && merchantCountry == null) {
      p.warn('mobile.merchantCountryCode',
          'a merchant id is set but no country; wallets will stay disabled');
    }

    final remoteConfigUrl = _url(json, 'remoteConfigUrl', 'mobile.remoteConfigUrl', p);

    final rawFields = json['registration'] is Map
        ? (json['registration'] as Map).cast<String, dynamic>()['fields']
        : null;
    var fields = kDefaultRegistrationFields;
    if (rawFields != null) {
      final requested = _stringList(rawFields, 'mobile.registration.fields', p);
      final kept = <String>[];
      for (final f in requested) {
        if (kKnownRegistrationFields.contains(f)) {
          kept.add(f);
        } else {
          p.warn('mobile.registration.fields',
              'unknown field "$f"; the socle has no widget for it, so it is ignored');
        }
      }
      final missing =
          kUserRequiredRegistrationFields.where((f) => !kept.contains(f)).toList();
      if (missing.isNotEmpty) {
        p.error(
          'mobile.registration.fields',
          'the backend rejects a registration without ${missing.join(', ')}. '
              'Omitting a server-required field does not make it optional — it '
              'makes every sign-up fail with a 400.',
        );
      }
      fields = kept;
    }

    // Steps are optional. Absent, the form stays one page.
    final rawSteps = json['registration'] is Map
        ? (json['registration'] as Map).cast<String, dynamic>()['steps']
        : null;
    var steps = const <RegistrationStep>[];
    if (rawSteps != null) {
      steps = _registrationSteps(rawSteps, fields, p);
    }

    // The iOS OAuth client. Read by the iOS build (xcconfig -> Info.plist
    // GIDClientID), never by Dart, so it is checked here and not stored:
    // Studio's form and the app then enforce one set of rules.
    final serverClient =
        _string(json, 'googleServerClientId', p, path: 'mobile.googleServerClientId');
    final iosClient = _string(json, 'googleIosClientId', p, path: 'mobile.googleIosClientId');
    if (iosClient != null && !iosClient.endsWith('.apps.googleusercontent.com')) {
      p.error('mobile.googleIosClientId',
          'an OAuth client id ends with ".apps.googleusercontent.com"');
    } else if (iosClient != null && iosClient == serverClient) {
      p.error('mobile.googleIosClientId',
          'this is the web client (googleServerClientId); iOS needs its own client, of type iOS');
    }
    if (serverClient != null && iosClient == null) {
      p.warn('mobile.googleIosClientId',
          'Google sign-in is offered with no iOS client: on iOS the button fails on every tap');
    }

    if (applicationId == null ||
        bundleIdentifier == null ||
        displayName == null ||
        deepLinkScheme == null ||
        apiBaseUrl == null ||
        pk == null) {
      return null;
    }

    return BrandMobile(
      applicationId: applicationId,
      bundleIdentifier: bundleIdentifier,
      displayName: displayName,
      deepLinkScheme: deepLinkScheme,
      universalLinkHosts: _stringList(json['universalLinkHosts'], 'mobile.universalLinkHosts', p),
      apiBaseUrl: apiBaseUrl,
      stripePublishableKey: pk,
      merchantIdentifier: merchantId,
      merchantCountryCode: merchantCountry,
      remoteConfigUrl: remoteConfigUrl,
      minimumSupportedVersion:
          _string(json, 'minimumSupportedVersion', p, path: 'mobile.minimumSupportedVersion'),
      cardBackground: _string(json, 'cardBackground', p, path: 'mobile.cardBackground'),
      googleServerClientId: serverClient,
      popularDestinations: _stringList(
        json['popularDestinations'],
        'mobile.popularDestinations',
        p,
      ),
      registrationFields: fields,
      registrationSteps: steps,
    );
  }
}

/// Reads `registration.steps` and checks it against the fields already parsed.
///
/// The checks exist because a mis-grouped step fails the same way a short field
/// list does — silently, at sign-up, with a 400. A field that no step names is
/// a field the user is never shown and the server still demands.
List<RegistrationStep> _registrationSteps(
  Object? raw,
  List<String> fields,
  BrandProblems p,
) {
  const path = 'mobile.registration.steps';
  if (raw is! List) {
    p.error(path, 'expected a list of steps');
    return const <RegistrationStep>[];
  }

  final out = <RegistrationStep>[];
  final placed = <String>{};

  for (var i = 0; i < raw.length; i++) {
    final entry = raw[i];
    if (entry is! Map) {
      p.error('$path[$i]', 'expected an object with "title" and "fields"');
      continue;
    }
    final map = entry.cast<String, dynamic>();
    final title = map['title'];
    if (title is! String || title.isEmpty) {
      p.error('$path[$i].title', 'a step needs a title key');
      continue;
    }

    final stepFields = _stringList(map['fields'], '$path[$i].fields', p);
    final kept = <String>[];
    for (final f in stepFields) {
      if (!fields.contains(f)) {
        p.error('$path[$i].fields',
            'step names "$f", which is not in registration.fields. A step groups '
            'fields that already exist; it cannot introduce one.');
        continue;
      }
      if (!placed.add(f)) {
        p.error('$path[$i].fields',
            '"$f" appears on more than one step; the user would be asked twice '
            'and the second answer would win.');
        continue;
      }
      kept.add(f);
    }

    if (kept.isEmpty) {
      p.warn('$path[$i]', 'step "$title" has no fields and would render empty');
      continue;
    }
    out.add(RegistrationStep(titleKey: title, fields: kept));
  }

  final stranded = fields.where((f) => !placed.contains(f)).toList();
  if (stranded.isNotEmpty) {
    p.error(
      path,
      'no step shows ${stranded.join(', ')}. A field the user never sees is '
          'still a field the backend requires, so every sign-up would fail with '
          'a 400 — the same way a short registration.fields does.',
    );
  }

  return out;
}

// ---------------------------------------------------------------------------
// Primitive readers. Each records a problem instead of throwing, so one pass
// reports everything (§2.10).
// ---------------------------------------------------------------------------

String? _string(
  Map<String, dynamic> json,
  String key,
  BrandProblems p, {
  bool required = false,
  String? path,
}) {
  final field = path ?? key;
  final v = json[key];
  if (v == null) {
    if (required) p.error(field, 'is required');
    return null;
  }
  if (v is! String) {
    p.error(field, 'must be a string');
    return null;
  }
  if (v.isEmpty) {
    if (required) p.error(field, 'is required and must not be empty');
    return null;
  }
  return v;
}

Map<String, dynamic>? _map(
  Map<String, dynamic> json,
  String key,
  BrandProblems p, {
  bool required = false,
}) {
  final v = json[key];
  if (v == null) {
    if (required) p.error(key, 'is required');
    return null;
  }
  if (v is! Map) {
    p.error(key, 'must be an object');
    return null;
  }
  return v.cast<String, dynamic>();
}

List<String> _stringList(Object? v, String field, BrandProblems p, {bool required = false}) {
  if (v == null) {
    if (required) p.error(field, 'is required');
    return const [];
  }
  if (v is! List) {
    p.error(field, 'must be an array');
    return const [];
  }
  final out = <String>[];
  for (final e in v) {
    if (e is String) {
      out.add(e);
    } else {
      p.error(field, 'must contain only strings');
    }
  }
  if (required && out.isEmpty) p.error(field, 'must not be empty');
  return out;
}

Map<String, String> _langMap(Object? v, String field, BrandProblems p) {
  if (v == null) return const {};
  if (v is! Map) {
    p.error(field, 'must be an object of { language: text }');
    return const {};
  }
  final out = <String, String>{};
  for (final e in v.entries) {
    if (e.value is String) {
      out[e.key.toString()] = e.value as String;
    } else {
      p.error('$field.${e.key}', 'must be a string');
    }
  }
  return out;
}

final _hex = RegExp(r'^#([0-9a-fA-F]{6})$');

Color? _color(
  Map<String, dynamic> json,
  String key,
  String field,
  BrandProblems p, {
  bool required = false,
}) {
  final raw = _string(json, key, p, required: required, path: field);
  if (raw == null) return null;
  final m = _hex.firstMatch(raw);
  if (m == null) {
    p.error(field, '"$raw" is not a #RRGGBB colour');
    return null;
  }
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

String? _url(
  Map<String, dynamic> json,
  String key,
  String field,
  BrandProblems p, {
  bool required = false,
}) {
  final raw = _string(json, key, p, required: required, path: field);
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || !uri.isAbsolute) {
    p.error(field, '"$raw" is not an absolute URL');
    return null;
  }
  if (uri.scheme != 'https') {
    p.error(field, 'must be https, not "${uri.scheme}"');
    return null;
  }
  return raw;
}
