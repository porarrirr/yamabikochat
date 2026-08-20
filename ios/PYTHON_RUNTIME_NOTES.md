# Embedded Python release note

YamabikoChat embeds CPython and interprets code supplied by the user or generated
inside an existing chat tool call. It does not download executable code or add a
second AI/provider execution path. Python execution remains inside the standard
`LocalToolRegistry` and Pi Agents tool-result flow.

The runtime audit hook, workspace boundary, timeout, and memory watchdog are
accident-containment controls, not an attacker-resistant sandbox. CPython C
extensions can retain process-global state and may require an app restart if a
native call does not return after interruption.

Scientific binary wheels must be CPython 3.14 iOS wheels for every supported
device/simulator slice. `bootstrap-python.sh` intentionally rejects missing or
platform-substituted numpy, pandas, and matplotlib wheels. Every wheel must also
have an audited SHA-256 entry in `python-wheels.sha256`; unpinned files are not
bundled.
