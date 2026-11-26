# tdlib client-side MTProto security checks — audit checklist

Source: tdlib checked out at `submodules/telegram-ios/third-party/td/td/` (commit `e894536b2f`, 2025-05-27).
Every reference below was read in the code, not taken from comments or prior notes. Paths are relative to that root:

- `td/mtproto/...`: the core
- `td/telegram/net/...`: sessions and keys
- `td/telegram/files/...`: CDN
- `tdutils/td/utils/...`
- `tdnet/td/net/...`
- `td/generate/...`

"On failure" uses tdlib's real reactions:

- **close**: the `Status` error propagates out of `RawConnection::flush` or `SessionConnection::flush`. The TCP connection is dropped and later reopened. The session (session_id) and the keys are kept, and unacked queries are marked "unknown" and re-asked with `msgs_state_req` on the next connection.
- **session failed**: `callback_->on_session_failed`. The session is recreated with a new session_id.
- **restart handshake**: `AuthKeyHandshake::clear()`.
- **CHECK/FATAL**: a process abort.

Severity is what a client lacking the check risks:

- **critical**: forgery, MITM or key compromise.
- **high**: replay, session confusion, downgrade, or remote DoS by an unauthenticated network attacker.
- **medium**: misbehaviour by an authenticated server, robustness, or privacy.
- **low**: hygiene or interop.

---

## AUTHKEY — auth key generation (handshake), RSA, DH

| ID | What is checked (exact constants / comparisons) | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-AUTHKEY-1 | Handshake is a strict state machine `Start→ResPQ→ServerDHParams→DHGenResponse→Finish`; an incoming message is parsed only as the response expected in the current state | Any error → `clear()` (state=Start, new nonce on resume) → restart handshake | `td/mtproto/Handshake.cpp:327-345`, `:61-66` | high | Out-of-order or replayed handshake replies must not be accepted against a different state |
| TD-AUTHKEY-2 | Per-step deadlines: resPQ rejected if `now >= start + 0.6*timeout`; server_DH_params rejected if `now >= start + 0.8*timeout`; whole handshake actor timeout `10 s` | Error → restart; actor `timeout_expired` → "Timeout expired", connection closed | `td/mtproto/Handshake.cpp:87-89`, `:164-166`; `td/mtproto/HandshakeActor.cpp:34-39,58-61`; `td/telegram/net/Session.cpp:203-206` (passes 10) | low | Bounds the handshake; stale answers are not used. **Beyond docs** |
| TD-AUTHKEY-3 | Handshake transport: packet must be unencrypted (`auth_key_id==0`), ≥12 bytes. The 12-byte header (msg_id + length) is skipped, and the body is truncated to a multiple of 4 | "Expected not encrypted packet" / "Result is too small" → error → close | `td/mtproto/HandshakeConnection.h:68-82` | medium | Encrypted or garbage frames are not fed to the handshake parser. **Lenient:** msg_id and message_data_length of the unencrypted reply are NOT validated (see LENIENT-1) |
| TD-AUTHKEY-4 | resPQ parsed as boxed `resPQ#05162463` only (`TlFetchBoxed<…,85337187>`), with `check_end=false`: trailing bytes are allowed (transport padding) | Parse error → `Status::Error(500)` → restart | `td/mtproto/Handshake.cpp:31-46,91`; `td/generate/auto/td/mtproto/mtproto_api.cpp:1763-1767` | medium | Prevents type confusion. Trailing data is tolerated on purpose |
| TD-AUTHKEY-5 | `resPQ.nonce == nonce` (the 16-byte random nonce sent in `req_pq_multi`) | "Nonce mismatch" → restart | `td/mtproto/Handshake.cpp:92-94`; nonce from CSPRNG `:320` | critical | Binds the reply to this client's request (anti-replay, anti-injection) |
| TD-AUTHKEY-6 | `server_nonce` is stored without any check (free server value) | — | `td/mtproto/Handshake.cpp:96` | — | (informational; it is checked in every later message) |
| TD-AUTHKEY-7 | RSA key pinning: for each fingerprint in the server's list, **in server order**, look for an exactly equal fingerprint among the locally known keys; use the first match. No match → error | `get_rsa_key` error → `drop_keys()` (CDN: clears keys and refetches `help.getCdnConfig`; main: no-op) → restart | `td/mtproto/Handshake.cpp:98-103`; `td/telegram/net/PublicRsaKeySharedMain.cpp:54-67`; `td/telegram/net/PublicRsaKeySharedCdn.cpp:31-47` | critical | The only server-authentication step of the handshake. Accepting an unknown key = full MITM |
| TD-AUTHKEY-8 | Known main-DC keys are hard-coded: **one** production key and **one** test key. There are no legacy keys | — | `td/telegram/net/PublicRsaKeySharedMain.cpp:14-52` | critical | Trust anchor |
| TD-AUTHKEY-9 | Fingerprint = `SHA1(TL bare rsa_public_key n:string e:string)[12..20]` (lower 64 bits), computed locally from (n,e) | — | `td/mtproto/RSA.cpp:111-123` | critical | Wrong fingerprint derivation = wrong pinning |
| TD-AUTHKEY-10 | PEM keys must parse as RSA with modulus size **exactly 256 bytes** (`EVP_PKEY_is_a(...,"RSA")`, `EVP_PKEY_size==256` / `RSA_size==256`) | Error (main keys: `move_as_ok()` → crash on a bad built-in key; CDN keys: logged and skipped) | `td/mtproto/RSA.cpp:38-109`; `td/telegram/net/PublicRsaKeyWatchdog.cpp:128-132` | medium | Rejects weak or malformed CDN keys from config |
| TD-AUTHKEY-11 | CDN RSA keys come only from `help.getCdnConfig` (asked over the authenticated main-DC session) and are filtered by `dc_id == key.dc_id`. Refetch is flood-limited (1/1 s, 2/60 s, 3/120 s) and the config is cached per layer | Missing → handshake fails until keys arrive | `td/telegram/net/PublicRsaKeyWatchdog.cpp:45-58,60-83,122-137`; `td/telegram/net/NetQueryDispatcher.cpp:230-237` | critical | A CDN must not be able to present its own key (docs P-115) |
| TD-AUTHKEY-12 | pq factorisation must succeed (`pq_factorize` returns −1 → error). Small path: `pq < 2^63` (8-byte, top bit clear); otherwise BigNum Pollard-rho | "Failed to factorize" → restart | `td/mtproto/Handshake.cpp:105-109`; `tdutils/td/utils/crypto.cpp:103-140,171-255` | low | Proof of work. **Lenient:** see LENIENT-2 (no size bound, trivial p=1 accepted, CPU DoS) |
| TD-AUTHKEY-13 | `new_nonce` = 32 bytes from the CSPRNG | (RNG failure → FATAL, see CRYPTO-13) | `td/mtproto/Handshake.cpp:111` | critical | new_nonce keys the tmp AES and authenticates dh_gen_ok |
| TD-AUTHKEY-14 | Inner data choice: perm key → `p_q_inner_data_dc` (dc); temp/CDN key → `p_q_inner_data_temp_dc` (dc, expires_in), and `expires_at = now + expires_in` is recorded. dc = raw id, +10000 on test, negative for media-only | — | `td/mtproto/Handshake.cpp:113-125`; `td/telegram/net/SessionProxy.cpp:231-238`; `td/telegram/net/Session.cpp:1443-1444` | high | A temp key generated as a perm key (or the reverse) breaks PFS semantics. A wrong dc gives `-444`/-404 |
| TD-AUTHKEY-15 | RSA_PAD: `len(data) ≤ 144`, else error; random padding to 192; reverse those 192 bytes; append `SHA256(temp_key ‖ data_with_padding)`; AES-256-IGE with a zero 32-byte IV; `temp_key_xor = temp_key ⊕ SHA256(aes_encrypted)`; retry with a new temp_key while `key_aes_encrypted ≥ n` | "Too big data" → restart; ≥n → loop | `td/mtproto/Handshake.cpp:127-155`; `td/mtproto/RSA.cpp:130-146` | critical | The RSA_PAD integrity hash is what makes the server-side decryption non-malleable. Encrypting x≥n would leak/garble |
| TD-AUTHKEY-16 | `RSA::encrypt` asserts the modulus bit length is in `[2041, 2048]` and `from.size()==to.size()==256` | CHECK → abort | `td/mtproto/RSA.cpp:130-135` | low | Defensive invariant |
| TD-AUTHKEY-17 | `req_DH_params` result: only `server_DH_params_ok#d0e8075c` is accepted (`server_DH_params_fail` is not in the scheme → parse error) | Parse error → restart | `td/mtproto/Handshake.cpp:168`; `td/generate/auto/td/mtproto/mtproto_api.cpp:1723-1727`; `td/generate/scheme/mtproto_api.tl:18` | medium | Fail closed |
| TD-AUTHKEY-18 | `server_DH_params_ok.nonce == nonce` **and** `.server_nonce == server_nonce` | "Nonce mismatch" / "Server nonce mismatch" → restart | `td/mtproto/Handshake.cpp:171-176` | critical | Docs mandate nonce checks in every handshake message |
| TD-AUTHKEY-19 | `encrypted_answer.size() % 16 == 0` | "Bad padding for encrypted part" → restart | `td/mtproto/Handshake.cpp:177-179` | medium | Prevents a partial-block IGE decrypt |
| TD-AUTHKEY-20 | tmp_aes_key/iv from `tmp_KDF(server_nonce,new_nonce)`; decrypt; parse `SHA1(20) ‖ int32 id`; `id == server_DH_inner_data#b5890dba`; inner object parses without error | "Failed to fetch server_DH_inner_data" → restart | `td/mtproto/Handshake.cpp:181-200`; `td/mtproto/KDF.cpp:52-72` | critical | Only a holder of the RSA private key knows new_nonce, so this authenticates the DH params |
| TD-AUTHKEY-21 | Remaining random padding after inner data: `pad < 16` | "Too much pad" → restart | `td/mtproto/Handshake.cpp:202-205` | high | Bounds the unauthenticated tail. The docs specify 0..15 |
| TD-AUTHKEY-22 | `SHA1(answer[20 .. 20+inner_len]) == answer[0..20]`, where inner_len excludes the padding | "SHA1 mismatch" → restart | `td/mtproto/Handshake.cpp:207-212` | critical | Integrity of g, dh_prime, g_a, server_time (docs P-099) |
| TD-AUTHKEY-23 | Inner `nonce == nonce` and inner `server_nonce == server_nonce` (checked after the SHA1) | Mismatch → restart | `td/mtproto/Handshake.cpp:214-219` | critical | Ties the inner data to this exchange |
| TD-AUTHKEY-24 | `server_time` from the inner data → `server_time_diff = server_time − now`; key `created_at = server_time` | No range check | `td/mtproto/Handshake.cpp:221,248`; applied in `td/telegram/net/Session.cpp:1425-1427` (only via `update_server_time_difference`, which only increases after the first set) | low | Authenticated by TD-AUTHKEY-22; feeds msg_id generation. **Lenient:** no sanity bound |
| TD-AUTHKEY-25 | DH prime must be **exactly 2048 bits** (`get_num_bits()==2048`, i.e. 2^2047 ≤ p < 2^2048) | "p is not 2048-bit number" → restart | `td/mtproto/DhHandshake.cpp:21-26` | critical | A small or oversized group allows discrete-log attacks |
| TD-AUTHKEY-26 | `g ∈ {2..7}` and g is a quadratic residue: g=2 ⇒ p mod 8 = 7; g=3 ⇒ p mod 3 = 2; g=4 none; g=5 ⇒ p mod 5 ∈ {1,4}; g=6 ⇒ p mod 24 ∈ {19,23}; g=7 ⇒ p mod 7 ∈ {3,5,6}; any other g → fail | "Bad prime mod 4g" → restart | `td/mtproto/DhHandshake.cpp:28-63` | critical | Keeps g in the prime-order subgroup (no small-subgroup leak) |
| TD-AUTHKEY-27 | Known-good-prime fast path: if `prime_str` equals the built-in 2048-bit prime → good; else a persistent cache `good_prime:<p>` = "good"/"bad" is consulted. **The cache is consulted only after** the bit-length and g checks | Cached "bad" → "p or (p - 1) / 2 is not a prime number" → restart | `td/mtproto/DhHandshake.cpp:65-72`; `td/telegram/DhCache.cpp:23-45` | high | Avoids the slow primality test without skipping the cheap checks. **Beyond docs:** negative caching |
| TD-AUTHKEY-28 | Safe prime: `is_prime(p)` and `is_prime((p−1)/2)`. The result is cached as good/bad | "p is not a prime number" / "(p - 1) / 2 is not a prime number" → restart, prime persisted as bad | `td/mtproto/DhHandshake.cpp:73-92`; `td/telegram/DhCache.cpp:47-53` | critical | Docs P-101 |
| TD-AUTHKEY-29 | Primality test is OpenSSL `BN_check_prime` (3.x) or `BN_is_prime_ex` with 64 rounds (128 if >2048 bits); a result of −1 is fatal | `LOG_IF(FATAL)` | `tdutils/td/utils/BigNum.cpp:150-159` | high | Rounds well above the docs' 15 |
| TD-AUTHKEY-30 | `g_a` **and the client's own `g_b`** must lie in `[2^(2048−64), p − 2^(2048−64)]` (strictly stronger than `1 < x < p−1`) | "g^a or g^b is not between 2^{2048-64} and dh_prime - 2^{2048-64}" → restart (b is regenerated on the next attempt) | `td/mtproto/DhHandshake.cpp:95-126,183-195` | critical | Rejects degenerate shared secrets (g_a = 1, p−1, …) |
| TD-AUTHKEY-31 | `b` = 2048 random bits (`BigNum::random(b,2048,-1,0)`, OpenSSL RNG); `g_b = g^b mod p` | — | `td/mtproto/DhHandshake.cpp:128-143` | critical | The secret exponent must come from a CSPRNG (docs P-106) |
| TD-AUTHKEY-32 | `auth_key = (g_a^b mod p)` as exactly 256 big-endian bytes (left-padded); `auth_key_id = SHA1(auth_key)[12..20]` | — | `td/mtproto/DhHandshake.cpp:212-229` | critical | A wrong key encoding means server/client key mismatch, or a truncated key |
| TD-AUTHKEY-33 | `client_DH_inner_data(nonce, server_nonce, retry_id=0, g_b)`; `SHA1(data) ‖ data ‖ random pad` to a multiple of 16; tmp-AES-IGE | — | `td/mtproto/Handshake.cpp:230-242` | medium | — |
| TD-AUTHKEY-34 | `set_client_DH_params` reply parsed as `Set_client_DH_params_answer` (dh_gen_ok/retry/fail only; an unknown constructor → parse error) | Error → restart | `td/mtproto/Handshake.cpp:257`; `td/generate/auto/td/mtproto/mtproto_api.cpp:1358-1372` | medium | — |
| TD-AUTHKEY-35 | dh_gen_ok: `nonce`, `server_nonce` equal; `new_nonce_hash1 == SHA1(new_nonce ‖ 0x01 ‖ SHA1(auth_key)[0..8])[4..20]` | Mismatch → restart (key discarded) | `td/mtproto/Handshake.cpp:259-276` | critical | Key confirmation: proves the server derived the same auth_key |
| TD-AUTHKEY-36 | dh_gen_retry / dh_gen_fail → error, **without** checking nonces or `new_nonce_hash2/3`; there is never a retry with `retry_id = auth_key_aux_hash` | "DhGenRetry"/"DhGenFail" → restart from req_pq | `td/mtproto/Handshake.cpp:277-280` | low | Fail-closed deviation from docs P-110/P-111 (an unauthenticated retry/fail can only cause a restart) |
| TD-AUTHKEY-37 | Initial salt = `new_nonce[0..8] ⊕ server_nonce[0..8]`. Session installs it **only for the key the session actually uses** (`use_pfs ^ is_main`: the temp-key salt under PFS, the perm-key salt otherwise) | — | `td/mtproto/Handshake.cpp:250`; `td/telegram/net/Session.cpp:1420-1424` | medium | Prevents mixing perm and temp key salts |
| TD-AUTHKEY-38 | Transport `-404` while a handshake is in flight → `handshake_->clear()` | Handshake restarted from scratch | `td/mtproto/HandshakeConnection.h:50-57` | medium | Docs P-100 |
| TD-AUTHKEY-39 | Resume after a reconnect re-sends the **identical** last query (`last_query_`); state Finish or an empty last query → `clear()` | — | `td/mtproto/Handshake.cpp:287-313` | low | Docs P-113 (idempotent resend) |
| TD-AUTHKEY-40 | Handshake concurrency: a thread-local semaphore of 50 concurrent GenAuthKey actors; a warning at 100 | Queued | `td/telegram/net/Session.cpp:100-181` | low | Local DoS hygiene |
| TD-AUTHKEY-41 | `on_start` called in a state other than Start → `clear()` + error | Restart | `td/mtproto/Handshake.cpp:315-325` | low | State-machine guard |
| TD-AUTHKEY-42 | Unencrypted outgoing handshake packets carry `msg_id = 0`, plus random padding of `(−len mod 16) + 16·rand(0..15)` bytes counted in the length field | — | `td/mtproto/HandshakeConnection.h:64-66`; `td/mtproto/NoCryptoStorer.h:17-40` | low | **Beyond docs** (size obfuscation). **Lenient** (msg_id=0 instead of time-based) |

## CRYPTO — msg_key, KDF, padding, comparisons

| ID | What is checked | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-CRYPTO-1 | Inbound MTProto 2.0: `msg_key_large = SHA256(auth_key[88+8 .. +32] ‖ entire decrypted payload incl. padding)`; `msg_key = msg_key_large[8..24]`; it must equal the header msg_key. **X=8 inbound, X=0 outbound** | "message_key mismatch" → close | `td/mtproto/Transport.cpp:148-164,261,264-272,306` (read X=8), `:385` (write X=0) | critical | The only integrity/authentication check on encrypted traffic |
| TD-CRYPTO-2 | msg_key comparison is constant time (OR-accumulated XOR over all 16 bytes) | — | `td/mtproto/Transport.cpp:264-267` | high | Prevents a timing oracle on msg_key |
| TD-CRYPTO-3 | Ordering: msg_key is verified **before** any decrypted length field is trusted (v2); the length/padding checks run only after a valid MAC | — | `td/mtproto/Transport.cpp:243-296` | high | No padding/length oracle (docs P-132) |
| TD-CRYPTO-4 | v2: `message_data_length % 4 == 0` (`check_mod4` defaults to true) | "invalid length (not divisible by four)" → close | `td/mtproto/Transport.cpp:274-279`; `td/mtproto/PacketInfo.h:28` | medium | Docs P-133 |
| TD-CRYPTO-5 | v2: `message_data_length ≤ tail_size − 16` (tail = bytes after the 24-byte external header; 16 = msg_id+seq_no+len) | "message_data_length is too big" → close | `td/mtproto/Transport.cpp:280-284` | critical | Prevents reading past the decrypted buffer |
| TD-CRYPTO-6 | v2: padding `= tail_size − (message_data_length+16)` must be in **[12, 1024]** | "invalid padding length" → close | `td/mtproto/Transport.cpp:285-290` | high | Docs P-133; rejects truncation/extension games |
| TD-CRYPTO-7 | v1 (never used inbound, see CRYPTO-12) handles a bad length **branch-free**: the SHA1 is computed over `data_size` or `tail_size` chosen arithmetically, then the error is raised after the MAC check | "invalid length" → close | `td/mtproto/Transport.cpp:254-259,291-296` | low | **Beyond docs:** a timing-safe length check for MTProto 1.0 |
| TD-CRYPTO-8 | KDF2: `sha256_a = SHA256(msg_key ‖ auth_key[X..X+36])`, `sha256_b = SHA256(auth_key[40+X..+36] ‖ msg_key)`; `aes_key = a[0..8]‖b[8..24]‖a[24..32]`, `aes_iv = b[0..8]‖a[8..24]‖b[24..32]` | — | `td/mtproto/KDF.cpp:74-104` | critical | Wrong X or slicing = decryption under the wrong key |
| TD-CRYPTO-9 | KDF v1 asserts `auth_key.size() == 256` | `LOG_CHECK` → abort | `td/mtproto/KDF.cpp:17-18` | low | Invariant |
| TD-CRYPTO-10 | Encrypted part alignment: the trailing `size & 15` bytes are stripped before AES-IGE (they are tolerated, not rejected) | — | `td/mtproto/Transport.cpp:224-225` | low | Deliberate, for padded-intermediate transport padding. **Lenient** vs docs P-130 (`len%16==0`) |
| TD-CRYPTO-11 | Minimum sizes: the packet must be ≥ `sizeof(CryptoHeader)` (40 B: key_id 8 + msg_key 16 + salt 8 + session_id 8), and the decrypted tail ≥ 16 B (prefix) | "too small" / "Too small encrypted part" → close | `td/mtproto/Transport.cpp:217-220,243-246` | high | Prevents out-of-bounds header reads |
| TD-CRYPTO-12 | Inbound packets are always parsed as MTProto **2.0** (`packet_info.version = 2`); no v1 fallback on receive | v1 packets fail the msg_key check → close | `td/mtproto/RawConnection.cpp:189-192` (and `:404-407` for HTTP) | high | No downgrade to the SHA1-based MAC |
| TD-CRYPTO-13 | CSPRNG failure (`RAND_bytes != 1`) is fatal | `LOG_IF(FATAL)` | `tdutils/td/utils/Random.cpp:62-75` | critical | Fail closed rather than use weak nonces/keys |
| TD-CRYPTO-14 | Handshake temp key/iv: `tmp_aes_key = SHA1(new_nonce‖server_nonce) ‖ SHA1(server_nonce‖new_nonce)[0..12]`; `tmp_aes_iv = SHA1(server_nonce‖new_nonce)[12..20] ‖ SHA1(new_nonce‖new_nonce) ‖ new_nonce[0..4]` | — | `td/mtproto/KDF.cpp:52-72` | critical | — |
| TD-CRYPTO-15 | Outbound padding (v2), plain transport: `encrypted_size = align16(32+len+12)` rounded **up to a bucket** {64,128,192,256,384,512,768,1024,1280}, then steps of 448. With an MTProxy dd/ee secret: random `0..255` extra + 12, aligned to 16. Padding bytes come from the CSPRNG | — | `td/mtproto/Transport.cpp:166-197,350-352` | low | Guarantees ≥12 B of padding (server-side requirement). **Beyond docs:** size bucketing hides message lengths |
| TD-CRYPTO-16 | MTProto 1.0 (SHA1 msg_key, KDF v1) is used **only** to encrypt the `bind_auth_key_inner` message under the perm key | — | `td/mtproto/SessionConnection.cpp:856-878` | high | Required by auth.bindTempAuthKey. v1 must not leak into normal traffic |

## MSG — packet/session-level checks on decrypted messages

| ID | What is checked | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-MSG-1 | `header.auth_key_id == auth_key.id()` (checked before decryption) | "auth_key_id mismatch" → close (no key drop) | `td/mtproto/Transport.cpp:227-231` | critical | Prevents decrypting with the wrong key / key confusion |
| TD-MSG-2 | An unencrypted packet (`auth_key_id == 0`) on an established session is rejected | "Unexpected unencrypted packet" / "Unencrypted packet" → close | `td/mtproto/Transport.cpp:435-441`; `td/mtproto/SessionConnection.cpp:583-585,717-719` | critical | Otherwise a network attacker injects plaintext service messages / RPC results |
| TD-MSG-3 | Encrypted packet but the local key is empty → error | "auth key is empty" → close | `td/mtproto/Transport.cpp:442-444` | medium | — |
| TD-MSG-4 | Session refuses to flush/read without a usable key (`has_auth_key(now)`, which is false once the temp key has expired) | "No auth key" → close | `td/mtproto/SessionConnection.cpp:1081-1083`; `td/mtproto/AuthData.h:122-147` | high | Never accept or send under an expired temp key |
| TD-MSG-5 | `session_id` in the decrypted header == this session's id | "Receive packet from different session" → close | `td/mtproto/AuthData.cpp:139-145`; called at `td/mtproto/SessionConnection.cpp:722-739` | critical | Prevents cross-session replay/splicing (docs P-134) |
| TD-MSG-6 | Server msg_id must be **odd** (`msg_id & 1 == 1` ⇔ ≡1 or 3 mod 4) | "Receive invalid message" → close | `td/mtproto/AuthData.cpp:147-151` | high | Prevents reflecting client-originated (even) messages back (docs P-135) |
| TD-MSG-7 | Duplicate/replay window of N=**1000** msg_ids per session (sorted array of 2N, the oldest half dropped in bulk). msg_id **equal to a stored id** → code 1; **lower than all stored ids once ≥ N are stored** → code 2 | Code 1 → silently ignored **but acked**; code 2 → `on_session_failed` ("Receive too old packet") + close | `td/mtproto/AuthData.cpp:19-46,153`; `td/mtproto/AuthData.h:41-54,301`; `td/mtproto/SessionConnection.cpp:727-739` | critical | Replay protection (docs P-136). The ack stops server re-delivery |
| TD-MSG-8 | Time window: msg_id time must satisfy `server_time − 300 < t < server_time + 30`, enforced once the session's time difference has been set (always true after the first packet) | "Ignore too old or too new" → close | `td/mtproto/AuthData.cpp:133-137,158-164` | high | Replay protection beyond the 1000-id window (docs P-137). **Lenient:** see LENIENT-6 (the +30 s bound is effectively inert) |
| TD-MSG-9 | Server time difference is learned from **every** accepted packet's msg_id: set on the first packet of the session, afterwards **only increased** (`old + 1e-4 < new`) | — | `td/mtproto/AuthData.cpp:70-89,156`; `td/mtproto/SessionConnection.cpp:721-726` | medium | Monotone clock: a delayed packet cannot drag time back |
| TD-MSG-10 | Forced time reset when the server's msg_id is **> 15 s older** than the request it answers (rpc_result `req_msg_id`, pong `msg_id`), or on bad_msg 17 | `reset_server_time_difference` (can decrease) + Global update forced | `td/mtproto/SessionConnection.cpp:233-237,251-253,416-418,350-356` | medium | Recovers from a local clock running ahead, which the monotone rule cannot fix |
| TD-MSG-11 | The top-level message must exactly fill the envelope: `parse_message` (msg_id 8, seqno 4, bytes 4, body) then `fetch_end()`, so `bytes == message_data_length − 16` | "Failed to parse packet: Too much data to fetch" → close | `td/mtproto/SessionConnection.cpp:187-212,587-593` | high | Length consistency between the envelope and the message |
| TD-MSG-12 | Inner message length `bytes % 4 == 0`; the body read is bounds-checked (`fetch_string_raw` → `check_len`) | "size of message … is not divisible by 4" / "Not enough data" → close | `td/mtproto/SessionConnection.cpp:189-209` | high | — |
| TD-MSG-13 | Message body must be ≥ 4 bytes (a constructor id) | `on_session_failed` + close | `td/mtproto/SessionConnection.cpp:504-507` | medium | — |
| TD-MSG-14 | **Second** duplicate filter for updates on the *inner* msg_id (`updates_duplicate_checker_`, N=1000) plus a re-checker (N=100) for diagnostics | Duplicate → skipped; too old (code 2) → `on_session_failed` + close | `td/mtproto/SessionConnection.cpp:542-559`; `td/mtproto/AuthData.h:259-265,302-303` | high | Container-inner messages bypass TD-MSG-7. **Beyond docs** |
| TD-MSG-15 | Incoming seq_no: only the parity is used (odd ⇒ queue an ack). There is **no** monotonicity or consistency validation | — | `td/mtproto/SessionConnection.cpp:501-503` | — | **Lenient** (see LENIENT-7) |
| TD-MSG-16 | Incoming server_salt: **not checked** (explicit TODO) | — | `td/mtproto/SessionConnection.cpp:55`; `td/mtproto/Transport.cpp:311` (stored, unused) | — | **Lenient** (docs do not require it) |
| TD-MSG-17 | Outgoing msg_id: `t = server_time·2^32`, low 22 bits XOR random, `& ~3`; if ≤ last then `last + 8·(1..1024)`; strictly increasing | — | `td/mtproto/AuthData.cpp:107-125` | high | Server rejects non-monotone ids; the random low bits stop predictable ids |
| TD-MSG-18 | Outbound validity window `(server_time − 150, server_time + 30)`: a queued query whose msg_id has gone stale is wrapped in a **fresh container** instead of being sent bare | — | `td/mtproto/AuthData.cpp:127-131`; `td/mtproto/CryptoStorer.h:249-256` | medium | Avoids bad_msg 16/20 loops |
| TD-MSG-19 | Container msg_id is allocated **after** all inner ids (strictly greater); seq_no: content-related = odd and `+2`, service/containers even | — | `td/mtproto/CryptoStorer.h:37-44,249-253`; `td/mtproto/AuthData.h:267-274` | medium | Docs P-144/P-150..P-155 (else bad_msg 19/32-35) |
| TD-MSG-20 | Salt usability: a salt is "valid" only while `valid_until > server_time + 60`. A salt from bad_server_salt is valid for 600 s and clears future salts. The initial salt is random with `valid_until = −1e10` (unusable). The current salt is advanced to the newest future salt whose `valid_since < server_time` | Without a valid salt no queries are sent (only get_future_salts/acks/ping); `is_ready` is false | `td/mtproto/AuthData.h:220-245`; `td/mtproto/AuthData.cpp:48-68,169-175`; `td/mtproto/SessionConnection.cpp:657-693,950-956` | medium | — |
| TD-MSG-21 | `get_future_salts(64)` at most once per 60 s, and only when needed | — | `td/mtproto/SessionConnection.cpp:937-945,683-693` | low | — |
| TD-MSG-22 | session_id = CSPRNG uint64, regenerated until non-zero, fresh for every Session object (and every recreated session) | — | `td/telegram/net/Session.cpp:261-265` | high | A predictable or reused session_id weakens replay separation |
| TD-MSG-23 | HTTP long-poll connection sends nothing before it has a salt | — | `td/mtproto/SessionConnection.cpp:657-666` | low | — |

## SVC — service messages

| ID | What is checked / how handled | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-SVC-1 | Dispatch by constructor: `msg_container` → container; `rpc_result` → result; any constructor of `mtproto_api` → strict fetch **with `fetch_end()`** then a typed handler; anything else = "update" | Parse error of a service object → close | `td/mtproto/SessionConnection.cpp:500-560` | high | Strict parsing of service messages |
| TD-SVC-2 | Container: `int32 count`, then `count` × `parse_message` (each with bytes%4 and bounds); `container_message_id_` is tracked for diagnostics | Inner parse error → close | `td/mtproto/SessionConnection.cpp:214-231` | medium | **Lenient:** nested containers, trailing bytes, no count cap, inner ids not ordered/deduped (LENIENT-8) |
| TD-SVC-3 | `rpc_result`: `req_msg_id` parsed; `req_msg_id == 0` rejected | "Receive an update in rpc_result" → close | `td/mtproto/SessionConnection.cpp:239-248` | medium | — |
| TD-SVC-4 | rpc_result body: `rpc_error` (strictly parsed), `gzip_packed` (decompressed), or raw bytes passed through | rpc_error parse error → close | `td/mtproto/SessionConnection.cpp:255-277` | medium | — |
| TD-SVC-5 | rpc_result for an unknown/already-answered msg_id is dropped. Dropped results > 16 KiB are summed; > **256 KiB** → error | Code 2 "Too many dropped packets" → close | `td/telegram/net/Session.cpp:870-891` | medium | Bounds bandwidth/memory waste. **Beyond docs** |
| TD-SVC-6 | rpc_error sanitising: `code == 0` or `|code| ≥ 10000` → 500; non-UTF-8 message → `INVALID_UTF8_ERROR_MESSAGE`; error with msg_id 0 → ignored; unknown msg_id → `force_ack` | — | `td/telegram/net/Session.cpp:922-931,974-988` | low | Untrusted error data. **Beyond docs** |
| TD-SVC-7 | 401 handling: `AUTH_KEY_PERM_EMPTY` under PFS → drop **only** the temp key (500, retry); other 401s: a non-main session under PFS drops its temp key; a CDN or non-main-DC key is dropped and re-imported **without** log-out; otherwise `auth_flag=false`, log out, session failed. `SESSION_PASSWORD_NEEDED` is excluded | — | `td/telegram/net/Session.cpp:932-967` | high | Wrong 401 handling = needless log-out (DoS), or keeping a revoked key |
| TD-SVC-8 | `CONNECTION_NOT_INITED` / `CONNECTION_LAYER_INVALID` (400) → re-attach the initConnection header, error → 500 (retry) | — | `td/telegram/net/Session.cpp:968-972`; `td/mtproto/AuthKey.h:42-53` | low | — |
| TD-SVC-9 | bad_msg_notification. **16** (msg_id too low): resend with a new msg_id (time is fixed by TD-MSG-9). **17** (too high): clear the send queue, force a time reset from the notification's msg_id, session failed. **18, 19, 32, 33, 34, 35, 64, and any unknown code**: close ("BUG! CALL FOR A DEVELOPER"). **20** (too old): resend | As listed | `td/mtproto/SessionConnection.cpp:324-387` | medium | Unknown codes fail closed. No check that `bad_msg_id` belongs to us (LENIENT-9) |
| TD-SVC-10 | bad_server_salt: **unconditionally** adopt `new_server_salt` (valid 10 min, future salts cleared), persist it, and resend `bad_msg_id` (or its whole container) | — | `td/mtproto/SessionConnection.cpp:389-397`; `td/mtproto/AuthData.h:225-231`; `td/telegram/net/Session.cpp:607-613` | medium | Authenticated by msg_key, so a network attacker cannot inject it |
| TD-SVC-11 | new_session_created: map `first_msg_id` to its container; every sent query with `container_msg_id < first_msg_id` is resent; main session injects `updatesTooLong` (forces getDifference). **unique_id is not deduped; server_salt is ignored** | — | `td/mtproto/SessionConnection.cpp:309-322`; `td/telegram/net/Session.cpp:701-732` | medium | Prevents lost queries/updates (docs P-320). LENIENT-10 |
| TD-SVC-12 | msgs_ack: every id is matched against sent containers/queries; unknown ids are ignored; quick-ack promise fulfilled | — | `td/mtproto/SessionConnection.cpp:399-406`; `td/telegram/net/Session.cpp:763-798` | low | — |
| TD-SVC-13 | gzip_packed (service level): `gzdecode` then recursive `on_slice_packet`. A decode error or truncated stream returns an **empty** buffer, which then fails TD-MSG-13 | Empty → session failed + close | `td/mtproto/SessionConnection.cpp:408-412`; `tdutils/td/utils/Gzip.cpp:157-185` | medium | **Lenient:** no decompressed-size cap, no recursion-depth cap (LENIENT-11) |
| TD-SVC-14 | pong: forced time reset if the server msg_id is > 15 s before `pong.msg_id`; if `destroy_auth_key` was sent > 60 s ago without a reply → error; liveness timestamps updated; Session dead-query detector (see TD-SVC-24) | Error → close | `td/mtproto/SessionConnection.cpp:414-433` | low | — |
| TD-SVC-15 | future_salts: adopted as-is (sorted by valid_since desc); **req_msg_id and `now` not checked**; an empty list is ignored | — | `td/mtproto/SessionConnection.cpp:435-449`; `td/mtproto/AuthData.cpp:91-99` | low | Authenticated; LENIENT-12 |
| TD-SVC-16 | msgs_state_info: `req_msg_id` must be an outstanding **GetStateInfo** service query; `msg_ids.size() == info.size()` | "Unknown msgs_state_info" / type mismatch / size mismatch → close | `td/mtproto/SessionConnection.cpp:451-477` | medium | Prevents mis-attributing state bytes to queries (which could cause double execution or loss) |
| TD-SVC-17 | msgs_all_info: `msg_ids.size() == info.size()` | Size mismatch → close | `td/mtproto/SessionConnection.cpp:479-482` | low | — |
| TD-SVC-18 | msg_detailed_info / msg_new_detailed_info / state bytes → `Session::on_message_info`: state&7 ∈ {1,2,3} → resend; 0 without an answer id → resend; 4 (or 0 with an answer) → mark acked; other → log; non-zero `answer_msg_id` → `msg_resend_req`. Only ids in `sent_queries_` are affected | — | `td/mtproto/SessionConnection.cpp:484-498`; `td/telegram/net/Session.cpp:1038-1091` | medium | The idempotency-safe resend policy (docs B2.15) |
| TD-SVC-19 | destroy_auth_key_ok/none/fail is accepted **only if** this connection requested key destruction | Unexpected → logged and ignored; expected → drop the main key, close | `td/mtproto/SessionConnection.cpp:286-307`; `td/telegram/net/Session.cpp:1093-1097` | high | Otherwise a server message could wipe the key at will |
| TD-SVC-20 | Unknown/unsupported mtproto_api objects (e.g. RpcDropAnswer outside rpc_result, server-sent msgs_state_req, msg_resend_req) → logged and ignored | — | `td/mtproto/SessionConnection.cpp:280-284` | low | — |
| TD-SVC-21 | Updates arriving on a **CDN** session are rejected | "Receive an update from a CDN connection" → close | `td/telegram/net/Session.cpp:857-860` | high | Docs P-308: an untrusted CDN must not inject updates |
| TD-SVC-22 | Ack policy: ack every odd-seq_no message, **before** parsing it (including container elements and ignored duplicates); acks batched (≤30 s, flushed at 100 ids, ≤8192 ids per msgs_ack) | — | `td/mtproto/SessionConnection.cpp:501-503,728-731,886-900,1004-1011`; `td/mtproto/SessionConnection.h:129` | low | — |
| TD-SVC-23 | Outbound container limits: ≤1000 queries and ≤32 KiB per packet; cancel count capped so the total stays below 1024; ≤8192 ids per resend/state_req/ack | — | `td/mtproto/SessionConnection.cpp:947-1011` | low | Server rejects oversized containers (docs P-163) |
| TD-SVC-24 | Dead-query detector: after a connection has been up 60 s, a pong while queries are in "unknown" state, or a query unanswered for `60 s + (now − ping_time)`, → error | Close (reconnect) | `td/telegram/net/Session.cpp:564-597` | low | **Beyond docs** |
| TD-SVC-25 | Unknown-state queries capped: `unknown_queries_ > 1024` (`MAX_INFLIGHT_QUERIES`) → session failed; at most 1024 in flight | Session failed | `td/telegram/net/Session.cpp:1295-1299,1544`; `td/telegram/net/Session.h:181` | low | — |
| TD-SVC-26 | On reconnect, unacked queries are marked *unknown* and resolved with `msgs_state_req` instead of being blindly resent; invokeAfter dependents wait while any query is unknown, and a dependency must be from the same session_id | — | `td/telegram/net/Session.cpp:673-695,1129-1145,1300-1308` | medium | Prevents double execution of non-idempotent calls |

## PFS — temporary keys and binding

| ID | What is checked | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-PFS-1 | Temp key lifetime is random `23–24 h` (`expires_in` in `p_q_inner_data_temp_dc`). CDN keys are generated the same way (temporary, never bound) | — | `td/telegram/net/Session.cpp:1443-1444`; `td/mtproto/Handshake.cpp:118-121` | medium | — |
| TD-PFS-2 | Regenerate the temp key **60 min** before expiry (**2 min** if the temp key is persisted) | New handshake | `td/telegram/net/Session.cpp:1493-1495`; `td/mtproto/AuthData.h:101-112` | medium | Never run on an expired key |
| TD-PFS-3 | Expired temp key ⇒ `has_tmp_auth_key` false ⇒ not ready, and the connection errors "No auth key" | Close; new key | `td/mtproto/AuthData.h:122-147`; `td/mtproto/AuthData.cpp:54-68`; `td/mtproto/SessionConnection.cpp:1081-1083` | high | — |
| TD-PFS-4 | **No API queries until the temp key is bound** (`get_bind_flag`); also none while the main key is being checked or destroyed | Queries stay pending | `td/telegram/net/Session.cpp:1352-1360,1541-1559`; `td/mtproto/AuthData.h:160-166` | critical | An unbound temp key is not tied to the user; sending queries would leak them / fail auth |
| TD-PFS-5 | Bind message: `bind_auth_key_inner(nonce=rand64, temp_auth_key_id, perm_auth_key_id, temp_session_id, expires_at = server-time expiry)`, encrypted with the **perm key, MTProto 1.0**, random salt and random session_id; the inner msg_id == the outer `auth.bindTempAuthKey` msg_id; `dispatch_ttl_=0` | — | `td/telegram/net/Session.cpp:1362-1388`; `td/mtproto/SessionConnection.cpp:856-878` | critical | Server-side binding proof; a mistake = PFS silently off or bind rejected |
| TD-PFS-6 | Bind result must parse as `Bool` and be `true`. `ENCRYPTED_MESSAGE_INVALID` triggers the main-key validation path, with **immunity** if server time is unreliable, or the key is < 60 s old, or (key > 1 day old **and** last success < 1 day ago). Without PFS and without immunity → drop the main key and log out | Other errors → close both connections; `DispatchTtlError` → resend | `td/telegram/net/Session.cpp:383-445` | high | Prevents false log-outs from clock skew while still detecting a dead perm key. **Beyond docs** |
| TD-PFS-7 | `-404` ladder in `on_closed`: PFS → drop the temp key only; CDN → drop the CDN key + session failed; destroying → drop the main key; otherwise a non-PFS session first switches to PFS to probe the perm key, then (if `need_check_main_key_`) drops the main key → log out (or a silent drop for a non-main DC) | — | `td/telegram/net/Session.cpp:619-662` | high | Instantly wiping the perm key on a spoofable-looking −404 is a DoS. **Beyond docs** |
| TD-PFS-8 | Main-key probe: `help.getNearestDc` over the **perm key without PFS**; ok or any non-−404 error ⇒ key fine | −404 → close, then the ladder above | `td/telegram/net/Session.cpp:447-473,1327-1350` | medium | — |
| TD-PFS-9 | `auth.dropTempAuthKeys(except_auth_keys = currently registered main-session temp keys)`, debounced (0.1 s / max 1 s), re-run up to 6× at 5 s intervals while > 1 key is registered | Retried on error | `td/telegram/net/TempAuthKeyWatchdog.h:50-147`; registration `td/telegram/net/Session.cpp:256-258,1410-1412` | medium | Revokes stale temp keys server-side (limits key-compromise windows). **Beyond docs** |
| TD-PFS-10 | Persisted temp key: dropped on load if `expires_at < now`. Persisted expiry is stored as time-left plus a wall-clock stamp, and elapsed wall time is clamped ≥ 0, so a clock rollback cannot extend a key's life. Without persistence a stored temp key is erased | — | `td/telegram/net/SessionProxy.cpp:130-143`; `td/mtproto/AuthKey.h:96-118` | medium | — |
| TD-PFS-11 | Temp-key salts are kept separately from perm-key salts (Session takes `server_salts` only together with a temp key) | — | `td/telegram/net/Session.cpp:249-260`; `td/telegram/net/SessionProxy.cpp:279-281` | low | — |
| TD-PFS-12 | Losing the auth flag (`set_auth_flag(false)`) also drops the temp key | — | `td/mtproto/AuthData.h:153-158` | medium | — |
| TD-PFS-13 | CDN sessions never use PFS (`use_pfs && !is_cdn`) | — | `td/telegram/net/SessionMultiProxy.cpp:132-134` | low | CDN has no perm key to bind to |
| TD-PFS-14 | Key destruction (log-out): `destroy_auth_key` is sent only when requested, has a 60 s response deadline, and a `-404` or the response drops the main key | — | `td/mtproto/SessionConnection.cpp:420-424,695-697,966-978`; `td/telegram/net/Session.cpp:638-641,1093-1097`; `td/telegram/net/NetQueryDispatcher.cpp:315-332` | medium | — |

## TRANSPORT — framing, transport errors, obfuscation

| ID | What is checked | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-TRANSPORT-1 | Maximum inbound frame: an expected size > `(1<<22)+1024` (4 MiB + 1 KiB) is rejected. **Only enforced while the frame is still incomplete** (the check is on `wait_size`) | "Expected packet size is too big" → close | `td/mtproto/RawConnection.cpp:163-173` | high | Prevents memory-exhaustion DoS by a network attacker before any MAC (see LENIENT-13) |
| TD-TRANSPORT-2 | Intermediate framing: a length with the top bit set is a 4-byte quick-ack; otherwise wait for `len+4` bytes | — | `td/mtproto/TcpTransport.cpp:20-48` | medium | — |
| TD-TRANSPORT-3 | Short packets (< 16 B): < 4 B → error; int32 `0` → NOP; `-1` with ≥ 8 B → quick ack; **any other int32 → transport error code** | Error → see TD-TRANSPORT-4 | `td/mtproto/Transport.cpp:418-433` | medium | — |
| TD-TRANSPORT-4 | Transport errors. `-429` → error **500** + per-client `mtproto_error_flood_control` (1/1 s, 4/2 s, 8/3 s) delaying reconnects. `-404` → error code −404 (handshake reset / PFS ladder). Any other code (incl. `-444`) → generic error | Close | `td/mtproto/RawConnection.cpp:197-199,221-232`; `td/telegram/net/ConnectionCreator.cpp:89-91,112-114,723-727,1000-1001` | medium | −404 semantics drive key management (TD-PFS-7) |
| TD-TRANSPORT-5 | Quick-ack: inbound token must have bit 31 set and be an outstanding token; otherwise ignored (not an error). On send, a token collision in the map → no quick ack requested | — | `td/mtproto/RawConnection.cpp:73-82,234-249` | low | — |
| TD-TRANSPORT-6 | Errors are sticky: after the first error `has_error_` makes every later flush fail ("Connection has already failed") | Close | `td/mtproto/RawConnection.cpp:107-121,259-262` | medium | No processing of further bytes from a stream already known to be bad |
| TD-TRANSPORT-7 | Packets are re-aligned to 4 bytes before parsing (copy if unaligned) | `LOG_CHECK` | `td/mtproto/RawConnection.cpp:179-187` | low | — |
| TD-TRANSPORT-8 | Obfuscated2 header: 64 random bytes, regenerated while the first byte is `0xef`, or the first int ∈ {`HEAD`,`POST`,`GET `,`OPTI`,`0xdddddddd`,`0xeeeeeeee`,`0x02010316`}, or the second int == 0 (skipped for fake-TLS); `CHECK(try_cnt < 10)`. Protocol tag at offset 56, int16 dc at offset 60 | — | `td/mtproto/TcpTransport.cpp:80-112` | medium | DPI resistance; a bad header gets a connection reset |
| TD-TRANSPORT-9 | Obfuscation keys: enc key/iv = header[8..40]/[40..56]; dec = the same from the reversed header. With a proxy secret, `key = SHA256(key ‖ secret16)` | — | `td/mtproto/TcpTransport.cpp:114-142` | high | A wrong key derivation leaks plaintext MTProto framing |
| TD-TRANSPORT-10 | Padded intermediate (`0xdddddddd`) whenever the secret is ≥ 17 bytes: 0..15 random bytes appended per frame. Inbound padding is tolerated (stripped by `size & 15` / `& ~3`) | — | `td/mtproto/TcpTransport.cpp:50-78`; `td/mtproto/ProxySecret.h:44-46`; `td/mtproto/Transport.cpp:224-225`; `td/mtproto/HandshakeConnection.h:79` | low | — |
| TD-TRANSPORT-11 | Outbound frame invariants: `size % 4 == 0`, `size < 2^24` | CHECK → abort | `td/mtproto/TcpTransport.cpp:51-53` | low | — |
| TD-TRANSPORT-12 | Liveness. Ping (`ping_delay_disconnect` with `disconnect_delay = ping_timeout + 2`) and read timeouts: online `rtt·2.5` / `rtt·3.5` (rtt ≥ 2 s), offline `135 s + rand(0..5)`. **Any successfully decrypted packet counts as a pong.** Going online forces a reply within rtt | "Ping timeout"/"Read timeout" → close | `td/mtproto/SessionConnection.h:145-163`; `td/mtproto/SessionConnection.cpp:569-572,781-797,1098-1115`; `td/mtproto/RawConnection.cpp:200-206` | low | Detects black-holed connections |
| TD-TRANSPORT-13 | Reconnect flood control per client: `sanity` 5/10 s; offline 1/1 s, 4/2 s, 8/3 s; online 1/4 s, 5/5 s; plus exponential backoff | Delayed reconnect | `td/telegram/net/ConnectionCreator.cpp:102-115,1000-1004` | low | Avoids reconnect storms (server may −429) |
| TD-TRANSPORT-14 | Connection "check mode": a new socket must complete a ping (`req_pq_multi` round trip without a key, or ping/pong over a copy of the temp-key AuthData) within 10 s before being handed out | Fail → closed | `td/telegram/net/ConnectionCreator.cpp:1070-1121`; `td/mtproto/Ping.cpp:19-101`; `td/mtproto/PingConnection.cpp:31-91` | low | The req_pq probe does **not** parse the reply (LENIENT-14) |
| TD-TRANSPORT-15 | Raw connections from an older network generation are discarded | — | `td/telegram/net/Session.cpp:1247-1252` | low | — |
| TD-TRANSPORT-16 | HTTP transport: the response must be an HTTP *Response* with exactly one body (`container_.size()==2`); headers capped at 256 KiB. The 4 MiB frame cap (TD-TRANSPORT-1) also applies | "Unexpected HTTP query type"/"Wrong response" → close | `td/mtproto/HttpTransport.cpp:27-42`; `tdnet/td/net/HttpReader.h:108-112` | low | — |
| TD-TRANSPORT-17 | Obfuscated header dc_id: raw dc (+10000 on test DCs), negated for media-only options | — | `td/telegram/net/ConnectionCreator.cpp:780-806` | low | A wrong dc is routed to the wrong DC by MTProxy |

## PROXY — MTProxy secrets, fake TLS, SOCKS5/HTTP

| ID | What is checked | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-PROXY-1 | Secret decoding: hex, else base64url, else base64 | "Wrong proxy secret" (400) | `td/mtproto/ProxySecret.cpp:15-27` | low | — |
| TD-PROXY-2 | Secret shape: length > `17 + 182` → error (or truncated if `truncate_if_needed`); accepted: exactly 16 B; 17 B with first byte `0xdd`; ≥ 18 B with first byte `0xee` (non-empty domain); < 16 → "Wrong proxy secret"; anything else → "Unsupported proxy secret" | 400 error | `td/mtproto/ProxySecret.cpp:29-46` | medium | Rejects malformed secrets that would crash TLS-hello building |
| TD-PROXY-3 | Domain used in the SNI is truncated to `MAX_DOMAIN_LENGTH = 182` so the ClientHello can never exceed its fixed size | — | `td/mtproto/ProxySecret.h:18`; `td/mtproto/TlsInit.cpp:201-203` | low | — |
| TD-PROXY-4 | ClientHello builder validation: random/zero op length in (0, 1024]; grease seed in range; scope < 2^14; balanced scopes; total ≤ 514 before padding and ≥ 43; padded to exactly **517** bytes | Error → `move_as_ok()` abort (unreachable with truncated domain) | `td/mtproto/TlsInit.cpp:210-312,478-499` | low | — |
| TD-PROXY-5 | ClientHello random = `HMAC-SHA256(secret16, whole hello with zero random)`, last 4 bytes XOR `unix_time` (corrected by the **server time difference**) | — | `td/mtproto/TlsInit.cpp:412-424,501-507` | medium | The server-side replay window relies on the timestamp |
| TD-PROXY-6 | Key-share field is a valid-looking X25519 point (random x with `y²` a quadratic residue mod 2^255−19, doubled 3×) | — | `td/mtproto/TlsInit.cpp:348-368,431-471` | low | DPI resistance |
| TD-PROXY-7 | ServerHello verification: the stream must start with `16 03 03 <len>` then `14 03 03 00 01 01 17 03 03 <len>`, and `HMAC-SHA256(secret16, client_random ‖ response_with_server_random_zeroed)` must equal the server random (bytes 11..43) | "First part of response to hello is invalid" / "Response hash mismatch" → error, connection dropped | `td/mtproto/TlsInit.cpp:509-543` | high | Authenticates the MTProxy (prevents an active prober/MITM proxy). Comparison is not constant time; the server timestamp is not checked |
| TD-PROXY-8 | After the ServerHello there must be no extra buffered bytes; the proxy handshake has a 10 s deadline | "Proxy has sent too many data" / "Connection timeout expired" | `tdnet/td/net/TransparentProxy.cpp:36-47,54-62,80-82` | low | — |
| TD-PROXY-9 | Fake-TLS data phase: every inbound record must start `17 03 03`; the 16-bit length is honoured (no cap below 65535) | "Invalid bytes at the beginning of a packet (emulated tls)" → close | `td/mtproto/TlsReaderByteFlow.cpp:15-37` | medium | — |
| TD-PROXY-10 | Fake-TLS outbound: records ≤ **2878** bytes; the first record is preceded once by CCS `14 03 03 00 01 01` | CHECK on overflow | `td/mtproto/TcpTransport.cpp:162,173-213` | low | — |
| TD-PROXY-11 | SOCKS5: greeting version 5; method 0 or 2 only; username/password < 128 B; sub-negotiation version 1 and status 0; reply version 5, REP = 0, RSV = 0, ATYP ∈ {1 (IPv4), 4 (IPv6)} | Error → connection fails | `tdnet/td/net/Socks5.cpp:35-168` | low | — |
| TD-PROXY-12 | HTTP CONNECT: status line must be `HTTP/1.1 2xx` or `HTTP/1.0 2xx`; headers read up to the blank line | "Failed to connect" | `tdnet/td/net/HttpProxy.cpp:36-80` | low | — |
| TD-PROXY-13 | `dcOption.secret` / `ipPortSecret.secret` from config go through `ProxySecret::from_binary`; an invalid secret leaves the option invalid (no IP), so it is skipped | Option dropped | `td/telegram/net/DcOptions.h:71-79,89-97`; `td/telegram/net/DcOptionsSet.cpp:70-73` | low | — |
| TD-PROXY-14 | User proxy input: non-empty server ≤ 255 chars, port 1..65535, valid type | 400 error | `td/telegram/net/Proxy.cpp:13-49` | low | — |

## CDN — redirects, decryption, hash verification

| ID | What is checked | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-CDN-1 | `upload.getFile.cdn_supported` is set only when not streaming (offset 0); web files never use the CDN | — | `td/telegram/files/FileDownloader.cpp:150-174` | low | Because CDN data needs whole-range hash checks |
| TD-CDN-2 | `upload.fileCdnRedirect`: `encryption_key.size()==32` and `encryption_iv.size()==16`; the same token → just restart the part; a new token → `generation++`, store hashes, enable `need_check_` | "Wrong ctr key or iv size" → download error | `td/telegram/files/FileDownloader.cpp:76-100` | high | — |
| TD-CDN-3 | Redirect `dc_id` → `DcId::external(dc_id)`, which `CHECK`s `1 ≤ dc_id ≤ 1000` | **Abort** on an out-of-range id (main-DC-authenticated input) | `td/telegram/files/FileDownloader.cpp:91`; `td/telegram/net/DcId.h:20-24,35-38` | low | Fail-crash rather than fail-error |
| TD-CDN-4 | CDN requests are sent with `AuthFlag::Off`; the CDN session uses the anonymous initConnection header, no PFS, and its own temp-style key; updates from it are rejected (TD-SVC-21) | — | `td/telegram/files/FileDownloader.cpp:177-181`; `td/telegram/net/Session.cpp:276-280,857-860`; `td/telegram/net/SessionMultiProxy.cpp:132-134` | high | Docs P-308: no private info to the CDN, no CDN-injected updates |
| TD-CDN-5 | Returned part size must be ≤ the requested (padded) size | "Part size is more than requested" → error | `td/telegram/files/FileDownloader.cpp:240-246` | medium | — |
| TD-CDN-6 | AES-256-CTR with IV = `encryption_iv` whose last 4 bytes are replaced by `offset/16` big-endian; `CHECK(offset % 16 == 0)` | CHECK | `td/telegram/files/FileDownloader.cpp:252-263` | medium | — |
| TD-CDN-7 | A part fetched under an old file_token generation is discarded and refetched | Restart part | `td/telegram/files/FileDownloader.cpp:118-123,178` | medium | Never mixes data from different tokens/keys |
| TD-CDN-8 | `upload.cdnFileReuploadNeeded` → `upload.reuploadCdnFile` sent to the **file's master DC** (authorised); the returned hashes are added | — | `td/telegram/files/FileDownloader.cpp:103-116,182-188` | low | — |
| TD-CDN-9 | `FILE_TOKEN_INVALID` → stop using the CDN and download from the master DC; `REQUEST_TOKEN_INVALID` → retry | — | `td/telegram/files/FileDownloader.cpp:63-71` | low | — |
| TD-CDN-10 | **SHA-256 verification of every downloaded CDN byte range** against hashes from the master DC (the redirect `file_hashes`, the reupload reply, or `upload.getFileHashes` asked of the master DC when a range is not covered) | "Hash mismatch" → download fails (`FILE_DOWNLOAD_RESTART` when re-checking a local file) | `td/telegram/files/FileDownloader.cpp:326-399,401-410,318-324` | critical | The CDN is untrusted; without this it can serve arbitrary file content (docs P-312) |
| TD-CDN-11 | With `need_check_` set: the file is "ready" only when `checked_prefix_size == size`; the partial-download bitmask and ready-prefix expose **only the verified prefix**; streaming offsets are ignored | — | `td/telegram/files/PartsManager.cpp:41-46,159-161,206-227` | high | Unverified bytes never reach the app (they are written only to the temp file) |
| TD-CDN-12 | CDN key `-404` → drop the CDN key + session failed; CDN `401` → drop the CDN key without log-out | — | `td/telegram/net/Session.cpp:633-637,949` | medium | Docs P-307 |

## TL — parser bounds

| ID | What is checked | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-TL-1 | Every fixed-size fetch calls `check_len`; after the first error the parser points at a static zero buffer with `left_len = 0` (sticky error, no out-of-bounds reads) | Error status | `tdutils/td/utils/tl_parsers.h:56-124`; `tdutils/td/utils/tl_parsers.cpp:21-34` | critical | Memory safety on untrusted input |
| TD-TL-2 | Strings: 1-byte length (< 254), 254 ⇒ 3-byte length, 255 ⇒ 7-byte length (non-standard, rejected if > `SIZE_MAX−3`); the aligned length is bounds-checked before advancing | "Not enough data to read" / "Too big string found" | `tdutils/td/utils/tl_parsers.h:126-162` | high | — |
| TD-TL-3 | Vectors: `multiplicity > remaining bytes` → error **before** `reserve` | "Wrong vector length" | `td/tl/tl_object_parse.h:119-136` | high | Prevents allocation-bomb DoS from a 4-byte count |
| TD-TL-4 | Boxed types check the constructor id (e.g. `Vector` `0x1cb5c415`); polymorphic fetch fails on an unknown constructor; Bool must be exactly true/false | "Wrong constructor"/"Unknown constructor"/"Bool expected" | `td/tl/tl_object_parse.h:20-51`; e.g. `td/generate/auto/td/mtproto/mtproto_api.cpp:1358-1372` | medium | Type confusion |
| TD-TL-5 | `fetch_end()` (no trailing bytes) is enforced for: the top-level message, every mtproto service object, and every API result (`fetch_result` in NetQuery.h). It is **not** enforced for: handshake replies (`check_end=false`) and container bodies | Error | `tdutils/td/utils/tl_parsers.h:176-180`; `td/mtproto/SessionConnection.cpp:524,589`; `td/telegram/net/NetQuery.h:323-336`; `td/mtproto/Handshake.cpp:31-46` | medium | — |
| TD-TL-6 | API-layer strings (`TlBufferParser`): NUL bytes → space; invalid UTF-8 is truncated to the last full character, or emptied | Sanitised | `tdutils/td/utils/tl_parsers.h:187-209`; `tdutils/td/utils/tl_parsers.cpp:46-61` | low | — |

## OTHER

| ID | What is checked | On failure | Where | Sev | Rationale |
|---|---|---|---|---|---|
| TD-OTHER-1 | `*_MIGRATE_X` (303): `X` must be a valid DC id 1..1000 before `main_dc_id` changes. **But** a non-main-DC query is resent with `DcId::internal(X)`, which `CHECK`s and aborts on an invalid X | Invalid → logged (main) / abort (non-main path) | `td/telegram/net/NetQueryDispatcher.cpp:390-434`; `td/telegram/net/DcId.h:20-38` | low | Authenticated input; a crash, not an exploit |
| TD-OTHER-2 | DC routing: the DC must be exact and within the table | "Not exact DC"/"Too big DC ID" → query error | `td/telegram/net/NetQueryDispatcher.cpp:200-209,160-162` | low | — |
| TD-OTHER-3 | FLOOD_WAIT/SLOWMODE/…: wait clamped to `[1, 14 days]`; a cumulative per-query `total_timeout_limit` → surfaced as 429; backoff 1→64 s for 5xx and negative codes; `-503` without `need_resend_on_503` → 502 | — | `td/telegram/net/NetQueryDelayer.cpp:22-112` | low | A hostile value cannot park the client forever |
| TD-OTHER-4 | Main DC id loaded from the DB is validated (`DcId::is_valid`) | Logged, ignored | `td/telegram/net/DcAuthManager.cpp:30-42` | low | — |
| TD-OTHER-5 | The same DH validation is reused for secret chats, calls and SRP (`check_config` on getDhConfig; `run_checks(skip_config_check=true)` plus a `g_a_hash` commitment check for calls) | Error | `td/telegram/SecretChatActor.cpp:514,1787,1900,2096,2115`; `td/telegram/CallActor.cpp:608,640`; `td/telegram/PasswordManager.cpp:61,84`; `td/mtproto/DhHandshake.cpp:151-166,186-188` | (out of scope) | — |
| TD-OTHER-6 | The auth flag is set heuristically when a result's constructor is `auth.authorization` / `auth.loginTokenSuccess` / `auth.sentCodeSuccess` (the main DC switches, except for importAuthorization) | — | `td/telegram/net/Session.cpp:897-909` | low | — |
| TD-OTHER-7 | DcAuthManager logs out if the main DC key is not OK while `check_authorization_is_ok` is pending | Log out | `td/telegram/net/DcAuthManager.cpp:228-240` | low | — |
| TD-OTHER-8 | E2E (secret chat) packets share `read_crypto_impl` (same msg_key and length checks) with `X = 8` if `is_creator && v2` else 0 | — | `td/mtproto/Transport.cpp:317-328,390-409` | (out of scope) | — |

---

## Checks tdlib performs that go BEYOND the official docs

1. Negative and persistent DH-prime cache (`good_prime:` = "bad" short-circuits) plus a built-in prime; both are used only after the cheap 2048-bit and g checks. See TD-AUTHKEY-27.
2. Per-step handshake deadlines (0.6 / 0.8 of the timeout) and a global handshake semaphore. See TD-AUTHKEY-2 and TD-AUTHKEY-40.
3. A 4 MiB + 1 KiB inbound frame cap before any decryption. See TD-TRANSPORT-1.
4. Constant-time msg_key comparison, and a branch-free v1 length check. See TD-CRYPTO-2 and TD-CRYPTO-7.
5. Size bucketing of outbound padding (64…1280, then 448 steps), plus random padding of unencrypted handshake packets. See TD-CRYPTO-15 and TD-AUTHKEY-42.
6. A second duplicate filter on update msg_ids inside containers. See TD-MSG-14.
7. A "too old msg_id" (older than all of the last 1000) recreates the session instead of being silently dropped. See TD-MSG-7.
8. The forced time reset when a reply is > 15 s older than its request. See TD-MSG-10.
9. A dropped-results byte cap (256 KiB), the dead-query detector, and the unknown-query cap. See TD-SVC-5, TD-SVC-24 and TD-SVC-25.
10. Error-code and UTF-8 sanitisation of rpc_error. See TD-SVC-6.
11. The −404 ladder and the ENCRYPTED_MESSAGE_INVALID immunity rules. See TD-PFS-6 and TD-PFS-7.
12. Server-side revocation of stale temp keys (`auth.dropTempAuthKeys`), and persisted temp-key expiry that a clock rollback cannot extend. See TD-PFS-9 and TD-PFS-10.
13. MTProxy fake-TLS: HMAC verification of the ServerHello and a no-trailing-data check. See TD-PROXY-7 and TD-PROXY-8.
14. The CDN partial/streaming state exposes only the hash-verified prefix. See TD-CDN-11.
15. The connection "check mode" ping before a socket is used. See TD-TRANSPORT-14.

## Places where tdlib is deliberately (or effectively) LENIENT

| ID | Leniency | Where | Reason / comment in code | Risk for a port |
|---|---|---|---|---|
| LENIENT-1 | The unencrypted handshake reply's msg_id and `message_data_length` are not validated: the 12-byte header is skipped and the body truncated to `& ~3`. tdlib itself sends msg_id **0** (the RTT probe sends 1) | `td/mtproto/HandshakeConnection.h:64-80`; `td/mtproto/PingConnection.cpp:51-52` | Comment: "remove some padded data" (transport padding) | Low: the handshake is authenticated by nonces, SHA1 and RSA |
| LENIENT-2 | pq is not bounded to ≤ 2^63−1. Big pq values go to a BigNum Pollard-rho of up to 2^23+2^24+2^25 iterations **before** the 144-byte size check. A prime or 1-factor pq yields `p=1, q=pq` (accepted and sent). There is no `p<q, p>1` check | `tdutils/td/utils/crypto.cpp:103-140,171-255`; `td/mtproto/Handshake.cpp:105-131` | No comment (TODO "qsieve?") | Medium: an on-path attacker (resPQ is unauthenticated) can burn CPU for seconds per handshake; a port should cap pq at 8 bytes |
| LENIENT-3 | `server_time` from server_DH_inner_data is accepted without a range check | `td/mtproto/Handshake.cpp:221` | — | Low (it is authenticated) |
| LENIENT-4 | dh_gen_retry/fail are not authenticated (no nonce or new_nonce_hash2/3 check); there is no retry with `retry_id` | `td/mtproto/Handshake.cpp:277-280` | Simplification; fails closed | Low |
| LENIENT-5 | Encrypted payloads that are not 16-aligned are accepted: the tail of `size & 15` bytes is dropped | `td/mtproto/Transport.cpp:224-225` | Needed for padded-intermediate transport padding | Low (the MAC covers the aligned part) |
| LENIENT-6 | The +30 s future bound of the msg_id window is effectively never hit: the time difference is raised to the packet's own time **before** the window check, and the first packet of a session re-anchors it | `td/mtproto/AuthData.cpp:156-164` | The comment quotes docs (the client checks only "if it is certain of its time") | Low |
| LENIENT-7 | Incoming seq_no is not validated at all | `td/mtproto/SessionConnection.cpp:501-503` | — | Low |
| LENIENT-8 | Containers: nested containers are allowed (recursive `on_slice_packet`); the count is not capped at 1024; trailing bytes after the last element are ignored; inner msg_ids are not required to be < the container's id, and are not deduplicated (except updates, TD-MSG-14) | `td/mtproto/SessionConnection.cpp:214-231,510-512` | — | Medium: there is no depth limit, so a hostile *authenticated* server could recurse deeply (stack); a port should cap depth |
| LENIENT-9 | bad_msg_notification / bad_server_salt are applied without checking that `bad_msg_id` is a recently sent message (docs P-146) | `td/mtproto/SessionConnection.cpp:324-397` | — | Low (msg_key-authenticated) |
| LENIENT-10 | new_session_created: `unique_id` is not deduplicated, so a repeated notice re-triggers resends and getDifference. `server_salt` is ignored | `td/mtproto/SessionConnection.cpp:309-322`; `td/telegram/net/Session.cpp:701-732` | Header TODO: "It is reasonable to store unique_id…" | Low |
| LENIENT-11 | gzip has **no output-size limit** (an output buffer of 2× input, then growing ×1.5) and gzip-in-gzip recursion is allowed | `tdutils/td/utils/Gzip.cpp:157-185`; `td/mtproto/SessionConnection.cpp:408-412` | — | Medium: decompression bomb from an authenticated server; a port should cap it (e.g. 16–64 MiB) |
| LENIENT-12 | future_salts: `req_msg_id` and `now` are not checked; salt validity bounds are taken verbatim | `td/mtproto/SessionConnection.cpp:435-449` | — | Low |
| LENIENT-13 | The 4 MiB frame cap only fires while the frame is incomplete. A frame fully buffered in one `flush_read` (which is unbounded) is accepted at any size | `td/mtproto/RawConnection.cpp:158-173`; `tdutils/td/utils/BufferedFd.h:100-114` | — | Low–medium; a port should check the declared length up front |
| LENIENT-14 | The RTT probe (`PingConnectionReqPQ`) does not parse the resPQ it gets back | `td/mtproto/PingConnection.cpp:69-83` | `// TODO: fetch_result` | Low (no key is derived) |
| LENIENT-15 | The incoming server salt is never compared | `td/mtproto/SessionConnection.cpp:55` | "TODO-list. 1. Should I check input salt?" | Low |
| LENIENT-16 | Fake-TLS: the ServerHello HMAC is compared with `!=` (not constant time); the server timestamp is not checked; record lengths up to 65535 are accepted | `td/mtproto/TlsInit.cpp:535-539`; `td/mtproto/TlsReaderByteFlow.cpp:28-34` | — | Low |
| LENIENT-17 | TL strings: padding bytes are not checked to be zero, and the non-canonical 254-prefix form is accepted for short strings | `tdutils/td/utils/tl_parsers.h:126-162` | — | Low |
| LENIENT-18 | Server-originated `msgs_state_req`, `msg_resend_req`, `destroy_session*` and `msg_copy` are not handled (ignored, or treated as an "update") | `td/generate/scheme/mtproto_api.tl:42-49,81-83`; `td/mtproto/SessionConnection.cpp:280-284` | The scheme has them commented out | Low |

---

## Counts

| Area | Entries |
|---|---|
| AUTHKEY | 42 |
| CRYPTO | 16 |
| MSG | 23 |
| SVC | 26 |
| PFS | 14 |
| TRANSPORT | 17 |
| PROXY | 14 |
| CDN | 12 |
| TL | 6 |
| OTHER | 8 |
| **Total checks** | **178** |
| LENIENT notes | 18 |

## Top-10 most critical (for auditing the Rust engine)

1. **TD-CRYPTO-1 and TD-CRYPTO-2.** Recompute msg_key = SHA256(auth_key[96..128] ‖ the *whole* decrypted payload incl. padding)[8..24] (X=8 inbound) and compare in constant time, before any decrypted field is used.
2. **TD-CRYPTO-5 and TD-CRYPTO-6 (+ CRYPTO-4).** After the MAC: `message_data_length ≤ tail−16`, padding in [12,1024], `len % 4 == 0`. These stop out-of-bounds reads and truncation.
3. **TD-MSG-1 and TD-MSG-2.** auth_key_id must equal the session key's id, and an unencrypted (`auth_key_id == 0`) packet is never accepted on an established session.
4. **TD-MSG-5.** The decrypted session_id must equal this session's id.
5. **TD-MSG-7 and TD-MSG-8.** Replay defence: a 1000-entry msg_id duplicate window (duplicates acked and ignored, too-old ⇒ new session) plus the −300 s time window and odd-parity (TD-MSG-6).
6. **TD-AUTHKEY-25, 26, 28 and 30.** DH group safety: an exactly 2048-bit safe prime, g ∈ 2..7 with the residue conditions, and g_a and the client's own g_b in [2^1984, p−2^1984].
7. **TD-AUTHKEY-5, 18, 22 and 23 (+ 19, 21).** nonce/server_nonce in resPQ, server_DH_params_ok and the inner data; SHA1(answer) integrity with pad < 16 and an aligned encrypted_answer.
8. **TD-AUTHKEY-35.** Key confirmation: new_nonce_hash1 = SHA1(new_nonce ‖ 0x01 ‖ SHA1(auth_key)[0..8])[4..20], plus the dh_gen_ok nonces.
9. **TD-AUTHKEY-7, 9, 11 and 15.** RSA server authentication: select a key only by exact fingerprint match against the pinned built-in keys (CDN: only keys from `help.getCdnConfig` over the main DC), and RSA_PAD with the SHA256 integrity hash and the `x < n` retry.
10. **TD-CDN-10 and TD-CDN-11 (+ SVC-21, CDN-4).** SHA-256 verification of every CDN byte range against master-DC hashes, with only the verified prefix exposed. No updates and no user info are taken from or sent to CDN sessions.

Next in line: **TD-PFS-4 and TD-PFS-5**. No API query is sent on a temp key until `auth.bindTempAuthKey` (an MTProto-1.0 inner message under the perm key, with inner msg_id equal to the outer) has returned `true`.
