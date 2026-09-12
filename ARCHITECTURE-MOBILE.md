# ARCHITECTURE-MOBILE — Socle Flutter white-label TRANSASIM

> **Phase 2** du chantier décrit dans `BRIEF-MOBILE-WHITE-LABEL.md` (§6.2).
> **Livrable bloquant (J2).** Aucun code applicatif n'est écrit avant validation de ce document par le client.
> **Date :** 10 septembre 2026.
> **Critère de validation (§6.2 du brief) :** un développeur extérieur au projet doit pouvoir, en lisant ce seul document, ajouter un client fictif sans poser de question sur la structure. Le §11 est le test de ce critère.

---

## 0. Décisions d'entrée, et ce qu'elles retirent du périmètre

Deux arbitrages ont été rendus par le client avant la rédaction de ce document. Ils ne sont pas rediscutés ici.

| Décision | Portée |
|---|---|
| **Pile : Flutter propre, dépôt neuf** | Ni migration de `Sabily-mobile`, ni continuation de `rebuild/expo`. Cette dernière est mise de côté, non supprimée ; **rien n'en est repris**. |
| **Périmètre : BtoC exclusivement** | Le module `reseller` et le drapeau `features.b2b` du §5.1/§5.6 du brief sont **retirés de cette architecture** : ni construits, ni ébauchés, ni désactivés par drapeau. Si le BtoB arrive un jour sur mobile, ce sera une décision distincte avec son propre document. |

**Ce que la décision BtoC ne change pas :** le contrat `AppModule` (§4), le module squelette `wallet` pour TransaPay, et la règle de dépendance entre couches. Le mécanisme de modularité reste exigé par le §3.3 critère 6 du brief — il est simplement démontré par `wallet` plutôt que par `reseller`.

### 0.1 Ce qui est repris de l'existant, et sous quelle forme

Rien n'est copié. Ce qui traverse, ce sont des **contrats et des patrons**, réimplémentés :

| Objet repris | Forme de reprise | Référence |
|---|---|---|
| Les 18 endpoints vivants | Contrat documenté, client réécrit | `handoff/api-contract.md` §10 |
| Le contrat d'activation eSIM `LPA:1$<smdpAddress>$<matchingId>` | **Tel quel** — correct, standard GSMA SGP.22, indépendant du cadre | `ANALYSE-EXISTANT.md` §6.1 |
| Le patron Stripe PaymentSheet en deux temps | Patron repris, **première moitié construite pour de bon** (§6.3) | `ANALYSE-EXISTANT.md` §7.0 |
| Le découpage client → dépôt | Concept repris, réimplémenté sous Riverpod | `ANALYSE-EXISTANT.md` §2.1 |
| Les intentions des 24 fichiers de test | Intentions reprises, code non portable | §8.6 |

### 0.2 Nom du paquet Dart — décision, et pourquoi elle compte

Le dossier conteneur s'appelle `new sabily app`. **Ce n'est pas le nom du projet.**

> **Nom du paquet Dart retenu : `transasim_mobile`.**

Ce n'est pas cosmétique. `ANALYSE-EXISTANT.md` §4.2 a mesuré **527 occurrences de `import 'package:sabily_mobile/…'` réparties sur 115 fichiers** dans l'ancien dépôt. Un paquet nommé d'après un client réintroduit mécaniquement cette dette dans chaque fichier du socle, et fait échouer le critère §3.3.3 du brief (`grep -ri "sabily"` dans `lib/` ne renvoie rien hors du dossier de configuration de Sabily) **avant même la première ligne de code métier**.

Le socle appartient à TRANSASIM ; les clients sont des configurations. Le nom du paquet suit la propriété du code, pas celle du premier client.

Commande de création correspondante, **à n'exécuter qu'après validation de ce document** :

```bash
flutter create --project-name transasim_mobile --org com.transasim \
               --platforms=android,ios --template=app .
```

⚠️ **Deux points d'exploitation à trancher au démarrage (§12) :**

- **L'espace dans le nom du dossier.** Flutter accepte `--project-name`, mais les espaces dans un chemin de projet restent une source connue de pannes en aval (scripts de build CocoaPods, certaines tâches Gradle, chemins non échappés en CI). **Recommandation : renommer le dossier en `transasim-mobile`.** Coût nul aujourd'hui, coût non nul le jour où un script tiers casse.
- **Aucune chaîne d'outils Flutter n'est installée sur la machine de travail** (`flutter` et `dart` absents du `PATH`, aucun JDK). À installer avant la phase 3 ; sans cela ni build, ni test, ni `flutter analyze` ne sont exécutables.

---

## 1. Structure de dossiers et règle de dépendance

### 1.1 Arborescence

```
transasim-mobile/
├── lib/
│   ├── main_common.dart              ← point d'entrée paramétré, un seul
│   ├── flavors/
│   │   └── main_sabily.dart          ← void main() => bootstrap('sabily');
│   ├── core/                         ← LE NOYAU. Ne connaît aucun module.
│   │   ├── brand/                    ← BrandConfig, chargeur, validation, repli, cache
│   │   ├── theme/                    ← ThemeData DÉRIVÉ de BrandConfig
│   │   ├── i18n/                     ← dictionnaires communs + surcharges de marque
│   │   ├── network/                  ← client HTTP unique, intercepteurs, erreurs typées
│   │   ├── session/                  ← jeton, stockage sécurisé, expiration
│   │   ├── router/                   ← GoRouter + enregistrement des routes par module
│   │   ├── modules/                  ← contrat AppModule + registre
│   │   ├── result/                   ← Result/Either, erreurs de domaine
│   │   └── telemetry/                ← journalisation filtrée, rapport d'erreurs
│   ├── modules/                      ← LES MODULES. Ne se connaissent pas entre eux.
│   │   ├── catalog/
│   │   ├── account/
│   │   ├── esim/
│   │   ├── checkout/
│   │   └── wallet/                   ← squelette TransaPay, actif si features.wallet
│   └── shared/                       ← widgets communs, formatage, extensions
├── brands/
│   └── sabily/
│       ├── brand.json                ← la configuration du client
│       ├── assets/                   ← logos, visuels, icône, écran de lancement
│       └── README.md                 ← les décisions que le JSON ne peut pas porter
├── tool/
│   ├── check_brands.dart             ← validation hors ligne, exécutable en CI
│   ├── build_brand.sh                ← un script produit un client
│   └── check_layers.dart             ← fait échouer la CI sur violation de couche
├── test/
└── integration_test/
```

Le dossier `brands/` **reprend délibérément le nom et la structure du socle web** (§5.2 du brief) : un client se décrit une fois pour les deux socles, et tout écart entre son site et son application se voit par simple comparaison de deux fichiers.

### 1.2 Structure interne d'un module

```
modules/esim/
├── domain/            ← entités, contrats de dépôt, cas d'usage. AUCUNE dépendance externe.
├── data/              ← implémentations, DTO, sources distantes/locales, mapping
├── presentation/      ← écrans, widgets, contrôleurs Riverpod
└── esim_module.dart   ← déclaration du module (id, routes, onglets, providers)
```

**Pourquoi cette séparation, concrètement.** Ce n'est pas un rituel. C'est ce qui permet (a) de tester la logique métier sans widget ni réseau, et (b) de **détacher un module**. Un cas d'usage qui dépend d'un `BuildContext` ou d'un client HTTP concret n'est pas déplaçable vers TransaPay ; un cas d'usage qui dépend d'un contrat de dépôt l'est.

### 1.3 La règle de dépendance — et son application mécanique

> **Le noyau ne connaît aucun module. Les modules ne se connaissent pas entre eux. Un module qui a besoin d'un autre passe par un contrat exposé dans le noyau.**

C'est ce qui rend un module réellement retirable, et donc un drapeau réellement honnête.

Une règle écrite dans un guide de style ne tient pas six mois (§7.5 du brief). Elle est donc **appliquée par la CI**, via `tool/check_layers.dart`, qui fait échouer la construction sur l'une de ces quatre violations :

| # | Règle | Détection |
|---|---|---|
| L1 | `lib/core/**` n'importe jamais `package:transasim_mobile/modules/` | grep d'import |
| L2 | `lib/modules/<a>/**` n'importe jamais `package:transasim_mobile/modules/<b>/` | grep d'import croisé |
| L3 | `lib/modules/*/domain/**` n'importe ni `package:flutter/`, ni `dart:io`, ni `package:http/`, ni `../data/` | grep d'import |
| L4 | `lib/modules/**` n'importe jamais `dart:io`/`package:http` directement — le réseau passe par `core/network` | grep d'import |

Quatre `grep`. C'est la défense la moins chère qui résiste à la pression de livraison.

### 1.4 Ce que le noyau expose aux modules

Le noyau n'a aucune connaissance des modules, mais il leur offre un contrat stable :

| Contrat | Rôle |
|---|---|
| `BrandConfig` (via provider) | Toute valeur de marque. Injectée, jamais globale mutable. |
| `AppTheme` | Jetons dérivés. Aucun module ne construit une couleur. |
| `L10n` | Résolution surcharge de marque → dictionnaire commun. |
| `ApiClient` | La seule sortie réseau. URL de base issue de la configuration. |
| `Session` | Jeton, identité, expiration. |
| `AppRouter` | Enregistrement des routes déclarées par les modules actifs. |
| `Result<T>` / `AppError` | Erreurs typées, traduites au bord. |
| `Telemetry` | Journalisation filtrée (§10.4). |

---

## 2. Le contrat `BrandConfig`, champ par champ

Le format est **JSON, avec les noms de champs du socle web** (§5.3 du brief). Le gain est immédiat : la configuration d'un client se rédige une fois pour les deux socles, et la console de provisioning à venir n'a qu'un format à produire.

Ce qui est propre au mobile vit dans un bloc `mobile` séparé, pour que la parenté reste lisible.

**Convention de lecture du tableau :** « Absent → » décrit le comportement réel du socle quand le champ manque. **Erreur** = la marque est refusée et nommée dans les journaux. **Avertissement** = la marque fonctionne mais une partie de la configuration est inerte — c'est exactement le cas où un client rappelle en disant que sa demande n'a pas été prise en compte (§2.8 du brief).

### 2.1 Identité

| Champ | Type | Obl. | Absent → | Pourquoi il existe |
|---|---|---|---|---|
| `slug` | `string` | ✅ | **Erreur** | Identifiant technique. **Doit être égal au nom du dossier** — vérifié à la validation. C'est la clé de tout : flavor, assets, secrets de CI. |
| `name` | `string` | ✅ | **Erreur** | Nom commercial affiché. Interpolé partout via `{brand}` — **jamais écrit dans un dictionnaire** (§3 du brief §7.1). |
| `tagline` | `{lang: string}` | ⬜ | Aucune signature affichée | Baseline par langue. Optionnel parce qu'une marque peut n'en avoir aucune. |
| `domain` | `string` | ⬜ | Les liens web relatifs sont désactivés | Domaine canonique du client. Sert aux liens sortants et à recouper avec `mobile.universalLinkHosts`. |

### 2.2 Couleurs — cinq rôles, et pourquoi exactement cinq

```jsonc
"colors": {
  "primary":  "#003c3a",  // ancrage : texte fort, aplats sombres, barres
  "accent":   "#d2f5ec",  // symbole, états positifs, éléments actifs
  "surface":  "#f9f2d3",  // fond de marque, teinté
  "cta":      "#fadb14",  // appel à l'action, contraste fort attendu sur primary
  "ctaText":  "#003c3a"   // texte posé sur un fond CTA
}
```

| Champ | Type | Obl. | Absent → |
|---|---|---|---|
| `colors.primary` | `#RRGGBB` | ✅ | **Erreur** |
| `colors.accent` | `#RRGGBB` | ✅ | **Erreur** |
| `colors.surface` | `#RRGGBB` | ✅ | **Erreur** |
| `colors.cta` | `#RRGGBB` | ✅ | **Erreur** |
| `colors.ctaText` | `#RRGGBB` | ✅ | **Erreur** |

**Les couleurs sont définies par rôle, jamais par teinte.** `primary` ne veut pas dire « vert » : il veut dire « la couleur d'ancrage ». Le jour où un client arrive en bleu nuit, rien ne s'appelle `vertSabily`.

**Arbitrage effectué — à valider explicitement.** `ANALYSE-EXISTANT.md` §5.7 a constaté que le Figma porte **trois palettes différentes pour un seul client** (`#004d40`, `#003c3a`, `#114c49`) et **aucune variable Figma**. Le tableau ci-dessus tranche en faveur du lot du 10 septembre, et fait entrer la palette cible dans les cinq rôles du web **sans en inventer un sixième** :

| Palette de la charte | Rôle web retenu | Justification |
|---|---|---|
| Vert profond `#003c3a` | `primary` | Ancrage |
| Menthe `#d2f5ec` | `accent` | Le commentaire du contrat web dit « symbole, états positifs, éléments actifs » — c'est exactement l'usage de la menthe dans les maquettes |
| Crème `#f9f2d3` | `surface` | « Fond de marque, teinté » |
| Jaune `#fadb14` | `cta` | « Appel à l'action, contraste fort attendu sur primary » — c'est le bouton « Buy Now » et l'onglet actif |
| Bronze `#735c00` | **pas un rôle** → `theme.premium` | Voir §2.3 |

Ce mapping est le point le plus important à faire relire par le design : il fixe la sémantique pour tous les clients à venir.

#### 2.2.1 La dérive se confirme, et le lot *desktop* donne raison au §2.2

Constaté en tirant les valeurs réelles des écrans `Welcome` (63:533), `Log In`
(52:519) et `Sign Up` (52:369) via `get_design_context`, puis en comparant au
`Sign Up - Sabily` **desktop** (47:2486) :

| Valeur | Lot **mobile** | Lot **desktop** | §2.2 |
|---|---|---|---|
| Vert | `#004d40` | `#003c3a` | **`#003c3a`** |
| Crème | `#fff9e8` | `#f9f2d3` | **`#f9f2d3`** |

Le desktop utilise **déjà les deux valeurs canoniques**. Ce n'est donc pas un
arbitrage entre deux lots également défendables : le lot mobile est le seul à
diverger, sur les deux couleurs à la fois. Le §2.2 est confirmé.

Trois précisions qui évitent de refaire l'enquête au prochain écran :

- `#fff9e8` **n'est pas disponible**. C'est déjà `premiumSurface` (§2.3), le
  crème volontairement détaché du registre premium. L'écrire comme fond
  d'authentification ferait porter aux écrans de compte le crème du registre
  premium, par accident.
- Le code résout vers les bonnes valeurs dans les deux cas : le fond
  d'authentification est un dégradé `accent → surface`, donc il **termine
  exactement** sur le `#f9f2d3` littéral de `Log In`. Seuls `Welcome` et
  `Sign Up` rendent un crème ~2 % plus soutenu que ce que le Figma dessine.
- Deux autres littéraux mobiles n'existent nulle part ailleurs et sont dérivés
  d'un rôle plutôt qu'écrits : `#90d2ce` (texte légal sur `primary`) et
  `#bfc9c7` (bordure de champ). Les écrire aurait ajouté un cinquième et un
  sixième vert au socle.

**Action côté source, non bloquante :** réconcilier les frames mobiles sur les
valeurs desktop. Le code n'en dépend pas — il passe par les rôles — mais tant
que le fichier se contredit, chaque nouvel écran mobile rouvre la question.

### 2.3 Jetons optionnels — `theme.premium`

```jsonc
"theme": {
  "premium": { "surface": "#…", "accent": "#…", "text": "#…" }   // OPTIONNEL, bloc entier
}
```

| Champ | Type | Obl. | Absent → |
|---|---|---|---|
| `theme.premium.*` | `#RRGGBB` | ⬜ | **Le rendu d'origine du socle est utilisé, jeton par jeton** |

C'est la nuance du §7.5 du brief, transposée telle quelle. Le bloc « offre premium » a délibérément un registre crème et doré qui le détache du reste. La bonne réponse n'est pas de le repeindre aux couleurs de la marque, mais de **sortir ses valeurs dans un jeu de jetons optionnel** : une marque qui n'écrit rien obtient le rendu d'origine ; une marque qui veut « la même chose en bleu » n'a que trois valeurs à écrire.

> **Configurable ne veut pas dire uniformisé.**

**Ce qui n'est PAS configurable par marque, et c'est délibéré :** les couleurs sémantiques (`danger`, `success`, `warning`) et les gris de structure. Ce sont des décisions produit, pas des décisions de marque. Elles vivent dans le socle. Elles deviendront configurables **le jour où un client le demande**, pas avant — la règle d'hygiène du §2.5 du brief s'applique aussi aux jetons : *n'entre dans la configuration que ce que le code lit et qu'un client a une raison de changer.*

### 2.4 Logos et visuels

```jsonc
"logo": {
  "mark":        "logo-mark.png",
  "full":        "logo-full.png",
  "fullInverse": "logo-full-inverse.png"
},
"visuals": {
  "hero":       { "background": "hero-bg.jpg", "backgroundSmall": "hero-bg-sm.jpg" },
  "howItWorks": { "ltr": "how-ltr.png", "rtl": "how-rtl.png" }
}
```

| Champ | Type | Obl. | Absent → |
|---|---|---|---|
| `logo.mark` | chemin relatif à `brands/<slug>/assets/` | ✅ | **Erreur** — sert d'icône in-app et de repli partout |
| `logo.full` | idem | ✅ | **Erreur** |
| `logo.fullInverse` | idem | ⬜ | `logo.full` est utilisé sur fond sombre, avec **avertissement** au chargement |
| `visuals.hero.background` | idem | ⬜ | Aplat `colors.surface`, sans image |
| `visuals.hero.backgroundSmall` | idem | ⬜ | `background` est servi aux petits écrans |
| `visuals.howItWorks.ltr` | idem | ⬜ | Le bloc n'est pas rendu |
| `visuals.howItWorks.rtl` | idem | ⬜ si `ar` n'est pas dans `locales` ; **avertissement** sinon | ⚠️ **Un décor miroité est illisible.** Le §4.4 du brief impose deux jeux **recomposés**, pas retournés. Une marque servant l'arabe sans visuel RTL déclenche un avertissement explicite |

**Aucun chemin ne contient jamais le slug d'un client.** Les chemins sont relatifs au dossier d'assets de la marque active ; c'est le chargeur qui les résout. `assets/brands/sabily/logo.png` écrit dans un widget est exactement la faute du §7.4 du brief.

### 2.5 Langues et devise

| Champ | Type | Obl. | Absent → | Pourquoi |
|---|---|---|---|---|
| `locales` | `string[]` | ✅ | **Erreur** | Les langues que **cette marque** sert. Autorité unique. |
| `defaultLocale` | `string` | ✅ | **Erreur** | ⚠️ **Aucune langue par défaut universelle.** eSimple sert l'allemand. Un socle qui suppose « français partout » est cassé au deuxième client (§7.3 du brief). |
| `currency` | ISO 4217 | ✅ | **Erreur** | Doit exister côté backend. Une seule devise par marque — voir §6.6. |

**Validation croisée :** `defaultLocale` doit appartenir à `locales` (**erreur** sinon), et chaque entrée de `locales` doit appartenir aux langues supportées par le socle (**avertissement** sinon, avec le nom de la langue inconnue — la marque reste utilisable, la langue est simplement ignorée).

La constante globale du socle ne décrit **que** l'ensemble des langues qu'il sait servir. Elle n'est jamais l'autorité pour une marque. C'est le §7.3 du brief, et c'est le bug qui a fait qu'une marque limitée à `fr`/`en` répondait normalement sur `/de/…`.

### 2.6 Fonctions activables

```jsonc
"features": { "wallet": false }
```

| Champ | Type | Obl. | Absent → |
|---|---|---|---|
| `features.wallet` | `bool` | ⬜ | `false` — le module TransaPay n'est ni enregistré ni joignable |

**Il n'y a qu'un seul drapeau, et c'est délibéré.** La règle d'hygiène du §2.5 du brief est appliquée strictement :

> **N'entre dans `features` que ce qui est réellement lu par le code.**

Le socle web a promis pendant des mois `vouchers`, `topUp`, `citySearch`, `segments`, `analytics`, `social`, `apps` — **tous déclarés, aucun lu**. Ils ont été retirés. Ici, `wallet` est le seul drapeau parce que `wallet` est le seul module optionnel.

Une clé inconnue sous `features` produit un **avertissement** nommant la clé. C'est précisément le cas « le client croit avoir activé quelque chose ».

**`features.b2b` n'existe pas dans ce contrat** (décision §0). Il ne sera pas ajouté « au cas où » : un drapeau décoratif est un mensonge à retardement.

### 2.7 Support et identité légale

```jsonc
"support": { "email": "contact@sabily.fr", "hours": "7j/7" },
"legal":   { "companyName": "…", "country": "FR", … }
```

| Champ | Type | Obl. | Absent → |
|---|---|---|---|
| `support.email` | `string` | ✅ | **Erreur** — l'écran de support n'a rien à afficher |
| `support.hours` | `string` ou `{lang: string}` | ⬜ | Ligne d'horaires masquée |
| `legal.companyName` | `string` | ✅ | **Erreur** |
| `legal.tradingAs` | `string` | ⬜ | `companyName` est utilisé |
| `legal.country` | ISO alpha-2 | ✅ | **Erreur — volontairement sans valeur par défaut** |
| `legal.legalForm`, `siren`, `siret`, `vatNumber`, `capital`, `rcs`, `ape` | `string` | ⬜ | **Champ affiché vide, avec un tiret** |
| `legal.address`, `city` | `string` | ⬜ | Bloc d'adresse masqué |
| `legal.director`, `directorTitle` | `string` | ⬜ | Ligne masquée |
| `legal.jurisdiction` | `string` | ⬜ | Ligne masquée |
| `legal.textsLastUpdated` | ISO 8601 | ⬜ | Date de mise à jour masquée |
| `legal.host` | `string` | ⬜ | Bloc hébergeur masqué |
| `legal.vatRate` | `number` | ⬜ | **Avertissement** — voir §6.7 |
| `legal.termsUrl`, `legal.privacyUrl` | URL absolue | ✅ | **Erreur** — voir ci-dessous |

Trois décisions reprises du contrat web, **à ne pas négocier** :

- **`country` n'a volontairement aucune valeur par défaut.** Supposer « FR » ferait porter les obligations françaises à un client étranger. Un socle white-label n'a pas à décider ça à sa place.
- **Les identifiants légaux non fournis restent vides — on n'en fabrique aucun.** Chez une marque française, l'écran les affiche **même vides, avec un tiret** : leur absence est une anomalie qu'il vaut mieux rendre visible que masquer.
- 🔴 **`termsUrl` / `privacyUrl` sont des URL, pas des fichiers embarqués, et c'est obligatoire.** `ANALYSE-EXISTANT.md` §4.7 a constaté qu'il existe aujourd'hui **un seul jeu de PDF, embarqué dans le binaire, servi à tous les clients des branches `spc/*`**. Les textes juridiques appartiennent au client et l'engagent ; ils doivent être modifiables **sans soumission au store** (§7.2 du brief). Le socle affiche une WebView sur l'URL, avec cache hors ligne du dernier contenu chargé.

### 2.8 Surcharges de textes

```jsonc
"texts": {
  "premium.title":     { "de": "Werden Sie", "fr": "Devenez" },
  "premium.highlight": { "de": "Partner",    "fr": "partenaire" }
}
```

| Champ | Type | Obl. | Absent → |
|---|---|---|---|
| `texts` | `{clé: {langue: texte}}` | ⬜ | Le dictionnaire commun est servi |

**Résolution, dans cet ordre :** surcharge dans la langue demandée → surcharge dans **la langue par défaut de la marque** → dictionnaire commun.

Le repli intermédiaire est délibéré : une marque qui n'a traduit son message que dans deux langues sur six est mieux servie dans **son** message, même en allemand, que dans le message d'une autre marque correctement traduit — les deux apparaîtraient sinon sur le même écran.

**Une clé de surcharge qui ne vise aucune clé existante du dictionnaire produit un avertissement nommant la clé.** C'est la configuration « partiellement inerte » du §2.8 du brief.

⚠️ À n'utiliser **que** pour ce qui relève du discours du client. Une chaîne réécrite ici sort du circuit de traduction commun : elle ne bénéficiera d'aucune relecture ultérieure du socle.

### 2.9 Le bloc `mobile`

```jsonc
"mobile": {
  "applicationId":          "com.sabily.esim",
  "bundleIdentifier":       "com.sabily.esim",
  "displayName":            "Sabily",
  "deepLinkScheme":         "sabily",
  "universalLinkHosts":     ["sabily.fr", "www.sabily.fr"],
  "apiBaseUrl":             "https://api.sabily.fr/api",
  "stripePublishableKey":   "pk_live_…",
  "merchantIdentifier":     "merchant.com.sabily.esim",
  "merchantCountryCode":    "FR",
  "remoteConfigUrl":        "https://api.sabily.fr/api/app-config",
  "minimumSupportedVersion": "1.0.0",
  "registration": { "fields": ["email","password","firstName","lastName","phoneNum","country"] }
}
```

| Champ | Type | Obl. | Absent → | Figé au build ? |
|---|---|---|---|---|
| `applicationId` | reverse-DNS | ✅ | **Erreur** | 🔒 **Oui — irréversible après publication** |
| `bundleIdentifier` | reverse-DNS | ✅ | **Erreur** | 🔒 **Oui — irréversible après publication** |
| `displayName` | `string` | ✅ | **Erreur** | 🔒 Oui (manifeste / `Info.plist`) |
| `deepLinkScheme` | `string` | ✅ | **Erreur** | 🔒 Oui |
| `universalLinkHosts` | `string[]` | ⬜ | Aucun App Link / Universal Link | 🔒 Oui |
| `apiBaseUrl` | URL absolue | ✅ | **Erreur** | 🔒 **Oui — voir §6.4** |
| `stripePublishableKey` | `pk_…` | ✅ | **Erreur** | Non — surchargeable à distance |
| `merchantIdentifier` | `merchant.…` | ⬜ | Apple Pay désactivé | 🔒 Oui (habilitation) |
| `merchantCountryCode` | ISO alpha-2 | ⬜ si pas d'Apple/Google Pay | Wallets désactivés | Non |
| `remoteConfigUrl` | URL absolue | ⬜ | **Configuration embarquée uniquement**, sans erreur | 🔒 Oui |
| `minimumSupportedVersion` | semver | ⬜ | Aucun blocage de version | Non |
| `registration.fields` | `string[]` d'identifiants connus | ⬜ | Jeu par défaut du socle | Non |

🔴 **`stripePublishableKey` est validé : une valeur ne commençant pas par `pk_` est une erreur, et une valeur commençant par `sk_` est une erreur nommée explicitement.** Ce n'est pas de la paranoïa : le §4.4 du brief rapporte qu'une clé secrète `sk_live_` a **déjà** été trouvée posée dans un environnement de développement. Deux lignes de validation valent mieux qu'un incident irréversible dans une application publiée.

**`registration.fields` — pourquoi ce champ existe, et où s'arrête sa souplesse.** Le §8.4 du brief indique que l'inscription exige aujourd'hui onze champs et qu'une demande de réduction à quatre est déposée côté backend. Le §4.3 impose que tout ce qui peut être résolu à l'exécution le soit. Ce champ permet donc de suivre le contrat backend **sans soumission au store**.

Sa souplesse est **délibérément bornée** : c'est une liste ordonnée d'identifiants pris dans un ensemble fermé, connu du code. Le socle possède le libellé, le widget et la validation de chaque champ ; la configuration choisit lesquels afficher et dans quel ordre. **Ce n'est pas un constructeur de formulaires.** Un identifiant inconnu produit un avertissement et est ignoré. Ajouter un *type* de champ reste un changement de code — et c'est voulu, sinon ce champ devient un langage.

### 2.10 Modélisation Dart

```dart
@immutable
class BrandConfig {
  final String slug;
  final String name;
  final BrandColors colors;
  final BrandTheme theme;          // jetons optionnels
  final BrandLogo logo;
  final BrandVisuals visuals;
  final List<Locale> locales;
  final Locale defaultLocale;
  final String currency;
  final BrandFeatures features;
  final BrandSupport support;
  final BrandLegal legal;
  final BrandMobile mobile;
  final Map<String, Map<String, String>> texts;   // clé → langue → texte

  const BrandConfig({ /* … */ });

  /// Lève une [BrandConfigError] nommant CHAQUE champ fautif, jamais un seul.
  /// Un intégrateur doit corriger sa configuration en une passe, pas en dix.
  static BrandValidation parse(Map<String, dynamic> json);
}

/// Résultat de validation : distingue ce qui rend la marque inutilisable
/// de ce qui la rend partiellement inerte.
class BrandValidation {
  final BrandConfig? config;       // null si errors est non vide
  final List<BrandError> errors;   // marque refusée
  final List<BrandWarning> warnings; // marque utilisable, configuration partiellement morte
}
```

Deux exigences reprises du web, non négociables :

- **La validation nomme tous les problèmes d'un coup**, et distingue erreur et avertissement.
- **Aucun accès à `BrandConfig` par variable globale mutable.** Elle est injectée par un `Provider` Riverpod surchargé à la racine. Une globale rend le socle intestable et invite au `if (brand == 'sabily')`.

---

## 3. Table des flavors — artefact contractuel

> **Cette table est un artefact contractuel, pas un détail de build (§4.2 du brief).** Les identifiants ci-dessous **ne se changent jamais après publication** : une erreur se paie par une nouvelle fiche store et la perte de toutes les installations. **Elle doit être validée explicitement et nommément.**

### 3.1 Table

| slug | `applicationId` (Android) | `bundleIdentifier` (iOS) | Nom affiché | Schéma de lien profond | Hôtes de liens universels | État |
|---|---|---|---|---|---|---|
| `sabily` | **`com.sabily.esim`** | **`com.sabily.esim`** | Sabily | `sabily` | `sabily.fr`, `www.sabily.fr` | 🔒 **Publié — exception, voir §3.2** |

### 3.2 Sabily est une exception explicite, pas un oubli

Le §5.3 du brief propose la convention `com.transasim.<slug>`. **Elle n'est pas appliquée à Sabily.**

L'application Android de Sabily est **déjà publiée sur le Play Store sous `com.sabily.esim`** (`ANALYSE-EXISTANT.md` §10.1). Sur Android, l'`applicationId` est l'identité de la fiche : le changer crée une **nouvelle** fiche, et **la totalité des installations existantes est perdue** — les utilisateurs ne reçoivent plus aucune mise à jour et doivent réinstaller.

> **Sabily conserve `com.sabily.esim`. C'est une exception assumée, écrite ici pour qu'elle ne soit ni « corrigée » par un successeur bien intentionné, ni découverte au moment de la première publication.**

C'est exactement le §7.10 du brief : documenter la décision, pas seulement la valeur.

### 3.3 Convention pour les clients suivants — à trancher (§12)

La convention ne peut pas être arrêtée avant la décision sur la propriété des comptes stores (§12.4), parce que les deux se commandent :

| Convention | Va avec | Conséquence |
|---|---|---|
| `com.transasim.<slug>` | Publication sous le compte développeur **de TRANSASIM** | Cohérent, lisible, un seul compte à administrer. Le nom du prestataire apparaît dans l'identifiant technique de la marque du client. |
| `<tld>.<client>.<app>` (ex. `at.esimple.app`) | Publication sous le compte développeur **du client** | Plus propre juridiquement, plus lourd opérationnellement (un compte, un jeu de certificats et un jeu de secrets de CI par client). |

**Décision par client, à figer avant toute publication.** Un client peut être publié sous son compte et un autre sous le vôtre ; ce qui ne peut pas varier, c'est la rigueur avec laquelle la ligne est écrite dans cette table avant le premier envoi.

### 3.4 Identifiants déjà revendiqués par les anciennes branches — statut vérifié

Les branches clientes de l'ancien dépôt portent déjà des `applicationId`. **Leur statut de publication a été vérifié le 10 septembre 2026** contre les fiches publiques du Play Store et de l'App Store.

| Branche | Identifiant revendiqué | Google Play | App Store | Statut |
|---|---|---|---|---|
| `spc/sabily` | `com.sabily.esim` | ✅ **Publié** | ✅ **Publié** — « Sabily eSim », v1.3, sortie 08/03/2026 | 🔒 **Figé** |
| `spc/esimple` | `com.esimple.esim` | ✅ **Publié** | ✅ **Publié** — « eSimple », v1.0, sortie 24/08/2026 | 🔒 **Figé** |
| `spc/djezzy` | ⚠️ `com.djeezy.esim` | ❌ Aucune fiche | ❌ Aucune fiche | 🟢 **Corrigeable — voir ci-dessous** |
| `spc/castrum` | `com.castrum.esim` | ❌ Aucune fiche | ❌ Aucune fiche | 🟢 Corrigeable |

**Correction apportée à ce document :** `com.esimple.esim` était donné « à vérifier » dans la première rédaction. Il est **publié sur les deux stores**. La table du §3.1 ne couvre que Sabily, seul client du périmètre de ce document ; mais **quand eSimple y entrera en phase 4, il y entrera comme une seconde exception figée**, au même titre et pour la même raison que Sabily (§3.2). La convention du §3.3 ne s'appliquera donc qu'aux clients **non encore publiés** : `djezzy`, `castrum`, et les suivants.

#### 🟢 La faute de frappe `djeezy` est encore corrigeable — sous réserve de deux vérifications en console

L'identifiant `com.djeezy.esim` (au lieu de `djezzy`) **n'a jamais fait l'objet d'une publication** :

| Preuve | Constat |
|---|---|
| Fiche publique Play Store | HTTP 404, pour `com.djeezy.esim` **et** pour `com.djezzy.esim` |
| Recherche App Store par `bundleId` (storefronts us, fr, at, dz) | Aucun résultat |
| `versionCode` de la branche | **17**, identique à `master` — jamais incrémenté depuis le point de branche |
| Comparaison avec le client réellement publié | `spc/esimple` porte `versionCode 19 / 1.1.8`, **au-dessus** de `master` : la signature d'un vrai cycle de publication. `djezzy` ne l'a pas |
| Dernier commit de la branche | 18 juillet 2026, soit cinq semaines avant la sortie d'eSimple |

⚠️ **Deux vérifications en console restent nécessaires avant de considérer la faute comme corrigeable, et elles ne peuvent pas se faire depuis l'extérieur :**

1. **Google Play Console.** L'absence de fiche publique prouve l'absence de **publication**, pas l'absence d'**envoi**. Déposer un artefact sur n'importe quel canal — interne, fermé, ouvert — **réserve définitivement le nom de paquet sur ce compte Google Play**, même si l'application est ensuite supprimée. Un nom réservé n'est jamais réutilisable ni renommable.
2. **Portail Apple Developer.** Un `bundleIdentifier` enregistré est réservé sans aucune présence sur l'App Store, et **une application diffusée uniquement par TestFlight n'apparaît pas** dans la recherche par `bundleId`. Or la CI de l'ancien dépôt publie précisément vers TestFlight (`ios-testflight.yml`).

**Si les deux consoles sont vierges de `com.djeezy.esim`, la faute se corrige sans coût.**

#### La branche se contredisait elle-même — et c'est ce qui tranche

Le relevé exhaustif donne **23 occurrences réparties sur 12 fichiers**, pas trois. Mais surtout, deux fichiers portaient déjà **la bonne orthographe** :

| Fichier | Valeur |
|---|---|
| `android/fastlane/Appfile` | `package_name(… \|\| "com.djezzy.esim")` ✅ |
| `ios/fastlane/Appfile` | `app_identifier(… \|\| "com.djezzy.esim")` ✅ |
| `assets/.env` | `WEB_URL = "https://djezzy.transasim.com"` ✅ |

**Tout ce qui construit ou publie portait la faute ; tout ce qui déclare l'intention portait la bonne graphie.** L'outil qui téléverse et l'artefact téléversé n'étaient pas d'accord. `com.djezzy.esim` est donc l'identifiant voulu : la correction aligne la branche sur son intention, elle n'impose pas un choix nouveau.

**Correction préparée** sur la branche locale `fix/djezzy-application-id` (descendante directe de `origin/spc/djezzy`, commit `d8e68d3`, **non poussée**) : `build.gradle` (`namespace` + `applicationId`), le paquet Kotlin **et son répertoire** (`git mv`), `google-services.json` (×4), `android-release.yml` (cible du téléversement Play), `project.pbxproj` iOS (×6), `Info.plist`, `GoogleService-Info.plist`, `exportOptions.plist`, `firebase_options.dart`, l'identifiant marchand Apple Pay, et les fichiers macOS.

Trois suites que ce commit ne fait volontairement pas :

- **Les fichiers Firebase sont édités à la main.** La construction passera — le greffon Gradle ne compare que `package_name` — mais les autres champs ont été émis pour l'ancien nom. Il faut enregistrer `com.djezzy.esim` dans la console Firebase et retélécharger. Rien ne casse entretemps : `Firebase.initializeApp()` n'est jamais appelé (§1.3 de l'analyse).
- **`merchant.com.djezzy.esim`** doit être enregistré comme Merchant ID dans le portail Apple si Apple Pay est un jour voulu. Il ne peut de toute façon pas fonctionner aujourd'hui : l'habilitation `in-app-payments` est un tableau vide.
- **Le schéma d'URL reste `sabily-mobile`**, y compris sur la branche Djezzy. Ce n'est pas cette faute-là, c'est un défaut de déclinaison distinct — et il signifie que **deux applications issues de ce code, installées côte à côte, se disputent le même schéma**. À traiter avec le §2.9 (`mobile.deepLinkScheme`), qui le rend propre à chaque marque.

> **Aucun de ces trois clients n'entre dans le périmètre de ce document** (le socle se prouve sur Sabily d'abord, §6.3 du brief). Ils sont listés ici parce que la table des flavors est un artefact contractuel : les identifiants déjà revendiqués font partie du contrat, y compris leurs fautes — et parce que `djezzy` est la seule fenêtre encore ouverte pour en corriger une.

---

## 4. Découpage en modules et contrat `AppModule`

### 4.1 Le contrat

```dart
abstract class AppModule {
  /// Identifiant stable — sert de clé dans `features` quand le module est optionnel.
  String get id;

  /// Ce module est-il actif pour cette marque ?
  bool isEnabled(BrandConfig config);

  /// Routes exposées. NON ENREGISTRÉES quand le module est inactif :
  /// c'est ce qui rend le drapeau honnête.
  List<RouteBase> routes(BrandConfig config);

  /// Entrées de navigation principale (onglets). Peut être vide.
  List<NavEntry> navEntries(BrandConfig config);

  /// Dépendances (providers) à installer. Non installées si inactif.
  List<Override> providers(BrandConfig config);
}
```

Enregistrement au démarrage :

```dart
const allModules = <AppModule>[
  CatalogModule(), AccountModule(), EsimModule(), CheckoutModule(),
  WalletModule(),   // squelette TransaPay — actif si features.wallet
];

final active = allModules.where((m) => m.isEnabled(config)).toList();
```

### 4.2 La garde d'entrée — l'autre moitié du mécanisme

**Ne pas enregistrer la route ne suffit pas.** Le lien profond, la navigation nommée et l'appel réseau existent encore dans le binaire. C'est la leçon la plus chère du socle web (§2.5, §7.6 du brief) et `ANALYSE-EXISTANT.md` §4.10 l'a retrouvée intacte dans l'ancienne application : `FEATURE_CREDIT_CARD` masquait **1 point d'entrée sur 4** et fermait **0 route sur 1**.

Chaque cas d'usage d'un module optionnel commence donc par sa garde :

```dart
class OpenWallet {
  Future<Result<void>> call() async {
    if (!features.wallet) return const Result.failure(FeatureUnavailable());
    // …
  }
}
```

**Deux frontières, deux gardes.** Le registre ferme la route ; le cas d'usage refuse l'appel. Un test de non-régression vérifie les deux (§8.4).

### 4.3 Les modules

| Module | Actif | Contenu | Onglet |
|---|---|---|---|
| `catalog` | Toujours | Destinations, recherche, fiche destination, fiche forfait, forfaits régionaux | Accueil, Boutique |
| `account` | Toujours | Inscription, connexion, OTP, mot de passe oublié, profil, langue, support, textes légaux | Profil |
| `esim` | Toujours | Mes eSIM, QR, installation, consommation, bon d'achat | Mes eSIM |
| `checkout` | Toujours | Panier, paiement, confirmation, reprise de commande | — (pas d'onglet) |
| `wallet` | `features.wallet` | **Squelette** : une route, un écran « bientôt disponible », zéro logique | Portefeuille |

**Le module `wallet` est un livrable de ce projet, et il est vide.** Son rôle est de **prouver que le point d'extension fonctionne** avant que TransaPay n'existe. Un point d'extension jamais exercé est un point d'extension qui ne marche pas (§5.6 du brief). Il est exercé par le test du §8.4.

**Il n'y a pas de module `reseller`.** Décision §0.

### 4.4 Liste des drapeaux et de ce qu'ils coupent réellement

C'est le tableau que le §6.2 point 4 du brief exige.

| Drapeau | Défaut | Écrans coupés | Routes coupées | Appels réseau coupés | Onglet |
|---|---|---|---|---|---|
| `features.wallet` | `false` | `WalletHomeScreen` | `/wallet` et toutes ses sous-routes — **non enregistrées** dans `GoRouter` | Aucun aujourd'hui (le squelette n'appelle rien). Quand TransaPay existera, ses cas d'usage porteront `assertWallet()` | Retiré de la barre |

**Un seul drapeau, une seule ligne.** Si cette table s'allonge sans que la colonne « appels réseau » se remplisse, le drapeau ajouté ment.

---

## 5. Gestion d'état : Riverpod

**Riverpod v2, avec `riverpod_generator`.**

### 5.1 Justification

Le §5.5 du brief autorise à garder Bloc « si l'analyse de phase 1 révèle un existant Bloc conséquent et sain ». `ANALYSE-EXISTANT.md` §3 a conclu qu'il est **conséquent mais pas homogène** : deux paradigmes d'état cohabitent (blocs d'un côté, `serviceLocator.*Repository` appelé depuis `setState` de l'autre), huit blocs à plat sont morts, dont des fichiers nommés `_temp` en source de production. Cela ne franchit pas la barre du brief **même dans une migration**.

Et comme il s'agit ici d'un départ propre, il n'y a **aucune couche d'état existante à mettre dans la balance** : la question est tranchée sans coût.

Pourquoi Riverpod pour ce projet précis :

| Critère | Pourquoi ça compte **ici** |
|---|---|
| **Surcharge de providers** | La configuration de marque s'injecte à la racine et se surcharge en test. Tester le même écran sous deux marques est un `override` — c'est exactement le besoin d'un socle multi-marques (§8.3). |
| **Indépendance du `BuildContext`** | La logique reste testable sans widget — condition pour que les cas d'usage soient réutilisables par TransaPay. |
| **Composition / invalidation** | Un module désactivé n'installe simplement pas ses providers. Aucune machinerie à débrancher : c'est `AppModule.providers()` qui n'est pas appelé. |
| **Volume de code** | Moindre que Bloc à couverture égale. Sur un socle destiné à porter deux produits, le volume compte. |

### 5.2 Trois règles d'usage

1. **Aucun widget n'appelle un dépôt directement.** Widget → contrôleur → cas d'usage → dépôt. C'est le second paradigme de l'ancienne application qui est interdit ici, nommément.
2. **L'état d'écran est un type scellé** (`sealed class` + `freezed`), jamais trois booléens `isLoading` / `hasError` / `data` qui autorisent des états impossibles.
3. **Les erreurs sont typées et traduites au bord.** Une erreur réseau qui remonte brute jusqu'à l'écran finit toujours par s'afficher en anglais à un utilisateur arabophone. `core/result/` définit `AppError` ; la traduction se fait dans la couche présentation, jamais avant.

---

## 6. Stratégie de configuration distante

### 6.1 Les trois niveaux de résolution

```
1. Configuration DISTANTE (récupérée au démarrage, validée, mise en cache)  ← modifiable sans store
2. brand.json EMBARQUÉ dans le flavor                                        ← repli hors ligne, toujours présent
3. Valeurs par défaut du socle                                               ← dernier filet
```

L'ordre est **l'inverse du web** (le plus dynamique gagne), pour la raison du §4.3 du brief : sur mobile, ce qui est modifiable sans republier vaut de l'or.

### 6.2 Ce qui est modifiable sans soumission au store

| Modifiable à distance | Figé au build |
|---|---|
| `colors.*`, `theme.premium.*` | `mobile.applicationId` |
| `logo.*`, `visuals.*` (URL distantes, avec repli embarqué) | `mobile.bundleIdentifier` |
| `texts.*` | `mobile.displayName` |
| `legal.*`, dont `termsUrl` / `privacyUrl` | `mobile.deepLinkScheme` |
| `support.*` | `mobile.universalLinkHosts` |
| `locales`, `defaultLocale` | `mobile.apiBaseUrl` (§6.4) |
| `features.wallet` | `mobile.remoteConfigUrl` |
| `mobile.stripePublishableKey` (§6.5) | Icône, écran de lancement |
| `mobile.registration.fields` | `name`, `slug` |
| `mobile.minimumSupportedVersion` | |

**La colonne de droite est la liste que le §7.8 du brief demande de dresser et de défendre ligne à ligne.** Chaque entrée y figure parce que les stores l'imposent (identifiants, nom, icône, écran de lancement, schémas d'URL déclarés dans le manifeste), ou pour la raison du §6.4.

### 6.3 Trois garde-fous

- **La configuration distante est validée avant d'être adoptée.** Une configuration distante invalide est **ignorée** au profit de l'embarquée, avec une trace remontée en télémétrie. Ne jamais laisser une erreur de saisie serveur casser l'application de tous les utilisateurs d'un client.
- **Elle ne peut pas tout changer.** Les champs de la colonne de droite, s'ils apparaissent dans la configuration distante, sont **ignorés avec un avertissement**. Ils sont figés dans le binaire ; les accepter donnerait l'illusion qu'ils ont changé.
- **Elle est mise en cache**, et le cache sert au démarrage suivant. **Une application qui démarre sans réseau doit s'afficher correctement** — c'est un test de recette obligatoire (§8.5).

### 6.4 Pourquoi `apiBaseUrl` n'est PAS surchargeable à distance

C'est une divergence assumée par rapport à la lecture littérale du §5.3 du brief, et elle mérite sa justification :

**La configuration distante est servie par le backend du client.** Si elle pouvait déplacer `apiBaseUrl`, on obtient soit un paradoxe d'amorçage (l'application ne sait plus où chercher sa configuration au démarrage suivant), soit un vecteur de détournement (une configuration compromise redirige tout le trafic d'un client, y compris ses jetons de session, vers un tiers).

Changer le backend d'un client est un événement rare qui justifie une livraison. **`apiBaseUrl` reste dans le flavor, avec surcharge possible par `--dart-define` au build** pour les environnements de développement et de recette — ce qui répond au besoin réel (§9.3 de l'analyse : « chaque développeur, chaque exécution de CI et chaque test frappe la production ») sans ouvrir le vecteur.

### 6.5 Pourquoi `stripePublishableKey` l'est

Une clé publiable est publique par conception. Elle est servie en TLS par le backend du client lui-même — le même domaine de confiance que celui qui crée déjà les intentions de paiement. Un backend compromis peut faire pire que remplacer une clé publiable.

Le gain, lui, est réel : **faire tourner un compte Stripe sans republier.** Un client qui change de PSP, ou dont le compte est suspendu, ne doit pas attendre une revue Apple.

Contrepartie non négociable : la validation `pk_` / rejet de `sk_` (§2.9) s'applique **aussi** à la valeur distante.

### 6.6 Devise — une seule par marque, et c'est délibéré

`ANALYSE-EXISTANT.md` §7.3 a établi que le sélecteur de devise de l'ancienne application **ne convertit pas le montant débité** : il affiche un prix converti par une API tierce gratuite et envoie le nombre en euros étiqueté USD. Le backend, lui, contrôle le montant débité contre `price.sabilyAmount` **dans la devise réellement capturée** et refuse le provisionnement en cas d'écart.

**Le socle n'expose donc aucun sélecteur de devise.** Chaque marque sert `currency`, et les prix affichés sont ceux que le backend renvoie pour cette devise. Aucun change n'est calculé sur l'appareil, et `api.exchangerate-api.com` n'apparaît nulle part.

Le multi-devises redeviendra possible **le jour où le backend servira des prix par devise** — c'est une demande à formuler (§13.2), pas une fonctionnalité à simuler.

### 6.7 L'endpoint de configuration distante n'existe pas encore

⚠️ **`GET /app-config` n'existe pas dans le backend analysé.** Aucun endpoint de ce type n'a été trouvé dans le JAR (`ANALYSE-EXISTANT.md` §7.10). C'est une **demande backend** (§13.2).

**En attendant, le socle fonctionne sur la configuration embarquée seule** — c'est précisément le rôle du niveau 2. Mais le chemin de code distant est **construit, câblé et testé dès la phase 3**, contre un serveur de bouchon en test : un point d'extension jamais exercé est un point d'extension qui ne marche pas.

---

## 7. Chemin de l'argent — la conception, et pourquoi elle diffère de l'existant

Cette section n'est pas dans la liste du §6.2, mais elle conditionne le module `checkout` et deux demandes backend. Elle est le cœur de ce que la reconstruction doit corriger.

### 7.1 Ce que l'analyse a établi, et qui change la conception

Quatre faits, tous vérifiés sur le bytecode du backend :

1. **`POST /v1/payments/init` lit la chaîne de requête, pas le corps.** Les deux paramètres sont `@RequestParam` ; il n'y a aucun `@RequestBody`.
2. **Il crée déjà un enregistrement serveur.** `initPayment()` insère une ligne `Payment` au statut `INITIALED`, avec `externalReference` = l'identifiant de l'intention Stripe, et **renvoie son `paymentId`**. Il n'existe pas d'entité « commande » séparée dans ce backend — `/api/v1/packs` n'expose aucune route d'achat ou de commande. **La ligne `Payment` *est* la commande.**
3. **`POST /v1/subscriptions/card` est idempotent en effet, clé = l'identifiant d'intention Stripe.** `subscribeByCard` recherche le paiement par `externalReference` et, s'il est déjà au statut `COMPLETED_AND_CONSUMED`, **lève au lieu de provisionner une seconde fois**.
4. **Le montant est contrôlé côté serveur.** `result.getAmount().compareTo(price.getSabilyAmount()) != 0` → `PaimentException`. C'est ce qui transforme la troncature des centimes en échec de livraison, pas seulement en manque à gagner.

Les points 2 et 3 sont les plus importants : ils signifient que **la reprise après échec est constructible aujourd'hui, sans changement backend**.

### 7.2 Le flux retenu

```
1. L'utilisateur confirme l'achat
2. POST /v1/payments/init?amount=<décimal EXACT>&currency=<code>
      → crée la ligne Payment (INITIALED) côté serveur
      → renvoie { paymentId, + l'identifiant d'intention et le secret client }
   ⇒ On PERSISTE localement { paymentId, packId, paymentIntentId, montant, devise, horodatage }
      AVANT de présenter quoi que ce soit à l'utilisateur.
3. Stripe PaymentSheet est présentée
4. Succès → POST /v1/subscriptions/card { packId, paymentIntentId }
      avec REPRISE : jusqu'à N tentatives, dos exponentiel
5. Échec/expiration à l'étape 4 → la commande reste en attente localement
      → reprise automatique au prochain lancement
      → et un écran « Ma commande » qui la montre et permet de relancer
6. Annulation utilisateur → AUCUN appel. On supprime l'attente locale.
```

**Cinq différences avec l'existant, chacune corrigeant un défaut mesuré :**

| # | Existant (`ANALYSE-EXISTANT.md`) | Ici |
|---|---|---|
| 1 | La commande est fabriquée côté client après 500 ms de sommeil (§7.1) | La ligne `Payment` serveur créée à l'étape 2 **est** la commande |
| 2 | `.toInt()` tronque les centimes (§7.2) | **Le montant décimal exact part dans la requête.** Aucun `toInt`, nulle part |
| 3 | Aucune reprise, aucune idempotence (§7.1) | Reprise avec dos exponentiel, **sûre parce que le serveur garde `COMPLETED_AND_CONSUMED`** |
| 4 | L'annulation poste quand même un appel de création d'abonnement (§7.5) | L'annulation ne poste rien |
| 5 | Le client code en dur `status: 'success'` quoi que réponde le serveur (§7.5) | La réponse est lue ; l'écran de succès **exige** une provisionnement confirmé |

### 7.3 Analyse de la réponse de `/payments/init` — conception insensible à R3

`ANALYSE-EXISTANT.md` §7.4 a établi sur le bytecode que le serveur inverse `clientSecret` et `paymentIntentId`, et que le champ `id` n'est **jamais affecté**. Mais le JAR analysé date du 4 juillet, cinq semaines avant le dernier commit mobile : **seule une requête en direct tranche pour la production.**

**Le socle est conçu pour ne pas dépendre de la réponse.** Le secret client et l'identifiant d'intention sont identifiés **par leur forme**, pas par leur nom de champ :

```dart
// Un secret client Stripe : pi_XXX_secret_YYY.  Un identifiant : pi_XXX, sans _secret_.
final secret = json.values.whereType<String>()
    .firstWhereOrNull((v) => _secretPattern.hasMatch(v));   // ^pi_[A-Za-z0-9]+_secret_
final intentId = json.values.whereType<String>()
    .firstWhereOrNull((v) => _intentPattern.hasMatch(v));   // ^pi_[A-Za-z0-9]+$
```

Et le champ dans lequel chacun est **effectivement** arrivé est remonté en télémétrie une fois par version.

Trois bénéfices :

- Le paiement fonctionne que le backend soit corrigé ou non ;
- **R3 sort du chemin critique** — la conception n'attend pas la vérification ;
- La production **dit elle-même** quelle variante est vraie, ce qui permet ensuite au backend de renommer ses champs **sans livraison mobile coordonnée** — ce que le §7.4 de l'analyse signalait comme un risque de rupture pour toutes les applications installées.

La même tolérance s'applique à `rmainingData` : les deux orthographes sont acceptées, et la valeur est lue en `num` (le backend la type `BigDecimal`, l'ancien client la castait en `int?` — défaut de type latent relevé au §7.10 de l'analyse).

### 7.4 Ce qui n'est pas construit

- **Aucun formulaire de carte.** Stripe PaymentSheet est la seule surface de collecte. L'application ne touche jamais un PAN, un CVC ou une date d'expiration : elle reste **hors périmètre PCI**. C'est le seul point du chemin de l'argent que l'ancienne application faisait bien, et il est repris tel quel.
- **Aucun achat in-app (StoreKit / Play Billing).** Un forfait data consommé hors de l'application relève du paiement externe. ⚠️ **À faire confirmer, règles Apple et Google en main, avant la première soumission** — c'est un risque de rejet au store (§12.5).


### 7.5 La clé Stripe de Sabily est un espace réservé, et le validateur la laisse passer

`mobile.stripePublishableKey` vaut `pk_test_PLACEHOLDER_AWAITING_CLIENT`. Le
validateur §2.9 ne vérifie que deux choses — que la clé ne commence pas par
`sk_`, et qu'elle commence par `pk_`. L'espace réservé satisfait les deux.

Conséquence : l'application **démarre normalement** et n'échoue qu'au moment de
présenter la feuille de paiement, c'est-à-dire au pire endroit possible.

Le module de paiement demande donc `canTakePayments` avant toute chose : une
clé réelle est `pk_(test|live)_` suivi d'au moins 24 caractères base62, ce que
l'espace réservé n'est pas. Quand la réponse est non, l'écran le dit et le
bouton reste désactivé — plutôt que de présenter une feuille qui ne peut pas
fonctionner.

**Ce qui reste non vérifié tant que B11 n'est pas fourni :** la présentation
réelle de la PaymentSheet, une annulation réelle, et le comportement de la
reprise sous une vraie coupure réseau. Tout le reste du chemin — le montant
exact sur le fil, la persistance avant présentation, l'absence d'appel après un
échec — a été vérifié sur appareil avec une clé bien formée mais factice.

---

## 8. Stratégie de test

### 8.1 Tests unitaires — ce qui est testé sans widget ni réseau

| Objet | Ce qui est vérifié |
|---|---|
| `BrandConfig.parse` | Chaque champ obligatoire manquant produit une erreur **nommée** ; **tous** les défauts sont rapportés en une passe ; les avertissements ne bloquent pas |
| Validation croisée | `slug` ≠ nom de dossier → erreur ; `defaultLocale` ∉ `locales` → erreur ; `sk_` dans `stripePublishableKey` → erreur ; clé `features` inconnue → avertissement |
| Dérivation du thème | Deux `BrandConfig` différentes produisent deux `ThemeData` différentes ; aucun jeton n'est nul |
| Résolution i18n | surcharge langue demandée → surcharge langue par défaut de la marque → dictionnaire commun, dans cet ordre |
| **Construction LPA** | `LPA:1$<smdp>$<matchingId>`, et **refus explicite** si l'un des deux est nul (l'ancienne application interpolait `"null"` et affichait un QR d'apparence valide) |
| **Montant de paiement** | `9.99` produit `amount=9.99` dans la requête. **Test de non-régression direct de R1** |
| **Analyse `/payments/init`** | Le secret client est trouvé quelle que soit la clé qui le porte : `{id}`, `{clientSecret}`, `{paymentIntentId}` |
| Consommation | `restant/total`, garde de division par zéro, formatage des unités |
| Machine à états du checkout | L'annulation ne produit aucun appel ; l'échec de finalisation laisse une commande en attente |

### 8.2 Tests de widget

- Chaque écran, rendu **sous deux `BrandConfig` différentes** via `ProviderScope.overrides` — c'est le test qui prouve qu'aucune valeur de marque n'est en dur.
- Chaque écran en **arabe**, avec `Directionality.rtl`, dès le premier écran et non à la fin.
- Les états scellés : chargement, vide, erreur, données — un cas par branche.

### 8.3 Le test qui prouve le socle

```dart
testWidgets('le même écran rendu sous deux marques ne partage aucune valeur de marque', …);
```

C'est la traduction directe du critère §3.3.2 du brief. Il tourne sur une marque **fictive** (`brands/_fixture/`), pas sur un client réel : si ajouter une marque de test demande de toucher `lib/`, le socle a un défaut.

### 8.4 Le test qui prouve la modularité

Trois assertions, avec `features.wallet: false` :

1. `/wallet` **n'est pas enregistrée** dans le routeur ;
2. Un lien profond `sabily://wallet` **n'ouvre rien** ;
3. Le cas d'usage `OpenWallet` renvoie `FeatureUnavailable`.

C'est le test qui empêche le drapeau de mentir. Il est le pendant exact du §4.2.

### 8.5 Recette manuelle — ce qui ne s'automatise pas

| Sujet | Pourquoi manuel |
|---|---|
| Paiement Stripe de bout en bout | Compte de test, carte de test, sur appareil réel |
| **Installation d'un profil eSIM** | Impossible en simulateur. Un profil ne s'installe qu'une fois — nécessite des profils de test consommables |
| Apple Pay / Google Pay | Dépend de l'habilitation et du portefeuille de l'appareil |
| Démarrage **sans réseau** | Vérifie le cache de configuration (§6.3) |
| Recette RTL | Un lecteur arabophone, pas une capture d'écran |
| Liens profonds / liens universels | Nécessite les domaines déclarés et une application signée |

### 8.6 Ce qui est repris des 24 tests existants

Le code ne se porte pas (Bloc → Riverpod, et le découpage change). **Les intentions se portent**, et elles ont de la valeur parce qu'elles ont été écrites contre l'API réelle :

| Fichier existant | Intention reprise |
|---|---|
| `auth_client_test`, `auth_models_test`, `auth_repository_test` | Formes de requête/réponse d'authentification, cas d'e-mail déjà utilisé |
| `pack_test`, `pack_api_test` | Analyse de `Pack`, enveloppe `Page` de `/packs/all`, tri |
| `destination_service_test` | Jointure pays × forfaits |
| `currency_test` | Formatage monétaire (**pas** la conversion — supprimée, §6.6) |
| `invoice_test`, `invoice_screen_enhanced_test` | ⚠️ Intentions **non reprises** : elles testent la fabrication de factures sur l'appareil, qui est le défaut R8 |
| `live_api_test` | ⚠️ **Non repris** : il frappe l'API de production |

### 8.7 Les garde-fous de CI — la défense qui tient dans la durée

Cinq contrôles qui **font échouer la construction** (§6.3 point 5 du brief) :

| # | Contrôle | Ce qu'il empêche |
|---|---|---|
| C1 | `grep -ri "sabily" lib/` renvoie **zéro** résultat | Les 163 références mesurées dans l'ancien dépôt (§4.2 de l'analyse) |
| C2 | Aucune valeur hexadécimale ni `Colors.*` dans `lib/modules/` et `lib/shared/` | Les 894 décisions de couleur non configurables (§4.4) |
| C3 | Aucun nom de client dans `lib/core/i18n/` | Les 88 occurrences dans les dictionnaires (§4.3) |
| C4 | `dart tool/check_brands.dart` valide **toutes** les configurations | Une configuration cassée découverte après publication coûte une soumission |
| C5 | `dart tool/check_layers.dart` (règles L1–L4, §1.3) | L'érosion de la règle de dépendance |

Plus : **la CI construit tous les flavors à chaque intégration**, même si un seul est publié (§9.2). C'est le seul moyen de détecter qu'un changement a cassé le client qu'on ne regardait pas — et l'ancien dépôt ne construisait **aucune** de ses trois branches clientes.

---

## 9. Stratégie de construction et de publication

Cette section est écrite pour **ne pas reproduire** les constats du §10 de `ANALYSE-EXISTANT.md`.

### 9.1 Flavors

- **Android** : un `productFlavor` par client — `applicationId`, `resValue` pour le nom affiché, ressources sous `android/app/src/<slug>/res/`. Le nom d'application n'est **jamais** écrit dans `AndroidManifest.xml` (l'ancien dépôt l'y avait en dur).
- **iOS** : un `scheme` + une `configuration` par client — bundle id, `Info.plist`, `Assets.xcassets` par cible.
- **Icônes et écrans de lancement générés** depuis `brands/<slug>/assets/` via `flutter_launcher_icons` et `flutter_native_splash`, configurés par flavor — **jamais à la main**, sinon la dixième application aura l'icône de la troisième.

### 9.2 Un script produit un client

```bash
tool/build_brand.sh <slug> <android|ios> [--release]
```

Il valide la configuration, génère icônes et écran de lancement, sélectionne le flavor, construit. **Si produire un client demande huit commandes mémorisées, la neuvième sera oubliée.**

### 9.3 Environnements

`ANALYSE-EXISTANT.md` §9.3 : *« Chaque développeur, chaque exécution de CI et chaque test frappe la production. »* Corrigé par construction :

| Environnement | Sélection |
|---|---|
| `dev` | `--dart-define=API_BASE_URL=…` surcharge `mobile.apiBaseUrl` |
| `staging` | idem, canal de test interne |
| `prod` | valeur du `brand.json`, aucune surcharge |

⚠️ **`--dart-define` doit être réellement lu.** L'ancienne CI en passait deux et **`String.fromEnvironment` n'apparaissait nulle part** (§4.9 de l'analyse) : les valeurs n'atteignaient jamais le binaire, sans qu'aucun build n'échoue. **Un test de démarrage vérifie que l'URL de base effective correspond à celle attendue pour l'environnement** — c'est la règle du §7.7 du brief : *si cette valeur est fausse, est-ce que ça se voit ?*

### 9.4 Secrets, cloisonnés par client dès le premier jour

L'ancienne CI référence 31 secrets, **aucun préfixé par un client** : publier un deuxième client exigeait d'écraser ceux du premier (§10.5 de l'analyse). Convention retenue, calquée sur le `BACKEND_URL_<SLUG>` du web (§2.4 du brief) :

```
ANDROID_KEYSTORE_B64_<SLUG>     ANDROID_KEYSTORE_PASSWORD_<SLUG>
ANDROID_KEY_ALIAS_<SLUG>        ANDROID_KEY_PASSWORD_<SLUG>
IOS_ASC_KEY_ID_<SLUG>           IOS_ASC_ISSUER_ID_<SLUG>
IOS_ASC_KEY_B64_<SLUG>          PLAY_SERVICE_ACCOUNT_JSON_<SLUG>
API_BASE_URL_<SLUG>             (dev/staging uniquement)
```

**Aucun secret dans le binaire. Clés publiques uniquement.**

### 9.5 Signature — un seul mécanisme

L'ancien dépôt en portait **deux, dont un cassé** : un chemin manuel p12 + profil qui fonctionne, et des appels Fastlane `match(readonly: true)` sans `Matchfile` ni variables `MATCH_*` câblées, qui échouent à la première exécution (§10.4 de l'analyse).

> **Retenu : clé API App Store Connect par client, provisionnement automatique.** Un seul mécanisme, qui supporte N équipes Apple distinctes sans exiger un dépôt de certificats par client. Fastlane `match` n'est **pas** utilisé ; aucun appel `match` ne subsiste.

### 9.6 Deux corrections d'habilitations à porter dès le premier build

| Constat (§10.3 de l'analyse) | Correction |
|---|---|
| `aps-environment` = `development` | `production` dans les configurations Release. À poser même sans push aujourd'hui : sinon les notifications échoueront silencieusement le jour où elles arriveront |
| `com.apple.developer.in-app-payments` = tableau **vide** alors que le code posait un `merchantIdentifier` | Renseigné par flavor **si et seulement si** `mobile.merchantIdentifier` est présent. Sinon Apple Pay est désactivé côté code aussi — pas de bouton qui ne peut pas apparaître |

### 9.7 Version : une seule source de vérité

`pubspec.yaml` est l'autorité. Gradle **lit** `flutter.versionName` / `flutter.versionCode` au lieu de les écraser. L'ancien dépôt publiait `1.1.6+17` sur Android et `1.0.9+8` sur iOS **depuis le même commit** (§1.2 de l'analyse) ; sur N clients cette dérive se multiplie par N.

⚠️ **La dérive est en réalité plus large que ce que le dépôt laisse voir.** La fiche App Store de Sabily annonce, au 10 septembre 2026, la version **`1.3`** — qui ne correspond **à aucune** des deux valeurs présentes dans le dépôt (`1.0.9` dans `pubspec.yaml`, `1.1.6` dans Gradle). Une troisième numérotation existe donc, posée en dehors du dépôt — vraisemblablement dans Xcode au moment de l'envoi. Conséquence pratique : **on ne peut pas, aujourd'hui, dire quel commit correspond à la version iOS installée chez les utilisateurs.** C'est exactement le défaut « une correction jamais déployée » du §7.7 du brief. D'où la règle ci-dessus, et le marqueur de version visible en application (§10.4).

### 9.8 Canaux et cadence

| Canal | Usage |
|---|---|
| Interne (Play internal / TestFlight interne) | Chaque intégration sur `main` |
| Test public (Play beta / TestFlight externe) | Chaque jalon de recette |
| Production | Déploiement **progressif** (5 % → 20 % → 50 % → 100 %) |

Le déploiement progressif n'est pas un luxe : c'est le seul filet contre un défaut de configuration qui ne se voit pas en recette. Corollaire du §4.3 du brief : **toute version publiée doit savoir vivre sans la configuration distante**, et le socle doit tolérer des versions anciennes en circulation.

---

## 10. Réseau, session, sécurité

### 10.1 Une seule couche réseau

Dans le noyau, URL de base issue de la configuration. **Aucun `http.get('https://…')` dans un module** — appliqué par la règle L4 (§1.3). Les hôtes tiers de l'ancienne application (`flagcdn.com`, `api.exchangerate-api.com`, `api.worldbank.org`, `sabily.fr/wp-content/…`) **n'existent pas** dans ce socle : les drapeaux et les visuels de forfaits viennent de la marque ou du backend du client.

### 10.2 Session

- **Jeton JWT en stockage sécurisé** (Keychain / Keystore) via `flutter_secure_storage`. **Une seule couche de stockage** — l'ancienne application en avait deux, dont une seule était effacée à la déconnexion, si bien qu'un utilisateur déconnecté continuait à envoyer son ancien jeton (§7 de `auth-and-state.md`).
- **Aucun mot de passe n'est jamais persisté.** Jamais.
- **`exp` du jeton décodé et vérifié au démarrage et avant chaque requête**, pas seulement à la réception d'un 401. L'ancienne application éjectait l'utilisateur au premier 401, potentiellement en plein tunnel de paiement.
- Expiration et renouvellement gérés **dans l'intercepteur**, jamais dans les écrans.

### 10.3 Isolement des clients

**Chaque client parle à SON backend, et à lui seul.** C'est une exigence contractuelle (§1.2 du brief), pas une commodité.

> **Test exigé :** construire le flavor A et vérifier qu'**aucune URL du client B n'apparaît dans le binaire**. Automatisé en CI, sur l'artefact produit.

### 10.4 Journalisation

**Les journaux ne contiennent ni jeton, ni e-mail, ni ICCID, ni charge de paiement, en production.** L'API sert des personnes physiques.

L'ancienne application comptait **246 `print()`**, dont un qui imprimait **chaque corps de réponse HTTP** et un autre les 20 premiers caractères du secret client Stripe — conservés en build release (§7.8 de l'analyse). Ici : `core/telemetry/` est la seule sortie, `print()` est interdit par le linter, et les champs sensibles sont masqués à la source.

### 10.5 Épinglage de certificat

**À trancher (§12.2).** Utile, mais il rend une rotation de certificat capable de bloquer une application publiée — ce qui est précisément ce qu'on ne peut pas corriger vite.

### 10.6 Une action de sécurité côté plateforme, hors périmètre mobile

⚠️ Le fichier `application-prod.yml` **embarqué dans le JAR du backend** (`mobile/backend/sabily-backend.jar` de l'ancien dépôt) contient en clair : les identifiants de la base **de production** (hôte public, port, utilisateur, mot de passe), le **secret de signature JWT**, des identifiants SMTP, et les identifiants SFTP d'un fournisseur. Toute personne obtenant ce JAR peut **forger un jeton valide pour n'importe quel compte**.

Circonstances atténuantes : le JAR est correctement ignoré par Git, et les clés Stripe qu'il contient sont en mode **test**.

Ce n'est pas un sujet mobile et cela n'entre pas dans ce document, mais **la rotation de ces secrets et leur passage en variables d'environnement doivent être traités côté plateforme**, indépendamment de ce chantier.

---

## 11. Ajouter un client — la procédure cible

C'est le test du critère de validation du §6.2. Un développeur extérieur doit pouvoir suivre ces sept étapes sans poser de question.

```
1. brands/<slug>/brand.json      ← configuration, validée par `dart tool/check_brands.dart`
2. brands/<slug>/assets/         ← logos, visuels, icône, écran de lancement
3. brands/<slug>/README.md       ← les décisions prises pour ce client
4. lib/flavors/main_<slug>.dart  ← void main() => bootstrap('<slug>');
5. Android : productFlavor + applicationId
   iOS     : scheme + configuration + bundle identifier
6. Secrets de CI : *_<SLUG> (§9.4)
7. tool/build_brand.sh <slug>    ← icônes, écran de lancement, build
8. Recette : langues servies, RTL si servi, drapeaux, paiement, installation eSIM, démarrage hors ligne
9. Publication
```

> **Si l'une de ces étapes exige de modifier un fichier de `lib/core/` ou `lib/modules/`, ce n'est pas un contretemps : c'est un défaut du socle.** On corrige le socle, on ne bricole pas le client. Chaque exception acceptée ici est une exception que les clients suivants paieront (§6.4 du brief).

Le `README.md` de chaque marque porte **les décisions que le JSON ne peut pas porter** : pourquoi cette couleur, quel visuel est provisoire, quel champ attend une réponse du client. Un `// TODO` ne dit rien ; un commentaire qui dit *pourquoi* évite qu'un successeur bien intentionné « corrige » une décision validée.

---

## 12. Décisions à faire trancher avant la phase 3

Ces points sont **remontés, pas résolus**. Ils ne bloquent pas la validation de ce document, mais ils bloquent la phase 3.

### 12.1 Mode sombre — supporté ou explicitement désactivé

**Recommandation : explicitement désactivé pour la v1, pour tous les clients.** Un mode sombre à moitié fait est plus coûteux qu'un mode sombre absent, la charte cible est construite sur un fond crème clair, et la décision se prend une fois pour tous les clients. Si elle est prise dans l'autre sens, elle double le nombre de jetons de `BrandConfig` — d'où l'urgence de trancher **avant** le §2.2, pas après.

### 12.2 Épinglage de certificat

Sécurité contre risque de blocage à distance non corrigeable. La contrepartie est asymétrique sur mobile : une rotation de certificat mal coordonnée bloque des applications installées que l'on ne peut pas corriger en quelques minutes.

### 12.3 Versions d'OS minimales

Détermine les capacités eSIM disponibles. L'existant est `minSdk 23` / iOS 15.0.

⚠️ **Les deux applications publiées ne servent déjà pas le même plancher iOS** : la fiche App Store de Sabily annonce **iOS 15.0**, celle d'eSimple **iOS 13.0**. Deux planchers différents issus d'un même code, parce que `spc/esimple` a été branchée avant le commit `c63833b` (« Bump iOS target ») et ne l'a jamais reçu — illustration directe de la dérive des forks mesurée au §4.1 de `ANALYSE-EXISTANT.md`.

Le socle impose **un plancher unique pour tous les clients**. À arbitrer contre la part réelle du parc et contre les API d'installation eSIM natives visées — en sachant qu'un plancher relevé au-dessus de 13.0 retire des utilisateurs à eSimple.

### 12.4 Propriété des comptes stores — la question n'est plus ouverte, seule la décision l'est

La première rédaction de ce document disait, d'après le §10.6 de `ANALYSE-EXISTANT.md`, que l'indice du fichier `note` « suggère sans le prouver » que le compte Apple n'est pas celui du client final. **La vérification des fiches publiques le 10 septembre 2026 l'établit :**

| Application | Éditeur Google Play | Vendeur App Store |
|---|---|---|
| Sabily eSim (`com.sabily.esim`) | **Unception** | **Unception** |
| eSimple (`com.esimple.esim`) | **Unception** | **Unception** |

**Les deux clients sont publiés, sur les deux stores, sous un seul et même compte tiers — ni TRANSASIM, ni Sabily, ni Haus des Handys.**

Deux conséquences, dont une que le client connaît déjà :

- Le §7.2 du brief signale que les textes juridiques du socle web portaient **deux identités contradictoires — « TRANSASIM » d'un côté, « Unception » de l'autre**. La présence sur les stores confirme que l'incohérence n'est pas seulement rédactionnelle : c'est **« Unception » qui est l'éditeur déclaré aux deux stores** pour les deux clients. Un utilisateur de Sabily voit aujourd'hui « Unception » comme éditeur de l'application qu'il installe.
- **Le transfert d'une fiche existante vers un autre compte est possible mais non trivial** (transfert Play, transfert App Store Connect), et il ne peut pas se faire pendant que la fiche reçoit des mises à jour. Si un transfert est souhaité, il doit être planifié **avant** la bascule du §13.5, pas après.

Décision par client, à figer avant toute publication — et elle commande la convention d'identifiants du §3.3.

### 12.5 Paiement : SDK carte ou achat in-app

Risque de rejet au store. À arbitrer tôt, règles Apple et Google en main (§7.4).

### 12.6 Arbitrages design en attente

| Sujet | Constat |
|---|---|
| **Palette** | Trois palettes coexistent dans le Figma, aucune variable. Le §2.2 tranche — **à faire valider** |
| **Typographie** | Trois piles de polices dans le Figma, dont un lot en `Liberation Sans` (= police non définie). **Aucune police compatible arabe** n'est spécifiée nulle part — bloquant pour Sabily |
| **Tunnel de paiement** | Deux maquettes mutuellement incompatibles (code promo + Apple Pay d'un côté, sélecteur de devise de l'autre). Le §6.6 retire le sélecteur de devise ; **le code promo reste à arbitrer** — aucun endpoint correspondant n'a été identifié |
| **Barre d'onglets** | Le gabarit white-label en compte 3, la déclinaison Sabily 4. Le contrat `navEntries(config)` le permet — la question est de savoir si c'est voulu |
| **Écrans Figma non exportés** | `Pack Details`, `Purchase Summary`, `White-Label Store Template` |

---

## 13. Plan de migration et de bascule

### 13.1 Deux applications coexistent pendant le chantier

`Sabily-mobile` **reste en production** et continue de vendre. Ce dépôt construit vers la parité. `ANALYSE-EXISTANT.md` §13.3 identifie ce trou de couverture comme **le vrai risque d'une reconstruction propre** — il est donc traité explicitement.

| Dépôt | Rôle pendant le chantier |
|---|---|
| `Sabily-mobile` (`master`) | En production. Reçoit **uniquement** les six correctifs du §13.5 de l'analyse. **Aucune évolution fonctionnelle**, aucune nouvelle branche `spc/*` |
| `transasim-mobile` (ce dépôt) | Construit vers la parité. Aucune publication en production avant bascule |

**La règle qui protège le plan :** chaque fonctionnalité ajoutée à l'ancienne application pendant le chantier est une fonctionnalité à rattraper dans le nouveau. Le gel fonctionnel de l'ancien est ce qui rend la date de bascule prévisible.

### 13.2 Demandes backend à formuler maintenant

Elles conditionnent le contenu de la parité et ont un délai propre. À verser au cahier de demandes existant côté web (§8.4 du brief).

| # | Demande | Bloque |
|---|---|---|
| B1 | **Endpoint de configuration distante** (`GET /app-config`) | §6.7 — sans lui, tout est figé au build |
| B2 | **Endpoint de factures côté abonné** | L'écran « Mes factures ». `/api/v1/transactions` est ADMIN/AGENCY seulement ; il n'existe **rien** pour un abonné |
| B3 | **Code d'erreur distinct pour « paiement déjà consommé »** | La reprise (§7.2) doit distinguer « déjà provisionné » (= succès) d'un vrai échec. Aujourd'hui les deux sont un 400 générique |
| B4 | **Prix par devise** | Le multi-devises (§6.6) |
| B5 | **Endpoint de recharge (top-up)** | La maquette `eSIM Tracking` porte un bouton « Top Up Data ». Rien de tel n'existe côté application ni côté API |
| B6 | **Authentification tierce Google / Apple** | Les endpoints n'existent pas. Quasi obligatoire côté iOS dès qu'un autre fournisseur tiers est proposé |
| B7 | **`remainingData` en double émission** avec `rmainingData` | Corriger la faute de frappe sans casser les applications installées |
| B8 | **`Accept-Language` honoré** | Le backend embarque `messages_{fr,en,ar_LY}.properties` et le client n'envoie pas l'en-tête |
| B9 | **Consommation en lot** (voir §13.2.1) | L'écran « Mes eSIM ». Une requête par eSIM pour l'usage, et rien pour l'obtenir en une fois |
| B10 | **Validation d'un code promo avant achat** | L'écran de paiement. `SubscriptionModel` accepte un `voucherToken` au moment de l'abonnement, et `/v1/subscriptions/voucher` + `/redeem/{voucherToken}` existent — mais **rien ne permet de chiffrer une remise avant le paiement**. Le champ est donc présent et l'application dit qu'elle ne peut pas encore le vérifier, plutôt que d'afficher un total inventé |
| B11 | **Clé Stripe de test réelle** | La vérification sur appareil du chemin de l'argent. `brands/sabily/brand.json` porte `pk_test_PLACEHOLDER_AWAITING_CLIENT`, qui **passe** le validateur (il ne contrôle que le préfixe `pk_`). Voir §7.5 |

#### 13.2.1 Le N+1 de « Mes eSIM » : ce qui est réellement nécessaire

Vérifié dans le JAR déployé (pool de constantes de `SubPlanResourceExt`,
`EsimProfileResourceExt`, `SubscriberResourceExt`), **pas depuis la mémoire des
maquettes**.

`GET /api/v1/sub-plans/subscriber/details` — l'endpoint agrégé proposé —
**n'existe pas**. `SubPlanResourceExt` expose exactement `/all`,
`/esim-profile/{idEP}`, `/pack/{idPack}`, `/subscriber`, `/subscriber/{idSub}`.

⚠️ Conséquence à ne pas manquer : `/subscriber/details` **correspond** à la
route `/subscriber/{idSub}`, avec `"details"` lié à un `Long`. Le serveur
répond donc **400, pas 404**. Un code défensif qui traiterait « 404 ⇒ endpoint
absent, je bascule sur le plan B » se tromperait de branche.

**Mais l'endpoint agrégé n'est pas nécessaire pour la liste.** `SubPlanDTO`
porte déjà les objets imbriqués `pack`, `esimProfile`, `subscriber`,
`transaction` ; `PackDTO` porte `name`, `countries`, `dataValue`/`dataUnit`,
`validityDuration`, `unlimited`, `prices` ; `EsimProfileDTO` porte
`smdpAddress`, `matchingId`, `activationCode`, `simSerial`, `status`.

Autrement dit : **un seul appel**, `GET /api/v1/sub-plans/subscriber`, contient
tout ce qu'il faut pour peindre la liste ET pour construire la chaîne LPA. Les
16–21 requêtes séquentielles de l'ancienne application (`ANALYSE-EXISTANT.md`)
rechargeaient des données qu'elle tenait déjà.

Le seul manque réel est **l'usage**. `ConsumptionsModel`
(`totalData`, `rmainingData`, `unit`, `startDate`, `endDate`) est servi par
`SubscriberResourceExt` via deux méthodes, toutes deux **unitaires** :
`getConsumption(long)` et `getConsumptionForBookedEsim(String simSerial)`. Il
n'existe aucun moyen d'obtenir la consommation de N eSIM en une fois.

**D'où B9**, formulée plus étroitement que la demande S3 d'origine : soit
`consumption` embarqué dans `SubPlanDTO`, soit un `GET /subscribers/consumption`
qui renvoie l'ensemble. La demande S3 telle qu'écrite demandait un endpoint
dont l'essentiel existe déjà.

**En attendant**, l'écran est construit défensivement (§9.4) : la liste se peint
sur un appel, et l'usage arrive ensuite **en parallèle** et **seulement pour
les eSIM actives** — jamais en série.

### 13.3 Ce que « parité » veut dire, précisément

La bascule est décidée sur une liste, pas sur une impression.

**Parcours qui doivent fonctionner :**

| # | Parcours | Critère |
|---|---|---|
| P1 | Catalogue : destinations, recherche, fiche destination, fiche forfait | Sans authentification, comme aujourd'hui |
| P2 | Inscription e-mail + OTP, connexion, mot de passe oublié | Champs pilotés par `registration.fields` |
| P3 | **Achat** : forfait → paiement → eSIM provisionnée | **Montant exact**, commande serveur avant la feuille, reprise après échec |
| P4 | Mes eSIM : liste, QR, texte copiable, consommation | QR construit depuis `smdpAddress` + `matchingId` |
| P5 | Bon d'achat | ⚠️ **La réponse serveur est lue** — pas de succès inconditionnel |
| P6 | Profil, support, textes légaux | Textes juridiques **servis à distance** |
| P7 | 7 langues, dont l'arabe en RTL | Recette par un locuteur arabophone |
| P8 | Démarrage sans réseau | Affichage correct depuis le cache |
| P9 | Module `wallet` activable par configuration | Test du §8.4 |

**Retiré délibérément — et c'est une décision, pas un manque :**

| Retiré | Raison |
|---|---|
| Écran « Gestion eSIM de l'appareil » | 8 méthodes sur 12 sont des bouchons ; l'écran ne peut structurellement rien afficher (§6.2 de l'analyse) |
| Installation eSIM « en un geste » via `flutter_esim ^0.0.4` | Remplacée par une implémentation native (`CTCellularPlanProvisioning` / `EuiccManager`), traitée comme **une amélioration au mieux** : le QR et la saisie manuelle restent le chemin fiable |
| Build Flutter Web | Son tunnel de paiement n'a jamais fonctionné (§7.6 de l'analyse) |
| Fabrication de factures sur l'appareil | Défaut de conformité (R8). Remplacée par B2, ou l'écran n'est pas livré |
| Sélecteur de devise | §6.6, en attente de B4 |
| Connexion Google / Apple | Les endpoints n'existent pas (§7.7 de l'analyse). Revient avec B6 |

### 13.4 Ordre de travail

Repris du §6.3 du brief, ajusté :

1. **Le noyau d'abord** : `BrandConfig` + chargeur + validation + thème dérivé + i18n + réseau + session + routeur + registre de modules, **avec ses tests**. Rien d'affichable — c'est normal.
2. **Le flavor Sabily**, jusqu'à une application qui démarre, affiche ses couleurs et son logo **depuis la configuration**, dans les sept langues. **Premier jalon vérifiable (J3).**
3. **Les modules, un par un**, du plus structurant au plus périphérique : `catalog` → `account` → `esim` → `checkout`.
4. **Le module `wallet` squelette**, pour prouver le point d'extension.
5. **Les garde-fous de CI** (§8.7).

### 13.5 Comment la bascule est décidée

| Étape | Critère de passage |
|---|---|
| **J3** — Le socle démarre aux couleurs de la configuration | Démonstration |
| **J4** — Sabily complet en canal de test | Les 9 parcours P1–P9 passent la recette. **P3 vérifié avec un paiement réel de bout en bout** |
| **J5** — Production, déploiement progressif | 5 % → 20 % → 50 % → 100 %, avec un critère d'arrêt écrit : taux d'échec de provisionnement, taux de plantage, tickets de support |
| **Fin de vie de l'ancienne application** | **Pas le jour de la mise en production.** L'ancienne reste publiée et fonctionnelle jusqu'à ce que le déploiement progressif atteigne 100 % et se stabilise. À la manière du web : **on observe** |

⚠️ **Ne pas enchaîner sur un deuxième client le jour de la mise en production de Sabily.** La phase 4 commence après observation.

---

## 14. Hors périmètre, dit explicitement

| Hors périmètre | Précision |
|---|---|
| **BtoB / revendeur, sous toutes ses formes** | Ni module, ni squelette, ni drapeau, ni écran, ni lien sortant. Décision §0. Si le BtoB arrive un jour sur mobile, ce sera un document distinct. **Note pour la phase 2 :** le backend expose déjà `/api/v1/agencies/register` et les maquettes APRÈS contiennent un formulaire de candidature en application — ces éléments existent, ils ne sont simplement pas utilisés |
| **TransaPay lui-même** | Seul son **squelette de module** est livré : une route, un écran « bientôt disponible », un drapeau, zéro logique |
| **Back-office / administration** | Reste web |
| **Flutter Web, macOS, Linux, Windows** | Android et iOS uniquement |
| **Notifications push** | Aucune intégration. L'habilitation iOS est corrigée (§9.6) pour ne pas bloquer une arrivée ultérieure, mais rien n'est construit |
| **Les trois autres clients** (`esimple`, `djezzy`, `castrum`) | Phase 4. Ce document couvre le socle et **Sabily comme client modèle** |
| **Le change / multi-devises** | §6.6, en attente de B4 |
| **La correction du backend** | Les défauts établis au §7 de `ANALYSE-EXISTANT.md` sont des demandes (§13.2), pas des travaux de ce chantier |
| **Le nettoyage de `Sabily-mobile`** | L'ancien dépôt reçoit **uniquement** les six correctifs du §13.5 de l'analyse |

---

## 15. Ce qui reste à valider pour lever le jalon J2

| # | À valider | Par |
|---|---|---|
| 1 | **La table des flavors (§3)**, et nommément l'exception `com.sabily.esim` | Client — bloquant |
| 2 | **Le contrat `BrandConfig` (§2)**, et en particulier le mapping des cinq rôles de couleur (§2.2) | Client + design |
| 3 | La convention d'identifiants pour les clients suivants (§3.3) | Client |
| 4 | Les six décisions du §12 | Client |
| 5 | La liste de parité et la liste des retraits (§13.3) | Client — c'est elle qui définit « fini » |
| 6 | Les huit demandes backend (§13.2) | Plateforme |

---

*Fin du document d'architecture. Conformément au §6.2 du brief, aucun code applicatif n'est écrit avant sa validation.*
