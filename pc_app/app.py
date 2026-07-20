#!/usr/bin/env python3
"""
iPFaker PC — điều khiển iPFaker trên iPhone qua Wi‑Fi SSH (không cần USB).

  python pc_app/app.py
  hoặc:  pc_app\\run_ipfaker_pc.bat
"""
from __future__ import annotations

import json
import os
import random
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, scrolledtext, ttk

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from device_client import DeviceClient, DeviceStatus  # noqa: E402
from auto_reg import AutoRegError, AutoRegRunner  # noqa: E402

# Reuse profile builder from repo
import select_device_profile as sdp  # noqa: E402

SETTINGS_PATH = Path(os.environ.get("APPDATA", str(Path.home()))) / "iPFakerPC" / "settings.json"

# Dark theme colors
BG = "#0f1115"
PANEL = "#171a21"
FG = "#e8eaed"
MUTED = "#9aa0a6"
ACCENT = "#3b82f6"
GREEN = "#22c55e"
ORANGE = "#f59e0b"
RED = "#ef4444"
ENTRY_BG = "#1f2430"
SEL = "#2563eb"

DEFAULT_APPS = [
    ("Zalo (VN)", "vn.com.vng.zingalo"),
    ("Zalo (alt)", "com.zing.zalo"),
    ("Bản đồ", "com.apple.Maps"),
    ("Thời tiết", "com.apple.weather"),
]


class IPfakerPC(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("iPFaker PC — Điều khiển máy")
        self.geometry("1100x820")
        self.minsize(960, 700)
        self.configure(bg=BG)
        self.client: DeviceClient | None = None
        self.reg_runner: AutoRegRunner | None = None
        self.catalog = sdp.load_catalog()
        self.devices = list(self.catalog.get("devices") or [])
        self._busy = False
        self._device_vars: dict[str, tk.BooleanVar] = {}
        self._ios_vars: dict[str, tk.BooleanVar] = {}
        self._app_vars: dict[str, tk.BooleanVar] = {}

        self._style()
        self._build_ui()
        self._load_settings()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── style ──────────────────────────────────────────────
    def _style(self) -> None:
        st = ttk.Style(self)
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
        st.configure("Status.TLabel", background=PANEL, foreground=GREEN, font=("Consolas", 10))
        st.configure("TButton", font=("Segoe UI", 10), padding=6)
        st.configure("Accent.TButton", font=("Segoe UI Semibold", 10))
        st.configure("TCheckbutton", background=PANEL, foreground=FG)
        st.configure("TEntry", fieldbackground=ENTRY_BG, foreground=FG)
        st.configure("TNotebook", background=BG, borderwidth=0)
        st.configure("TNotebook.Tab", background=PANEL, foreground=FG, padding=[12, 6])
        st.map("TNotebook.Tab", background=[("selected", ACCENT)], foreground=[("selected", "#fff")])

    # ── UI ─────────────────────────────────────────────────
    def _build_ui(self) -> None:
        head = ttk.Frame(self)
        head.pack(fill="x", padx=14, pady=(12, 6))
        ttk.Label(head, text="iPFaker PC", style="Title.TLabel").pack(side="left")
        ttk.Label(
            head,
            text="  Wi‑Fi SSH · không cần USB · điều khiển spoof / wipe / lưu data",
            foreground=MUTED,
            background=BG,
        ).pack(side="left", padx=8)

        # Connection bar
        conn = ttk.Frame(self, style="Card.TFrame")
        conn.pack(fill="x", padx=14, pady=6)
        inner = ttk.Frame(conn, style="Card.TFrame")
        inner.pack(fill="x", padx=10, pady=10)

        self.var_host = tk.StringVar(value="192.168.1.10")
        self.var_user = tk.StringVar(value="mobile")
        self.var_pass = tk.StringVar(value="")
        self.var_port = tk.StringVar(value="22")

        def lab_ent(parent, text, var, show=None, w=16):
            f = ttk.Frame(parent, style="Card.TFrame")
            f.pack(side="left", padx=(0, 12))
            ttk.Label(f, text=text, style="Muted.TLabel").pack(anchor="w")
            e = ttk.Entry(f, textvariable=var, width=w, show=show)
            e.pack()
            return e

        lab_ent(inner, "IP máy (Wi‑Fi)", self.var_host, w=16)
        lab_ent(inner, "User", self.var_user, w=10)
        lab_ent(inner, "Mật khẩu SSH", self.var_pass, show="•", w=14)
        lab_ent(inner, "Port", self.var_port, w=6)

        btns = ttk.Frame(inner, style="Card.TFrame")
        btns.pack(side="left", padx=8)
        ttk.Label(btns, text=" ", style="Muted.TLabel").pack()
        ttk.Button(btns, text="Kết nối", command=self._connect).pack(side="left", padx=2)
        ttk.Button(btns, text="Làm mới", command=self._refresh_status).pack(side="left", padx=2)
        ttk.Button(btns, text="Ngắt", command=self._disconnect).pack(side="left", padx=2)

        self.lbl_link = ttk.Label(inner, text="● Chưa kết nối", style="Status.TLabel", foreground=ORANGE)
        self.lbl_link.pack(side="right", padx=8)

        # Status card
        stf = ttk.Frame(self, style="Card.TFrame")
        stf.pack(fill="x", padx=14, pady=6)
        st_in = ttk.Frame(stf, style="Card.TFrame")
        st_in.pack(fill="x", padx=10, pady=8)
        ttk.Label(st_in, text="Trạng thái máy", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(anchor="w")
        self.lbl_status = ttk.Label(
            st_in,
            text="Chưa có dữ liệu — kết nối SSH rồi bấm Làm mới.",
            style="Muted.TLabel",
            justify="left",
        )
        self.lbl_status.pack(anchor="w", pady=(4, 0))

        # Main split
        body = ttk.Frame(self)
        body.pack(fill="both", expand=True, padx=14, pady=6)

        left = ttk.Frame(body, style="Card.TFrame")
        left.pack(side="left", fill="both", expand=True, padx=(0, 6))
        right = ttk.Frame(body, style="Card.TFrame")
        right.pack(side="right", fill="both", expand=True, padx=(6, 0))

        # Device pool
        ttk.Label(left, text="Pool đời máy (chọn nhiều)", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(
            anchor="w", padx=10, pady=(10, 4)
        )
        dev_tools = ttk.Frame(left, style="Card.TFrame")
        dev_tools.pack(fill="x", padx=10)
        ttk.Button(dev_tools, text="Chọn tất cả", command=lambda: self._set_all_devices(True)).pack(side="left", padx=2)
        ttk.Button(dev_tools, text="Bỏ chọn", command=lambda: self._set_all_devices(False)).pack(side="left", padx=2)

        dev_wrap = ttk.Frame(left, style="Card.TFrame")
        dev_wrap.pack(fill="both", expand=True, padx=8, pady=4)
        self.dev_canvas = tk.Canvas(dev_wrap, bg=PANEL, highlightthickness=0)
        dev_scroll = ttk.Scrollbar(dev_wrap, orient="vertical", command=self.dev_canvas.yview)
        self.dev_inner = ttk.Frame(self.dev_canvas, style="Card.TFrame")
        self.dev_inner.bind(
            "<Configure>", lambda e: self.dev_canvas.configure(scrollregion=self.dev_canvas.bbox("all"))
        )
        self.dev_canvas.create_window((0, 0), window=self.dev_inner, anchor="nw")
        self.dev_canvas.configure(yscrollcommand=dev_scroll.set)
        self.dev_canvas.pack(side="left", fill="both", expand=True)
        dev_scroll.pack(side="right", fill="y")
        self._fill_devices()

        # iOS pool
        ttk.Label(right, text="Pool iOS (chọn nhiều)", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(
            anchor="w", padx=10, pady=(10, 4)
        )
        ios_tools = ttk.Frame(right, style="Card.TFrame")
        ios_tools.pack(fill="x", padx=10)
        ttk.Button(ios_tools, text="Chọn phổ biến", command=self._select_popular_ios).pack(side="left", padx=2)
        ttk.Button(ios_tools, text="Bỏ chọn", command=lambda: self._set_all_ios(False)).pack(side="left", padx=2)

        ios_wrap = ttk.Frame(right, style="Card.TFrame")
        ios_wrap.pack(fill="both", expand=True, padx=8, pady=4)
        self.ios_canvas = tk.Canvas(ios_wrap, bg=PANEL, highlightthickness=0, height=180)
        ios_scroll = ttk.Scrollbar(ios_wrap, orient="vertical", command=self.ios_canvas.yview)
        self.ios_inner = ttk.Frame(self.ios_canvas, style="Card.TFrame")
        self.ios_inner.bind(
            "<Configure>", lambda e: self.ios_canvas.configure(scrollregion=self.ios_canvas.bbox("all"))
        )
        self.ios_canvas.create_window((0, 0), window=self.ios_inner, anchor="nw")
        self.ios_canvas.configure(yscrollcommand=ios_scroll.set)
        self.ios_canvas.pack(side="left", fill="both", expand=True)
        ios_scroll.pack(side="right", fill="y")
        self._fill_ios()

        # Apps
        ttk.Label(right, text="App mục tiêu (lưu / xóa / reset)", style="Card.TLabel", font=("Segoe UI Semibold", 11)).pack(
            anchor="w", padx=10, pady=(8, 4)
        )
        apps_f = ttk.Frame(right, style="Card.TFrame")
        apps_f.pack(fill="x", padx=10, pady=4)
        for name, bid in DEFAULT_APPS:
            v = tk.BooleanVar(value=("zalo" in bid.lower() or bid.endswith("Maps") or bid.endswith("weather")))
            # default: zalo on, maps/weather on for wipe pool parity with phone
            if "zalo" in bid.lower():
                v.set(True)
            elif bid in ("com.apple.Maps", "com.apple.weather"):
                v.set(False)
            self._app_vars[bid] = v
            ttk.Checkbutton(apps_f, text=f"{name}  ({bid})", variable=v).pack(anchor="w")

        # Action buttons
        act = ttk.Frame(self, style="Card.TFrame")
        act.pack(fill="x", padx=14, pady=6)
        row = ttk.Frame(act, style="Card.TFrame")
        row.pack(fill="x", padx=10, pady=10)

        self._btn("Áp dụng máy đã chọn", self._apply_selected, row, ACCENT)
        self._btn("Đặt lại dữ liệu app", self._reset_data, row, RED)
        self._btn("Đặt lại + Lưu dữ liệu", self._save_then_reset, row, GREEN)
        self._btn("Chỉ xóa data app", self._wipe_only, row, ORANGE)
        self._btn("Mở Zalo", self._open_zalo, row, None)

        # ── Reg tự động ───────────────────────────────────
        reg = ttk.Frame(self, style="Card.TFrame")
        reg.pack(fill="x", padx=14, pady=6)
        reg_in = ttk.Frame(reg, style="Card.TFrame")
        reg_in.pack(fill="x", padx=10, pady=10)

        ttk.Label(
            reg_in,
            text="Reg Zalo tự động (Frida UI)",
            style="Card.TLabel",
            font=("Segoe UI Semibold", 11),
        ).pack(anchor="w")
        ttk.Label(
            reg_in,
            text="Mở khóa màn hình · Zalo sạch · spoof đã áp dụng · PC cùng Wi‑Fi (port 27042 cho Gadget)",
            style="Muted.TLabel",
        ).pack(anchor="w", pady=(2, 8))

        form = ttk.Frame(reg_in, style="Card.TFrame")
        form.pack(fill="x")

        self.var_phone = tk.StringVar(value="")
        self.var_name = tk.StringVar(value="Lab User")
        self.var_otp = tk.StringVar(value="")
        self.var_reg_wipe = tk.BooleanVar(value=True)
        self.var_reg_spoof = tk.BooleanVar(value=True)

        def _field(parent, label, var, w=18, show=None):
            f = ttk.Frame(parent, style="Card.TFrame")
            f.pack(side="left", padx=(0, 12))
            ttk.Label(f, text=label, style="Muted.TLabel").pack(anchor="w")
            ttk.Entry(f, textvariable=var, width=w, show=show).pack()

        _field(form, "Số điện thoại", self.var_phone, 16)
        _field(form, "Tên hiển thị", self.var_name, 16)
        _field(form, "OTP (sau khi nhận SMS)", self.var_otp, 12)

        opts = ttk.Frame(reg_in, style="Card.TFrame")
        opts.pack(fill="x", pady=(8, 4))
        ttk.Checkbutton(
            opts,
            text="Random spoof trước (pool máy+iOS)",
            variable=self.var_reg_spoof,
        ).pack(side="left", padx=(0, 12))
        ttk.Checkbutton(
            opts,
            text="Xóa data Zalo trước (mất login cũ)",
            variable=self.var_reg_wipe,
        ).pack(side="left")

        reg_btns = ttk.Frame(reg_in, style="Card.TFrame")
        reg_btns.pack(fill="x", pady=(8, 0))
        self._btn("Reg tự động → tới OTP", self._auto_reg_start, reg_btns, "#a855f7")
        self._btn("Gửi OTP / Tiếp reg", self._auto_reg_otp, reg_btns, GREEN)
        self._btn("Dừng Frida reg", self._auto_reg_stop, reg_btns, None)

        # Log
        logf = ttk.Frame(self)
        logf.pack(fill="both", expand=True, padx=14, pady=(0, 12))
        ttk.Label(logf, text="Nhật ký", foreground=MUTED, background=BG).pack(anchor="w")
        self.log_box = scrolledtext.ScrolledText(
            logf,
            height=8,
            bg=ENTRY_BG,
            fg=FG,
            insertbackground=FG,
            font=("Consolas", 9),
            relief="flat",
            borderwidth=0,
        )
        self.log_box.pack(fill="both", expand=True, pady=4)

    def _btn(self, text, cmd, parent, color):
        b = tk.Button(
            parent,
            text=text,
            command=cmd,
            bg=color or PANEL,
            fg="#fff" if color else FG,
            activebackground=SEL,
            activeforeground="#fff",
            relief="flat",
            padx=12,
            pady=8,
            font=("Segoe UI Semibold", 10),
            cursor="hand2",
        )
        b.pack(side="left", padx=4)

    def _fill_devices(self) -> None:
        for w in self.dev_inner.winfo_children():
            w.destroy()
        self._device_vars.clear()
        # default: select a few modern models
        defaults = {"iphone13-mini", "iphone14-pro", "iphone15-pro", "iphone16-pro", "iphone16-pro-max"}
        for d in self.devices:
            did = d.get("id") or ""
            label = f"{d.get('MarketingName', did)}  ·  {d.get('ProductType', '')}"
            v = tk.BooleanVar(value=did in defaults)
            self._device_vars[did] = v
            ttk.Checkbutton(self.dev_inner, text=label, variable=v).pack(anchor="w", padx=4, pady=1)

    def _fill_ios(self) -> None:
        for w in self.ios_inner.winfo_children():
            w.destroy()
        self._ios_vars.clear()
        releases = list((self.catalog.get("ios_releases") or {}).keys())
        # sort version-like
        def key(v: str):
            parts = []
            for p in v.split("."):
                try:
                    parts.append(int(p))
                except ValueError:
                    parts.append(0)
            return parts

        releases = sorted(releases, key=key, reverse=True)
        popular = {"18.5", "18.6", "17.6.1", "16.7.10", "15.8.3", "18.0", "17.0"}
        for ver in releases:
            v = tk.BooleanVar(value=ver in popular or ver.startswith("18.") and ver.count(".") <= 1)
            # keep list manageable: only show major recent + popular unless all
            maj = ver.split(".")[0]
            if maj not in ("15", "16", "17", "18", "26") and ver not in popular:
                continue
            self._ios_vars[ver] = v
            ttk.Checkbutton(self.ios_inner, text=f"iOS {ver}", variable=v).pack(anchor="w", padx=4, pady=1)

    def _set_all_devices(self, on: bool) -> None:
        for v in self._device_vars.values():
            v.set(on)

    def _set_all_ios(self, on: bool) -> None:
        for v in self._ios_vars.values():
            v.set(on)

    def _select_popular_ios(self) -> None:
        pop = {"18.5", "18.6", "18.0", "17.6.1", "17.0", "16.7.10", "15.8.3"}
        for ver, var in self._ios_vars.items():
            var.set(ver in pop or ver.startswith("18.5") or ver.startswith("18.6"))

    # ── settings ───────────────────────────────────────────
    def _load_settings(self) -> None:
        try:
            if SETTINGS_PATH.exists():
                data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
                self.var_host.set(data.get("host") or self.var_host.get())
                self.var_user.set(data.get("user") or "mobile")
                self.var_port.set(str(data.get("port") or 22))
                # password optional remember
                if data.get("remember_pass") and data.get("password"):
                    self.var_pass.set(data["password"])
                if data.get("phone"):
                    self.var_phone.set(data["phone"])
                if data.get("reg_name"):
                    self.var_name.set(data["reg_name"])
                for did in data.get("devices") or []:
                    if did in self._device_vars:
                        self._device_vars[did].set(True)
                for ios in data.get("ios") or []:
                    if ios in self._ios_vars:
                        self._ios_vars[ios].set(True)
        except Exception as e:
            self.log(f"Không đọc settings: {e}")

    def _save_settings(self) -> None:
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
                "devices": [k for k, v in self._device_vars.items() if v.get()],
                "ios": [k for k, v in self._ios_vars.items() if v.get()],
            }
            SETTINGS_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")
        except Exception as e:
            self.log(f"Lưu settings lỗi: {e}")

    # ── helpers ────────────────────────────────────────────
    def log(self, msg: str) -> None:
        def _do():
            self.log_box.insert("end", msg.rstrip() + "\n")
            self.log_box.see("end")

        self.after(0, _do)

    def _set_link(self, ok: bool, text: str) -> None:
        def _do():
            self.lbl_link.configure(text=text, foreground=GREEN if ok else ORANGE)

        self.after(0, _do)

    def _set_status_label(self, st: DeviceStatus) -> None:
        if not st.ok:
            txt = f"Lỗi: {st.message}"
        else:
            txt = (
                f"Gói: {st.package}\n"
                f"Máy spoof: {st.marketing or '?'}  ({st.product_type or '?'})  ·  iOS {st.ios or '?'} ({st.build or '?'})\n"
                f"Serial: {st.serial or '?'}  ·  Model: {st.model or '?'}  ·  IMEI: {st.imei or '?'}  ·  IDFV: {(st.idfv or '?')[:13]}…"
            )

        def _do():
            self.lbl_status.configure(text=txt, foreground=FG if st.ok else RED)

        self.after(0, _do)

    def _run_bg(self, title: str, fn) -> None:
        if self._busy:
            messagebox.showinfo("Đang chạy", "Đợi thao tác hiện tại xong.")
            return

        def wrap():
            self._busy = True
            self.log(f"—— {title} ——")
            try:
                fn()
            except Exception as e:
                self.log(f"LỖI: {e}")
                self.after(0, lambda: messagebox.showerror(title, str(e)))
            finally:
                self._busy = False
                self.log(f"—— xong: {title} ——\n")

        threading.Thread(target=wrap, daemon=True).start()

    def _need_client(self) -> DeviceClient:
        if not self.client or not self.client.connected:
            raise RuntimeError("Chưa kết nối. Nhập IP + mật khẩu SSH rồi bấm Kết nối.")
        return self.client

    def _selected_device_ids(self) -> list[str]:
        return [k for k, v in self._device_vars.items() if v.get()]

    def _selected_ios(self) -> list[str]:
        return [k for k, v in self._ios_vars.items() if v.get()]

    def _selected_apps(self) -> list[str]:
        apps = [k for k, v in self._app_vars.items() if v.get()]
        if not apps:
            apps = ["vn.com.vng.zingalo"]
        return apps

    def _valid_pairs(self) -> list[tuple[dict, str, dict]]:
        """List of (device, ios_ver, ios_meta) allowed by matrix ∩ pools."""
        cat = self.catalog
        d_ids = self._selected_device_ids()
        i_list = self._selected_ios()
        pairs = []
        for did in d_ids:
            dev = next((d for d in self.devices if d.get("id") == did), None)
            if not dev:
                continue
            supported = set(sdp.device_supported_ios(dev, cat))
            for ios in i_list:
                if ios not in cat["ios_releases"]:
                    continue
                if supported and ios not in supported:
                    continue
                pairs.append((dev, ios, cat["ios_releases"][ios]))
        return pairs

    def _build_and_deploy(self, device: dict, ios: str, ios_meta: dict) -> dict:
        client = self._need_client()
        built = sdp.build_profile(device, ios, ios_meta, None)
        flat = built["flat"]
        # write local copy for debug
        sdp.write_plist(flat, sdp.OUT_PLIST)
        sdp.OUT_ACTIVE.write_text(json.dumps(built["active"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        plist_text = sdp.OUT_PLIST.read_text(encoding="utf-8")
        client.deploy_config(plist_text, built["active"])
        return flat

    # ── actions ────────────────────────────────────────────
    def _connect(self) -> None:
        self._save_settings()

        def job():
            host = self.var_host.get().strip()
            user = self.var_user.get().strip() or "mobile"
            password = self.var_pass.get()
            port = int(self.var_port.get() or 22)
            if not host or not password:
                raise RuntimeError("Cần IP và mật khẩu SSH (cùng Wi‑Fi với máy).")
            if self.client:
                self.client.close()
            self.client = DeviceClient(host, password, user=user, port=port, log=self.log)
            self.client.connect()
            self._set_link(True, f"● Online {host}")
            st = self.client.fetch_status()
            self._set_status_label(st)
            self.log(json.dumps({
                "package": st.package,
                "device": st.marketing,
                "ios": st.ios,
            }, ensure_ascii=False))

        self._run_bg("Kết nối", job)

    def _disconnect(self) -> None:
        if self.client:
            self.client.close()
            self.client = None
        self._set_link(False, "● Đã ngắt")
        self.log("Đã ngắt kết nối.")

    def _refresh_status(self) -> None:
        def job():
            st = self._need_client().fetch_status()
            self._set_status_label(st)
            self.log(f"Refresh: {st.marketing} / iOS {st.ios}")

        self._run_bg("Làm mới", job)

    def _apply_selected(self) -> None:
        def job():
            pairs = self._valid_pairs()
            if not pairs:
                # if only one device toggled intent — use first selected device + first ios even if matrix empty
                raise RuntimeError(
                    "Không có cặp máy+iOS hợp lệ trong pool.\n"
                    "Chọn đời máy + iOS (matrix Apple) rồi thử lại."
                )
            # Prefer currently checked single if only one device selected
            dev, ios, meta = pairs[0]
            if len(self._selected_device_ids()) == 1 and len(self._selected_ios()) >= 1:
                # pick random valid among selected
                dev, ios, meta = random.choice(pairs)
            else:
                dev, ios, meta = random.choice(pairs)
            self.log(f"Áp dụng: {dev.get('MarketingName')} + iOS {ios}")
            flat = self._build_and_deploy(dev, ios, meta)
            self._need_client().kill_apps()
            st = self._need_client().fetch_status()
            self._set_status_label(st)
            self.after(
                0,
                lambda: messagebox.showinfo(
                    "Áp dụng",
                    f"Đã ghi spoof:\n{flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\n"
                    f"Serial {flat.get('SerialNumber')}\n\nMở lại Zalo để nạp spoof.",
                ),
            )

        self._run_bg("Áp dụng máy", job)

    def _reset_data(self) -> None:
        """Như «Đặt lại dữ liệu app»: random pool + wipe sạch (mất login)."""

        def job():
            pairs = self._valid_pairs()
            if not pairs:
                raise RuntimeError("Pool máy/iOS trống hoặc không có cặp hợp lệ.")
            apps = self._selected_apps()
            dev, ios, meta = random.choice(pairs)
            self.log(f"Đặt lại: {dev.get('MarketingName')} / {ios} + wipe {apps}")
            flat = self._build_and_deploy(dev, ios, meta)
            wipe_msg = self._need_client().wipe_apps(apps, skip_keychain=False)
            self.log(wipe_msg[-800:] if wipe_msg else "wipe done")
            st = self._need_client().fetch_status()
            self._set_status_label(st)
            self.after(
                0,
                lambda: messagebox.showinfo(
                    "Đặt lại dữ liệu app",
                    f"Máy mới: {flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\n"
                    f"Đã xóa data app — phiên đăng nhập MẤT.\nMở lại app để vào màn hình sạch.",
                ),
            )

        self._run_bg("Đặt lại dữ liệu app", job)

    def _save_then_reset(self) -> None:
        """Backup 100% params + app data (login) → random → wipe soft → restore."""

        def job():
            pairs = self._valid_pairs()
            if not pairs:
                raise RuntimeError("Pool máy/iOS trống hoặc không có cặp hợp lệ.")
            apps = self._selected_apps()
            client = self._need_client()
            self.log("① Lưu thông số máy + data app…")
            bak = client.backup_apps(apps)
            self.log(f"Backup: {bak}")
            dev, ios, meta = random.choice(pairs)
            self.log(f"② Đặt lại hồ sơ: {dev.get('MarketingName')} / {ios}")
            flat = self._build_and_deploy(dev, ios, meta)
            self.log("③ Xóa data (giữ keychain)…")
            client.wipe_apps(apps, skip_keychain=True)
            self.log("④ Khôi phục data — giữ đăng nhập…")
            rest = client.restore_apps(bak, apps)
            self.log(rest[-600:] if rest else "restore ok")
            client.kill_apps()
            st = client.fetch_status()
            self._set_status_label(st)
            self.after(
                0,
                lambda: messagebox.showinfo(
                    "Đặt lại + Lưu dữ liệu",
                    f"Đã lưu + spoof mới:\n{flat.get('MarketingName')} · iOS {flat.get('ProductVersion')}\n"
                    f"Phiên đăng nhập được khôi phục từ backup.\n\nBackup:\n{bak}",
                ),
            )

        self._run_bg("Đặt lại + Lưu dữ liệu", job)

    def _wipe_only(self) -> None:
        def job():
            apps = self._selected_apps()
            msg = self._need_client().wipe_apps(apps, skip_keychain=False)
            self.log(msg[-800:] if msg else "wipe only done")
            self.after(0, lambda: messagebox.showinfo("Xóa data", f"Đã xóa data:\n" + "\n".join(apps)))

        self._run_bg("Xóa data app", job)

    def _open_zalo(self) -> None:
        def job():
            self._need_client().open_zalo()
            self.log("Đã gửi lệnh mở Zalo.")

        self._run_bg("Mở Zalo", job)

    # ── Reg tự động ────────────────────────────────────────
    def _auto_reg_start(self) -> None:
        phone = self.var_phone.get().strip()
        if not phone:
            messagebox.showwarning("Reg tự động", "Nhập số điện thoại trước.")
            return
        self._save_settings()

        def job():
            client = self._need_client()
            # 1) optional spoof
            if self.var_reg_spoof.get():
                pairs = self._valid_pairs()
                if not pairs:
                    raise RuntimeError("Bật «Random spoof» nhưng pool máy/iOS không có cặp hợp lệ.")
                dev, ios, meta = random.choice(pairs)
                self.log(f"Reg: spoof {dev.get('MarketingName')} / iOS {ios}")
                self._build_and_deploy(dev, ios, meta)
            # 2) optional wipe
            if self.var_reg_wipe.get():
                self.log("Reg: xóa data Zalo trước…")
                client.wipe_apps(
                    ["vn.com.vng.zingalo", "com.zing.zalo"],
                    skip_keychain=False,
                )
            # 3) Frida UI → phone
            if self.reg_runner:
                try:
                    self.reg_runner.close()
                except Exception:
                    pass
            self.reg_runner = AutoRegRunner(client, log=self.log)
            self.reg_runner.run_full_until_otp(phone)
            self.after(
                0,
                lambda: messagebox.showinfo(
                    "Reg tự động",
                    f"Đã điền SĐT {phone}.\n\n"
                    "1) Nhập mã OTP trên iPhone (SMS)\n"
                    "   hoặc gõ OTP vào ô rồi bấm «Gửi OTP / Tiếp reg»\n"
                    "2) Captcha / ảnh (nếu có) làm tay trên máy",
                ),
            )

        self._run_bg("Reg tự động", job)

    def _auto_reg_otp(self) -> None:
        def job():
            if not self.reg_runner or not self.reg_runner._script:
                raise RuntimeError(
                    "Chưa chạy «Reg tự động → tới OTP» hoặc Frida đã đứt.\n"
                    "Chạy lại Reg tự động trước."
                )
            otp = self.var_otp.get().strip()
            name = self.var_name.get().strip() or "Lab User"
            self.reg_runner.submit_otp_and_finish(otp=otp, name=name)
            self.after(
                0,
                lambda: messagebox.showinfo(
                    "Tiếp reg",
                    "Đã gửi OTP/tên (nếu có) và bấm tiếp các bước UI.\n"
                    "Kiểm tra Zalo trên máy — captcha có thể cần tay.",
                ),
            )

        self._run_bg("Gửi OTP / Tiếp reg", job)

    def _auto_reg_stop(self) -> None:
        def job():
            if self.reg_runner:
                self.reg_runner.close()
                self.reg_runner = None
                self.log("Đã dừng session Frida reg.")
            else:
                self.log("Không có session reg đang mở.")

        self._run_bg("Dừng Frida reg", job)

    def _on_close(self) -> None:
        self._save_settings()
        if self.reg_runner:
            try:
                self.reg_runner.close()
            except Exception:
                pass
        if self.client:
            self.client.close()
        self.destroy()


def main() -> int:
    app = IPfakerPC()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
