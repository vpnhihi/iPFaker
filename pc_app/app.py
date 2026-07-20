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
        self.root.geometry("980x820")
        self.root.minsize(880, 680)
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

        # Notebook: Dieu khien | API
        nb = ttk.Notebook(self.root)
        nb.pack(fill="both", expand=True, padx=12, pady=4)

        tab_ctrl = ttk.Frame(nb, style="Card.TFrame")
        tab_api = ttk.Frame(nb, style="Card.TFrame")
        nb.add(tab_ctrl, text="  Dieu khien  ")
        nb.add(tab_api, text="  API SMS / Captcha  ")

        # --- Control tab ---
        ttk.Label(
            tab_ctrl,
            text="May + iOS lay tu pool tren dien thoai (khong chon o day).",
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

        # Reg
        reg = ttk.Frame(tab_ctrl, style="Card.TFrame")
        reg.pack(fill="x", padx=10, pady=6)
        ttk.Label(reg, text="Reg Zalo tu dong", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(
            anchor="w", pady=(4, 2)
        )
        ttk.Label(
            reg,
            text="Bat API SMS de tu lay SDT+OTP · bat AchiCaptcha de giai captcha (chup man hinh).",
            style="Muted.TLabel",
        ).pack(anchor="w")

        self.var_phone = tk.StringVar(value="")
        self.var_name = tk.StringVar(value="Lab User")
        self.var_otp = tk.StringVar(value="")
        self.var_reg_wipe = tk.BooleanVar(value=True)
        self.var_reg_spoof = tk.BooleanVar(value=True)
        self.var_use_sms = tk.BooleanVar(value=True)
        self.var_use_captcha = tk.BooleanVar(value=True)

        form = ttk.Frame(reg, style="Card.TFrame")
        form.pack(fill="x", pady=6)
        for lab, var, w in (
            ("SDT (hoac de trong neu dung API)", self.var_phone, 22),
            ("Ten hien thi", self.var_name, 14),
            ("OTP tay", self.var_otp, 10),
        ):
            f = ttk.Frame(form, style="Card.TFrame")
            f.pack(side="left", padx=(0, 10))
            ttk.Label(f, text=lab, style="Muted.TLabel").pack(anchor="w")
            ttk.Entry(f, textvariable=var, width=w).pack()

        opts = ttk.Frame(reg, style="Card.TFrame")
        opts.pack(fill="x")
        for text, var in (
            ("Random spoof (pool DT)", self.var_reg_spoof),
            ("Xoa data Zalo truoc", self.var_reg_wipe),
            ("Dung API SMS (SDT+OTP)", self.var_use_sms),
            ("Dung AchiCaptcha", self.var_use_captcha),
        ):
            ttk.Checkbutton(opts, text=text, variable=var).pack(side="left", padx=(0, 12))

        rb = ttk.Frame(reg, style="Card.TFrame")
        rb.pack(fill="x", pady=8)
        self._mkbtn(rb, "Reg tu dong (full)", self._auto_reg_start, PURPLE)
        self._mkbtn(rb, "Gui OTP / Tiep", self._auto_reg_otp, GREEN)
        self._mkbtn(rb, "Dung Frida", self._auto_reg_stop, PANEL)

        # --- API tab ---
        api_in = ttk.Frame(tab_api, style="Card.TFrame")
        api_in.pack(fill="both", expand=True, padx=10, pady=10)

        ttk.Label(api_in, text="API thue so / OTP", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(
            anchor="w"
        )
        self.var_sms_enabled = tk.BooleanVar(value=False)
        self.var_sms_key = tk.StringVar(value="")
        self.var_sms_rent = tk.StringVar(value="")
        self.var_sms_otp = tk.StringVar(value="")
        self.var_sms_cancel = tk.StringVar(value="")
        self.var_sms_phone_path = tk.StringVar(value="phone|data.phone|number")
        self.var_sms_order_path = tk.StringVar(value="id|data.id|order_id|request_id")
        self.var_sms_otp_path = tk.StringVar(value="otp|code|data.otp|data.code|message")

        ttk.Checkbutton(api_in, text="Bat API SMS", variable=self.var_sms_enabled).pack(anchor="w", pady=2)
        self._api_field(api_in, "API key SMS", self.var_sms_key, 56, show="*")
        self._api_field(
            api_in,
            "URL thue so  (placeholder: {api_key})",
            self.var_sms_rent,
            70,
        )
        self._api_field(
            api_in,
            "URL lay OTP  (placeholder: {api_key} {order_id})",
            self.var_sms_otp,
            70,
        )
        self._api_field(api_in, "URL huy so (optional)", self.var_sms_cancel, 70)
        self._api_field(api_in, "JSON path SDT", self.var_sms_phone_path, 40)
        self._api_field(api_in, "JSON path order id", self.var_sms_order_path, 40)
        self._api_field(api_in, "JSON path OTP", self.var_sms_otp_path, 40)

        ttk.Label(api_in, text="AchiCaptcha", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(
            anchor="w", pady=(12, 2)
        )
        self.var_cap_enabled = tk.BooleanVar(value=False)
        self.var_cap_key = tk.StringVar(value="")
        self.var_cap_create = tk.StringVar(value="https://achicaptcha.com/api/createTask")
        self.var_cap_result = tk.StringVar(value="https://achicaptcha.com/api/getTaskResult")

        ttk.Checkbutton(api_in, text="Bat AchiCaptcha", variable=self.var_cap_enabled).pack(anchor="w")
        self._api_field(api_in, "API key AchiCaptcha", self.var_cap_key, 56, show="*")
        self._api_field(api_in, "URL createTask", self.var_cap_create, 70)
        self._api_field(api_in, "URL getTaskResult", self.var_cap_result, 70)

        ttk.Button(api_in, text="Luu cau hinh API", command=self._save_settings).pack(anchor="w", pady=10)
        ttk.Label(
            api_in,
            text="Huong dan: dien URL dung voi nha cung cap cua ban. Placeholder {api_key}, {order_id}.\n"
            "AchiCaptcha mac dinh kieu clientKey + ImageToTextTask (doi URL neu docs khac).",
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
            for k, var in (
                ("host", self.var_host),
                ("user", self.var_user),
                ("password", self.var_pass),
                ("phone", self.var_phone),
                ("reg_name", self.var_name),
                ("sms_api_key", self.var_sms_key),
                ("sms_rent_url", self.var_sms_rent),
                ("sms_otp_url", self.var_sms_otp),
                ("sms_cancel_url", self.var_sms_cancel),
                ("sms_phone_path", self.var_sms_phone_path),
                ("sms_order_path", self.var_sms_order_path),
                ("sms_otp_path", self.var_sms_otp_path),
                ("captcha_api_key", self.var_cap_key),
                ("captcha_create_url", self.var_cap_create),
                ("captcha_result_url", self.var_cap_result),
            ):
                if data.get(k):
                    var.set(str(data[k]))
            if data.get("port"):
                self.var_port.set(str(data["port"]))
            if "sms_enabled" in data:
                self.var_sms_enabled.set(bool(data["sms_enabled"]))
            if "captcha_enabled" in data:
                self.var_cap_enabled.set(bool(data["captcha_enabled"]))
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
                "phone": self.var_phone.get().strip(),
                "reg_name": self.var_name.get().strip(),
                "sms_enabled": self.var_sms_enabled.get(),
                "sms_api_key": self.var_sms_key.get().strip(),
                "sms_rent_url": self.var_sms_rent.get().strip(),
                "sms_otp_url": self.var_sms_otp.get().strip(),
                "sms_cancel_url": self.var_sms_cancel.get().strip(),
                "sms_phone_path": self.var_sms_phone_path.get().strip(),
                "sms_order_path": self.var_sms_order_path.get().strip(),
                "sms_otp_path": self.var_sms_otp_path.get().strip(),
                "captcha_enabled": self.var_cap_enabled.get(),
                "captcha_api_key": self.var_cap_key.get().strip(),
                "captcha_create_url": self.var_cap_create.get().strip(),
                "captcha_result_url": self.var_cap_result.get().strip(),
            }
            # write without BOM
            SETTINGS_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            self._settings = data
            self.log(f"Da luu settings → {SETTINGS_PATH}")
        except Exception as e:
            self.log(f"Luu settings loi: {e}")

    def _api_cfg(self) -> dict:
        self._save_settings()
        return dict(self._settings)

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

    def _auto_reg_start(self):
        self._save_settings()

        def job():
            from auto_reg import AutoRegRunner
            from captcha_api import CaptchaApi
            from sms_api import SmsApi

            client = self._need_client()
            cfg = self._api_cfg()
            sms = SmsApi(cfg, log=self.log)
            cap = CaptchaApi(cfg, log=self.log)

            # spoof from phone pool
            if self.var_reg_spoof.get():
                dev, ios, meta = self._pick_from_phone_pool()
                self.log(f"Reg spoof {dev.get('MarketingName')} / {ios}")
                self._build_and_deploy(dev, ios, meta)
            if self.var_reg_wipe.get():
                client.wipe_apps(["vn.com.vng.zingalo", "com.zing.zalo"], skip_keychain=False)

            # phone from SMS API or manual
            phone = self.var_phone.get().strip()
            order_id = None
            if self.var_use_sms.get() and self.var_sms_enabled.get() and sms.enabled:
                order = sms.rent_number()
                phone = order.phone
                order_id = order.order_id
                self.root.after(0, lambda p=phone: self.var_phone.set(p))
                self.log(f"API SMS → {phone} (order {order_id})")
            if not phone:
                raise RuntimeError("Can SDT: nhap tay hoac bat API SMS + URL thue so.")

            if self.reg_runner:
                try:
                    self.reg_runner.close()
                except Exception:
                    pass
            self.reg_runner = AutoRegRunner(client, log=self.log)
            self.reg_runner.run_full_until_otp(phone)

            # captcha attempt: screenshot + solve
            if self.var_use_captcha.get() and self.var_cap_enabled.get() and cap.enabled:
                self._try_solve_captcha(client, cap)

            # OTP from API
            otp = self.var_otp.get().strip()
            if self.var_use_sms.get() and self.var_sms_enabled.get() and sms.enabled and order_id:
                self.log("Cho OTP tu API SMS…")
                try:
                    otp = sms.wait_otp(order_id, timeout=180)
                    self.root.after(0, lambda o=otp: self.var_otp.set(o))
                except Exception as e:
                    self.log(f"OTP API: {e} — nhap tay neu can")

            if otp:
                self.reg_runner.submit_otp_and_finish(
                    otp=otp, name=self.var_name.get().strip() or "Lab User"
                )
                # second captcha pass after OTP
                if self.var_use_captcha.get() and self.var_cap_enabled.get() and cap.enabled:
                    self._try_solve_captcha(client, cap)
                msg = f"Reg xong luong UI.\nSDT {phone}\nOTP {otp}"
            else:
                msg = f"Da dien SDT {phone}.\nCho OTP: nhap o OTP + Gui OTP, hoac doi API."

            self.root.after(0, lambda m=msg: self.messagebox.showinfo("Reg", m))

        self._run_bg("Reg tu dong", job)

    def _try_solve_captcha(self, client, cap) -> None:
        """Screenshot device → AchiCaptcha image solve → type into Zalo via Frida."""
        try:
            remote = "/var/mobile/Library/iPFaker/logs/cap_screen.png"
            # iOS screencapture variants
            out = client.run(
                f"rm -f {remote}; "
                f"(screencapture {remote} 2>/dev/null || "
                f"screencapture -t png {remote} 2>/dev/null || "
                f"/var/jb/usr/bin/screencapture {remote} 2>/dev/null || true); "
                f"ls -la {remote} 2>/dev/null || echo NO_SHOT",
                sudo=True,
                timeout=30,
            )
            self.log(f"Screenshot: {out[-200:]}")
            if "NO_SHOT" in out or "No such" in out:
                self.log("Khong chup duoc man hinh — captcha can tay hoac cai screencapture.")
                return
            # pull via sftp
            local = PC_DIR / "last_captcha.png"
            c = client._require()
            sftp = c.open_sftp()
            try:
                sftp.get(remote, str(local))
            finally:
                sftp.close()
            if not local.is_file() or local.stat().st_size < 100:
                self.log("File screenshot rong.")
                return
            text = cap.solve_image_file(str(local))
            self.log(f"Captcha text: {text}")
            if self.reg_runner and self.reg_runner._script:
                self.reg_runner._rpc("settext", text)
                self.reg_runner._tap_any(
                    ["Xac nhan", "Xác nhận", "Tiep tuc", "Tiếp tục", "OK", "Submit", "Confirm"],
                    pause=1.5,
                )
        except Exception as e:
            self.log(f"Captcha auto: {e}")

    def _auto_reg_otp(self):
        def job():
            if not self.reg_runner or not getattr(self.reg_runner, "_script", None):
                raise RuntimeError("Chua chay Reg tu dong.")
            self.reg_runner.submit_otp_and_finish(
                otp=self.var_otp.get().strip(),
                name=self.var_name.get().strip() or "Lab User",
            )
            cfg = self._api_cfg()
            if self.var_use_captcha.get() and self.var_cap_enabled.get():
                from captcha_api import CaptchaApi

                self._try_solve_captcha(self._need_client(), CaptchaApi(cfg, log=self.log))
            self.root.after(0, lambda: self.messagebox.showinfo("OTP", "Da gui buoc tiep."))

        self._run_bg("Gui OTP", job)

    def _auto_reg_stop(self):
        def job():
            if self.reg_runner:
                self.reg_runner.close()
                self.reg_runner = None
                self.log("Da dung Frida.")
            else:
                self.log("Khong co session.")

        self._run_bg("Dung", job)

    def _on_close(self):
        try:
            self._save_settings()
        except Exception:
            pass
        if self.reg_runner:
            try:
                self.reg_runner.close()
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
