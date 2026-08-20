#!/usr/bin/env python3
"""Run cibuildwheel against YamabikoChat's exact embedded iOS runtime."""

from __future__ import annotations

import os
from pathlib import Path

import cibuildwheel.platforms.ios as ios


def _required_path(name: str) -> Path:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    path = Path(value).resolve()
    if not path.exists():
        raise SystemExit(f"Configured path does not exist: {path}")
    return path


build_python = _required_path("YAMABIKO_BUILD_PYTHON")
target_root = _required_path("YAMABIKO_TARGET_ROOT")

# cibuildwheel normally installs another system-wide build Python and downloads
# its own target runtime. Wheels for the app must instead be built against the
# exact Python.xcframework that the app embeds. The build Python remains a
# native CPython 3.14 virtual environment; only those two locations are bound.
ios.install_build_cpython = lambda _tmp, _version, _url, _free_threading: build_python
ios.install_target_cpython = lambda _tmp, _config, _free_threading: target_root

from cibuildwheel.__main__ import main  # noqa: E402


main()
