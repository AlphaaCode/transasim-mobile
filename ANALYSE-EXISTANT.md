# ANALYSE-EXISTANT — Application mobile Sabily

> **Phase 1** du chantier décrit dans `BRIEF-MOBILE-WHITE-LABEL.md` (§6.1).
> **Livrable :** état des lieux, dette white-label chiffrée, risques, et recommandation argumentée.
> **Date :** 10 septembre 2026.
> **Aucune modification de code n'a été faite.** Ce document est un inventaire, pas un commit.

---

## 0. Périmètre, sources et méthode

### 0.1 Ce qui a été analysé

| Objet | Référence exacte |
|---|---|
| Dépôt mobile | `Sabily-mobile`, branche `rebuild/expo`, HEAD `c41bc04` |
| Référence de comparaison | `master`, HEAD `7c21c61` (10 août 2026) |
| Branches clients | `origin/spc/sabily`, `spc/esimple`, `spc/djezzy`, `spc/castrum` |
| Backend | `mobile/backend/sabily-backend.jar` — Spring Boot 3.4.1 / JHipster, paquet `com.tamarisoft.sabily`, construit le **4 juillet 2026**, branche `sprint_0`, commit `1285990` |
| Maquettes AVANT | `E:\disk f\Work\Sabily\rebrand\mobile\old` (21 fichiers) |
| Maquettes APRÈS | `E:\disk f\Work\Sabily\rebrand\mobile\new` (18 fichiers) |
| Figma | fichier `iY7aEuS0N07tOKIB4Lfmx6`, 1 page, 19 cadres mobiles (390 pt) |

### 0.2 Sur quoi ce document s'appuie

Cinq documents d'audit préexistants couvrent déjà ce dépôt en détail : `handoff/payment-architecture.md`, `esim-lifecycle.md`, `api-contract.md`, `auth-and-state.md`, `rebuild-brief.md`. Ils ont été lus intégralement et servent de socle. Ce document **ne les recopie pas** : il les synthétise selon la grille du §6.1 du brief, **revérifie les chiffres contre l'arbre de travail d'aujourd'hui**, et ajoute ce qu'ils ne couvraient pas :

- les **comptes stores, certificats et profils de signature** (dernière ligne de la grille §6.1) ;
- la **couverture fonctionnelle notée contre le tableau §3.4 du brief**, et croisée avec les maquettes APRÈS et le Figma ;
- la **réconciliation backend**, tranchée sur le bytecode du JAR plutôt que déduite du client ;
- l'inventaire de la **dette white-label chiffrée fichier par fichier**, dans la forme de l'audit web cité au §7 du brief.

### 0.3 Vérification que rien n'a bougé depuis l'audit

Le code Flutter n'a **pas changé** depuis l'audit. `git diff master..HEAD` sur `lib/`, `android/`, `ios/`, `assets/` et `pubspec.yaml` ne renvoie **aucune différence**. Les seuls ajouts de la branche courante sont le dossier `mobile/` (chantier Expo, voir §11) et trois workflows CI. Toutes les citations `fichier:ligne` des cinq documents d'audit restent valides.

### 0.4 Comment lire les chiffres

Chaque nombre de ce document est reproductible. La commande qui le produit est donnée en annexe (§15). Quand un chiffre diverge de celui d'un document d'audit antérieur, c'est signalé et c'est **le comptage d'aujourd'hui qui fait foi**.

---

## 1. Ce que c'est, techniquement

*Grille §6.1 — ligne 1 : version Flutter/Dart, état des dépendances, plateformes ciblées.*

| | |
|---|---|
| Cadre | Flutter / Dart, contrainte `sdk: ^3.5.3` (`pubspec.yaml:22`) |
| Version en CI | **`3.24.5`**, épinglée dans 3 workflows |
| Nom de paquet Dart | `sabily_mobile` (`pubspec.yaml:1`) |
| Taille | **170 fichiers Dart, 36 982 lignes** ; `lib/screens/` seul = **13 409 lignes / 29 écrans** (≈ 460 lignes/écran) |
| État | BLoC `flutter_bloc ^9.1.1`, `Navigator` 1.0 + `onGenerateRoute`, aucune bibliothèque de routage |
| Paiement | Stripe uniquement (`flutter_stripe ^10.0.0`) |
| Journalisation | **246 appels `print()`**, conservés en build release |
| Tests | **24 fichiers** dans `test/` |

### 1.1 Plateformes

Six dossiers de plateforme existent, **trois sont réels** :

| Plateforme | État |
|---|---|
| Android | Configuré, signé, publié sur le Play Store. `compileSdk 36`, `minSdk 23` |
| iOS | Configuré, signé, publié sur TestFlight. Cible de déploiement 15.0 |
| Web | Construit et déployé sur Firebase Hosting (site `sabilymobile`). **Son tunnel de paiement ne fonctionne pas** (§7.6) |
| macOS / Linux / Windows | Échafaudage Flutter jamais touché |

### 1.2 Incohérence de version — trois sources de vérité

| Source | Version | Build |
|---|---|---|
| `pubspec.yaml:19` | `1.0.9` | `8` |
| `android/app/build.gradle:37-38` | **`1.1.6`** | **`17`** |
| iOS `project.pbxproj` | suit `pubspec` | suit `pubspec` |

Gradle **écrase** pubspec. Depuis un même commit, **Android publie 1.1.6/17 pendant qu'iOS publie 1.0.9/8** — neuf numéros de build d'écart. À traiter avant toute publication multi-client, où l'erreur se multiplierait par N.

### 1.3 Dépendances : trois entrées mortes ou périmées

| Dépendance | Problème |
|---|---|
| `firebase_core ^3.3.0`, `firebase_auth ^5.2.0` | **Jamais initialisées.** `Firebase.initializeApp()` n'est appelé nulle part ; `lib/firebase_options.dart` est généré mais importé par rien. À supprimer. |
| `provider ^6.1.5` | Déclarée, **jamais utilisée** — aucun `ChangeNotifierProvider` dans le dépôt. |
| `flutter_esim ^0.0.4` | Version **0.0.x** sur le chemin le plus critique du produit (§6). |
| `flutter_stripe_web` | Déclarée **sans contrainte de version**. |
| `google_fonts ^6.1.0` | Utilisée **uniquement pour embarquer Roboto dans les PDF**, jamais pour l'interface. |

---

## 2. L'architecture réelle

*Grille §6.1 — ligne 2 : couches, couplage, testabilité.*

### 2.1 Ce qui est propre

Le découpage `client → repository → bloc → écran` est réel et suivi sur la majorité du chemin de données :

```
lib/api/clients/      11 fichiers — HTTP brut par domaine
lib/api/repository/   10 dépôts — fine couche de délégation
lib/blocs/            état par fonctionnalité
lib/screens/          29 écrans
```

C'est testable, ça se lit, et **ça se transpose à n'importe quel cadre technique**. C'est, avec les contrats d'API, l'actif principal du dépôt.

### 2.2 Ce qui ne l'est pas

- **Deux paradigmes d'état cohabitent.** Certains écrans passent par les blocs, d'autres appellent `serviceLocator.*Repository` directement depuis du code `setState` (`EsimConsommationScreen.dart:63-64`, `profilscreen.dart:50`, `regions_screen.dart:37,46`).
- **Injection de dépendances artisanale.** `ServiceLocator` (`lib/common/service_locator.dart:29-135`) est un singleton fait main avec des champs `late final`, sans garde de ré-entrance. Cinq instances de `HttpClient` y sont câblées, dont quatre sans authentification.
- **Abstraction à moitié faite.** Huit interfaces de dépôt existent dans `lib/api/repository/interfaces/`, **quatre ne sont importées par rien** — les classes concrètes ne les implémentent donc pas.
- **Écrans obèses** : `invoice_screen.dart` 1 060 lignes, `homescreensabily.dart` 968, `MyEsimsScreen.dart` 908, `EsimConsommationScreen.dart` 904.
- **Aucune bibliothèque de composants.** `lib/widgets/` contient 7 widgets, tous fonctionnels (sélecteur de devise, tuile de destination, scanner QR…), **aucun présentationnel**. Pas de bouton partagé, pas de carte partagée, pas d'état vide partagé. Conséquence mesurable : les seuils de couleur du pourcentage de consommation sont **inversés entre deux onglets du même écran** (`MyEsimsScreen.dart:507-509` vs `:668-670`).
- **Routage non typé** : arguments en `Map<String, dynamic>` avec transtypage à l'exécution (`args?['pack'] as Pack?`), et un `Scaffold` « argument manquant » écrit à la main dans chaque cas, **en français en dur**.

### 2.3 Code mort — environ 2 000 lignes

| Catégorie | Détail |
|---|---|
| Écrans non routés (~1 100 lignes) | `SubscriptionScreen.dart` (473 — importé par le routeur, jamais routé), `SubscriptionScreenWithBloc.dart` (377), `EsimDetailsScreen.dart` (379), `invoice_screen_new.dart` (190), `language_demo_screen.dart` (146), `homescreensabily_clean.dart` (**0 octet**) |
| Blocs orphelins | `auth_bloc.dart`, `auth_bloc_temp.dart`, `esim_bloc.dart`, `esim_bloc_temp.dart`, `pack_bloc.dart`, `pack_bloc_temp.dart`, `subscriber_bloc.dart`, `area_bloc.dart` — doublons à plat de la version dossier-par-fonctionnalité. **Des fichiers nommés `_temp` sont en source de production.** |
| Autres | `common/http_client_refactored.dart` (réécriture abandonnée), `common/currency_service.dart` (doublon), `api/models/agency.dart`, 4 interfaces sur 8, et **`lib/test_navigation_main.dart` — un second `main()` en source de production** |
| Surface d'API morte | **24 endpoints** câblés qu'aucun écran vivant n'atteint, plus 3 commentés (`api-contract.md` §10) |

---

## 3. La gestion d'état

*Grille §6.1 — ligne 3 : cohérent ou non.*

**BLoC (`flutter_bloc ^9.1.1`), globalement sain, avec deux bons réflexes à conserver :**

1. **`PackPurchaseBloc` est délibérément non global** — créé à neuf par tunnel d'achat (`app_router.dart:180-183`). L'état d'achat ne survit pas à la navigation. C'est le bon instinct ; à reproduire.
2. `DeviceEsimBloc` est de même limité à son écran.

Dix blocs sont fournis globalement dans un `MultiBlocProvider` (`main.dart:61-126`). Deux remarques :

- `DestinationBloc` **construit son propre `DestinationService`**, contournant le localisateur.
- `InvoiceBloc` est instancié et **aucun écran vivant ne le consomme**.

**Les erreurs sont explicitement avalées.** `MyEsimsScreen.dart:146-171` et `EsimConsommationScreen.dart:92-102` enregistrent des `BlocListener` dont **tout le corps de la branche d'erreur est commenté**.

**Persistance locale** : tout dans `shared_preferences`. Pas de SQLite, pas de Hive, **aucun cache hors ligne** des forfaits ou des profils eSIM. Mode avion = écrans vides.

> **Lecture pour le §5.5 du brief.** Le brief autorise à garder Bloc « si l'analyse révèle un existant Bloc conséquent et sain ». Il est **conséquent** mais **pas homogène** : deux paradigmes coexistent, et la moitié des blocs à plat est morte. Garder Bloc est défendable ; garder *ce* câblage-là ne l'est pas.

---

## 4. La dette white-label, chiffrée

*Grille §6.1 — ligne 4 : où « Sabily » est écrit en dur. C'est l'inventaire central de ce document.*

L'audit web cité au §7.5 du brief parle de « **73 couleurs en dur dans 11 fichiers** ». Voici l'équivalent mobile, dans la même forme.

### 4.1 Le fait le plus important : le white-label existe déjà, sous forme de forks

**Quatre clients sont aujourd'hui livrés par quatre branches durables.** C'est exactement ce que le critère §3.3.1 du brief interdit (« Aucun fork par client, aucune branche `client/xxx` durable »).

| Branche | Dernier commit | `APP_NAME` | `applicationId` | `versionName` |
|---|---|---|---|---|
| `origin/spc/sabily` | 10 août 2026 | `Sabily` | `com.sabily.esim` | `1.1.6` |
| `origin/spc/esimple` | 31 juillet 2026 | `eSimple` | `com.esimple.esim` | `1.1.8` |
| `origin/spc/djezzy` | 18 juillet 2026 | `Djezzy eSIM` | `com.djeezy.esim` | `1.1.6` |
| `origin/spc/castrum` | 18 mai 2026 | `Castrum eSim` | `com.castrum.esim` | `1.0.7` |

**Le coût de ce modèle, mesuré :**

| Branche | Retard / avance sur `master` | Fichiers différents | dont `lib/` | dont `lib/` écrit à la main |
|---|---|---|---|---|
| `spc/esimple` | 35 derrière, 20 devant | 151 | 84 (+5 841 / −1 705) | **67 fichiers, +2 521 / −1 590** |
| `spc/djezzy` | 35 derrière, 16 devant | 148 | 80 (+5 614 / −1 654) | — |
| `spc/castrum` | 35 derrière, 2 devant | 129 | 66 (+1 322 / −1 058) | — |

`lib/` compte environ 153 fichiers écrits à la main. **Chaque client fait donc diverger ~44 % du code applicatif**, et la divergence ne porte pas sur des assets : elle porte sur `email_register_screen.dart` (+279/−253), `profilscreen.dart` (+221/−58), `homescreensabily.dart` (+134/−121), `pack_purchase_screen.dart`, `login.dart`, `MyEsimsScreen.dart`, `auth_bloc.dart`. **Ce sont des forks de logique métier.**

Trois conséquences déjà visibles :

- Les trois branches clientes sont **35 commits en retard** sur `master`. Toute correction du noyau depuis fin juillet n'existe que chez Sabily.
- Les versions ont divergé de façon incohérente (1.1.8 chez le client secondaire, 1.0.7 chez le quatrième).
- **`spc/castrum` pointe encore `WEB_URL` sur `https://sabily.fr`.** C'est littéralement le §7.4 du brief — un deuxième client qui hérite des adresses du premier — et c'est déjà arrivé, en production potentielle.

> C'est le chiffre à retenir de toute la phase 1 : **le socle mobile n'a pas à être inventé, il a à remplacer un mécanisme qui existe et qui coûte 2 500 lignes de divergence par client.**

### 4.2 Le nom de la marque dans le code

| Mesure | Occurrences | Fichiers |
|---|---|---|
| `import 'package:sabily_mobile/…'` | **527** | 115 |
| Références à la marque **hors** imports de paquet | **163** | **27** |
| — dont littéraux de chaîne | 126 (81 distincts) | — |
| — dont identifiants (`HomeScreenSabily`, `ProfileScreenSabily`, noms de fichiers…) | 37 | — |

Les 27 fichiers, par densité :

| Fichier | Occurrences |
|---|---|
| `lib/screens/homescreensabily.dart` | 25 |
| `lib/generated/gen_l10n/app_localizations.dart` | 14 |
| `lib/generated/gen_l10n/app_localizations_{sl,fr,es,en,de}.dart` | 9 chacun |
| `lib/screens/profilscreen.dart` | 8 |
| `lib/generated/gen_l10n/app_localizations_sq.dart` | 8 |
| `lib/firebase_options.dart` | 8 |
| `lib/api/models/price.dart` | 8 |
| `lib/api/models/pack.dart` | 7 |
| `lib/services/invoice_pdf_service.dart` | 6 |
| `lib/screens/EsimConsommationScreen.dart` | 5 |
| `lib/services/stripe_ui_service_mobile.dart` | 4 |
| `lib/generated/gen_l10n/app_localizations_{ur,ar}.dart` | 4 chacun |
| 14 autres fichiers | 1 à 3 chacun |

Deux points méritent d'être isolés :

- **`lib/api/models/price.dart` — 8 occurrences.** Le modèle de prix porte un champ `sabilyAmount`, et le client le **préfère systématiquement** à `amount` (`pack.dart:188, 196, 205, 229, 251`). Le nom du client est donc dans le **contrat de données**, côté mobile *et* côté backend (`PriceDTO.getSabilyAmount()`, vérifié dans le JAR). C'est la dette la plus profonde : elle ne se corrige pas côté mobile seul.
- **`lib/screens/homescreensabily.dart`, `homescreensabily_clean.dart`** — le nom du client est dans le **nom de fichier** de l'écran d'accueil.

### 4.3 La marque dans les dictionnaires de traduction

C'est l'erreur §7.1 du brief (« 16 occurrences de Sabily par langue »), reproduite ici.

| Fichier ARB | Occurrences de « Sabily » | Clés porteuses |
|---|---|---|
| `lib/l10n/app_en.arb` | **17** | 11 |
| `lib/l10n/app_es.arb` | 12 | 9 |
| `lib/l10n/app_fr.arb` | 12 | 9 |
| `lib/l10n/app_sl.arb` | 12 | 9 |
| `lib/l10n/app_de.arb` | 11 | 8 |
| `lib/l10n/app_sq.arb` | 10 | 7 |
| `lib/l10n/app_ar.arb` | 7 | 4 |
| `lib/l10n/app_ur.arb` | 7 | 4 |
| **Total** | **88** | — |

Exemples réels (`app_en.arb`) :

```
"appTitle":            "Sabily eSim"
"copyright":           "© 2025 Sabily"
"voucherValidity":     "Sabily vouchers are valid for 30 days from the activation date."
"iAcceptTerms":        "I accept Sabily's Terms & Conditions…"
"byCreatingAccount":   "…the Terms & Conditions and privacy policy of Sabily."
"enjoyPremiumOffer":   "Enjoy the Premium Offer from Sabily Reserved for Professionals!"
```

**Pire que le web : trois clés portent le nom du client dans leur propre identifiant**, répliqué dans les 8 fichiers (24 déclarations) :

```
"sabily":                   "Sabily"          ← libellé d'onglet
"joinSabily":               "Join Sabily"
"subscribeToSabilyPremium": "Subscribe to Sabily Premium"
```

Une clé de dictionnaire est un contrat entre le socle et les surcharges de marque. Une clé nommée `joinSabily` ne peut pas être surchargée proprement par eSimple : le deuxième client hérite du nom du premier **jusque dans la clé**.

### 4.4 Les couleurs

Structurellement **meilleur que le web, et pourtant plus contraignant**.

| Mesure | Valeur | Fichiers |
|---|---|---|
| Jetons de couleur définis (`static const int` ARGB) | **25** | 1 (`lib/common/theme.dart`) |
| Références `CustomTheme.` | **862** | **37** |
| Littéraux `Color(0x…)` hors du fichier de thème | **1** | 1 |
| `Colors.*` bruts (Material) | **31** | **7** |
| **Total des décisions de couleur** | **894** | **39** |

Les 31 `Colors.*` bruts, par fichier :

| Fichier | Occurrences |
|---|---|
| `lib/screens/invoice_screen.dart` | 14 |
| `lib/screens/all_packs_screen.dart` | 8 |
| `lib/screens/otp_verification_screen.dart` | 4 |
| `lib/screens/device_esim_screen.dart` | 2 |
| `lib/screens/voucherscreen.dart` | 1 |
| `lib/screens/pack_purchase_screen.dart` | 1 |
| `lib/screens/SubscriptionScreenWithBloc.dart` | 1 |

Répartition : `Colors.teal` ×12, `Colors.blue` ×10, `Colors.grey` ×8, `Colors.green` ×1.

**Le littéral isolé compte double :** `lib/services/stripe_ui_service_mobile.dart:43` fixe l'accent de la feuille de paiement Stripe à `Color(0xFF015552)` — une valeur **qui ne correspond à aucun jeton du thème** (le primaire est `0xFF2B6E73`). C'est le cas §2.6 du brief : le SDK tiers ne lit pas `ThemeData`, la couleur voyage comme une donnée, et personne ne l'a synchronisée.

> **Nuance importante pour la comparaison avec le web.** 894 contre 73 ne veut pas dire « douze fois pire ». Le mobile a fait le bon geste : la palette est **centralisée**. Mais elle est centralisée en `static const int` — donc **figée à la compilation**. Le web servait des variables CSS résolues par requête ; le mobile ne peut pas changer une couleur sans une soumission au store. **Le problème n'est pas la dispersion, c'est l'immuabilité.** Les 862 appels ne sont pas 862 corrections à faire : ils sont 862 points qui deviendront corrects le jour où `CustomTheme` sera dérivé d'une `BrandConfig` au lieu d'être une constante — plus 32 exceptions, dans 8 fichiers, qui ne le deviendront pas toutes seules.

**Écart avec la cible.** La charte visée (§4.10 des maquettes, et `rebuild-brief.md` §5) n'est pas une retouche :

| Rôle | Actuel | Cible | Nature de l'écart |
|---|---|---|---|
| Primaire | `#2B6E73` sarcelle | `#003c3a` vert profond | Même famille, nettement plus sombre |
| Accent | `#4DB6AC` sarcelle clair | `#fadb14` jaune | **Inversion complète.** Un accent « calme » devient un accent « appel à l'action » — c'est une refonte de hiérarchie visuelle, pas une teinte à remplacer |
| Fond | `#C9DAD7` gris-sarcelle | `#f9f2d3` crème chaud | Froid → chaud. Change la température de tous les écrans |
| Premium | `#3d4f65` bleu ardoise, **commenté « Gold »** | `#735c00` bronze | La valeur actuelle contredit son propre commentaire |

### 4.5 La typographie

| Mesure | Valeur |
|---|---|
| Styles nommés définis (`TextTheme`) | **0** |
| Littéraux `fontSize:` en ligne | **288** |
| Valeurs distinctes | **14** (16 ×82, 14 ×49, 12 ×44, 18 ×32, 20 ×22, 13 ×18, 24 ×14, 10 ×9, 22 ×5, 11 ×5, 15 ×3, 28 ×2, 26 ×2, 32 ×1) |
| Police globale | `'Roboto'` — une chaîne nue dans `MaterialApp.theme` (`main.dart:139`) |
| Police compatible arabe | **aucune déclarée** — l'app s'en remet au repli système |

Il n'y a **rien à migrer**. C'est du terrain vierge : coûteux, mais propre.

### 4.6 URL, hôtes et adresses e-mail en dur

**12 littéraux d'URL dans 8 fichiers, 7 hôtes distincts**, dont 4 tiers non contractualisés :

| Hôte | Rôle | Emplacement |
|---|---|---|
| `api.sabily.fr` | Backend | `lib/common/config.dart:3` — une **`const`** |
| `sabily.fr` | Images de couverture des forfaits | `lib/api/models/pack.dart:58` — **l'hôte WordPress du client est dans le modèle de données** |
| `sabily.fr` | Couverture de repli | `lib/widgets/pack_cover_image.dart:60` |
| `sabily.web.app` | Inscription revendeur, CGU, contact | `lib/screens/profilscreen.dart:459, 474, 508` |
| `flagcdn.com` | Drapeaux des pays | `country.dart:75,77` ; `destination.dart:152` |
| `api.exchangerate-api.com` | **Taux de change pilotant les prix affichés** | `lib/services/currency_service.dart:7` |
| `api.worldbank.org` | Déduction de région en repli | `lib/api/repository/area_repository.dart:80` |
| `api.stripe.com` | Chemin mort | `lib/common/config.dart:25` |

**2 adresses e-mail en dur :** `support@sabily.fr` (`invoice_pdf_service.dart:294`, imprimée sur les factures PDF) et `invite@sabily.fr` (`stripe_ui_service_mobile.dart:37`, envoyée à Stripe comme e-mail de facturation **pour tous les paiements**, alors que l'utilisateur est authentifié avec un vrai e-mail).

### 4.7 Les chemins d'assets en dur

**22 littéraux `'assets/…'` dans 14 fichiers.** C'est le §7.4 du brief mot pour mot.

| Chemin | Occurrences |
|---|---|
| `assets/images/logo.png` | **8** — le logo de marque, écrit dans huit widgets |
| `assets/images/google.png` | 3 |
| `assets/images/saoudie.jpg` | 2 — photo de destination spécifique à Sabily |
| `assets/images/sabilycarte.png` | 2 |
| `assets/images/header.PNG` | 2 |
| `assets/images/apple.png` | 2 |
| `assets/images/splash_animated.gif`, `logonext.png` | 1 chacun |
| `assets/$type-$code.pdf` | 1 — les CGU/confidentialité, **embarquées dans le binaire** |

Le dossier `assets/images/` contient **4 fichiers nommés d'après la marque** (`logosabily.png`, `logosabily2.png`, `logosabily3.png`, `sabilycarte.png`) plus `assets/icon/sabily.icon/`.

**Point réglementaire.** Il existe **un seul jeu** de CGU et de politique de confidentialité, en 4 langues (`assets/terms-{en,sl,fr,ar}.pdf`), **embarqué dans le bundle**. Le §7.2 du brief est explicite : ces textes engagent légalement le client et doivent être modifiables sans livraison. Aujourd'hui, **une mise à jour juridique demandée par un client déclenche une soumission au store**, et le même PDF est servi à tous les clients des branches `spc/*`.

### 4.8 Le natif, le web, et les stores

**35 références à la marque dans 10 fichiers de configuration suivis en Git :**

| Fichier | Occurrences |
|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` | 9 |
| `android/app/google-services.json` | 6 |
| `web/index.html` | 5 |
| `ios/Runner/Info.plist` | 4 |
| `ios/Runner/GoogleService-Info.plist` | 3 |
| `android/app/build.gradle` | 2 |
| `android/app/src/main/AndroidManifest.xml` | 2 |
| `web/manifest.json` | 2 |
| `android/…/kotlin/com/sabily/esim/MainActivity.kt` | 1 (le **chemin du paquet** porte la marque) |
| `ios/exportOptions.plist` | 1 |

**Trois noms d'affichage différents pour une seule application :**

| Source | Valeur |
|---|---|
| `AndroidManifest.xml:13` | `Sabily eSim` |
| `Info.plist` → `CFBundleDisplayName` | `Sabily Mobile` |
| `Info.plist` → `CFBundleName` | `sabily_mobile` |
| `app_en.arb` → `appTitle` | `Sabily eSim` |

### 4.9 La couche de configuration qui existe — et celle qui ne marche pas

**`assets/.env` est le seul mécanisme réellement en place**, et il pointe dans la bonne direction. Il est lu à l'exécution via `flutter_dotenv` (`main.dart:34`) et porte 10 clés :

```
APP_NAME, WEB_URL, WEB_CONTACT_URL, WEB_TERMS_URL, WEB_PRIVACY_URL,
WEB_AGENCY_REGISTER_URL, SUPPORT_EMAIL,
FEATURE_STRIPE, FEATURE_ADDRESS, FEATURE_PHONENUMBER, FEATURE_NAME, FEATURE_CREDIT_CARD
+ 3 clés reCAPTCHA (clés *site*, publiques)
```

Utilisation réelle : `APP_NAME` lu 14 fois, les 6 autres clés de marque 1 fois chacune. C'est **la bonne idée, à la mauvaise échelle** : un seul fichier versionné, pas une variante par client, et **empaqueté comme asset Flutter** (`pubspec.yaml:105`) — donc tout ce qu'on y met est trivialement extractible d'un `.apk`.

#### 🔴 Les deux crochets de configuration au build sont inertes

C'est le §7.7 du brief — « rien n'échoue, le résultat est simplement faux » — et il est présent, en CI, aujourd'hui :

| Ce que fait la CI | Ce que fait l'application |
|---|---|
| Écrit `.env` **à la racine du dépôt** avec `STRIPE_PUBLISHABLE_KEY` et `API_BASE_URL` (`android-playstore.yml:77-82`, `ios-testflight.yml:76-81`, `web-firebase.yml:68-73`) | Lit **`assets/.env`** (`main.dart:34`) |
| Passe `--dart-define=STRIPE_PUBLISHABLE_KEY=… --dart-define=API_BASE_URL=…` au build web (`web-firebase.yml:83-84`) | **`String.fromEnvironment` n'apparaît nulle part dans `lib/`** (0 occurrence) |

**Conséquence : les deux secrets de build injectés par la CI n'atteignent jamais le binaire.** Les valeurs qui partent en production sont la `const` de `lib/common/config.dart:3` et la `const` de `lib/services/stripe_ui_service_mobile.dart:9`. Aucun build n'échoue, aucun avertissement n'est émis. Quelqu'un a mis en place une configuration par environnement ; elle ne fait rien depuis.

### 4.10 Les drapeaux qui mentent

C'est le §2.5 / §7.6 du brief, présent à l'identique.

| Drapeau | Déclaré dans `.env` | Lu par le code | Ce qu'il coupe réellement |
|---|---|---|---|
| `FEATURE_NAME` | ✅ | 6 sites | Champs nom/prénom du formulaire d'inscription — **honnête** |
| `FEATURE_ADDRESS` | ✅ | 6 sites | Champs d'adresse — **honnête** |
| `FEATURE_PHONENUMBER` | ✅ | 3 sites | Champ téléphone — **honnête** |
| `FEATURE_CREDIT_CARD` | ✅ | **1 site** | 🔴 **Ment** — voir ci-dessous |
| `FEATURE_STRIPE` | ✅ | 2 sites | 🔴 **Ne coupe rien sur mobile** — un site est dans un écran mort (`SubscriptionScreenWithBloc.dart:358`), l'autre dans le dialogue **web** (`stripe_payment_dialog.dart:117`), lui-même non fonctionnel (§7.6) |
| `STRIPE_ENABLED` | ❌ absent | 3 sites, **tous commentés** | Rien |

**Le cas `FEATURE_CREDIT_CARD`, chiffré.** Passé à `false`, il masque **un bouton** (`destination_details_screen.dart:597`). Or il existe **quatre points d'entrée** vers le tunnel d'achat :

| Point d'entrée | Protégé par le drapeau ? |
|---|---|
| `destination_details_screen.dart:609` (push direct) | ✅ |
| `homescreensabily.dart:467` (route nommée) | ❌ |
| `all_packs_screen.dart:344` (route nommée) | ❌ |
| `region_details_screen.dart:477` (route nommée) | ❌ |
| **La route elle-même** — `app_router.dart:173` | ❌ **enregistrée sans condition** |

Le drapeau coupe donc **1 des 4 entrées, et 0 des 1 routes**. La navigation nommée, le lien profond et l'appel réseau restent intacts. C'est la définition exacte du « drapeau menteur » du §2.5 : *pire qu'une absence*.

### 4.11 Récapitulatif

| Couche | Occurrences | Fichiers |
|---|---|---|
| Imports `package:sabily_mobile/` | 527 | 115 |
| Marque dans le Dart (hors imports) | 163 | 27 |
| Marque dans les dictionnaires ARB | 88 | 8 |
| Clés ARB portant la marque dans leur nom | 3 clés × 8 fichiers = 24 | 8 |
| Marque dans le natif / web | 35 | 10 |
| Chemins d'assets en dur | 22 | 14 |
| URL / hôtes en dur | 12 (7 hôtes) | 8 |
| Adresses e-mail en dur | 2 | 2 |
| Assets nommés d'après la marque | 4 images + 1 dossier d'icône | — |
| Fichiers Dart nommés d'après la marque | 2 | — |
| **Surface couplée à la marque** | **≈ 830 occurrences** | **≈ 150 fichiers** |
| Décisions de couleur non configurables | 894 | 39 |
| Littéraux typographiques | 288 (14 valeurs) | — |
| **Divergence de code par client (mesurée)** | **+2 521 / −1 590 lignes** | **67 fichiers écrits à la main** |

---

## 5. Couverture fonctionnelle réelle, contre le tableau §3.4

*Grille §6.1 — ligne 5 : ce qui existe, ce qui manque, ce qui est mort.*

### 5.1 Ce que l'application fait aujourd'hui

Quatre onglets (`homescreensabily.dart:730-765`) : **Accueil** (catalogue, public), **Mes eSIM** (+ onglet « Mes forfaits »), **Profil**, **Réglages**. Plus : connexion/inscription avec OTP, mot de passe oublié, écran bon d'achat, tunnel d'achat, diagnostic eSIM de l'appareil. Sept langues actives.

### 5.2 Notation contre le tableau §3.4 du brief

| Domaine | Parcours attendu | Priorité brief | État réel |
|---|---|---|---|
| **Découverte** | Catalogue destinations, fiche destination, recherche, comparaison | Haute | 🟢 **Présent.** Catalogue public (sans jeton), destinations + forfaits joints côté client. ⚠️ **Aucune pagination** — toutes les listes sont chargées entières. Images de couverture construites depuis l'hôte WordPress de Sabily |
| **Achat** | Panier, paiement carte (Stripe), confirmation | Haute | 🟠 **Partiel et défaillant.** Pas de panier (achat unitaire direct). Stripe PaymentSheet correct. **Aucune commande serveur avant capture** (§7.1). Le backend expose pourtant `/api/v1/carts` — inutilisé |
| **eSIM** | Installation (QR/activation), compatibilité appareil, mes eSIM, suivi conso | Haute | 🟠 **QR et suivi présents et corrects. Installation en un geste = coquille** — 8 méthodes sur 12 sont des bouchons (§6) |
| **Compte** | Inscription, connexion, mot de passe oublié, profil, commandes, support | Haute | 🟠 **Présent, mais** : l'inscription exige 11 champs ; **la connexion Google et Apple appelle des endpoints qui n'existent pas** (§7.7) ; pas d'historique de commandes ; pas d'édition de profil |
| **Recharge** | Recharge d'une eSIM existante | Moyenne | 🔴 **Inexistant.** `topUp`, `recharge`, `renew` : zéro correspondance dans `lib/`. Aucun endpoint backend correspondant non plus |
| **Revendeur (BtoB)** | Candidature partenaire, espace agence, panier agence, bons, factures, solde | Optionnel — sous drapeau | 🔴 **Aucune fonctionnalité en application.** Un seul point de contact : `profilscreen.dart:457-459` ouvre `WEB_AGENCY_REGISTER_URL` dans le navigateur système. `lib/api/models/agency.dart` existe et n'est importé par rien. `Subscriber.agency` est typé `dynamic`, parsé, jamais affiché. **Voir §5.4 — question de périmètre non tranchée** |
| **Back-office** | Administration | Hors périmètre | 🟢 Conforme — absent du mobile |
| **TransaPay** | Portefeuille | À venir | ⚪ Aucun point d'extension. Il n'existe **aucun registre de modules** : les routes sont un `switch` monolithique de 151 lignes (`app_router.dart:61-212`) |

### 5.3 Fonctions présentes mais non listées au §3.4

| Fonction | État |
|---|---|
| **Bon d'achat / voucher** | Présent (`VoucherScreen`, 234 lignes), joignable par push direct depuis l'accueil, **non routé**. 🔴 Le client **jette la réponse serveur** et renvoie un `Voucher(status: 'valid')` en dur (`voucher_client.dart:12-19`) : tout 2xx est annoncé à l'utilisateur comme un bon valide |
| **Factures PDF** | Présent (1 060 lignes), 🔴 **fabriquées sur l'appareil**, `taxRate: 0.0` en dur, sans enregistrement serveur (§7.4) |
| **Sélecteur de devise** | Présent (EUR/USD/GBP), 🔴 **ne convertit pas le montant débité** (§7.3) |
| **Diagnostic eSIM appareil** | Écran de 674 lignes + bloc à 9 gestionnaires, 🔴 **structurellement incapable d'afficher une donnée réelle** (§6) |

### 5.4 ⚠️ Conflit de périmètre BtoB — à trancher en phase 2, pas ici

**Deux consignes actives se contredisent, et la phase 1 n'a pas à les départager.**

| Source | Position |
|---|---|
| `BRIEF-MOBILE-WHITE-LABEL.md` §3.3 critère 5, §3.4, §5.1, §5.6 | Le BtoB est un **module mobile réel, sous drapeau `features.b2b`**, et **Sabily doit précisément le livrer actif** (« Sabily (BtoC + BtoB, 6 langues dont l'arabe RTL) ») |
| Consigne antérieure du projet | Le mobile est **BtoC uniquement, sans aucune partie agence** |

**Ce que l'analyse peut affirmer, et qui est compatible avec les deux directions :** il n'existe **aucune fonctionnalité B2B en application aujourd'hui** — un lien sortant vers le web, et rien d'autre.

**Trois éléments que la phase 2 devra avoir sous les yeux pour trancher :**

1. **Le backend expose déjà une surface B2B complète.** `/api/v1/agencies` : `/register`, `/create`, `/validate`, `/suspend`, `/reject`, `/account/activate`, `/account/disable`, `/add-balance`, `/dashboard/stats`, `/current`, `/country/{code}`, `/currency/{code}`. Un formulaire de candidature en application **a un endpoint** (`POST /api/v1/agencies/register`).
2. **Les maquettes APRÈS, elles, tranchent — dans le sens du brief.** `Become a Partner - Sabily (Mobile).png` (Figma `52:639`) est un **formulaire de candidature complet en application** : Agency / Company Name, Primary Contact Name, Business Email, Phone Number, Agency Type (liste déroulante), texte libre, bouton « Submit Application ». Ce n'est pas un lien sortant.
3. **Le poids du module change selon la décision.** « Candidature seule » ≈ un écran et un appel. « Espace agence » (panier agence, bons, factures, solde) ≈ un module complet, et le §8.3 du brief le pose explicitement comme une décision client (« L'espace revendeur passe-t-il en mobile, ou reste-t-il web ? »).

> **Aucune recommandation n'est faite ici.** Le §13 traite les deux hypothèses.

### 5.5 Les maquettes APRÈS impliquent des fonctions qui n'existent nulle part

Croisement des 18 PNG et des 19 cadres Figma contre le code et l'API :

| Élément de maquette | Existe en application ? | Existe côté API ? |
|---|---|---|
| **« Top Up Data »** (`eSIM Tracking`) | ❌ | ❌ aucun endpoint de recharge |
| **Panier** (icône d'en-tête sur `Home` et `eSIM Catalog`) | ❌ | ✅ **`/api/v1/carts`** existe et n'est pas utilisé |
| **Code promo / remise** (`Checkout`) | ❌ | ❓ non identifié |
| **Moyens de paiement enregistrés** (`Profile Settings`) | ❌ | ❌ pas de Stripe Customer / SetupIntent |
| **Notifications** (`Profile Settings`) | ❌ aucune intégration push | ❌ |
| **Sécurité — mot de passe et authentification** (`Profile Settings`) | ❌ | ❌ (seul le reset par e-mail existe) |
| **Modifier le profil / informations personnelles** | ❌ | ✅ `PUT /api/subscribers/{id}` câblé côté client, **mort** |
| **Candidature partenaire en application** | ❌ (lien sortant) | ✅ `/api/v1/agencies/register` |
| **Connexion par téléphone** (gabarit white-label) | ❌ | ❌ |
| **Connexion Google** (gabarit white-label) | ✅ bouton présent | ❌ **endpoint inexistant** (§7.7) |
| **Onglet « Store » séparé de « Home »** | ❌ (3 onglets + Réglages aujourd'hui) | s.o. |
| **Onglet « Réglages »** | ✅ présent aujourd'hui | **absent des maquettes** — langue et devise migrent dans Profil |

### 5.6 Discordances entre le dossier de maquettes et le Figma

Les deux sources ne sont pas alignées. Rien ici ne doit être traité comme faisant autorité sans arbitrage.

**Dans Figma, absents du dossier `new/` :**

| Cadre Figma | Identifiant |
|---|---|
| `Pack Details - Sabily (Mobile)` | `63:53` |
| `Purchase Summary - Sabily (Mobile)` | `63:371` |
| `White-Label Store Template` | `66:28` |

**Dans le dossier `new/`, sans cadre mobile correspondant dans Figma :** `eSIM Catalog - Sabily (Mobile).png` et `eSIM Tracking - Sabily (Mobile).png`. Le Figma ne porte ces deux noms qu'en **largeur 1280 px** (cadres bureau `47:2` et `47:923`). Les PNG sont bien des mises en page téléphone : ils proviennent donc d'une version antérieure du fichier, ou d'un cadre depuis renommé.

**Deux générations de maquettes, de nature différente :**

| Lot | Cadres | Nature |
|---|---|---|
| **7 août** (`52:*`) | Home, My eSIMs, Sign Up, About Us, Log In, Checkout, Become a Partner, Profile Settings | **Conceptions neuves.** Contenu inventé, mise en page repensée |
| **10 septembre** (`63:*`) | Pack Details, Verification, Regional Packs, Purchase Summary, Forgot Password, Activate Voucher, My Invoices, Welcome | **Captures de l'application vivante, recolorées.** On y lit les vraies données du catalogue, la troncature des noms de forfaits, le bug de pluriel « 1 days », et le mélange français/anglais existant (« My Invoices » / « Rechercher une facture… » / « Aucune facture ») |

**Deux tunnels de paiement mutuellement incompatibles cohabitent dans le même fichier :**

| `Checkout` (7 août, `52:560`) | `Purchase Summary` (10 sept., `63:371`) |
|---|---|
| Récapitulatif de commande, **code promo**, sous-total/remise/total | Fiche forfait, prix |
| **Sélection du moyen de paiement** (Apple Pay coché par défaut / Carte) | **Sélecteur de devise** (EUR) |
| Pas de sélecteur de devise | Pas de code promo, pas de moyen de paiement |

À noter : Apple Pay est le moyen **coché par défaut** dans la maquette, alors que l'habilitation iOS correspondante est un tableau vide (§10.3) ; et le sélecteur de devise est précisément la fonctionnalité défaillante du §7.3.

### 5.7 Le système de design Figma n'est pas prêt à porter une `BrandConfig`

**Aucune variable Figma n'est définie dans le fichier** (`get_variable_defs` renvoie `{}` sur les cadres testés, marque et gabarit white-label). Toutes les couleurs sont des littéraux. Conséquence : **trois palettes et trois piles typographiques pour un seul client.**

| Lot | Primaire | Fond | Typographie |
|---|---|---|---|
| 7 août (`52:*`) | `#004d40` | `#f9f2d3` | Be Vietnam Pro + Noto Sans + IBM Plex Sans |
| 10 sept. (`63:*`) | `#003c3a` | `#fff9e8` | **Liberation Sans** — c'est-à-dire *police non définie*, substitut métrique d'Arial |
| Gabarits white-label (`66:*`) | **`#114c49`** | `#f9fbf9` / `#fcf9f8` | Plus Jakarta Sans + Inter |

**Le gabarit white-label n'est pas neutre :** `White-Label Welcome Template` (`66:148`) affiche encore **le logo de Sabily** dans l'emplacement « Brand Logo » (l'asset est pourtant nommé `stitch-placeholder-300x300.svg`).

**Le gabarit white-label et la déclinaison Sabily n'ont pas la même barre d'onglets :** le gabarit en compte **3** (Store / My eSIMs / Profile), Sabily en compte **4** (Home / Store / My eSIMs / Profile). C'est en soi une bonne nouvelle — le design a déjà anticipé qu'un jeu d'onglets varie par client, ce qui correspond exactement au contrat `AppModule.navEntries(config)` du §5.6 du brief. Mais cela doit être décidé, pas subi.

**Enfin, les maquettes reconduisent la dette du §4.3 :** `Activate Voucher` affiche « **Sabily** vouchers are valid for 30 days from the activation date. » — la clé `voucherValidity` telle quelle, nom du client compris.

---

## 6. Comment l'installation d'eSIM est implémentée

*Grille §6.1 — ligne 6 : point le plus spécifique et le plus risqué du produit.*

### 6.1 Ce qui est correct et portable

Le QR est **construit sur l'appareil** à partir de deux champs de l'API, au format GSMA SGP.22 standard (`EsimConsommationScreen.dart:569-570`) :

```dart
final qrData = 'LPA:1\$${esimProfile.smdpAddress}\$${esimProfile.matchingId}';
```

Rendu avec `qr_flutter`. **Aucun verrouillage technologique** : ce contrat se reconstruit dans n'importe quel cadre. C'est, avec les contrats d'API, le second actif du dépôt.

La triade **scanner / copier le texte / installer en un geste** est la bonne forme d'expérience. À conserver.

⚠️ **Aucune garde de nullité sur la construction du QR.** Si `smdpAddress` ou `matchingId` est nul, la chaîne interpole le littéral `"null"` et l'application affiche un QR **valide en apparence et inutilisable**.

### 6.2 Ce qui est une coquille

`flutter_esim ^0.0.4`. Sur les 12 méthodes exposées par `EsimService`, **8 sont des bouchons codés en dur** (`lib/services/esim_service.dart:143-256`) :

| Méthode | Retour | Ligne |
|---|---|---|
| `getInstalledProfiles()` | `[]` toujours | `:143-158` |
| `activateProfile(iccid)` | `false` | `:162-171` |
| `deactivateProfile(iccid)` | `false` | `:175-184` |
| `deleteProfile(iccid)` | `false` | `:188-197` |
| `getCarrierInfo()` | `null` | `:201-209` |
| `isNetworkConnected()` | `true` sans condition | `:212-226` |
| `openCellularSettings()` | `false` | `:229-245` |
| `isProfileActive(iccid)` | `false` | `:248-256` |

L'écran « Gestion eSIM de l'appareil » (674 lignes) et son bloc (9 gestionnaires) sont câblés sur ces méthodes. **L'écran est atteignable** (icône réglages de « Mes eSIM » → `/device-esim`) et **ne peut structurellement afficher aucune donnée réelle**.

Deux fragilités supplémentaires :

- **La détection de succès est du reniflage de chaîne** : `result.toLowerCase().contains('success' | 'installed' | 'ok')` (`:87-89`). Cassant d'une version de greffon à l'autre, et d'une langue à l'autre.
- **`_manualEsimCheck()` (`:36-49`) renvoie `true` sur toute plateforme mobile** quand le greffon lève une exception — un appareil non compatible peut donc s'entendre dire qu'il l'est.

### 6.3 Le champ `activationCode` que le backend envoie et que le client ignore

`EsimConsommationScreen.dart:683` :

```dart
String? activationCode; //esimProfile.activationCode;
```

Déclaré nul, la vraie source commentée. Le code retombe systématiquement sur la reconstruction `LPA:` depuis `smdpAddress` + `matchingId`.

**Vérifié dans le JAR :** `activationCode` existe bien dans `EsimProfile`, `EsimProfileDTO`, `EsimProfileModel` et dans les modèles du client eSIM amont (`ESimProfileResponse`, `ESimDetails`) — le champ est donc alimenté par le fournisseur. Quelqu'un l'a désactivé délibérément côté mobile ; savoir pourquoi est une question à poser avant de le réactiver.

**À l'inverse, `esimProfileCodeQR` — parsé par le client (`esim_profile.dart:16, 58`) et jamais affiché — n'existe pas du tout côté backend** (0 occurrence dans le JAR). Le client analyse un champ que le serveur n'envoie pas.

---

## 7. Le paiement, et la réconciliation backend

*Grille §6.1 — ligne 7 : SDK, flux, conformité aux règles des stores.*

### 7.0 Ce qui est bon

- **Stripe PaymentSheet est la seule surface de collecte.** Aucun `CardField`, aucun formulaire de carte, nulle part. **L'application est hors périmètre PCI.** À conserver tel quel — ne pas construire de formulaire de carte.
- **La forme en deux temps est juste** : créer l'intention côté serveur → présenter la feuille → finaliser côté serveur.

### 7.1 🔴 Aucune commande serveur avant la capture

L'étape qui devrait créer la commande **n'appelle aucune API**. `pack_purchase_client.dart:12-41` dort 500 ms et fabrique un identifiant de commande, un statut et un identifiant d'intention côté client. L'appel réel est commenté (`:31-37`), avec le commentaire *« API non implémentée côté backend »*.

La commande ne devient réelle qu'**après** la capture Stripe, via `POST /v1/subscriptions/card`. **Si cet appel échoue ou expire, le client a payé, rien n'est provisionné, et il n'existe aucune reprise** : ni clé d'idempotence (0 occurrence côté mobile **et** 0 côté backend, vérifié), ni nouvelle tentative, ni « restaurer mon achat », ni notification push, ni scrutation.

### 7.2 🔴 Les centimes sont perdus — et cela fait échouer le provisionnement

C'est la question n°1 du §8 de `rebuild-brief.md`. **Elle est tranchée.**

**Côté mobile** (`stripe_client.dart:56-70`) — le montant est envoyé **deux fois, dans deux formats** :

```dart
POST /v1/payments/init?amount=9&currency=eur     ← calculateAmount() fait .toInt()  → 9,99 devient 9
Body: { "amount": "9.99", "currency": "EUR" }    ← la valeur exacte
```

**Côté backend** — bytecode de `PaymentResourceExt.createPaymentIntent` :

```java
@PostMapping("init")
@PreAuthorize("hasAuthority(\"ROLE_SUBSCRIBER\")")
ResponseEntity<?> createPaymentIntent(@RequestParam BigDecimal amount,
                                      @RequestParam String currency)
```

> **Les deux paramètres sont des `@RequestParam`. Il n'y a aucun `@RequestBody` sur cet endpoint.**
> **⇒ Le serveur lit la chaîne de requête, tronquée. Le corps JSON, correct, est intégralement ignoré.**

Puis, dans `StripePaymentValidationService.createPaymentIntent` (une seule constante numérique dans toute la classe : `LONG 100`) :

```java
long minor = BigDecimal.valueOf(100).multiply(amount).longValue();   // 9 × 100 = 900
PaymentIntentCreateParams.builder().setAmount(minor).setCurrency(currency)…
```

**Un forfait à 9,99 € produit une intention Stripe de 9,00 €.**

**Et ce n'est pas seulement un manque à gagner — cela casse la livraison.** À la finalisation, `SubscriberServiceImplExt.subscribeByCard` :

```java
result = checkpayment(paymentIntentId, …);          // PaymentIntent.retrieve → status.equals("succeeded")
                                                    // amount = BigDecimal(900).divide(100) = 9.00
if (!result.isSuccess())                    throw new PaimentException(…);
price = packService.getPriceByCurrencyCode(pack, result.getCurrency());
if (price == null)                          throw new PaimentException(…);
if (result.getAmount().compareTo(price.getSabilyAmount()) != 0)
                                            throw new PaimentException(…);   // 9.00 ≠ 9.99
```

> 🔴 **Pour tout forfait dont le prix n'est pas un nombre entier d'unités, la séquence est : le client paie, Stripe capture, et le provisionnement est refusé par le contrôle de montant côté serveur.** L'application, elle, affiche « achat réussi » (§7.5).
>
> **Élément de corroboration :** les captures du catalogue réel présentes dans les maquettes du 10 septembre (`Regional Packs`) affichent **12,00 / 9,00 / 4,00 / 5,00 / 5,00 / 10,00 EUR** — que des unités entières. C'est précisément la condition dans laquelle le bug est invisible. À confirmer sur la base de production : **combien de forfaits ont un prix à centimes non nuls, et combien de `PaimentException` figurent dans les journaux.**

**Action minimale, sans attendre la refonte :** supprimer `.toInt()`. Une ligne. Le corps JSON n'a jamais été lu de toute façon.

### 7.3 🔴 Le sélecteur de devise ne convertit pas le montant débité

L'écran laisse choisir EUR/USD/GBP et **affiche** un prix converti, mais le montant envoyé est toujours `pack.mainPrice` — la valeur brute de `prices.first`, dans la devise propre au forfait — pendant que `currency` porte le choix de l'utilisateur (`pack_purchase_screen.dart:91-92`). **Choisir USD envoie le nombre EUR étiqueté USD.**

Aggravants : Google Pay code en dur `currencyCode: 'EUR'` (`stripe_ui_service_mobile.dart:52`), et `/v1/subscriptions/card` code en dur `"currency": "EUR"` (`payment_terminate.dart:38`).

**Et côté serveur, le contrôle de montant se fait dans la devise Stripe :** `getPriceByCurrencyCode(pack, result.getCurrency())` — si le forfait n'a pas de prix dans la devise réellement débitée, c'est encore un `PaimentException`.

**Aggravant supplémentaire (🔴 R4 de l'audit) :** les prix affichés viennent de `api.exchangerate-api.com`, appelé **directement depuis le téléphone**, mis en cache 6 h. Aucun contrat, aucune garantie de service. Le change appartient au backend.

### 7.4 🔴 Les champs `id` / `clientSecret` sont bien inversés — et le résultat n'est pas ce que l'audit supposait

C'est la question n°2 du §8 de `rebuild-brief.md`. **Tranchée sur le bytecode.**

`StripePaymentValidationService.createPaymentIntent`, instructions 153-172 :

```java
new PaymentIntentModel(
    paymentIntent.getId(),           // → champ `clientSecret`      ← l'identifiant pi_…
    paymentIntent.getClientSecret(), // → champ `paymentIntentId`   ← le vrai secret client
    paymentDTO.getId()               // → champ `paymentId`
);
```

(Noms des paramètres du constructeur, lus dans `MethodParameters` : `clientSecret, paymentIntentId, paymentId`.)

**Les champs sont donc réellement inversés côté serveur.** Le JSON produit est :

```json
{ "clientSecret": "pi_3ABC…",              ← identifiant de l'intention
  "paymentIntentId": "pi_3ABC…_secret_…",  ← le secret client
  "id": null,                              ← champ jamais affecté (setId n'est appelé nulle part)
  "paymentId": 12345 }
```

Le client, lui, fait (`stripe_payment_response.dart:92-93`) :

```dart
paymentIntentId: json['clientSecret'] as String,  // ✅ reçoit bien pi_…
clientSecret:    json['id'] as String,            // ⚠️ reçoit null
```

⚠️ **`json['id'] as String` sur une valeur nulle lève en Dart.** Sur la foi du seul JAR analysé, l'appel `/v1/payments/init` **échouerait à l'analyse de la réponse**, et le tunnel s'arrêterait à l'étape 4.

**Ce point demande une vérification en direct avant toute conclusion**, pour deux raisons : le JAR date du 4 juillet 2026 alors que `master` mobile date du 10 août ; et l'audit antérieur partait de l'hypothèse que les paiements fonctionnent en production. **Une seule requête authentifiée `POST /v1/payments/init` sur un backend de développement tranche définitivement** — c'est le premier test à faire en phase 2.

Quelle que soit l'issue : **les deux côtés doivent être corrigés ensemble ou pas du tout.** Renommer côté serveur sans livraison mobile coordonnée casse le paiement pour toutes les applications installées.

### 7.5 🔴 `/v1/subscriptions/card` ignore presque tout ce que le mobile lui envoie

Le mobile poste 11 champs (`payment_terminate.dart:28-55`) : `success`, `message`, `currency`, `id`, `paymentId`, `paymentIntentId`, `status`, `transactionId`, `packId`, `description`, `metadata`.

Le modèle serveur `SubscriptionModel` n'en a **que cinq** : `voucherToken`, `packId`, `paymentIntentId`, `description`, `sessionId`.

> **`success`, `status`, `currency`, `id`, `paymentId`, `transactionId` et `metadata` sont silencieusement écartés.**

C'est la réponse à la question n°3 du §9 de `api-contract.md` (« que fait le backend d'un `success: false` / `status: "CANCELLED"` ? ») : **il ne les lit pas.** Ce qui protège réellement, c'est le contrôle Stripe de `subscribeByCard` (§7.2), pas le statut annoncé par le client.

Deux conséquences pratiques :
- **L'annulation utilisateur déclenche quand même un appel de création d'abonnement** (`pack_purchase_screen.dart:405-426`). Il sera rejeté par le contrôle Stripe — mais il ne devrait pas partir.
- **Le champ `currency` du mobile ne sert à rien**, ce qui rend le §7.3 encore plus trompeur qu'il n'y paraît.

**Et le client ignore la réponse en retour :** `pack_purchase_client.dart:118-122` code en dur `status: 'success'` (`subscriptionResponse` est commenté à `:104`). **Quoi que réponde le serveur, l'application annonce la réussite à l'utilisateur.** Les erreurs de `/v1/payments/finish` sont, elles, avalées par un `catch (e) {}` vide (`:110-116`).

### 7.6 🔴 Le tunnel web ne fonctionne pas

`stripe_payment_element_widget.dart:43-49` crée le `<div id="payment-element">`, mais **rien n'y monte jamais l'élément Stripe**. Le code le dit : *« Pour l'instant, on simule l'initialisation »* (`stripe_payment_dialog.dart:47-51`) — il attend 500 ms puis se déclare prêt, et appelle `confirmPaymentElement` sur un élément inexistant.

### 7.7 🔴 La connexion Google et Apple appelle des endpoints qui n'existent pas

Le §8.4 du brief l'annonce (« aucun endpoint d'authentification tierce n'existe aujourd'hui »). **Le JAR le confirme sans ambiguïté** : `google-auth`, `apple-auth`, `google-register`, `apple-register` — **zéro occurrence dans les 891 classes applicatives**. `AuthenticateController` n'expose que `POST /api/authenticate`.

Or l'application **affiche et câble** ces quatre chemins (`auth_client.dart:164-173, 204-213, 252-262, 291-301`), appelés depuis `login.dart:29, 61` et `signup.dart:24, 66`.

> **Les boutons « Se connecter avec Google » et « Se connecter avec Apple » sont présents dans l'interface de production et appellent des routes inexistantes.**

Point store associé : dès qu'iOS propose un fournisseur tiers, Apple exige « Sign in with Apple ». L'habilitation `com.apple.developer.applesignin` est bien présente — le backend, lui, ne l'est pas. **C'est une demande backend à formuler tôt**, comme le prévoit le §8.4.

### 7.8 Autres défauts du chemin de l'argent

| # | Défaut | Emplacement |
|---|---|---|
| D3 | `googlePay.testEnv: true` **avec une clé publiable `pk_live_`** | `stripe_ui_service_mobile.dart:51` |
| D4 | Apple Pay : `merchantIdentifier` posé dans le code, mais l'habilitation `com.apple.developer.in-app-payments` est un **tableau vide** → le bouton ne peut pas apparaître | `Runner.entitlements` |
| D9 | Détails de facturation en dur : `name: 'Invité'`, `email: 'invite@sabily.fr'` envoyés à Stripe **pour chaque paiement** — reçus, règles Radar et preuves de litige reçoivent le substitut | `stripe_ui_service_mobile.dart:35-38` |
| D10 | `http_client.dart:107` imprime **chaque corps de réponse** ; `stripe_client.dart:54,60` impriment la charge de l'intention ; `stripe_ui_service_mobile.dart:27` imprime les 20 premiers caractères du secret client. **En release** | — |
| D11 | `clientSecret.substring(0, 20)` non gardé → `RangeError` si la réponse est malformée, **avant** `initPaymentSheet` | `stripe_ui_service_mobile.dart:27` |
| — | Annulation détectée par comparaison de chaîne : `e.toString().contains('cancelled')` contre un message produit en anglais | `pack_purchase_screen.dart:427` |

### 7.9 Conformité aux règles des stores

Un forfait data consommé **hors de l'application** relève normalement du paiement externe, pas de l'achat in-app. Le modèle actuel (Stripe uniquement, aucune intégration StoreKit / Play Billing) est donc **a priori défendable** — mais c'est un arbitrage à faire confirmer, règles Apple et Google en main, avant toute nouvelle soumission (§8.3 du brief). Aucun élément du dépôt n'indique que la question ait été instruite.

### 7.10 Récapitulatif de la réconciliation backend

| Question ouverte | Verdict | Source |
|---|---|---|
| `/v1/payments/init` lit-il la requête tronquée ou le corps ? | 🔴 **La requête.** Les deux paramètres sont `@RequestParam`, il n'y a pas de `@RequestBody`. Le corps n'est jamais lu | Bytecode `PaymentResourceExt` |
| Unités majeures ou mineures ? | **Majeures en entrée**, multipliées par 100 côté serveur | `LONG 100` + `multiply`, `StripePaymentValidationService` |
| Y a-t-il eu sous-facturation ? | 🔴 **Pire : le provisionnement échoue.** Le contrôle `amount == price.sabilyAmount` rejette tout forfait à centimes non nuls | `SubscriberServiceImplExt.subscribeByCard` |
| `id` / `clientSecret` réellement inversés ? | 🔴 **Oui**, et `id` n'est **jamais affecté** → `null`. À confirmer en direct (§7.4) | Bytecode `createPaymentIntent` + `PaymentIntentModel` |
| `/v1/sub-plans/subscriber/details` existe-t-il ? | 🔴 **Non.** `SubPlanResourceExt` expose `/all`, `/esim-profile/{idEP}`, `/pack/{idPack}`, `/subscriber`, `/subscriber/{idSub}`. `/details` : **0 occurrence dans tout le JAR**. Un appel lierait `"details"` à un `Long` → **400**, pas 404 | Constantes `SubPlanResourceExt` + balayage du JAR |
| Que fait le backend d'un `success: false` ? | Il ne le lit pas — `SubscriptionModel` n'a pas ce champ. La protection réelle vient du contrôle Stripe | `SubscriptionModel` + `subscribeViaCard` |
| Endpoints Google/Apple ? | 🔴 **Inexistants** (0 occurrence) — confirme le §8.4 du brief | Balayage du JAR |
| `/api/transactions` (factures) actif ? | 🔴 **Le chemin n'existe pas.** Le vrai est `/api/v1/transactions`, et ses quatre routes sont **`ROLE_ADMIN` / `ROLE_AGENCY` uniquement**. **Il n'existe aucun endpoint de facture côté abonné** | `TransactionResourceExt` |
| La faute de frappe `rmainingData` ? | Confirmée : c'est le nom sur le fil (`ConsumptionsModel.rmainingData`, de type **`BigDecimal`**). `remainingData` : 0 occurrence → **pas de double émission aujourd'hui** | `ConsumptionsModel` |
| Idempotence côté backend ? | 🔴 **Aucune.** `idempot` : 0 occurrence dans le JAR | Balayage du JAR |
| `GET /api/account` renvoie-t-il un objet `user` ? | 🔴 **Non.** `AuthenticateController$JWTToken` ne porte que `idToken` → `id_token`. Le `AuthResponse.userData = json['user'] ?? {}` du mobile est **toujours vide** | `AuthenticateController$JWTToken` |
| « API WordPress » ? | Rien ne l'étaye. La pile est JHipster / Spring Boot 3.4.1, paquet `com.tamarisoft.sabily`. Les commentaires du client Dart sont probablement un vestige | Manifeste + classes |
| Panier | ✅ **`/api/v1/carts` existe** (`/cart`, `/add_items`, `/delete_items`, `/purchase_cart`) et n'est **pas utilisé** par le mobile | `CartResourceExt` |

**Défaut de type latent, découvert au passage :** `ConsumptionsModel.rmainingData` est un `BigDecimal` côté serveur ; côté mobile, `esim_profile.dart:19` le déclare `final int?` et `:61` l'affecte sans conversion. **Une valeur décimale non entière ferait échouer l'analyse de tout le profil eSIM.**

⚠️ **Réserve de méthode.** Le JAR analysé est daté du 4 juillet 2026, branche `sprint_0`, commit `1285990`. Il peut différer de la production. Chaque verdict ci-dessus est **certain quant à ce binaire** ; les trois marqués 🔴 sur le chemin de l'argent doivent être reconfirmés contre l'instance réellement déployée avant toute correction.

---

## 8. Internationalisation, langues et RTL

*Grille §6.1 — ligne 8.*

| | |
|---|---|
| Mécanisme | `flutter_localizations` + ARB généré (`l10n.yaml`, `lib/l10n/` → `lib/generated/gen_l10n/`) |
| Langues actives | **7** : en, fr, ar, es, sl, de, sq (`language_service.dart:7-16`) |
| Langue désactivée | Urdu — les ARB existent, la locale est commentée hors de `supportedLocales` |
| Persistance | `SharedPreferences` (`selected_language`), pilotée par `LanguageBloc` |

### 8.1 🔴 RTL : la langue est là, la conception ne l'est pas

L'arabe est dans la liste des langues supportées. **Aucun traitement RTL spécifique n'existe** :

- `EdgeInsetsDirectional` : **0 occurrence**
- Aucun `Directionality`, aucun visuel composé distinct LTR/RTL
- **Aucune police compatible arabe déclarée** — l'application s'en remet au repli système

Point rassurant : `EdgeInsets.only(left:/right:)` n'apparaît que **4 fois**. Le miroir automatique de Flutter couvre donc presque tout. Ce qui manque, c'est une **passe de recette en arabe**, et les **visuels recomposés** que le §4.4 du brief exige (le bloc « comment ça marche » est justement présent dans les maquettes APRÈS, avec trois pictogrammes et du texte — il faudra deux jeux).

### 8.2 Chaînes échappant au circuit de traduction

Des textes visibles par l'utilisateur sont écrits en dur, en français et en anglais mélangés :

| Emplacement | Nature |
|---|---|
| `app_router.dart:89, 146, 169, 194, 207` | Écrans de repli « argument manquant », **en français en dur** |
| `stripe_payment_dialog.dart:143, 263, 293, 311` | Dialogue de paiement web |
| `regions_screen.dart:150, 220` ; `region_details_screen.dart:87, 287, 310, 452` | **6 marqueurs `// TODO: Add translation`** |

⚠️ **Aucun en-tête `Accept-Language` n'est envoyé** (vérifié dans `http_client.dart:20-31`), alors que l'application sert 7 langues. Tous les messages d'erreur serveur reviennent dans la langue par défaut du backend. Le JAR embarque pourtant `messages.properties`, `messages_fr.properties`, `messages_en.properties`, `messages_ar_LY.properties` — la localisation serveur existe et n'est pas sollicitée.

### 8.3 Pour le socle

Le §7.3 du brief (« deux autorités concurrentes pour les langues ») **ne s'est pas encore produit ici** : il n'y a qu'une seule autorité, la constante globale de `language_service.dart`. C'est un point de départ propre — à condition que `locales` et `defaultLocale` deviennent des champs de la marque, et non une constante partagée, **avant** le deuxième client. eSimple sert l'allemand par défaut ; l'application actuelle n'a aucun moyen de l'exprimer.

---

## 9. Tests et CI

*Grille §6.1 — ligne 9 : base de la non-régression pendant la refonte.*

### 9.1 Tests

**24 fichiers** dans `test/`, couvrant l'authentification, les forfaits, la devise, les factures, la localisation et quelques écrans. `mocktail` et `bloc_test` sont présents. **C'est une base réelle**, et c'est le filet de sécurité de toute refonte progressive.

Deux réserves :

- **`test/live_api_test.dart` frappe l'API de production.**
- Aucune mesure de couverture n'est disponible dans le dépôt ; `code-quality.yml` lance `flutter test --coverage` et pousse vers Codecov, mais aucun seuil n'est imposé.

### 9.2 CI — six workflows

| Workflow | Rôle |
|---|---|
| `ios-testflight.yml` | Build + TestFlight, runner macOS |
| `android-playstore.yml` | Build + Play Store, canal sélectionnable |
| `android-release.yml` | Build release Android |
| `web-deploy.yml` / `web-firebase.yml` | Flutter Web → Firebase Hosting |
| `code-quality.yml` | `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test --coverage`, Codecov |

Tous se déclenchent sur `master`/`main`/`release/*` et sur les PR. **Aucun ne construit les branches `spc/*`** — les trois déclinaisons clientes ne sont donc jamais compilées par la CI. C'est exactement ce que le §5.4 du brief cherche à éviter (« La CI construit TOUS les flavors à chaque intégration »).

### 9.3 🔴 Aucune séparation d'environnement

| Sujet | Réalité |
|---|---|
| Dév / recette / production | **Aucune.** `ApiConfig.baseUrl` est une `const` pointant sur la production, avec le commentaire *« À modifier selon l'environnement »* |
| Flavors de build | **Aucun.** `grep productFlavors android/` : 0 résultat. Un seul schéma Xcode, `Runner` |
| `--dart-define` | Passé par la CI, **jamais lu** (§4.9) |
| Projets Firebase | `.firebaserc` fait pointer `default`, `production`, `staging` **et `dev`** sur le **même** projet `sabily` |
| Backend par client | **Impossible sans changement de code** |

**Chaque développeur, chaque exécution de CI et chaque test frappe la production.**

---

## 10. Comptes stores, certificats et profils de signature

*Grille §6.1 — ligne 10 : bloquant pour toute publication (§8.3 du brief). Cette section n'était couverte par aucun des cinq documents antérieurs.*

### 10.1 Android

| Élément | État |
|---|---|
| `applicationId` / `namespace` | `com.sabily.esim` (`build.gradle:18, 32`) |
| Nom d'affichage | `Sabily eSim`, **en dur dans le manifeste** (`AndroidManifest.xml:13`) — pas de `resValue` par flavor |
| `productFlavors` | **Aucun** |
| Ressources par flavor | **Aucune** — `android/app/src/` ne contient que `main`, `debug`, `profile` |
| Signature release | Lit `android/key.properties`, **absent du dépôt** et correctement ignoré par Git (`*.jks`, `*.keystore`, `key.properties`) ✅ |
| Build release | `minifyEnabled` + `shrinkResources` actifs ✅ |
| `google-services.json` | **Versionné** (`android/app/google-services.json`), projet `sabily`, 6 références à la marque |
| Publication | Fastlane `upload_to_play_store`, `package_name(ENV["ANDROID_PACKAGE_NAME"] \|\| "com.sabily.esim")` — **paramétrable, avec un défaut Sabily** |

### 10.2 iOS

| Élément | État |
|---|---|
| Schémas Xcode | **Un seul** : `Runner` |
| Configurations | `Debug` / `Release` / `Profile` — standard, **pas de configuration par client** |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.sabily.esim` (+ `com.sabily.esim.RunnerTests`) |
| **`DEVELOPMENT_TEAM`** | **`DP7F8WQCJD`**, en dur dans `project.pbxproj`, sur les **3 cibles** |
| `CODE_SIGN_STYLE` | **`Automatic`** sur les 3 cibles |
| `CFBundleDisplayName` / `CFBundleName` | `Sabily Mobile` / `sabily_mobile` |
| Schéma d'URL | `sabily-mobile` (consommé uniquement par le SDK Stripe) |

### 10.3 Habilitations iOS — deux anomalies

`ios/Runner/Runner.entitlements` :

```xml
<key>aps-environment</key>            <string>development</string>   ← ⚠️
<key>com.apple.developer.applesignin</key>  <array><string>Default</string></array>
<key>com.apple.developer.authentication-services.autofill-credential-provider</key> <true/>
<key>com.apple.developer.in-app-payments</key>  <array/>              ← 🔴 vide
```

- 🔴 **`in-app-payments` est un tableau vide** alors que le code pose `Stripe.merchantIdentifier = 'merchant.com.sabily.esim'`. **Apple Pay ne peut pas apparaître dans la feuille de paiement.** Il faut demander à l'exploitation si une transaction Apple Pay a **jamais** abouti en production.
- ⚠️ **`aps-environment` est en `development`.** Aucune intégration push n'existe par ailleurs (`firebase_messaging` absent, `Firebase.initializeApp()` jamais appelé). Si des notifications sont ajoutées — et les maquettes en prévoient (§5.5) — elles ne fonctionneront pas en production avec cette habilitation.

### 10.4 🔴 Deux mécanismes de signature iOS concurrents, dont un non opérationnel

| Mécanisme | Où | État |
|---|---|---|
| **Manuel** | `.github/workflows/ios-testflight.yml:66-73, 104-105` — installe `IOS_P12_BASE64` + `IOS_PROVISIONING_PROFILE_BASE64`, puis `xcodebuild` avec `PROVISIONING_PROFILE_SPECIFIER` et `DEVELOPMENT_TEAM` | C'est **ce qui tourne réellement** |
| **Fastlane `match`** | `ios/fastlane/Fastfile:24, 72, 86, 111, 117` — `match(type: "appstore", readonly: true)` | 🔴 **Non opérationnel.** Il n'existe **aucun `Matchfile`**, et `MATCH_GIT_URL` / `MATCH_PASSWORD` sont documentés dans `SETUP_SECRETS.md` mais **référencés par aucun workflow**. Toute exécution de `fastlane beta` échouera |

`ios/fastlane/Appfile` porte des valeurs de remplacement non renseignées : `apple_id(ENV["FASTLANE_USER"] || "your-apple-id@example.com")`, `team_id(ENV["IOS_TEAM_ID"] || "YOUR_TEAM_ID")`.

### 10.5 🔴 Les secrets de CI ne sont pas cloisonnés par client

31 secrets distincts sont référencés par les workflows. **Aucun n'est préfixé ou suffixé par un client.**

| Secret | Cardinalité |
|---|---|
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | **Un jeu** |
| `IOS_P12_BASE64`, `IOS_P12_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_PROVISIONING_PROFILE_SPECIFIER`, `IOS_TEAM_ID`, `IOS_CODE_SIGN_IDENTITY` | **Un jeu** |
| `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_KEY_CONTENT`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APPLE_ID_EMAIL`, `APPLE_APP_SPECIFIC_PASSWORD` | **Un jeu** |
| `PLAY_STORE_SERVICE_ACCOUNT_JSON`, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | **Deux noms pour la même chose** |
| `STRIPE_PUBLISHABLE_KEY`, `API_BASE_URL` | **Un jeu — et inerte (§4.9)** |
| `FIREBASE_TOKEN`, `FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID` | **Un jeu** |

C'est le contre-modèle exact du `BACKEND_URL_<SLUG>` / `STRIPE_PK_<SLUG>` du §2.4 du brief. **En l'état, publier un deuxième client depuis cette CI exige d'écraser les secrets du premier.**

### 10.6 Propriété des comptes — élément factuel, pas conclusion

Le fichier `note`, à la racine du dépôt (versionné), contient une URL d'équipe App Store Connect et une URL d'autorisation OAuth GitHub. L'URL ASC est liée au dépôt `github.com/abdoutech93/Sabily-mobile` — le compte du prestataire précédent (cf. le commit de fusion `Merge pull request #32 from abdoutech93/spc/sabily`).

**Cela suggère, sans le prouver, que l'équipe Apple Developer utilisée n'est pas celle du client final.** C'est la question la plus bloquante du §8.3 du brief (« Comptes stores : les vôtres ou ceux du client ? »), et elle ne peut être tranchée que par TRANSASIM. Aucun élément du dépôt n'indique le propriétaire du compte Google Play.

**Recommandation de forme, indépendante de la réponse :** le fichier `note` n'a rien à faire dans le dépôt.

### 10.7 Récapitulatif — état de préparation à la publication multi-client

| Prérequis §4.2 / §8.3 du brief | État |
|---|---|
| Table de flavors comme artefact contractuel | ❌ N'existe pas. 4 `applicationId` existent, **répartis sur 4 branches** |
| `applicationId` / `bundleIdentifier` par client, figés | ⚠️ Existent de fait, jamais validés formellement, **déjà publiés** pour au moins Sabily |
| Icônes et écrans de lancement générés par flavor | ❌ `flutter_launcher_icons` est en dev-dependency, **sans configuration par flavor** |
| Un script unique produit un client | ❌ Aucun script. La procédure est « changer de branche » |
| CI construisant tous les flavors | ❌ Les branches `spc/*` ne sont jamais construites |
| Secrets cloisonnés par client | ❌ Un seul jeu |
| Propriété des comptes tranchée | ❌ Non documentée, indices défavorables |
| Signature iOS reproductible | ⚠️ Fonctionne par le chemin manuel ; le chemin Fastlane est cassé |

---

## 11. Le chantier déjà engagé — à porter à la connaissance du client

La branche de travail courante (`rebuild/expo`, commit `c41bc04` du 10 septembre 2026, 01 h 14) contient **un début de reconstruction en Expo / React Native**, antérieur de quelques heures à la réception du brief TRANSASIM.

| | |
|---|---|
| Emplacement | `mobile/` |
| Taille | **4 256 lignes** TypeScript, 23 fichiers de route (`expo-router`), 7 fichiers de test |
| Ce qui est déjà là | Une couche `BrandConfig` (`src/brand/`), un fichier de configuration client (`clients/sabily.json`) avec la palette cible, un thème dérivé, i18n 7 langues, une couche réseau unique, `expo-secure-store` pour le jeton, une tranche verticale de bout en bout, 3 workflows CI dédiés |
| Ce qui manque | Tout le reste : catalogue complet, modules, drapeaux, deuxième client, flavors iOS/Android complets |

**Ce que cela change pour la décision, et qui doit être dit clairement :**

- Le §5 du brief est **entièrement rédigé pour Flutter** : Riverpod, `flutter_launcher_icons` / `flutter_native_splash`, `tool/check_brands.dart`, `productFlavors` Gradle, schémas Xcode. Ces recommandations ne se transposent pas telles quelles.
- Le brief est cependant explicite (§5, en-tête) : *« Ce qui n'est pas négociable, ce sont les propriétés attendues (§3.3), pas les bibliothèques. »* Les sept critères d'acceptation sont **agnostiques du cadre technique**.
- **Le choix de pile est donc une décision client, à prendre en même temps que la recommandation du §13, pas après.** Elle est traitée explicitement ci-dessous.

---

## 12. Risques classés

| # | Risque | Gravité | Portée |
|---|---|---|---|
| R1 | Centimes tronqués → **client débité, provisionnement refusé** pour tout prix à centimes non nuls | 🔴 Critique | Argent + livraison |
| R2 | Aucune commande serveur avant capture, aucune idempotence, aucune reprise | 🔴 Critique | Argent |
| R3 | `id` / `clientSecret` inversés, `id` jamais affecté | 🔴 Critique | Argent |
| R4 | Quatre forks clients, 35 commits de retard, ~2 500 lignes divergentes chacun | 🔴 Critique | Socle |
| R5 | Aucune couche de configuration ; les deux crochets de build existants sont **inertes** | 🔴 Critique | Socle |
| R6 | Connexion Google / Apple appelant des endpoints inexistants | 🔴 Élevé | Compte |
| R7 | Installation eSIM en un geste : 8 méthodes sur 12 sont des bouchons ; écran atteignable et vide | 🟠 Élevé | Produit |
| R8 | Factures fabriquées sur l'appareil, TVA à 0, sans enregistrement serveur ; **aucun endpoint abonné n'existe** | 🟠 Élevé | Conformité |
| R9 | Bon d'achat : tout 2xx annoncé comme valide | 🟠 Élevé | Produit |
| R10 | Sélecteur de devise ne convertissant pas le montant débité ; change fourni par un tiers gratuit | 🟠 Élevé | Argent |
| R11 | Jeton JWT **et mot de passe en clair** dans `SharedPreferences` ; deux copies du jeton, une seule effacée à la déconnexion ; aucun rafraîchissement | 🟠 Élevé | Sécurité |
| R12 | Apple Pay habilitation vide ; Google Pay en `testEnv` avec clé live ; `aps-environment: development` | 🟠 Élevé | Stores |
| R13 | Secrets de CI non cloisonnés ; signature Fastlane iOS cassée ; propriété des comptes inconnue | 🟠 Élevé | Publication |
| R14 | Aucune séparation d'environnement ; tests frappant la production | 🟠 Moyen | Exploitation |
| R15 | 246 `print()` en release, dont chaque corps de réponse et une partie du secret client | 🟡 Moyen | Sécurité |
| R16 | « Mes eSIM » : ~16 à 21 requêtes séquentielles ; l'endpoint optimisé **n'existe pas** côté serveur | 🟡 Moyen | Performance |
| R17 | Analyses non gardées : `countries` nul casse tout le catalogue ; date nulle casse la liste ; division par zéro ; `BigDecimal` → `int?` | 🟡 Moyen | Stabilité |
| R18 | Textes juridiques embarqués dans le binaire, un seul jeu pour tous les clients | 🟡 Moyen | Conformité |
| R19 | Désynchronisation de version Android / iOS (1.1.6+17 vs 1.0.9+8) | 🟡 Moyen | Publication |
| R20 | ~2 000 lignes de code mort, dont un second `main()` et des fichiers `_temp` | 🟡 Faible | Maintenance |

---

## 13. Recommandation argumentée

> **Le brief est explicite (§6.1) : cette recommandation est une décision de client. Les deux options sont exposées avec ce qui plaide pour chacune et ce qu'elle coûte. Elle n'est pas prise ici.**

### 13.1 Le constat qui commande le choix

Trois faits, tous chiffrés plus haut, encadrent la décision :

1. **Ce qui a de la valeur dans ce dépôt n'est pas du code d'interface.** Ce sont **les contrats d'API** (18 endpoints vivants, désormais réconciliés contre le backend réel), **le contrat d'activation eSIM** (`LPA:1$…`), **le patron d'intégration Stripe PaymentSheet**, **le découpage client/dépôt/bloc**, et **24 fichiers de test**. Tout cela est portable, dans n'importe quel cadre.
2. **La couche de présentation n'a rien à reprendre** : 0 style typographique nommé, 0 composant réutilisable, 894 décisions de couleur figées à la compilation, 13 409 lignes de Material écrit en ligne dans 29 écrans, ~2 000 lignes mortes. Et la cible visuelle **inverse la hiérarchie de l'accent** — ce n'est pas une recoloration.
3. **La dette white-label n'est pas répartie, elle est structurelle.** Le mécanisme de déclinaison actuel est le fork de branche. Chaque client coûte **67 fichiers et ~2 500 lignes de divergence permanente**, et trois clients sur quatre sont déjà 35 commits en retard.

Le point 3 est décisif. Un refactoring progressif suppose une base commune sur laquelle refactoriser. **Il n'y en a pas une : il y en a quatre**, dont trois divergentes et périmées. Toute correction du noyau doit aujourd'hui être fusionnée quatre fois.

### 13.2 Option A — Refactoriser progressivement le Flutter existant

**Ce qui plaide pour :**

- L'application **est en production**, sur deux stores, avec des utilisateurs. Elle continue de vendre pendant les travaux.
- Le découpage client/dépôt/bloc est sain et sert de fondation.
- **24 fichiers de test existent** — c'est un filet de non-régression réel, et c'est l'argument le plus fort de cette option.
- Les identifiants de bundle, comptes stores, certificats et fiches sont **déjà en place et déjà publiés**. Aucun risque de perte d'installations.
- La palette est **centralisée** : dériver `CustomTheme` d'une `BrandConfig` transforme 862 sites d'appel en une seule fois, sans les toucher.
- Les corrections critiques du chemin de l'argent (R1, R2, R3) peuvent être livrées **en quelques jours**, indépendamment de tout le reste. R1 est littéralement la suppression d'un `.toInt()`.
- Le §5 du brief est écrit pour Flutter. Aucune traduction d'architecture n'est nécessaire.
- Le §1.4 du brief — *« on n'automatise que ce qu'on a déjà maîtrisé à la main »* — plaide pour partir de ce qui tourne.

**Ce que ça coûte :**

| Poste | Charge |
|---|---|
| Corrections critiques (R1, R2, R3, R6, R9, R11) | **Faible** — chirurgical, à faire quoi qu'il arrive |
| Réunification des 4 branches en un tronc unique | **Élevée et risquée** — 67 fichiers × 3 branches, dont des écrans métier, sur des bases 35 commits divergentes. C'est la tâche la plus incertaine du plan |
| Introduction de `BrandConfig` + flavors + assets par client | **Moyenne** — travail connu, mais touche le natif des deux plateformes |
| Extraction d'un thème dérivé + jetons | **Moyenne** — mécanique sur 862 sites, plus 32 exceptions à traiter à la main |
| Construction d'un système typographique | **Élevée** — 288 littéraux, aucun `TextTheme`, à créer de zéro |
| Bibliothèque de composants | **Très élevée** — n'existe pas ; 13 409 lignes d'interface à recomposer |
| Registre de modules + drapeaux honnêtes | **Élevée** — le routeur est un `switch` monolithique de 151 lignes à remplacer |
| Suppression du code mort | Faible |
| Refonte visuelle vers la charte cible | **Très élevée** — inversion de l'accent, changement de température, 29 écrans |

**La honnêteté impose de le dire :** en additionnant les postes « bibliothèque de composants », « système typographique » et « refonte visuelle », **cette option reconstruit de fait la couche de présentation entière** — tout en portant le passif : deux paradigmes d'état, `ServiceLocator` fait main, routes non typées, 4 branches à réunifier.

**Cette option est la bonne si** la continuité de service et la préservation des fiches stores priment, si l'équipe qui reprend est à l'aise en Flutter, et si le client accepte que le socle multi-client arrive **après** un long travail de consolidation.

### 13.3 Option B — Reconstruire le socle en réutilisant les briques saines

Non pas « tout jeter » : reconstruire la coquille (configuration, thème, navigation, modules, interface) et **réimporter les actifs identifiés au §13.1 point 1** — contrats d'API, contrat eSIM, patron Stripe, découpage en couches, intentions des tests.

**Ce qui plaide pour :**

- **Le socle est construit correct dès le départ.** Les sept critères du §3.3 deviennent des propriétés de conception, pas des cibles de refactoring. Le §6.4 du brief est intransigeant : décliner le deuxième client sans toucher au noyau. Un noyau extrait d'une application mono-client tend à garder ses hypothèses mono-client — la liste du §7 du brief est la liste de ce qui arrive quand on procède ainsi.
- **On ne réunifie rien.** Les 4 branches deviennent 4 configurations. Les ~7 500 lignes de divergence cumulée ne sont pas fusionnées : elles sont **remplacées** par 4 fichiers JSON. C'est le gain le plus important, et il est immédiat.
- **La couche de présentation étant à écrire dans les deux options**, la construire directement contre la charte cible et contre un système de jetons évite de la faire deux fois.
- **Le RTL et la typographie sont du terrain vierge.** Les concevoir dès le premier écran coûte moins que les rétro-ajuster sur 29 écrans.
- **Un chantier existe déjà** (§11) : 4 256 lignes, une tranche verticale fonctionnelle, une `BrandConfig` opérationnelle, 7 tests. Le coût de démarrage est déjà partiellement payé.
- Les défauts du chemin de l'argent se corrigent **une fois**, dans un code neuf, plutôt que dans quatre branches.

**Ce que ça coûte :**

| Poste | Charge |
|---|---|
| Noyau (config, thème, i18n, réseau, session, routeur, registre de modules) | **Moyenne** — largement amorcé (§11) |
| Réimplémentation des modules `catalog`, `account`, `esim`, `checkout` | **Élevée** — mais les contrats d'API sont documentés endpoint par endpoint, ce qui en retire l'essentiel du risque |
| Parité fonctionnelle avec la production | **Élevée, et c'est le vrai risque.** Tant qu'elle n'est pas atteinte, il faut maintenir l'ancienne application en parallèle |
| Migration des tests | **Moyenne** — les intentions se réutilisent, le code non |
| Refonte visuelle | **Élevée** — mais faite une seule fois, contre la charte cible |
| Configuration native, flavors, signature, fiches stores | **Moyenne** — les identifiants et les comptes existent, seule la mécanique de build change |
| **Si l'option B se fait sur une autre pile (Expo/RN)** | **Surcoût réel** : le §5 du brief à retraduire, une nouvelle chaîne de build à maîtriser, une pile de compétences à assumer dans la durée, et le SDK Stripe / l'installation eSIM native à revalider intégralement |

**Le risque principal de cette option est le trou de couverture** : entre le premier jour et la parité, l'ancienne application reste en production et continue de nécessiter des correctifs. Il faut budgéter ce double entretien, ou accepter un gel fonctionnel.

**Cette option est la bonne si** le socle multi-client est l'objectif prioritaire — et le brief entier dit qu'il l'est —, si le client accepte une période de double entretien, et si les corrections critiques du chemin de l'argent sont **livrées immédiatement sur l'application actuelle**, sans attendre le socle.

### 13.4 Ce que l'analyse peut affirmer sans trancher

Les faits penchent en faveur de **l'option B**, pour une raison unique et mesurée : **l'option A doit réunifier quatre branches divergentes de ~2 500 lignes chacune avant même de commencer le socle**, et doit de toute façon réécrire la couche de présentation entière. Le refactoring progressif y perd son principal avantage — la petite marche — sans perdre son principal inconvénient — le passif conservé.

**Trois réserves qui appartiennent au client :**

1. **La continuité de service.** Si l'application actuelle doit continuer d'évoluer fonctionnellement pendant les travaux, le double entretien de l'option B peut coûter plus cher que la réunification de l'option A.
2. **Le choix de pile est distinct du choix refactoriser/reconstruire.** L'option B est réalisable **en Flutter**, en repartant d'un projet neuf dans le même dépôt. Cela conserve la compétence, la conformité au §5 du brief, le SDK Stripe déjà éprouvé et le travail eSIM natif. Le chantier Expo du §11 est un **troisième choix**, qui doit être arbitré explicitement et non par défaut.
3. **Le périmètre BtoB (§5.4)** change le dimensionnement de l'option B, pas celui de l'option A. Si le module revendeur est attendu actif chez Sabily comme le prévoit le §3.3 critère 5, il faut le budgéter dès le découpage en modules.

### 13.5 Ce qui est vrai dans les deux options

**Quelle que soit la décision, ces six points sont indépendants et doivent être engagés tout de suite :**

1. **Corriger R1** (`.toInt()` dans `stripe_client.dart:67-70`). Une ligne. Des clients paient et ne sont pas livrés.
2. **Vérifier R3 en direct** — une requête `POST /v1/payments/init` authentifiée sur un backend de développement.
3. **Retirer les boutons Google / Apple** ou obtenir les endpoints. Aujourd'hui ils échouent silencieusement.
4. **Ouvrir un cahier de demandes backend** : endpoint de recharge, endpoint de factures côté abonné, endpoint agrégé `/sub-plans/subscriber/details`, idempotence, `remainingData` en double émission, authentification tierce. Le §8.4 du brief indique qu'un cahier existe déjà côté web — y verser celles-ci plutôt que de contourner en silence.
5. **Sortir `note` du dépôt**, et trancher la propriété des comptes stores (§10.6).
6. **Arrêter d'ouvrir de nouvelles branches `spc/*`.** Chaque nouveau fork ajoute ~2 500 lignes à ce qu'il faudra réunifier ou remplacer.

---

## 14. Ce dont nous avons besoin de vous

*Correspond au §8 du brief. Les trois premiers points sont bloquants pour la phase 2.*

### 14.1 Décisions bloquantes

| # | Décision | Pourquoi maintenant |
|---|---|---|
| 1 | **Refactoriser ou reconstruire** (§13) | Détermine tout le document d'architecture |
| 2 | **Pile technique** — Flutter ou autre (§11) | Le §5 du brief suppose Flutter. Le chantier en cours ne l'est pas |
| 3 | **Périmètre BtoB mobile** (§5.4) | Deux consignes actives se contredisent. Change le découpage en modules |
| 4 | **Comptes stores : les vôtres ou ceux du client ?** (§10.6) | Bloquant pour toute publication. Indices d'un compte prestataire |
| 5 | **Convention d'`applicationId` / `bundleIdentifier`** | 4 conventions existent déjà, dont une publiée. Irréversible |
| 6 | **Mode sombre : supporté ou explicitement désactivé** | Inexistant aujourd'hui ; la feuille Stripe est même verrouillée en `ThemeMode.light` |
| 7 | **Épinglage de certificat** | §8.3 du brief |
| 8 | **Versions d'OS minimales** | `minSdk 23` / iOS 15.0 aujourd'hui — détermine les capacités eSIM |

### 14.2 Questions d'exploitation, chiffrables par vous seuls

| # | Question | Ce qu'elle dimensionne |
|---|---|---|
| 9 | **Combien de tickets « j'ai payé et je n'ai rien reçu » ?** Et combien de `PaimentException` dans les journaux backend ? | Dimensionne R1 — et confirme ou infirme le §7.2 |
| 10 | **Combien de forfaits ont un prix à centimes non nuls ?** | Détermine la population touchée par R1 |
| 11 | **Apple Pay ou Google Pay ont-ils déjà abouti en production ?** | Détermine le sort de R12 |
| 12 | **Le paiement mobile fonctionne-t-il réellement aujourd'hui ?** | R3 — le bytecode et l'hypothèse de l'audit divergent |
| 13 | **Flutter Web est-il une surface produit soutenue ?** | Son tunnel de paiement ne fonctionne pas (§7.6) |
| 14 | **Le multi-devises est-il une fonctionnalité réelle ou une intention ?** | R10 |
| 15 | **L'arabe est-il un marché réel ?** | Dimensionne la passe RTL |
| 16 | **Les factures PDF sans TVA, sans enregistrement serveur, sont-elles acceptables pour Transasim en France ?** | R8 — question juridique et comptable |

### 14.3 Éléments à fournir

- [ ] **Accès à un backend de développement** + un compte de test — pour trancher R3 en une requête.
- [ ] **La documentation OpenAPI** (`/v3/api-docs`) de l'instance **réellement déployée**, pour confirmer la réconciliation du §7.10 contre la production et non contre un JAR du 4 juillet.
- [ ] **Charte complète de Sabily** : les 5 couleurs de rôle **arbitrées** — le Figma en propose trois jeux (§5.7) —, logos (symbole, lockup, variante fond sombre), icône, écran de lancement.
- [ ] **Arbitrage des maquettes** : les deux tunnels de paiement incompatibles (§5.6), et les 3 cadres Figma non exportés.
- [ ] **Identité légale de Sabily** et les textes juridiques dans les langues servies — ils doivent sortir du binaire (§4.7).
- [ ] **Clé publique Stripe** de chaque client (`pk_…` uniquement).
- [ ] **Domaines** pour les liens universels / App Links — aucun n'existe aujourd'hui (§4.8).
- [ ] **Chartes des trois autres clients** (eSimple, Djezzy, Castrum), pour valider que le contrat `BrandConfig` les couvre avant de le figer.

---

## 15. Annexe — reproduire les chiffres

Toutes les commandes s'exécutent à la racine du dépôt, sur `master` ou sur `rebuild/expo` (`lib/` y est identique).

```bash
# §1 — taille
find lib -name "*.dart" | wc -l                                   # 170
find lib -name "*.dart" -exec cat {} + | wc -l                     # 36982
find lib/screens -name "*.dart" -exec cat {} + | wc -l             # 13409
grep -ro "print(" lib/ --include="*.dart" | wc -l                  # 246
find test -name "*.dart" | wc -l                                   # 24

# §4.1 — divergence par client
git rev-list --left-right --count origin/master...origin/spc/esimple
git diff --numstat origin/master...origin/spc/esimple -- lib/ \
    ':(exclude)lib/generated/' ':(exclude)lib/l10n/' \
  | awk '{a+=$1;d+=$2;f++} END{print f" fichiers, +"a" -"d}'       # 67, +2521 -1590

# §4.2 — la marque dans le code
grep -r "package:sabily_mobile" lib/ --include="*.dart" -o | wc -l           # 527
grep -rn "[Ss]abily\|SABILY" lib/ --include="*.dart" \
  | grep -v "package:sabily_mobile" | wc -l                                  # 163
grep -rn "[Ss]abily\|SABILY" lib/ --include="*.dart" \
  | grep -v "package:sabily_mobile" | cut -d: -f1 | sort -u | wc -l           # 27

# §4.3 — la marque dans les dictionnaires
grep -oi "sabily" lib/l10n/*.arb | wc -l                            # 88
for f in lib/l10n/*.arb; do echo -n "$f: "; grep -oi sabily "$f" | wc -l; done

# §4.4 — couleurs
grep -ro "CustomTheme\." lib/ --include="*.dart" | wc -l            # 862
grep -rl "CustomTheme\." lib/ --include="*.dart" | wc -l            # 37
grep -rnoE "Color\(0x[0-9a-fA-F]{6,8}\)" lib/ --include="*.dart" | wc -l   # 1
grep -roE "\bColors\.[a-zA-Z0-9]+" lib/ --include="*.dart" | wc -l         # 31

# §4.5 — typographie
grep -roE "fontSize:\s*[0-9]+" lib/ --include="*.dart" | wc -l      # 288
grep -rhoE "fontSize:\s*[0-9]+" lib/ --include="*.dart" \
  | grep -oE "[0-9]+" | sort -u | wc -l                             # 14
grep -rn "TextTheme" lib/ --include="*.dart"                        # (vide)

# §4.6 / §4.7 — hôtes, e-mails, assets
grep -rnE "https?://" lib/ --include="*.dart" | wc -l               # 12
grep -rnoE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" lib/ --include="*.dart" | sort -u
grep -roE "'assets/[^']*'" lib/ --include="*.dart" | wc -l          # 22

# §4.9 — les crochets de configuration inertes
grep -rn "dotenv.load" lib/                                         # assets/.env
grep -rn "fromEnvironment" lib/                                     # (vide)
grep -rn -A4 "Create .env file" .github/workflows/*.yml             # écrit ./.env

# §4.10 — les drapeaux
grep -rn "FEATURE_" lib/ --include="*.dart"
grep -rn "AppRoutes.packPurchase" lib/ --include="*.dart"           # 4 entrées, 1 gardée

# §8.1 — RTL
grep -ro "EdgeInsetsDirectional" lib/ --include="*.dart" | wc -l    # 0

# §9.3 / §10 — flavors, signature
grep -rn "productFlavors\|flavorDimensions" android/                # (vide)
ls ios/Runner.xcodeproj/xcshareddata/xcschemes/                     # Runner.xcscheme seul
grep -oE "DEVELOPMENT_TEAM = [A-Z0-9]+;" ios/Runner.xcodeproj/project.pbxproj | sort -u
grep -rhoE "secrets\.[A-Z0-9_]+" .github/workflows/ | sort -u
```

**Réconciliation backend** — le JAR est un fat-jar Spring Boot ; les classes applicatives sont sous `BOOT-INF/classes/com/tamarisoft/sabily/`. Les verdicts du §7.10 sont issus de la lecture du pool de constantes et du bytecode des méthodes (annotations `@RequestParam` / `@RequestBody`, valeurs de `@PostMapping`, ordre des arguments de constructeur, constantes numériques). Un JDK — absent de cette machine — permettrait de reproduire les mêmes constats avec `javap -c -p`.

---

*Fin de l'analyse. Conformément au §6.2 du brief, `ARCHITECTURE-MOBILE.md` ne sera pas commencé avant validation de ce document et arbitrage des décisions du §14.1.*
