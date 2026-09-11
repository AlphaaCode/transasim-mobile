import 'package:flutter/painting.dart' show Color;

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

  const BrandThemeTokens({this.premiumSurface, this.premiumAccent, this.premiumText});

  bool get hasPremiumOverrides =>
      premiumSurface != null || premiumAccent != null || premiumText != null;

  static BrandThemeTokens _parse(Map<String, dynamic>? json, BrandProblems p) {
    if (json == null) return const BrandThemeTokens();
    final premium = json['premium'];
    if (premium == null) return const BrandThemeTokens();
    if (premium is! Map) {
      p.error('theme.premium', 'must be an object');
      return const BrandThemeTokens();
    }
    final m = premium.cast<String, dynamic>();
    for (final k in m.keys) {
      if (!const {'surface', 'accent', 'text'}.contains(k)) {
        p.warn('theme.premium.$k', 'unknown premium token; it will be ignored');
      }
    }
    return BrandThemeTokens(
      premiumSurface: _color(m, 'surface', 'theme.premium.surface', p),
      premiumAccent: _color(m, 'accent', 'theme.premium.accent', p),
      premiumText: _color(m, 'text', 'theme.premium.text', p),
    );
  }
}

class BrandLogo {
  final String mark;
  final String full;

  /// Variant for dark backgrounds. Absent -> [full] is used, with a warning.
  final String? fullInverse;

  const BrandLogo({required this.mark, required this.full, this.fullInverse});

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
    if (mark == null || full == null) return null;
    return BrandLogo(mark: mark, full: full, fullInverse: inverse);
  }
}

class BrandVisuals {
  final String? heroBackground;
  final String? heroBackgroundSmall;

  /// "How it works" artwork. §2.4 and brief §4.4: a mirrored composition is
  /// unreadable, so LTR and RTL are two RECOMPOSED images, not one flipped.
  final String? howItWorksLtr;
  final String? howItWorksRtl;

  const BrandVisuals({
    this.heroBackground,
    this.heroBackgroundSmall,
    this.howItWorksLtr,
    this.howItWorksRtl,
  });

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

  const BrandSupport({required this.email, required this.hours});

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
    if (email == null) return null;
    return BrandSupport(email: email, hours: hours);
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

/// What the LIVE backend refuses to register without.
///
/// Read off `SubscriberModel` in the deployed JAR: every one of these carries
/// `@NotNull`, so a request missing any of them is rejected with a 400 before
/// it reaches any business logic. Eleven fields, exactly as brief §8.4 warned.
///
/// ⚠️ Brief §8.4 also records a filed request to cut this to four. It is filed,
/// NOT shipped. This list tracks what is deployed; when the backend actually
/// changes, this constant is the single thing to edit — and the validation
/// below will immediately tell every brand whether its config still fits.
const List<String> kServerRequiredRegistrationFields = <String>[
  'title',
  'email',
  'firstName',
  'lastName',
  'dateOfBirth',
  'address',
  'zipCode',
  'language',
  'city',
  'country',
  'password',
];

/// Of those eleven, three are supplied by the app rather than typed by a user:
///
///  - `language` — the interface language in use;
///  - `platform` — IOS / ANDROID (optional server-side, sent anyway);
///  - `title`    — a salutation. The live app sends `null` here, which the
///    deployed `@NotNull` should reject; the socle sends an empty string
///    instead, which satisfies the constraint under either reading. Flagged as
///    a backend question rather than guessed at.
const Set<String> kAppSuppliedRegistrationFields = <String>{'language', 'title'};

/// The nine a person actually has to fill in. A brand whose `registration.fields`
/// omits any of these cannot register anyone, so it is a configuration ERROR
/// rather than a 400 discovered in production.
final List<String> kUserRequiredRegistrationFields = kServerRequiredRegistrationFields
    .where((f) => !kAppSuppliedRegistrationFields.contains(f))
    .toList(growable: false);

/// The socle's default when a brand says nothing: exactly what the live backend
/// requires of a user, and nothing more.
final List<String> kDefaultRegistrationFields = kUserRequiredRegistrationFields;

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
  final List<String> registrationFields;

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
    required this.registrationFields,
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
      registrationFields: fields,
    );
  }
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
