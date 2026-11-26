#import "TLottieBridge.h"

#include <tlottie.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace {

class KeyPath {
public:
    explicit KeyPath(const std::string &keyPath) {
        std::stringstream stream(keyPath);
        std::string item;
        while (std::getline(stream, item, '.')) {
            _keys.push_back(item);
        }
    }

    bool isEmpty() const {
        return _keys.empty();
    }

    bool matches(const std::string &key, size_t depth) const {
        if (skip(key)) {
            return true;
        }
        if (depth > size()) {
            return false;
        }
        return _keys[depth] == key || _keys[depth] == "*" || _keys[depth] == "**";
    }

    size_t nextDepth(const std::string &key, size_t depth) const {
        if (skip(key)) {
            return depth;
        }
        if (_keys[depth] != "**") {
            return depth + 1;
        }
        if (depth == size()) {
            return depth;
        }
        if (_keys[depth + 1] == key) {
            return depth + 2;
        }
        return depth;
    }

    bool fullyResolvesTo(const std::string &key, size_t depth) const {
        if (depth >= _keys.size()) {
            return false;
        }
        const bool isLastDepth = depth == size();
        if (!isGlobstar(depth)) {
            const bool matched = _keys[depth] == key || isGlob(depth);
            return (isLastDepth || (depth == size() - 1 && endsWithGlobstar())) && matched;
        }
        const bool nextKeyMatches = !isLastDepth && _keys[depth + 1] == key;
        if (nextKeyMatches) {
            return depth == size() - 1 || (depth == size() - 2 && endsWithGlobstar());
        }
        if (isLastDepth) {
            return true;
        }
        if (depth + 1 < size()) {
            return false;
        }
        return _keys[depth + 1] == key;
    }

    bool propagate(const std::string &key, size_t depth) const {
        return skip(key) ? true : (depth < size()) || (_keys[depth] == "**");
    }

private:
    bool skip(const std::string &key) const {
        return key == "__";
    }
    bool isGlobstar(size_t depth) const {
        return _keys[depth] == "**";
    }
    bool isGlob(size_t depth) const {
        return _keys[depth] == "*";
    }
    bool endsWithGlobstar() const {
        return _keys.back() == "**";
    }
    size_t size() const {
        return _keys.size() - 1;
    }

    std::vector<std::string> _keys;
};

struct KeyPathColor {
    std::string keyPath;
    double red;
    double green;
    double blue;
};

std::string NameOf(NSDictionary *object) {
    id name = object[@"nm"];
    if ([name isKindOfClass:[NSString class]]) {
        return std::string([name UTF8String]);
    }
    return std::string();
}

void ResolveContent(NSMutableDictionary *content, const KeyPath &keyPath, size_t depth, NSDictionary *color) {
    id type = content[@"ty"];
    if (![type isKindOfClass:[NSString class]]) {
        return;
    }
    const std::string name = NameOf(content);
    if ([type isEqualToString:@"gr"]) {
        if (!keyPath.matches(name, depth) || !keyPath.propagate(name, depth)) {
            return;
        }
        const size_t next = keyPath.nextDepth(name, depth);
        id items = content[@"it"];
        if ([items isKindOfClass:[NSArray class]]) {
            for (id item in items) {
                if ([item isKindOfClass:[NSMutableDictionary class]]) {
                    ResolveContent(item, keyPath, next, color);
                }
            }
        }
    } else if ([type isEqualToString:@"fl"] || [type isEqualToString:@"st"]) {
        if (keyPath.matches(name, depth) && keyPath.fullyResolvesTo(name, depth)) {
            content[@"c"] = color;
        }
    }
}

void ResolveLayer(NSMutableDictionary *layer, const KeyPath &keyPath, size_t depth, NSDictionary *assets, NSDictionary *color) {
    const std::string name = NameOf(layer);
    if (!keyPath.matches(name, depth) || !keyPath.propagate(name, depth)) {
        return;
    }
    const size_t next = keyPath.nextDepth(name, depth);
    id type = layer[@"ty"];
    if (![type isKindOfClass:[NSNumber class]]) {
        return;
    }
    if ([type integerValue] == 4) {
        id shapes = layer[@"shapes"];
        if ([shapes isKindOfClass:[NSArray class]]) {
            for (id shape in shapes) {
                if ([shape isKindOfClass:[NSMutableDictionary class]]) {
                    ResolveContent(shape, keyPath, next, color);
                }
            }
        }
    } else if ([type integerValue] == 0) {
        id refId = layer[@"refId"];
        NSDictionary *asset = refId != nil ? assets[[NSString stringWithFormat:@"%@", refId]] : nil;
        id children = asset[@"layers"];
        if ([children isKindOfClass:[NSArray class]]) {
            for (id child in children) {
                if ([child isKindOfClass:[NSMutableDictionary class]]) {
                    ResolveLayer(child, keyPath, next, assets, color);
                }
            }
        }
    }
}

NSData *ApplyKeyPathColors(NSData *json, const std::vector<KeyPathColor> &colors) {
    NSMutableDictionary *root = [NSJSONSerialization JSONObjectWithData:json options:NSJSONReadingMutableContainers error:nil];
    if (![root isKindOfClass:[NSMutableDictionary class]]) {
        return nil;
    }
    NSMutableDictionary *assets = [[NSMutableDictionary alloc] init];
    id assetList = root[@"assets"];
    if ([assetList isKindOfClass:[NSArray class]]) {
        for (id asset in assetList) {
            if ([asset isKindOfClass:[NSDictionary class]] && asset[@"id"] != nil) {
                assets[[NSString stringWithFormat:@"%@", asset[@"id"]]] = asset;
            }
        }
    }
    id layers = root[@"layers"];
    if (![layers isKindOfClass:[NSArray class]]) {
        return nil;
    }
    for (const auto &entry : colors) {
        const KeyPath keyPath(entry.keyPath);
        if (keyPath.isEmpty()) {
            continue;
        }
        NSDictionary *color = @{
            @"a": @0,
            @"k": @[@(entry.red), @(entry.green), @(entry.blue), @1]
        };
        for (id layer in layers) {
            if ([layer isKindOfClass:[NSMutableDictionary class]]) {
                ResolveLayer(layer, keyPath, 0, assets, color);
            }
        }
    }
    return [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
}

TLottieInstance *CreateInstance(NSData *json) {
    return tlottie_new_with_options(
        (const uint8_t *)json.bytes,
        (size_t)json.length,
        TLOTTIE_FITZ_NONE,
        nullptr,
        0,
        nullptr,
        0,
        TLOTTIE_CHANNEL_BGRA);
}

}

@implementation TLottieBridge {
    std::mutex _mutex;
    NSData *_json;
    std::vector<KeyPathColor> _colors;
    bool _colorsChanged;
    TLottieInstance *_instance;
    std::vector<uint32_t> _scratch;
    int32_t _width;
    int32_t _height;
    int32_t _frameCount;
    int32_t _fps;
}

- (instancetype _Nullable)initWithJson:(NSString *)json {
    self = [super init];
    if (self != nil) {
        _json = [json dataUsingEncoding:NSUTF8StringEncoding];
        if (_json == nil) {
            return nil;
        }
        _instance = CreateInstance(_json);
        if (_instance == nullptr) {
            return nil;
        }
        _width = (int32_t)tlottie_width(_instance);
        _height = (int32_t)tlottie_height(_instance);
        _frameCount = (int32_t)tlottie_frame_count(_instance);
        _fps = (int32_t)tlottie_frame_rate(_instance);
    }
    return self;
}

- (void)dealloc {
    tlottie_drop(_instance);
}

- (int32_t)startFrame {
    return 0;
}

- (int32_t)endFrame {
    return _frameCount;
}

- (int32_t)fps {
    return _fps;
}

- (void)setColor:(NSColor *)color forKeyPath:(NSString *)keyPath {
    if (keyPath.length == 0) {
        return;
    }
    NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    const std::string path(keyPath.UTF8String);
    std::lock_guard<std::mutex> lock(_mutex);
    _colors.erase(std::remove_if(_colors.begin(), _colors.end(), [&path](const KeyPathColor &entry) {
        return entry.keyPath == path;
    }), _colors.end());
    _colors.push_back({ path, rgbColor.redComponent, rgbColor.greenComponent, rgbColor.blueComponent });
    _colorsChanged = true;
}

- (void)applyColorsIfNeeded {
    if (!_colorsChanged) {
        return;
    }
    _colorsChanged = false;
    NSData *json = ApplyKeyPathColors(_json, _colors);
    TLottieInstance *instance = json != nil ? CreateInstance(json) : nullptr;
    if (instance != nullptr) {
        tlottie_drop(_instance);
        _instance = instance;
    }
}

- (void)renderFrameWithIndex:(int32_t)index into:(uint8_t *)buffer width:(int32_t)width height:(int32_t)height bytesPerRow:(int32_t)bytesPerRow {
    if (width <= 0 || height <= 0 || bytesPerRow < width * 4) {
        return;
    }
    std::lock_guard<std::mutex> lock(_mutex);
    [self applyColorsIfNeeded];

    const size_t stride = (size_t)bytesPerRow;
    if (_width <= 0 || _height <= 0) {
        memset(buffer, 0, stride * (size_t)height);
        return;
    }
    const double scale = std::min(width / (double)_width, height / (double)_height);
    const int32_t fitWidth = std::clamp((int32_t)std::lround(_width * scale), 1, width);
    const int32_t fitHeight = std::clamp((int32_t)std::lround(_height * scale), 1, height);

    if (fitWidth == width && fitHeight == height && stride == (size_t)width * 4) {
        const size_t count = (size_t)width * (size_t)height;
        if (tlottie_render(_instance, (float)index, (uint32_t)width, (uint32_t)height, (uint32_t *)buffer, count, 1) != TLOTTIE_OK) {
            memset(buffer, 0, stride * (size_t)height);
        }
        return;
    }

    _scratch.resize((size_t)fitWidth * (size_t)fitHeight);
    if (tlottie_render(_instance, (float)index, (uint32_t)fitWidth, (uint32_t)fitHeight, _scratch.data(), _scratch.size(), 1) != TLOTTIE_OK) {
        memset(buffer, 0, stride * (size_t)height);
        return;
    }
    const int32_t skipX = (width - fitWidth) / 2;
    const int32_t skipY = (height - fitHeight) / 2;
    const int32_t after = skipX + fitWidth;
    for (int32_t y = 0; y < height; y++) {
        uint8_t *line = buffer + (size_t)y * stride;
        if (y < skipY || y >= skipY + fitHeight) {
            memset(line, 0, stride);
            continue;
        }
        if (skipX > 0) {
            memset(line, 0, (size_t)skipX * 4);
        }
        memcpy(line + (size_t)skipX * 4, _scratch.data() + (size_t)(y - skipY) * (size_t)fitWidth, (size_t)fitWidth * 4);
        if (after < width) {
            memset(line + (size_t)after * 4, 0, (size_t)(width - after) * 4);
        }
    }
}

@end
