import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("flat_generation", ROOT / "scripts/prepare-flat-serialization.py")
flat_generation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flat_generation)


def write(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)
    return path


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


class TemporaryTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="telegram ci tests ")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)


class FlatSerializationTests(TemporaryTest):
    def setUp(self):
        super().setUp()
        (self.root / "scripts").mkdir()
        (self.root / "scripts/flatc").symlink_to(ROOT / "scripts/flatc")
        base = self.root / "submodules/telegram-ios/submodules/TelegramCore/FlatSerialization"
        self.model = write(base / "Models/Sample.fbs", "namespace Test;\ntable Sample { value:int (id: 0); }\n")
        self.output = base / "Sources/Sample_generated.swift"

    def test_unchanged_generation_preserves_timestamps_and_removes_obsolete_files(self):
        flat_generation.prepare(self.root)
        before = self.output.stat().st_mtime_ns
        obsolete = write(self.output.parent / "Obsolete.swift", "obsolete")
        flat_generation.prepare(self.root)
        self.assertEqual(before, self.output.stat().st_mtime_ns)
        self.assertFalse(obsolete.exists())

    def test_changed_model_and_missing_output_are_regenerated(self):
        flat_generation.prepare(self.root)
        before = self.output.read_bytes()
        self.model.write_text("namespace Test;\ntable Sample { value:long (id: 0); }\n")
        flat_generation.prepare(self.root)
        self.assertNotEqual(before, self.output.read_bytes())
        self.output.unlink()
        flat_generation.prepare(self.root)
        self.assertTrue(self.output.is_file())

    def test_failed_generation_keeps_previous_output(self):
        flat_generation.prepare(self.root)
        before = self.output.read_bytes()
        self.model.write_text("invalid schema")
        with self.assertRaises(subprocess.CalledProcessError):
            flat_generation.prepare(self.root)
        self.assertEqual(before, self.output.read_bytes())

    def test_successful_but_incomplete_generator_does_not_publish(self):
        flat_generation.prepare(self.root)
        before = self.output.read_bytes()
        (self.root / "scripts/flatc").unlink()
        executable = write(self.root / "scripts/flatc", "#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        with self.assertRaises(RuntimeError):
            flat_generation.prepare(self.root)
        self.assertEqual(before, self.output.read_bytes())


class SyncTests(TemporaryTest):
    def test_headers_preserve_unchanged_files_repair_changes_and_remove_stale_files(self):
        source = self.root / "source"
        target = self.root / "target"
        header = write(source / "nested/API.h", "first")
        write(source / "code.cpp", "not a header")
        command = ["sh", str(ROOT / "scripts/sync-headers.sh"), str(source), str(target)]
        run(command)
        copied = target / "nested/API.h"
        before = copied.stat().st_mtime_ns
        os.utime(header, (1, 1))
        write(target / "stale.h", "stale")
        write(target / "stale.cpp", "stale")
        run(command)
        self.assertEqual(before, copied.stat().st_mtime_ns)
        self.assertEqual([str(p.relative_to(target)) for p in target.rglob("*") if p.is_file()], ["nested/API.h"])
        header.write_text("other")
        os.utime(header, ns=(before, before))
        run(command)
        self.assertEqual(copied.read_text(), "other")
        header.unlink()
        run(command)
        self.assertFalse(copied.exists())

    def test_source_sync_preserves_only_build_owned_paths(self):
        source = self.root / "checkout"
        target = self.root / "build"
        write(source / "tracked.swift", "new")
        write(target / "removed.swift", "old")
        preserved = [
            "core-xprojects/libopus/build/libopus.a",
            "core-xprojects/tlottie/build/libtlottie.a",
            "packages/WalletEngine/wallet_engineFFI.xcframework/Info.plist",
            "submodules/telegram-ios/submodules/MTProtoRustEngine/MTProtoEngineFFI.xcframework/Info.plist",
            "submodules/tgcalls/SharedHeaders/api.h",
            "submodules/telegram-ios/submodules/OpusBinding/SharedHeaders/api.h",
            ".build/telegram-api-generation/state.json",
            "submodules/telegram-ios/build-system/SwiftTL/.build/generator",
            "submodules/telegram-ios/submodules/TelegramApi/Sources/SwiftPMGenerated/Api0.swift",
            "submodules/telegram-ios/submodules/TelegramApi/ObjC/SwiftPMGenerated/Schema.m",
            "submodules/telegram-ios/submodules/TelegramApi/Tests/SwiftPMGenerated/Tests.swift",
            "submodules/telegram-ios/submodules/TelegramCore/FlatSerialization/Sources/Sample_generated.swift",
            "Telegram-Mac/Release.xcconfig",
        ]
        for name in preserved:
            write(target / name, "cached")
            write(source / name, "checkout copy")
        write(source / ".ci-build-logs/archive.log", "log")
        run(["sh", str(ROOT / "buildbox/sync-source.sh"), str(source), str(target)])
        for name in preserved:
            self.assertEqual((target / name).read_text(), "cached", name)
        self.assertFalse((target / "removed.swift").exists())
        self.assertFalse((target / ".ci-build-logs").exists())
        self.assertEqual((target / "tracked.swift").read_text(), "new")
        for name in preserved:
            (source / name).unlink()
        run(["sh", str(ROOT / "buildbox/sync-source.sh"), str(source), str(target)])
        self.assertTrue(all((target / name).exists() for name in preserved))

    def test_timing_preserves_failure_status(self):
        timing = self.root / "timings.tsv"
        environment = dict(os.environ, BUILD_TIMING_LOG=str(timing))
        result = subprocess.run(["sh", str(ROOT / "scripts/time-step.sh"), "failure", "sh", "-c", "exit 37"], env=environment, capture_output=True)
        self.assertEqual(result.returncode, 37)
        self.assertEqual(timing.read_text().split("\t")[::2], ["failure", "37\n"])


class FrameworkTests(TemporaryTest):
    libraries = ["OpenH264", "OpenSSL", "libopus", "libvpx", "mozjpeg", "libwebp", "dav1d", "ffmpeg", "webrtc", "tde2e", "wallet-engine", "mtproto-engine"]
    projects = ["OpenH264", "OpenSSLEncryption", "libopus", "libvpx", "Mozjpeg", "libwebp", "dav1d", "ffmpeg", "webrtc", "tde2e", "WalletEngine", "MTProtoEngine"]

    def setUp(self):
        super().setUp()
        for name in ["configure_frameworks.sh", "framework-inputs.sh", "sync-headers.sh", "time-step.sh", "check-wallet-engine-bindings.sh"]:
            destination = self.root / "scripts" / name
            destination.parent.mkdir(exist_ok=True)
            shutil.copy2(ROOT / "scripts" / name, destination)
        for name in ["prepare-telegram-api.py", "prepare-flat-serialization.py"]:
            write(self.root / "scripts" / name, "")
        write(self.root / "scripts/rebuild", "no")
        write(self.root / "core-xprojects/tlottie/build.sh", "exit 0\n")
        for lib, project in zip(self.libraries, self.projects):
            write(self.root / f"core-xprojects/{lib}/{project}.xcodeproj/project.pbxproj", "fixture")
        for name in ["submodules/telegram-ios/third-party/rnnoise/PublicHeaders/api.h", "submodules/telegram-ios/submodules/EncryptionProvider/PublicHeaders/api.h", "submodules/telegram-ios/third-party/mozjpeg/mozjpeg/api.h", "submodules/telegram-ios/third-party/td/td/api.h"]:
            write(self.root / name, "header")
        write(self.root / ".gitignore", "build/\nSharedHeaders/\n*.xcframework/\nruns\nbin/\nWalletEngineFFI.swift\n")
        run(["git", "init", "-q", str(self.root)])
        run(["git", "-C", str(self.root), "add", "."])
        run(["git", "-C", str(self.root), "-c", "user.name=CI Test", "-c", "user.email=ci@example.invalid", "commit", "-qm", "fixture"])
        mock_build = '''#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
while [ "$1" != "-project" ]; do shift; done
shift
LIB=$(basename "$(dirname "$1")")
echo "$LIB" >> "$ROOT/runs"
. "$ROOT/scripts/framework-inputs.sh"
mkdir -p "$ROOT/core-xprojects/$LIB/build"
if [ "$LIB" = "${FAIL_LIB:-}" ]; then exit 37; fi
framework_required_outputs "$ROOT" "$LIB" | while IFS= read -r output; do
    mkdir -p "$(dirname "$output")"
    printf 'artifact' > "$output"
done
if [ "$LIB" = "wallet-engine" ]; then
    mkdir -p "$ROOT/packages/WalletEngine/Sources/WalletEngineFFI"
    cp "$ROOT/core-xprojects/$LIB/build/WalletEngineFFI.swift" "$ROOT/packages/WalletEngine/Sources/WalletEngineFFI/WalletEngineFFI.swift"
fi
if [ "$LIB" = "${INCOMPLETE_LIB:-}" ]; then
    output=$(framework_required_outputs "$ROOT" "$LIB" | head -1)
    rm "$output"
fi
'''
        for name, contents in [("xcrun", mock_build), ("xcodebuild", "#!/bin/sh\nprintf 'Xcode fixture\\n'\n")]:
            executable = write(self.root / "bin" / name, contents)
            executable.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"])
        self.environment.pop("BUILD_TIMING_LOG", None)

    def configure(self, **environment):
        return run(["sh", str(self.root / "scripts/configure_frameworks.sh")], cwd=self.root, env=dict(self.environment, **environment))

    def runs(self):
        return (self.root / "runs").read_text().splitlines()

    def test_cold_build_then_warm_build_skips_all_framework_invocations(self):
        self.configure()
        self.assertEqual(self.runs(), self.libraries)
        self.configure()
        self.assertEqual(self.runs(), self.libraries)

    def test_missing_native_output_and_xcframework_are_repaired(self):
        self.configure()
        (self.root / "core-xprojects/libopus/build/libopus/lib/libopus.a").unlink()
        shutil.rmtree(self.root / "packages/WalletEngine/wallet_engineFFI.xcframework")
        self.configure()
        self.assertEqual(self.runs()[12:], ["libopus", "wallet-engine"])
        self.configure()
        self.assertEqual(len(self.runs()), 14)

    def test_changed_input_rebuilds_dependents_and_force_rebuilds_all(self):
        self.configure()
        write(self.root / "core-xprojects/libopus/libopus.xcodeproj/project.pbxproj", "changed")
        self.configure()
        self.assertEqual(self.runs()[12:], ["libopus", "ffmpeg", "webrtc"])
        write(self.root / "core-xprojects/libopus/libopus.xcodeproj/project.pbxproj", "changed again")
        self.configure()
        self.assertEqual(self.runs()[15:], ["libopus", "ffmpeg", "webrtc"])
        write(self.root / "scripts/rebuild", "yes")
        self.configure()
        self.assertEqual(self.runs()[-12:], self.libraries)

    def test_failed_or_incomplete_build_is_never_stamped(self):
        for variable in ["FAIL_LIB", "INCOMPLETE_LIB"]:
            with self.assertRaises(subprocess.CalledProcessError):
                self.configure(**{variable: "libopus"})
            self.assertFalse((self.root / "core-xprojects/libopus/build/.framework-stamp").exists())
        self.configure()
        self.assertTrue((self.root / "core-xprojects/libopus/build/.framework-stamp").exists())

    def test_binding_mismatch_forces_regeneration(self):
        self.configure()
        write(self.root / "packages/WalletEngine/Sources/WalletEngineFFI/WalletEngineFFI.swift", "wrong ABI")
        self.configure()
        self.assertEqual(self.runs()[12:], ["wallet-engine"])


class ArchiveTests(TemporaryTest):
    def setUp(self):
        super().setUp()
        self.source = self.root / "checkout"
        for name in ["buildbox/build-mac.sh", "buildbox/sync-source.sh", "scripts/time-step.sh"]:
            destination = self.source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        write(self.source / "scripts/configure_frameworks.sh", 'exit "${PREPARE_RESULT:-0}"\n')
        write(self.source / "Telegram-Mac/Release.xcconfig", "STABLE")
        for channel in ["Beta", "Alpha", "Stable", "Appstore", "AppStore"]:
            write(self.source / "configurations" / (channel + ".xcconfig"), channel)
        self.record = self.root / "archive-arguments.json"
        mock = write(self.root / "bin/xcodebuild", '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
Path(os.environ["ARCHIVE_RECORD"]).write_text(json.dumps(sys.argv[1:]))
if os.environ.get("ARCHIVE_RESULT"):
    print("error: deliberate archive failure")
    sys.exit(int(os.environ["ARCHIVE_RESULT"]))
archive = Path("../telegrammacos.xcarchive")
app = archive / "Products/Applications/Telegram.app/Contents"
app.mkdir(parents=True, exist_ok=True)
(app / "Info.plist").write_text("fixture")
symbols = archive / "dSYMs/Telegram.app.dSYM"
symbols.mkdir(parents=True, exist_ok=True)
(symbols / "symbols").write_text("symbols")
print("Build Timing Summary\\nCompileSwift: fixture")
''')
        mock.chmod(0o755)
        self.logs = self.source / ".ci-build-logs/job"
        self.logs.mkdir(parents=True)
        self.environment = dict(os.environ, PATH=str(mock.parent) + os.pathsep + os.environ["PATH"],
                                TELEGRAM_BUILD_ROOT=str(self.root / "builds"), ARCHIVE_RECORD=str(self.record),
                                CI_BUILD_LOG_DIR=str(self.logs), BUILD_TIMING_LOG=str(self.logs / "timings.tsv"))
        self.environment.pop("TELEGRAM_COMPILATION_CACHE", None)

    def build(self, channel="Beta", **environment):
        return run(["sh", "buildbox/build-mac.sh", channel], cwd=self.source, env=dict(self.environment, **environment))

    def test_release_channels_keep_flags_archive_symbols_and_logs(self):
        for channel, condition in [("Beta", "BETA"), ("Alpha", "ALPHA"), ("Stable", "STABLE"), ("Appstore", "APP_STORE"), ("AppStore", "APP_STORE")]:
            self.build(channel)
            arguments = json.loads(self.record.read_text())
            self.assertIn("SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) " + condition, arguments)
            self.assertIn("-showBuildTimingSummary", arguments)
            self.assertNotIn("-quiet", arguments)
            self.assertFalse(any(arg.startswith("COMPILATION_CACHE_ENABLE_CACHING=") for arg in arguments))
            output = self.root / "builds" / ("build-" + channel)
            self.assertTrue((output / "Telegram.app/Contents/Info.plist").exists())
            self.assertTrue((output / "Telegram.app.DSYM.zip").exists())
            self.assertIn("CompileSwift", (self.logs / "xcodebuild.log").read_text())
            self.assertTrue((self.logs / "frameworks.log").exists())

    def test_warm_archive_preserves_channel_config_and_cache_is_opt_in(self):
        self.build()
        config = self.root / "builds/build-Beta/telegrammacos/Telegram-Mac/Release.xcconfig"
        before = config.stat().st_mtime_ns
        self.build(TELEGRAM_COMPILATION_CACHE="YES")
        self.assertEqual(before, config.stat().st_mtime_ns)
        self.assertIn("COMPILATION_CACHE_ENABLE_CACHING=YES", json.loads(self.record.read_text()))
        self.build(TELEGRAM_COMPILATION_CACHE="NO")
        self.assertIn("COMPILATION_CACHE_ENABLE_CACHING=NO", json.loads(self.record.read_text()))

    def test_failed_preparation_never_archives_and_failed_archive_never_packages(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.build(PREPARE_RESULT="31")
        self.assertFalse(self.record.exists())
        self.build()
        with self.assertRaises(subprocess.CalledProcessError):
            self.build(ARCHIVE_RESULT="37")
        self.assertFalse((self.root / "builds/build-Beta/Telegram.app").exists())
        self.assertIn("deliberate archive failure", (self.logs / "xcodebuild.log").read_text())


class TlottieTests(TemporaryTest):
    def test_warm_build_preserves_library_and_does_not_reinstall_toolchain(self):
        script = self.root / "core-xprojects/tlottie/build.sh"
        script.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "core-xprojects/tlottie/build.sh", script)
        write(self.root / "submodules/tlottie/Cargo.toml", "fixture")
        write(self.root / "submodules/telegram-ios/third-party/mtproto-engine/rust-toolchain.toml", 'channel = "fixture"\n')
        cargo = write(self.root / "bin/cargo", '''#!/bin/sh
set -e
while [ "$1" != "--target" ]; do shift; done
shift
mkdir -p "$CARGO_TARGET_DIR/$1/release"
printf '%s' "${LIBRARY_CONTENT:-library}" > "$CARGO_TARGET_DIR/$1/release/libtlottie.a"
''')
        rustup = write(self.root / "bin/rustup", '''#!/bin/sh
if [ "$1" = "run" ]; then exit 0; fi
if [ "$1 $2" = "target list" ]; then printf 'aarch64-apple-darwin\\nx86_64-apple-darwin\\n'; exit 0; fi
echo "unexpected rustup installation" >&2
exit 37
''')
        lipo = write(self.root / "bin/lipo", '''#!/bin/sh
if [ "$1" = "-info" ]; then exit 0; fi
cat "$2" "$3" > "$5"
''')
        for executable in [cargo, rustup, lipo]:
            executable.chmod(0o755)
        environment = dict(os.environ, CARGO=str(cargo), PATH=str(cargo.parent) + os.pathsep + os.environ["PATH"])
        run(["sh", str(script)], env=environment)
        output = script.parent / "build/libtlottie.a"
        before = output.stat().st_mtime_ns
        run(["sh", str(script)], env=environment)
        self.assertEqual(before, output.stat().st_mtime_ns)
        run(["sh", str(script)], env=dict(environment, LIBRARY_CONTENT="changed"))
        self.assertEqual(output.read_text(), "changedchanged")


if __name__ == "__main__":
    unittest.main()
