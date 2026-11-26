# Rust MTProto engine: security map for auditors

Engine: `submodules/telegram-ios/third-party/mtproto-engine` (submodule HEAD `c9c7f23`). Read-only review; nothing was edited.

## Path and test abbreviations

| Short | Full path (relative to the engine root) |
|---|---|
| `core/` | `crates/mtproto-core/src/` |
| `hs-tests` | `crates/mtproto-core/tests/handshake.rs` |
| `sess-tests` | `crates/mtproto-core/src/session/tests.rs` |
| `rpc-tests` | `crates/mtproto-core/src/rpc/tests.rs` |
| `eng/` | `crates/mtproto-engine/src/` |
| `eng-tests` | `crates/mtproto-engine/tests/engine.rs` (real sockets against `mtproto-testserver`) |
| `ffi` | `crates/mtproto-ffi/src/lib.rs`; `ffi-tests` = `crates/mtproto-ffi/tests/ffi.rs`; header `crates/mtproto-ffi/include/mtproto_engine.h` |
| `fuzz:<name>` | target in `crates/mtproto-fuzz/src/targets.rs` (`TARGETS` at line 36). Run as one smoke test by `crates/mtproto-fuzz/tests/smoke.rs::every_target_survives_a_short_run` |
| `cov:<ID>` | row ID in `docs/protocol-coverage.md` |

Test references have the form `file:line name`. Code references have the form `file:line`.

## 0. Build and threat-model facts that change how findings should be read

- **Unsafe policy.** `#![forbid(unsafe_code)]` applies to mtproto-core (`core/lib.rs:1`). `#![deny(unsafe_code)]` applies to mtproto-engine (`eng/lib.rs:1`), with three local `#[allow]`s. `#![allow(unsafe_code)]` applies to the FFI crate. The workspace lint is `unsafe_code = "deny"` (`Cargo.toml`), but `crates/mtproto-ffi/Cargo.toml` has no `[lints] workspace = true`.
- **Panics.** The iOS Bazel build (`BUILD`, `_ENGINE_RUSTC_FLAGS`) uses `-Cpanic=abort -Copt-level=3` with no LTO. The macOS xcframework (`core-xprojects/mtproto-engine/mtproto-engine/build.sh`) is built with `cargo build --release -p mtproto-ffi`, and `profile.release` sets `panic = "abort"`. **Any panic, including any `assert!`/`expect`, aborts the whole app.** Release builds have no overflow checks or debug assertions. The fuzz profile turns on `debug-assertions` and `overflow-checks` with `panic = "unwind"`.
- **Features.** The `test-support` feature (`XorShiftRandom`, `SequenceRandom`, the test server, the `*_for_tests` TLS helpers) is not enabled in either shipping build. Production RNG is always `OsRandom` (`eng/worker.rs:120`).
- **Attacker classes used below:**
  - **NET**: on-path attacker without the auth key. With no proxy secret, the obfuscation keys are in the clear 64-byte header, so NET can read and inject transport frames.
  - **SRV**: a peer holding the auth key, i.e. the server.
  - **HOST**: the Swift caller of the C ABI.

---

## 1. AUTHKEY (auth-key handshake)

| Item | What the engine does | Code | Tests / fuzz | Flags |
|---|---|---|---|---|
| Request | `req_pq_multi` with a 16-byte random nonce taken from the RNG pool. The plain msg_id comes from `MsgIdGenerator` (local time). | `core/handshake.rs:105-110`, `core/msg_id.rs:15-27` | `hs-tests:35 permanent_key_agreement` | |
| Plain envelope | Needs ≥20 bytes and `auth_key_id == 0`, otherwise `NotPlain`. Requires `0 ≤ len ≤ remaining`; trailing bytes are tolerated. The server msg_id is **not** validated (parity and time unchecked). | `core/message.rs:250-263` | `core/message.rs:453 plain_message_roundtrip`, `484 decrypt_never_panics`; `hs-tests:214 trailing_bytes_…`; fuzz:plain | Plain msg_id is unchecked (tdlib parity, Info) |
| resPQ nonce | `res_pq.nonce != nonce` gives `NonceMismatch`. This is a plain compare, which is fine because the nonce is public. | `core/handshake.rs:136-139` | `hs-tests:80 tampering_is_rejected` | |
| RSA key choice | Takes the first server fingerprint that matches a configured key. If none match, `UnknownFingerprints(count)`. Fingerprint = low 64 bits of SHA1(TL bytes n, bytes e). Keys are PEM from the HOST, and PEMs that fail to parse are silently dropped (`ffi:629-632`). The fingerprint vector is capped at 65 536 entries. | `core/handshake.rs:140-147`, `core/crypto/rsa.rs:35-62`, `core/tl/mtproto.rs:25-34` | `hs-tests:104 unknown_server_key_is_rejected`; `core/crypto/rsa.rs:210 production_key_parses_with_expected_fingerprint`, `216 spki_and_pkcs1_agree`, `233 rejects_garbage` | F16 (no check on e or n) |
| pq | Length must be 1..8 bytes (`BadPq`). Rejects `pq < 4` or a probable prime (32-round Miller-Rabin). Pollard-Brent has a global budget of 2^24 steps, 63 seeds and `r ≤ 2^26`, with a deterministic Miller-Rabin for u64. p and q are sent in minimal big-endian. | `core/handshake.rs:148-157,389-393`, `core/crypto/factor.rs:1-138` | `hs-tests:161 hostile_pq_values_fail_fast_without_hanging`; `core/crypto/factor.rs:145-196` (6 tests); fuzz:pq, fuzz:handshake | |
| p_q_inner_data | Uses `p_q_inner_data_dc`, or `_temp_dc` plus `expires_in` for temp keys. `new_nonce` is 32 random bytes. The serialized inner is zeroized after encryption. | `core/handshake.rs:158-171`, `core/tl/mtproto.rs:59-73` | `hs-tests:47 temporary_key_agreement`; `core/tl/mtproto.rs:820 pq_inner_data_variants` | F12 (`new_nonce` stays in `State` without zeroize) |
| RSA_PAD | Follows the spec: data (≤144 B) plus random padding to 192 B, reversed; random temp_key; SHA256(temp_key‖data_with_padding); AES-256-IGE with a zero IV; temp_key_xor; then retries with a new temp_key while `block ≥ n`. Buffers are zeroized on success. | `core/crypto/rsa.rs:80-111` | `core/crypto/rsa.rs:279 rsa_pad_roundtrips_through_private_key` (proptest, 16 cases), `240 rsa_pad_payload_limits` | F12 (retry iterations leave `data_with_hash` and hash temporaries); F15 (`encrypt_legacy` and textbook `public_exponent_raw` are public and unused) |
| server_DH_params_fail | Checks nonces, then `constant_time_eq(new_nonce_hash, SHA1(new_nonce)[4..20])`. Gives `NewNonceHashMismatch` or `ServerDhParamsFail`. | `core/handshake.rs:195-206` | `hs-tests:68 server_failures_are_reported`, `116 server_dh_params_fail_with_bad_hash_…` | |
| encrypted_answer | Must be non-empty and a multiple of 16. tmp_aes key and IV follow the spec (`kdf.rs:65-77`), then IGE decrypt. Parses `server_DH_inner_data` from `[20..]`. Requires padding < 16 and `constant_time_eq(SHA1(inner), answer[..20])`; otherwise `BadEncryptedAnswer`. | `core/handshake.rs:208-223` | `hs-tests:149 encrypted_answer_shape_is_validated`, `80 tampering_is_rejected` | |
| Inner nonces | Checks `nonce` and `server_nonce` in DH params, in the inner data and in dh_gen (`check_nonces`, plain compare). | `core/handshake.rs:192,200,224,258,374-387` | `hs-tests:125 nonce_checks_cover_every_message` | |
| dh_prime | Must be exactly 256 bytes with the top bit set (`BadPrimeLength`). Generator checks run **before** the known-prime shortcut: g ∈ {2..7} with the documented residue conditions (2: p mod 8 = 7; 3: p mod 3 = 2; 4: none; 5: p mod 5 ∈ {1,4}; 6: p mod 24 ∈ {19,23}; 7: p mod 7 ∈ {3,5,6}). Any other g gives `BadGenerator`. The built-in Telegram prime skips primality testing. Any other prime needs 64-round Miller-Rabin on both p and (p−1)/2. The runtime passes **no** prime cache (`eng/session_runtime.rs:1191`, `None`). | `core/crypto/dh.rs:47-91` | `core/crypto/dh.rs:135-194` (5 tests); `hs-tests:180 non_safe_or_short_primes_are_rejected`; fuzz:handshake (overrides dh_prime and g, with and without a cache) | |
| g, g_a, g_b ranges | `1 < v < p−1` and `2^1984 ≤ v ≤ p − 2^1984` for g_a. The client's b is 2048 random bits (zeroized as bytes, but the `BigUint` is not), and it loops until g_b passes the same check. | `core/crypto/dh.rs:93-103`, `core/handshake.rs:226-227,331-340` | `core/crypto/dh.rs:197 g_a_range_checks`; `hs-tests:80` (`small_g_a`) | F12 (`b` and `key_number` are `BigUint`s that cannot be zeroized) |
| auth_key | `g_a^b mod p` as fixed 256-byte big-endian (keeps a leading zero byte). `auth_key_id` = SHA1[12..20], `aux_hash` = SHA1[0..8]. | `core/handshake.rs:341-344`, `core/crypto/kdf.rs:79-87`, `core/auth_key.rs:13-17` | `core/crypto/dh.rs:211 fixed_be_padding`; `core/crypto/kdf.rs:145` | |
| client_DH_inner_data | `retry_id` = 0, then the previous `aux_hash` on retry. Sends SHA1(inner)‖inner‖random pad to 16, AES-IGE with tmp_aes. | `core/handshake.rs:346-357` | `hs-tests:56 dh_gen_retry_is_followed` | |
| new_nonce_hash1/2/3 | `SHA1(new_nonce ‖ [1,2,3] ‖ aux_hash)[4..20]`, constant-time compare, checked for all three answer kinds **before** acting on any of them. | `core/handshake.rs:257-268` | `hs-tests:141 dh_gen_hash_mismatch_is_rejected` | |
| dh_gen_retry / fail | Retry with the same g_a, prime and new_nonce and a fresh b, up to `MAX_DH_RETRIES = 5` attempts (`TooManyRetries`). `dh_gen_fail` gives `DhGenFail`. | `core/handshake.rs:17,286-307` | `hs-tests:56`, `62 too_many_retries_fail`, `68` | |
| Server salt | `new_nonce[0..8] XOR server_nonce[0..8]`. | `core/handshake.rs:271-274` | `hs-tests:35` | |
| Server time | `time_difference = server_time − local_now`, with **no plausibility bound**. Used for later msg_ids and `expires_at`, and reported to the HOST. | `core/handshake.rs:228,275-276` | `hs-tests:47` (`expires_at`) | Info |
| State machine | `mem::replace(state, Done)` on every packet, so any error leaves `Done` and the handshake cannot be resumed. Wrong constructor gives `Tl(UnexpectedConstructor)`. | `core/handshake.rs:133-134,310` | `hs-tests:220 unexpected_constructor_in_state_fails`, `228 handshake_never_panics_on_garbage`; fuzz:handshake (MITM mutation of every reply; checks that the "agreed key" equals the server's) | |
| Runtime wiring | 10 s timeout, then `AuthKeyCreationFailed` and the connection closes with backoff. Any handshake error gives `AuthKeyCreationFailed`, close, `HandshakeFailed`. On success the key goes to the HOST as a secret buffer, and a session is installed with a 600 s salt. | `eng/session_runtime.rs:30,1188-1231,1460-1465` | `eng-tests:269 generates_auth_key_with_handshake_then_serves_requests`, `591 handshake_transport_error_restarts_key_generation_without_key_invalid`, `617 stalled_handshake_is_raced_away_…` | F24 (the 10 s timeout path has no test) |

## 2. CRYPTO

| Item | What the engine does | Code | Tests / fuzz | Flags |
|---|---|---|---|---|
| msg_key compute (2.0) | `msg_key_large = SHA256(auth_key[88+x .. 120+x] ‖ plaintext_with_padding)`; `msg_key = [8..24]`; x = 0 for client to server, x = 8 for server to client. Quick-ack token = `LE u32(msg_key_large[0..4]) | 0x8000_0000`. | `core/message.rs:109-117`, `core/crypto/kdf.rs:89-93` | `core/crypto/kdf.rs:153 msg_key_v2_uses_auth_key_slice_88`; `core/message.rs:284` | F20 (no external test vector) |
| msg_key verify | Decrypts the 16-aligned prefix (`floor((len−24)/16)·16`), recomputes over the **whole** plaintext including padding, then `constant_time_eq` on 16 bytes. The length and padding checks are computed before the comparison but reported after it, so error variants only differ after authentication, and all of them get the same reaction (close). | `core/message.rs:127-164` | `core/message.rs:309 tampering_is_detected_everywhere`, `297 wrong_side_or_key_is_rejected`, `397 rejects_forged_length_with_valid_msg_key`; `sess-tests:954 foreign_session_and_tampering_are_rejected`; fuzz:decrypt (mutated ciphertext must not decrypt to different content; reflection rejected) | |
| KDF (2.0) | Per spec: `a = SHA256(msg_key ‖ ak[x..x+36])`, `b = SHA256(ak[40+x..76+x] ‖ msg_key)`, key = a[0..8]‖b[8..24]‖a[24..32], IV = b[0..8]‖a[8..24]‖b[24..32]. The `MessageKeyMaterial` key and IV are zeroized on drop. | `core/crypto/kdf.rs:20-45` | `core/crypto/kdf.rs:109 v2_sides_differ`, `119 v2_layout_matches_spec_definition` (re-derives the spec in the test itself) | F20 |
| KDF / msg_key 1.0 | `message_key_v1`, `msg_key_v1`, and `encrypt/decrypt_message_v1` (SHA-1 msg_key, length read before the MAC check). **Unused** in the runtime: no bindTempAuthKey. | `core/crypto/kdf.rs:47-63,95-98`, `core/message.rs:175-233` | `core/crypto/kdf.rs:132`; `core/message.rs:440 v1_roundtrip_and_tamper` | F15 |
| AES-IGE | Hand-written IGE over `aes::Aes256`. Unaligned input is an error. One key schedule per message. The `AesIge` IV is zeroized on drop, and the key schedule is zeroized by `aes`'s `zeroize` feature (`Cargo.toml`). Hardware AES via `--cfg aes_armv8` (`.cargo/config.toml`; for Bazel, `MODULE.bazel` annotations). | `core/crypto/aes_ige.rs:1-116` | `core/crypto/aes_ige.rs:141,148,154,168` (roundtrip against an in-test reference using the same algorithm) | F20 (no published IGE test vector) |
| AES-CTR (obfuscation) | 128-bit big-endian counter that wraps; 8-block keystream; keystream zeroized on drop. | `core/crypto/aes_ctr.rs:8-60` | `core/crypto/aes_ctr.rs:68 nist_sp800_38a_ctr_aes256` (known-answer test), `94`, `106` | |
| Padding generation | `12 + align16`, giving 12..27, plus `(rng.next_u32() % (n+1))·16` random extra bytes, then reduced in 16-byte steps until ≤ 1024. n = 4 when direct and 15 behind a proxy or secret (`eng/session_runtime.rs:36-37,232-241`). Padding bytes are random. | `core/message.rs:61-78,93-107` | `core/message.rs:427 padding_policy_bounds`, `475 roundtrip_any_body` | |
| Padding / length verify | `len ≥ 0`, `len % 4 == 0`, `len ≤ plaintext − 32`, padding in 12..=1024. Minimum packet is 68 bytes (effectively 72 after flooring). 1–15 trailing junk bytes after the aligned ciphertext are silently ignored. | `core/message.rs:128-164` | `core/message.rs:365 padding_bounds_are_enforced_after_authentication`, `320 rejects_bad_shapes`, `330 trailing_transport_junk_is_ignored_like_tdlib` | F21 (Info, tdlib parity) |
| Comparisons | Constant time: `constant_time_eq` (OR fold, length short-circuit) for msg_key and every handshake hash; HMAC `verify_slice` for fake TLS. Plain compares only on public values: auth_key_id, nonces, session_id (after MAC), fingerprints. | `core/message.rs:265-267`; `core/handshake.rs:202,221,266`; `core/transport/tls.rs:281` | (no timing tests) | F17 (Info) |
| RNG | `OsRandom`: `getrandom::fill` (OS CSPRNG). Requests over 128 bytes go straight to the OS; smaller ones come from a 256-byte per-worker pool, and bytes handed out are zeroized in the pool. Pool zeroized on drop. A failure triggers `expect`, i.e. panic=abort (fails closed). | `core/crypto/rng.rs:40-94` | `core/crypto/rng.rs:168,176 os_random_pool_never_repeats_or_keeps_handed_out_bytes` | |
| Hashes | `sha1` / `sha2` crates. | `core/crypto/hash.rs` | `core/crypto/hash.rs:33,39,44` (known-answer tests) | |

## 3. MSG (per-packet receive checks, outgoing ids)

| Item | What the engine does | Code | Tests / fuzz | Flags |
|---|---|---|---|---|
| auth_key_id on receive | Read at bytes 0..8. If it differs from our key: `Decrypt(AuthKeyMismatch)`, then the connection closes and reconnects. | `core/message.rs:135-138`; `eng/session_runtime.rs:1270-1274` | `core/message.rs:297`, `320`; fuzz:decrypt | |
| session_id | `header.session_id != self.session_id` gives `ForeignSession`. **The packet is ignored, not acked, and the connection is kept** (tdlib closes). `session_id` is a random u64 from `Session::new` and `reset`. | `core/session/mod.rs:1197-1199,348,865`; `eng/session_runtime.rs:1267-1269` | `sess-tests:954` | F22 (Info) |
| Server msg_id parity | Outer packet: an even msg_id gives `EvenServerMsgId`, packet ignored and not acked. Container and msg_copy children with even ids are skipped. | `core/session/mod.rs:1200-1202,1386,1396,1513-1515` | `sess-tests:1112 even_server_msg_id_is_ignored`, `1469 container_children_with_even_msg_ids_are_skipped` | |
| Time window | Only when `time_synchronized`: message time must be in `[server_now − 300, server_now + 30]` (`is_within_time_window`). **`observe_server_time` runs before the check and only raises the clock, so a future msg_id raises the clock and always passes.** The window is skipped entirely while not synchronized: at session start and after every `reset_server_time`. Outside the window with no freshness proof, the packet is dropped silently (not recorded, not acked). Inside, `has_freshness_proof` (recursive, depth ≤ 8, ≤ 4096 visited, gzip on the shared budget) forces a clock reset to the packet's msg_id when the packet answers our live state. Only the **outer** msg_id is time-checked. | `core/session/mod.rs:1210-1219,1265-1326`; `core/msg_id.rs:49-50` | `sess-tests:968 messages_outside_time_window_are_ignored_after_sync`, `1180 future_msg_id_glitch_is_recovered_through_a_freshness_proof`, `1207 wall_clock_jumps_do_not_move_server_time`, `1262 responses_older_than_their_request_reset_the_clock`; cov:D11, D12, TI1–TI5 | **F2**, **F4**, **F5**, F6 |
| Duplicates | `DuplicateChecker::new(1000)` keeps a sorted window of 1000..2000 ids; when it reaches 2000 the oldest 1000 are drained. Results: `New`; `Duplicate` → **AckOnly** (re-acks content children, no processing); `TooOld` (below the window) → **Replay** (acked, and acts only on live client state: rpc_result for a pending query, pong for a pending ping, state info for a pending request, future_salts for a pending request; updates are not delivered and `UpdatesLost` goes to the host). Children are checked with `received.check` (records them). A separate `updates` window of 1000 dedupes update delivery. Both are cleared on session reset. | `core/session/dedupe.rs:19-65`; `core/session/mod.rs:378-379,1205-1209,1219,1382-1405,1484-1494,1498-1525` | `core/session/dedupe.rs:90,101,111,123,133`; `sess-tests:1122 duplicate_container_reacks_every_content_child`, `1146 too_old_messages_are_acked_and_replayed_safely`, `2337 replayed_old_salt_and_bad_msg_notifications_are_ignored`, `2377 an_answer_redelivered_with_an_evicted_msg_id_still_completes_its_query`; fuzz:session | **F3** (deviation: guideline says ignore) |
| Incoming seqno | Used only as `seq_no & 1` to decide on acks (odd seqno gets an ack before processing, also for malformed bodies; an immediate flush for bodies ≥ 16 KiB). **No monotonicity or consistency check.** Unpacked gzip content gets `seq_no & !1`, so it is not acked twice. | `core/session/mod.rs:1360-1365,1393,1415` | `sess-tests:2196 only_odd_seqno_messages_are_acked`, `1032 many_acks_flush_immediately` | F6 (Info, tdlib parity) |
| Incoming salt | **Not checked** (tdlib parity, cov:D15). | (absent) `core/session/mod.rs:1194-1230` | `sess-tests:2238 incoming_salt_is_not_validated` | F7 (Info) |
| Outgoing msg_id | `msg_id_for_time(mono + server_offset)`, clamped to `[0, i32::MAX−1]` seconds, XOR 22 random low bits, `& !3`. A zero low word gets +4. If ≤ last, the id becomes `last + 8·(1..1024)`. Strictly monotonic per session. A container id is allocated after its children. | `core/session/mod.rs:670-683,2328`; `core/msg_id.rs:29-40` | `sess-tests:1990 outgoing_msg_ids_stay_monotonic_when_the_clock_moves_back`; `core/msg_id.rs:96,146` (they test `MsgIdGenerator`, which only the handshake uses) | F15 note: `msg_id.rs` helpers `check_server_msg_id_time` and `SeqNoGenerator` are dead code |
| Outgoing seqno | Content messages get `seq_no | 1`, then `seq_no += 2`. Service messages and containers get the current even value. Reset to 0 on `reset()`. Retransmissions reuse the original msg_id and seqno inside a fresh container. | `core/session/mod.rs:685-693,862-904,2104-2139` | `core/msg_id.rs:123 seqno_rules` (dead helper); `sess-tests:147 queries_are_packed_into_one_container_in_order`, `335 reconnect_without_ack_retransmits_with_original_msg_ids` | F23 (i32 `+= 2` is not saturating) |
| Salts (outgoing) | `SaltState`: rotates by `valid_since`; a salt is valid while `valid_until > now + 60`. `bad_server_salt` gives a 10-minute salt and clears the future list. Without a valid salt, only `get_future_salts(64)` is sent, every 60 s. Inverted or non-finite future salt ranges are dropped. A HOST restore picks the currently valid salt. | `core/session/salts.rs:14-108`; `core/session/mod.rs:1881-1905,2208-2219` | `core/session/salts.rs:120,127,138,151`; `sess-tests:843 missing_salt_requests_future_salts_first`, `194` | |
| Length / padding bounds | See CRYPTO. Request bodies must be ≤ 8 MiB, non-empty and 4-aligned, otherwise the request fails locally with `400 REQUEST_INVALID_SIZE`. That check does **not** cover wrapper data added later (init params, verification tokens). | `core/rpc/mod.rs:21,296-305`; `core/rpc/wrap.rs:39-91` | `rpc-tests:855 oversized_or_unaligned_requests_fail_locally_instead_of_reaching_the_wire` | F18 |

## 4. SVC (service messages; dispatch in `core/session/mod.rs:1406-1495`, parser in `core/tl/mtproto.rs:468-546`)

All `bad_msg_*` handling applies only if `was_sent(bad_msg_id)` holds: the id is a live query, container, service request, pending ping, future-salts request, service container, or one of the last 1024 sent (`core/session/mod.rs:970-978`).

| Message | Handling | Code | Tests / fuzz | Flags |
|---|---|---|---|---|
| bad_msg_notification 16 | `reset_server_time(notification msg_id)` (sets `time_synchronized = false`), then resend with a new msg_id (or retransmit if it may have arrived). | `:1583-1586` | `sess-tests:210 bad_msg_16_resyncs_time_and_resends`, `1307 every_bad_msg_notification_code_recovers_the_message`; `eng-tests:688`, `716` | (F4) |
| 17 | Clock reset, then fail the message, then a drained session reset after `clamp(rtt_estimate, 1, 5)` s (collects answers still in flight). | `:1587-1594`; `:460-471` | `sess-tests:227`, `245`, `274` | |
| 20 | Resend. | `:1595` | `sess-tests:1307` | |
| 32 / 33 | Resend, then `pending_reset` (new session at the end of the packet). | `:1596-1599`; `:1246-1250` | `sess-tests:294 bad_msg_32_resets_session_and_keeps_processing_container` | |
| 48 | `invalidate_current` salt, so requests wait for future_salts; then resend. | `:1600-1604` | `sess-tests:1307` | |
| 18, 19, 34, 35, 64, unknown | `strike_and_fail`: a terminal `500 PROTOCOL_ERROR_BAD_MSG_<code>` after 3 strikes per query; otherwise `message_failed` (resend children, restart ping). Separately, any query rejected more than 12 times fails with `500 PROTOCOL_ERROR_REJECTED`. | `:1605-1608,1081-1100,995-1035` | `sess-tests:1356 repeated_bug_class_rejections_fail_the_query_instead_of_looping`, `1340 container_rejection_resends_every_child`, `2388 a_server_rejecting_every_send_cannot_hold_a_query_in_a_resend_loop` | |
| bad_server_salt | Requires `was_sent`. Sets the new salt (600 s), emits `SaltsUpdated`, refetches future salts, `message_failed(Salt)` (retransmit under the same msg_id if it may have arrived). Not allowed in Replay mode. | `:1430-1439` | `sess-tests:194`, `1376`, `1287 notifications_about_messages_we_never_sent_are_ignored`, `637`, `653`; `eng-tests:403` | |
| new_session_created | Ignored in Replay mode or when its `unique_id` is among the last 16. Adopts `server_salt` if it differs from ours or ours is invalid. Queries whose container or msg_id is < `first_msg_id` are resent, deferred to the end of the packet. Emits `ServerSessionReset`, which becomes `UpdatesReset`. | `:1716-1756,1241-1245` | `sess-tests:315`, `1395`, `1411`, `1427`; `eng-tests:417` | |
| msgs_ack | Each id, including container ids expanded to their children, marks queries acknowledged. Never completes an RPC. Vector ≤ 65 536. | `:1446-1450,1102-1131` | `sess-tests:777 msgs_ack_on_container_acknowledges_children_once` | |
| msg_container | ≤ 1024 children; each child length must be ≥ 0, a multiple of 4 and ≤ remaining. A broken top-level container gives `Malformed`, which closes the connection; a broken nested one is ignored. Nesting depth ≤ 8 (`MAX_NESTING_DEPTH`) and ≤ 4096 messages per packet. Per child: parity skip, dedupe (mode combine), seqno ack. **No check that a child's msg_id is below the container's, and no per-child time window.** | `core/tl/mtproto.rs:576-591`; `core/session/mod.rs:33-35,1356-1381,1407-1411,1512-1525` | `core/tl/mtproto.rs:841 container_parse_and_limits`, `1116 container_parser_never_panics_on_any_layout`; `sess-tests:1450`, `1481`, `1509`, `2253`; fuzz:tl, fuzz:session | F6 |
| gzip_packed | The gzip trailer's ISIZE is checked before inflating: anything above `min(budget, 32 MiB)` is refused. An honest stream is decoded into one exact allocation, and a stream longer than it declares fails. Plain zlib data is bounded by the limit. Failures charge `max(output, input)` to a **64 MiB per-packet** budget, which is shared with the freshness pass and with `rpc_result` unpacking. Depth ≤ 8. flate2 rust_backend (memory-safe). | `core/tl/mtproto.rs:635-695`; `core/session/mod.rs:38,1210,1290-1292,1391-1394,1413-1417,1674` | `core/tl/mtproto.rs:916 gunzip_enforces_limit`, `1055 declared_sizes_bound_allocation`, `1072 gunzip_budget_is_shared`; `sess-tests:1524 unpacking_is_bounded_per_packet_and_by_depth`, `2306 gzip_bombs_are_refused_without_unpacking_them`; fuzz:gunzip, fuzz:tl | |
| rpc_result | Unknown `req_msg_id`: dropped (acked); results over 16 KiB count toward an 8 MiB / 10 s budget whose overflow triggers a connection reset. Known id: if the result is > 15 s older than the request, the clock is reset. Body: `rpc_error` (code normalized: 0 or \|code\| > 9999 becomes 500; invalid UTF-8 is replaced); `gzip_packed` with the budget; `rpc_answer_*` silent; anything else is the value. Unpack failure gives a terminal `500 RESPONSE_UNPACK_FAILED`. | `:1647-1699`; `core/tl/mtproto.rs:341-360,612-633` | `sess-tests:2225`, `789`, `1693`, `1672`, `1647`, `1044`; `core/tl/mtproto.rs:880 rpc_result_variants`, `1034`; `rpc-tests:788`, `518` | |
| msgs_state_req (from server) | Replies 4 = received, 1 = older than the window, 3 = newer than anything seen, 2 = missing inside the window. At most 64 queued replies. | `:1465-1468,1527-1544` | `sess-tests:987`, `1550` | F18 (each reply can hold 64 KiB of info) |
| msgs_state_info / msgs_all_info | state_info must answer one of our pending `service_requests`; it is ignored if the `info` length does not match the ids. Status `& 7`: 1..3 means resend (unless already retransmitted), 4 means ack. A state_info answering one of our resend requests means the answer is gone: retry one id at a time, then resend the query. `msgs_all_info` is processed **without** request correlation. | `:1457-1464,1811-1851` | `sess-tests:604`, `740`, `1763`, `1976`, `689`, `2482` | |
| msg_resend_req (from server) | For each id that is a live query: retransmit with the original msg_id, seqno and body in a fresh container, at most 8 server-requested resends per query. Unknown ids get `msgs_state_info` with 1. | `:1546-1576` | `sess-tests:1582`, `2421 a_server_cannot_make_the_client_upload_a_query_forever`; `eng-tests:649` | F23 |
| msg_resend_ans_req | `msgs_state_info` with all 1s. | `:1470-1472` | `sess-tests:1610` | |
| msg_detailed_info / msg_new_detailed_info | Status 1..3, or 0 with no answer id: resend the query. Otherwise ack the query, and if the answer has not been seen, `msg_resend_req` (awaited answers ≤ 1024; after 3 unanswered requests, resend). Unknown query: just ack the answer id. | `:1451-1456,1758-1809,2026-2058` | `sess-tests:866`, `883`, `1708`, `1718`, `2210`, `2280 hostile_detailed_info_fan_out_stays_bounded` | |
| destroy_session_ok / none | Ignored; `destroy_session` is never sent. | `:1479` | `sess-tests:1919` | |
| destroy_auth_key_ok / none / fail | `DestroyAuthKey` event only if we requested it. | `:1480-1482,1641-1645` | `sess-tests:1919`; `eng-tests:1151` | |
| future_salts | Must answer one of the last 8 `get_future_salts` msg_ids. Accepts bare or boxed items (≤ 65 536). Drops non-finite or inverted ranges. The current salt rotates. No sanity check against the current time beyond rotation. | `:1473-1478,1853-1865`; `core/tl/mtproto.rs:518-534`; `core/session/salts.rs:53-66` | `sess-tests:1623 future_salts_must_answer_our_request`; `core/tl/mtproto.rs:925` | |
| pong | Matched against pending pings by msg_id or ping_id (≤ 16 kept). If the pong is > 15 s older than the ping, the clock is reset. Updates RTT. An unknown pong is ignored, apart from liveness. If unknown queries have been stuck for over 60 s, the connection is closed after the packet. | `:1612-1639` | `sess-tests:121`, `1251`, `1262`, `1778` | |
| ping / ping_delay_disconnect (from server) | Answered with a pong (≤ 64 queued). | `:1424-1429` | `sess-tests:1226`; `eng-tests:635` | |
| msg_copy | Inner message (boxed or bare) handled as a child (parity and dedupe). | `:1396-1398,1412`; `core/tl/mtproto.rs:549-562` | `sess-tests:1437` | |
| http_wait, other MTProto-layer constructors | Ignored and never forwarded as updates. | `:1483`; `core/tl/mtproto.rs:407-465,540` | `sess-tests:1949`; `core/tl/mtproto.rs:1016` | |
| Unknown (API) constructors | Become `Update` events, deduped by msg_id. Not delivered in Replay mode (`UpdatesLost` instead). Dropped for CDN sessions. | `:1484-1494`; `core/rpc/mod.rs:543-552` | `sess-tests:819`; `rpc-tests:843 cdn_sessions_never_forward_updates` | (F3) |

## 5. PFS (temporary keys)

| Item | What the engine does | Code | Tests | Flags |
|---|---|---|---|---|
| Temp key creation | `p_q_inner_data_temp_dc` with `expires_in` set from `MTSessionSetup.temp_key_expires_in > 0`. `expires_at = server_time + expires_in` (saturating) is reported in the `AuthKeyCreated` event (`integer2`). | `core/handshake.rs:56,159-168,275-276`; `ffi:633-636,268-274` | `hs-tests:47 temporary_key_agreement` | |
| bindTempAuthKey | **Not implemented in the engine.** `BindAuthKeyInner` and the v1 encryption exist but are unused. Binding is done by the HOST (MTContext). cov:P05–P08 marks this as a gap. | `core/tl/mtproto.rs:253-284`; `core/message.rs:175-233` | none | F19, F15 |
| Expiry tracking / rotation | **None in the engine.** The engine never looks at `expires_at` again. | (absent) | none | F19 |
| AUTH_KEY_PERM_EMPTY (401) | Never surfaced. `TemporaryKeyRejected` is emitted once per key or every 30 s; the request is parked with a 1→30 s backoff until a different key is installed. | `core/rpc/mod.rs:583-586,714-732` | `rpc-tests:279 auth_key_perm_empty_never_surfaces`, `797` | |
| -404 | See TRANSPORT. For the RustEngine HOST, `handleMissingKey` drops and re-requires ephemeral (temp) or CDN keys, removes the foreign auth token on token workers, and calls `checkIfLoggedOut` for persistent selectors (`submodules/MTProtoRustEngine/Sources/MTProtoRustEngineMapping/RustEngineMapping.swift:203-213`). | `eng/session_runtime.rs:1312-1320` | `eng-tests:380 unknown_key_reports_invalid_and_recovers_with_new_key` | **F1** |
| Key replacement | `install_key` with a different id calls `replace_auth_key` plus `reset_session` (new session_id and seqno, and requests are requeued). | `eng/session_runtime.rs:243-279`; `core/session/mod.rs:536-541` | `eng-tests:747`, `766` | |

## 6. TRANSPORT

| Item | What the engine does | Code | Tests / fuzz | Flags |
|---|---|---|---|---|
| Abridged framing | Length byte `< 0x7f` gives ×4. `0x7f` plus 3 LE bytes gives ×4. A marker of 0 or a quarter count of 0 is an error. Length > 16 MiB is an error (`MAX_FRAME_LEN`). The top bit marks a quick ack (4-byte **big-endian** token). | `core/transport/codec.rs:5,153-189` | `core/transport/codec.rs:329,349,370,431,442 rejects_bad_lengths,495 decode_any_split,540 decoder_never_panics`; fuzz:frames, fuzz:stream | |
| Intermediate / padded | 4-byte LE length. The top bit marks a quick ack. `len < 4` or `> 16 MiB` is an error. Padded sends 0..15 random bytes and trims on receive using the inner structure (plain messages use the declared length; encrypted ones are floored to 24 + 16k). | `core/transport/codec.rs:56-75,190-209,295-313` | `core/transport/codec.rs:342,358,379,460 padded_trim_uses_inner_structure` | |
| Short frames, transport errors | Payload < 16 bytes (< 24 when padded): fewer than 4 bytes or a zero word is a Nop; `0xffffffff` + token is a quick ack; **any** other word is `TransportError(code)`. Frames at or above the threshold are always packets. **Unauthenticated.** | `core/transport/codec.rs:266-293` | `core/transport/codec.rs:395 short_frames_follow_tdlib_classification`, `418 long_frames_are_packets_even_with_suspicious_prefixes` | F1, F8 |
| Error reaction | During the handshake, any code gives `AuthKeyCreationFailed` plus close (with the flood delay for -429). After it: **-404 sends `AuthKeyInvalid`, `rpc.take()` drops the session and key, and every request including in-flight ones is requeued for the next key; if `key_generation` is set the engine regenerates a key itself.** -429 sends `TransportFlood` with a 1,2,4..30 s delay (not a failure). -444 / -403 / others: rejection backoff of 1..16 s, and the address counts as failed from the second rejection. Every case closes the connection. | `eng/session_runtime.rs:1284-1336,1100-1124`; `core/transport/mod.rs:39-105` | `core/transport/mod.rs:112,126,134,146,155`; `eng-tests:380`, `520`, `543`, `591`, `1199` | **F1** |
| Quick ack | Token `& 0x7fffffff` is matched against the last 256 sent tokens and marks those queries acknowledged. Unauthenticated, 31-bit. | `core/session/mod.rs:1139-1147,2395-2409` | `sess-tests:764`; `rpc-tests:405` | F8 |
| Obfuscation init | Draws 64 random bytes until: `header[0] != 0xef`; first u32 ∉ {HEAD, POST, `GET `, OPTI, 0xdddddddd, 0xeeeeeeee, 0x02010316}; second u32 ≠ 0. **These checks are skipped when fake TLS is used.** Bytes 56..60 carry the tag, 60..62 the dc_id as i16 LE. Keys are header[8..40] and header[40..56], and the same from the reversed header. With a proxy secret, `key = SHA256(key ‖ secret)`. Only bytes 56..64 of the header are encrypted. | `core/transport/obfuscation.rs:6-63` | `core/transport/obfuscation.rs:109,134,141 rejects_forbidden_prefixes,159`; `core/transport/stream.rs:289-319`; fuzz:stream | F21 (Info) |
| Buffering bounds | The decoder rejects an oversized length as soon as the header is available. Reads are capped at 512 KiB per session per poll turn. TLS records are ≤ 64 KiB each. A racer gives up after 2 reads or 16 KiB without a matching resPQ nonce. | `eng/session_runtime.rs:33-40,1061-1093,902-980` | `eng-tests:938 a_racer_fed_endless_garbage_…`, `1171 trickling_or_noisy_…` | |

## 7. PROXY

| Item | What the engine does | Code | Tests / fuzz | Flags |
|---|---|---|---|---|
| MTProxy secret parsing | Accepts hex, then base64url (padding stripped), then base64, then base64-no-pad. Valid forms: 16 bytes (simple), 17 bytes starting `dd` (padded), ≥ 18 bytes starting `ee` (fake TLS + domain). Longer than 199 bytes: `TooLong`, or truncated when the caller allows it (the engine always truncates: `eng/types.rs:104-110`). `proxy_key` = bytes [1..17] or [0..16]. Debug output prints only the kind. A `dd` or `ee` secret forces padded intermediate. An invalid MTProxy secret yields no secret, so the client connects to the proxy host without one; there is no downgrade to a direct DC connection. | `core/transport/proxy_secret.rs:34-79`; `core/transport/stream.rs:17-24` | `core/transport/proxy_secret.rs:93,105,120,132`; `eng-tests:362 mtproxy_simple_padded_and_fake_tls`; fuzz:secret | F12 (raw secret not zeroized) |
| Fake-TLS ClientHello | Chrome-like template (MtProtoKit port) with GREASE, fake X25519 and ML-KEM key shares, and the domain (≤ 182 bytes) as SNI. `random = HMAC-SHA256(secret, hello with zero random)`, last 4 bytes XOR unix_time. | `core/transport/tls.rs:42-240` | `core/transport/tls.rs:430,498,512 hello_hmac_encodes_time,524,536,550` | |
| ServerHello verification | Expects `16 03 03 len`, then `14 03 03 00 01 01 17 03 03 len`; returns false if not enough bytes yet, and `InvalidPrefix` on a mismatch or if fewer than 43 bytes. `HMAC-SHA256(secret, client_random ‖ response with [11..43] zeroed)` is checked with `verify_slice` (constant time); failure gives `HashMismatch`, which closes the connection. Queued MTProto frames are released only after verification. | `core/transport/tls.rs:250-284`; `core/transport/stream.rs:134-171` | `core/transport/tls.rs:562 server_hello_roundtrip` (byte-by-byte, tampered, wrong prefix); fuzz:tls (a forged ServerHello must never verify), fuzz:stream | |
| TLS records | Type must be `17 03 03`; any other type is an error and closes. Zero-length and split records are fine. Writes chunk at 2878 bytes. | `core/transport/tls.rs:286-333` | `core/transport/tls.rs:588`, `604`; fuzz:tls | |
| SOCKS5 | Greeting `05 01 00` or `05 02 00 02`. Username and password ≤ 255 bytes, sent in **cleartext** (RFC 1929). Reply version and method are checked; the auth reply version must be 0x01; CONNECT reply version and REP are checked; ATYP must be 1, 3 or 4. Leftover bytes go to the transport. The DC is passed as an IP literal or a domain, so the client does no DNS for DC hosts behind a proxy (it resolves the proxy host only). The reserved byte is not checked. The connect transition runs before the first read. | `core/transport/socks5.rs:63-178`; `eng/connection.rs:139-144,246-278`; `eng/session_runtime.rs:729-745` | `core/transport/socks5.rs:194,207,230`; `eng-tests:343`; fuzz:socks5 | F12 (password not zeroized) |

## 8. TL

| Item | What the engine does | Code | Tests / fuzz | Flags |
|---|---|---|---|---|
| Reader bounds | Every read goes through `read_raw` (checks remaining length). `read_bytes`: first byte < 254 means short form, 254 means 3-byte length (≤ 16 MiB − 1), 255 is an error. Checks the 4-padded total. Padding bytes are not checked (tdlib parity). | `core/tl/reader.rs:37-121` | `core/tl/reader.rs:153,166,177,185,222,254`; fuzz:tl | |
| Vectors / strings | `read_count` rejects counts < 0 or > max. Service vectors are capped at `MAX_VECTOR_ITEMS = 65 536`, containers at 1024. The i64 vector checks remaining ≥ count·8 before allocating. | `core/tl/reader.rs:123-143`; `core/tl/mtproto.rs:11-12` | `core/tl/reader.rs:195 vector_count_limits` | |
| Recursion | `process_message` and `has_freshness_proof` have depth ≤ 8 and ≤ 4096 messages per packet. Parsers themselves are flat. | `core/session/mod.rs:1283,1356-1371` | `sess-tests:1524`, `2150 arbitrary_server_packets_never_panic_and_state_stays_bounded` | |
| Writer | `write_bytes` **asserts** length < 2^24. Container and msg_copy writers `expect` i32 lengths. | `core/tl/writer.rs:73-91`; `core/tl/mtproto.rs:730-790` | — | F18 |

## 9. FFI (C ABI)

| Item | What the code does | Code | Tests | Flags |
|---|---|---|---|---|
| Input buffers | `bytes`, `text` and `slice` treat a null pointer or zero length as empty; otherwise `from_raw_parts(ptr, len)` and copy (UTF-8 lossy for strings). **Validity and length are trusted from the HOST.** Request size is checked only later, in the RPC layer. | `ffi:437-456` | `ffi-tests:140 null_pointers_are_ignored` | F13 |
| Key input | `bytes(auth_key)` copy, then `AuthKey::from_slice` (exactly 256 bytes, otherwise silently "no key"), then the copy is `zeroize()`d. | `ffi:618-627,700-708`; `core/auth_key.rs:19-22` | `ffi-tests:48 c_abi_end_to_end` | F12 (stack array inside `from_slice`) |
| Output payloads | `Box<MTBuffer>` ownership passes to the callback; the HOST must call `mt_buffer_free` exactly once. `secret = true` (the `AuthKeyCreated` key) zeroizes on free. Double free or use after `mt_buffer_free` is undefined behaviour (no guard). The Swift wrapper wraps each payload in `Data(bytesNoCopy:deallocator: mt_buffer_free)` (`docs/swift-integration.md:111`). | `ffi:140-151,179-181,821-842` | `ffi-tests:48` (frees payloads) | F13 |
| Borrowed event fields | `text`, `text2` and `salts` point into Rust temporaries and are **valid only during the callback**. Not documented in the header. | `ffi:175-177,328,386-398` | `ffi-tests:48` | F13 |
| Engine handle | `engine(ptr)` dereferences a raw `Box<MTEngine>`. `mt_engine_destroy` = `Box::from_raw`, set `closed`, send shutdown and join the workers (the current thread is skipped). Any call concurrent with or after destroy is a use-after-free; a second destroy is a double free. Session handles are plain u64s; the worker is chosen by `handle & 0xff` clamped to the worker count, so a bad handle is harmless. | `ffi:540-576`; `eng/lib.rs:102-105,213-223` | `ffi-tests:140` | F13 |
| Callbacks | Run on engine worker threads (`ContextPointer` is `unsafe impl Send + Sync`). Concurrent across sessions, so the HOST context must be thread-safe. No callback after `closed` is set; `mt_engine_destroy` joins the workers, so a callback already running finishes before destroy returns. Re-entrant calls into the ABI from a callback are safe because commands are queued over mpsc. | `ffi:161-171,196-207`; `eng/worker.rs:230-368` | none for the "no callbacks after destroy" claim (cov:X12) | F10, F20 |
| Panics across FFI | No `catch_unwind`. With panic=abort (both shipping builds), any panic inside an `extern "C"` function or on a worker thread aborts the process. | `BUILD`; `Cargo.toml [profile.release]` | — | (see section 12) |
| f64 inputs | `time_difference` (session setup and `set_time_difference`), salt times, `idle_disconnect_after` and `request_timeout` are not validated. NaN or ∞ timeouts fall back to defaults, but a NaN `time_difference` makes `server_offset` NaN, the time-window check then rejects everything and `observe_server_time` never fixes it. | `ffi:641-648,808-812`; `core/session/mod.rs:531-534,1265-1272,1311` | — | F14 |
| ABI layout | The C header is compiled and its sizes and offsets compared with Rust. | `include/mtproto_engine.h` | `ffi-tests:152 c_header_layout_matches_rust` | |

## 10. SECRETS

| Item | Status | Code |
|---|---|---|
| `AuthKey` | `Box<[u8;256]>`, zeroized on Drop. `Clone` (each clone zeroizes). Debug prints only the id. `AuthKey::new(key: [u8;256])` takes the key **by value**, so the caller's stack copy is not wiped (`handshake.rs:343-344`, `auth_key.rs:20`). | `core/auth_key.rs:5-47` |
| Message key / IV | `MessageKeyMaterial` is zeroized on Drop; `AesIge` IV is zeroized; AES key schedules are zeroized by the `aes` `zeroize` feature; the AES-CTR keystream is zeroized. | `core/crypto/kdf.rs:20-30`; `core/crypto/aes_ige.rs:62-66`; `core/crypto/aes_ctr.rs:55-60`; `Cargo.toml` |
| RNG pool | Bytes are zeroized after use and on Drop. | `core/crypto/rng.rs:65-93` |
| Handshake | `p_q_inner_data` bytes and the RSA_PAD block, temp_key and padding are zeroized. **Not zeroized:** `new_nonce` (in `State`, dropped when the state is replaced), the DH exponent `b` and the shared `key_number` (`BigUint`, which num-bigint cannot zeroize; `drop(b)` only frees), `key_bytes`, and per-iteration RSA_PAD temporaries on retry. | `core/handshake.rs:69-91,171,331-344`; `core/crypto/rsa.rs:89-110` |
| Transport secrets | `ProxySecret.raw`, the obfuscation derived keys and header, the `TlsState::WaitingForServerHello.secret` copy, `Socks5Auth` and `ProxyConfig` passwords, and the `Verification` APNS secret and reCAPTCHA token: none are zeroized. | `core/transport/proxy_secret.rs:16`; `core/transport/obfuscation.rs:22-62`; `core/transport/stream.rs:28`; `core/transport/socks5.rs:11`; `eng/types.rs:19`; `core/rpc/wrap.rs:33-37` |
| FFI | Input key copies are zeroized. The output key is a secret `MTBuffer` (zeroized on free), and is zeroized immediately if there is no callback or the bridge is closed. A race between the `closed` check in `emit_secret` and the one in `deliver` can drop the key `Vec` unwiped (F10). | `ffi:188-207,618-620,700-702` |
| Logging | Only `Display` text from errors and fixed strings goes to the log callback (`eng/session_runtime.rs:1411-1413` and call sites at 917, 1102, 1250, 1271, 1285, 1463, 1502, 1565; `eng/worker.rs:143`). `MessageError` includes auth_key_id values, which are public on the wire. `HandshakeError::UnknownFingerprints` logs only the count. No `{:?}` of secret-bearing types in production code. **Latent risk:** `#[derive(Debug)]` on `EngineEvent` (`AuthKeyCreated.key: Vec<u8>`, `eng/types.rs:122-135`), `DcAddress` (secret, `eng/types.rs:10-15`), `SessionSetup` (`eng/types.rs:61`), `Verification` and `ApiEnvironment` (`core/rpc/wrap.rs:15-37`). | F11 |

---

## 11. Every `unsafe` block

Shipping code (iOS and macOS):

| Location | What | Assessment |
|---|---|---|
| `eng/clock.rs:5-13` | `libc::clock_gettime(CLOCK_MONOTONIC, &mut spec)` | Sound: valid out-pointer. The error fallback returns about 0 s, which is a poor fallback but unreachable in practice. |
| `eng/interface.rs:4-37` | `getifaddrs` / walk / `freeifaddrs`; casts `ifa_addr` to `sockaddr_in`/`sockaddr_in6` by `sa_family`; `CStr::from_ptr(ifa_name)` | Sound: null checks on `ifa_addr` and `ifa_name`, the cast matches the family, the list is freed on every path after success. |
| `eng/connection.rs:318-334` | `getsockopt(SOL_SOCKET, SO_NWRITE)` into a `c_int` with the correct length | Sound. |
| `ffi:163-164` | `unsafe impl Send/Sync for ContextPointer` | Sound only if the HOST context is thread-safe (callbacks run on several threads); this contract is not documented. |
| `ffi:206` | Calls the HOST `on_event(context, session, &event)` | Sound for the duration of the call; event fields borrow Rust temporaries (valid only during the call). |
| `ffi:309` | Calls the HOST `on_log(context, level, MTString)` | Sound; the string is borrowed only for the call. |
| `ffi:437-456` (`bytes`, `text`, `slice`) | `from_raw_parts` on HOST pointer and length after a null/zero check | Sound only if the HOST passes valid memory (unavoidable for a C ABI). No upper bound on length. |
| `ffi:458-538` (`salts`, `addresses`, `proxy`, `environment`, `request`) | Nested HOST pointers (`MTString`, `MTBytes`) dereferenced through the helpers above | Same HOST-trust caveat. |
| `ffi:540-542` (`engine`) | `&(*pointer).engine` | Sound only while the engine has not been destroyed. No use-after-destroy guard (F13). |
| `ffi:569-576` | `Box::from_raw(pointer)` in `mt_engine_destroy` | Sound once. A second destroy is a double free. |
| `ffi:598-650` | `&*setup`, `&*setup.environment` (null-checked), `slice(public_keys_pem)` | HOST-trust caveat. |
| `ffi:660-819` | `&*value` / `&*noop` after null checks; other parameters by value | HOST-trust caveat. |
| `ffi:822-842` | `(*buffer).data.as_ptr()/len()`, `Box::from_raw(buffer)` | Null-checked. Calling after free, or freeing twice, is undefined behaviour (HOST contract). |

Test or tooling only (not shipped): `crates/mtproto-fuzz/src/alloc.rs:30-56` (a `GlobalAlloc` wrapper that forwards to `System`; sound); `crates/mtproto-netsim/src/lib.rs:306,499,521,825` (`setsockopt`/`getsockopt` on owned fds; sound); `crates/mtproto-engine/tests/engine.rs:898-901` (`getrusage` into zeroed `rusage`; sound); `crates/mtproto-ffi/tests/ffi.rs` (calls the ABI); `crates/mtproto-bench` (16 occurrences, benchmark binary).

## 12. Possible panics on attacker-controlled input (each one aborts the app)

**NET (no key): none found.** Every index and slice on wire data is guarded:
- codec: `core/transport/codec.rs:118-302`, length checked before `take` and `consume`.
- TLS: `core/transport/tls.rs:257-283`; `position ≥ 43` is checked before `[11..43]`.
- SOCKS5: `core/transport/socks5.rs:110-172`.
- Plain/handshake: `core/message.rs:250-263`; `core/handshake.rs:214-223`, with `answer.len() ≥ 20` checked.
- pq: `core/crypto/factor.rs`; u128 `mul_mod`, budget-bounded.
- decrypt: `core/message.rs:128-171`; the minimum length guarantees `plaintext.len() ≥ 44`.
- `progress_target`: `core/session/mod.rs:1172` checks `head.len() ≥ 72`.

Arithmetic on wire lengths (`quarter*4`, `count*8`, `4+word`) cannot overflow on 64-bit targets. The fuzz targets frames, stream, tls, socks5, plain, decrypt, pq and handshake all run with overflow checks and debug assertions on.

**SRV (key holder):**
- `query.server_resends += 1` (u32, `core/session/mod.rs:1558`) is incremented for every id in every `msg_resend_req`, even past the cap. That is about 2·10^6 per 16 MiB packet, so about 32 GB of input wraps it. In release the counter silently re-enables resends; with overflow checks on it panics. Negligible (F23).
- `encode_frame` asserts outgoing payload < 16 MiB (`core/transport/codec.rs:42-43`). A server can grow one outgoing packet to roughly 8 MiB (one query) + 64 × 64 KiB (`msgs_state_info` replies to 65 536-id `msgs_state_req`s, `core/session/mod.rs:1539-1544,2273-2280`) + 3 × 64 KiB of id lists, about 12.4 MiB. That is below the limit, but the bound is implicit, not enforced (F18).
- `Writer::write_bytes` assert (`core/tl/writer.rs:79`): a server-sourced `info` is ≤ 65 536 bytes. Not reachable.
- `read_bounded` `clamp(min, max)` (`core/tl/mtproto.rs:663`): min ≤ max is guaranteed by the preceding branch. Not reachable.
- Debug-build-only internal invariant asserts (`core/session/mod.rs:486-492`, `core/rpc/mod.rs:485-497`). Exercised by fuzz:session, fuzz:rpc and fuzz:soak with debug assertions on.

**HOST:**
- Oversized `environment.params`, device strings, or APNS/reCAPTCHA tokens: the `write_bytes` assert, or a frame over 16 MiB through `wrap_request`, which is not size-checked (`core/rpc/wrap.rs:39-91`).
- Invalid pointers (section 11).
- NaN `time_difference` does not panic (`Duration::from_secs_f64` at `eng/worker.rs:140` is protected because `f64::min` ignores NaN), but it wedges the session (F14).

**Unconditional:** OS RNG failure gives `expect` (`core/crypto/rng.rs:77,83`). This is intentional fail-closed behaviour.

## 13. Reaction to decryption and verification failures

| Failure | Where | Reaction |
|---|---|---|
| Bad frame length or marker, bad TLS record type | `core/transport/codec.rs:166-202`; `core/transport/tls.rs:322-324` | `ConnectionError::Transport`: close and reconnect, counted as a failure (backoff) unless a packet was received. Key and session kept. |
| Fake-TLS prefix or HMAC mismatch | `core/transport/tls.rs:261-281` | Close and reconnect with backoff. |
| Short-frame transport error | `eng/session_runtime.rs:1284-1336` | During the handshake: `AuthKeyCreationFailed` and close. -404: **engine drops its key and session, requeues every request, emits `AuthKeyInvalid`**; the HOST decides, and the engine regenerates the key only if `key_generation` is set. -429: flood delay. Other codes: rejection backoff. All close the connection. |
| `Decrypt(TooShort / AuthKeyMismatch / MsgKeyMismatch / InvalidLength / InvalidPadding)` | `core/message.rs:127-164`; `eng/session_runtime.rs:1270-1274` | Warning logged, **connection closed**, reconnect (counted as failed if nothing was received yet). **Key and session are kept; no key regeneration.** Identical for every variant, so there is no oracle. |
| `ForeignSession`, `EvenServerMsgId` (and `TooOld`, which is never produced) | `eng/session_runtime.rs:1267-1269` | **Packet dropped silently; connection kept.** Not acked. |
| Outside the time window, no freshness proof | `core/session/mod.rs:1213-1216` | Dropped silently (`Ok`); not recorded or acked; connection kept. |
| Duplicate msg_id | `core/session/mod.rs:1207,1382-1402` | Content children re-acked; nothing processed. |
| Older than the dedupe window | `core/session/mod.rs:1208,1403` | Replay-safe processing (F3). |
| Malformed top-level container | `core/session/mod.rs:1372-1381,1256-1258` | `SessionError::Malformed`: close and reconnect. |
| Malformed non-container body or nested child | `core/session/mod.rs:1372-1380` | Ignored (acked if its seqno is odd). |
| Handshake verification failure (nonce, hash, DH, fingerprint, pq, constructor) | `eng/session_runtime.rs:1222-1230` | `AuthKeyCreationFailed`, close (`HandshakeFailed`, counts as failure, backoff), restart on the next connection. |
| Handshake timeout (10 s) | `eng/session_runtime.rs:1460-1465` | Same as a handshake failure. |
| `UnknownQueriesStuck`; dropped answers over 8 MiB in 10 s | `core/session/mod.rs:1259-1261`; `eng/session_runtime.rs:1370-1374,1404-1407` | Close and reconnect (the second reconnects immediately). |
| `AUTH_KEY_PERM_EMPTY` | `core/rpc/mod.rs:583-586` | Request parked, `TemporaryKeyRejected` to the HOST, connection kept. |

## 14. Test and fuzz coverage notes

- **Fuzzing** is a custom seeded, generator-based harness (`crates/mtproto-fuzz`), not coverage-guided (no libFuzzer or cargo-fuzz). It has 14 targets.
- **Fuzzing does not reach:**
  - the FFI layer;
  - the engine runtime (`eng/session_runtime.rs`, `eng/connection.rs`, `eng/worker.rs`); these are covered only by integration tests against the test server and netsim;
  - the RSA PEM/DER parser (`core/crypto/rsa.rs:136-193`);
  - `Session::progress_target`.
- **No external test vectors** for AES-IGE, the MTProto 2.0 KDF, msg_key or the auth key/DH result. The tests re-derive the spec in code, or check against `mtproto-testserver`, which uses the same core functions. Interop with production is exercised only by the manual `crates/mtproto-core/examples/live_*.rs`.
- `crates/mtproto-core/src/msg_id.rs` tests (`server_time_window`, `seqno_rules`, `MsgIdGenerator`) exercise helpers that the live session does not use. The live paths are covered by sess-tests.
- `docs/protocol-coverage.md` rows L07 and H13 cite `engine::stalled_handshake_times_out_and_retries`, which **does not exist**. The nearest test (`eng-tests:617`) asserts the stall is raced away in under 6 s, so the `HANDSHAKE_TIMEOUT` path (`eng/session_runtime.rs:1460-1465`) is not covered (F24).
- cov:X12 claims (FFI key zeroization, no callbacks after `mt_engine_destroy`) are not asserted by `ffi-tests` (which has 3 tests: end-to-end, null pointers, layout).

## 15. Flags (missing, weaker than expected, or suspicious)

Severity reflects the engine as integrated: NET = on-path attacker without the key; SRV = key holder; HOST = Swift caller.

- **F1 (Medium, design; NET).** An unauthenticated `-404` short frame makes the engine drop its auth key and session on the spot, and re-queue **all** requests, including in-flight ones that may already have run, for a new key and session. A replay under a new session cannot be deduplicated by the server, so non-idempotent requests without `random_id` can execute twice. With `key_generation` set, the engine also regenerates a key by itself.
  - Code: `eng/session_runtime.rs:1312-1320`, `373`; `core/transport/codec.rs:269-283`; `core/rpc/mod.rs:832-841`.
  - Reachability: injecting a frame takes no key when there is no proxy secret, because the obfuscation keys are in the clear header.
  - HOST mitigation: it maps persistent selectors to `checkIfLoggedOut` (`RustEngineMapping.swift:203-213`), so no permanent key loss. Ephemeral keys and foreign-DC tokens are dropped and re-created or re-imported (a cost and DoS lever).
  - Parity: tdlib behaves similarly for temp keys.
- **F2 (Low, deliberate deviation; SRV).** Server msg_ids more than 30 s in the future are never rejected: `observe_server_time` raises the clock before the window check (`core/session/mod.rs:1212-1213,1308-1318`). This contradicts the security guideline's +30 s rule; the coverage doc lists it as tdlib parity (cov:D11). One far-future packet makes later genuine packets look stale until a freshness proof arrives.
- **F3 (Low; NET replay).** msg_ids below the dedupe window are processed in "Replay" mode instead of ignored, as the guideline requires (`core/session/mod.rs:1205-1209,1403-1405,1484-1488,1498-1510`).
  - They are acked; rpc_result, pong, state_info and future_salts act on live state.
  - Updates are not delivered, but `UpdatesLost` reaches the HOST (getDifference).
  - Within the 300 s window, a replay of a packet evicted from a busy session's 1000–2000-id window costs only a getDifference, which is an amplification lever.
- **F4 (Low; NET replay, SRV).** No time window while `time_synchronized == false`: at session start and after every `reset_server_time` (bad_msg 16/17, freshness proof, 15 s response skew). The first packet afterwards sets the clock in either direction (`core/session/mod.rs:1265-1268,1311,1320-1326`). A same-session packet that has been evicted from the dedupe window and is replayed right after a reset can roll the clock back (transient; `TimeDifferenceUpdated` reaches the HOST).
- **F5 (Low).** The freshness proof for `rpc_result` and `msg_detailed_info` only checks `by_msg_id.contains_key` (`core/session/mod.rs:1294,1302`), with no 300 s recency bound, unlike bad_msg, bad_server_salt and new_session (`was_sent_recently`, `:966-968`). A withheld genuine answer to a long-pending query, delivered more than 300 s later, is accepted and forces a clock reset to its old msg_id (`:1217`).
- **F6 (Info, tdlib parity).**
  - No per-child time window.
  - No "child msg_id < container msg_id" check.
  - No incoming seqno validation; seqno parity is only used to decide acks (`core/session/mod.rs:1360,1512-1525`).
  - `msgs_all_info` is acted on without request correlation (`:1462-1464`).
- **F7 (Info).** The incoming server_salt is not checked (`core/session/mod.rs:1194-1230`; cov:D15).
- **F8 (Low; NET).** Quick acks are unauthenticated 31-bit tokens. A match marks queries acknowledged: an acknowledged query is not retransmitted on reconnect, and its `rejections` counter resets (`core/session/mod.rs:1114-1147`; `core/transport/codec.rs:157-163,195-198,276-279`). A blind match needs about 2^31/N injected 4-byte frames.
- **F9 (Low).** `progress_target` AES-IGE-decrypts an **unauthenticated** frame head and maps its req_msg_id to a pending request to drive `Progress` events (`core/session/mod.rs:1171-1192`; `eng/session_runtime.rs:1338-1366`). Impact is limited to progress UI; a forgery needs the key to hit a real msg_id. There is no MAC check by design, since this runs on partial frames.
- **F10 (Low).** FFI `emit_secret` checks `closed`, then `deliver` re-checks it. If `mt_engine_destroy` sets `closed` in between, the auth-key `Vec` is dropped without `zeroize` (`ffi:188-207`).
- **F11 (Low, latent).** Secret-bearing types derive `Debug`: `EngineEvent::AuthKeyCreated { key }`, `DcAddress.secret`, `SessionSetup`, `Verification`, `ApiEnvironment` (`eng/types.rs:10-15,61,122-135`; `core/rpc/wrap.rs:15-37`). Nothing logs them today, but any future `{:?}` would leak raw key, secret or token bytes.
- **F12 (Low).** Secrets that are never zeroized (section 10):
  - `new_nonce`;
  - the DH `b` and shared `key_number` `BigUint`s;
  - stack copies of the key (`AuthKey::new` by value, `from_slice`);
  - RSA_PAD retry temporaries;
  - obfuscation keys;
  - proxy secret bytes;
  - SOCKS5 and proxy passwords;
  - APNS secret and reCAPTCHA token;
  - decrypted plaintext buffers.
- **F13 (Low, contract).** The C header documents no ownership or lifetime rules:
  - payloads must be freed exactly once;
  - `text` and `salts` pointers are valid only during the callback;
  - callbacks run concurrently on worker threads;
  - no calls during or after `mt_engine_destroy`.

  There is no guard against use-after-destroy or a double `mt_engine_destroy`/`mt_buffer_free` (`ffi:540-576,821-842`; `include/mtproto_engine.h`). Input lengths have no upper bound before copying (`ffi:437-456`).
- **F14 (Low; HOST).** f64 inputs from the FFI are not validated. A NaN `time_difference` makes `server_offset` NaN; every packet then fails the time window and the clock never resyncs (`ffi:641,808-812`; `core/session/mod.rs:531-534,1265-1272,1311`).
- **F15 (Info).** Unused cryptographic public API in the shipped library:
  - MTProto 1.0 `encrypt/decrypt_message_v1`, whose decrypt reads the length before the SHA-1 MAC check;
  - `RsaPublicKey::encrypt_legacy` (old RSA scheme) and `public_exponent_raw` (unpadded textbook RSA);
  - `BindAuthKeyInner`;
  - dead helpers `check_server_msg_id_time`, `SeqNoGenerator`, `MAX_MESSAGE_LEN`.

  Code: `core/message.rs:10,175-233`; `core/crypto/rsa.rs:113-133`; `core/msg_id.rs:43-88`; `core/tl/mtproto.rs:253-284`.
- **F16 (Info).** RSA key import checks only `n.bits() == 2048`. The exponent is not checked (`e = 1` or an even e is accepted) and n is not checked for oddness (`core/crypto/rsa.rs:35-47`). Keys come from HOST PEM, and invalid PEMs are dropped silently (`ffi:629-632`).
- **F17 (Info).** `constant_time_eq` is a hand-rolled OR fold, without `subtle` or `black_box` (`core/message.rs:265-267`). This is adequate in practice; HMAC uses the constant-time `verify_slice`.
- **F18 (Low, robustness).** Outgoing size invariants are enforced only by `assert!`s that abort the app: `encode_frame` (`core/transport/codec.rs:42-43`), `Writer::write_bytes` (`core/tl/writer.rs:79`), and the container and msg_copy `expect`s.
  - `wrap_request` adds HOST data (`params`, environment strings, APNS/reCAPTCHA tokens) after the 8 MiB body check (`core/rpc/wrap.rs:39-91`; `core/rpc/mod.rs:296`).
  - Server-driven `msgs_state_info` replies (64 × ≤ 64 KiB) plus one 8 MiB query stay at about 12.4 MiB < 16 MiB only by implicit composition.
  - No NET path found.
- **F19 (Info, gap).** PFS is incomplete in the engine. Temp keys are created, but binding (`auth.bindTempAuthKey`), `expires_at` tracking and rotation are left to the HOST (cov:P05–P08 "gap"). The runtime passes no DH prime cache (`eng/session_runtime.rs:1191`).
- **F20 (Info, test gaps).**
  - No external known-answer test vectors for IGE or the 2.0 KDF / msg_key / auth key.
  - FFI zeroization and "no callback after destroy" are untested, although cov:X12 claims them.
  - Fuzzing is not coverage-guided and skips the FFI, the engine runtime, the RSA PEM/DER parser and `progress_target`.
  - The `msg_id.rs` unit tests cover dead helpers.
- **F21 (Info).** Two tdlib-parity malleability points:
  - Forbidden-first-word checks are skipped for fake TLS (`core/transport/obfuscation.rs:25-27`); harmless, because the header is inside TLS records.
  - Up to 15 trailing bytes after the aligned ciphertext are accepted without authentication (`core/message.rs:131`; codec floors to 4 bytes).
- **F22 (Info).** `ForeignSession` and even-msg_id packets are dropped while the connection is kept (tdlib closes) (`eng/session_runtime.rs:1267-1269`). Each such packet still costs a decrypt, with no rate limit beyond the per-turn 512 KiB read budget.
- **F23 (Info).** Counters without saturation: `query.server_resends` (u32, SRV-driven, `core/session/mod.rs:1558`); `seq_no += 2` (i32, about 10^9 content messages per session, `:688`); `failures += 1` (u32, `eng/session_runtime.rs:767`). They overflow only at unrealistic volumes; in release they wrap silently, and with overflow checks on they panic.
- **F24 (Info, test gap).** The 10 s `HANDSHAKE_TIMEOUT` path (`eng/session_runtime.rs:30,1460-1465`) has no test. The coverage doc cites a test that does not exist (`engine::stalled_handshake_times_out_and_retries`, rows L07/H13).
