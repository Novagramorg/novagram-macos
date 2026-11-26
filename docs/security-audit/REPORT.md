# MTProto security audit — consolidated report (2026-10-02)

Scope: the shipping macOS transport stack.
- Rust MTProto engine: github.com/TelegramMessenger/mtproto-engine c9c7f23, telegram-ios third-party/mtproto-engine. It handles sessions, transport, obfuscation, proxy and CDN connections.
- MtProtoKit. In the app it still performs every auth key exchange and temp-key binding; the engine runs with generate_key = 0.
- The Swift host glue (MTProtoRustEngine) and TelegramCore's CDN download path (FetchV2).

Requirements were taken from 155 official-doc entries (core.telegram.org, quotes verified) and 178 tdlib checks (file:line, tdlib e894536b2f). Every entry was cross-checked against the code.

Source files, all in this folder:
- docs-checklist.md, tdlib-checklist.md: the requirement lists.
- engine-map.md: the engine's security code map.
- audit-A.md: CRYPTO, MSG, TRANSPORT, TL; 120 IDs, each with a bench case.
- audit-B.md: SVC, PFS, CDN, OTHER, FFI.
- mtprotokit-keyex.md: MtProtoKit key exchange and binding.
- rangetest.m, fact*.c/.s: crash reproductions.

## High: pre-authentication remote crash or hang in MtProtoKit (shared with Telegram iOS)
Both are reachable by any on-path attacker or the operator of a configured proxy, before the server is authenticated. Both reproduce on this machine.

| ID | What | Where | Reproduced |
|---|---|---|---|
| H1 | A forged `server_DH_params_ok` whose `encrypted_answer` is 20–35 bytes. The padding-strip loop removes the last byte up to 16 times with no length check, so it throws an uncaught `NSRangeException` and the app crashes. The attacker needs only nonce and server_nonce, both sent in clear. tdlib requires padding < 16 after parsing. | MtProtoKit `MTDatacenterAuthMessageService.m:578-601` | `rangetest` → "terminating due to uncaught exception" |
| H2 | `res_pq` with `pq` = 0 or 1 (no length or minimum check), then `MTFactorize` does `% what` / `% (what-1)`. On x86_64 this is SIGFPE (exit 136, pq=0 and pq=1). On arm64 at -Os/-O2 the division-by-zero UB lets clang remove the zero check in `mygcd`, so the loop never ends on the process-wide `MTProto managerQueue` and all key creation and binding freezes. There is also UB in `1 << (i+18)`. tdlib bounds pq. | MtProtoKit `MTEncryption.m:537-600`, `MTDatacenterAuthMessageService.m:436-452` | `fact_x86 0/1` → exit 136; `fact_arm_Os 0` still spinning after 2 s |

Fix: H1, stop when `answerData.length == 0` and better parse-then-require padding < 16. H2, reject `pq` longer than 8 bytes, `pq` < 4 or `pq` ≥ 2^63 before factorizing, and make `MTFactorize` total (guard small inputs, cap the shift).

## Medium
| ID | What | Where | Who |
|---|---|---|---|
| M1 | An unauthenticated `-404` frame (5 bytes) makes the engine drop the session and silently re-send in-flight requests in a new session. A request the server already executed (e.g. createChannel without random_id) runs twice. The host then removes the temp key, so every session sharing it pauses, re-keys and replays as well. The hostile test suite excludes -404 (`mtproto-testserver/src/lib.rs:1080`). | engine `codec.rs:280-283`, `session_runtime.rs:1284-1288,1313-1320`, `rpc/mod.rs:832-841`; host `RustNetworkSession.swift:522-526,826-871` | on-path attacker, SOCKS5/MTProxy operator |
| M2 | AUTH_KEY_DUPLICATED (406) is never acted on. The engine only emits a soft reset and TelegramCore retries forever (≤5 s backoff, about 30 pollers), which matches the live storm of ~340 failures/min on dc2 plus help.getConfig every ~2 s. Likely trigger: the live engine switch keeps the old main session connected for 5 s next to the new one on the same temp key; main and upload/background workers also share one temp key. | `rpc/mod.rs:696-699`, `RustNetworkSession.swift:508-512`, `Network.swift:1356-1359`, `SwitchingNetworkEngine.swift:136-196` | self-inflicted, or server |
| M3 | A hostile CDN can silently truncate any CDN-served file. An empty reply skips hash verification and is committed as EOF. A short reply ending on a 128 KiB boundary passes because only the returned bytes are checked. The stored size is then lowered. Substitution is still blocked. This path runs only under the Rust engine (`cdn_supported`). | TelegramCore `FetchV2.swift:881-882,535-569,1008,1268-1282` | CDN operator |
| M4 | A hostile CDN can set the app-wide clock. A later msg_id raises the session clock before the window check, CDN sessions are not filtered, and the host writes it into the shared context. Consequences: auto-delete timers fire locally, outgoing timestamps are wrong, and temp-key binding and DoH time checks use the wrong time. | `session/mod.rs:1212-1213,1308-1318`, `rpc/mod.rs:559-561`, `RustNetworkSession.swift:541-542` | CDN operator |
| M5 | MtProtoKit handshake failures have no backoff. Any failed check reconnects at once, an unauthenticated frame resets the TCP backoff, and the attacker chooses the CPU cost per round (~0.6 s with a 63-bit prime pq). | `MTDatacenterAuthMessageService.m:154-187`, `MTTcpConnectionBehaviour.m:49-63` | on-path attacker |

## Low (selected; full lists in the source files)
- B-8: CDN redirect IV shorter than 4 bytes leads to an out-of-bounds `memcpy` write (`FetchV2.swift:884-889`, `MultipartFetch.swift:372-386`). Malicious main DC only. Memory corruption, trivial to fix.
- A-L1/L2/L3: replays older than the duplicate window are processed (ack + UpdatesLost, so getDifference per injected packet) and can roll the clock back after a reset. The freshness proof has no recency bound. tdlib runs the duplicate check before touching the clock.
- A-L4: a fake 16 MiB frame trickled at ≥512 B/s stalls a session for about 9 h. Bound per-frame time and use tdlib's 4 MiB + 1 KiB cap.
- A-L5: padding is 0–64 bytes with no size buckets, so message sizes leak on direct connections.
- A-L6: host-reachable `assert!` aborts on oversized outgoing data.
- B-5: CDN DCs receive the full initConnection (device, OS, app version, MTProxy address); tdlib sends an anonymous header.
- B-6: a CDN can stall a download forever via AUTH_KEY_PERM_EMPTY; FetchV2 has no per-part timeout or fallback.
- B-7 / MtProtoKit F9: temp keys are never rotated before expiry and dropTempAuthKeys is never called (tdlib rotates 60 min early).
- MtProtoKit:
  - auth_key not left-padded to 256 bytes (about 1/256 handshakes fail);
  - g_b not range-checked;
  - SecRandomCopyBytes failures ignored;
  - legacy p_q_inner_data without dc;
  - server_time and initial salt ignored;
  - bind expires_at taken from bind time;
  - bind-failure handling;
  - -404 during a media bind treated as success;
  - CDN RSA modulus size unchecked (an endless RSA_PAD loop with a short key);
  - static buffer in MTRsaFingerprint;
  - up to 128 bytes of plaintext logged on a parse error.
- Engine hygiene:
  - FFI ownership and lifetime rules undocumented, plus a zeroization race in destroy (unreachable in the app: singleton, never destroyed);
  - Debug-derived types that hold secrets;
  - several secrets not zeroized (new_nonce, DH exponent, obfuscation keys, proxy secret);
  - dead MTProto 1.0 / legacy RSA API still shipped;
  - no external test vectors;
  - the fuzzer is not coverage-guided and never reaches FFI, runtime or RSA parsing;
  - protocol-coverage.md cites tests that don't exist (X12, L07/H13).

## What holds up
- Core crypto:
  - msg_key in both directions over decrypted text including padding, KDF2, AES-IGE;
  - length and padding bounds;
  - uniform reaction to every pre-MAC error;
  - constant-time compares;
  - inbound MTProto 2.0 only;
  - no panic reachable by an attacker without the key.
- Bounds:
  - frame length checked before buffering;
  - gzip bombs, container count and container nesting bounded.
  These are stricter than tdlib.
- Service messages:
  - bad_msg_notification / bad_server_salt act only on msg_ids the client actually sent (stricter than tdlib);
  - future_salts are correlated with requests;
  - responses cannot reach the wrong query;
  - CDN answers cannot complete other DCs' queries;
  - updates from CDN sessions are dropped.
- MtProtoKit key exchange:
  - trusted RSA keys identical to tdlib's, and an unknown fingerprint is never accepted;
  - RSA_PAD correct;
  - every nonce check present;
  - DH prime, g and g_a checks correct;
  - new_nonce_hash1/2/3 correct;
  - key handoff to Rust wiped on both sides.
