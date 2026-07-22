#!/usr/bin/env python3
"""Force-push sileo-repo/ to branch gh-pages for https://vpnhihi.github.io/ipfaker/"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "sileo-repo"


def git_cred() -> tuple[str, str]:
    p = subprocess.run(
        ["git", "credential", "fill"],
        input="protocol=https\nhost=github.com\n\n",
        text=True,
        capture_output=True,
        check=True,
    )
    user, password = "vpnhihi", ""
    for line in p.stdout.splitlines():
        if line.startswith("username="):
            user = line.split("=", 1)[1]
        if line.startswith("password="):
            password = line.split("=", 1)[1]
    return user, password


def main() -> int:
    if not SRC.is_dir():
        print("missing sileo-repo/")
        return 1
    (SRC / ".nojekyll").write_text("", encoding="utf-8")
    (SRC / "index.html").write_text(
        """<!DOCTYPE html>
<html lang="vi"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>iPFaker Sileo</title>
<style>
body{font-family:-apple-system,sans-serif;max-width:640px;margin:2rem auto;padding:0 1rem;background:#0b0d10;color:#e8eaed}
.url{background:#111;color:#4ade80;padding:1rem;border-radius:8px;word-break:break-all}
a{color:#60a5fa}
</style></head><body>
<h1>iPFaker — nguồn Sileo</h1>
<p class="url">https://vpnhihi.github.io/ipfaker/</p>
<p>Gói <b>com.ipfaker 2.8.0</b> · full stack lab · rootless · iphoneos-arm64 · Dopamine</p>
<ol>
<li>Sileo → Sources → +</li>
<li>Dán URL (chữ thường ipfaker) → Add</li>
<li>Refresh → tìm <b>iPFaker</b> → Cài</li>
</ol>
<p><a href="debs/com.ipfaker_2.8.0_iphoneos-arm64.deb">Tải .deb 2.8.0 trực tiếp</a></p>
</body></html>
""",
        encoding="utf-8",
    )

    user, password = git_cred()
    if not password:
        print("no git credentials")
        return 2

    tmp = Path(tempfile.mkdtemp(prefix="ipf-pages-"))
    for item in SRC.iterdir():
        dest = tmp / item.name
        if item.is_dir():
            shutil.copytree(item, dest)
        else:
            shutil.copy2(item, dest)

    def run(cmd: list[str]) -> None:
        print("+", " ".join(cmd))
        subprocess.check_call(cmd, cwd=tmp)

    run(["git", "init", "-b", "gh-pages"])
    run(["git", "config", "user.email", "ipfaker-lab@local"])
    run(["git", "config", "user.name", "iPFaker Lab"])
    run(["git", "add", "-A"])
    run(["git", "commit", "-m", "sileo pages 2.8.0 full stack"])

    ask = tmp / "askpass.py"
    ask.write_text(
        "#!/usr/bin/env python3\nimport os\nprint(os.environ.get('GIT_PASSWORD',''))\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env["GIT_PASSWORD"] = password
    env["GIT_ASKPASS"] = str(ask)
    env["GIT_TERMINAL_PROMPT"] = "0"
    subprocess.check_call(
        [
            "git",
            "push",
            "-f",
            f"https://{user}@github.com/vpnhihi/ipfaker.git",
            "HEAD:gh-pages",
        ],
        cwd=tmp,
        env=env,
    )
    print("OK: gh-pages updated")
    print("Sileo source: https://vpnhihi.github.io/ipfaker/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
