#!/usr/bin/env python3
"""Desktop cleanup — sorts loose Desktop files into buckets per desktop-cleanup-rules.json.

Safety model:
  - Acts on TOP-LEVEL FILES only. Directories are NEVER moved (logged to a registry).
  - Screenshots are SOFT-deleted (moved to a dated quarantine), never hard-deleted.
    Quarantine entries older than trash_retention_days are purged (only destructive op,
    only on our own quarantine folder, only after retention).
  - Unmatched file types are left untouched.
  - mode 'dry-run' (default in rules): reports what it WOULD do, moves nothing.
  - Name collisions at destination are resolved by appending " (2)", " (3)", ...

Usage:
  python3 scripts/desktop-cleanup.py            # uses mode from rules JSON
  python3 scripts/desktop-cleanup.py --dry-run  # force dry-run
  python3 scripts/desktop-cleanup.py --apply    # force apply
"""
import json, sys, shutil, datetime
from pathlib import Path

RULES_PATH = Path(__file__).resolve().parent.parent / "desktop-cleanup-rules.json"
BUNDLE_DIR_EXTS = {"app", "numbers", "pages", "key", "rtfd", "photoslibrary"}

def load_rules():
    return json.loads(RULES_PATH.read_text(encoding="utf-8"))

def ext_of(name: str) -> str:
    return name.rsplit(".", 1)[1].lower() if "." in name and not name.startswith(".") else ""

def unique_dest(dest_dir: Path, name: str) -> Path:
    cand = dest_dir / name
    if not cand.exists():
        return cand
    stem = name.rsplit(".", 1)[0] if "." in name else name
    suf = ("." + name.rsplit(".", 1)[1]) if "." in name else ""
    i = 2
    while (dest_dir / f"{stem} ({i}){suf}").exists():
        i += 1
    return dest_dir / f"{stem} ({i}){suf}"

def main():
    rules = load_rules()
    mode = rules.get("mode", "dry-run")
    if "--dry-run" in sys.argv: mode = "dry-run"
    if "--apply" in sys.argv: mode = "apply"
    apply = mode == "apply"

    desktop = Path(rules["desktop"]).expanduser()
    icloud_videos = Path(rules["icloud_videos_dir"]).expanduser()
    trash_root = Path(rules["trash_dir"]).expanduser()
    retention = int(rules["trash_retention_days"])
    log_dir = Path(rules["log_dir"]).expanduser()
    registry = Path(rules["folders_registry"]).expanduser()
    ss_patterns = [p.lower() for p in rules["screenshot_name_patterns"]]
    buckets = rules["buckets"]            # bucket name -> [exts]
    video_exts = set(rules["video_extensions"])
    never = set(rules["never_touch"])
    ext_to_bucket = {e: b for b, exts in buckets.items() for e in exts}
    image_exts = set(buckets.get("IMAGINE", []))

    actions, folders, skipped = [], [], []

    for entry in sorted(desktop.iterdir(), key=lambda p: p.name):
        name = entry.name
        if name.startswith("."):
            continue
        if name in never:
            skipped.append((name, "protejat (never_touch)")); continue
        if entry.is_symlink():
            skipped.append((name, "symlink/alias")); continue
        if entry.is_dir():
            e = ext_of(name)
            if e in BUNDLE_DIR_EXTS:
                skipped.append((name, f"bundle .{e}"))
            else:
                folders.append(name)
            continue
        if not entry.is_file():
            skipped.append((name, "non-fișier")); continue

        e = ext_of(name)
        low = name.lower()
        is_image = e in image_exts
        is_screenshot = is_image and any(p in low for p in ss_patterns)

        if is_screenshot:
            day = datetime.date.today().isoformat()
            tdir = trash_root / day
            dest = unique_dest(tdir, name) if apply else tdir / name
            actions.append(("SOFT-DELETE → coș " + day, name, dest))
        elif e in video_exts:
            dest = unique_dest(icloud_videos, name) if apply else icloud_videos / name
            actions.append(("VIDEO → iCloud FROM DESKTOP/VIDEOS", name, dest))
        elif e in ext_to_bucket:
            b = ext_to_bucket[e]
            ddir = desktop / b
            dest = unique_dest(ddir, name) if apply else ddir / name
            actions.append((f"→ {b}", name, dest))
        else:
            skipped.append((name, f"tip necunoscut (.{e or 'fără ext'}) — neatins"))

    # ---- execute (apply only) ----
    purged = []
    if apply:
        for label, name, dest in actions:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(desktop / name), str(dest))
        # purge old quarantine
        if trash_root.exists():
            cutoff = datetime.date.today() - datetime.timedelta(days=retention)
            for d in trash_root.iterdir():
                if d.is_dir():
                    try:
                        ddate = datetime.date.fromisoformat(d.name)
                    except ValueError:
                        continue
                    if ddate < cutoff:
                        shutil.rmtree(d); purged.append(d.name)

    # ---- post-apply verification ----
    verify = []
    if apply:
        # (a) no classifiable loose file should still be on the desktop
        for entry in desktop.iterdir():
            if entry.name.startswith(".") or entry.name in never:
                continue
            if entry.is_symlink() or entry.is_dir() or not entry.is_file():
                continue
            e2 = ext_of(entry.name)
            low2 = entry.name.lower()
            is_img2 = e2 in image_exts
            is_ss2 = is_img2 and any(p in low2 for p in ss_patterns)
            if is_ss2 or e2 in video_exts or e2 in ext_to_bucket:
                verify.append(f"încă pe desktop (ar fi trebuit mutat): {entry.name}")
        # (b) every recorded action's destination must exist; source must be gone
        for label, name, dest in actions:
            if not Path(dest).exists():
                verify.append(f"lipsă la destinație: {name} -> {dest}")
            if (desktop / name).exists():
                verify.append(f"încă pe desktop după mutare: {name}")

    # ---- registry of working folders ----
    reg_lines = [f"# Foldere de lucru pe desktop — {datetime.datetime.now():%Y-%m-%d %H:%M}",
                 "", "Decidem task-cu-task ce facem cu ele (rămân / mutăm / arhivăm).", ""]
    reg_lines += [f"- {f}" for f in sorted(folders)] or ["- (niciun folder)"]
    if apply:
        registry.write_text("\n".join(reg_lines) + "\n", encoding="utf-8")

    # ---- manifest log ----
    ts = datetime.datetime.now()
    log_lines = [f"# Desktop cleanup — {ts:%Y-%m-%d %H:%M:%S} — mode={mode}", "",
                 f"Acțiuni: {len(actions)} | Foldere (neatinse): {len(folders)} | Skip: {len(skipped)}", ""]
    log_lines.append("## Acțiuni")
    log_lines += [f"- {lbl}: {nm}" for lbl, nm, _ in actions] or ["- (niciuna)"]
    log_lines += ["", "## Foldere de lucru (neatinse)"]
    log_lines += [f"- {f}" for f in sorted(folders)] or ["- (niciunul)"]
    log_lines += ["", "## Skip / neatins"]
    log_lines += [f"- {nm} — {why}" for nm, why in skipped] or ["- (nimic)"]
    if purged:
        log_lines += ["", f"## Coș golit (mai vechi de {retention} zile)"] + [f"- {p}" for p in purged]
    if apply:
        log_lines += ["", "## Verificare post-rulare"]
        log_lines += ["CURAT ✅ — toate fișierele la locul lor, desktop fără reziduuri."] if not verify \
            else ["ANOMALII ⚠️:"] + [f"- {a}" for a in verify]
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / f"cleanup-{ts:%Y-%m-%d-%H%M%S}.md").write_text("\n".join(log_lines) + "\n", encoding="utf-8")

    # ---- summary to stdout (for the agent to relay) ----
    from collections import Counter
    c = Counter(lbl for lbl, _, _ in actions)
    print(f"MODE={mode}")
    print(f"Total fișiere de procesat: {len(actions)} | foldere neatinse: {len(folders)} | skip: {len(skipped)}")
    for k, v in sorted(c.items()):
        print(f"  {k}: {v}")
    if purged:
        print(f"Coș golit: {len(purged)} zi(le) > {retention}z")
    if apply:
        if not verify:
            print("VERIFICARE: CURAT ✅ — desktop fără reziduuri, toate la destinație.")
        else:
            print(f"VERIFICARE: ANOMALII ⚠️ ({len(verify)}):")
            for a in verify:
                print(f"  - {a}")
    if not apply:
        print("DRY-RUN: nimic mutat. Treci mode pe 'apply' în desktop-cleanup-rules.json după validare.")

if __name__ == "__main__":
    main()
