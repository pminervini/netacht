#!/usr/bin/env python3
"""Drive the exported NetAcht web build and save playthrough evidence.

The runner serves docs/index.html locally, launches Chromium through
Playwright, sends PICO-8 button masks, and writes screenshots plus report.json.
It uses the already-exported web build; regenerate docs/ first when testing
fresh cartridge edits.
"""

from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
import socketserver
import threading
import time
from collections import deque
from pathlib import Path
from typing import Any

from playwright.sync_api import sync_playwright


REPO = Path(__file__).resolve().parents[1]
DOCS = REPO / "docs"
DEFAULT_CHROMIUM = Path("/Applications/Chromium.app/Contents/MacOS/Chromium")
BUTTONS = {
    "left": 0x01,
    "right": 0x02,
    "up": 0x04,
    "down": 0x08,
    "o": 0x10,
    "x": 0x20,
}
PATROL = [
    "right",
    "right",
    "right",
    "down",
    "down",
    "o",
    "left",
    "left",
    "left",
    "up",
    "up",
    "o",
    "right",
    "down",
    "right",
    "o",
]
PIXEL_JS = """() => {
    const c = document.getElementById('canvas');
    const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let nonzero = 0;
    let sum = 0;
    for (let i = 0; i < data.length; i += 4) {
        const v = data[i] + data[i + 1] + data[i + 2];
        if (v) nonzero++;
        sum = (sum + v) >>> 0;
    }
    return {width: c.width, height: c.height, nonzero, sum};
}"""
PLAY_SCREEN_JS = """() => {
    const c = document.getElementById('canvas');
    const data = c.getContext('2d').getImageData(0, 0, c.width, 12).data;
    let hud = 0;
    for (let i = 0; i < data.length; i += 4) {
        if (data[i] === 29 && data[i + 1] === 43 && data[i + 2] === 83) hud++;
    }
    return hud > 900;
}"""
SCREEN_JS = """() => {
    const c = document.getElementById('canvas');
    const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    const colors = {
        gray: '95,87,79',
        corridor: '131,118,156',
        door: '171,82,54',
        player: '255,204,170',
        stair: '255,241,232',
        item: '255,163,0'
    };
    function at(x, y) {
        const i = (y * c.width + x) * 4;
        return data[i] + ',' + data[i + 1] + ',' + data[i + 2];
    }
    const cells = [];
    let player = null;
    for (let sy = 0; sy < 16; sy++) {
        const row = [];
        for (let sx = 0; sx < 32; sx++) {
            const counts = {};
            const white = [];
            let nonzero = 0;
            for (let y = 13 + sy * 6; y < 13 + (sy + 1) * 6 && y < 109; y++) {
                for (let x = sx * 4; x < sx * 4 + 4; x++) {
                    const key = at(x, y);
                    if (key !== '0,0,0') {
                        counts[key] = (counts[key] || 0) + 1;
                        nonzero++;
                        if (key === colors.stair) white.push([x - sx * 4, y - (13 + sy * 6)]);
                    }
                }
            }
            let stairKind = null;
            if (white.length > 0) {
                const has = (x, y) => white.some((p) => p[0] === x && p[1] === y);
                if (has(0, 2) && (has(2, 0) || has(2, 4))) {
                    stairKind = 'up';
                } else if (has(2, 2) && (has(0, 0) || has(0, 4))) {
                    stairKind = 'down';
                } else {
                    stairKind = 'unknown';
                }
            }
            let kind = 'unknown';
            if ((counts[colors.player] || 0) >= 2) {
                kind = stairKind ? 'player_stair_' + stairKind : 'player';
                player = {sx, sy, stair: stairKind};
            } else if ((counts[colors.gray] || 0) >= 20) {
                kind = 'wall';
            } else if ((counts[colors.stair] || 0) > 0) {
                kind = 'stair_' + stairKind;
            } else if ((counts[colors.door] || 0) > 0) {
                kind = 'door';
            } else if ((counts[colors.corridor] || 0) > 0) {
                kind = 'floor';
            } else if ((counts[colors.item] || 0) > 0) {
                kind = 'item';
            } else if (nonzero > 0) {
                kind = 'floor';
            }
            row.push(kind);
        }
        cells.push(row);
    }
    return {player, cells};
}"""
DEPTH_SIG_JS = """() => {
    const c = document.getElementById('canvas');
    const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let sig = '';
    for (let y = 1; y <= 5; y++) {
        for (let x = 9; x <= 20; x++) {
            const i = (y * c.width + x) * 4;
            sig += data[i] === 255 && data[i + 1] === 241 && data[i + 2] === 232 ? '1' : '0';
        }
    }
    return sig;
}"""


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args: object) -> None:
        pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--steps", type=int, default=128, help="input steps after starting")
    parser.add_argument(
        "--mode",
        choices=["sequence", "explore"],
        default="sequence",
        help="input strategy: fixed sequence or map-aware exploration",
    )
    parser.add_argument("--docs", type=Path, default=DOCS, help="web export directory")
    parser.add_argument("--out", type=Path, default=None, help="output directory")
    parser.add_argument("--chromium", type=Path, default=DEFAULT_CHROMIUM)
    parser.add_argument("--screenshot-every", type=int, default=16)
    parser.add_argument("--fresh", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument(
        "--stop-when-not-playing",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="stop after the game leaves the normal play HUD, e.g. death/title/help",
    )
    parser.add_argument(
        "--sequence",
        default=",".join(PATROL),
        help="comma-separated buttons: left,right,up,down,o,x",
    )
    return parser.parse_args()


def output_dir(path: Path | None) -> Path:
    if path is not None:
        out = path
    else:
        out = Path("/tmp") / f"netacht-play-{time.strftime('%Y%m%d-%H%M%S')}"
    out.mkdir(parents=True, exist_ok=True)
    return out


def read_sequence(raw: str) -> list[str]:
    seq = [part.strip().lower() for part in raw.split(",") if part.strip()]
    bad = [name for name in seq if name not in BUTTONS]
    if bad:
        raise SystemExit(f"unknown button(s): {', '.join(bad)}")
    if not seq:
        raise SystemExit("sequence must contain at least one button")
    return seq


def passable(kind: str | None) -> bool:
    return kind in {
        "floor",
        "door",
        "stair_up",
        "stair_down",
        "stair_unknown",
        "item",
        "player",
        "player_stair_up",
        "player_stair_down",
        "player_stair_unknown",
    }


DIRS = {
    "left": (-1, 0),
    "right": (1, 0),
    "up": (0, -1),
    "down": (0, 1),
}


def step_toward(path: list[tuple[int, int]]) -> str | None:
    if len(path) < 2:
        return None
    x0, y0 = path[0]
    x1, y1 = path[1]
    delta = (x1 - x0, y1 - y0)
    for name, vec in DIRS.items():
        if vec == delta:
            return name
    return None


def find_path(
    world: dict[tuple[int, int], str],
    start: tuple[int, int],
    goals: set[tuple[int, int]],
) -> list[tuple[int, int]] | None:
    if start in goals:
        return [start]
    queue = deque([start])
    prev: dict[tuple[int, int], tuple[int, int] | None] = {start: None}
    while queue:
        x, y = queue.popleft()
        for dx, dy in DIRS.values():
            nxt = (x + dx, y + dy)
            if nxt in prev or not passable(world.get(nxt)):
                continue
            prev[nxt] = (x, y)
            if nxt in goals:
                path = [nxt]
                while prev[path[-1]] is not None:
                    path.append(prev[path[-1]])  # type: ignore[arg-type]
                path.reverse()
                return path
            queue.append(nxt)
    return None


def find_local_path(
    cells: list[list[str]],
    start: tuple[int, int],
    goals: set[tuple[int, int]],
) -> list[tuple[int, int]] | None:
    if start in goals:
        return [start]
    queue = deque([start])
    prev: dict[tuple[int, int], tuple[int, int] | None] = {start: None}
    while queue:
        sx, sy = queue.popleft()
        for dx, dy in DIRS.values():
            nx, ny = sx + dx, sy + dy
            if nx < 0 or ny < 0 or nx >= 32 or ny >= 16:
                continue
            nxt = (nx, ny)
            if nxt in prev or not passable(cells[ny][nx]):
                continue
            prev[nxt] = (sx, sy)
            if nxt in goals:
                path = [nxt]
                while prev[path[-1]] is not None:
                    path.append(prev[path[-1]])  # type: ignore[arg-type]
                path.reverse()
                return path
            queue.append(nxt)
    return None


def choose_visible_move(
    screen: dict[str, Any],
    current_stair_attempted: bool,
    force_current_stair: bool,
) -> tuple[str | None, str | None]:
    player = screen.get("player")
    if not player:
        return None, None
    cells = screen["cells"]
    start = (int(player["sx"]), int(player["sy"]))
    if (
        (player.get("stair") == "down" or (force_current_stair and player.get("stair")))
        and not current_stair_attempted
    ):
        return "o", "use_stair"

    stairs_down = {
        (sx, sy)
        for sy, row in enumerate(cells)
        for sx, kind in enumerate(row)
        if kind == "stair_down"
    }
    path = find_local_path(cells, start, stairs_down)
    move = step_toward(path) if path else None
    if move:
        return move, "enter_down_stair" if path and len(path) == 2 else "visible_stair"

    frontiers = set()
    for sy, row in enumerate(cells):
        for sx, kind in enumerate(row):
            if not passable(kind):
                continue
            for dx, dy in DIRS.values():
                nx, ny = sx + dx, sy + dy
                if 0 <= nx < 32 and 0 <= ny < 16 and cells[ny][nx] == "unknown":
                    frontiers.add((sx, sy))
                    break
    path = find_local_path(cells, start, frontiers)
    move = step_toward(path) if path else None
    if move:
        return move, "visible_frontier"

    for name, (dx, dy) in DIRS.items():
        nx, ny = start[0] + dx, start[1] + dy
        if 0 <= nx < 32 and 0 <= ny < 16 and passable(cells[ny][nx]):
            return name, "visible_neighbor"
    return None, None


def choose_explore_move(
    world: dict[tuple[int, int], str],
    pos: tuple[int, int],
    visits: dict[tuple[int, int], int],
    attempted_stairs: set[tuple[int, int]],
) -> tuple[str, str | None]:
    stairs = {p for p, kind in world.items() if kind == "stair_down" and p not in attempted_stairs}
    if pos in stairs:
        return "o", "use_stair"
    path = find_path(world, pos, stairs)
    move = step_toward(path) if path else None
    if move:
        return move, "stair"

    frontiers = set()
    for (x, y), kind in world.items():
        if not passable(kind):
            continue
        if any(world.get((x + dx, y + dy)) is None for dx, dy in DIRS.values()):
            frontiers.add((x, y))
    path = find_path(world, pos, frontiers)
    move = step_toward(path) if path else None
    if move:
        return move, "frontier"

    options = []
    for name, (dx, dy) in DIRS.items():
        nxt = (pos[0] + dx, pos[1] + dy)
        if passable(world.get(nxt)):
            options.append((visits.get(nxt, 0), name))
    if options:
        options.sort()
        return options[0][1], "least_visited"

    return "o", "search"


def make_contact_sheet(out: Path) -> str | None:
    try:
        from PIL import Image, ImageDraw
    except Exception:
        return None

    images = sorted(p for p in out.glob("*.png") if p.name != "contact_sheet.png")
    if not images:
        return None
    scale = 2
    cols = 4
    thumb_w = thumb_h = 128 * scale
    label_h = 18
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * thumb_w, rows * (thumb_h + label_h)), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    for i, path in enumerate(images):
        img = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.NEAREST)
        x = (i % cols) * thumb_w
        y = (i // cols) * (thumb_h + label_h)
        sheet.paste(img, (x, y))
        draw.text((x + 4, y + thumb_h + 3), path.stem, fill=(255, 255, 255))
    contact = out / "contact_sheet.png"
    sheet.save(contact)
    return str(contact)


def serve_docs(docs: Path) -> tuple[socketserver.TCPServer, int]:
    os.chdir(docs)
    server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def main() -> int:
    args = parse_args()
    docs = args.docs.resolve()
    out = output_dir(args.out)
    sequence = read_sequence(args.sequence)
    if not (docs / "index.html").exists():
        raise SystemExit(f"missing web export: {docs / 'index.html'}")
    if not args.chromium.exists():
        raise SystemExit(f"missing Chromium executable: {args.chromium}")

    server, port = serve_docs(docs)
    screens: list[dict[str, Any]] = []
    console_events: list[dict[str, str]] = []
    page_errors: list[str] = []
    http_errors: list[dict[str, Any]] = []
    explore_stats: dict[str, Any] = {
        "floor_changes": 0,
        "stair_uses": 0,
        "stair_attempts": 0,
        "explored_cells": 0,
        "visited_cells": 0,
        "fallback_searches": 0,
        "reasons": {},
    }

    def record_screen(canvas: Any, page: Any, name: str, step: int | None = None) -> None:
        prefix = f"{len(screens):02d}"
        suffix = f"{name}" if step is None else f"{name}_{step:03d}"
        path = out / f"{prefix}_{suffix}.png"
        canvas.screenshot(path=str(path))
        pixels = page.evaluate(PIXEL_JS)
        screens.append(
            {
                "name": name,
                "step": step,
                "path": str(path),
                "pixels": pixels,
                "sha256_16": hashlib.sha256(path.read_bytes()).hexdigest()[:16],
            }
        )

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(
                headless=True,
                executable_path=str(args.chromium),
                args=["--autoplay-policy=no-user-gesture-required"],
            )
            page = browser.new_page(viewport={"width": 900, "height": 900}, device_scale_factor=1)
            page.on(
                "console",
                lambda msg: console_events.append({"type": msg.type, "text": msg.text[:300]}),
            )
            page.on("pageerror", lambda err: page_errors.append(str(err)))
            page.on(
                "response",
                lambda resp: http_errors.append({"status": resp.status, "url": resp.url})
                if resp.status >= 400
                else None,
            )
            page.goto(f"http://127.0.0.1:{port}/index.html", wait_until="domcontentloaded")
            page.click("#p8_container")
            page.wait_for_function(
                "window.p8_is_running === true && window.Module && window.Module.canvas "
                "&& window.pico8_state && window.pico8_state.frame_number > 5",
                timeout=15000,
            )
            canvas = page.locator("#canvas")

            def wait_frames(n: int) -> None:
                base = page.evaluate("pico8_state.frame_number")
                page.wait_for_function(
                    "(target) => window.pico8_state.frame_number >= target",
                    arg=base + n,
                    timeout=10000,
                )

            def pulse(button: str, frames: int = 8) -> None:
                page.evaluate("(mask) => { window.pico8_buttons[0] = mask; }", BUTTONS[button])
                wait_frames(frames)
                page.evaluate("window.pico8_buttons[0] = 0")
                wait_frames(4)

            def read_screen() -> dict[str, Any]:
                return page.evaluate(SCREEN_JS)

            def grid_signature(screen: dict[str, Any]) -> str:
                return "\n".join("".join(row) for row in screen["cells"])

            def integrate_screen(
                screen: dict[str, Any],
                world: dict[tuple[int, int], str],
                pos: tuple[int, int],
            ) -> tuple[int, int] | None:
                player = screen.get("player")
                if not player:
                    return None
                px = int(player["sx"])
                py = int(player["sy"])
                for sy, row in enumerate(screen["cells"]):
                    for sx, kind in enumerate(row):
                        if kind == "unknown":
                            continue
                        if kind == "player":
                            mapped = "floor"
                        elif kind.startswith("player_stair_"):
                            mapped = kind[len("player_") :]
                        else:
                            mapped = kind
                        world[(pos[0] + sx - px, pos[1] + sy - py)] = mapped
                return px, py

            record_screen(canvas, page, "title")
            pulse("x" if args.fresh else "o", 10)
            wait_frames(30)
            record_screen(canvas, page, "start", 0)

            stopped_at = None
            world: dict[tuple[int, int], str] = {}
            visits: dict[tuple[int, int], int] = {}
            attempted_stairs: set[tuple[int, int]] = set()
            pos = (0, 0)
            pending_down_stair = False
            screen = read_screen()
            integrate_screen(screen, world, pos)
            visits[pos] = 1
            last_sig = grid_signature(screen)

            for step in range(1, args.steps + 1):
                if args.mode == "explore":
                    screen = read_screen()
                    integrate_screen(screen, world, pos)
                    button, reason = choose_visible_move(screen, pos in attempted_stairs, pending_down_stair)
                    pending_down_stair = False
                    if not button:
                        button, reason = choose_explore_move(world, pos, visits, attempted_stairs)
                    explore_stats["reasons"][reason or "none"] = (
                        explore_stats["reasons"].get(reason or "none", 0) + 1
                    )
                    before_sig = grid_signature(screen)
                    before_depth_sig = page.evaluate(DEPTH_SIG_JS)
                    old_pos = pos
                    target = None
                    if button in DIRS:
                        dx, dy = DIRS[button]
                        target = (pos[0] + dx, pos[1] + dy)
                        if world.get(target) == "door":
                            world[target] = "floor"
                        else:
                            pos = target
                            visits[pos] = visits.get(pos, 0) + 1
                    elif reason == "use_stair":
                        attempted_stairs.add(pos)
                        explore_stats["stair_attempts"] += 1
                    elif button == "o":
                        explore_stats["fallback_searches"] += 1

                    pulse(button, frames=6)
                    after = read_screen()
                    player_seen = integrate_screen(after, world, pos)
                    after_sig = grid_signature(after)
                    if args.mode == "explore" and reason == "use_stair":
                        changed = before_depth_sig != page.evaluate(DEPTH_SIG_JS)
                        if changed:
                            explore_stats["floor_changes"] += 1
                            explore_stats["stair_uses"] += 1
                            pos = (0, 0)
                            world = {}
                            visits = {pos: 1}
                            attempted_stairs = set()
                            pending_down_stair = False
                            integrate_screen(after, world, pos)
                            record_screen(canvas, page, "floor_change", step)
                        last_sig = after_sig
                    elif reason == "enter_down_stair":
                        pending_down_stair = True
                        last_sig = after_sig
                    elif player_seen is None:
                        pos = old_pos
                    elif target and not passable(world.get(target)):
                        pos = old_pos
                    else:
                        last_sig = after_sig
                else:
                    pulse(sequence[(step - 1) % len(sequence)], frames=6)

                if args.screenshot_every > 0 and step % args.screenshot_every == 0:
                    record_screen(canvas, page, "step", step)
                if args.stop_when_not_playing and not page.evaluate(PLAY_SCREEN_JS):
                    stopped_at = step
                    record_screen(canvas, page, "stopped", step)
                    break

            final_step = stopped_at or args.steps
            explore_stats["explored_cells"] = sum(1 for kind in world.values() if passable(kind))
            explore_stats["visited_cells"] = len(visits)
            record_screen(canvas, page, "final", final_step)
            frame = page.evaluate("pico8_state.frame_number")
            running = page.evaluate("window.p8_is_running === true")
            browser.close()

        contact = make_contact_sheet(out)
        report = {
            "url": f"http://127.0.0.1:{port}/index.html",
            "docs": str(docs),
            "out_dir": str(out),
            "steps": args.steps,
            "stopped_at": stopped_at,
            "mode": args.mode,
            "sequence": sequence,
            "explore_stats": explore_stats if args.mode == "explore" else None,
            "frame": frame,
            "running": running,
            "screens": screens,
            "contact_sheet": contact,
            "http_errors": http_errors,
            "page_errors": page_errors,
            "console_events": console_events[-30:],
        }
        (out / "report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 0 if running and not page_errors else 1
    finally:
        server.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
