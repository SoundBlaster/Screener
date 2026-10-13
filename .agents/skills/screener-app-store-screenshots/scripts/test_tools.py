"""Focused orchestration checks; no Xcode, Simulator or network required."""
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("screenshot_runner", HERE / "run.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
sys.path.insert(0, str(HERE))
import run_macos


class ScreenshotToolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def install(self, app="App", tests="AppUITests", platform="iOS"):
        return subprocess.run([sys.executable, str(HERE / "install.py"), "--root", str(self.root),
                               "--app-sources", app, "--test-sources", tests, "--platform", platform], capture_output=True)

    def test_macos_installer_selects_appkit_and_window_adapters(self):
        self.assertEqual(self.install(platform="macOS").returncode, 0)
        manifest = json.loads((self.root / "screenshots/tool-provenance.json").read_text())
        self.assertEqual(len(manifest), 6)
        for item in manifest:
            self.assertEqual(runner.digest(self.root / item["target"]), item["sha256"])
        self.assertTrue((self.root / "screenshots/tools/run_macos.py").is_file())
        self.assertIn("AppKit", (self.root / "App/ScreenshotHarness.swift").read_text())

    def test_macos_native_geometry_configuration(self):
        config = {"platform": "macOS", "orientations": ["window"], "locales": ["en-US"],
                  "checkpoints": ["01-main"], "windowPoints": [1280, 800], "nativeWindowPixels": [2560, 1600]}
        run_macos.validate(config)
        with self.assertRaisesRegex(ValueError, "never resample"):
            run_macos.validate(config | {"nativeWindowPixels": [2560, 800]})
        with self.assertRaisesRegex(ValueError, "unique safe names"):
            run_macos.validate(config | {"locales": ["../escape"]})

    def test_macos_plan_uses_host_relative_bundle_path(self):
        target = {"BlueprintName": "AppUITests", "TestBundlePath": "__TESTHOST__/Contents/PlugIns/AppUITests.xctest",
                  "TestHostPath": "__TESTROOT__/Screenshots/AppUITests-Runner.app"}
        config = {"testTarget": "AppUITests", "buildConfiguration": "Screenshots"}
        self.assertTrue(run_macos.matches_plan({"TestConfigurations": [{"TestTargets": [target]}]}, config))
        self.assertFalse(run_macos.matches_plan({"TestTargets": [target]}, config | {"buildConfiguration": "Release"}))

    def test_installer_provenance_and_no_overwrite(self):
        self.assertEqual(self.install().returncode, 0)
        manifest = json.loads((self.root / "screenshots/tool-provenance.json").read_text())
        self.assertEqual(len(manifest), 4)
        for item in manifest:
            self.assertEqual(runner.digest(self.root / item["target"]), item["sha256"])
        target = self.root / "App/ScreenshotHarness.swift"
        target.write_text("user edit")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(target.read_text(), "user edit")

    def test_installer_preflight_no_partial_copy(self):
        (self.root / "AppUITests").mkdir()
        (self.root / "AppUITests/ScreenshotScenario.swift").write_text("existing")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertFalse((self.root / "screenshots").exists())

    def test_installer_rejects_escape(self):
        self.assertNotEqual(self.install(app="../outside").returncode, 0)
        self.assertFalse((self.root / "screenshots").exists())

    def test_preparation_rejects_incomplete_collection(self):
        runner.write_json(self.root / "manifest.json", {"collectionComplete": False})
        with self.assertRaisesRegex(ValueError, "Collection is not complete"):
            runner.prepare(self.root, None)

    def test_closed_and_ordered_timeline(self):
        trace = self.root / "trace.vtrace"
        trace.mkdir()
        timeline = trace / "timeline.jsonl"
        timeline.write_text('{"sequence":0,"kind":"sessionStarted"}\n')
        with self.assertRaises(ValueError):
            runner.read_timeline(trace)
        timeline.write_text('{"sequence":0,"kind":"sessionStarted"}\n{"sequence":2,"kind":"sessionEnded"}\n')
        with self.assertRaises(ValueError):
            runner.read_timeline(trace)
        timeline.write_text('{"sequence":0,"kind":"sessionStarted"}\n{"sequence":1,"kind":"sessionEnded"}\n')
        self.assertEqual(len(runner.read_timeline(trace)), 2)

    def fixture(self, checkpoint="01-main", stopped=True):
        cache = self.root / "cache"
        run = cache / "uuid"
        trace = run / "trace.vtrace"
        trace.mkdir(parents=True)
        (run / "system").mkdir()
        if stopped:
            (run / "stopped.json").write_text("{}")
        png = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\x0dIHDR" + struct.pack(">II", 10, 20) + bytes([8, 2, 0, 0, 0])
        (trace / "frame.png").write_bytes(png)
        (run / "system/01-main.png").write_bytes(png)
        rows = [
            {"kind": "sessionStarted", "name": "start"},
            {"kind": "marker", "name": "screenshots.ready", "metadata": {"orientation": "portrait"}},
            {"kind": "marker", "name": "screenshots.checkpoint", "metadata": {"name": checkpoint, "pointWidth": "5", "pointHeight": "10"}},
            {"kind": "keyframe", "name": checkpoint, "id": "frame", "blob": "frame.png", "metadata": {"scale": "2"}},
            {"kind": "sessionEnded", "name": "end"}]
        for index, row in enumerate(rows):
            row["sequence"] = index
        (trace / "timeline.jsonl").write_text("".join(json.dumps(row) + "\n" for row in rows))
        config = {"orientations": ["portrait"], "nativePortraitPixels": [10, 20], "checkpoints": ["01-main"], "locales": ["en-US"]}
        return cache, config

    def test_collect_pair_and_detect_changed_raw(self):
        cache, config = self.fixture()
        out = self.root / "output"
        assets = runner.collect(cache, set(), out, "en-US", config)
        self.assertEqual(len(assets), 2)
        runner.write_json(out / "manifest.json", {"collectionComplete": True, "configuration": config, "assets": assets})
        (out / assets[0]["source"]).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "Raw capture changed"):
            runner.prepare(out, None)

    def test_collect_rejects_wrong_checkpoint(self):
        cache, config = self.fixture(checkpoint="unexpected")
        with self.assertRaisesRegex(ValueError, "checkpoints"):
            runner.collect(cache, set(), self.root / "output", "en-US", config)

    def test_collect_rejects_unacknowledged_stop(self):
        cache, config = self.fixture(stopped=False)
        with self.assertRaisesRegex(ValueError, "stop"):
            runner.collect(cache, set(), self.root / "output", "en-US", config)

    def test_resume_metrics_preserve_capture_metrics(self):
        original = {"elapsedSeconds": 123, "operations": []}
        runner.write_json(self.root / "metrics.json", original)
        recovery = runner.Runner(self.root, [], self.root, "preparation-metrics.json")
        recovery.run(sys.executable, "-c", "pass")
        self.assertEqual(json.loads((self.root / "metrics.json").read_text()), original)
        self.assertEqual(len(json.loads((self.root / "preparation-metrics.json").read_text())["operations"]), 1)

    def test_macos_window_pair_requires_exact_system_geometry(self):
        cache, config = self.fixture()
        trace = cache / "uuid/trace.vtrace/timeline.jsonl"
        trace.write_text(trace.read_text().replace('"portrait"', '"window"'))
        config.update(platform="macOS", orientations=["window"], nativeWindowPixels=[10, 20])
        self.assertEqual(len(runner.collect(cache, set(), self.root / "valid", "en-US", config)), 2)
        system = cache / "uuid/system/01-main.png"
        data = bytearray(system.read_bytes())
        data[16:24] = struct.pack(">II", 20, 10)
        system.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "Non-native"):
            runner.collect(cache, set(), self.root / "invalid", "en-US", config)


if __name__ == "__main__":
    unittest.main()
