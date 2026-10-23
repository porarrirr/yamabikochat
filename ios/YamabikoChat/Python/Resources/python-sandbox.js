// Trusted WebKit parent. User Python runs only in a Worker, never in this realm.
// There is no native file-read/network/auth RPC. Native sends bounded copies.
(() => {
    "use strict";
    const assets = new Map();
    let worker = null;
    let pending = null;
    const post = value => window.webkit.messageHandlers.pythonResult.postMessage(value);
    const string = value => typeof value === "string" && value.length <= 65536 ? value : null;
    function validated(data) {
        const result = data.result;
        if (!result || !["ok", "error"].includes(result.status) || !Array.isArray(result.artifacts) || result.artifacts.length > 1024 || !Array.isArray(data.files) || data.files.length > 4096) throw new Error("Invalid Python result");
        if (string(result.stdout) === null || string(result.stderr) === null || (result.result_repr != null && string(result.result_repr) === null)) throw new Error("Oversized Python output");
        let bytes = 0;
        const files = data.files.map(file => {
            if (typeof file.path !== "string" || file.path.length > 4096 || (file.data != null && (typeof file.data !== "string" || file.data.length > 34952536 || (bytes += file.data.length) > 139813000))) throw new Error("Oversized workspace");
            return { path: file.path, data: file.data ?? null };
        });
        const artifacts = result.artifacts.map(file => {
            if (string(file.name) === null || string(file.relpath) === null || string(file.mime) === null || !["workspace", "outputs"].includes(file.root) || !Number.isSafeInteger(file.size) || file.size < 0 || file.size > 26214400) throw new Error("Invalid artifact");
            return { name: file.name, root: file.root, relpath: file.relpath, mime: file.mime, size: file.size };
        });
        const error = result.error;
        if (error && [error.type, error.message, error.traceback].some(value => string(value) === null)) throw new Error("Invalid Python error");
        return { type: "result", id: pending, files, result: {
            status: result.status, stdout: result.stdout, stderr: result.stderr,
            result_repr: result.result_repr ?? null, artifacts,
            duration_ms: Number.isSafeInteger(result.duration_ms) ? Math.max(0, result.duration_ms) : 0,
            error: error ? { type: error.type, message: error.message, traceback: error.traceback } : null
        } };
    }
    globalThis.pythonSandbox = Object.freeze({
        addAsset(name, base64) {
            assets.set(name, Uint8Array.from(atob(base64), c => c.charCodeAt(0)));
        },
        start(workerSource) {
            worker = new Worker(URL.createObjectURL(new Blob([workerSource], { type: "text/javascript" })), { type: "module" });
            worker.onmessage = ({ data }) => {
                if (data.type === "ready") { post({ type: "ready" }); return; }
                if (data.type === "startup_error") { post({ type: "startup_error", message: string(data.message)?.slice(0, 1024) }); return; }
                if (!pending || data.id !== pending) return;
                let response;
                try { response = validated(data); }
                catch { response = { type: "worker_error", id: pending }; }
                pending = null;
                post(response);
            };
            worker.onerror = () => { post({ type: "worker_error", id: pending }); };
            worker.postMessage({ type: "initialize", assets: [...assets] });
            assets.clear();
        },
        execute(id, input) {
            if (pending || !worker) throw new Error("Python worker unavailable");
            pending = id;
            worker.postMessage({ type: "execute", id, input });
        },
        dispose() { worker?.terminate(); worker = null; pending = null; assets.clear(); }
    });
})();
