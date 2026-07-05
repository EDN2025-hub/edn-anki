#!/usr/bin/env python3
"""
Extraction STRUCTURÉE de la base de données ThePornDude.

Principe (pas de scraping "à l'aveugle") :
  1. On lit les sitemaps officiels (sitemap.link.*.xml) pour énumérer les
     reviews publiées par ThePornDude — c'est leur propre index.
  2. Pour chaque review, on interroge l'endpoint JSON officiel du site
     (https://theporndude.com/json/<id>/<slug>) que leurs propres pages
     utilisent. Ce JSON contient des champs structurés :
       - data_category_link : l'URL OFFICIELLE du site listé
       - data_category      : la catégorie ThePornDude
       - title_slug         : le domaine affiché
       - is_deadsite        : site mort ou non
     Aucune heuristique de parsing HTML, aucun crawl de liens : uniquement
     des données que ThePornDude publie lui-même de façon structurée.
  3. Cache disque avec reprise. Seuls les 404 définitifs sont mémorisés
     comme erreurs ; les échecs transitoires (429/403/5xx/réseau) ne sont
     JAMAIS mis en cache et sont retentés au prochain passage.
  4. Politesse : faible concurrence, délai aléatoire entre requêtes,
     backoff exponentiel long sur 429 (rate limit Cloudflare).

Usage :
  python3 fetch_theporndude.py --out data/ --cache .cache/tpd [--limit N]
  (relancer jusqu'à convergence ; le cache évite tout re-téléchargement)
"""

import argparse
import json
import os
import random
import re
import sys
import threading
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE = "https://theporndude.com"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

SITEMAP_INDEX = f"{BASE}/sitemap.xml"
REVIEW_URL_RE = re.compile(
    r"https://theporndude\.com/(?:([a-z]{2}(?:-[a-z]{2})?)/)?(\d+)/([^/<]+)$"
)

# Frein global partagé : quand le serveur renvoie 429, tous les threads
# ralentissent ensemble.
_cooldown_until = 0.0
_cooldown_lock = threading.Lock()


def _respect_cooldown() -> None:
    while True:
        with _cooldown_lock:
            wait = _cooldown_until - time.monotonic()
        if wait <= 0:
            return
        time.sleep(min(wait, 5))


def _trigger_cooldown(seconds: float) -> None:
    global _cooldown_until
    with _cooldown_lock:
        _cooldown_until = max(_cooldown_until, time.monotonic() + seconds)


def http_get(url: str, timeout: int = 30, retries: int = 6) -> tuple[int, bytes | None]:
    """GET poli. Renvoie (status, body). status=404 est définitif ;
    status=0 signifie échec transitoire (à retenter plus tard)."""
    backoff = 4.0
    for _ in range(retries):
        _respect_cooldown()
        time.sleep(random.uniform(0.15, 0.45))  # politesse
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA,
                                                       "Accept": "*/*"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return 404, None
            if e.code in (429, 403, 503):
                retry_after = e.headers.get("Retry-After")
                pause = float(retry_after) if (retry_after or "").isdigit() \
                    else backoff
                _trigger_cooldown(pause + random.uniform(0, 2))
                backoff = min(backoff * 2, 90)
                continue
            time.sleep(backoff)
            backoff = min(backoff * 2, 90)
        except Exception:
            time.sleep(backoff)
            backoff = min(backoff * 2, 90)
    return 0, None


def enumerate_reviews(cache_dir: str) -> dict[int, dict]:
    """Énumère id -> {slug, lang} depuis les sitemaps officiels.
    Slug anglais préféré quand il existe."""
    status, idx = http_get(SITEMAP_INDEX)
    if not idx:
        sys.exit("Impossible de lire le sitemap index")
    link_maps = re.findall(
        r"<loc>(https://theporndude\.com/sitemap\.link\.\d+\.xml)</loc>",
        idx.decode("utf-8", "replace"))
    entries: dict[int, dict] = {}
    for sm_url in link_maps:
        status, body = http_get(sm_url)
        if not body:
            print(f"  ! sitemap illisible: {sm_url}", file=sys.stderr)
            continue
        for loc in re.findall(r"<loc>([^<]+)</loc>", body.decode("utf-8", "replace")):
            m = REVIEW_URL_RE.match(loc)
            if not m:
                continue
            lang, sid, slug = m.group(1) or "en", int(m.group(2)), m.group(3)
            if sid not in entries or (lang == "en" and entries[sid]["lang"] != "en"):
                entries[sid] = {"slug": slug, "lang": lang}
    return entries


def fetch_one(sid: int, slug: str, lang: str, cache_dir: str) -> dict | None:
    """Récupère le JSON structuré d'une review (cache disque).
    Renvoie None si échec transitoire (sera retenté à la prochaine passe)."""
    cache_path = os.path.join(cache_dir, f"{sid}.json")
    if os.path.exists(cache_path):
        try:
            with open(cache_path, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass

    candidates = [f"{BASE}/json/{sid}/{slug}"]
    if lang != "en":
        candidates.append(f"{BASE}/{lang}/json/{sid}/{slug}")

    record: dict | None = None
    for url in candidates:
        status, body = http_get(url)
        if status == 0:
            return None  # transitoire : ne PAS mettre en cache
        if status == 404:
            continue
        try:
            data = json.loads(body)
        except Exception:
            return None  # page de challenge / HTML -> transitoire
        record = {
            "id": sid,
            "slug": slug,
            "lang": lang,
            "official_url": data.get("data_category_link") or "",
            "display": data.get("title_slug") or "",
            "category": data.get("data_category") or "",
            "dead": bool(data.get("is_deadsite")),
        }
        break
    if record is None:
        record = {"id": sid, "slug": slug, "lang": lang, "error": "notfound"}

    tmp = cache_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False)
    os.replace(tmp, cache_path)
    return record


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data")
    ap.add_argument("--cache", default=".cache/tpd")
    ap.add_argument("--limit", type=int, default=0, help="limiter (debug)")
    ap.add_argument("--concurrency", type=int, default=3)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    os.makedirs(args.cache, exist_ok=True)

    ids_path = os.path.join(args.cache, "review_index.json")
    if os.path.exists(ids_path):
        entries = {int(k): v for k, v in json.load(open(ids_path)).items()}
        print(f"{len(entries)} reviews (index en cache)")
    else:
        print("Énumération des reviews via les sitemaps officiels…")
        entries = enumerate_reviews(args.cache)
        json.dump({str(k): v for k, v in entries.items()}, open(ids_path, "w"))
        print(f"{len(entries)} reviews uniques")

    items = sorted(entries.items())
    if args.limit:
        items = items[: args.limit]

    results: list[dict] = []
    pending = 0
    done = 0
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futs = {pool.submit(fetch_one, sid, meta["slug"], meta["lang"],
                            args.cache): sid for sid, meta in items}
        for fut in as_completed(futs):
            rec = fut.result()
            done += 1
            if rec is None:
                pending += 1
            else:
                results.append(rec)
            if done % 250 == 0:
                ok = sum(1 for r in results if "error" not in r)
                print(f"  {done}/{len(items)} traités "
                      f"({ok} ok, {pending} à retenter)", flush=True)

    results.sort(key=lambda r: r["id"])
    ok = [r for r in results if "error" not in r and r.get("official_url")]
    notfound = [r for r in results if r.get("error") == "notfound"]
    out_path = os.path.join(args.out, "theporndude_sites.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"source": "theporndude.com (endpoints JSON officiels)",
                   "count": len(ok),
                   "sites": ok}, f, ensure_ascii=False, indent=1)
    print(f"\n{len(ok)} sites avec URL officielle -> {out_path}")
    print(f"{len(notfound)} reviews 404 (retirées), "
          f"{pending} transitoires à retenter (relancer le script)")


if __name__ == "__main__":
    main()
