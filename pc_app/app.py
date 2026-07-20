#!/usr/bin/env python3
"""
iPFaker PC — điều khiển qua Wi‑Fi SSH.
Pool máy/iOS chọn trên iPhone (iPFaker.app). PC: spoof/wipe/reg + API SMS/OTP/captcha.
"""
from __future__ import annotations

import json
import os
import sys
import threading
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
PC_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(PC_DIR))

ERR_LOG = PC_DIR / "last_error.txt"
START_LOG = PC_DIR / "startup.log"
SETTINGS_PATH = Path(os.environ.get("APPDATA", str(Path.home()))) / "iPFakerPC" / "settings.json"

os.environ.setdefault("PYTHONUTF8", "1")
os.environ.setdefault("PYTHONIOENCODING", "utf-8")

BG = "#0f1115"
PANEL = "#171a21"
FG = "#e8eaed"
MUTED = "#9aa0a6"
ACCENT = "#3b82f6"
GREEN = "#22c55e"
ORANGE = "#f59e0b"
RED = "#ef4444"
ENTRY_BG = "#1f2430"
PURPLE = "#a855f7"

DEFAULT_APPS = [
    ("Zalo (VN)", "vn.com.vng.zingalo"),
    ("Zalo (alt)", "com.zing.zalo"),
    ("Ban do", "com.apple.Maps"),
    ("Thoi tiet", "com.apple.weather"),
]


def _log_start(msg: str) -> None:
    try:
        with START_LOG.open("a", encoding="utf-8") as f:
            f.write(msg.rstrip() + "\n")
    except Exception:
        pass


def _write_err(tb: str) -> None:
    try:
        ERR_LOG.write_text(tb, encoding="utf-8")
    except Exception:
        pass


def _read_json(path: Path) -> dict:
    """Read JSON; tolerate UTF-8 BOM (PowerShell Set-Content)."""
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    return json.loads(raw.decode("utf-8"))


def _safe_import_tk():
    import tkinter as tk
    from tkinter import messagebox, scrolledtext, ttk

    return tk, messagebox, scrolledtext, ttk


_sdp = None


def sdp():
    global _sdp
    if _sdp is None:
        import select_device_profile as mod

        _sdp = mod
    return _sdp


class IPfakerPC:
    def __init__(self, tk, ttk, messagebox, scrolledtext):
        self.tk = tk
        self.ttk = ttk
        self.messagebox = messagebox
        self.root = tk.Tk()
        self.root.title("iPFaker PC")
        self.root.geometry("1020x900")
        self.root.minsize(900, 720)
        self.pipeline = None
        self.root.configure(bg=BG)

        self.client = None
        self.reg_runner = None
        self._busy = False
        self._app_vars = {}
        self.catalog = {"devices": [], "ios_releases": {}}
        self._settings: dict = {}

        try:
            self.catalog = sdp().load_catalog()
        except Exception as e:
            _log_start(f"catalog: {e}")

        self._style()
        self._build_ui(scrolledtext)
        self._load_settings()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self.root.report_callback_exception = self._tk_exception

    def _tk_exception(self, exc, val, tb):
        text = "".join(traceback.format_exception(exc, val, tb))
        _write_err(text)
        self.log(f"LOI UI: {val}")
        try:
            self.messagebox.showerror("Loi", f"{val}\n\n{ERR_LOG}")
        except Exception:
            pass

    def _style(self):
        st = self.ttk.Style(self.root)
        try:
            st.theme_use("clam")
        except Exception:
            pass
        st.configure(".", background=BG, foreground=FG, fieldbackground=ENTRY_BG)
        st.configure("TFrame", background=BG)
        st.configure("Card.TFrame", background=PANEL)
        st.configure("TLabel", background=BG, foreground=FG, font=("Segoe UI", 10))
        st.configure("Card.TLabel", background=PANEL, foreground=FG)
        st.configure("Muted.TLabel", background=PANEL, foreground=MUTED, font=("Segoe UI", 9))
        st.configure("Title.TLabel", background=BG, foreground=FG, font=("Segoe UI Semibold", 14))
        st.configure("TCheckbutton", background=PANEL, foreground=FG)
        st.configure("TButton", font=("Segoe UI", 10), padding=5)
        st.configure("TEntry", fieldbackground=ENTRY_BG, foreground=FG)
        st.configure("TNotebook", background=BG)
        st.configure("TNotebook.Tab", background=PANEL, foreground=FG, padding=[10, 5])
        st.map("TNotebook.Tab", background=[("selected", ACCENT)], foreground=[("selected", "#fff")])

    def _build_ui(self, scrolledtext):
        tk, ttk = self.tk, self.ttk

        head = ttk.Frame(self.root)
        head.pack(fill="x", padx=12, pady=(10, 4))
        ttk.Label(head, text="iPFaker PC", style="Title.TLabel").pack(side="left")
        ttk.Label(
            head,
            text="  Wi-Fi SSH  |  pool may/iOS tren iPhone  |  reg + API",
            foreground=MUTED,
            background=BG,
        ).pack(side="left")

        # Connection
        conn = ttk.Frame(self.root, style="Card.TFrame")
        conn.pack(fill="x", padx=12, pady=4)
        row = ttk.Frame(conn, style="Card.TFrame")
        row.pack(fill="x", padx=8, pady=8)

        self.var_host = tk.StringVar(value="192.168.1.10")
        self.var_user = tk.StringVar(value="mobile")
        self.var_pass = tk.StringVar(value="")
        self.var_port = tk.StringVar(value="22")

        for label, var, w, show in (
            ("IP may", self.var_host, 14, None),
            ("User", self.var_user, 8, None),
            ("Mat khau SSH", self.var_pass, 12, "*"),
            ("Port", self.var_port, 5, None),
        ):
            f = ttk.Frame(row, style="Card.TFrame")
            f.pack(side="left", padx=(0, 10))
            ttk.Label(f, text=label, style="Muted.TLabel").pack(anchor="w")
            ttk.Entry(f, textvariable=var, width=w, show=show or "").pack()

        bf = ttk.Frame(row, style="Card.TFrame")
        bf.pack(side="left", padx=6)
        ttk.Label(bf, text=" ", style="Muted.TLabel").pack()
        ttk.Button(bf, text="Ket noi", command=self._connect).pack(side="left", padx=2)
        ttk.Button(bf, text="Lam moi", command=self._refresh_status).pack(side="left", padx=2)
        ttk.Button(bf, text="Ngat", command=self._disconnect).pack(side="left", padx=2)

        self.lbl_link = tk.Label(row, text="● Chua ket noi", bg=PANEL, fg=ORANGE, font=("Segoe UI", 10))
        self.lbl_link.pack(side="right", padx=8)

        # Status + phone pool
        stf = ttk.Frame(self.root, style="Card.TFrame")
        stf.pack(fill="x", padx=12, pady=4)
        ttk.Label(stf, text="Trang thai (doc tu iPhone)", style="Card.TLabel", font=("Segoe UI Semibold", 10)).pack(
            anchor="w", padx=8, pady=(6, 0)
        )
        self.lbl_status = tk.Label(
            stf,
            text="Chua ket noi.\nPool may/iOS: chon trong app iPFaker tren dien thoai (tab Chon may / iOS).",
            bg=PANEL,
            fg=MUTED,
            justify="left",
            font=("Consolas", 9),
            anchor="w",
        )
        self.lbl_status.pack(fill="x", padx=8, pady=(2, 8))

        # Notebook
        nb = ttk.Notebook(self.root)
        nb.pack(fill="both", expand=True, padx=12, pady=4)

        tab_ctrl = ttk.Frame(nb, style="Card.TFrame")
        tab_wf = ttk.Frame(nb, style="Card.TFrame")
        tab_api = ttk.Frame(nb, style="Card.TFrame")
        nb.add(tab_ctrl, text="  Dieu khien  ")
        nb.add(tab_wf, text="  Quy trinh 18 buoc  ")
        nb.add(tab_api, text="  API keys  ")

        # --- Control tab ---
        ttk.Label(
            tab_ctrl,
            text="Pool may/iOS: chon tren iPhone (iPFaker). PC doc pools.json.",
            style="Muted.TLabel",
        ).pack(anchor="w", padx=10, pady=(10, 4))

        apps_f = ttk.Frame(tab_ctrl, style="Card.TFrame")
        apps_f.pack(fill="x", padx=10, pady=4)
        ttk.Label(apps_f, text="App muc tieu (wipe / backup)", style="Card.TLabel").pack(anchor="w")
        for name, bid in DEFAULT_APPS:
            v = tk.BooleanVar(value="zalo" in bid.lower())
            self._app_vars[bid] = v
            ttk.Checkbutton(apps_f, text=name, variable=v).pack(anchor="w")

        ar = ttk.Frame(tab_ctrl, style="Card.TFrame")
        ar.pack(fill="x", padx=10, pady=10)
        self._mkbtn(ar, "Ap dung may (pool DT)", self._apply_selected, ACCENT)
        self._mkbtn(ar, "Dat lai du lieu app", self._reset_data, RED)
        self._mkbtn(ar, "Dat lai + Luu du lieu", self._save_then_reset, GREEN)
        self._mkbtn(ar, "Chi xoa data", self._wipe_only, ORANGE)
        self._mkbtn(ar, "Mo Zalo", self._open_zalo, PANEL)

        reg = ttk.Frame(tab_ctrl, style="Card.TFrame")
        reg.pack(fill="x", padx=10, pady=8)
        ttk.Label(
            reg,
            text="Reg day du 18 buoc (Proxy → Shadowrocket → Reset → Zalo → OTP → AppManager)",
            style="Card.TLabel",
            font=("Segoe UI Semibold", 11),
        ).pack(anchor="w")
        ttk.Label(
            reg,
            text="Cau hinh: tab «Quy trinh 18 buoc» + «API keys». Mo khoa man hinh may.",
            style="Muted.TLabel",
        ).pack(anchor="w")
        rb = ttk.Frame(reg, style="Card.TFrame")
        rb.pack(fill="x", pady=8)
        self._mkbtn(rb, "CHAY QUY TRINH REG", self._run_pipeline, PURPLE)
        self._mkbtn(rb, "Dung pipeline", self._stop_pipeline, PANEL)

        # placeholders for old settings keys
        self.var_phone = tk.StringVar(value="")
        self.var_name = tk.StringVar(value="Lab User")
        self.var_otp = tk.StringVar(value="")

        # --- Workflow tab: names, profiles, delays ---
        self._build_workflow_tab(tab_wf, scrolledtext)

        # --- API keys tab ---
        api_in = ttk.Frame(tab_api, style="Card.TFrame")
        api_in.pack(fill="both", expand=True, padx=10, pady=10)

        self.var_boss_token = tk.StringVar(value="")
        self.var_boss_network = tk.StringVar(value="")
        self.var_boss_prefix = tk.StringVar(value="")
        self.var_rota_key = tk.StringVar(value="")
        self.var_rota_app = tk.StringVar(value="")
        self.var_achi_key = tk.StringVar(value="")
        self.var_2cap_key = tk.StringVar(value="")
        self.var_capsolver_key = tk.StringVar(value="")
        self.var_cap_provider = tk.StringVar(value="auto")
        self.var_privacy = tk.StringVar(value="first_only")
        self.var_contacts = tk.StringVar(value="skip")
        self.var_appmgr = tk.StringVar(value="com.tigisoftware.appdatamanager")

        ttk.Label(api_in, text="BossOTP.net", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(anchor="w")
        self._api_field(api_in, "API token (sk_...)", self.var_boss_token, 64, show="*")
        self._api_field(api_in, "Network (VIETTEL/MOBIFONE/... de trong = bat ky)", self.var_boss_network, 40)
        self._api_field(api_in, "Prefixs (vd 56|57|95)", self.var_boss_prefix, 40)

        ttk.Label(api_in, text="RotaProxy.com", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(
            anchor="w", pady=(10, 0)
        )
        self._api_field(api_in, "package_api_key", self.var_rota_key, 64, show="*")
        self._api_field(api_in, "app_id (optional)", self.var_rota_app, 20)

        ttk.Label(
            api_in,
            text="Captcha (Achi loi → dung 2captcha / CapSolver)",
            style="Card.TLabel",
            font=("Segoe UI Semibold", 11),
        ).pack(anchor="w", pady=(10, 0))
        self._api_field(
            api_in,
            "Provider: auto | 2captcha | capsolver | achi",
            self.var_cap_provider,
            16,
        )
        self._api_field(api_in, "2captcha.com API key (khuyen nghi khi Achi die)", self.var_2cap_key, 64, show="*")
        self._api_field(api_in, "CapSolver.com API key (optional)", self.var_capsolver_key, 64, show="*")
        self._api_field(api_in, "AchiCaptcha clientKey (khi web song lai)", self.var_achi_key, 64, show="*")

        ttk.Label(api_in, text="Tuy chon reg", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(
            anchor="w", pady=(10, 0)
        )
        self._api_field(
            api_in,
            "Privacy mode: first_only | first_two | all_three",
            self.var_privacy,
            20,
        )
        self._api_field(api_in, "Contacts: skip | continue", self.var_contacts, 16)
        self._api_field(api_in, "AppManager bundle", self.var_appmgr, 40)

        ttk.Button(api_in, text="Luu API + tuy chon", command=self._save_settings).pack(anchor="w", pady=12)
        ttk.Label(
            api_in,
            text="Token chi luu tren PC (%APPDATA%\\iPFakerPC\\settings.json) — KHONG commit git.\n"
            "Ban da gui token trong chat: nen xoay key moi tren BossOTP neu lo.",
            style="Muted.TLabel",
            justify="left",
        ).pack(anchor="w")

        # Log
        logf = ttk.Frame(self.root)
        logf.pack(fill="both", expand=True, padx=12, pady=(2, 10))
        ttk.Label(logf, text="Nhat ky", foreground=MUTED, background=BG).pack(anchor="w")
        self.log_box = scrolledtext.ScrolledText(
            logf, height=8, bg=ENTRY_BG, fg=FG, insertbackground=FG, font=("Consolas", 9), relief="flat"
        )
        self.log_box.pack(fill="both", expand=True)
        self.log("San sang. Chon pool may/iOS tren iPhone. PC chi ket noi + reg/API.")

    def _api_field(self, parent, label, var, width, show=None):
        f = self.ttk.Frame(parent, style="Card.TFrame")
        f.pack(fill="x", pady=2)
        self.ttk.Label(f, text=label, style="Muted.TLabel").pack(anchor="w")
        self.ttk.Entry(f, textvariable=var, width=width, show=show or "").pack(anchor="w")

    def _build_workflow_tab(self, tab, scrolledtext):
        """Names table, DOB/gender profiles, per-step delay min/max."""
        from workflow_data import load_delays, load_names, load_profiles

        tk, ttk = self.tk, self.ttk
        outer = ttk.Frame(tab, style="Card.TFrame")
        outer.pack(fill="both", expand=True, padx=8, pady=8)

        # left: names + profiles
        left = ttk.Frame(outer, style="Card.TFrame")
        left.pack(side="left", fill="both", expand=True, padx=(0, 6))
        right = ttk.Frame(outer, style="Card.TFrame")
        right.pack(side="right", fill="both", expand=True, padx=(6, 0))

        ttk.Label(left, text="Bang ten Zalo (1 dong = 1 ten, random)", style="Card.TLabel").pack(anchor="w")
        self.txt_names = scrolledtext.ScrolledText(
            left, height=8, bg=ENTRY_BG, fg=FG, insertbackground=FG, font=("Segoe UI", 10), relief="flat"
        )
        self.txt_names.pack(fill="both", expand=True, pady=4)
        self.txt_names.insert("1.0", "\n".join(load_names()))

        ttk.Label(
            left,
            text="Bang sinh nhat + gioi tinh (moi dong: dd/mm/yyyy|nam hoac nu)",
            style="Card.TLabel",
        ).pack(anchor="w", pady=(8, 0))
        self.txt_profiles = scrolledtext.ScrolledText(
            left, height=8, bg=ENTRY_BG, fg=FG, insertbackground=FG, font=("Segoe UI", 10), relief="flat"
        )
        self.txt_profiles.pack(fill="both", expand=True, pady=4)
        lines = []
        for p in load_profiles():
            lines.append(f"{p.get('dob')}|{p.get('gender')}")
        self.txt_profiles.insert("1.0", "\n".join(lines))

        ttk.Button(left, text="Luu bang ten + profile", command=self._save_tables).pack(anchor="w", pady=6)

        ttk.Label(
            right,
            text="Delay random tung buoc (giay): min max — moi dong: key min max",
            style="Card.TLabel",
        ).pack(anchor="w")
        self.txt_delays = scrolledtext.ScrolledText(
            right, height=22, bg=ENTRY_BG, fg=FG, insertbackground=FG, font=("Consolas", 9), relief="flat"
        )
        self.txt_delays.pack(fill="both", expand=True, pady=4)
        delays = load_delays()
        delay_lines = [f"{k}  {v[0]}  {v[1]}" for k, v in sorted(delays.items())]
        self.txt_delays.insert("1.0", "\n".join(delay_lines))
        ttk.Button(right, text="Luu delay", command=self._save_delays_ui).pack(anchor="w", pady=4)
        ttk.Label(
            right,
            text="Vi du: 13_soak  30  120  = ngam 30–120s\n"
            "01_rotate_proxy  2  5\nMoi buoc deu random min–max.",
            style="Muted.TLabel",
            justify="left",
        ).pack(anchor="w")

    def _mkbtn(self, parent, text, cmd, color):
        b = self.tk.Button(
            parent,
            text=text,
            command=cmd,
            bg=color if color != PANEL else "#2a2f3a",
            fg="#ffffff",
            activebackground=ACCENT,
            relief="flat",
            padx=10,
            pady=6,
            font=("Segoe UI Semibold", 9),
            cursor="hand2",
        )
        b.pack(side="left", padx=3)

    # ── settings ───────────────────────────────────────────
    def _load_settings(self):
        try:
            if not SETTINGS_PATH.exists():
                return
            data = _read_json(SETTINGS_PATH)
            self._settings = data
            mapping = (
                ("host", self.var_host),
                ("user", self.var_user),
                ("password", self.var_pass),
                ("bossotp_token", self.var_boss_token),
                ("bossotp_network", self.var_boss_network),
                ("bossotp_prefixs", self.var_boss_prefix),
                ("rotaproxy_key", self.var_rota_key),
                ("rotaproxy_app_id", self.var_rota_app),
                ("achicaptcha_key", self.var_achi_key),
                ("twocaptcha_key", self.var_2cap_key),
                ("capsolver_key", self.var_capsolver_key),
                ("captcha_provider", self.var_cap_provider),
                ("privacy_mode", self.var_privacy),
                ("contacts_action", self.var_contacts),
                ("appmanager_bundle", self.var_appmgr),
            )
            for k, var in mapping:
                if data.get(k) is not None and str(data.get(k)) != "":
                    var.set(str(data[k]))
            if data.get("port"):
                self.var_port.set(str(data["port"]))
        except Exception as e:
            self.log(f"Khong doc settings: {e}")

    def _save_settings(self):
        try:
            SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
            data = {
                "host": self.var_host.get().strip(),
                "user": self.var_user.get().strip(),
                "port": int(self.var_port.get() or 22),
                "remember_pass": True,
                "password": self.var_pass.get(),
                "bossotp_token": self.var_boss_token.get().strip(),
                "bossotp_network": self.var_boss_network.get().strip(),
                "bossotp_prefixs": self.var_boss_prefix.get().strip(),
                "rotaproxy_key": self.var_rota_key.get().strip(),
                "rotaproxy_app_id": self.var_rota_app.get().strip(),
                "achicaptcha_key": self.var_achi_key.get().strip(),
                "twocaptcha_key": self.var_2cap_key.get().strip(),
                "capsolver_key": self.var_capsolver_key.get().strip(),
                "captcha_provider": self.var_cap_provider.get().strip() or "auto",
                "privacy_mode": self.var_privacy.get().strip() or "first_only",
                "contacts_action": self.var_contacts.get().strip() or "skip",
                "appmanager_bundle": self.var_appmgr.get().strip()
                or "com.tigisoftware.appdatamanager",
            }
            SETTINGS_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            self._settings = data
            try:
                from workflow_data import save_config

                save_config({k: data[k] for k in data if k not in ("password", "host", "user", "port", "remember_pass")})
            except Exception as e:
                self.log(f"sync workflow config: {e}")
            self.log(f"Da luu settings → {SETTINGS_PATH}")
        except Exception as e:
            self.log(f"Luu settings loi: {e}")

    def _save_tables(self):
        from workflow_data import save_names, save_profiles

        names = [ln.strip() for ln in self.txt_names.get("1.0", "end").splitlines() if ln.strip()]
        save_names(names)
        profiles = []
        for ln in self.txt_profiles.get("1.0", "end").splitlines():
            ln = ln.strip()
            if not ln:
                continue
            if "|" in ln:
                dob, gen = ln.split("|", 1)
            elif "," in ln:
                dob, gen = ln.split(",", 1)
            else:
                dob, gen = ln, "nam"
            profiles.append({"dob": dob.strip(), "gender": gen.strip()})
        save_profiles(profiles)
        self.log(f"Luu {len(names)} ten, {len(profiles)} profile")

    def _save_delays_ui(self):
        from workflow_data import save_delays

        delays = {}
        for ln in self.txt_delays.get("1.0", "end").splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            parts = ln.split()
            if len(parts) >= 3:
                try:
                    delays[parts[0]] = [float(parts[1]), float(parts[2])]
                except ValueError:
                    pass
        if delays:
            save_delays(delays)
            self.log(f"Luu {len(delays)} delay keys")

    # ── helpers ────────────────────────────────────────────
    def log(self, msg: str):
        def _do():
            try:
                self.log_box.insert("end", str(msg).rstrip() + "\n")
                self.log_box.see("end")
            except Exception:
                pass

        try:
            self.root.after(0, _do)
        except Exception:
            pass

    def _set_link(self, ok: bool, text: str):
        self.root.after(0, lambda: self.lbl_link.configure(text=text, fg=GREEN if ok else ORANGE))

    def _set_status_text(self, txt: str, ok: bool = True):
        self.root.after(0, lambda: self.lbl_status.configure(text=txt, fg=FG if ok else RED))

    def _run_bg(self, title: str, fn):
        if self._busy:
            self.messagebox.showinfo("Dang chay", "Doi thao tac hien tai xong.")
            return

        def wrap():
            self._busy = True
            self.log(f"—— {title} ——")
            try:
                fn()
            except Exception as e:
                tb = traceback.format_exc()
                _write_err(tb)
                self.log(f"LOI: {e}")
                self.root.after(0, lambda: self.messagebox.showerror(title, f"{e}\n\n{ERR_LOG}"))
            finally:
                self._busy = False
                self.log(f"—— xong: {title} ——\n")

        threading.Thread(target=wrap, daemon=True).start()

    def _need_client(self):
        if not self.client or not self.client.connected:
            raise RuntimeError("Chua ket noi SSH.")
        return self.client

    def _selected_apps(self):
        apps = [k for k, v in self._app_vars.items() if v.get()]
        return apps or ["vn.com.vng.zingalo"]

    def _pick_from_phone_pool(self):
        from phone_pool import fetch_pools, pick_pair, format_pool_summary

        client = self._need_client()
        pools = fetch_pools(client)
        self.log(format_pool_summary(pools))
        return pick_pair(self.catalog, pools)

    def _build_and_deploy(self, device, ios, ios_meta):
        client = self._need_client()
        mod = sdp()
        built = mod.build_profile(device, ios, ios_meta, None)
        flat = built["flat"]
        mod.write_plist(flat, mod.OUT_PLIST)
        mod.OUT_ACTIVE.write_text(
            json.dumps(built["active"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        client.deploy_config(mod.OUT_PLIST.read_text(encoding="utf-8"), built["active"])
        return flat

    def _refresh_pool_status(self, st=None):
        from phone_pool import fetch_pools, format_pool_summary

        try:
            pools = fetch_pools(self._need_client())
            pool_txt = format_pool_summary(pools)
        except Exception as e:
            pool_txt = f"Pool: (chua doc duoc — {e})"
        if st and getattr(st, "ok", False):
            head = (
                f"Goi: {st.package}\n"
                f"Spoof: {st.marketing or '?'} ({st.product_type or '?'})  iOS {st.ios or '?'}\n"
                f"Serial: {st.serial or '?'}  Model: {st.model or '?'}\n"
            )
        elif st:
            head = f"Loi status: {st.message}\n"
        else:
            head = ""
        self._set_status_text(head + pool_txt, ok=True)

    # ── actions ────────────────────────────────────────────
    def _connect(self):
        self._save_settings()

        def job():
            from device_client import DeviceClient

            host = self.var_host.get().strip()
            user = self.var_user.get().strip() or "mobile"
            password = self.var_pass.get()
            port = int(self.var_port.get() or 22)
            if not host or not password:
                raise RuntimeError("Can IP va mat khau SSH.")
            if self.client:
                try:
                    self.client.close()
                except Exception:
                    pass
            self.client = DeviceClient(host, password, user=user, port=port, log=self.log)
            self.client.connect()
            self._set_link(True, f"● Online {host}")
            st = self.client.fetch_status()
            self._refresh_pool_status(st)

        self._run_bg("Ket noi", job)

    def _disconnect(self):
        if self.client:
            try:
                self.client.close()
            except Exception:
                pass
            self.client = None
        self._set_link(False, "● Da ngat")

    def _refresh_status(self):
        def job():
            st = self._need_client().fetch_status()
            self._refresh_pool_status(st)

        self._run_bg("Lam moi", job)

    def _apply_selected(self):
        def job():
            dev, ios, meta = self._pick_from_phone_pool()
            self.log(f"Ap dung pool DT: {dev.get('MarketingName')} / {ios}")
            flat = self._build_and_deploy(dev, ios, meta)
            self._need_client().kill_apps()
            st = self._need_client().fetch_status()
            self._refresh_pool_status(st)
            self.root.after(
                0,
                lambda: self.messagebox.showinfo(
                    "Ap dung",
                    f"{flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\nMo lai Zalo.",
                ),
            )

        self._run_bg("Ap dung may", job)

    def _reset_data(self):
        def job():
            apps = self._selected_apps()
            dev, ios, meta = self._pick_from_phone_pool()
            flat = self._build_and_deploy(dev, ios, meta)
            self._need_client().wipe_apps(apps, skip_keychain=False)
            st = self._need_client().fetch_status()
            self._refresh_pool_status(st)
            self.root.after(
                0,
                lambda: self.messagebox.showinfo(
                    "Dat lai",
                    f"{flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\nLogin MAT.",
                ),
            )

        self._run_bg("Dat lai", job)

    def _save_then_reset(self):
        def job():
            apps = self._selected_apps()
            client = self._need_client()
            bak = client.backup_apps(apps)
            dev, ios, meta = self._pick_from_phone_pool()
            flat = self._build_and_deploy(dev, ios, meta)
            client.wipe_apps(apps, skip_keychain=True)
            client.restore_apps(bak, apps)
            client.kill_apps()
            st = client.fetch_status()
            self._refresh_pool_status(st)
            self.root.after(
                0,
                lambda: self.messagebox.showinfo(
                    "Dat lai + Luu",
                    f"{flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\nBackup: {bak}",
                ),
            )

        self._run_bg("Dat lai + Luu", job)

    def _wipe_only(self):
        def job():
            apps = self._selected_apps()
            self._need_client().wipe_apps(apps, skip_keychain=False)
            self.root.after(0, lambda: self.messagebox.showinfo("Xoa", "\n".join(apps)))

        self._run_bg("Xoa data", job)

    def _open_zalo(self):
        def job():
            self._need_client().open_zalo()

        self._run_bg("Mo Zalo", job)

    def _workflow_cfg(self) -> dict:
        self._save_settings()
        try:
            self._save_tables()
            self._save_delays_ui()
        except Exception as e:
            self.log(f"save tables/delays: {e}")
        return {
            "bossotp_token": self.var_boss_token.get().strip(),
            "bossotp_network": self.var_boss_network.get().strip(),
            "bossotp_prefixs": self.var_boss_prefix.get().strip(),
            "rotaproxy_key": self.var_rota_key.get().strip(),
            "rotaproxy_app_id": self.var_rota_app.get().strip(),
            "achicaptcha_key": self.var_achi_key.get().strip(),
            "twocaptcha_key": self.var_2cap_key.get().strip(),
            "capsolver_key": self.var_capsolver_key.get().strip(),
            "captcha_provider": self.var_cap_provider.get().strip() or "auto",
            "privacy_mode": self.var_privacy.get().strip() or "first_only",
            "contacts_action": self.var_contacts.get().strip() or "skip",
            "appmanager_bundle": self.var_appmgr.get().strip()
            or "com.tigisoftware.appdatamanager",
        }

    def _run_pipeline(self):
        def job():
            from reg_pipeline import RegPipeline

            client = self._need_client()
            cfg = self._workflow_cfg()
            if not cfg.get("bossotp_token"):
                raise RuntimeError("Nhap BossOTP token o tab API keys.")
            if self.pipeline:
                try:
                    self.pipeline.close()
                except Exception:
                    pass
            self.pipeline = RegPipeline(client, self.catalog, log=self.log, ui_cfg=cfg)
            msg = self.pipeline.run(self._build_and_deploy)
            self.root.after(0, lambda: self.messagebox.showinfo("Pipeline", msg))

        self._run_bg("Quy trinh 18 buoc", job)

    def _stop_pipeline(self):
        def job():
            if self.pipeline:
                self.pipeline.close()
                self.pipeline = None
                self.log("Da dung pipeline.")
            else:
                self.log("Khong co pipeline.")

        self._run_bg("Dung pipeline", job)

    def _on_close(self):
        try:
            self._save_settings()
        except Exception:
            pass
        if self.pipeline:
            try:
                self.pipeline.close()
            except Exception:
                pass
        if self.client:
            try:
                self.client.close()
            except Exception:
                pass
        self.root.destroy()

    def run(self):
        self.root.mainloop()


def main() -> int:
    _log_start(f"--- start pid={os.getpid()} ---")
    try:
        tk, messagebox, scrolledtext, ttk = _safe_import_tk()
    except Exception:
        tb = traceback.format_exc()
        _write_err(tb)
        print(tb)
        try:
            input("Enter...")
        except EOFError:
            pass
        return 1

    def excepthook(etype, val, tb):
        text = "".join(traceback.format_exception(etype, val, tb))
        _write_err(text)
        try:
            r = tk.Tk()
            r.withdraw()
            messagebox.showerror("Crash", f"{val}\n{ERR_LOG}")
            r.destroy()
        except Exception:
            print(text)
        try:
            input("Enter...")
        except EOFError:
            pass

    sys.excepthook = excepthook
    try:
        app = IPfakerPC(tk, ttk, messagebox, scrolledtext)
        app.run()
        return 0
    except Exception:
        tb = traceback.format_exc()
        _write_err(tb)
        try:
            r = tk.Tk()
            r.withdraw()
            messagebox.showerror("Loi", tb[-1200:])
            r.destroy()
        except Exception:
            print(tb)
        try:
            input("Enter...")
        except EOFError:
            pass
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
