#!/usr/bin/env python3
"""
Suite de tests OFFLINE du pipeline (aucun réseau requis).

Vérifie les invariants anti-faux-positifs et anti-régression :
  python3 tests_pipeline.py
Échoue avec un code de sortie != 0 à la moindre violation.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_blocklist import (host_of, registrable, build_rotation_rules,
                             safari_rules, external_consensus, load_list,
                             GENERIC_BRAND_WORDS)

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = []


def check(name: str, cond: bool, detail: str = "") -> None:
    if cond:
        print(f"  ok  {name}")
    else:
        print(f"  FAIL {name} {detail}")
        FAILURES.append(name)


# ── Normalisation des hôtes ──────────────────────────────────────────────
check("host_of strip www/port/chemin",
      host_of("https://www.Example.COM:8443/a?b=c") == "example.com")
check("host_of URL invalide", host_of("pas une url") == "")
check("registrable simple", registrable("a.b.tnaflix.com") == "tnaflix.com")
check("registrable suffixe 2 niveaux", registrable("x.shop.co.uk") == "shop.co.uk")
check("registrable apex", registrable("beeg.com") == "beeg.com")

# ── Regex de rotation : jamais de faux positif mainstream ────────────────
fake_meta = {"category": "t", "id": 1, "dead": False}
adult_tokens = load_list(os.path.join(HERE, "brand_tokens.txt"))
rot = build_rotation_rules(
    {d: fake_meta for d in [
        "pornhd.com", "pornhd3x.tv", "xmoviesforyou.com", "cumlouder.com",
        "sexvid.xxx", "beeg.com", "teens.org", "video4.com", "hqporner.com",
    ]}, adult_tokens)

check("marque courte exclue (beeg: 4 lettres)", "beeg" not in rot)
check("mot générique exclu (teens)", "teens" not in rot)
check("mot générique exclu (video)", "video" not in rot)
check("marque adulte incluse (famille pornhd)",
      any("pornhd" in k for k in rot))
check("marque adulte incluse (xmoviesforyou)", "xmoviesforyou" in rot)

MAINSTREAM_CORPUS = [
    # pièges lexicaux réels : contiennent cum/sex/dick/anal/strip/porn…
    "https://documentcloud.org/", "https://www.cummins.com/",
    "https://circumstances.net/", "https://dickssportinggoods.com/",
    "https://www.sussex.ac.uk/", "https://essex.ac.uk/",
    "https://middlesex.edu/", "https://www.analytics.google.com/",
    "https://canalplus.com/", "https://www.stripe.com/",
    "https://striped-patterns.design/", "https://sexagesimal-math.org/",
    "https://cockpit-project.org/", "https://hancock.edu/",
    "https://scunthorpe.gov.uk/", "https://penistone.co.uk/",
    "https://fapiao-service.cn/", "https://www.wankel-engine.de/",
    # géants du web
    "https://google.com/", "https://youtube.com/", "https://wikipedia.org/",
    "https://amazon.fr/", "https://leboncoin.fr/", "https://doctolib.fr/",
]
fp = [(u, b) for u in MAINSTREAM_CORPUS
      for b, rx in rot.items() if re.search(rx, u, re.I)]
check("regex rotation: zéro faux positif sur corpus piège", not fp, str(fp))

# les variantes de la marque DOIVENT matcher
check("rotation matche pornhd3x.tv",
      any(re.search(rx, "https://pornhd3x.tv/", re.I) for rx in rot.values()))
check("rotation matche xmoviesforyou2.net",
      any(re.search(rx, "https://www.xmoviesforyou2.net/x", re.I) for rx in rot.values()))
check("rotation matche nouveau TLD (pornhd.si)",
      any(re.search(rx, "https://pornhd.si/", re.I) for rx in rot.values()))

# ── Consensus externe : gardes infranchissables ──────────────────────────
allow = {"netflix.com"}
platforms = {"reddit.com"}
ext = [
    {"badporn.com", "www.badporn.com", "netflix.com", "reddit.com", "solo.com"},
    {"badporn.com", "netflix.com", "reddit.com"},
    {"other.net"},
]
cons = external_consensus(ext, allow, platforms)
check("consensus: >=2 listes requis", "badporn.com" in cons and "solo.com" not in cons
      and "other.net" not in cons)
check("consensus: allowlist exclue", "netflix.com" not in cons)
check("consensus: plateformes exclues", "reddit.com" not in cons)

# ── Règles Safari : validité et sûreté ───────────────────────────────────
rules = safari_rules(["a.com", "b.net"], ["x.blogspot.com"], rot)
check("règles Safari: JSON sérialisable", bool(json.dumps(rules)))
check("règles Safari: uniquement des actions block",
      all(r["action"]["type"] == "block" for r in rules))
check("règles Safari: < 150000 (limite Safari)", len(rules) < 150000)
check("règles Safari: if-domain préfixé * (inclut sous-domaines)",
      all(d.startswith("*") for r in rules
          for d in r["trigger"].get("if-domain", [])))

# ── Cohérence des fichiers de politique ──────────────────────────────────
allow_f = load_list(os.path.join(HERE, "allowlist.txt"))
plat_f = load_list(os.path.join(HERE, "platforms.txt"))
user_f = load_list(os.path.join(HERE, "user_platform_blocks.txt"))
check("allowlist et platforms disjoints", not (allow_f & plat_f),
      str(allow_f & plat_f))
check("blocs utilisateur ⊆ plateformes (politique cohérente)",
      user_f <= plat_f, str(user_f - plat_f))
check("twitter et reddit bien dans les blocs utilisateur",
      {"twitter.com", "x.com", "reddit.com"} <= user_f)
check("aucun mot générique dans les jetons adultes",
      not (adult_tokens & GENERIC_BRAND_WORDS))

# ── Données finales si présentes (exécuté après build) ───────────────────
data_dir = os.path.join(os.path.dirname(HERE), "data")
bl_path = os.path.join(data_dir, "blocklist_domains.txt")
if os.path.exists(bl_path):
    blocked = {l.split("#")[0].strip() for l in open(bl_path, encoding="utf-8")}
    blocked.discard("")
    check("données finales: allowlist ∩ blocklist = ∅", not (blocked & allow_f),
          str((blocked & allow_f)))
    inter = blocked & plat_f
    check("données finales: plateformes ∩ blocklist = blocs utilisateur seuls",
          inter <= user_f, str(inter - user_f))
    bj = os.path.join(data_dir, "blockerList.json")
    if os.path.exists(bj):
        rules = json.load(open(bj))
        check("blockerList.json: valide + block uniquement",
              all(r["action"]["type"] == "block" for r in rules))
        check("blockerList.json: < 150000 règles", len(rules) < 150000)

print()
if FAILURES:
    print(f"{len(FAILURES)} ÉCHEC(S): {FAILURES}")
    sys.exit(1)
print("Tous les tests passent.")
