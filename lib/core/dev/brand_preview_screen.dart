import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand/brand_config.dart';
import '../brand/brand_loader.dart';
import '../brand/brand_providers.dart';
import '../i18n/locales.dart';
import '../theme/app_theme.dart';

/// The J3 milestone screen (ARCHITECTURE-MOBILE.md §13.4 step 2).
///
/// It renders NOTHING of its own: every colour, every string, the logo and the
/// language list all come from [BrandConfig]. That is the point — it is the
/// first verifiable proof that the socle is configuration-driven.
///
/// It is replaced as `/` by the catalog module at step 3. It stays afterwards
/// as a QA surface, which is also where the version marker lives: brief §7.7's
/// "a fix that was never deployed" is caught by a visible marker, and the old
/// app shipped a version number matching neither of the two in its own repo
/// (`ARCHITECTURE-MOBILE.md` §9.7).
class BrandPreviewScreen extends ConsumerWidget {
  const BrandPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandConfigProvider);
    final l10n = ref.watch(l10nProvider);
    final language = ref.watch(languageProvider);
    final source = ref.watch(brandSourceProvider);
    final t = AppTokens.of(context);
    final registry = ref.watch(moduleRegistryProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            _Header(brand: brand),
            const SizedBox(height: Gap.xl),
            Text(l10n.t('startup.welcome'), style: AppType.display),
            const SizedBox(height: Gap.xs),
            Text(l10n.t('startup.subtitle'), style: AppType.body.copyWith(color: t.inkMuted)),
            const SizedBox(height: Gap.sm),
            Text(
              brand.tagline[language] ?? brand.tagline[brand.defaultLocale] ?? l10n.t('app.tagline'),
              style: AppType.body,
            ),
            const SizedBox(height: Gap.xl),
            _SectionTitle(l10n.t('common.language')),
            const SizedBox(height: Gap.sm),
            const _LanguagePicker(),
            const SizedBox(height: Gap.xl),
            const _SectionTitle('Colour roles'),
            const SizedBox(height: Gap.sm),
            const _Swatches(),
            const SizedBox(height: Gap.xl),
            const _SectionTitle('Type scale'),
            const SizedBox(height: Gap.sm),
            _TypeSpecimen(),
            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: () {},
              child: Text(l10n.t('common.continue')),
            ),
            const SizedBox(height: Gap.xl),
            _Diagnostics(brand: brand, source: source, moduleCount: registry.active.length),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final BrandConfig brand;
  const _Header({required this.brand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    return Row(
      children: [
        // Resolved through the config: no path in lib/ carries a client slug.
        Image.asset(
          brand.assetPath(brand.logo.mark),
          height: 56,
          width: 56,
          errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: t.danger),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(brand.name, style: AppType.title.copyWith(color: t.primary)),
              Text(brand.legal.displayName, style: AppType.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(text, style: AppType.heading);
}

class _LanguagePicker extends ConsumerWidget {
  const _LanguagePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandConfigProvider);
    final current = ref.watch(languageProvider);
    final t = AppTokens.of(context);

    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        // Only the languages THIS brand serves. The socle's list is not the
        // authority (§2.5).
        for (final code in brand.locales)
          ChoiceChip(
            selected: code == current,
            onSelected: (_) => ref.read(languageProvider.notifier).set(code),
            label: Text(kLanguageEndonyms[code] ?? code),
            labelStyle: AppType.label,
            selectedColor: t.accent,
            backgroundColor: t.card,
            side: BorderSide(color: t.hairline),
          ),
      ],
    );
  }
}

class _Swatches extends ConsumerWidget {
  const _Swatches();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final roles = <String, Color>{
      'primary': t.primary,
      'accent': t.accent,
      'surface': t.surface,
      'cta': t.cta,
      'ctaText': t.ctaText,
      'premium': t.premiumAccent,
    };
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        for (final e in roles.entries)
          Column(
            children: [
              Container(
                width: 64,
                height: 48,
                decoration: BoxDecoration(
                  color: e.value,
                  borderRadius: BorderRadius.circular(Gap.sm),
                  border: Border.all(color: t.hairline),
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(e.key, style: AppType.caption),
            ],
          ),
      ],
    );
  }
}

class _TypeSpecimen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Display', style: AppType.display),
          Text('Title', style: AppType.title),
          Text('Heading', style: AppType.heading),
          Text('Body — العربية والفرنسية معًا', style: AppType.body),
          Text('Label', style: AppType.label),
          Text('Caption', style: AppType.caption),
        ],
      );
}

/// The version marker. Brief §7.7: *if this value is wrong, does it show?*
class _Diagnostics extends StatelessWidget {
  final BrandConfig brand;
  final BrandSource source;
  final int moduleCount;

  const _Diagnostics({
    required this.brand,
    required this.source,
    required this.moduleCount,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final rows = <String, String>{
      'slug': brand.slug,
      'applicationId': brand.mobile.applicationId,
      'backend': brand.mobile.apiBaseUrl,
      'config source': source.name,
      'locales': brand.locales.join(' '),
      'default': brand.defaultLocale,
      'currency': brand.currency,
      'wallet': brand.features.wallet.toString(),
      'active modules': moduleCount.toString(),
    };
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Gap.md),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${e.key}: ${e.value}', style: AppType.caption),
            ),
        ],
      ),
    );
  }
}
