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
4. **Apps Twitter/Reddit : blocage ciblé par Limites d'apps.**
   ⚠️ N'utilise PAS le plafond d'âge « 12+ » ni « Installation d'apps :
   Non » si tu veux garder des apps classées 17+ comme Claude, ChatGPT ou
   Firefox — les classements d'âge bloquent par familles entières.
   À la place :
   - Temps d'écran > **Limites d'apps** > Ajouter une limite ;
   - cocher la catégorie **Réseaux sociaux** entière ;
   - durée **1 min/jour** + **« Bloquer à la fin de la limite »**.
   Une limite de *catégorie* couvre automatiquement toute nouvelle app
   installée dans cette catégorie : réinstaller Twitter/Reddit ou un
   client alternatif ne sert à rien.
   - Puis Temps d'écran > **Toujours autorisées** : y ajouter les réseaux
     sociaux que tu veux conserver (WhatsApp, Instagram…) — ils échappent
     à la limite. Ne pas y mettre Twitter/Reddit.
   - Les apps NSFW, elles, sont déjà écartées par l'App Store standard
     (Apple n'y accepte pas d'apps pornographiques) + le filtre web pour
     Safari ; le plafond 12+/le blocage d'installation restent des options
     « mode strict » si tu n'utilises aucune app 17+.
5. **Restrictions** → interdire les **modifications de compte** et les
   **modifications de code**.
6. Supprimer les apps Twitter/X, Reddit, VPN et navigateurs tiers déjà
   installées (la limite de catégorie couvrira toute réinstallation).

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

La « supervision » est le mode entreprise/école d'iOS : le seul où les
restrictions sont réellement inviolables. L'outil, **Apple Configurator**,
est gratuit (Mac App Store). Un profil prêt à l'emploi est fourni :
`supervision/SelfShield-Supervision.mobileconfig`.

### Ce que la supervision débloque (impossible autrement)

| Pouvoir | Effet |
|---|---|
| Profil **non-retirable** | seul le Mac superviseur peut le retirer — aucun code sur l'iPhone ne le permet |
| Filtre web natif + liste noire imposée | appliqué par l'OS à tous les navigateurs, non désactivable |
| `allowVPNCreation = false` | le vecteur VPN disparaît totalement |
| `allowAppInstallation` / `allowUIConfigurationProfileInstallation = false` | rien ne peut être ajouté pour contourner |
| `allowEraseContentAndSettings = false` | **« Effacer contenu et réglages » est grisé** : le dernier vecteur de l'option A est fermé |

### Pas-à-pas (~45 min, dont la restauration)

1. **Sauvegarder** l'iPhone (iCloud ou câble) — la mise sous supervision
   **efface l'appareil**, une seule fois.
2. Sur un Mac (le tien, celui d'un proche, 30 min d'accès suffisent) :
   installer **Apple Configurator**, brancher l'iPhone en USB, le
   déverrouiller et « Se fier » au Mac.
3. Configurator → sélectionner l'iPhone → **Préparer** :
   - Préparation *manuelle* ;
   - **Superviser l'appareil : OUI** ; autoriser l'appairage si tu veux
     pouvoir gérer depuis ce Mac ensuite ;
   - ne PAS inscrire à un serveur MDM ;
   - nom de l'organisation : ce que tu veux (« SelfShield »).
   L'iPhone redémarre, vierge et supervisé.
4. Restaurer ta sauvegarde (Finder/iTunes ou iCloud à la configuration).
5. Configurator → l'iPhone → **Ajouter > Profils** → choisir
   `SelfShield-Supervision.mobileconfig`. Il s'installe marqué
   « non retirable ».
6. Vérifier sur l'iPhone : Réglages > Général > VPN et gestion de
   l'appareil > le profil apparaît sans bouton « Supprimer ».
7. Confier le Mac superviseur — ou exporter l'**identité de supervision**
   (Configurator > Réglages > Organisations > exporter) — à ta personne
   de confiance. C'est elle qui détient la clé.

### Limites résiduelles, pour être exact

- Une **restauration DFU** (flash complet via un ordinateur) reste
  physiquement possible, comme sur tout iPhone : friction maximale,
  perte totale des données, et l'appareil ressort non configuré.
- La liste noire du profil contient les plateformes + racines majeures ;
  le gros du blocage vient du filtre adulte natif (`AutoFilterEnabled`)
  + de la couche DNS. Sur appareil supervisé tu peux aussi ajouter
  l'app SelfShield par-dessus pour la liste exhaustive Safari.

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
