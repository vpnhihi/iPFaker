#!/usr/bin/env python3
"""Stage sileo-repo with highest semantic version com.ipfaker from dist/sileo."""
from __future__ import annotations

import gzip
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / "sileo-repo"
DEBS = REPO / "debs"
DIST = ROOT / "dist" / "sileo"


def parse_ver(name: str) -> tuple:
    m = re.search(r"com\.ipfaker_([^_]+)_", name)
    if not m:
        return (0,)
    parts = []
    for p in m.group(1).split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def main() -> int:
    cands = list(DIST.glob("com.ipfaker_*_iphoneos-arm64.deb"))
    if not cands:
        raise SystemExit("no dist deb")
    dist_deb = max(cands, key=lambda p: parse_ver(p.name))
    ver = re.search(r"com\.ipfaker_([^_]+)_", dist_deb.name).group(1)
    dist_pkg = DIST / "repo" / "Packages"
    if not dist_pkg.is_file():
        raise SystemExit(f"missing {dist_pkg}")
    pkg_text = dist_pkg.read_text(encoding="utf-8")
    if f"Version: {ver}" not in pkg_text:
        raise SystemExit(f"dist Packages version mismatch, want {ver}")

    DEBS.mkdir(parents=True, exist_ok=True)
    for p in list(REPO.glob("com.ipfaker_*.deb")) + list(DEBS.glob("com.ipfaker_*.deb")):
        print("rm", p.name)
        p.unlink()
    shutil.copy2(dist_deb, DEBS / dist_deb.name)
    print("copy", dist_deb.name, dist_deb.stat().st_size)

    old = (REPO / "Packages").read_text(encoding="utf-8", errors="replace")
    deps = []
    for b in old.split("\n\n"):
        b = b.strip()
        if not b or b.startswith("Package: com.ipfaker"):
            continue
        fn = None
        for line in b.splitlines():
            if line.startswith("Filename: "):
                fn = line.split(" ", 1)[1].strip()
        if fn and (REPO / fn).is_file():
            deps.append(b)

    packages = (pkg_text.strip() + "\n\n" + "\n\n".join(deps) + "\n").replace("\r\n", "\n")
    (REPO / "Packages").write_bytes(packages.encode("utf-8"))
    with gzip.open(REPO / "Packages.gz", "wb") as gz:
        gz.write(packages.encode("utf-8"))
    (REPO / "Release").write_text(
        "Origin: iPFaker Lab\nLabel: iPFaker\nSuite: stable\nVersion: 1.0\n"
        "Codename: ipfaker\nArchitectures: iphoneos-arm64\nComponents: main\n"
        "Description: iPFaker packages for Dopamine rootless / Sileo\n",
        encoding="utf-8",
    )
    (REPO / "INSTALL.txt").write_text(
        f"iPFaker {ver} — Userspace Reboot only after dpkg install completes\n"
        "Source: https://vpnhihi.github.io/ipfaker/\n"
        f"1) Install iPFaker {ver}\n"
        "2) Wait Sileo Done — then auto Userspace Reboot\n"
        "3) Open iPFaker -> Apply\n",
        encoding="utf-8",
    )
    html = f"""<!DOCTYPE html>
<html lang="vi"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>iPFaker Sileo</title>
<style>
body{{font-family:-apple-system,sans-serif;max-width:640px;margin:2rem auto;padding:0 1rem;background:#0b0d10;color:#e8eaed;line-height:1.5}}
.url{{background:#111;color:#4ade80;padding:1rem;border-radius:8px;word-break:break-all}}
a{{color:#60a5fa}}
.box{{background:#151820;padding:1rem;border-radius:8px;margin:1rem 0}}
.warn{{color:#fbbf24}}
</style></head><body>
<h1>iPFaker — nguồn Sileo</h1>
<p class="url">https://vpnhihi.github.io/ipfaker/</p>
<p>Gói <b>com.ipfaker {ver}</b> · full stack · rootless</p>
<div class="box"><strong>{ver}:</strong> tự Userspace Reboot <em>chỉ sau khi</em> dpkg cài xong hẳn (không cắt giữa chừng).</div>
<ol>
<li>Sileo → Sources → Refresh</li>
<li>Cài <b>iPFaker {ver}</b> — đợi Sileo <b>Done</b></li>
<li class="warn">Máy tự Userspace Reboot sau khi install hoàn tất</li>
<li>Mở iPFaker → Apply → Zalo</li>
</ol>
<p><a href="debs/com.ipfaker_{ver}_iphoneos-arm64.deb">Tải .deb {ver}</a></p>
</body></html>
"""
    (REPO / "index.html").write_text(html, encoding="utf-8")
    (REPO / ".nojekyll").write_text("", encoding="utf-8")
    print("version", ver)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
