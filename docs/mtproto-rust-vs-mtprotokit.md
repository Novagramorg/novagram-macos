# Rust MTProto engine vs MtProtoKit

Final results, 2026-10-02: telegram-ios master (bc97579868), beta 283249. The one-million-request rows were
measured on that code, back to back with MtProtoKit. The other suites ran on the same engine before the live
kill-switch layer was added; an A/B shows the layer costs nothing measurable. The real-server rows are from beta
build 283245. A visual version with charts is generated from the same tables (`mtproto-rust-vs-mtprotokit.html`).

**Short answer:** Rust is faster, lighter and much harder to break:
- it downloads big files 2–3.3× faster;
- it waits up to 60× less when the network breaks;
- it uses 2–8.7× less CPU;
- it survived all 47 hostile-server scenarios without running a single request twice.

MtProtoKit finished cleanly in 18 of the 47: it got stuck in 11, burned CPU in 2 endless loops, and ran requests
twice in 24 (49,395 times). On a clean, saturated link small transfers come out even, because the network is the
limit.

## How it was measured

- **TelegramCore path (`mtproto-bench tc`, suites `quick`, `torture-quick`, `hostile-quick`).**
  - The real TelegramCore stack runs once with each engine: `initializedNetwork`, `MultiplexedRequestManager`,
    `Download`, `multipartFetchV2`, `Network.request`.
  - It talks to a fake Telegram cluster (main DC, file DC, CDN) behind a network simulator.
  - Both engines run the same scenarios, seeds and files.
  - CPU and memory are for the whole client process.
- **Hostile and torture suites.** The fake server misbehaves on purpose, from single faults to an attacker that
  reacts to what the client does. It validates message times like the real server.
- **Real servers (NetworkLab in the Debug app).** Heavy account, read-only, direct connection.

## Speed and resources (TelegramCore path)

| Test | Rust | MtProtoKit | Rust vs MtProtoKit |
|---|---|---|---|
| Big file, 100 ms connection, 200 Mbit/s | 22.3 MB/s | 6.7 MB/s | **3.3× faster** |
| Big file through the CDN, same connection | 13.7 MB/s | 6.8 MB/s | **2.0× faster** |
| Videos, clean link | 606 MB/s, 0.12 s CPU, 54 MB | 434 MB/s, 0.26 s CPU, 110 MB | 1.4× faster, half the CPU and memory |
| Videos, flaky link (resets every 2–6 s) | 25.3 s, 1.00× bytes | 42.3 s, 1.65× bytes | 40% faster, no re-downloads |
| CDN videos, flaky link | 17.9 s, 1.00× bytes | 28.1 s, 1.48× bytes | 36% faster, no re-downloads |
| Mixed load with a 6 s outage, typical / slowest wait | 72 ms / 5.9 s | 4.3 s / 11.9 s | **60× lower typical wait** |
| First answer after that outage ends | 0.07 s | 1.11 s | 16× sooner |
| Mixed load with dead connections, typical / slowest wait | 115 ms / 2.6 s | 4.1 s / 12.1 s | **36× / 4.6× lower** |
| Mixed load with dead connections, longest stall | 2.9 s | 11.1 s | 3.9× shorter |
| Mixed load on 3G, typical wait | 396 ms | 469 ms | 16% lower, 2.5× less CPU |
| 10,000 small API requests, typical wait and CPU | 1.4 ms, 0.20 s | 2.2 ms, 1.05 s | 5.3× less CPU |
| Photos, clean link | 644 MB/s, 0.41 s CPU, 51 MB | 483 MB/s, 0.82 s CPU, 79 MB | 1.3× faster, half the CPU |
| Photos, lossy link | 3.28 s typical, 0.35 s CPU | 3.27 s typical, 0.70 s CPU | even, half the CPU |
| Scrolling photos with cancellations, typical / slowest | 439 / 838 ms | 449 / 880 ms | even (link is full), half the CPU |

Bytes columns show bytes downloaded ÷ bytes needed; 1.00× means nothing was downloaded twice. Rust used less CPU in
12 of 14 tests: it was even on CDN videos over a clean link and used 16% more on the big file through the CDN, which
it downloaded twice as fast.

### Why scrolling is even

That test runs 12 photo downloads at once over a 6.5 MB/s link, and both engines reach 5.2 MB/s, so the link is
full. Each photo gets about 0.55 MB/s, and an average 220 KB photo takes about 0.4 s whichever engine carries it. Both
engines also use identical download settings for small files, so they waste the same 1.26–1.27× on cancelled photos.
Rust still uses about half the CPU there.

### What made big files faster

These changes are active only with the Rust engine:

- The app now tells the server it can use the CDN. Previously big files always came from the file's own DC.
- The download window adapts:
  - it starts at 6 parts;
  - it grows while parts return within 1 s;
  - it halves when a part takes over 2 s;
  - it tops out at 16 parts (32 on the CDN);
  - parts grow from 128 KB to 512 KB once a file downloads faster than 4 MB/s.
- CDN downloads may use 8 connections × 4 requests. Regular DCs keep 4 × 3 to avoid slowing down scrolling.
- CDN problems fall back to the file's own DC without losing data that was already received:
  - bad data;
  - endless reupload requests;
  - missing hashes;
  - an invalid token.

## Hostile servers and long-running stability

| Test | Rust | MtProtoKit |
|---|---|---|
| Torture suite: 27 scenarios, from single faults to an adaptive attacker | all completed, 0 duplicates | **stuck in 7**: rotate-salt, transport-flood, all-faults, all-faults-flaky, a-time-warp, a-trickle, apocalypse-hostile. Ran requests twice in 12 (up to 8,086) |
| Hostile suite: 17 malformed or malicious data scenarios | all completed, 0 duplicates | stuck in 3 (packet for another session, invalid msg_id, compression bomb). Ran requests twice in 11 |
| All hostile faults together | 0 duplicates, 56 MB, 20 connections | 1,641 duplicates, 284 MB, 61 connections |
| Compression bomb | 42.5 MB | 238.5 MB, stuck |
| Server fan-out attack | 0.06 s CPU, 1.4 ms typical | 1.69 s CPU, 29 ms typical |
| Salt / clock rejection loops | 0.5 s CPU, about 60 packets | 52 s CPU, 290,000 packets |
| Server resend loop | 0 duplicates, 1 connection | 10,769 duplicates, 4,965 connections, 64 requests stuck |
| Hostile CDN: bad data, endless reuploads, no hashes, bad token | falls back to the file's DC, 0 bad bytes | doesn't use the CDN |
| 1 million API requests through TelegramCore, completed / failed | 1,000,000 / 0 | 1,000,000 / 0 |
| 1 million requests, per request typical / slowest 1% | 0.82 / 2.0 ms | 7.33 / 10.0 ms |
| 1 million requests, throughput | **262,351 req/s** (254,596–284,855 over 3 runs) | 34,588 req/s |
| 1 million requests, CPU | **8.4 s** | 73.6 s |
| 1 million requests, peak memory | **111 MB** | 591 MB (567–804 MB across runs) |
| Fuzzing (Rust only) | 10.1 million cases on the final code (50.4 million in earlier runs), 0 failures | not run, see below |
| 60-minute soak (Rust only) | 2.76 million requests, 0 wrong / failed / lost / duplicated; heap flat at 1–3 MB; 3 threads, 14 file descriptors | not run, see below |

In the three endless-loop scenarios the server never accepts two of the requests. Rust keeps those two waiting with
backoff and finishes everything else. MtProtoKit spins on them, or gets stuck and duplicates requests.

Fuzzing and the soak have no MtProtoKit numbers because both drive the Rust engine directly in-process:
- the fuzzer calls the Rust parsers and state machine millions of times a minute;
- the soak fast-forwards time to simulate 30–90 days.

MtProtoKit is Objective-C, and no such harness exists for it. The 1-million-request run is the long-running test
that ran both engines the same way.

## What the final hardening pass changed

| Rust, 1 million requests | Beta 283245 | Final |
|---|---|---|
| CPU | 11.8 s | 8.4 s |
| Engine thread busy | 93% | 43% |
| Packets sent | 28,995 | 8,871 |
| Typical / slowest 1% | 1.16 / 1.4 ms | 0.82 / 2.0 ms |

The 1 ms batching window (tdlib's `QUERY_DELAY`) adds a little to the slowest requests. The first version of the live kill switch (betas 283247 and 283248) cut this test to about 150k requests/s by tracking every request; beta 283249 lets the old engine move its own requests instead, which costs nothing per request. The pass also fixed edge
cases found by the new adaptive attacker:
- connections kept "alive" with junk bytes;
- large uploads restarted forever on a slow uplink;
- reconnect storms against persistent transport errors;
- DNS answers that never expired;
- duplicate executions after a server clock jump.

## Real Telegram servers

Heavy account, read-only, direct connection. Measured before the fast-download change, when both engines still used
the same download settings.

| Test | Rust | MtProtoKit |
|---|---|---|
| Media download | 267 Mbit/s, 1.5 s CPU | 141 Mbit/s, 3.4 s CPU |
| Catching up 10,000 missed updates | 7.5 s | 9.0 s |
| Lossy network | same speed, 5.4 s CPU | same speed, 13.9 s CPU |
| Outages | same wall time, about 38% less CPU | — |

## Where Rust is not better

- **CDN on a clean link.** 298 vs 373 MB/s. Rust asks for the CDN, and the CDN first fetches each file from the DC
  (24 reupload round trips in that test). MtProtoKit reads from the DC directly. On a 100 ms link the CDN path wins
  (13.7 vs 6.8 MB/s).
- **Hostile CDN.** Rust takes 0.2–0.6 s longer per file to detect a broken CDN and fall back. MtProtoKit never uses
  the CDN at all.
- **Peak memory on big downloads.** About 12 MB higher (62 vs 50 MB), because more data is in flight.
- **Slow-drip torture test.** 123 vs 210 requests/s. This comes from the test, not the engine:
  - the fake server drips the whole reply to the packet that triggered the fault and stops reading meanwhile;
  - Rust packs up to 130 requests into one packet (tdlib's 1 ms batching), so its dripped replies are twice as
    large;
  - before that batching Rust led this test 358 to 185;
  - a real server keeps reading while a slow write drains.
- **Even:** scrolling and lossy-network photos. On clean-link broadband the slowest 1% of mixed-load requests was
  76 vs 69 ms.

## Not measured yet

- Real-server download of a big file from @macos_stable_updates_files after the fast-download change. NetworkLab has
  a `bigfile` scenario for it, but it needs the Debug app closed.
- MtProtoKit fuzzing and a long soak. They would need a separate Objective-C harness; for the soak, an hour-long run
  through the TelegramCore bench would work for both engines.
- Real-server comparison with TDLib. The test account has 2FA, so TDLib was only checked without logging in.
- The iOS build of telegram-ios. Its compatibility was checked by reading the changes, not by a Bazel build. iOS
  keeps MtProtoKit either way.
