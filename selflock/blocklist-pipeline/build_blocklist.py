#!/usr/bin/env python3
"""
Construction de la blocklist finale à partir du dataset ThePornDude,
avec garde-fous anti-faux-positifs.

Étapes :
  1. Normalisation : URL officielle -> hôte -> domaine enregistrable (eTLD+1,
     avec table des suffixes à deux niveaux les plus courants).
  2. Résolution des redirecteurs d'affiliation de ThePornDude (pdude.link,
     tpd.deals) vers le domaine de destination FINAL (option --resolve,
     nécessite le réseau ; résultats mis en cache).
  3. Classification avec gardes :
       - domaine ∈ platforms.txt  -> jamais auto-bloqué ; bloqué seulement
         s'il figure dans user_platform_blocks.txt (choix utilisateur :
         Twitter, Reddit…). Contenu hébergé sur plateforme (sous-domaine
         type xyz.blogspot.com) -> blocage du sous-domaine exact uniquement.
       - domaine ∈ allowlist.txt  -> QUARANTAINE (jamais bloqué), revue
         manuelle dans quarantine_review.txt.
       - review "dead" pointant vers theporndude.com -> ignorée.
       - domaine mort mais réel -> conservé (un ancien domaine porno
         redirige presque toujours vers du porno), listé aussi à part.
  4. Règles de rotation de domaines : pour les marques qui changent
     régulièrement de nom de domaine, génération d'une regex qui matche le
     label EXACT de la marque + suffixe numérique optionnel + n'importe quel
     TLD (ex: ^https?://([^/:]*\\.)?xmoviesforyou[0-9]*\\.[a-z]{2,}).
     Garde-fous : marque >= 5 caractères, ET (contient un jeton adulte
     explicite OU observée avec >= 2 variantes de TLD/numéro dans la base),
     et absente d'une liste de mots génériques.
  5. Rapport de confiance : croisement facultatif avec des blocklists
     publiques indépendantes (--crosscheck) pour signaler les domaines que
     seul ThePornDude connaît (information, pas exclusion).

Sorties (dans --out) :
  blocklist_domains.txt   liste finale (1 domaine/ligne, commentaires = catégorie)
  platform_blocks.txt     plateformes bloquées par choix utilisateur
  platform_subdomains.txt sous-domaines de plateformes à bloquer individuellement
  quarantine_review.txt   entrées écartées pour revue manuelle
  dead_domains.txt        domaines de sites morts (inclus, tagués)
  rotation_rules.json     regex de rotation (marque -> règle)
  blockerList.json        règles Safari Content Blocker prêtes à l'emploi
  report.md               statistiques et vérifications
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

# Redirecteurs d'affiliation appartenant à ThePornDude
TPD_REDIRECTORS = {"pdude.link", "tpd.deals", "porndude.link"}
TPD_OWN = {"theporndude.com", "porndude.link", "pdude.link", "tpd.deals",
           "porndudecasting.com", "porndudedeutsch.com", "porndudeshop.com"}

# Suffixes publics à deux niveaux les plus courants (sous-ensemble PSL)
TWO_LEVEL_SUFFIXES = {
    "co.uk", "org.uk", "me.uk", "ac.uk", "gov.uk",
    "com.au", "net.au", "org.au", "com.br", "net.br", "org.br",
    "co.jp", "ne.jp", "or.jp", "co.kr", "or.kr", "com.mx", "com.ar",
    "com.co", "com.pe", "com.ve", "co.in", "net.in", "org.in", "co.za",
    "com.tr", "com.tw", "com.hk", "com.sg", "com.my", "com.ph", "com.vn",
    "co.th", "in.th", "com.cn", "net.cn", "org.cn", "com.ua", "com.pl",
    "com.ru", "com.de", "co.nz", "org.nz", "com.es", "com.pt", "com.gr",
    "co.il", "org.il", "com.eg", "com.ng", "co.ke", "com.sa", "com.pk",
    "com.bd", "eu.org",
}

GENERIC_BRAND_WORDS = {
    "video", "videos", "movie", "movies", "photo", "photos", "image",
    "images", "media", "stream", "streaming", "online", "world", "planet",
    "house", "store", "games", "gaming", "forum", "forums", "board",
    "chat", "live", "webcam", "camera", "model", "models", "girls",
    "boys", "teens", "asian", "latina", "ebony", "amateur", "premium",
    "gratis", "free", "best", "top", "new", "hot",
}


def load_list(path: str) -> set[str]:
    out = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip().lower()
            if line and not line.startswith("#"):
                out.add(line)
    return out


def host_of(url: str) -> str:
    try:
        h = urllib.parse.urlsplit(url).hostname or ""
    except Exception:
        return ""
    h = h.lower().strip(".")
    return h[4:] if h.startswith("www.") else h


def registrable(host: str) -> str:
    """eTLD+1 approché : gère les suffixes à deux niveaux courants."""
    parts = host.split(".")
    if len(parts) <= 2:
        return host
    if ".".join(parts[-2:]) in TWO_LEVEL_SUFFIXES:
        return ".".join(parts[-3:])
    return ".".join(parts[-2:])


def resolve_final_host(url: str, cache: dict, max_hops: int = 8) -> str:
    """Suit la chaîne de redirections et renvoie l'hôte FINAL."""
    if url in cache:
        return cache[url]
    cur = url
    final_host = host_of(url)
    try:
        for _ in range(max_hops):
            req = urllib.request.Request(cur, headers={"User-Agent": UA},
                                         method="GET")
            # pas de suivi automatique : on veut chaque hop
            opener = urllib.request.build_opener(NoRedirect())
            try:
                resp = opener.open(req, timeout=20)
                final_host = host_of(cur)
                resp.close()
                break
            except urllib.error.HTTPError as e:
                if e.code in (301, 302, 303, 307, 308):
                    loc = e.headers.get("Location")
                    if not loc:
                        break
                    cur = urllib.parse.urljoin(cur, loc)
                    final_host = host_of(cur)
                    continue
                final_host = host_of(cur)
                break
    except Exception:
        pass
    cache[url] = final_host
    return final_host


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def build_rotation_rules(domains_with_meta: dict[str, dict],
                         adult_tokens: set[str]) -> dict[str, str]:
    """Regex de rotation pour marques instables ou explicitement adultes."""
    brands: dict[str, set[str]] = {}
    for dom in domains_with_meta:
        label = dom.split(".")[0]
        brand = re.sub(r"[0-9]+", "", label)
        if len(brand) < 5:
            continue
        brands.setdefault(brand, set()).add(dom)

    rules: dict[str, str] = {}
    for brand, doms in brands.items():
        if brand in GENERIC_BRAND_WORDS:
            continue
        has_token = any(t in brand for t in adult_tokens)
        multi_variant = len(doms) >= 2
        if not (has_token or multi_variant):
            continue
        esc = re.escape(brand)
        rules[brand] = (
            rf"^https?://([^/:]*\.)?{esc}[0-9]*\.[a-z]{{2,24}}(:[0-9]+)?([/?]|$)"
        )
    return rules


def safari_rules(domains: list[str], subdomain_hosts: list[str],
                 rotation: dict[str, str]) -> list[dict]:
    """Règles Safari Content Blocker.
    - domaines entiers : if-domain (rapide, exact, *.domaine inclus)
    - sous-domaines de plateformes : if-domain sur l'hôte exact
    - rotation : url-filter regex
    """
    rules: list[dict] = []
    chunk = 250
    for i in range(0, len(domains), chunk):
        batch = domains[i:i + chunk]
        rules.append({
            "trigger": {"url-filter": ".*",
                        "if-domain": [f"*{d}" for d in batch]},
            "action": {"type": "block"},
        })
    for i in range(0, len(subdomain_hosts), chunk):
        batch = subdomain_hosts[i:i + chunk]
        rules.append({
            "trigger": {"url-filter": ".*",
                        "if-domain": [f"*{h}" for h in batch]},
            "action": {"type": "block"},
        })
    for brand in sorted(rotation):
        rules.append({
            "trigger": {"url-filter": rotation[brand],
                        "url-filter-is-case-sensitive": False},
            "action": {"type": "block"},
        })
    return rules


def crosscheck(domains: set[str]) -> dict[str, int]:
    """Croise avec des blocklists publiques indépendantes (confiance)."""
    sources = [
        "https://raw.githubusercontent.com/blocklistproject/Lists/master/porn.txt",
        "https://raw.githubusercontent.com/Sinfonietta/hostfiles/master/pornography-hosts",
    ]
    counts = {d: 0 for d in domains}
    for src in sources:
        try:
            req = urllib.request.Request(src, headers={"User-Agent": UA})
            body = urllib.request.urlopen(req, timeout=60).read()
        except Exception as e:
            print(f"  ! crosscheck indisponible: {src} ({e})", file=sys.stderr)
            continue
        seen = set()
        for line in body.decode("utf-8", "replace").splitlines():
            line = line.strip().lower()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            host = parts[-1] if parts else ""
            host = host[4:] if host.startswith("www.") else host
            seen.add(registrable(host))
        for d in domains:
            if d in seen:
                counts[d] += 1
    return counts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", default="data/theporndude_sites.json")
    ap.add_argument("--out", default="data")
    ap.add_argument("--resolve", action="store_true",
                    help="résoudre les redirecteurs pdude.link (réseau)")
    ap.add_argument("--resolve-cache", default=".cache/redirects.json")
    ap.add_argument("--crosscheck", action="store_true",
                    help="croiser avec des blocklists publiques (réseau)")
    args = ap.parse_args()

    dataset = json.load(open(args.dataset, encoding="utf-8"))
    sites = dataset["sites"]
    allow = load_list(os.path.join(HERE, "allowlist.txt"))
    platforms = load_list(os.path.join(HERE, "platforms.txt"))
    user_platform_blocks = load_list(os.path.join(HERE, "user_platform_blocks.txt"))
    adult_tokens = load_list(os.path.join(HERE, "brand_tokens.txt"))

    redirect_cache: dict = {}
    if os.path.exists(args.resolve_cache):
        redirect_cache = json.load(open(args.resolve_cache))

    blocked: dict[str, dict] = {}          # registrable -> meta
    platform_subdomains: dict[str, dict] = {}
    quarantine: list[dict] = []
    dead: set[str] = set()
    platform_hits: dict[str, int] = {}
    unresolved_redirectors = 0

    for s in sites:
        url = s["official_url"]
        host = host_of(url)
        if not host:
            continue
        reg = registrable(host)

        # Redirecteur d'affiliation ThePornDude -> résoudre la destination
        if reg in TPD_REDIRECTORS:
            if args.resolve:
                final = resolve_final_host(url, redirect_cache)
                if final and registrable(final) not in TPD_REDIRECTORS:
                    host = final
                    reg = registrable(final)
                else:
                    unresolved_redirectors += 1
                    continue
            else:
                unresolved_redirectors += 1
                continue

        # Pages internes ThePornDude (sites morts, hall of fame…)
        if reg in TPD_OWN:
            continue

        meta = {"category": s.get("category", ""), "id": s["id"],
                "dead": s.get("dead", False)}

        if reg in allow:
            quarantine.append({"domain": reg, "host": host, **meta,
                               "reason": "allowlist"})
            continue

        if reg in platforms:
            platform_hits[reg] = platform_hits.get(reg, 0) + 1
            # contenu hébergé (xyz.blogspot.com) -> sous-domaine exact
            if host != reg and host.count(".") > reg.count("."):
                platform_subdomains[host] = meta
            continue

        if meta["dead"]:
            dead.add(reg)
        blocked.setdefault(reg, meta)

    # sauvegarde cache redirections
    os.makedirs(os.path.dirname(args.resolve_cache) or ".", exist_ok=True)
    json.dump(redirect_cache, open(args.resolve_cache, "w"))

    # garde finale : jamais d'intersection avec allowlist/platforms
    assert not (set(blocked) & allow), "faux positif: allowlist dans blocklist"
    assert not (set(blocked) & platforms), "plateforme dans blocklist"

    rotation = build_rotation_rules(blocked, adult_tokens)

    platform_blocked = sorted(user_platform_blocks)
    all_domains = sorted(set(blocked) | set(platform_blocked) | {"theporndude.com"})

    xcheck = crosscheck(set(blocked)) if args.crosscheck else {}

    os.makedirs(args.out, exist_ok=True)

    def write_lines(name: str, lines: list[str]) -> None:
        with open(os.path.join(args.out, name), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

    write_lines("blocklist_domains.txt",
                [f"{d}  # {blocked[d]['category']}" if d in blocked else d
                 for d in all_domains])
    write_lines("platform_blocks.txt", platform_blocked)
    write_lines("platform_subdomains.txt", sorted(platform_subdomains))
    write_lines("dead_domains.txt", sorted(dead))
    write_lines("quarantine_review.txt",
                [json.dumps(q, ensure_ascii=False) for q in quarantine] or
                ["# vide : aucune entrée suspecte"])
    json.dump(rotation, open(os.path.join(args.out, "rotation_rules.json"), "w"),
              indent=1)

    rules = safari_rules(all_domains, sorted(platform_subdomains), rotation)
    json.dump(rules, open(os.path.join(args.out, "blockerList.json"), "w"),
              separators=(",", ":"))

    only_tpd = sorted(d for d, c in xcheck.items() if c == 0)
    with open(os.path.join(args.out, "report.md"), "w", encoding="utf-8") as f:
        f.write("# Rapport de construction de la blocklist\n\n")
        f.write(f"- Sites dans le dataset ThePornDude : **{len(sites)}**\n")
        f.write(f"- Domaines bloqués (sites) : **{len(blocked)}**\n")
        f.write(f"- Plateformes bloquées (choix utilisateur) : "
                f"**{len(platform_blocked)}** ({', '.join(platform_blocked)})\n")
        f.write(f"- Sous-domaines de plateformes bloqués : "
                f"**{len(platform_subdomains)}**\n")
        f.write(f"- Entrées en quarantaine (allowlist) : **{len(quarantine)}**\n")
        f.write(f"- Domaines de sites morts (inclus, tagués) : **{len(dead)}**\n")
        f.write(f"- Regex de rotation de domaine : **{len(rotation)}**\n")
        f.write(f"- Redirecteurs d'affiliation non résolus (ignorés) : "
                f"**{unresolved_redirectors}**"
                f"{'' if args.resolve else ' (relancer avec --resolve)'}\n")
        f.write(f"- Règles Safari générées : **{len(rules)}**\n\n")
        f.write("## Contenus de plateformes détectés (non bloqués "
                "automatiquement)\n\n")
        for p, n in sorted(platform_hits.items(), key=lambda x: -x[1]):
            mark = "BLOQUÉE (choix utilisateur)" if p in user_platform_blocks \
                else "non bloquée (plateforme généraliste)"
            f.write(f"- {p} : {n} contenus référencés — {mark}\n")
        if args.crosscheck:
            f.write(f"\n## Croisement avec des listes publiques\n\n")
            f.write(f"Domaines confirmés par au moins une liste externe : "
                    f"**{sum(1 for c in xcheck.values() if c > 0)}** / {len(xcheck)}\n\n")
            f.write(f"Domaines connus uniquement de ThePornDude "
                    f"({len(only_tpd)}) — source humaine curée, inclus :\n\n")
            for d in only_tpd[:400]:
                f.write(f"- {d} ({blocked[d]['category']})\n")

    print(f"{len(blocked)} domaines bloqués, {len(rotation)} regex de rotation, "
          f"{len(quarantine)} en quarantaine -> {args.out}/")


if __name__ == "__main__":
    main()
