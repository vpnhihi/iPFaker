#!/usr/bin/env python3
"""Rebuild deb 2.3.5, sync sileo-repo, force-push gh-pages for Sileo."""
from __future__ import annotations

import hashlib
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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
    subprocess.check_call(
        ["python", str(ROOT / "scripts" / "build_sileo_deb.py"), "--version", "2.3.5"],
        cwd=ROOT,
    )
    deb = ROOT / "dist" / "sileo" / "com.ipfaker_2.3.5_iphoneos-arm64.deb"
    repo_src = ROOT / "dist" / "sileo" / "repo"
    out = ROOT / "sileo-repo"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    (out / "debs").mkdir()
    shutil.copy2(repo_src / "Packages", out / "Packages")
    shutil.copy2(repo_src / "Packages.gz", out / "Packages.gz")
    shutil.copy2(repo_src / "Release", out / "Release")
    shutil.copy2(deb, out / "debs" / deb.name)
    shutil.copy2(deb, out / deb.name)
    (out / ".nojekyll").write_text("", encoding="utf-8")
    (out / "index.html").write_text(
        """<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>iPFaker Sileo</title></head><body>
<h1>iPFaker Sileo Repo</h1>
<p><code>https://vpnhihi.github.io/iPFaker/</code></p>
<p>Package: com.ipfaker 2.3.5 (data.tar.lzma)</p>
<p><a href="debs/com.ipfaker_2.3.5_iphoneos-arm64.deb">Download .deb</a></p>
</body></html>
""",
        encoding="utf-8",
    )

    user, password = git_cred()
    tmp = Path(tempfile.mkdtemp(prefix="ipfaker-gh-"))
    for item in out.iterdir():
        dest = tmp / item.name
        if item.is_dir():
            shutil.copytree(item, dest)
        else:
            shutil.copy2(item, dest)

    def run(cmd, **kw):
        print("+", " ".join(cmd) if isinstance(cmd, list) else cmd)
        subprocess.check_call(cmd, cwd=tmp, **kw)

    run(["git", "init", "-b", "gh-pages"])
    run(["git", "config", "user.email", "ipfaker-lab@local"])
    run(["git", "config", "user.name", "iPFaker Lab"])
    run(["git", "add", "-A"])
    run(["git", "commit", "-m", "iPFaker Sileo 2.3.5 lzma"])
    # Avoid printing token: use askpass helper
    ask = tmp / "askpass.py"
    ask.write_text(
        "#!/usr/bin/env python3\nimport os,sys\n"
        "print(os.environ.get('GIT_PASSWORD',''))\n",
        encoding="utf-8",
    )
    env = {**dict(**{k: v for k, v in __import__("os").environ.items()}), "GIT_PASSWORD": password}
    env["GIT_ASKPASS"] = str(ask)
    env["GIT_TERMINAL_PROMPT"] = "0"
    subprocess.check_call(
        ["git", "push", "-f", f"https://{user}@github.com/vpnhihi/iPFaker.git", "gh-pages"],
        cwd=tmp,
        env=env,
    )

    print("pushed gh-pages")
    # verify after short wait
    import time

    time.sleep(15)
    for u in (
        "https://raw.githubusercontent.com/vpnhihi/iPFaker/gh-pages/debs/com.ipfaker_2.3.5_iphoneos-arm64.deb",
        "https://vpnhihi.github.io/iPFaker/debs/com.ipfaker_2.3.5_iphoneos-arm64.deb",
        "https://cdn.jsdelivr.net/gh/vpnhihi/iPFaker@gh-pages/debs/com.ipfaker_2.3.5_iphoneos-arm64.deb",
    ):
        try:
            data = urllib.request.urlopen(u, timeout=30).read()
            print("OK", len(data), data[:8], hashlib.sha256(data).hexdigest()[:12], u)
        except Exception as e:
            print("FAIL", u, e)

    # clear apt cache on device (optional; needs IPFAKER_HOST / IPFAKER_PASS)
    try:
        import paramiko
        import sys
        from pathlib import Path

        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from _device_env import require

        host, user, password = require()
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(
            host,
            username=user,
            password=password,
            timeout=20,
            allow_agent=False,
            look_for_keys=False,
        )
        cmd = (
            f"echo {password} | sudo -S -p '' "
            "rm -rf /var/jb/var/cache/apt/archives/com.ipfaker* "
            "/var/jb/var/lib/apt/lists/* 2>/dev/null; true"
        )
        _, o, _ = c.exec_command(cmd, timeout=60)
        print("device cache cleared", o.read()[:200])
        c.close()
    except SystemExit:
        print("device clear skip (set IPFAKER_HOST/IPFAKER_PASS to enable)")
    except Exception as e:
        print("device clear skip", e)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
