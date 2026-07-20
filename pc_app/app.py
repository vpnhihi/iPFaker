#!/usr/bin/env python3
"""
iPFaker PC — điều khiển iPFaker trên iPhone qua Wi‑Fi SSH (không cần USB).

  python pc_app/app.py
  hoặc:  pc_app\\CHAY_APP.bat
"""
from __future__ import annotations

import json
import os
import random
import sys
import threading
import traceback
from pathlib import Path

# ── path bootstrap (must be first) ─────────────────────────
ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
PC_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(PC_DIR))

ERR_LOG = PC_DIR / "last_error.txt"
START_LOG = PC_DIR / "startup.log"
SETTINGS_PATH = Path(os.environ.get("APPDATA", str(Path.home()))) / "iPFakerPC" / "settings.json"

# Force UTF-8 on Windows consoles
os.environ.setdefault("PYTHONUTF8", "1")
os.environ.setdefault("PYTHONIOENCODING", "utf-8")


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


def _safe_import_tk():
    import tkinter as tk
    from tkinter import messagebox, scrolledtext, ttk

    return tk, messagebox, scrolledtext, ttk


# Defer heavy imports until after tk is ok
_sdp = None


def sdp():
    global _sdp
    if _sdp is None:
        import select_device_profile as mod

        _sdp = mod
    return _sdp


# Theme
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

DEFAULT_DEVICE_IDS = [
    "iphone13-mini",
    "iphone14-pro",
    "iphone15-pro",
    "iphone16-pro",
    "iphone16-pro-max",
]
DEFAULT_IOS = {"18.5", "18.6", "18.6.1", "18.6.2", "17.6.1", "17.0", "16.7.10", "15.8.3"}


class IPfakerPC:
    def __init__(self, tk, ttk, messagebox, scrolledtext):
        self.tk = tk
        self.ttk = ttk
        self.messagebox = messagebox
        self.root = tk.Tk()
        self.root.title("iPFaker PC")
        self.root.geometry("1040x780")
        self.root.minsize(900, 620)
        self.root.configure(bg=BG)

        self.client = None
        self.reg_runner = None
        self._busy = False
        self._app_vars = {}
        self.catalog = {"devices": [], "ios_releases": {}}
        self.devices = []
        self._device_ids = []  # parallel to listbox lines
        self._ios_vers = []

        try:
            self.catalog = sdp().load_catalog()
            self.devices = list(self.catalog.get("devices") or [])
        except Exception as e:
            _log_start(f"catalog load fail: {e}")
            self.messagebox.showwarning(
                "Catalog",
                f"Khong doc duoc device_catalog.json:\n{e}\n\nVan mo app (chi thieu pool may).",
            )

        self._style()
        self._build_ui(scrolledtext)
        self._load_settings()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        # Catch Tk callback crashes (button handlers, after())
        self.root.report_callback_exception = self._tk_exception

    def _tk_exception(self, exc, val, tb):
        text = "".join(traceback.format_exception(exc, val, tb))
        _write_err(text)
        self.log(f"LOI UI:\n{text[-800:]}")
        try:
            self.messagebox.showerror("Loi", f"Loi giao dien (app van mo):\n\n{val}\n\nXem: {ERR_LOG}")
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

    def _build_ui(self, scrolledtext):
        tk, ttk = self.tk, self.ttk

        head = ttk.Frame(self.root)
        head.pack(fill="x", padx=12, pady=(10, 4))
        ttk.Label(head, text="iPFaker PC", style="Title.TLabel").pack(side="left")
        ttk.Label(head, text="  Wi-Fi SSH  |  spoof / wipe / reg", foreground=MUTED, background=BG).pack(
            side="left"
        )

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

        # Status
        stf = ttk.Frame(self.root, style="Card.TFrame")
        stf.pack(fill="x", padx=12, pady=4)
        ttk.Label(stf, text="Trang thai may", style="Card.TLabel", font=("Segoe UI Semibold", 10)).pack(
            anchor="w", padx=8, pady=(6, 0)
        )
        self.lbl_status = tk.Label(
            stf,
            text="Chua co du lieu — ket noi SSH roi bam Lam moi.",
            bg=PANEL,
            fg=MUTED,
            justify="left",
            font=("Consolas", 9),
            anchor="w",
        )
        self.lbl_status.pack(fill="x", padx=8, pady=(2, 8))

        # Body: devices | ios+apps
        body = ttk.Frame(self.root)
        body.pack(fill="both", expand=True, padx=12, pady=4)

        left = ttk.Frame(body, style="Card.TFrame")
        left.pack(side="left", fill="both", expand=True, padx=(0, 4))
        right = ttk.Frame(body, style="Card.TFrame")
        right.pack(side="right", fill="both", expand=True, padx=(4, 0))

        ttk.Label(left, text="Pool doi may (Ctrl+click chon nhieu)", style="Card.TLabel").pack(
            anchor="w", padx=8, pady=(8, 2)
        )
        dt = ttk.Frame(left, style="Card.TFrame")
        dt.pack(fill="x", padx=8)
        ttk.Button(dt, text="Chon tat ca", command=lambda: self._list_select_all(self.lst_dev)).pack(
            side="left", padx=2
        )
        ttk.Button(dt, text="Bo chon", command=lambda: self.lst_dev.selection_clear(0, "end")).pack(
            side="left", padx=2
        )
        ttk.Button(dt, text="Mac dinh", command=self._select_default_devices).pack(side="left", padx=2)

        self.lst_dev = tk.Listbox(
            left,
            selectmode="extended",
            bg=ENTRY_BG,
            fg=FG,
            selectbackground=ACCENT,
            font=("Segoe UI", 9),
            highlightthickness=0,
            borderwidth=0,
            activestyle="none",
        )
        sb1 = ttk.Scrollbar(left, orient="vertical", command=self.lst_dev.yview)
        self.lst_dev.configure(yscrollcommand=sb1.set)
        self.lst_dev.pack(side="left", fill="both", expand=True, padx=(8, 0), pady=6)
        sb1.pack(side="right", fill="y", pady=6, padx=(0, 8))

        self._device_ids = []
        for d in self.devices:
            did = d.get("id") or ""
            name = d.get("MarketingName") or did
            pt = d.get("ProductType") or ""
            self._device_ids.append(did)
            self.lst_dev.insert("end", f"{name}  ·  {pt}")

        ttk.Label(right, text="Pool iOS (Ctrl+click)", style="Card.TLabel").pack(anchor="w", padx=8, pady=(8, 2))
        it = ttk.Frame(right, style="Card.TFrame")
        it.pack(fill="x", padx=8)
        ttk.Button(it, text="Pho bien", command=self._select_popular_ios).pack(side="left", padx=2)
        ttk.Button(it, text="Bo chon", command=lambda: self.lst_ios.selection_clear(0, "end")).pack(
            side="left", padx=2
        )

        self.lst_ios = tk.Listbox(
            right,
            selectmode="extended",
            bg=ENTRY_BG,
            fg=FG,
            selectbackground=ACCENT,
            font=("Segoe UI", 9),
            height=12,
            highlightthickness=0,
            borderwidth=0,
            activestyle="none",
        )
        sb2 = ttk.Scrollbar(right, orient="vertical", command=self.lst_ios.yview)
        self.lst_ios.configure(yscrollcommand=sb2.set)
        ios_wrap = ttk.Frame(right, style="Card.TFrame")
        ios_wrap.pack(fill="both", expand=True, padx=8, pady=4)
        self.lst_ios.pack(in_=ios_wrap, side="left", fill="both", expand=True)
        sb2.pack(in_=ios_wrap, side="right", fill="y")

        self._ios_vers = []
        releases = list((self.catalog.get("ios_releases") or {}).keys())

        def vkey(v: str):
            out = []
            for p in v.split("."):
                try:
                    out.append(int(p))
                except ValueError:
                    out.append(0)
            return out

        for ver in sorted(releases, key=vkey, reverse=True):
            maj = ver.split(".")[0]
            if maj not in ("15", "16", "17", "18", "26"):
                continue
            self._ios_vers.append(ver)
            self.lst_ios.insert("end", f"iOS {ver}")

        ttk.Label(right, text="App muc tieu", style="Card.TLabel").pack(anchor="w", padx=8, pady=(4, 2))
        apps_f = ttk.Frame(right, style="Card.TFrame")
        apps_f.pack(fill="x", padx=8, pady=4)
        for name, bid in DEFAULT_APPS:
            v = tk.BooleanVar(value="zalo" in bid.lower())
            self._app_vars[bid] = v
            ttk.Checkbutton(apps_f, text=f"{name}", variable=v).pack(anchor="w")

        # Actions
        act = ttk.Frame(self.root, style="Card.TFrame")
        act.pack(fill="x", padx=12, pady=4)
        ar = ttk.Frame(act, style="Card.TFrame")
        ar.pack(fill="x", padx=6, pady=8)
        self._mkbtn(ar, "Ap dung may", self._apply_selected, ACCENT)
        self._mkbtn(ar, "Dat lai du lieu app", self._reset_data, RED)
        self._mkbtn(ar, "Dat lai + Luu du lieu", self._save_then_reset, GREEN)
        self._mkbtn(ar, "Chi xoa data", self._wipe_only, ORANGE)
        self._mkbtn(ar, "Mo Zalo", self._open_zalo, PANEL)

        # Reg panel
        reg = ttk.Frame(self.root, style="Card.TFrame")
        reg.pack(fill="x", padx=12, pady=4)
        ri = ttk.Frame(reg, style="Card.TFrame")
        ri.pack(fill="x", padx=8, pady=8)
        ttk.Label(ri, text="Reg Zalo tu dong (Frida)", style="Card.TLabel", font=("Segoe UI Semibold", 10)).pack(
            anchor="w"
        )

        self.var_phone = tk.StringVar(value="")
        self.var_name = tk.StringVar(value="Lab User")
        self.var_otp = tk.StringVar(value="")
        self.var_reg_wipe = tk.BooleanVar(value=True)
        self.var_reg_spoof = tk.BooleanVar(value=True)

        form = ttk.Frame(ri, style="Card.TFrame")
        form.pack(fill="x", pady=4)
        for lab, var, w in (
            ("So dien thoai", self.var_phone, 14),
            ("Ten hien thi", self.var_name, 14),
            ("OTP", self.var_otp, 10),
        ):
            f = ttk.Frame(form, style="Card.TFrame")
            f.pack(side="left", padx=(0, 10))
            ttk.Label(f, text=lab, style="Muted.TLabel").pack(anchor="w")
            ttk.Entry(f, textvariable=var, width=w).pack()

        opts = ttk.Frame(ri, style="Card.TFrame")
        opts.pack(fill="x")
        ttk.Checkbutton(opts, text="Random spoof truoc", variable=self.var_reg_spoof).pack(side="left", padx=(0, 10))
        ttk.Checkbutton(opts, text="Xoa data Zalo truoc", variable=self.var_reg_wipe).pack(side="left")

        rb = ttk.Frame(ri, style="Card.TFrame")
        rb.pack(fill="x", pady=(6, 0))
        self._mkbtn(rb, "Reg tu dong -> OTP", self._auto_reg_start, PURPLE)
        self._mkbtn(rb, "Gui OTP / Tiep reg", self._auto_reg_otp, GREEN)
        self._mkbtn(rb, "Dung Frida reg", self._auto_reg_stop, PANEL)

        # Log
        logf = ttk.Frame(self.root)
        logf.pack(fill="both", expand=True, padx=12, pady=(2, 10))
        ttk.Label(logf, text="Nhat ky", foreground=MUTED, background=BG).pack(anchor="w")
        self.log_box = scrolledtext.ScrolledText(
            logf,
            height=7,
            bg=ENTRY_BG,
            fg=FG,
            insertbackground=FG,
            font=("Consolas", 9),
            relief="flat",
            borderwidth=0,
        )
        self.log_box.pack(fill="both", expand=True)

        self._select_default_devices()
        self._select_popular_ios()
        self.log("San sang. Nhap IP + mat khau SSH roi bam Ket noi.")

    def _mkbtn(self, parent, text, cmd, color):
        b = self.tk.Button(
            parent,
            text=text,
            command=cmd,
            bg=color if color != PANEL else "#2a2f3a",
            fg="#ffffff",
            activebackground=ACCENT,
            activeforeground="#fff",
            relief="flat",
            padx=10,
            pady=6,
            font=("Segoe UI Semibold", 9),
            cursor="hand2",
        )
        b.pack(side="left", padx=3)

    def _list_select_all(self, lb):
        lb.selection_set(0, "end")

    def _select_default_devices(self):
        self.lst_dev.selection_clear(0, "end")
        for i, did in enumerate(self._device_ids):
            if did in DEFAULT_DEVICE_IDS:
                self.lst_dev.selection_set(i)

    def _select_popular_ios(self):
        self.lst_ios.selection_clear(0, "end")
        for i, ver in enumerate(self._ios_vers):
            if ver in DEFAULT_IOS or ver.startswith("18.5") or ver.startswith("18.6"):
                self.lst_ios.selection_set(i)

    # ── settings ───────────────────────────────────────────
    def _load_settings(self):
        try:
            if not SETTINGS_PATH.exists():
                return
            data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            if data.get("host"):
                self.var_host.set(data["host"])
            if data.get("user"):
                self.var_user.set(data["user"])
            if data.get("port"):
                self.var_port.set(str(data["port"]))
            if data.get("remember_pass") and data.get("password"):
                self.var_pass.set(data["password"])
            if data.get("phone"):
                self.var_phone.set(data["phone"])
            if data.get("reg_name"):
                self.var_name.set(data["reg_name"])

            # Restore selection — but NEVER select all 50 (was causing lag/crash feel)
            saved_dev = data.get("devices") or []
            if saved_dev and len(saved_dev) <= 20:
                self.lst_dev.selection_clear(0, "end")
                for i, did in enumerate(self._device_ids):
                    if did in saved_dev:
                        self.lst_dev.selection_set(i)
            saved_ios = data.get("ios") or []
            if saved_ios and len(saved_ios) <= 30:
                self.lst_ios.selection_clear(0, "end")
                for i, ver in enumerate(self._ios_vers):
                    if ver in saved_ios:
                        self.lst_ios.selection_set(i)
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
                "devices": self._selected_device_ids(),
                "ios": self._selected_ios(),
            }
            SETTINGS_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")
        except Exception as e:
            self.log(f"Luu settings loi: {e}")

    # ── log / status ───────────────────────────────────────
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
        def _do():
            self.lbl_link.configure(text=text, fg=GREEN if ok else ORANGE)

        self.root.after(0, _do)

    def _set_status_text(self, txt: str, ok: bool = True):
        def _do():
            self.lbl_status.configure(text=txt, fg=FG if ok else RED)

        self.root.after(0, _do)

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
                self.root.after(0, lambda: self.messagebox.showerror(title, f"{e}\n\nChi tiet: {ERR_LOG}"))
            finally:
                self._busy = False
                self.log(f"—— xong: {title} ——\n")

        threading.Thread(target=wrap, daemon=True).start()

    def _need_client(self):
        from device_client import DeviceClient  # noqa: F401

        if not self.client or not self.client.connected:
            raise RuntimeError("Chua ket noi. Nhap IP + mat khau SSH roi bam Ket noi.")
        return self.client

    def _selected_device_ids(self):
        ids = []
        for i in self.lst_dev.curselection():
            if 0 <= i < len(self._device_ids):
                ids.append(self._device_ids[i])
        return ids

    def _selected_ios(self):
        vers = []
        for i in self.lst_ios.curselection():
            if 0 <= i < len(self._ios_vers):
                vers.append(self._ios_vers[i])
        return vers

    def _selected_apps(self):
        apps = [k for k, v in self._app_vars.items() if v.get()]
        return apps or ["vn.com.vng.zingalo"]

    def _valid_pairs(self):
        cat = self.catalog
        pairs = []
        mod = sdp()
        for did in self._selected_device_ids():
            dev = next((d for d in self.devices if d.get("id") == did), None)
            if not dev:
                continue
            supported = set(mod.device_supported_ios(dev, cat))
            for ios in self._selected_ios():
                if ios not in (cat.get("ios_releases") or {}):
                    continue
                if supported and ios not in supported:
                    continue
                pairs.append((dev, ios, cat["ios_releases"][ios]))
        return pairs

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
            self._apply_status(st)

        self._run_bg("Ket noi", job)

    def _apply_status(self, st):
        if not st.ok:
            self._set_status_text(f"Loi: {st.message}", ok=False)
            return
        txt = (
            f"Goi: {st.package}\n"
            f"Spoof: {st.marketing or '?'} ({st.product_type or '?'})  iOS {st.ios or '?'} ({st.build or '?'})\n"
            f"Serial: {st.serial or '?'}  Model: {st.model or '?'}  IMEI: {st.imei or '?'}"
        )
        self._set_status_text(txt, ok=True)

    def _disconnect(self):
        if self.client:
            try:
                self.client.close()
            except Exception:
                pass
            self.client = None
        self._set_link(False, "● Da ngat")
        self.log("Da ngat ket noi.")

    def _refresh_status(self):
        def job():
            st = self._need_client().fetch_status()
            self._apply_status(st)
            self.log(f"Refresh: {st.marketing} / iOS {st.ios}")

        self._run_bg("Lam moi", job)

    def _apply_selected(self):
        def job():
            pairs = self._valid_pairs()
            if not pairs:
                raise RuntimeError("Khong co cap may+iOS hop le. Chon pool (Ctrl+click).")
            dev, ios, meta = random.choice(pairs)
            self.log(f"Ap dung: {dev.get('MarketingName')} + iOS {ios}")
            flat = self._build_and_deploy(dev, ios, meta)
            self._need_client().kill_apps()
            st = self._need_client().fetch_status()
            self._apply_status(st)
            self.root.after(
                0,
                lambda: self.messagebox.showinfo(
                    "Ap dung",
                    f"{flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\n"
                    f"Serial {flat.get('SerialNumber')}\nMo lai Zalo.",
                ),
            )

        self._run_bg("Ap dung may", job)

    def _reset_data(self):
        def job():
            pairs = self._valid_pairs()
            if not pairs:
                raise RuntimeError("Pool may/iOS trong.")
            apps = self._selected_apps()
            dev, ios, meta = random.choice(pairs)
            flat = self._build_and_deploy(dev, ios, meta)
            self._need_client().wipe_apps(apps, skip_keychain=False)
            st = self._need_client().fetch_status()
            self._apply_status(st)
            self.root.after(
                0,
                lambda: self.messagebox.showinfo(
                    "Dat lai",
                    f"May moi: {flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\nLogin MAT.",
                ),
            )

        self._run_bg("Dat lai du lieu app", job)

    def _save_then_reset(self):
        def job():
            pairs = self._valid_pairs()
            if not pairs:
                raise RuntimeError("Pool may/iOS trong.")
            apps = self._selected_apps()
            client = self._need_client()
            bak = client.backup_apps(apps)
            self.log(f"Backup: {bak}")
            dev, ios, meta = random.choice(pairs)
            flat = self._build_and_deploy(dev, ios, meta)
            client.wipe_apps(apps, skip_keychain=True)
            client.restore_apps(bak, apps)
            client.kill_apps()
            st = client.fetch_status()
            self._apply_status(st)
            self.root.after(
                0,
                lambda: self.messagebox.showinfo(
                    "Dat lai + Luu",
                    f"{flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\n"
                    f"Login duoc khoi phuc.\n{bak}",
                ),
            )

        self._run_bg("Dat lai + Luu du lieu", job)

    def _wipe_only(self):
        def job():
            apps = self._selected_apps()
            self._need_client().wipe_apps(apps, skip_keychain=False)
            self.root.after(0, lambda: self.messagebox.showinfo("Xoa data", "Da xoa:\n" + "\n".join(apps)))

        self._run_bg("Xoa data", job)

    def _open_zalo(self):
        def job():
            self._need_client().open_zalo()
            self.log("Mo Zalo.")

        self._run_bg("Mo Zalo", job)

    def _auto_reg_start(self):
        phone = self.var_phone.get().strip()
        if not phone:
            self.messagebox.showwarning("Reg", "Nhap so dien thoai.")
            return
        self._save_settings()

        def job():
            from auto_reg import AutoRegRunner

            client = self._need_client()
            if self.var_reg_spoof.get():
                pairs = self._valid_pairs()
                if not pairs:
                    raise RuntimeError("Random spoof bat nhung pool khong hop le.")
                dev, ios, meta = random.choice(pairs)
                self.log(f"Reg spoof {dev.get('MarketingName')} / {ios}")
                self._build_and_deploy(dev, ios, meta)
            if self.var_reg_wipe.get():
                self.log("Wipe Zalo…")
                client.wipe_apps(["vn.com.vng.zingalo", "com.zing.zalo"], skip_keychain=False)
            if self.reg_runner:
                try:
                    self.reg_runner.close()
                except Exception:
                    pass
            self.reg_runner = AutoRegRunner(client, log=self.log)
            self.reg_runner.run_full_until_otp(phone)
            self.root.after(
                0,
                lambda: self.messagebox.showinfo(
                    "Reg",
                    f"Da dien SDT {phone}.\nNhap OTP tren may hoac o OTP + Gui OTP.",
                ),
            )

        self._run_bg("Reg tu dong", job)

    def _auto_reg_otp(self):
        def job():
            if not self.reg_runner or not getattr(self.reg_runner, "_script", None):
                raise RuntimeError("Chua chay Reg tu dong hoac Frida da dut.")
            self.reg_runner.submit_otp_and_finish(
                otp=self.var_otp.get().strip(),
                name=self.var_name.get().strip() or "Lab User",
            )
            self.root.after(0, lambda: self.messagebox.showinfo("OTP", "Da gui buoc tiep. Kiem tra Zalo."))

        self._run_bg("Gui OTP", job)

    def _auto_reg_stop(self):
        def job():
            if self.reg_runner:
                self.reg_runner.close()
                self.reg_runner = None
                self.log("Da dung Frida reg.")
            else:
                self.log("Khong co session reg.")

        self._run_bg("Dung reg", job)

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
    _log_start(f"--- start pid={os.getpid()} py={sys.version} ---")
    try:
        tk, messagebox, scrolledtext, ttk = _safe_import_tk()
    except Exception:
        tb = traceback.format_exc()
        _write_err(tb)
        print(tb)
        print("Thieu tkinter. Cai lai Python (tick tcl/tk).")
        try:
            input("Enter de dong...")
        except EOFError:
            pass
        return 1

    # Global hooks
    def excepthook(etype, val, tb):
        text = "".join(traceback.format_exception(etype, val, tb))
        _write_err(text)
        _log_start(text)
        try:
            r = tk.Tk()
            r.withdraw()
            messagebox.showerror("iPFaker PC crash", f"{val}\n\n{ERR_LOG}")
            r.destroy()
        except Exception:
            print(text)
        try:
            input("Enter de dong...")
        except EOFError:
            pass

    sys.excepthook = excepthook

    try:
        app = IPfakerPC(tk, ttk, messagebox, scrolledtext)
        _log_start("UI created OK")
        app.run()
        _log_start("mainloop exit OK")
        return 0
    except Exception:
        tb = traceback.format_exc()
        _write_err(tb)
        _log_start(tb)
        try:
            r = tk.Tk()
            r.withdraw()
            messagebox.showerror("iPFaker PC", f"Loi khoi dong:\n{tb[-1200:]}\n\n{ERR_LOG}")
            r.destroy()
        except Exception:
            print(tb)
        try:
            input("Enter de dong...")
        except EOFError:
            pass
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
