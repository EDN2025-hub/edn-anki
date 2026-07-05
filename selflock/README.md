# SelfShield — bloqueur de contenu pornographique/NSFW pour iPhone

Application iOS de type **SelfLock** : elle bloque l'accès aux sites
pornographiques et NSFW (y compris **Twitter/X** et **Reddit**, par choix
explicite) sur tout l'appareil, se **verrouille** pour une durée choisie, et
utilise la **base de données de ThePornDude** (l'annuaire de sites pour
adultes le plus complet du web) comme source de vérité — extraite de façon
structurée, jamais par scraping aveugle.

**Trois façons de l'utiliser** (voir la matrice en fin de document) :
- **iPhone sans payer ni réinstaller** : `iphone/GUIDE_SANS_COMPTE_DEV.md`
  (configuration système permanente, 0 €, 0 ressource, recommandé) ;
- **Mac / Windows** : `desktop/install-macos.sh` et
  `desktop/install-windows.ps1` (hosts + DNS filtrant, aucun processus
  résident) ;
- **App iOS complète** : `ios/` (Xcode ; compte gratuit = re-signature
  tous les 7 jours, compte développeur = 1 an).

```
selflock/
├── iphone/               Guide iPhone SANS compte développeur (permanent, 0 €)
├── desktop/              Installateurs macOS et Windows (hosts + DNS)
├── blocklist-pipeline/   Extraction + validation de la base ThePornDude
│   ├── fetch_theporndude.py     extraction structurée (endpoints JSON officiels)
│   ├── build_blocklist.py       validation anti-faux-positifs + génération des règles
│   ├── allowlist.txt            garde-fou : domaines mainstream jamais bloqués
│   ├── platforms.txt            plateformes généralistes (traitement spécial)
│   ├── user_platform_blocks.txt plateformes bloquées par choix (Twitter, Reddit)
│   └── brand_tokens.txt         jetons adultes pour les regex de rotation
├── data/                 Sorties du pipeline (blocklist, règles Safari, rapport)
└── ios/                  Projet Xcode (XcodeGen)
    ├── project.yml
    ├── SelfShield/              app SwiftUI
    ├── ContentBlocker/          extension Safari Content Blocker
    └── dns/                     profil DNS filtrant optionnel
```

## 1. La base de données ThePornDude — extraction propre

**Aucun scraping à l'aveugle.** Le pipeline n'analyse pas des pages HTML au
hasard et ne suit aucun lien de manière heuristique :

1. **Énumération** via les *sitemaps officiels* du site
   (`sitemap.link.*.xml`) : c'est l'index publié par ThePornDude lui-même
   (~14 000 reviews, 27 langues, dédupliquées par identifiant).
2. **Extraction** via l'*endpoint JSON officiel* de chaque review
   (`/json/<id>/<slug>`) — celui que leurs propres pages consomment. Il
   fournit des champs structurés et non ambigus :
   - `data_category_link` → **l'URL officielle du site listé** ;
   - `data_category` → la catégorie (ex. « Free Porn Tube Sites ») ;
   - `is_deadsite` → site mort ou non.
3. Cache disque + reprise ; seuls les 404 définitifs sont mémorisés, les
   erreurs transitoires (rate-limit 429…) sont retentées. Faible
   concurrence, délais aléatoires, backoff long : le serveur n'est pas
   maltraité.

```bash
cd selflock/blocklist-pipeline
python3 fetch_theporndude.py --out ../data --cache .cache/tpd
# relancer jusqu'à « 0 transitoires à retenter » (le cache fait le reste)
```

## 2. Garanties anti-faux-positifs

`build_blocklist.py` applique plusieurs gardes **avant** qu'un domaine
n'entre dans la liste :

| Garde | Effet |
|---|---|
| **Allowlist** (`allowlist.txt`, ~160 domaines mainstream) | jamais bloqué ; l'entrée part en `quarantine_review.txt` pour revue manuelle |
| **Plateformes** (`platforms.txt` : Reddit, Twitter, Discord, Telegram, YouTube, Blogspot…) | jamais auto-bloquées, même si ThePornDude référence un subreddit ou un compte : seul un contenu hébergé en *sous-domaine* (ex. `xyz.blogspot.com`) est bloqué, au sous-domaine près |
| **Choix utilisateur** (`user_platform_blocks.txt`) | Twitter/X et Reddit sont bloqués **parce que tu l'as demandé**, au niveau plateforme (domaines + CDN : `t.co`, `twimg.com`, `redd.it`…) — pas parce que l'algorithme les aurait « devinés » |
| **Redirecteurs d'affiliation** (`pdude.link`, `tpd.deals`) | résolus jusqu'au domaine de destination *final* (`--resolve`), jamais bloqués eux-mêmes tels quels sans résolution |
| **Pages internes ThePornDude** (sites morts → « hall of fame ») | ignorées |
| **Vérifications finales** | assertions : intersection blocklist ∩ allowlist = ∅ et blocklist ∩ plateformes = ∅, sinon le build échoue |
| **Croisement externe** (`--crosscheck`) | chaque domaine est comparé à des blocklists publiques indépendantes ; ceux connus uniquement de ThePornDude sont listés dans `report.md` pour inspection |

```bash
python3 build_blocklist.py --dataset ../data/theporndude_sites.json \
    --out ../data --resolve --crosscheck --merge-external
```

### Couverture maximale : `--merge-external`

Pour bloquer un maximum de sites au-delà de la base ThePornDude, le mode
`--merge-external` fusionne trois blocklists publiques maintenues
indépendamment (Blocklist Project, Sinfonietta, StevenBlack). Règle de
consensus anti-faux-positifs : un domaine externe n'est inclus **que s'il
figure dans au moins 2 des 3 listes**, et il reste soumis aux gardes
allowlist/plateformes. Résultat : ~45 000 domaines, audités contre une
liste de domaines mainstream (deviantart, quora, weebly… détectés et
proprement écartés vers la garde plateformes).

## 3. Sites qui changent régulièrement de nom de domaine

Deux mécanismes complémentaires :

1. **Regex de rotation** (hors-ligne, immédiat) : pour chaque marque de la
   base (label de domaine sans chiffres), une règle
   `^https?://([^/:]*\.)?marque[0-9]*\.<n'importe quel TLD>` est générée
   **si et seulement si** :
   - la marque fait ≥ 5 caractères, **et**
   - elle contient un jeton explicitement adulte (`porn`, `xxx`, `hentai`…)
     **ou** est déjà observée avec ≥ 2 variantes de TLD/numéro dans la base,
   - et n'est pas un mot générique (`video`, `movies`, `games`…).

   Ainsi `xmoviesforyou.com` bloqué ⇒ `xmoviesforyou2.net`,
   `xmoviesforyou.to`… bloqués aussi, sans mise à jour. La regex matche le
   label **exact** de la marque : `cumlouder` ne matchera jamais
   `documentcloud`, etc.

2. **Mise à jour continue** (en ligne) : l'app télécharge chaque jour la
   dernière `blockerList.json` publiée par ce dépôt (tâche de fond
   `BGAppRefreshTask`) et recharge l'extension Safari. La validation
   n'accepte que des règles `block` : une mise à jour distante ne peut
   jamais *autoriser* quoi que ce soit.

## 4. L'app iOS : couches de blocage et anti-contournement

| Couche | Portée | Mécanisme |
|---|---|---|
| **Filtre web Temps d'écran** (`ManagedSettings`) | Safari + toutes les WebView, **navigation privée désactivée automatiquement** | filtre adulte système d'Apple (`.auto`) + domaines ajoutés (Twitter/X, Reddit, racines majeures) |
| **Safari Content Blocker** | Safari | base ThePornDude complète + consensus de listes publiques (~45 000 domaines) + regex de rotation, limite Safari 150 000 règles |
| **App Store limité à 12+** | App Store | `appStore.maximumRating = 300` : les apps NSFW (classées 17+) sont **invisibles et ininstallables** |
| **Mode strict anti-VPN** (option) | App Store | `denyAppInstallation` : plus aucune installation d'app possible — impossible d'installer un VPN ou un navigateur de contournement ; activable à tout moment, désactivable seulement hors verrou |
| **Shield d'applications** (`FamilyControls`) | apps natives | blocage des apps choisies : Twitter, Reddit, navigateurs tiers (Chrome/Firefox n'appliquent pas le Content Blocker), VPN déjà installés |
| **`denyAppRemoval`** | système | impossible de **supprimer** SelfShield (ou toute app) tant que la protection est active |
| **Horloge verrouillée** | système | `requireAutomaticDateAndTime` : impossible d'avancer la date pour faire expirer le verrou |
| **Comptes verrouillés** | système | `lockAccounts` : impossible de se déconnecter de l'identifiant Apple |
| **Médias explicites** | Musique/Podcasts/Livres/Films | contenu explicite, érotique et NC-17 bloqués |
| **Verrou d'engagement** | app | durée de 24 h à 1 an ; code d'urgence aléatoire affiché une seule fois, stocké uniquement en SHA-256, à confier à un tiers |
| **Profil DNS filtrant** (optionnel, `ios/dns/`) | tout l'appareil, toutes les apps | DoH Cloudflare for Families (1.1.1.3), profil marqué non-supprimable |

### Persistance : redémarrage, fermeture, purge RAM

Les restrictions Temps d'écran et le Content Blocker Safari sont stockés et
appliqués par des **démons système iOS**, pas par l'app :

- fermer l'app (swipe dans le sélecteur) **ne désactive rien** ;
- la purge de RAM par iOS **ne désactive rien** ;
- un **redémarrage** de l'iPhone recharge ces restrictions automatiquement.

En plus, deux mécanismes de ré-affirmation tournent sans que l'app soit
ouverte :

1. **Extension `SelfShieldMonitor`** (DeviceActivity) : iOS l'exécute dans
   un processus système au début/fin de chaque intervalle quotidien, et
   elle ré-applique l'intégralité des réglages (même si l'app n'est jamais
   relancée) ;
2. **Ré-application au premier plan** : chaque ouverture de l'app ré-écrit
   tous les réglages ;
3. la mise à jour de la blocklist tourne en tâche de fond planifiée
   (`BGAppRefreshTask`).

### Pourquoi un VPN ou un changement de DNS ne suffisent pas

Le filtre Temps d'écran, le shield d'apps et le Content Blocker sont
appliqués **sur l'appareil, dans le moteur WebKit et au niveau du
système** — pas sur le réseau. Un VPN ou un DNS tiers ne change donc rien :
la page est bloquée avant même que la requête sorte. Seule la couche DNS
optionnelle (profil `ios/dns/`) est contournable par VPN, c'est pour cela
qu'elle n'est qu'une défense en profondeur. Le **mode strict** empêche en
plus d'installer de nouvelles apps (VPN, navigateurs exotiques), et le
shield permet de verrouiller celles déjà installées.

### Qualité : tests et audit anti-faux-positifs

`blocklist-pipeline/tests_pipeline.py` (offline, sans réseau) vérifie à
chaque build : normalisation des hôtes, sûreté des regex de rotation sur un
corpus piège (`documentcloud.org`, `cummins.com`, `sussex.ac.uk`,
`dickssportinggoods.com`, `scunthorpe.gov.uk`…), règle de consensus
externe, validité des règles Safari (100 % `block`, < 150 000), cohérence
des fichiers de politique, et — si les données sont présentes —
`blocklist ∩ allowlist = ∅`. Cette suite a déjà attrapé deux bugs réels
avant mise en production (extraction de marque avec chiffres médians,
domaine dupliqué entre allowlist et plateformes).

```bash
python3 blocklist-pipeline/tests_pipeline.py
```

### Ressources consommées

Aucune couche n'exécute de processus résident :

| Couche | Processus | RAM | CPU/GPU |
|---|---|---|---|
| Temps d'écran / ManagedSettings | démons iOS existants | 0 dédiée | 0 |
| Safari Content Blocker | compilé par Safari en table binaire | ~qq Mo dans Safari | ~0 (lookup O(1) par requête) |
| Fichier hosts (Mac/Win) | résolveur système existant | ~2 Mo de texte | 0 |
| DNS filtrant | aucun (résolution côté serveur) | 0 | 0 |
| App SelfShield | uniquement quand tu l'ouvres | ~30 Mo ouverte, 0 fermée | 0 en veille |

L'app n'a **pas besoin de tourner** : fermée ou purgée de la RAM, toutes
les protections restent actives (elles vivent dans les démons système).

### Honnêteté sur le « non contournable »

Aucune app iOS non-MDM ne peut être contournable à 0 %. SelfShield empile
les protections les plus fortes accessibles à une app normale :
suppression d'app interdite, filtre système avec navigation privée coupée,
verrou temporel avec code détenu par un tiers, profil DNS non-supprimable.
Les limites résiduelles connues :

- l'utilisateur peut désactiver Temps d'écran **s'il connaît le code Temps
  d'écran** → *parade* : faire poser le code Temps d'écran par la personne
  de confiance (Réglages > Temps d'écran), ce qui verrouille aussi la
  révocation de l'autorisation ;
- effacer/restaurer l'iPhone reste possible → coût élevé, friction
  maximale ;
- pour un vrai « impossible », il faut un appareil **supervisé** (MDM,
  ex. Apple Configurator) — documenté ici comme option ultime.

Avec code Temps d'écran tiers + profil DNS + verrou SelfShield, le
contournement exige en pratique d'effacer complètement l'appareil.

### Audit des vecteurs de contournement

| Vecteur | Paré par |
|---|---|
| Supprimer l'app | `denyAppRemoval` (Temps d'écran) |
| Fermer l'app / redémarrer / purge RAM | réglages appliqués par les démons système + ré-affirmation quotidienne `SelfShieldMonitor` |
| VPN | filtre appliqué sur l'appareil (WebKit/système), pas sur le réseau — VPN inopérant ; installation de nouvelles apps VPN bloquée en mode strict ; VPN existants shieldables |
| Changer de DNS | idem : le filtre ne dépend pas du DNS ; la couche DNS n'est qu'une défense en profondeur |
| Navigation privée | désactivée automatiquement par le filtre système |
| Autre navigateur (Chrome, Firefox…) | filtre système s'applique aux WebViews ; apps shieldables ; installation bloquée (12+/strict) |
| Installer une app NSFW | App Store plafonné à 12+ |
| Avancer la date pour expirer le verrou | `requireAutomaticDateAndTime` |
| Se déconnecter de l'identifiant Apple | `lockAccounts` |
| Désactiver Temps d'écran | code Temps d'écran détenu par une personne de confiance |
| Retirer le profil DNS | `PayloadRemovalDisallowed` |
| Mise à jour distante malveillante de la liste | le client n'accepte que des règles `block` (jamais d'autorisation) |
| Effacer complètement l'iPhone | seul vecteur restant sans supervision : friction maximale, visible par la personne de confiance ; option supervision (`iphone/GUIDE_SANS_COMPTE_DEV.md`, option B) pour le fermer aussi |

## Matrice d'installation

| Plateforme | Méthode | Coût | Expiration | Fichier |
|---|---|---|---|---|
| iPhone (recommandé) | config système + profil DNS | 0 € | jamais | `iphone/GUIDE_SANS_COMPTE_DEV.md` (option A) |
| iPhone (max absolu) | supervision Apple Configurator | 0 € (Mac requis 1×) | jamais | idem (option B) |
| iPhone (app complète) | Xcode | 0 € (7 j) ou 99 €/an | 7 j / 1 an | `ios/` |
| macOS | hosts + DNS + Temps d'écran | 0 € | jamais | `desktop/install-macos.sh` |
| Windows 10/11 | hosts + DoH + Family Safety | 0 € | jamais | `desktop/install-windows.ps1` |

## 5. Installation sur votre iPhone

Apple n'autorise l'installation d'apps que via l'App Store ou Xcode : il
faut donc un **Mac avec Xcode** (les API FamilyControls ne peuvent pas être
« sideloadées » par AltStore & co, qui ne signent pas cet entitlement).
Comptez ~20 minutes la première fois.

### Prérequis
- un Mac (ou un accès à un Mac / Mac mini cloud) avec **Xcode 15+** ;
- un **identifiant Apple** (compte gratuit possible : l'app expire alors
  au bout de 7 jours et doit être re-signée ; compte développeur à
  99 €/an : 1 an) ;
- l'iPhone, en mode développeur (Réglages > Confidentialité et sécurité >
  Mode développeur, après le premier branchement à Xcode).

### Étapes

## Compilation (détail)

```bash
brew install xcodegen
cd selflock/ios
xcodegen generate
open SelfShield.xcodeproj
```

1. **Cloner ce dépôt et générer le projet** :
   ```bash
   git clone https://github.com/EDN2025-hub/edn-anki.git
   cd edn-anki/selflock/ios
   brew install xcodegen
   xcodegen generate
   open SelfShield.xcodeproj
   ```
2. **Identifiants** : remplacer le préfixe `com.example.selfshield` par le
   vôtre (unique) dans `project.yml`, `Constants.swift`,
   `ContentBlockerRequestHandler.swift` et `SelfShieldMonitor.swift` n'y
   touche pas (il lit `C.appGroup`) ; remplacer aussi l'App Group
   `group.com.example.selfshield`. Regénérer (`xcodegen generate`).
3. **Signature** : dans Xcode, pour les 3 cibles (SelfShield,
   ContentBlocker, Monitor) : *Signing & Capabilities* → cocher
   *Automatically manage signing* et choisir votre Team. Vérifier que les
   capabilities **Family Controls** (app + Monitor) et **App Groups**
   (les 3 cibles, même groupe) sont présentes.
4. **Blocklist** : copier `../data/blockerList.json` dans
   `ContentBlocker/` (le pipeline la génère ; une version est fournie dans
   le dépôt).
5. **Compiler sur l'iPhone réel** (câble USB, sélectionner l'appareil dans
   Xcode, ⌘R). Les API FamilyControls ne fonctionnent pas dans le
   simulateur. Au premier lancement : Réglages > Général > VPN et gestion
   de l'appareil > faire confiance à votre certificat développeur.
6. **Sur l'iPhone, suivre l'onboarding de l'app** :
   - autoriser Temps d'écran (popup système) ;
   - activer l'extension : Réglages > Apps > Safari > Extensions >
     SelfShield Blocker ;
   - sélectionner les apps à bloquer (Twitter, Reddit, Chrome, Firefox,
     apps VPN déjà installées…) ;
   - activer la protection, puis **poser le verrou d'engagement** et
     envoyer le code d'urgence à une personne de confiance.
7. **Durcissement recommandé** :
   - activer le **mode strict anti-VPN** dans l'app ;
   - installer le profil DNS `ios/dns/SelfShield-DNS.mobileconfig`
     (AirDrop → Réglages > Profil téléchargé > Installer) ;
   - faire poser un **code Temps d'écran** par la personne de confiance
     (Réglages > Temps d'écran > Utiliser un code) : sans ce code, même la
     révocation de l'autorisation de SelfShield est impossible.
