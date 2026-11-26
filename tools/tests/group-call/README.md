# Group call regression checks

Run from the repository root:

```sh
python3 tools/tests/group-call/run.py
python3 tools/tests/group-call/run.py --baseline
```

The runner extracts the production methods and initial-output application block
from `PresentationGroupCall.swift`, compiles them in a temporary Swift package,
and uses the repository's SwiftSignalKit implementation. Media contexts, device
permissions, and server requests are simulated so callback ordering and
cancellation can be controlled without joining a real call.

The tests cover independent main-call and screen-share requests, screen-share
teardown and failures, duplicate starts, reconnects preserving disabled media,
moderator mute transitions, delayed permission callbacks, push-to-talk, call
termination, and video-request deduplication and suspension.

`--baseline` reads production code from `HEAD`. The original implementation has
no participant mute reconciliation helper, so that entry point is a no-op in
the baseline harness. Ten of the thirteen cases fail against that baseline;
all thirteen pass with the fixes.

These checks do not exercise the full call state machine, Telegram servers,
WebRTC, device capture, or the call UI. Live validation should include reconnecting
after muting and disabling camera/screen sharing, rapid screen-share stop/start,
moderator mute/unmute, push-to-talk, and leaving during connection setup.
