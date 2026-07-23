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

    # Sanity: only one com.ipfaker deb
    debs = sorted((SRC / "debs").glob("com.ipfaker_*.deb"))
    root_debs = sorted(SRC.glob("com.ipfaker_*.deb"))
    if root_debs:
        print("ERROR: root-level com.ipfaker debs must be removed:", [p.name for p in root_debs])
        return 3
    if len(debs) != 1:
        print("ERROR: expected exactly 1 com.ipfaker deb in debs/, got:", [p.name for p in debs])
        return 4
    print("publishing", debs[0].name)

    (SRC / ".nojekyll").write_text("", encoding="utf-8")

    user, password = git_cred()
    if not password:
        print("no git credentials")
        return 2

    tmp = Path(tempfile.mkdtemp(prefix="ipf-pages-"))
    for item in SRC.iterdir():
        # never publish lab helpers
        if item.name.startswith("fix_") or item.name.endswith(".sh"):
            print("skip", item.name)
            continue
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
    run(["git", "commit", "-m", f"sileo pages {debs[0].name} only"])

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
    print("OK: gh-pages updated (force, single version)")
    print("Sileo source: https://vpnhihi.github.io/ipfaker/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
