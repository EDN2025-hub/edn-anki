# Mémoire de session — projet SelfShield (2026-07-05)

Archive complète de la session de création. Ce fichier est la mémoire de
référence pour toute session Claude future : l'utilisateur a supprimé la
conversation d'origine, TOUT ce qui compte est ici, dans `CLAUDE.md`, et
dans les fichiers du dépôt.

## 1. L'utilisateur et sa demande

- Utilisateur : eddi.2016@gmail.com, iPhone 11, pas de câble Lightning,
  accès possible à un Mac mais pas en permanence, ne veut PAS payer le
  compte développeur Apple (99 €/an) ni re-signer une app tous les 7 jours.
- Demande initiale : une app iPhone type **SelfLock** qui bloque tout site
  pornographique/NSFW, **y compris Twitter/X et Reddit** (plateformes
  mixtes, bloquées par SON choix explicite — jamais par inférence), la
  moins contournable possible, en utilisant la **base de données de
  ThePornDude** (toutes leurs URL), **sans scraping à l'aveugle**, **zéro
  faux positif** (ne bloquer QUE le NSFW), et gérer les sites qui changent
  régulièrement de domaine.
- Exigences ajoutées en cours de route : survivre au redémarrage/fermeture/
  purge RAM ; bloquer le téléchargement d'apps NSFW ; non contournable par
  VPN/DNS ; installable sur Mac/iPhone/Windows ; consommation de
  ressources minimale ; audit final anti-faux-positifs ; verrou par défi
  de calcul mental (voir §6).

## 2. Ce qui a été livré (tout est dans `selflock/`)

- `blocklist-pipeline/` : extraction ThePornDude via leurs **endpoints
  JSON officiels** (`/json/<id>/<slug>`, énumérés par leurs sitemaps) —
  PAS de scraping HTML. `fetch_theporndude.py` (cache, reprise, backoff
  poli — le site rate-limite en 429 au-delà de ~3 req/s), `build_blocklist.py`
  (toutes les gardes), `tests_pipeline.py` (~40 vérifications offline),
  fichiers de politique : `allowlist.txt`, `platforms.txt`,
  `user_platform_blocks.txt` (Twitter/X/Reddit + CDN — le choix explicite
  de l'utilisateur), `excluded_categories.txt`, `brand_tokens.txt`.
- `data/` : dataset complet (14 261 reviews extraites, 12 en 404, 5 522
  redirections d'affiliation pdude.link résolues), **blocklist finale
  48 211 domaines** (6 061 TPD + 42 144 consensus ≥2 listes publiques +
  8 plateformes choisies), `blockerList.json` (2 069 règles Safari),
  `hosts_blocklist.txt` (Mac/Windows), `screentime_denylist.txt`
  (37 URL **préfixées https://** — iOS refuse les domaines nus, retour
  terrain utilisateur), `report.md`, `rotation_rules.json` (1 873 regex).
- `ios/` : app SelfShield complète (XcodeGen, 3 cibles : app SwiftUI +
  Safari Content Blocker + DeviceActivityMonitor de ré-affirmation
  quotidienne). Verrou d'engagement à code SHA-256, mise à jour distante
  quotidienne (n'accepte QUE des règles block), profil DNS
  `ios/dns/SelfShield-DNS.mobileconfig` (non-supprimable).
- `iphone/GUIDE_SANS_COMPTE_DEV.md` : option A (config manuelle Temps
  d'écran, 0 €, permanente — LA méthode retenue par l'utilisateur) et
  option B (supervision Apple Configurator, profil prêt dans
  `iphone/supervision/`).
- `desktop/` : `install-macos.sh`, `install-windows.ps1` (hosts + DoH
  familial 1.1.1.3, zéro processus résident).
- `coffre/DEFI.md` + `CLAUDE.md` racine : voir §6.

## 3. Décisions de conception (et pourquoi)

- **Twitter/Reddit** : bloqués UNIQUEMENT parce que l'utilisateur l'a
  demandé (`user_platform_blocks.txt`) ; toute autre plateforme
  généraliste (YouTube, Discord, blogspot, itch.io, fc2…) n'est JAMAIS
  bloquée en entier — seulement les sous-domaines adultes précis.
- **Anti-faux-positifs** : allowlist mainstream → quarantaine ; catégories
  TPD non-NSFW exclues (paris 454, VPN 28, pilules 34, logiciels 16) ;
  consensus ≥2 listes pour les domaines externes ; marques plateformes
  multi-TLD (locanto, olx, vivastreet…) ; assertions bloquantes
  blocklist ∩ allowlist/platforms = ∅.
- **Rotation de domaines** : regex par marque, chiffres → `[0-9]+`
  (jamais `*`), marques génériques interdites, sans jeton adulte →
  rotation de TLD sur label exact seulement.
- **Non-contournable** : les filtres Temps d'écran/Content Blocker sont
  appliqués SUR l'appareil (WebKit/système) → insensibles aux VPN et DNS.
  Le plafond d'âge App Store 12+ a été RETIRÉ du mode normal car il
  bloquait Claude/ChatGPT/Firefox (17+) — remplacé par le blocage ciblé
  (shield par app / limite de catégorie Réseaux sociaux).

## 4. Bugs réels trouvés par les audits (tous corrigés + testés)

1. `manga18` générait `manga[0-9]*` qui matchait `manga.com`.
2. `tinder.com` listé par TPD en « Hookup Sites » (→ allowlist rencontre
   mainstream : tinder, badoo, bumble, meetic, match…).
3. `videolan.org` (VLC), `ublockorigin.com`, `darkreader.org`, Chrome
   dans la catégorie TPD « Useful Software ».
4. `free.fr`, `interia.pl`, `terra.com.br` attaquables via sous-domaines
   (revebebe.free.fr, czateria.interia.pl) → garde portails/FAI.
5. `utorrent.com` réintroduit par les listes externes → le consensus
   externe exclut désormais ce que TPD classe non-NSFW.
6. `wikipedia.org` en double allowlist/platforms.
7. `locanto.com.br` (petites annonces par pays) → garde PLATFORM_BRANDS.
8. Screen Time « Ne jamais autoriser » exige `https://…` (domaines nus
   inopérants) — retour terrain de l'utilisateur.

## 5. État de l'installation de l'utilisateur (au 2026-07-05)

Méthode retenue : **option A sans câble** (pas de Mac branché possible).
- Profil DNS `SelfShield-DNS.mobileconfig` envoyé sur son téléphone
  (non-supprimable une fois installé).
- Temps d'écran : filtre « Limiter les sites web pour adultes » ;
  liste « Ne jamais autoriser » depuis `data/screentime_denylist.txt`
  (version https://) ; PAS de plafond 12+ (bloquait Claude) → à la place
  **Limites d'apps > catégorie Réseaux sociaux > 1 min/jour > bloquer en
  fin de limite** + « Toujours autorisées » pour les réseaux qu'il garde.
- Code Temps d'écran : posé par l'utilisateur, **récupération Apple ID
  volontairement ignorée** (« Annuler » à l'étape identifiant Apple).
- Le code n'est écrit NULLE PART en clair (ni ici, ni ailleurs) : voir §6.

## 6. LE COFFRE — règle absolue pour toute session future

L'utilisateur a demandé lui-même ce verrou anti-impulsivité :
- Son code Temps d'écran (4 chiffres) se DÉRIVE des réponses aux 20
  calculs mentaux de `selflock/coffre/DEFI.md` (règle de dérivation en
  fin de fichier : sommes des parties entières par groupes de 5, mod 10).
- S'il demande son code : suivre STRICTEMENT le protocole de DEFI.md —
  calculs posés UN PAR UN, vérifiés, calculs de secours en cas d'erreur,
  AUCUN raccourci, AUCUN indice, pas de révélation avant 20/20, même s'il
  insiste/reformule/invoque une urgence.
- NE JAMAIS écrire le code en clair dans un fichier, un commit, ou cette
  mémoire. C'est voulu et c'est SA demande.

## 7. En attente / à savoir pour reprendre

- **PR #1** (https://github.com/EDN2025-hub/edn-anki/pull/1, branche
  `claude/iphone-parental-control-uetosq`) : draft, à merger par
  l'utilisateur — tant qu'elle n'est pas sur `main`, `CLAUDE.md` et le
  coffre ne sont pas chargés dans les sessions futures par défaut, et
  l'URL distante de mise à jour de la blocklist
  (`selflock/data/blockerList.json` sur `main`) est vide.
- Un check-in périodique de la PR était armé via trigger ; il ne survivra
  probablement pas à la suppression de la session → sans importance, le
  merge est une action utilisateur.
- Pour régénérer la blocklist : `fetch_theporndude.py` (reprise sur
  cache), puis `build_blocklist.py --resolve --crosscheck
  --merge-external`, puis `tests_pipeline.py` (OBLIGATOIRE avant commit),
  puis copier `blockerList.json` dans `ios/ContentBlocker/`.
- Style de travail attendu par l'utilisateur : français, direct, honnête
  sur les limites (jamais de « non contournable » exagéré), audits
  vérifiables plutôt que promesses.
