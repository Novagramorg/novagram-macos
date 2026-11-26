import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source',type=Path,default=root/'packages/StoriesUI/Sources/StoriesUI/StoryChatContent.swift')
args=parser.parse_args(); source=args.source.read_text()
def block(marker, source=source):
 start=source.index(marker); brace=source.index('{',start); end=brace+1; depth=1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}'); end+=1
 return source[start:end].replace('public ','')
current='private final class StoryMediaPreloadContext' in source
production='\n'.join(block(m) for m in ['private struct StoryKey:', 'private func storyPreloadInfos(', 'private final class StoryMediaPreloadContext', 'public final class StoryContentItem', 'public final class StoryContentContextState'] if m in source)
info=(root/'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift').read_text()
production+='\n'+block('public final class StoryPreloadInfo',info)
feed=source[source.index('    private func updateState()'):]
start=feed.index('        let preloadInfos =') if current else feed.index('        var nextPriority = 0')
feed_end='        self.storyMetadataRefresh.update(' if 'private final class StoryMetadataRefreshContext' in source else '        var pollIdByPeerId:'
feed=feed[start:feed.index(feed_end,start)]
listing=source[source.index('public final class PeerStoryListContentContextImpl'):]
start=listing.index('            if self.stateValue == nil || self.stateValue?.slice != stateValue.slice')
list_end='                self.storyMetadataRefresh.update(' if 'private final class StoryMetadataRefreshContext' in source else '                var pollIdByPeerId:'
listing=listing[start:listing.index(list_end,start)]+'\n            }\n'
fixture=Path(__file__).with_name('StoryPreloadFreshnessTests.swift').read_text()
properties='private let preloadStoryResources = StoryMediaPreloadContext()' if current else 'var preloadStoryResourceDisposables: [MediaId: Disposable] = [:]'
dispose='preloadStoryResources.dispose()' if current else 'for d in preloadStoryResourceDisposables.values { d.dispose() }; preloadStoryResourceDisposables.removeAll()'
for key,value in [('__PRODUCTION__',production),('__FEED__',feed),('__LIST__',listing),('__PROPERTIES__',properties),('__DISPOSE__',dispose),('__MANAGER_TESTS__',Path(__file__).with_name('ManagerTests.swift').read_text() if current else '')]: fixture=fixture.replace(key,value)
with tempfile.TemporaryDirectory(prefix='story-preload-freshness-') as directory:
 p=Path(directory); dep=json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))
 (p/'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "StoryPreloadFreshness", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '+dep+')], targets: [.testTarget(name: "StoryPreloadFreshnessTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
 (p/'Tests').mkdir(); (p/'Tests/StoryPreloadFreshnessTests.swift').write_text(fixture)
 raise SystemExit(subprocess.run(['swift','test','--package-path',str(p),'--disable-sandbox','--jobs','4']).returncode)
