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
platform-substituted NumPy, Matplotlib, Pillow, contourpy, and kiwisolver wheels.
Downloaded wheels and sources are pinned by SHA-256. Locally cross-built wheels
are accepted only when their generated checksum lock matches every expected iOS
slice; unpinned files are not bundled.

Matplotlib also bundles pinned OFL-licensed Noto Regular fonts for Japanese,
Simplified Chinese, Devanagari, Arabic, Urdu Nastaliq, Bengali, Latin, and
Cyrillic. The build verifies `Python/Resources/Fonts/SHA256SUMS` before copying
the fonts into Matplotlib's own font directory. The runtime configures the font
families as a direct fallback chain so mixed-script labels resolve per glyph.
