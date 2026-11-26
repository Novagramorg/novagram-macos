#!/usr/bin/env python3
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


OUTPUT_DIRECTORIES = ("Sources/SwiftPMGenerated", "ObjC/SwiftPMGenerated", "Tests/SwiftPMGenerated")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def host_environment():
    environment = os.environ.copy()
    for name in list(environment):
        if name in ["SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "TOOLCHAINS", "SWIFT_EXEC", "SWIFT_DRIVER_TOOLCHAIN_PATH"] or name.startswith("SWIFT_DEBUG_"):
            environment.pop(name)
    return environment


def inputs(root):
    upstream = root / "submodules/telegram-ios"
    api = upstream / "submodules/TelegramApi"
    generator = upstream / "build-system/SwiftTL"
    paths = [api / "swift_scheme.tl", api / "generate-swiftpm.sh", generator / "Package.swift"]
    paths += sorted((generator / "Sources").rglob("*.swift"))
    if not (generator / "Sources").is_dir():
        raise RuntimeError("SwiftTL sources are missing; initialize the telegram-ios submodule")
    return {
        "files": {str(path.relative_to(root)): digest(path) for path in paths},
        "preparation": digest(Path(__file__)),
        "swiftExecutable": subprocess.check_output(["xcrun", "--find", "swift"], env=host_environment(), text=True, stderr=subprocess.DEVNULL).strip(),
        "toolchain": subprocess.check_output(["xcrun", "swift", "--version"], env=host_environment(), text=True, stderr=subprocess.DEVNULL).strip(),
    }


def outputs(api):
    return {
        str(path.relative_to(api)): digest(path)
        for directory in OUTPUT_DIRECTORIES
        for path in sorted((api / directory).rglob("*"))
        if path.is_file()
    }


def validate_outputs(api):
    required = ["Sources/SwiftPMGenerated/Api0.swift", "ObjC/SwiftPMGenerated/TLApiSchemaData.m",
                "Tests/SwiftPMGenerated/SchemaFixtures.swift", "Tests/SwiftPMGenerated/SchemaAccessorProbes.swift"]
    for path in required:
        if not (api / path).is_file() or (api / path).stat().st_size == 0:
            raise RuntimeError("generator did not produce " + path)
    if "tlTypeRegistry" not in (api / required[0]).read_text():
        raise RuntimeError("generated Api0.swift has no tlTypeRegistry")


def prepare(root, check=False):
    api = root / "submodules/telegram-ios/submodules/TelegramApi"
    generator = root / "submodules/telegram-ios/build-system/SwiftTL"
    state = root / ".build/telegram-api-generation"
    if check and not (state / "lock").exists():
        raise RuntimeError("generated sources have not been prepared; run python3 scripts/prepare-telegram-api.py before opening Xcode or resolving packages")
    if not check:
        state.mkdir(parents=True, exist_ok=True)
    with (state / "lock").open("r" if check else "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_SH if check else fcntl.LOCK_EX)
        current_inputs = inputs(root)
        stamp = state / "state.json"
        try:
            saved = json.loads(stamp.read_text())
        except (OSError, ValueError):
            saved = {}
        current_outputs = outputs(api)
        if saved.get("inputs") == current_inputs and current_outputs and saved.get("outputs") == current_outputs:
            print("TelegramApi generated sources are up to date.")
            return
        if check:
            raise RuntimeError("generated sources are missing or stale; run python3 scripts/prepare-telegram-api.py before opening Xcode or resolving packages")
        print("Generating TelegramApi SwiftPM sources...", flush=True)
        with tempfile.TemporaryDirectory(prefix="generation-", dir=state) as temporary:
            staging = Path(temporary)
            staged_api = staging / "submodules/TelegramApi"
            staged_api.mkdir(parents=True)
            (staging / "build-system").mkdir()
            (staging / "build-system/SwiftTL").symlink_to(generator, target_is_directory=True)
            for name in ["generate-swiftpm.sh", "swift_scheme.tl"]:
                shutil.copy2(api / name, staged_api / name)
            environment = host_environment()
            environment["PATH"] = str(Path(current_inputs["swiftExecutable"]).parent) + os.pathsep + environment.get("PATH", "")
            subprocess.run(["/bin/bash", str(staged_api / "generate-swiftpm.sh")], env=environment, check=True)
            validate_outputs(staged_api)
            if inputs(root) != current_inputs:
                raise RuntimeError("generator inputs changed during generation; retry the build")
            generated = outputs(staged_api)
            for relative, checksum in generated.items():
                destination = api / relative
                if current_outputs.get(relative) == checksum:
                    continue
                destination.parent.mkdir(parents=True, exist_ok=True)
                staged_file = destination.with_name(destination.name + ".tmp")
                shutil.copy2(staged_api / relative, staged_file)
                os.replace(staged_file, destination)
            for relative in current_outputs.keys() - generated.keys():
                (api / relative).unlink()
            staged_stamp = state / "state.json.tmp"
            staged_stamp.write_text(json.dumps({"inputs": current_inputs, "outputs": generated}, sort_keys=True) + "\n")
            os.replace(staged_stamp, stamp)
        print("TelegramApi generated sources are ready.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        prepare(Path(__file__).resolve().parent.parent, check=args.check)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print("error: TelegramApi generation: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
