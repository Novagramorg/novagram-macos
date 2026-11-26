#!/usr/bin/env python3
import ctypes
import json
import os
import random
import resource
import sys
import tempfile
import time

TDJSON = os.environ.get("TDJSON", "libtdjson.dylib")
API_ID = int(os.environ.get("TDLIB_API_ID", "94575"))
API_HASH = os.environ.get("TDLIB_API_HASH", "a3406de8d171bb422bb6ddf3bbd800e2")


class Client:
    def __init__(self, database, proxy, test_dc):
        self.lib = ctypes.CDLL(TDJSON)
        self.lib.td_create_client_id.restype = ctypes.c_int
        self.lib.td_send.argtypes = [ctypes.c_int, ctypes.c_char_p]
        self.lib.td_receive.argtypes = [ctypes.c_double]
        self.lib.td_receive.restype = ctypes.c_char_p
        self.lib.td_execute.argtypes = [ctypes.c_char_p]
        self.lib.td_execute.restype = ctypes.c_char_p
        self.lib.td_execute(json.dumps({"@type": "setLogVerbosityLevel", "new_verbosity_level": 1}).encode())
        self.client = self.lib.td_create_client_id()
        self.database = database
        self.proxy = proxy
        self.test_dc = test_dc
        self.pending = {}
        self.extra = 0
        self.updates = []
        self.ready = False
        self.connection_state = None
        self.state_log = []

    def send(self, query):
        self.extra += 1
        query = dict(query)
        query["@extra"] = str(self.extra)
        self.lib.td_send(self.client, json.dumps(query).encode())
        return str(self.extra)

    def receive(self, timeout):
        raw = self.lib.td_receive(timeout)
        if not raw:
            return None
        event = json.loads(raw.decode())
        kind = event.get("@type")
        if kind == "updateConnectionState":
            self.connection_state = event["state"]["@type"]
            self.state_log.append((time.time(), self.connection_state))
        if kind == "updateAuthorizationState":
            self.authorization = event["authorization_state"]["@type"]
            self.authorization_event = event["authorization_state"]
            print(f"authorization: {self.authorization}", file=sys.stderr, flush=True)
        if kind == "error":
            print(f"error: {event}", file=sys.stderr, flush=True)
        if "@extra" in event:
            self.pending[event["@extra"]] = event
        else:
            self.updates.append(event)
            if len(self.updates) > 20000:
                self.updates = self.updates[-10000:]
        return event

    def call(self, query, timeout=300):
        extra = self.send(query)
        deadline = time.time() + timeout
        while time.time() < deadline:
            if extra in self.pending:
                return self.pending.pop(extra)
            self.receive(0.5)
        return {"@type": "error", "message": "timeout"}

    def wait(self, predicate, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            event = self.receive(0.5)
            if event is not None and predicate(event):
                return event
        return None

    def authorize(self, phone):
        self.authorization = None
        self.send({"@type": "getAuthorizationState"})
        while True:
            self.receive(1.0)
            state = getattr(self, "authorization", None)
            if state == "authorizationStateWaitTdlibParameters":
                self.send({
                    "@type": "setTdlibParameters",
                    "use_test_dc": self.test_dc,
                    "database_directory": self.database,
                    "files_directory": os.path.join(self.database, "files"),
                    "use_file_database": True,
                    "use_chat_info_database": True,
                    "use_message_database": True,
                    "api_id": API_ID,
                    "api_hash": API_HASH,
                    "system_language_code": "en",
                    "device_model": "NetworkLab",
                    "application_version": "1.0",
                })
                self.authorization = "sent-parameters"
            elif state == "authorizationStateWaitPhoneNumber":
                if self.proxy:
                    self.add_proxy()
                self.send({"@type": "setAuthenticationPhoneNumber", "phone_number": phone})
                self.authorization = "sent-phone"
            elif state == "authorizationStateWaitCode":
                code = os.environ.get("TDLIB_CODE")
                code_file = os.environ.get("TDLIB_CODE_FILE")
                if not code and code_file:
                    deadline = time.time() + 300
                    while time.time() < deadline and not os.path.exists(code_file):
                        self.receive(1.0)
                    code = open(code_file).read().strip() if os.path.exists(code_file) else ""
                if not code:
                    length = self.authorization_event.get("code_info", {}).get("type", {}).get("length", 5)
                    print(f"code info: {self.authorization_event.get('code_info')}", file=sys.stderr, flush=True)
                    code = phone[5] * length if phone.startswith("99966") else input("code: ")
                self.send({"@type": "checkAuthenticationCode", "code": code})
                self.authorization = "sent-code"
            elif state == "authorizationStateWaitRegistration":
                self.send({"@type": "registerUser", "first_name": "NetworkLab", "last_name": ""})
                self.authorization = "sent-registration"
            elif state == "authorizationStateReady":
                if self.proxy:
                    self.add_proxy()
                return
            elif state in ("authorizationStateClosed", "authorizationStateLoggingOut"):
                raise SystemExit(f"authorization failed: {state}")

    def add_proxy(self):
        host, port = self.proxy.split(":")
        self.call({"@type": "addProxy", "server": host, "port": int(port), "enable": True,
                   "type": {"@type": "proxyTypeSocks5", "username": "", "password": ""}}, timeout=30)

    def close(self):
        self.send({"@type": "close"})
        self.wait(lambda event: event.get("@type") == "updateAuthorizationState"
                  and event["authorization_state"]["@type"] == "authorizationStateClosed", 60)


def percentile(samples, value):
    if not samples:
        return 0.0
    ordered = sorted(samples)
    return ordered[min(len(ordered) - 1, int(round((len(ordered) - 1) * value)))] * 1000.0


def latency_metrics(samples, failures, prefix):
    return {f"{prefix}_requests": len(samples), f"{prefix}_failures": failures,
            f"{prefix}_p50_ms": percentile(samples, 0.5), f"{prefix}_p95_ms": percentile(samples, 0.95),
            f"{prefix}_max_ms": percentile(samples, 1.0)}


def timed(client, query, samples, failures, timeout=120):
    started = time.time()
    result = client.call(query, timeout)
    if result.get("@type") == "error":
        failures.append(result.get("message"))
        return None
    samples.append(time.time() - started)
    return result


def scenario_chatlist(client, options):
    samples, failures = [], []
    for _ in range(3):
        timed(client, {"@type": "getChats", "chat_list": {"@type": "chatListMain"}, "limit": 100}, samples, failures)
        timed(client, {"@type": "loadChats", "chat_list": {"@type": "chatListArchive"}, "limit": 100}, samples, failures)
    return latency_metrics(samples, len(failures), "dialogs")


def heavy_chats(client, count):
    chats = client.call({"@type": "getChats", "chat_list": {"@type": "chatListMain"}, "limit": 100})
    return chats.get("chat_ids", [])[:count]


def scenario_history(client, options):
    samples, failures = [], []
    messages = 0
    media = []
    for chat_id in heavy_chats(client, options["peers"]):
        offset = 0
        for _ in range(options["pages"]):
            result = timed(client, {"@type": "getChatHistory", "chat_id": chat_id, "from_message_id": offset,
                                    "offset": 0, "limit": 100, "only_local": False}, samples, failures)
            if not result or not result.get("messages"):
                break
            batch = result["messages"]
            messages += len(batch)
            offset = batch[-1]["id"]
            for message in batch:
                content = message.get("content", {})
                kind = content.get("@type")
                file = None
                if kind == "messagePhoto":
                    sizes = content["photo"]["sizes"]
                    file = sizes[-1]["photo"] if sizes else None
                elif kind in ("messageDocument", "messageVideo", "messageAudio"):
                    key = {"messageDocument": "document", "messageVideo": "video", "messageAudio": "audio"}[kind]
                    file = content[key].get(key) or content[key].get("document") or content[key].get("video")
                if file and 50_000 < (file.get("size") or file.get("expected_size") or 0) < 25_000_000:
                    media.append(file["id"])
    options["media_ids"] = media
    metrics = latency_metrics(samples, len(failures), "history")
    metrics["messages"] = messages
    return metrics


def scenario_media(client, options):
    ids = options.get("media_ids") or []
    ids = ids[: options["media_count"]]
    samples, failures = [], []
    total = 0
    started = time.time()
    for file_id in ids:
        client.call({"@type": "deleteFile", "file_id": file_id}, timeout=30)
    for file_id in ids:
        result = timed(client, {"@type": "downloadFile", "file_id": file_id, "priority": 1, "offset": 0, "limit": 0,
                                "synchronous": True}, samples, failures, timeout=options["media_timeout"])
        if result and result.get("local", {}).get("is_downloading_completed"):
            total += result.get("size") or result["local"].get("downloaded_size", 0)
    elapsed = time.time() - started
    for file_id in ids:
        client.call({"@type": "deleteFile", "file_id": file_id}, timeout=30)
    metrics = latency_metrics(samples, len(failures), "file")
    metrics.update({"files": len(ids), "megabytes": total / 1048576.0,
                    "throughput_mbit": total * 8 / elapsed / 1e6 if elapsed > 0 else 0})
    return metrics


def scenario_upload(client, options):
    me = client.call({"@type": "getMe"})
    chat = client.call({"@type": "createPrivateChat", "user_id": me["id"], "force": False})
    sizes = options["upload_sizes"]
    marker = f"network-lab-tdlib-{int(time.time())}"
    directory = tempfile.mkdtemp()
    total = 0
    pending = set()
    sent = []
    started = time.time()
    for index, megabytes in enumerate(sizes):
        path = os.path.join(directory, f"{marker}-{index}.bin")
        with open(path, "wb") as handle:
            handle.write(os.urandom(megabytes * 1048576))
        total += megabytes * 1048576
        result = client.call({"@type": "sendMessage", "chat_id": chat["id"], "input_message_content": {
            "@type": "inputMessageDocument", "document": {"@type": "inputFileLocal", "path": path},
            "caption": {"@type": "formattedText", "text": f"{marker} {index}"}}})
        if result.get("@type") == "message":
            pending.add(result["id"])
    deadline = time.time() + options["upload_timeout"]
    while pending and time.time() < deadline:
        event = client.receive(0.5)
        if event and event.get("@type") == "updateMessageSendSucceeded" and event["old_message_id"] in pending:
            pending.discard(event["old_message_id"])
            sent.append(event["message"]["id"])
        if event and event.get("@type") == "updateMessageSendFailed" and event["old_message_id"] in pending:
            pending.discard(event["old_message_id"])
    elapsed = time.time() - started
    file_ids = []
    for message_id in sent:
        message = client.call({"@type": "getMessage", "chat_id": chat["id"], "message_id": message_id})
        document = message.get("content", {}).get("document", {}).get("document")
        if document:
            file_ids.append(document["id"])
    for file_id in file_ids:
        client.call({"@type": "deleteFile", "file_id": file_id}, timeout=30)
    download_started = time.time()
    downloaded = 0
    for file_id in file_ids:
        client.send({"@type": "downloadFile", "file_id": file_id, "priority": 1, "offset": 0, "limit": 0, "synchronous": False})
    remaining = set(file_ids)
    deadline = time.time() + options["upload_timeout"]
    while remaining and time.time() < deadline:
        event = client.receive(0.5)
        if event and event.get("@type") == "updateFile" and event["file"]["id"] in remaining \
                and event["file"]["local"]["is_downloading_completed"]:
            remaining.discard(event["file"]["id"])
            downloaded += event["file"]["size"]
    download_elapsed = time.time() - download_started
    if sent:
        client.call({"@type": "deleteMessages", "chat_id": chat["id"], "message_ids": sent, "revoke": True})
    return {"files": len(sizes), "uploaded": len(sent), "megabytes": total / 1048576.0,
            "throughput_mbit": total * 8 / elapsed / 1e6 if len(sent) == len(sizes) and elapsed > 0 else 0,
            "download_s": download_elapsed if not remaining else -1,
            "download_mbit": downloaded * 8 / download_elapsed / 1e6 if download_elapsed > 0 else 0}


def scenario_catchup(client, options):
    client.close()
    time.sleep(options["offline_seconds"])
    reopened = Client(client.database, client.proxy, client.test_dc)
    started = time.time()
    reopened.authorize(options["phone"])
    reopened.wait(lambda event: event.get("@type") == "updateConnectionState"
                  and event["state"]["@type"] == "connectionStateReady", options["catchup_timeout"])
    options["client"] = reopened
    return {"catchup_s": time.time() - started}


def main():
    arguments = dict(zip(sys.argv[1::2], sys.argv[2::2]))
    phone = arguments["--phone"]
    label = arguments.get("--label", "tdlib")
    proxy = arguments.get("--proxy")
    scenarios = arguments.get("--scenarios", "chatlist,history,media,upload,catchup").split(",")
    database = arguments.get("--database", os.path.expanduser("~/.networklab-tdlib"))
    options = {
        "phone": phone,
        "peers": int(arguments.get("--peers", "12")),
        "pages": int(arguments.get("--pages", "6")),
        "media_count": int(arguments.get("--media-count", "40")),
        "media_timeout": float(arguments.get("--media-timeout", "180")),
        "upload_sizes": [int(value) for value in arguments.get("--upload-sizes", "1,1,1,8").split(",")],
        "upload_timeout": float(arguments.get("--upload-timeout", "600")),
        "offline_seconds": float(arguments.get("--offline-seconds", "60")),
        "catchup_timeout": float(arguments.get("--catchup-timeout", "600")),
    }
    os.makedirs(database, exist_ok=True)
    client = Client(database, proxy, arguments.get("--test-dc", "1") == "1")
    client.authorize(phone)
    client.wait(lambda event: event.get("@type") == "updateConnectionState"
                and event["state"]["@type"] == "connectionStateReady", 120)
    results = []
    for scenario in scenarios:
        before = resource.getrusage(resource.RUSAGE_SELF)
        started = time.time()
        metrics = globals()[f"scenario_{scenario}"](client, options)
        client = options.pop("client", client)
        after = resource.getrusage(resource.RUSAGE_SELF)
        metrics["wall_s"] = time.time() - started
        metrics["cpu_s"] = (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime)
        metrics["max_rss_mb"] = after.ru_maxrss / 1048576.0
        results.append({"scenario": scenario, "engine": "tdlib", "metrics": metrics})
        print(json.dumps(results[-1]), flush=True)
        time.sleep(3)
    out = arguments.get("--out")
    if out:
        with open(out, "w") as handle:
            json.dump({"label": label, "results": results}, handle, indent=1)
    client.close()


if __name__ == "__main__":
    main()
