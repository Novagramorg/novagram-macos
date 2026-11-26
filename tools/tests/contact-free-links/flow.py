from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / "Telegram-Mac/utils/InAppLinks.swift").read_text()
start = source.index("private func openNoPaidMessagesPeer(")
helper = source[start:source.index("\nprivate final class InAppLinkOrigin", start)]
start = source.index("    case let .contactToken(_, token, freeToken, context, callback):")
body = source[start:source.index("    case let .noPaidMessagesToken(_, username", start)].split("\n", 1)[1]
flow = "func openContact(token: String, freeToken: String?, context: AccountContext, callback: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) {\n" + body + "}\n"
tests = Path(__file__).with_name("ContactFlowTests.swift").read_text().replace("__PRODUCTION__", helper + flow)
with tempfile.TemporaryDirectory(prefix="contact-flow-") as directory:
    path = Path(directory)
    dependency = json.dumps(str(root / "submodules/telegram-ios/submodules/SSignalKit"))
    (path / "Package.swift").write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "ContactFlow", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + dependency + ')], targets: [.testTarget(name: "ContactFlowTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (path / "Tests").mkdir()
    (path / "Tests/ContactFlowTests.swift").write_text(tests)
    raise SystemExit(subprocess.run(["swift", "test", "--package-path", str(path), "--disable-sandbox", "--jobs", "4"]).returncode)
