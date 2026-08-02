from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "site"
APP = OUTPUT / "app"


def main() -> None:
    shutil.rmtree(OUTPUT, ignore_errors=True)
    flutter = shutil.which("flutter")
    if flutter is None:
        raise SystemExit("Flutter executable not found")
    command = [
        flutter,
        "build",
        "web",
        "--base-href",
        "/app/",
        "--output",
        str(APP),
    ]
    for name in ("VAR_DEMO_SEED", "VAR_VOTING_API_ENDPOINT"):
        value = os.environ.get(name)
        if value is not None:
            command.append(f"--dart-define={name}={value}")
    subprocess.run(command, cwd=ROOT, check=True)
    shutil.copytree(ROOT / "landing", OUTPUT, dirs_exist_ok=True)
    assets = OUTPUT / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "assets" / "branding" / "app_icon.png", assets / "app-icon.png")
    shutil.copy2(ROOT / "web" / "favicon.png", assets / "favicon.png")


if __name__ == "__main__":
    main()
