import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("prepare_telegram_api", ROOT / "scripts/prepare-telegram-api.py")
generation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generation)


class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="telegram api generation ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.api = self.root / "submodules/telegram-ios/submodules/TelegramApi"
        self.generator = self.root / "submodules/telegram-ios/build-system/SwiftTL"
        self.api.mkdir(parents=True)
        (self.generator / "Sources").mkdir(parents=True)
        (self.generator / "Sources/main.swift").write_text("generator v1")
        (self.generator / "Package.swift").write_text("package v1")
        (self.api / "swift_scheme.tl").write_text("schema v1")
        (self.api / "generate-swiftpm.sh").write_text('''set -euo pipefail
cd "$(dirname "$0")"
printf 'run\\n' >> ../../build-system/SwiftTL/runs
mkdir -p Sources/SwiftPMGenerated ObjC/SwiftPMGenerated Tests/SwiftPMGenerated
printf 'let tlTypeRegistry = []\\n' > Sources/SwiftPMGenerated/Api0.swift
cat swift_scheme.tl >> Sources/SwiftPMGenerated/Api0.swift
if grep -q FAIL swift_scheme.tl; then exit 7; fi
printf 'data\\n' > ObjC/SwiftPMGenerated/TLApiSchemaData.m
printf 'fixtures\\n' > Tests/SwiftPMGenerated/SchemaFixtures.swift
printf 'probes\\n' > Tests/SwiftPMGenerated/SchemaAccessorProbes.swift
''')
        self.toolchain = patch.object(generation.subprocess, "check_output", return_value="Swift fixture 1")
        self.toolchain.start()
        self.addCleanup(self.toolchain.stop)

    def prepare(self, check=False):
        generation.prepare(self.root, check=check)

    def runs(self):
        return (self.generator / "runs").read_text().count("run\n")

    def test_clean_checkout_and_incremental_build_preserve_output_timestamps(self):
        self.prepare()
        before = {p: (self.api / p).stat().st_mtime_ns for p in generation.outputs(self.api)}
        self.prepare()
        self.prepare(check=True)
        self.assertEqual(self.runs(), 1)
        self.assertEqual(before, {p: (self.api / p).stat().st_mtime_ns for p in before})

    def test_schema_generator_and_manifest_edits_invalidate(self):
        self.prepare()
        for index, path in enumerate([self.api / "swift_scheme.tl", self.generator / "Sources/main.swift", self.generator / "Package.swift", self.api / "generate-swiftpm.sh"], 2):
            path.write_text(path.read_text() + "\n")
            with self.assertRaises(RuntimeError):
                self.prepare(check=True)
            self.prepare()
            self.assertEqual(self.runs(), index)

    def test_output_deletion_corruption_and_extra_files_are_repaired(self):
        self.prepare()
        paths = list(generation.outputs(self.api))
        for relative in paths:
            (self.api / relative).unlink()
            with self.assertRaises(RuntimeError):
                self.prepare(check=True)
            self.prepare()
            self.assertTrue((self.api / relative).is_file())
        (self.api / paths[0]).write_text("corrupted")
        extra = self.api / "Sources/SwiftPMGenerated/Obsolete.swift"
        extra.write_text("obsolete")
        self.prepare()
        self.assertFalse(extra.exists())
        self.prepare(check=True)

    def test_failed_generation_preserves_outputs_and_fails_validation(self):
        self.prepare()
        before = generation.outputs(self.api)
        (self.api / "swift_scheme.tl").write_text("FAIL")
        with self.assertRaises(subprocess.CalledProcessError):
            self.prepare()
        self.assertEqual(generation.outputs(self.api), before)
        with self.assertRaises(RuntimeError):
            self.prepare(check=True)
        (self.api / "swift_scheme.tl").write_text("repaired")
        self.prepare()
        self.prepare(check=True)

    def test_missing_generation_output_does_not_publish(self):
        self.prepare()
        before = generation.outputs(self.api)
        path = self.api / "generate-swiftpm.sh"
        path.write_text(path.read_text() + "rm Tests/SwiftPMGenerated/SchemaAccessorProbes.swift\n")
        with self.assertRaises(RuntimeError):
            self.prepare()
        self.assertEqual(generation.outputs(self.api), before)

    def test_inputs_changed_during_generation_do_not_publish(self):
        self.prepare()
        before = generation.outputs(self.api)
        path = self.api / "generate-swiftpm.sh"
        path.write_text(path.read_text() + "printf 'changed' >> ../../build-system/SwiftTL/Sources/main.swift\n")
        with self.assertRaisesRegex(RuntimeError, "inputs changed"):
            self.prepare()
        self.assertEqual(generation.outputs(self.api), before)

    def test_unprepared_checkout_fails_validation(self):
        with self.assertRaisesRegex(RuntimeError, "have not been prepared"):
            self.prepare(check=True)

    def test_concurrent_builds_generate_once(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            list(executor.map(lambda _: self.prepare(), range(4)))
        self.assertEqual(self.runs(), 1)
        self.prepare(check=True)

    def test_toolchain_changes_invalidate(self):
        self.prepare()
        with patch.object(generation.subprocess, "check_output", return_value="Swift fixture 2"):
            with self.assertRaises(RuntimeError):
                self.prepare(check=True)
            self.prepare()
        self.assertEqual(self.runs(), 2)

    def test_xcode_target_settings_do_not_leak_into_host_generator(self):
        with patch.dict(os.environ, {"SDKROOT": "iphoneos", "SWIFT_DEBUG_INFORMATION_FORMAT": "dwarf", "TOOLCHAINS": "Metal XcodeDefault", "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}):
            environment = generation.host_environment()
            self.assertNotIn("SDKROOT", environment)
            self.assertNotIn("SWIFT_DEBUG_INFORMATION_FORMAT", environment)
            self.assertNotIn("TOOLCHAINS", environment)
            self.assertEqual(environment["DEVELOPER_DIR"], "/Applications/Xcode.app/Contents/Developer")


class IntegrationTests(unittest.TestCase):
    def test_shared_app_schemes_prepare_before_build(self):
        for name in ["Telegram", "Release", "TelegramShare"]:
            scheme = ET.parse(ROOT / f"Telegram.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme")
            actions = scheme.findall("BuildAction/PreActions/ExecutionAction/ActionContent")
            self.assertTrue(any('python3 "$SRCROOT/scripts/prepare-telegram-api.py"' in action.get("scriptText", "") and action.find("EnvironmentBuildable/BuildableReference") is not None for action in actions))

    def test_ci_prepares_before_xcode_and_targets_check_freshness(self):
        configure = (ROOT / "scripts/configure_frameworks.sh").read_text()
        self.assertLess(configure.index("prepare-telegram-api.py"), configure.index("xcrun xcodebuild"))
        for name, build in [("build-mac.sh", "xcodebuild archive"), ("build-vm.sh", "fastlane Release")]:
            script = (ROOT / "buildbox" / name).read_text()
            self.assertLess(script.index("scripts/configure_frameworks.sh"), script.index(build))
        project = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(ROOT / "Telegram.xcodeproj/project.pbxproj")]))
        for target in project["objects"].values():
            if target.get("isa") == "PBXNativeTarget" and target["name"] in ["Telegram", "TelegramShare"]:
                phase = project["objects"][target["buildPhases"][0]]
                self.assertIn('prepare-telegram-api.py" --check', phase["shellScript"])
                self.assertEqual(phase["alwaysOutOfDate"], "1")


if __name__ == "__main__":
    unittest.main()
