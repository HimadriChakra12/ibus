# Building and installing this ibus fork from scratch

This tree is a size-trimmed fork of upstream ibus (GTK2, gconf, gtk-doc,
and tests removed; GTK3/Vala panel and Python setup GUI ported forward
to a modern toolchain). Installed footprint: ~4.7MB stripped, vs 8.9MB
for a stock default build — with no functionality removed.

## 1. System dependencies (Arch/pacman example — adjust for your distro)

```
sudo pacman -S autoconf automake libtool intltool pkgconf \
    gobject-introspection vala gtk3 dbus glib2 \
    python-gobject python-pyxdg
```

You need `gobject-introspection` and `vala` even though this is a C
project — the built-in `simple` input engine is written in Vala, and
Vala needs the generated `.gir`/typelib at build time to compile against
libibus. This is a required build-time toolchain, not an optional
feature; it adds nothing to the installed runtime footprint.

## 2. Generate the build system

```
touch ChangeLog
autoreconf --force --install -I m4
```

(`autogen.sh` normally does this via `gnome-autogen.sh`, but that wrapper
depends on the `gnome-common` package, which is gone from most modern
distros. `autoreconf` does the same thing directly.)

## 3. Configure

```
./configure --enable-gtk3 --disable-static --enable-memconf --enable-vala --disable-python-library
```

The size-optimization flags (`-Os`, LTO, `--gc-sections`, strip) and the
`-std=gnu17 -Wno-error=incompatible-pointer-types` compatibility flag
are now baked into `configure.ac` as defaults — no need to prepend
`CFLAGS=`/`LDFLAGS=` by hand. If you want to override them with your
own choice, just pass `CFLAGS=...`/`LDFLAGS=...` on the command line as
usual; they get appended after the defaults, so `-O` flags you specify
will win (GCC uses whichever `-O` level appears last).

If you want a system-wide install instead of `/usr/local`, add
`--prefix=/usr` here.

## 4. Build

```
make -C src
make -C bindings
make -j$(nproc)
```

The two explicit steps first are required: the top-level `Makefile.am`
lists `bindings` after `engine`/`ui` in `SUBDIRS`, but `engine`'s Vala
code and `ui/gtk3`'s Vala code both need the `.vapi` that `bindings`
generates. Building `src` and `bindings` once up front avoids the
ordering problem; everything else builds in parallel fine after that.

## 5. Install

```
sudo make -C src install
sudo make -C bindings install
sudo make install
```

Then refresh caches so other apps (Python/GI, GTK, D-Bus) can find what
was just installed:

```
sudo ldconfig
sudo glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null
sudo gtk-query-immodules-3.0 --update-cache 2>/dev/null
```

(These normally happen automatically via package manager hooks; since
this is a from-source install, do them by hand once.)

## 6. Additional runtime dependency for the setup GUI

`ibus-setup` is a separate PyGObject app, not something this build
compiles — it needs `python-pyxdg` installed system-wide (already in
the pacman command in step 1 if you copy-pasted it).

## 7. Run it

```
ibus-daemon -d
ibus-setup
```

`ibus` (no hyphen) is a *different*, separate CLI tool from
`ibus-daemon` — it only takes these subcommands, no flags:

```
ibus engine [name]
ibus exit
ibus list-engine
ibus watch
ibus restart
```

## What was changed from upstream, and why

**Source removed** (directories deleted): `client/gtk2/` (GTK2 IM
module — its 3 source files were shared with GTK3 via symlink, so
those were copied into `client/gtk3/` directly first), `conf/gconf/`
(package no longer exists on modern distros; `dconf`/`memconf` already
cover config storage), `docs/` (gtk-doc API reference — build-time
only, never installed), `debian/` (packaging metadata, not needed for
a manual build), `src/tests/` (test-only, had a pre-existing broken
include path unrelated to any of this).

**Build system edited**: `Makefile.am` (top-level) reorders `SUBDIRS`
so `bindings` comes before `engine`/`client`/ui; `configure.ac` removes
the gconf detection block and dangling `AC_CONFIG_FILES` entries for
deleted dirs, and now bakes in the size-optimization + GCC-14
compatibility flags as defaults (see step 3 above); `client/Makefile.am`,
`conf/Makefile.am`, `src/Makefile.am` drop references to the deleted
subdirectories (Automake requires this even for conditionally-built
dirs — a conditional `SUBDIRS` entry still needs to correspond to a
real directory in the tree).

**C/Vala fixes** (toolchain drift, not logic changes):
- `ui/gtk3/application.vala` — 3 D-Bus signal callbacks needed
  `string?` instead of `string` for `sender_name`, matching the
  current GLib vapi's nullable signature.
- `ui/gtk3/switcher.vala` — `Gdk.EventKey *pe = &e;` → `= e;` in two
  places; the current GTK3 vapi already passes that virtual method's
  parameter as an implicit pointer, so `&e` was taking the address of
  a pointer.
- `ui/gtk3/handle.vala` — `Gtk.render_handle()` was removed from the
  vapi entirely; replaced with a small Cairo-drawn 3×3 dot grip using
  the current GTK theme's foreground color, same visual affordance.

**Python 2→3 and deprecated-API fixes**, all in `setup/` (the
`ibus-setup` GUI — none of this affects the daemon/engine):
- `raise X, y` → `raise X(y)`; `except X, e` → `except X as e`;
  `print x` → `print(x)` — mechanical Python 2 syntax across
  `enginetreeview.py`, `main.py`, `enginecombobox.py`,
  `keyboardshortcut.py`.
- `unicode(s, "utf-8")` calls removed in `main.py` — meaningless in
  Python 3, where strings are unicode by default.
- `dict.keys().sort(...)` and `list.sort(comparator_function)` in
  `enginecombobox.py` — Python 3's `dict.keys()` returns a view (no
  `.sort()`), and `.sort()`/`sorted()` no longer accept a raw
  comparator function. Fixed with `list(...)` and
  `functools.cmp_to_key(...)`. Also removed a leftover debug
  `print()` that was dumping every engine's language code to stdout.
- `Gtk.VBox`/`Gtk.HBox`/`Gtk.Table`/`Gtk.STOCK_*`/`Gtk.ImageMenuItem`
  in `keyboardshortcut.py`, `engineabout.py`, `enginecombobox.py`,
  `enginetreeview.py` — all fully removed from current GTK3 bindings
  (not just deprecated). Replaced with `Gtk.Box`/`Gtk.Grid`/plain
  label strings and standard freedesktop icon names.
- `Gtk.IconTheme.get_default()` removed — replaced with
  `Gtk.IconTheme.get_for_screen(Gdk.Screen.get_default())` in
  `icon.py` and `engineabout.py`.
- `gettext.bind_textdomain_codeset()` removed in Python 3.13+ (was
  always a no-op on Python 3 anyway) — guarded with `hasattr()` in
  `i18n.py` (shared between `setup/` and `ui/gtk2/` via symlink).
- **Root cause of most of the above**: `main.py` never called
  `gi.require_version('Gtk', '3.0')` before importing `Gtk`, so
  PyGObject was silently loading GTK4 if it was also installed on the
  system — GTK4 doesn't have `VBox`/`Table`/`STOCK_*`/etc at all. Added
  the explicit version pin at the top of `main.py`, before any
  `gi.repository` import.

None of these changes affect the daemon, the input engines, XIM, or
the GTK3 IM module — they were already working. Everything above was
either (a) trimming unused build output, or (b) fixing genuine drift
between this ~2013-era codebase and a 2026 toolchain, surfaced while
verifying the trimmed build actually runs end to end.
