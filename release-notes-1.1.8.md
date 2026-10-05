# 1.1.8 (21) — Android

Both apps ship the same build. Nothing here is a marketing line: each sentence
is a change a user can see.

The headline is the incident: **My eSIMs was empty for every real customer.**
Production answers the plan list in a flat shape the app refused to read, so a
paid-for eSIM simply did not appear. That is fixed, and three smaller defects
around it with it.

---

## Sabily

### English

**What's new**

- Your eSIMs are back. Plans bought in the app or added with a voucher now
  appear in My eSIMs, and show up straight after the purchase instead of
  after a restart.
- The data usage bar is back, with real numbers from the network.
- Install on this device now opens your phone's own eSIM setup.
- New help: "Does my phone support eSIM?", with how to check your exact model.
- Top up opens the Store.
- Scanning an eSIM QR code in the voucher scanner now says what it is instead
  of reporting an invalid voucher.

### Français

**Nouveautés**

- Vos eSIM sont de retour. Les forfaits achetés dans l'application ou ajoutés
  avec un bon apparaissent de nouveau dans Mes eSIM, et s'affichent juste après
  l'achat au lieu d'attendre un redémarrage.
- La barre de consommation est de retour, avec les chiffres réels du réseau.
- « Installer sur cet appareil » ouvre désormais la configuration eSIM de votre
  téléphone.
- Nouvelle aide : « Mon téléphone est-il compatible eSIM ? », avec la marche à
  suivre pour vérifier votre modèle exact.
- « Recharger » ouvre la boutique.
- Scanner un QR code eSIM dans le lecteur de bons indique maintenant de quoi il
  s'agit au lieu d'annoncer un bon invalide.

### Deutsch

**Neu**

- Ihre eSIMs sind wieder da. In der App gekaufte oder per Gutschein
  hinzugefügte Tarife erscheinen wieder unter Meine eSIMs, und zwar direkt nach
  dem Kauf statt erst nach einem Neustart.
- Die Verbrauchsanzeige ist zurück, mit echten Zahlen aus dem Netz.
- „Auf diesem Gerät installieren" öffnet jetzt die eSIM-Einrichtung Ihres
  Telefons.
- Neue Hilfe: „Unterstützt mein Telefon eSIM?", samt Anleitung zur Prüfung
  Ihres genauen Modells.
- „Aufladen" öffnet den Shop.
- Das Scannen eines eSIM-QR-Codes im Gutschein-Scanner sagt jetzt, worum es
  sich handelt, statt einen ungültigen Gutschein zu melden.

---

## eSimple

Same changes as above, plus:

### English

- A new app icon.

### Français

- Une nouvelle icône d'application.

### Deutsch

- Ein neues App-Symbol.

---

## Not in this release

Stated so nobody looks for them:

- **Payments are still disabled.** Both brands ship a placeholder Stripe key,
  so checkout cannot take money yet.
- **The usage bar has never been seen against the live server.** The gate that
  blocked it is fixed and the logic is covered by tests, but no device run has
  confirmed what the backend actually returns for `unit`. The app shows the
  server's own numbers and unit text when it does not recognise the unit,
  rather than guessing.
- **Installing an eSIM from inside the app** is not possible for this
  certificate: the profile's GSMA access rules at the SM-DP+ do not name it.
  The Install button hands off to the phone's own eSIM setup instead, which
  works. Registering the signing certificate with the operator would be needed
  to change that.
- **iOS is not in this release.** It is built separately on the Mac from
  `release/1.1.8-21`.
