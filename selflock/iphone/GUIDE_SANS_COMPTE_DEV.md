# iPhone : protection permanente SANS compte développeur, SANS réinstallation

## Pourquoi pas l'app tous les 7 jours ?

La limite des 7 jours ne vient pas de l'app mais de la **signature Apple** :
toute app installée hors App Store avec un compte gratuit expire au bout de
7 jours (1 an avec le compte à 99 €/an). Aucune réécriture de l'app ne peut
contourner ça.

La bonne nouvelle : **tout ce que fait l'app SelfShield repose sur des
mécanismes système d'iOS qui se configurent aussi À LA MAIN**, sans app,
gratuitement, de façon permanente, avec zéro consommation de ressources
(ce sont les démons d'iOS qui appliquent les règles, pas un processus à
vous). C'est la méthode recommandée.

---

## Option A — 10 minutes, gratuit, permanent, sans ordinateur

### 1. Temps d'écran (le cœur — insensible aux VPN et aux DNS)

Réglages > **Temps d'écran** :

1. **Restrictions relatives au contenu et à la confidentialité** : activer.
2. **Contenu web** → **Limiter les sites web pour adultes**.
   C'est le filtre système d'Apple : il s'applique à Safari ET aux
   navigateurs/WebViews tiers, désactive la navigation privée, et comme il
   agit sur l'appareil, **un VPN ou un changement de DNS ne le contourne
   pas**.
3. Toujours dans Contenu web, section **NE JAMAIS AUTORISER**, ajouter les
   domaines de `selflock/data/screentime_denylist.txt` — au minimum :
   ```
   twitter.com      x.com          t.co           twimg.com
   reddit.com       redd.it        redditmedia.com
   theporndude.com  pornhub.com    xvideos.com    xnxx.com
   xhamster.com     onlyfans.com   chaturbate.com spankbang.com
   ```
   (Le filtre adulte d'Apple couvre déjà l'immense majorité des sites
   pornos, y compris les nouveaux domaines — cette liste ajoute les
   plateformes que le filtre ne juge pas « adultes » et les racines
   majeures.)
4. **Restrictions** → **Achats dans l'iTunes et l'App Store** :
   - **Installation d'apps : Non** (mode strict anti-VPN), ou à défaut
   - **Apps** → limiter à **12 ans et moins** : les apps NSFW (17+) et la
     plupart des navigateurs alternatifs deviennent ininstallables.
5. **Restrictions** → interdire les **modifications de compte** et les
   **modifications de code**.
6. Apps déjà installées à retirer : supprimer Twitter/X, Reddit, VPN,
   navigateurs tiers AVANT l'étape 7 (après, la réinstallation sera
   impossible).

### 2. Le verrou : le code Temps d'écran détenu par un tiers

Réglages > Temps d'écran > **Utiliser un code** : faire **saisir le code
par une personne de confiance sans le regarder**.

C'est l'équivalent du « verrou d'engagement » de l'app : sans ce code,
impossible de désactiver le filtre, de réautoriser un site, de réinstaller
une app ou de lever les restrictions. Apple impose ce code au niveau
système — c'est le mécanisme anti-bypass le plus fort disponible sans MDM.

### 3. Couche réseau (optionnelle) : profil DNS filtrant

Installer `selflock/ios/dns/SelfShield-DNS.mobileconfig` (l'ouvrir depuis
Mail/AirDrop → Réglages > Profil téléchargé > Installer). Aucune signature
requise, gratuit, permanent (`PayloadRemovalDisallowed`), zéro ressource :
la résolution DNS passe par Cloudflare for Families qui bloque le porno
côté serveur — y compris pour les apps hors navigateur.

### Bilan option A

| Critère | Résultat |
|---|---|
| Coût | 0 € |
| Expiration | jamais |
| RAM/CPU/GPU | 0 (démons système iOS) |
| Survit à | redémarrage, fermeture, purge RAM, mise à jour iOS |
| VPN/DNS | inopérants contre le filtre système |
| Bypass restant | effacement complet de l'iPhone (et la personne de confiance le verrait) |

---

## Option B — le maximum absolu : supervision (gratuit, Mac requis 1 fois)

Pour un blocage de niveau MDM (celui des entreprises), **Apple
Configurator** (app gratuite d'Apple sur le Mac App Store) permet de
« superviser » l'iPhone :

1. ⚠️ La mise sous supervision **efface l'iPhone** (sauvegarder avant).
2. Apple Configurator > superviser l'appareil, puis installer un profil
   avec : filtre de contenu web (liste noire complète `blockerList`
   convertie), interdiction des VPN, interdiction d'installer des profils
   ou des apps, **profils impossibles à retirer**.
3. Résultat : contournement impossible sans effacer l'appareil via le Mac
   superviseur.

C'est l'option « zéro bypass » réelle ; l'option A en est très proche pour
un effort bien moindre.

---

## Option C — l'app SelfShield (si un jour tu veux l'app complète)

- Compte gratuit : re-signature tous les 7 jours (⌘R dans Xcode).
- Compte développeur 99 €/an : 1 an, plus la blocklist ThePornDude
  complète dans Safari et le verrou d'engagement intégré.
- L'app n'apporte par rapport à l'option A que : la blocklist exhaustive
  Safari (~45 000 domaines au lieu du filtre heuristique d'Apple + liste
  manuelle) et le confort de configuration.
