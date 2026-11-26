# MtProtoKit auth-key creation and temp-key binding: security audit

Date: 2026-10-02. Read-only review; no repository files were changed.

Path prefixes used below:
- `MTK/` = `/Users/renoir/projects/Telegram/telegrammacos/submodules/telegram-ios/submodules/MtProtoKit/Sources/`
- `RE/` = `/Users/renoir/projects/Telegram/telegrammacos/submodules/telegram-ios/submodules/MTProtoRustEngine/Sources/MTProtoRustEngine/`
- `ENG/` = `/Users/renoir/projects/Telegram/telegrammacos/submodules/telegram-ios/third-party/mtproto-engine/crates/`
- `TD/` = `/Users/renoir/projects/Telegram/telegrammacos/submodules/telegram-ios/third-party/td/td/`
- `OSSL/` = `/Users/renoir/projects/Telegram/telegrammacos/submodules/telegram-ios/submodules/OpenSSLEncryptionProvider/Sources/OpenSSLEncryptionProvider.m`

## How the code fits together in the shipping macOS app

- The macOS app passes `RustNetworkEngineFactory()` and `OpenSSLEncryptionProvider()` (`Telegram-Mac/app/AppDelegate.swift:829`).
- The Rust engine never creates keys in this configuration. `RE/RustNetworkSession.swift:191` sets `setup.generate_key = 0`, and `RE/RustNetworkSession.swift:573-574` ignores any key the engine creates.
- Keys always come from `MTContext authInfoForDatacenterWithIdRequired` (`MTK/MTContext.m:1557-1596`). That builds an `MTDatacenterAuthAction` (`MTK/MTContext.m:1550-1555`; `authActionFactory` is set only in tests). The action runs `MTDatacenterAuthMessageService` on its own `MTProto` in unauthorized mode, over MtProtoKit's own `MTTcpTransport` and the same proxy settings. It then binds the temp key with `MTBindKeyMessageService` (`MTK/MTDatacenterAuthAction.m:59-185`).
- The finished `MTDatacenterAuthInfo` is stored in the context and passed to Rust:
  - The context stores it in Postbox keychain table entries, archived with NSKeyedArchiver (`TelegramCore/Sources/Account/Account.swift:11-52`, `TelegramCore/Sources/Network/Network.swift:1375-1395`).
  - Rust receives it through `RE/RustNetworkSession.swift:1278-1297` (`makeKeyMaterial`, 256-byte check) and then `mt_session_create` / `mt_session_set_auth_key` (`ENG/mtproto-ffi/src/lib.rs:598-620, 688-705`).
- **An attacker can force a new key exchange whenever they like.** A 4-byte `-404` transport frame is not authenticated:
  - Rust maps it to `AuthKeyInvalid` (`ENG/mtproto-engine/src/session_runtime.rs:1313-1320`).
  - The Swift glue then drops the temp key and asks for a new one (`RE/RustNetworkSession.swift:522-527`, `825-875`).
  - MtProtoKit's own `MTProto` does the same (`MTK/MTProto.m:1974-1976`, `2093-2165`).

  New keys are also created when a temp key expires (24 h, `MTK/MTContext.m:269`) and for every new DC, media cluster or CDN.

  So an on-path network attacker can reach every pre-authentication bug below on demand, because obfuscated2 is not authenticated. So can the operator of any MTProxy or SOCKS proxy the user configured.

## Findings that are not OK (summary)

| # | Severity | Finding | MtProtoKit location |
|---|---|---|---|
| F1 | **High** | Remote crash (uncaught `NSRangeException`) from a forged `server_DH_params_ok` with a 32-byte `encrypted_answer` | `MTK/MTDatacenterAuthMessageService.m:578-601` (crash at 600) |
| F2 | **High** | `res_pq` with `pq` = 0 or 1: SIGFPE crash on x86_64. With pq = 0, an endless loop on the global MTProto manager queue in arm64 Release builds. No pq bounds at all. | `MTK/MTEncryption.m:538-611` (544-546), caller `MTK/MTDatacenterAuthMessageService.m:436-452` |
| F3 | Medium | No backoff after a failed handshake. Any unauthenticated frame resets the TCP backoff, so failures loop at network speed with attacker-chosen CPU per round. | `MTK/MTDatacenterAuthMessageService.m:154-187`, `MTK/MTTcpConnectionBehaviour.m:49-76`, `MTK/MTProto.m:2009-2021` |
| F4 | Low | auth_key is not left-padded to 256 bytes, so about 1 in 256 handshakes fails and restarts | `MTK/MTDatacenterAuthMessageService.m:698-703`, `MTK/MTEncryption.m:396-420`, `OSSL:154-162` |
| F5 | Low | g_b range is not checked (the docs require it) | `MTK/MTDatacenterAuthMessageService.m:688-698` |
| F6 | Low | `SecRandomCopyBytes` failures are ignored for nonce, new_nonce and b | `MTK/MTDatacenterAuthMessageService.m:227, 477, 689` |
| F7 | Low | Uses the legacy `p_q_inner_data` / `p_q_inner_data_temp` without `dc`, not the documented `_dc` variants | `MTK/MTDatacenterAuthMessageService.m:480-523` |
| F8 | Low | `server_time` is ignored. The initial `server_salt` is computed and then thrown away (salt 0 is stored instead). | `MTK/MTDatacenterAuthMessageService.m:704-711`, `MTK/MTDatacenterAuthAction.m:115,128,164` |
| F9 | Low | Temp keys are never rotated before they expire (expiry is only checked when the keychain loads). No `auth.dropTempAuthKeys`. | `MTK/MTContext.m:480-490`, `MTK/MTProto.m:893-950`, `RE/RustNetworkSession.swift:1278-1297` |
| F10 | Low | The bind's `expires_at` is computed at bind time, not from the key's real expiry | `MTK/MTBindKeyMessageService.m:56` |
| F11 | Low | Bind-failure handling: each retry is a full new DH. `ENCRYPTED_MESSAGE_INVALID` stops retries and the permanent key is not checked. The action can get stuck if the permanent key vanishes. | `MTK/MTDatacenterAuthAction.m:134-176`, `MTK/MTContext.m:1680-1735` |
| F12 | Low | An unauthenticated `-404` during a **media** bind is treated as a successful bind | `MTK/MTProto.m:2107-2116`, `MTK/MTBindKeyMessageService.m:173-175` |
| F13 | Low | CDN RSA: uses our CDN key even when no fingerprint matches and never refreshes stale keys. No modulus-size check, so a small modulus makes the RSA_PAD `while(true)` loop forever. | `MTK/MTDatacenterAuthMessageService.m:423-425, 332-410` |
| F14 | Info | `MTRsaFingerprint` uses a `static` scratch buffer (not thread-safe) | `MTK/MTEncryption.m:833-834` |
| F15 | Info | A parse error dumps up to 128 bytes of decrypted plaintext, including into `MTShortLog` | `MTK/MTProto.m:2047-2051` |

Everything else checked is OK and matches the docs and tdlib. Details for each item follow.

---

## 1. RSA

**Which keys are trusted**
- MtProtoKit hardcodes exactly one production key and one test key (`MTK/MTDatacenterAuthMessageService.m:46-78`). They are byte-identical to tdlib's (`TD/td/telegram/net/PublicRsaKeySharedMain.cpp:14-60`).
- Non-CDN connections always use this list (`MTK/MTDatacenterAuthMessageService.m:180-182`).
- CDN connections use keys from `help.getCdnConfig`, fetched over the authenticated main session (`TelegramCore/Sources/Network/Network.swift:927`, `MTK/MTContext.m:1137-1190`). This is the same trust model as tdlib (`PublicRsaKeySharedCdn.cpp`).

**Fingerprint matching**
- `selectPublicKey` (`MTK/MTDatacenterAuthMessageService.m:80-92`) returns only a locally trusted key whose fingerprint the server listed. The fingerprint is SHA1 of the TL `(n, e)`, lower 64 bits (`MTK/MTEncryption.m:813-844`), the same as `TD/td/mtproto/RSA.cpp:111-123`.
- If no fingerprint matches, the handshake resets (`:427-433`).
- **A key chosen by the server or an attacker can never be used.** The req_DH_params fingerprint is always that of our own key (`:474`).
- **CDN deviation (F13a):** if nothing matches but the server sent exactly one fingerprint and we hold exactly one CDN key, MtProtoKit uses our key anyway (`:423-425`). This is still encryption to a trusted key, so it does not accept an attacker key.
  - tdlib instead fails and calls `drop_keys()` so the CDN keys are fetched again (`TD/td/mtproto/Handshake.cpp:98-102`, `PublicRsaKeySharedCdn.cpp:31-42`).
  - MtProtoKit never refreshes stale CDN keys, which are persisted in the keychain group "ephemeral" (`MTK/MTContext.m:494-497`).
  - Verdict: weaker than tdlib (availability only). Low.

**RSA_PAD** (`MTK/MTDatacenterAuthMessageService.m:314-411`, compared with `TD/td/mtproto/Handshake.cpp:127-155` and the docs)
- data longer than 144 bytes is rejected (`:317`). Random padding brings it to 192 bytes (`:320-328`), and the padded data is byte-reversed (`:330`).
- A fresh 32-byte temp_key is generated on every attempt (`:334-338`).
- `SHA256(temp_key + data_with_padding)` is appended (`:340-349`), then AES-256-IGE with a zero IV (`:351-357`).
- `temp_key XOR SHA256(aes_encrypted)` is computed (`:358-366`) and must give 256 bytes (`:368-373`).
- **The "less than modulus" retry rule is implemented.** If key_aes_encrypted is not below the modulus, the loop starts again with a new temp_key (`:391-395`).
- Raw RSA (`OSSL:323-338`) is used and the result is left-padded to 256 bytes (`:398-407`). This is equivalent to tdlib's `RSA::encrypt` (`TD/td/mtproto/RSA.cpp:130-146`).
- Verdict: **OK**.
- Gap: tdlib refuses keys whose RSA size is not 256 (`RSA.cpp:74-76`) and checks the modulus is 2041 to 2048 bits (`RSA.cpp:133-134`). MtProtoKit has no size check, so a short CDN modulus makes `while (true)` spin almost forever (F13b, Low; only a malicious server can supply CDN keys).

**Inner data** (F7, Low)
- The code uses `0x83c95aec` = `p_q_inner_data` and `0x3c6a84d4` = `p_q_inner_data_temp` (`:487, :508`). These are the legacy constructors without `dc`.
- The comment at `:480-483` names the `_dc` variants, but the code does not use them.
- The docs (core.telegram.org/mtproto/auth_key) and tdlib (`Handshake.cpp:114-125`) use `p_q_inner_data_dc#a9f55f95` / `p_q_inner_data_temp_dc#56fddf88`. Their `dc` field is the DC id, +10000 on test servers and negative for a media DC.
- Without `dc`, the server cannot detect a handshake that was redirected to a different DC than the client intended. There is no confidentiality loss, but this drops a protocol hardening and relies on deprecated constructors.
- `expires_in` = `tempKeyExpiration` = 86400 (`:494`, `MTK/MTContext.m:269`). OK.

## 2. nonce / server_nonce / new_nonce

**Equality checks**
- `res_pq` nonce: `:419`. A mismatch is silently ignored, which is fine.
- `server_DH_params_ok`/`_fail` nonce and server_nonce: `:545`.
- Inner `server_DH_inner_data` nonce and server_nonce: `:625-643`.
- `dh_gen_ok/retry/fail` nonce and server_nonce: `:756`.
- tdlib does the same checks: `Handshake.cpp:92, 171-176, 214-219, 261-266`.
- Verdict: **OK**.

**new_nonce**
- It is 32 bytes from `SecRandomCopyBytes` (`:476-478`). It appears only inside the RSA-encrypted inner data and is never logged. Logs at `:235`, `:265` contain only the public nonce, server_nonce, p and q. It is set to nil (not wiped) on reset (`:160-162`).
- Verdict: **OK**, with F6 below.

**RNG failures (F6, Low)**
- The `SecRandomCopyBytes` return value is thrown away (`__unused`) for nonce (`:227`), new_nonce (`:477`) and b (`:689`). On failure, uninitialized stack bytes would become secrets.
- tdlib aborts if the RNG fails (`TD/tdutils/td/utils/Random.cpp:62-74`; `BigNum::random`: `TD/tdutils/td/utils/BigNum.cpp:244-247`).
- `encryptRSAModernPadding` already checks this correctly (`:324-327, :335-338`).
- This is very unlikely in practice.

## 3. pq factorization (F2 High; part of F3)

**MtProtoKit**
- `pq` is folded into a `uint64_t` with no length check (`MTK/MTDatacenterAuthMessageService.m:436-443`). An empty string gives 0, and more than 8 bytes is silently truncated.
- `MTFactorize` (`MTK/MTEncryption.m:538-611`) then runs:
  - `int q = ((lrand48() & 15) + 17) % what;` (`:544`). This divides by zero when pq = 0.
  - `uint64_t x = (uint64_t)lrand48() % (what - 1) + 1` (`:545`). This divides by zero when pq = 1.
  - `int lim = 1 << (i + 18);` (`:546`). This is undefined behavior once i ≥ 13, and nothing caps it.
  - There is no `pq > 2^63` guard, so `c += a` overflows (`:552-565`).
- The attacker only has to echo the plaintext nonce and list the public production fingerprint. Nothing else is checked before `MTFactorize` runs.

**Verified with standalone copies of the function** (scratchpad `sec/fact.c`; the exact code, compiled with clang):
- **x86_64:** pq = 0 and pq = 1 both end with exit 136 (SIGFPE). The app ships a universal binary with a 10.13 deployment target, so Intel Macs crash.
- **arm64 at -Os and -O2** (SwiftPM Release defaults; `MtProtoKit/Package.swift` sets no optimization flags): pq = 0 never returns. One run burned more than 2 minutes at 100 % CPU before it was killed. At -O0 it returns immediately.
  - The disassembly shows why. Because of `% what`, clang assumes `what != 0`, so it drops the `b != 0` guard in `mygcd`. That leaves `while ((b & 1) == 0) b >>= 1;` spinning on b == 0 (block `LBB0_8`).
  - `MTFactorize` runs on `[MTProto managerQueue]`, one serial queue for the whole process (`MTK/MTProto.m:140-149`). The hang therefore freezes **every** MtProtoKit `MTProto`: all key creation, binding and the MtProtoKit fallback engine. A synchronous `takeConnectionForReusing` (`MTK/MTProto.m:692-699`) would then also block the context queue.
- An adversarial 63-bit prime costs about 0.58 s of CPU per attempt (measured), and the attacker can repeat it (see F3).

**Comparison**
- p < q ordering: MtProtoKit swaps (`MTK/MTEncryption.m:589-596`). OK.
- tdlib `TD/tdutils/td/utils/crypto.cpp:103-139`:
  - returns early for `pq <= 2 || pq > 2^63` (`:104-106`);
  - caps the shift with `min(5, i)` (`:115`);
  - checks `p == 0 || pq % p != 0` (`:243-246`);
  - has a separate bignum path for longer pq (`:231-235`).
- The docs say "Normally, pq is less than or equal to 2^63-1".
- Verdict: **bug, High.** It is a reliable pre-authentication remote crash or hang, repeatable on every launch while a hostile network or proxy is in the path.

## 4. server_DH_params_ok decryption (F1 High)

**Key and IV derivation**
- tmp_aes_key = SHA1(new_nonce + server_nonce) + SHA1(server_nonce + new_nonce)[0:12].
- tmp_aes_iv = SHA1(server_nonce + new_nonce)[12:20] + SHA1(new_nonce + new_nonce) + new_nonce[0:4].
- Implemented at `MTK/MTDatacenterAuthMessageService.m:549-576`. **OK** (same as tdlib `tmp_KDF`, `Handshake.cpp:183`).

**Length check**
- A length that is not a multiple of 16 makes `MyAesIgeDecrypt` fail (`MTK/MTAes.m`), so `MTAesDecrypt` returns nil and the handshake resets (`:578-586`). Equivalent to tdlib `Handshake.cpp:177-179`.

**SHA1 check**
- The first 20 bytes are compared with SHA1 of the remainder, trying 0 to 15 trailing pad bytes (`:587-611`). Semantically this meets the doc rule.

**Bug (F1)**
- The only guard is `answerWithHash.length < 20` (`:579`).
- With a 32-byte `encrypted_answer`, `answerData` is 12 bytes. The loop removes one byte per iteration with `replaceBytesInRange:NSMakeRange(answerData.length - 1, 1)` (`:600`).
- At iteration 12 the length is 0, the range becomes `{NSUIntegerMax, 1}`, and Foundation throws `NSRangeException` ("range {18446744073709551615, 1} causes integer overflow"). Verified in scratchpad `sec/rangetest.m`.
- Nothing on the MTProto queue catches it, so the app aborts.
- **The forgery needs no secret.** An attacker only has to echo the plaintext nonce and server_nonce (both visible in req_DH_params) and send any 32-byte blob. The SHA1 check never gets a chance to reject it.
- tdlib parses the TL, requires pad < 16, and cannot crash (`Handshake.cpp:186-212`).
- Verdict: **bug, High.**

**Parsing and nonces after decryption**
- After the hash, the inner data is parsed and its nonces are checked (`:613-643`). OK.

## 5. DH parameters

**Prime size**
- `MTCheckIsSafePrime` requires `length == 256` and the top bit set, which means 2^2047 ≤ p < 2^2048 (`MTK/MTEncryption.m:637-643`).
- tdlib: `get_num_bits() == 2048` (`TD/td/mtproto/DhHandshake.cpp:24`). **OK.**

**Safe-prime test**
- Known-prime fast path: `goodPrime0` (the standard Telegram prime) is compared with `memcmp` (`MTK/MTEncryption.m:645-671`). There is also a keychain cache of results for any prime (`:631-635`, `:697`).
- Otherwise `BN_is_prime_ex` runs 64 rounds on p and on (p-1)/2 (`:673-695`, `OSSL:165-170`).
- tdlib: `DhHandshake.cpp:65-92` plus the `DhCallback` cache. **OK.**

**g**
- g must be in [2, 7] (`MTK/MTEncryption.m:614-617`, used at `MTK/MTDatacenterAuthMessageService.m:645-654`).
- The per-g residue rules are p mod 8 = 7 (g=2), p mod 3 = 2 (g=3), none (g=4), p mod 5 ∈ {1,4} (g=5), p mod 24 ∈ {19,23} (g=6), p mod 7 ∈ {3,5,6} (g=7). They are implemented at `MTK/MTEncryption.m:741-799`, cached per (prime, g).
- These match the security guidelines and `DhHandshake.cpp:37-63`. **OK.**

**g_a**
- Checked for 1 < g_a < p-1 and 2^(2048-64) < g_a < p - 2^(2048-64) (`MTK/MTEncryption.m:700-739`, called at `MTK/MTDatacenterAuthMessageService.m:656-666`). **OK.**

**g_b (F5, Low)**
- g_b is never checked (`:696`). `MTCheckIsSafeB` exists (`MTK/MTEncryption.m:501-514`) but is unused.
- The docs say: "both sides are to check that g, g_a and g_b are greater than 1 and less than dh_prime - 1".
- tdlib checks g_a **and** g_b against 2^(2048-64) bounds (`DhHandshake.cpp:95-126`, via `run_checks` `:183-195`).
- With a working RNG the chance of a bad g_b is negligible. The check matters mostly as a guard against RNG failure (F6). Verdict: missing check.

**b**
- 256 random bytes (2048 bits) (`:688-690`). tdlib: `BigNum::random(b_, 2048, -1, 0)` (`DhHandshake.cpp:136`).
- Modular exponentiation uses `BN_FLG_CONSTTIME` (`MTK/MTEncryption.m:396-420`). OK, except F6.

**auth_key padding (F4, Low)**
- `MTExp` returns `BN_bn2bin` output at its minimal length (`OSSL:154-162`). The auth_key at `:698` is therefore 255 bytes or shorter in about 1 in 256 handshakes.
- `auth_key_id` and `auth_key_aux_hash` are then computed over the short key and never match the server, so `dh_gen_ok` fails the hash1 check and the handshake restarts. The server is left holding a key that is never used.
- tdlib: `get_g_ab().to_binary(2048 / 8)` (`DhHandshake.cpp:219-223`). Not exploitable; a correctness bug.

**server_time (F8, Low)**
- `server_DH_inner_data.server_time` is parsed (`MTK/MTInternalMessageParser.m:136-142`) but never used. No time difference is set from the handshake.
- The docs say: "store the difference between server_time ... and its local time". tdlib does this (`Handshake.cpp:221`, `248`; `TD/td/telegram/net/Session.cpp:1425-1427`).
- MtProtoKit only corrects its clock later, from `bad_msg_notification` and pong time-sync, through authenticated channels. Using the handshake time for msg_id is also unauthenticated, so this is weaker but not a security hole.

## 6. new_nonce_hash1/2/3, auth_key_aux_hash, server_salt

**Hashes**
- `auth_key_aux_hash` = SHA1(auth_key)[0:8] (`:758-759`).
- `new_nonce_hashN` = SHA1(new_nonce + N + aux)[4:20] for N = 1, 2, 3 (`:761-783`).
- hash1 is checked for `dh_gen_ok` (`:785-805`), hash2 for retry (`:806-822`) and hash3 for fail (`:823-839`).
- `auth_key_id` = the low 64 bits of SHA1(auth_key) (`:700-703`).
- tdlib checks only hash1 and errors on retry and fail (`Handshake.cpp:268-280`). **OK.**

**dh_gen_retry**
- MtProtoKit restarts the whole exchange instead of sending a second `set_client_DH_params` with `retry_id` = aux_hash. `retry_id` is always 0 (`:720`). tdlib also gives up. Acceptable.

**server_salt (F8, Low)**
- `server_salt` = new_nonce[0:8] XOR server_nonce[0:8] is computed (`:704-711`) and **discarded**.
- The stored salt set is `salt:0` with a validity window starting at the **unauthenticated** msg_id of `dh_gen_ok` (`MTK/MTDatacenterAuthAction.m:104-105, 115, 128, 164`).
- tdlib stores it (`Handshake.cpp:250`, `Session.cpp:1420-1424`).
- Effect: every new key's first message gets `bad_server_salt` and costs an extra round trip. Functional, Low.

## 7. Temp keys (PFS) and auth.bindTempAuthKey

**Message format** (`MTK/MTBindKeyMessageService.m:47-100`, compared with the docs and `TD/td/mtproto/SessionConnection.cpp:856-879`)
- `bind_auth_key_inner#75a3f765` contains:
  - a 64-bit random nonce (`arc4random_buf`, which is ChaCha20-based on Apple platforms);
  - the temp key id and the permanent key id;
  - `temp_session_id` = the session id of the connection that sends the request;
  - `expires_at` (`:64-71`).
- It is encrypted with MTProto v1 under the **permanent** key (`MTK/MTProto.m:1610-1649`):
  - a random 128-bit value in place of salt and session_id (`:1613-1621`);
  - the same msg_id as the outer request (`MTK/MTBindKeyMessageService.m:53, 73, 89`; `MTK/MTProto.m:1089-1098` keeps an explicit id);
  - seq_no 0, and msg_key = SHA1 low 128 bits over the unpadded data (`:1626-1631`).
- The request is sent with the **temp** key on the temp session (`MTK/MTDatacenterAuthAction.m:136-141`, `useExplicitAuthKey`).
- Success requires `rpc_result{boolTrue}` for that msg_id, which arrives encrypted under the temp key (`MTK/MTBindKeyMessageService.m:143-170`).
- Verdict: **OK.**

**expires_at (F10, Low)**
- Computed as `globalTime + tempKeyExpiration` **at bind time** (`:56`). It can therefore be later than the server's real expiry, which is handshake time + expires_in, by up to the bind-retry backoff.
- tdlib uses the key's own `expires_at` (`TD/td/telegram/net/Session.cpp:1373`).

**Rebinding on expiry (F9, Low)**
- `validUntilTimestamp` is local time at handshake + 24 h (`MTK/MTDatacenterAuthMessageService.m:713`). It is enforced **only** when the keychain is loaded (`MTK/MTContext.m:480-490`).
- `MTProto` (`MTK/MTProto.m:893-950`) never checks it, and the Rust glue does not pass it to the engine (`RE/RustNetworkSession.swift:1278-1297`).
- In a long-running session the key is used until the server rejects it (-404 / `AUTH_KEY_PERM_EMPTY`), and only then does a new DH + bind run. That means a periodic stall every 24 h.
- tdlib regenerates the key 1 h (or 2 min) **before** expiry (`TD/td/mtproto/AuthData.h:101-111`, `Session.cpp:1486-1495`).
- tdlib also tells the server to delete superseded temp keys with `auth.dropTempAuthKeys` (`TD/td/telegram/net/TempAuthKeyWatchdog.h:128-129`). MtProtoKit never calls it (grep finds no use in MtProtoKit or TelegramCore).

**If binding fails (F11, Low)**
- A bind failure (boolFalse, any RPC error) fails the action. The temp key is **discarded**, and the context retries after 1, 2, 4 … 60 s (`MTK/MTContext.m:225-230, 1680-1735`) with a **new full DH**.
- tdlib keeps the temp key and only re-sends the bind (`Session.cpp:383-441`).
- On `ENCRYPTED_MESSAGE_INVALID` (`MTK/MTDatacenterAuthAction.m:40-42`), MtProtoKit stops retrying until connections resume (`MTK/MTContext.m:1700-1708`) and never checks the permanent key.
- tdlib validates the main key and logs out if it is gone, with a safe "immunity" window (`Session.cpp:391-421`).
- If the permanent key disappears while the temp handshake is running, `MTDatacenterAuthAction.m:134-176` neither completes nor fails. The action stays registered and blocks new actions for that selector (`MTK/MTContext.m:1563`) until a permanent key is stored again.

**A forged -404 marks a media bind as done (F12, Low)**
- When a 4-byte `-404` (unauthenticated) arrives on an explicit-key **media** bind connection, `handleMissingKey` calls `complete` on the bind service (`MTK/MTProto.m:2107-2116` → `MTK/MTBindKeyMessageService.m:173-175`). `MTDatacenterAuthAction` then stores the temp key as bound (`MTK/MTDatacenterAuthAction.m:163-168`).
- The key is a genuine DH key with the server, so there is no confidentiality impact. But requests on it are rejected with `AUTH_KEY_PERM_EMPTY`, which triggers another drop and regenerate. An attacker can use this as a loop trigger.
- tdlib has no equivalent.

**msg_id rules**
- The bind uses `generateClientMessageId` (server-time-based, monotonic) with `takeSeqNo:true`, and the inner msg_id equals the outer one. **OK.**

## 8. Key storage and handoff to Rust

**At rest and in memory**
- Keys live in `NSData` inside `MTDatacenterAuthInfo` and are persisted with NSKeyedArchiver into the Postbox keychain table, inside the SQLCipher-encrypted account database (`TelegramCore/Sources/Account/Account.swift:11-52`, `TelegramCore/Sources/Network/Network.swift:1375-1395`). They are never wiped in memory.
- tdlib likewise keeps keys in its (encrypted) database and does not wipe them in general. Info.

**Logging**
- Only key ids are logged (`MTK/MTDatacenterAuthAction.m:110`, `MTK/MTBindKeyMessageService.m:86`).
- `MTDatacenterAuthInfo.description` prints only the key length (`MTK/MTDatacenterAuthInfo.m:134-136`).
- new_nonce, b and tmp_aes are never logged.
- Exception: on a parse error, `dumpHexString` logs up to 128 bytes of **decrypted** plaintext into both `MTLog` and `MTShortLog` (`MTK/MTProto.m:2047-2051`). On the bind connection that is temp-key plaintext (salt, session, msg_id and the start of the payload). It is not key material (F15, Info).

**FFI**
- `makeKeyMaterial` requires exactly 256 bytes (`RE/RustNetworkSession.swift:1278-1280`).
- The copy is made in `RustEngineArena`, kept alive with `withExtendedLifetime` during the call (`RE/RustNetworkSession.swift:201-205, 890-892`), and wiped with `memset` when the arena is deinitialized (`RE/RustEngineArena.swift:10-15`).
- Rust copies the bytes, wipes its temporary copy (`ENG/mtproto-ffi/src/lib.rs:617-620, 699-702`) and wipes `AuthKey` on drop (`ENG/mtproto-core/src/auth_key.rs:43-47`).
- The pointer and length are passed by value. Ownership is clear, and there are no lifetime problems.
- Verdict: **OK.**

## 9. Error handling and retry loops

- Every check failure calls `reset:` (`MTK/MTDatacenterAuthMessageService.m:432, 449, 583, 608, 620, 630, 640, 651, 663, 673, 683, 748, 792, 813, 820, 830, 837, 845, 853`). `reset:` makes a fresh nonce, closes the TCP connection (`requestSecureTransportReset`) and immediately asks for a new transaction (`:154-187`).
- tdlib also clears the handshake on any error (`Handshake.cpp:340-343`). The difference is in rate limiting.

**No backoff (F3, Medium)**
- A handshake failure never reaches MTContext's 1-60 s retry backoff, which is only reached by bind outcomes.
- The transport backoff is reset to 0 by `connectionValidDataReceived` (`MTK/MTTcpConnectionBehaviour.m:49-52`). That fires on `decodeResult(success)`, which in unauthorized mode means **any** frame that is not a 4-byte error (`MTK/MTProto.m:2009, 2021`; `MTK/MTTcpTransport.m:466-491`).
- The first reconnect after a close is immediate (`MTK/MTTcpConnectionBehaviour.m:58-63`).
- So a hostile server or man in the middle (MITM) can keep the client in a connect → req_pq → bad answer → reconnect loop at network round-trip speed. The attacker can also pick how much CPU each round costs:
  - about 0.6 s for a 63-bit prime pq (F2);
  - one PEM parse + SHA1 per (server fingerprint × key) pair, because `selectPublicKey` recomputes the fingerprint inside the double loop (`:80-92`);
  - for pq longer than 8 bytes, the inner data exceeds 144 bytes, `encryptRSAModernPadding` returns nil, and the stage goes back to PQ. req_pq is then re-sent with the **same** nonce on the same connection with no reset at all (`:317-319, 525-530`).
- tdlib rate-limits new connections per DC with `FloodControlStrict` (`TD/td/telegram/net/ConnectionCreator.cpp:102-115, 997-1006`).
- This is a CPU, battery and network amplification. A network attacker can already block the connection, which is why this is Medium and not High.

**Pointless reset on server_DH_params_fail**
- `server_DH_params_fail` triggers a reset without checking its `new_nonce_hash` (`:743-749`). tdlib no longer has that constructor and also fails. Equal.

**F1 and F2 are the dangerous error paths.** They crash or hang instead of failing.

## Verification artifacts (scratchpad only)

- `sec/rangetest.m`: the exact strip loop on a 12-byte `NSMutableData` aborts with `NSRangeException ... range {18446744073709551615, 1} causes integer overflow`.
- `sec/fact.c`: a verbatim copy of `MTFactorize`/`mygcd`.
  - x86_64 (-O2 and -Os): pq = 0 and pq = 1 exit with 136 (SIGFPE).
  - arm64 -O2 and -Os: pq = 0 never returns (killed after 8 s; one earlier run after more than 2 min). -O0 returns at once.
  - The -Os assembly shows `LBB0_8: lsr x15,x15,#1; tbz w16,#0,LBB0_8` entered with x15 = what = 0.
  - A 63-bit prime pq takes 0.58 s; the real pq `0x17ED48941A08F981` takes 0.02 s.

## Suggested fixes (for whoever acts on this; nothing was changed)

1. **F1:** stop stripping when `answerData.length == 0`. Better, do what tdlib does: parse `server_DH_inner_data` from offset 20, require pad < 16, then SHA1 the parsed span.
2. **F2:** reject `pq.length == 0 || > 8`, `pq <= 3` and `pq > 2^63` before factorizing. Cap the shift with `min(i, 5)`. Verify `p * q == pq`.
3. **F3:** count handshake failures per DC and feed them into `MTRetryDelayForFailureCount`. Do not count an unauthorized frame as "valid data" for backoff until `dh_gen_ok`. Precompute key fingerprints once.
4. **F4:** left-pad `g_ab` (and g_b) to 256 bytes.
5. **F5:** check g_b with the same bounds as g_a.
6. **F6:** fail the handshake when `SecRandomCopyBytes` fails.
7. **F7:** switch to `p_q_inner_data_dc` / `_temp_dc` with the correct dc (negative for media, +10000 on test).
8. **F8:** store the computed salt and `server_time - now`.
9. **F9–F11:** rotate the temp key ahead of expiry; tie `expires_at` to the handshake; keep the temp key across bind retries; validate the permanent key on `ENCRYPTED_MESSAGE_INVALID`.
10. **F12:** drop the "-404 means bind success" special case, or make it not mark the key as bound.
11. **F13:** require a 2048-bit modulus for CDN keys, refetch CDN keys when no fingerprint matches, and bound the RSA_PAD loop.

The unused Rust handshake in `ENG/mtproto-core/src/handshake.rs` was not part of this audit.
