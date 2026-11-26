import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=Path,default=root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift')
parser.add_argument('--request-source',type=Path,default=root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift')
parser.add_argument('--list-source',type=Path,default=root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/StoryListContext.swift')
parser.add_argument('--skip-ordering-lifecycle',action='store_true')
args=parser.parse_args()
def block(source,marker):
 start=source.index(marker); brace=source.index('{',start); end=brace+1; depth=1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}'); end+=1
 return source[start:end].replace('public ','')
fixture=Path(__file__).with_name('StoryViewRefreshTests.swift').read_text()
if args.skip_ordering_lifecycle:
 fixture=fixture[:fixture.index('    func testTerminalRequestsReleaseTicketsWithoutExplicitDisposal()')]+'}\n'
fixture=fixture.replace('__METHOD__',block(args.source.read_text(),'        public func refreshStoryViews(')).replace('__REQUEST__',block(args.request_source.read_text(),'func _internal_getStoryViews('))
facade_source=args.source.read_text()
if 'final class StoryViewRefreshContext {' not in facade_source:
 facade_source=(root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift').read_text()
fixture=fixture.replace('__ORDERING_CONTEXT__',block(facade_source,'final class StoryViewRefreshContext {'))
reaction_source=(root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift').read_text()
fixture=fixture.replace('__REACTION_CONTEXT__',block(reaction_source,'final class StoryReactionContext {'))
account_source=(root/'submodules/telegram-ios/submodules/TelegramCore/Sources/Account/Account.swift').read_text()
property_line=next(line.strip() for line in account_source.splitlines() if 'storyViewRefreshContext' in line and ('let ' in line or 'var ' in line))
fixture=fixture.replace('__ACCOUNT_ORDERING_PROPERTY__',property_line)
source=args.list_source.read_text()
fixture=fixture.replace('__HELPERS__','\n'.join(block(source,m) for m in ['private func _internal_storyWithViews(', 'func _internal_applyStoryViews(']))
with tempfile.TemporaryDirectory(prefix='story-view-refresh-') as directory:
 p=Path(directory); dep=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
 (p/'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "StoryViewRefresh", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '+dep+')], targets: [.testTarget(name: "StoryViewRefreshTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
 (p/'Tests').mkdir(); (p/'Tests/StoryViewRefreshTests.swift').write_text(fixture)
 raise SystemExit(subprocess.run(['swift','test','--package-path',str(p),'--disable-sandbox','--jobs','4']).returncode)
