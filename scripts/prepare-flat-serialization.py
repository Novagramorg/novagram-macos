#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def prepare(root):
    base = root / "submodules/telegram-ios/submodules/TelegramCore/FlatSerialization"
    models = sorted((base / "Models").glob("*.fbs"))
    if not models:
        raise RuntimeError("FlatSerialization models are missing")
    output = base / "Sources"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="flat-serialization-") as temporary:
        staging = Path(temporary)
        subprocess.run([str(root / "scripts/flatc"), "--require-explicit-ids", "--swift", "-o", str(staging)]
                       + [str(model) for model in models], check=True)
        generated = list(staging.glob("*.swift"))
        expected = {model.stem + "_generated.swift" for model in models}
        if {path.name for path in generated} != expected or any(path.stat().st_size == 0 for path in generated):
            raise RuntimeError("flatc did not produce complete Swift sources")
        for path in generated:
            destination = output / path.name
            contents = path.read_bytes()
            if destination.is_file() and destination.read_bytes() == contents:
                continue
            staged = destination.with_suffix(".swift.tmp")
            staged.write_bytes(contents)
            os.replace(staged, destination)
        names = {path.name for path in generated}
        for path in output.glob("*.swift"):
            if path.name not in names:
                path.unlink()
    print("FlatSerialization sources prepared; unchanged files preserved.")


if __name__ == "__main__":
    try:
        prepare(Path(__file__).resolve().parent.parent)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print("error: FlatSerialization generation: " + str(error), file=sys.stderr)
        sys.exit(1)
