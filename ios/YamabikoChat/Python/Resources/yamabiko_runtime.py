"""Stateful execution harness for YamabikoChat's embedded CPython.

The audit policy reduces accidental damage from LLM-generated code. CPython is
still in the app process, so this must not be described as an attacker-resistant
sandbox.
"""

from __future__ import annotations

import ast
import builtins
import io
import json
import mimetypes
import os
from pathlib import Path
import random
import sys
import time
import traceback
from typing import Any


_MAX_STREAM_CHARS = 64 * 1024
_TRUNCATION_MARKER = "\n...truncated...\n"
_sessions: dict[str, dict[str, Any]] = {}
_baseline_modules = frozenset(sys.modules)
_active_workspace: Path | None = None
_active_outputs: Path | None = None
_active_read_roots: tuple[Path, ...] = ()

# Initialize only the built-in MIME table before the audit policy is active;
# desktop Python otherwise probes /etc/apache2/mime.types on first artifact.
mimetypes.init(files=[])


class _BoundedTextIO(io.TextIOBase):
    def __init__(self, limit: int = _MAX_STREAM_CHARS) -> None:
        self.limit = limit
        self._chunks: list[str] = []
        self._length = 0

    @property
    def encoding(self) -> str:
        return "utf-8"

    def writable(self) -> bool:
        return True

    def write(self, value: str) -> int:
        text = str(value)
        self._chunks.append(text)
        self._length += len(text)
        if self._length > self.limit * 2:
            joined = "".join(self._chunks)
            edge = max(1, (self.limit - len(_TRUNCATION_MARKER)) // 2)
            self._chunks = [joined[:edge], _TRUNCATION_MARKER, joined[-edge:]]
            self._length = sum(map(len, self._chunks))
        return len(text)

    def getvalue(self) -> str:
        value = "".join(self._chunks)
        if len(value) <= self.limit:
            return value
        edge = max(1, (self.limit - len(_TRUNCATION_MARKER)) // 2)
        return value[:edge] + _TRUNCATION_MARKER + value[-edge:]


def _resolved(path: os.PathLike[str] | str, *, base: Path | None = None) -> Path:
    candidate = Path(os.fsdecode(path))
    if not candidate.is_absolute():
        candidate = (base or Path.cwd()) / candidate
    return candidate.resolve(strict=False)


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _validate_path(value: object, *, writing: bool) -> None:
    if _active_workspace is None or isinstance(value, int):
        return
    if not isinstance(value, (str, bytes, os.PathLike)):
        return
    path = _resolved(value, base=_active_workspace)
    roots = (_active_workspace, _active_outputs) if writing else (_active_workspace, _active_outputs, *_active_read_roots)
    roots = tuple(root for root in roots if root is not None)
    if not any(_is_within(path, root) for root in roots):
        mode = "write" if writing else "read"
        raise PermissionError(f"Python {mode} access is restricted to the session workspace: {path}")


def _audit_hook(event: str, args: tuple[object, ...]) -> None:
    if _active_workspace is None:
        return
    if event.startswith("socket.") or event.startswith("subprocess"):
        raise PermissionError("Network and subprocess APIs are disabled for python_execute")
    if event in {
        "ctypes.dlopen", "os.system", "os.fork", "os.forkpty", "os.posix_spawn",
        "os.posix_spawnp", "os.exec", "os.spawn",
    } or event.startswith("os.exec") or event.startswith("os.spawn"):
        raise PermissionError(f"Dangerous API is disabled for python_execute: {event}")
    if event == "open" and args:
        mode = args[1] if len(args) > 1 else "r"
        flags = args[2] if len(args) > 2 else 0
        writing = isinstance(mode, str) and any(flag in mode for flag in "wax+")
        writing = writing or isinstance(flags, int) and bool(flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC))
        _validate_path(args[0], writing=writing)
    elif event in {"os.remove", "os.rmdir", "os.mkdir", "os.chmod", "os.chown", "os.truncate", "os.utime"}:
        if args:
            _validate_path(args[0], writing=True)
    elif event in {"os.rename", "os.link", "os.symlink"}:
        for value in args[:2]:
            _validate_path(value, writing=True)
    elif event in {"os.chdir", "os.listdir", "os.scandir"}:
        if args:
            _validate_path(args[0], writing=False)


sys.addaudithook(_audit_hook)


def _reset_global_state(session_id: str) -> None:
    _sessions.pop(session_id, None)
    pyplot = sys.modules.get("matplotlib.pyplot")
    matplotlib = sys.modules.get("matplotlib")
    if pyplot is not None:
        pyplot.close("all")
    if matplotlib is not None:
        matplotlib.rcdefaults()
    for name in tuple(sys.modules):
        if name not in _baseline_modules and name != __name__:
            sys.modules.pop(name, None)
    random.seed()


def reset_session(session_id: str) -> None:
    """Forget user-visible Python state for one conversation."""
    _reset_global_state(session_id)


def _namespace(session_id: str) -> dict[str, Any]:
    if session_id not in _sessions:
        session_builtins = dict(builtins.__dict__)
        session_builtins["__import__"] = _session_import
        _sessions[session_id] = {
            "__name__": "__yamabiko_cell__",
            "__builtins__": session_builtins,
        }
    return _sessions[session_id]


def _session_import(*args: Any, **kwargs: Any) -> Any:
    imported = builtins.__import__(*args, **kwargs)
    _patch_matplotlib_show()
    return imported


def _is_visible_generated_file(path: Path, root: Path) -> bool:
    relative = path.relative_to(root)
    return path.is_file() and not any(
        part.startswith(".") or part == "__pycache__" for part in relative.parts
    )


def _snapshot_files(root: Path) -> dict[str, tuple[int, int]]:
    return {
        str(path.relative_to(root)): (path.stat().st_mtime_ns, path.stat().st_size)
        for path in root.rglob("*")
        if _is_visible_generated_file(path, root)
    }


def _save_open_figures(outputs: Path) -> None:
    plt = sys.modules.get("matplotlib.pyplot")
    if plt is None:
        return
    for number in plt.get_fignums():
        index = 1
        while (outputs / f"figure_{index}.png").exists():
            index += 1
        plt.figure(number).savefig(outputs / f"figure_{index}.png", format="png", bbox_inches="tight")
    plt.close("all")


def _patch_matplotlib_show() -> None:
    plt = sys.modules.get("matplotlib.pyplot")
    if plt is None or getattr(plt.show, "__yamabiko_show__", False):
        return

    def save_instead_of_show(*_args: Any, **_kwargs: Any) -> None:
        if _active_outputs is not None:
            _save_open_figures(_active_outputs)

    save_instead_of_show.__yamabiko_show__ = True
    plt.show = save_instead_of_show


def _artifacts(
    roots: tuple[tuple[str, Path], ...],
    before: dict[str, dict[str, tuple[int, int]]],
) -> list[dict[str, Any]]:
    values: list[dict[str, Any]] = []
    for root_name, root in roots:
        for path in sorted(root.rglob("*")):
            if not _is_visible_generated_file(path, root):
                continue
            relpath = str(path.relative_to(root))
            stat = path.stat()
            if before[root_name].get(relpath) == (stat.st_mtime_ns, stat.st_size):
                continue
            mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            values.append({
                "name": path.name,
                "root": root_name,
                "relpath": relpath,
                "mime": mime,
                "size": stat.st_size,
            })
    return values


def _execute(code: str, namespace: dict[str, Any]) -> str | None:
    tree = ast.parse(code, mode="exec")
    if not tree.body or not isinstance(tree.body[-1], ast.Expr):
        exec(compile(tree, "<python_execute>", "exec"), namespace, namespace)
        return None
    prefix = ast.Module(body=tree.body[:-1], type_ignores=tree.type_ignores)
    if prefix.body:
        exec(compile(prefix, "<python_execute>", "exec"), namespace, namespace)
    expression = ast.Expression(tree.body[-1].value)
    value = eval(compile(expression, "<python_execute>", "eval"), namespace, namespace)
    return repr(value)


def run_cell(session_id: str, code: str, options_json: str) -> str:
    global _active_workspace, _active_outputs, _active_read_roots
    started = time.monotonic()
    stdout = _BoundedTextIO()
    stderr = _BoundedTextIO()
    previous_stdout, previous_stderr = sys.stdout, sys.stderr
    previous_cwd = Path.cwd()
    error: dict[str, str] | None = None
    result_repr: str | None = None
    artifacts: list[dict[str, Any]] = []
    artifact_roots: tuple[tuple[str, Path], ...] = ()
    before: dict[str, dict[str, tuple[int, int]]] = {}
    try:
        options = json.loads(options_json)
        workspace = _resolved(options["workspace"])
        outputs = _resolved(options["outputs"])
        workspace.mkdir(parents=True, exist_ok=True)
        outputs.mkdir(parents=True, exist_ok=True)
        read_roots = tuple(_resolved(path) for path in options.get("read_roots", []))
        _active_workspace = workspace
        _active_outputs = outputs
        _active_read_roots = read_roots
        if options.get("reset") or session_id not in _sessions:
            _reset_global_state(session_id)
        os.environ["MPLBACKEND"] = "Agg"
        os.environ["MPLCONFIGDIR"] = str(workspace / ".matplotlib")
        os.chdir(workspace)
        artifact_roots = (("outputs", outputs), ("workspace", workspace))
        before = {name: _snapshot_files(root) for name, root in artifact_roots}
        sys.stdout, sys.stderr = stdout, stderr
        result_repr = _execute(code, _namespace(session_id))
    except BaseException as exc:  # The bridge must always receive a JSON envelope.
        error = {
            "type": type(exc).__name__,
            "message": str(exc),
            "traceback": "".join(traceback.format_exception(type(exc), exc, exc.__traceback__)),
        }
    finally:
        sys.stdout, sys.stderr = previous_stdout, previous_stderr
        if artifact_roots:
            try:
                _save_open_figures(outputs)
                artifacts = _artifacts(artifact_roots, before)
            except BaseException as artifact_error:
                if error is None:
                    error = {
                        "type": type(artifact_error).__name__,
                        "message": str(artifact_error),
                        "traceback": "".join(traceback.format_exception(
                            type(artifact_error), artifact_error, artifact_error.__traceback__
                        )),
                    }
        _active_workspace = None
        _active_outputs = None
        _active_read_roots = ()
        try:
            os.chdir(previous_cwd)
        except OSError:
            pass

    payload = {
        "status": "error" if error else "ok",
        "stdout": stdout.getvalue(),
        "stderr": stderr.getvalue(),
        "result_repr": result_repr,
        "artifacts": artifacts,
        "duration_ms": int((time.monotonic() - started) * 1000),
        "error": error,
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
