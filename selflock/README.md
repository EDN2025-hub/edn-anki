# SelfShield — bloqueur de contenu pornographique/NSFW pour iPhone

Application iOS de type **SelfLock** : elle bloque l'accès aux sites
pornographiques et NSFW (y compris **Twitter/X** et **Reddit**, par choix
explicite) sur tout l'appareil, se **verrouille** pour une durée choisie, et
utilise la **base de données de ThePornDude** (l'annuaire de sites pour
adultes le plus complet du web) comme source de vérité — extraite de façon
structurée, jamais par scraping aveugle.

```
selflock/
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
    --out ../data --resolve --crosscheck
```

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
| **Safari Content Blocker** | Safari | la base ThePornDude complète (~milliers de domaines) + regex de rotation, limite Safari 150 000 règles |
| **Shield d'applications** (`FamilyControls`) | apps natives | blocage des apps choisies : Twitter, Reddit, navigateurs tiers (Chrome/Firefox n'appliquent pas le Content Blocker) |
| **`denyAppRemoval`** | système | impossible de **supprimer** SelfShield (ou toute app) tant que la protection est active |
| **Verrou d'engagement** | app | durée de 24 h à 1 an ; code d'urgence aléatoire affiché une seule fois, stocké uniquement en SHA-256, à confier à un tiers |
| **Profil DNS filtrant** (optionnel, `ios/dns/`) | tout l'appareil, toutes les apps | DoH Cloudflare for Families (1.1.1.3), profil marqué non-supprimable |
| **Ré-application au premier plan** | app | les réglages sont ré-appliqués à chaque activation de l'app |

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

## 5. Compilation (sur Mac)

```bash
brew install xcodegen
cd selflock/ios
xcodegen generate
open SelfShield.xcodeproj
```

1. Dans *Signing & Capabilities* : sélectionner votre équipe (les cibles
   ont `DEVELOPMENT_TEAM` vide dans `project.yml`).
2. Remplacer le préfixe `com.example.selfshield` (project.yml,
   `Constants.swift`, `ContentBlockerRequestHandler.swift`) par votre
   bundle id, et `group.com.example.selfshield` par votre App Group.
3. Capability **Family Controls** requise sur l'App ID principal
   (développement : cocher la capability ; distribution : demande
   d'entitlement auprès d'Apple).
4. Copier `../data/blockerList.json` dans `ContentBlocker/` (fait par le
   pipeline ; un fichier de base est fourni).
5. Compiler sur un **appareil réel** (les API FamilyControls ne
   fonctionnent pas dans le simulateur).
6. Sur l'iPhone : suivre l'onboarding (autorisation Temps d'écran,
   activation de l'extension dans Réglages > Apps > Safari > Extensions,
   sélection des apps à bloquer), puis poser le verrou.
7. Optionnel mais recommandé : installer `ios/dns/SelfShield-DNS.mobileconfig`
   et faire poser un code Temps d'écran par une personne de confiance.
