# Memory labs

Standalone measurements behind the `memory-diet` changes. Each one runs without an account and prints the numbers it proves.

## PostboxCacheLab

A real Postbox (SQLite on disk, `useCaches: true`) filled with 20,000 peers and 2,000 cached peer datas.

```sh
cd tools/perflab/MemoryLabs/PostboxCacheLab && swift test
```

Result on 2026-10-06 (M-series, Debug):

| What | Value |
|---|---|
| Table caches after reading every row | 9.0 MB (421 B per row with these light peers) |
| Freed by `postbox.clearCaches()` | 8.99 MB |
| Cold re-read after a clear | 3.1 µs per peer (68 ms for 22k rows) |
| Warm read | 2 ms for 20k peers |
| Data after a clear | intact |

## Scripts

Build each with `swiftc -O -o lab <file>` and run as noted at the top of the file.

| Script | Measures | Result |
|---|---|---|
| `wallpaper-bitdepth.swift` | Footprint of a pattern wallpaper shown as layer contents, 16-bit vs 8-bit PNG (`convert`, then `16` / `8`) | 20.9 MB vs 5.6 MB |
| `wallpaper-convert-in-memory.swift` | Converting the 16-bit mask in memory instead of on disk; pixel difference and timing (`check`, `show`) | 15.9 MB (the decoder keeps the 16-bit copy), 0/255 difference, 9.8 ms |
| `theme-thumbnail-retention.swift` | What an `NSImage` keeps after a full wallpaper is drawn into a small thumbnail (`full`, `small`) | about 0.9 MB per theme, not the decode |
| `mapped-media-data.swift` | Holding 60 photos' compressed data as heap copies vs mapped (`make`, then `heap` / `mapped`) | 23.6 MB vs 2.0 MB, same 3-4 ms decode |
| `jpeg-bgrx-compression.m` | `compressJPEGData` with the RGB copy vs BGRX rows fed straight to mozjpeg. Build: `clang -O2 -fobjc-arc -Icore-xprojects/Mozjpeg/build -Icore-xprojects/Mozjpeg/build/arm64 -framework AppKit jpeg-bgrx-compression.m core-xprojects/Mozjpeg/build/arm64/libjpeg.a`, run `old|new <w> <h>` | byte-identical output; 2560 px: 57 → 50 ms, peak footprint 75.7 → 70.9 MB; 12 MP: 108 → 94 ms, 184.5 → 172.6 MB |
| `lzfse-scratch-size.c` | `compression_encode_scratch_buffer_size(COMPRESSION_LZFSE)` | 684,288 bytes |
