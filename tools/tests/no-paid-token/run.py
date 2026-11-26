from pathlib import Path
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parents[3]
core = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "submodules/telegram-ios"
source = (core / "submodules/TelegramCore/Sources/TelegramEngine/Peers/NoPaidMessagesToken.swift").read_text()
schema = (core / "submodules/TelegramApi/swift_scheme.tl").read_text()
assert "exportedNoPaidMessagesToken#695dd042 flags:# token:string url:string" in schema
assert "exportedNoPaidMessagesTokenLegacy#cf5105be flags:# token:string url:flags.0?string" in schema
model = source[source.index("public struct ExportedNoPaidMessagesToken:"):source.index("public enum ImportNoPaidMessagesTokenError")]
start = source.index("        guard let result else { return nil }")
mapping = source[start:source.index("\n    }\n}", start)]
fixture = """
import Foundation
enum Api {
    struct Current { let token: String; let url: String; let expires: Int32? }
    struct Legacy { let token: String; let url: String?; let expires: Int32? }
    enum ExportedNoPaidMessagesToken {
        case exportedNoPaidMessagesToken(Current)
        case exportedNoPaidMessagesTokenLegacy(Legacy)
    }
}
""" + model + "\nfunc convert(_ result: Api.ExportedNoPaidMessagesToken?) -> ExportedNoPaidMessagesToken? {\n" + mapping + "\n}\n" + """
precondition(convert(nil) == nil)
for expires: Int32? in [nil, 1800000000] {
    let current = convert(.exportedNoPaidMessagesToken(.init(token: "token", url: "https://t.me/contact/test", expires: expires)))!
    precondition(current.token == "token" && current.url == "https://t.me/contact/test" && current.expires == expires)
    for url: String? in [nil, "", "https://t.me/user?free=token"] {
        let legacy = convert(.exportedNoPaidMessagesTokenLegacy(.init(token: "legacy", url: url, expires: expires)))!
        precondition(legacy.token == "legacy" && legacy.url == (url ?? "") && legacy.expires == expires)
    }
}
print("No-paid token conversion: 9 cases passed")
"""
with tempfile.TemporaryDirectory(prefix="no-paid-token-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(fixture)
    subprocess.run(["swift", "-module-cache-path", str(Path(directory) / "cache"), str(path)], check=True)
