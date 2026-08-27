"""
PfamIE Data Forge, stage 2/3: the two things Pfam's flatfiles do not carry.

  counters  family size, taxon count, structure count  (~151 requests)
  ida       ordered N-to-C domain architectures        (one request per family)

Both stages are resumable: results are appended to a JSON-lines file and any
accession already present is skipped, so an interrupted run costs nothing.
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests

BASE = "https://www.ebi.ac.uk/interpro/api"
UA = {"User-Agent": "PfamIE-forge/1.0 (marc@marcdeller.com)"}
IDA_PER_FAMILY = 15          # top architectures kept per family
TIMEOUT = 60


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update(UA)
    return s


def _get(session, url, attempts=5):
    """GET with backoff. InterPro answers 408/429/50x under load; those retry."""
    delay = 2.0
    for attempt in range(attempts):
        try:
            r = session.get(url, timeout=TIMEOUT)
            if r.status_code == 200:
                return r.json()
            if r.status_code == 204:            # documented "no hits" answer
                return None
            if r.status_code == 404:
                return None
            if r.status_code not in (408, 429, 500, 502, 503, 504):
                r.raise_for_status()
        except requests.RequestException:
            pass
        time.sleep(delay)
        delay = min(delay * 2, 60)
    raise RuntimeError(f"gave up on {url}")


def _load_done(path: Path) -> set[str]:
    if not path.exists():
        return set()
    done = set()
    with path.open() as fh:
        for line in fh:
            try:
                done.add(json.loads(line)["accession"])
            except Exception:
                continue           # a torn final line from a hard kill
    return done


# --------------------------------------------------------------------------- counters

def run_counters(build_dir: Path) -> dict:
    out = build_dir / "counters.jsonl"
    done = _load_done(out)
    session = _session()
    url = f"{BASE}/entry/pfam/?page_size=200&extra_fields=counters"
    written = 0

    with out.open("a") as fh:
        while url:
            payload = _get(session, url)
            if payload is None:
                break
            for row in payload["results"]:
                acc = row["metadata"]["accession"]
                if acc in done:
                    continue
                c = (row.get("extra_fields") or {}).get("counters") or {}
                fh.write(json.dumps({
                    "accession": acc,
                    "proteins": c.get("proteins", 0),
                    "taxa": c.get("taxa", 0),
                    "structures": c.get("structures", 0),
                    "architectures": c.get("domain_architectures", 0),
                    "alphafold": (c.get("structural_models") or {}).get("alphafold", 0),
                }) + "\n")
                written += 1
            fh.flush()
            url = payload.get("next")
            print(f"\rcounters: {written + len(done)}", end="", file=sys.stderr, flush=True)

    print(file=sys.stderr)
    return {"written": written, "total": written + len(done), "output": str(out)}


# --------------------------------------------------------------------------- ida

def run_ida(build_dir: Path, workers: int = 8) -> dict:
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    accessions = [f["accession"] for f in families]

    out = build_dir / "ida.jsonl"
    done = _load_done(out)
    todo = [a for a in accessions if a not in done]
    print(f"ida: {len(done)} done, {len(todo)} to fetch", file=sys.stderr)

    lock = threading.Lock()
    local = threading.local()
    counter = {"n": len(done), "fail": 0}
    started = time.time()
    fh = out.open("a")

    def fetch(acc: str):
        if not hasattr(local, "session"):
            local.session = _session()
        url = f"{BASE}/entry/pfam/{acc}/?ida&page_size={IDA_PER_FAMILY}"
        try:
            payload = _get(local.session, url)
        except RuntimeError:
            with lock:
                counter["fail"] += 1
            return
        rows = []
        if payload:
            for r in payload.get("results", []):
                rep = r.get("representative") or {}
                # The ida string is 'PFxxxxx:IPRyyyyy-PFzzzzz:IPRwwwww', N to C.
                members = [seg.split(":")[0] for seg in r["ida"].split("-") if seg]
                rows.append({
                    "members": members,
                    "n": r.get("unique_proteins", 0),
                    "rep": rep.get("accession"),
                    "rep_length": rep.get("length"),
                })
        record = {
            "accession": acc,
            "total_architectures": (payload or {}).get("count", 0),
            "architectures": rows,
        }
        with lock:
            fh.write(json.dumps(record) + "\n")
            counter["n"] += 1
            if counter["n"] % 50 == 0:
                fh.flush()
                elapsed = time.time() - started
                rate = max(counter["n"] - len(done), 1) / max(elapsed, 1e-6)
                remaining = (len(accessions) - counter["n"]) / max(rate, 1e-6)
                print(
                    f"\rida: {counter['n']}/{len(accessions)}  "
                    f"{rate:.1f}/s  eta {remaining/60:.0f} min  fail {counter['fail']}",
                    end="", file=sys.stderr, flush=True,
                )

    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(fetch, todo))

    fh.flush()
    fh.close()
    print(file=sys.stderr)
    return {"total": counter["n"], "failed": counter["fail"], "output": str(out)}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("stage", choices=["counters", "ida"])
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    build = root / "assets/build"
    result = run_counters(build) if args.stage == "counters" else run_ida(build, args.workers)
    print(json.dumps(result, indent=2))
