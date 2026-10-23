// This entire realm, including every Python/JS global, is untrusted after init.
// The security boundary is WebKit + CSP, not Python hooks or JS monkey patches.
let python;
let ready;
const decode = bytes => new TextDecoder().decode(bytes);
const MAX_FILE = 25 * 1024 * 1024;
const MAX_TOTAL = 100 * 1024 * 1024;
const MAX_FILES = 1024;

function safePath(path) {
    if (typeof path !== "string" || !path || path.startsWith("/") || path.includes("\\") || path.includes("\0")) throw new Error("Invalid workspace path");
    const parts = path.split("/");
    if (parts.length > 16 || parts.some(p => !p || p === "." || p === "..")) throw new Error("Invalid workspace path");
    return path;
}

async function initialize(entries) {
    const assets = new Map(entries);
    // All loader reads are immutable memory assets, even while connect-src is none.
    self.fetch = async input => {
        const url = new URL(typeof input === "string" || input instanceof URL ? String(input) : input.url, "https://python.invalid/");
        const name = url.pathname.slice(1);
        if (url.origin !== "https://python.invalid" || url.search || !assets.has(name)) throw new Error("Python network access is disabled");
        return new Response(assets.get(name), { headers: { "content-type": name.endsWith(".wasm") ? "application/wasm" : "application/octet-stream" } });
    };
    // Bundled modules only. Real network fetch remains prohibited by WebKit CSP.
    const coreURL = URL.createObjectURL(new Blob([assets.get("pyodide.asm.mjs")], { type: "text/javascript" }));
    const { default: createPyodideModule } = await import(coreURL);
    (0, eval)(decode(assets.get("pyodide.js")));
    python = await self.loadPyodide({
        indexURL: "https://python.invalid/", packageBaseUrl: "https://python.invalid/",
        lockFileContents: JSON.parse(decode(assets.get("pyodide-lock.json"))),
        createPyodideModule, stdout: () => {}, stderr: () => {},
        packages: ["numpy", "matplotlib", "pillow"]
    });
    const FS = python.FS;
    FS.mkdirTree("/workspace/outputs");
    FS.mkdirTree("/fonts");
    for (const [name, bytes] of assets) if (name.startsWith("Fonts/") && name.endsWith(".ttf")) FS.writeFile("/fonts/" + name.split("/").at(-1), bytes);
    FS.writeFile("/yamabiko_runtime.py", assets.get("yamabiko_runtime.py"));
    await python.runPythonAsync(`
import os, sys
sys.path.insert(0, '/')
os.environ['MPLBACKEND'] = 'Agg'
os.environ['MPLCONFIGDIR'] = '/tmp/matplotlib'
import matplotlib
from matplotlib import font_manager
from pathlib import Path
for font in Path('/fonts').glob('*.ttf'):
    font_manager.fontManager.addfont(str(font))
import yamabiko_runtime
`);
    URL.revokeObjectURL(coreURL);
    assets.clear();
}

function snapshotFiles() {
    const files = [];
    let total = 0;
    const walk = (directory, prefix) => {
        for (const name of python.FS.readdir(directory)) {
            if (name === "." || name === "..") continue;
            const relative = safePath(prefix + name);
            const absolute = directory + "/" + name;
            const stat = python.FS.lstat(absolute);
            if (python.FS.isLink(stat.mode)) throw new Error("Workspace symlinks cannot leave the sandbox");
            if (python.FS.isDir(stat.mode)) { files.push({ path: relative, data: null }); walk(absolute, relative + "/"); continue; }
            if (!python.FS.isFile(stat.mode)) throw new Error("Invalid workspace file");
            if (stat.size > MAX_FILE || (total += stat.size) > MAX_TOTAL || files.length >= MAX_FILES) throw new Error("Python workspace quota exceeded");
            const bytes = python.FS.readFile(absolute);
            let encoded = "";
            for (let offset = 0; offset < bytes.length; offset += 32768) encoded += String.fromCharCode(...bytes.subarray(offset, offset + 32768));
            files.push({ path: relative, data: btoa(encoded) });
        }
    };
    walk("/workspace", "");
    return files;
}

self.onmessage = async ({ data }) => {
    if (data.type === "initialize") {
        ready = initialize(data.assets);
        try { await ready; self.postMessage({ type: "ready" }); }
        catch (error) { self.postMessage({ type: "startup_error", message: String(error).slice(0, 1024) }); }
        return;
    }
    if (data.type !== "execute") return;
    try {
        await ready;
        const { input } = data;
        // Synchronize only explicit native workspace copies, with no host mounts.
        python.FS.chdir("/");
        const remove = path => { for (const name of python.FS.readdir(path)) { if (name === "." || name === "..") continue; const child = path + "/" + name; const stat = python.FS.lstat(child); if (python.FS.isDir(stat.mode)) { remove(child); python.FS.rmdir(child); } else python.FS.unlink(child); } };
        remove("/workspace");
        python.FS.mkdirTree("/workspace/outputs");
        for (const file of input.files) {
            const path = "/workspace/" + safePath(file.path);
            if (file.data == null) { python.FS.mkdirTree(path); continue; }
            python.FS.mkdirTree(path.slice(0, path.lastIndexOf("/")));
            python.FS.writeFile(path, Uint8Array.from(atob(file.data), c => c.charCodeAt(0)));
        }
        python.globals.set("_yb_code", input.code);
        python.globals.set("_yb_reset", input.reset);
        const result = await python.runPythonAsync(`yamabiko_runtime.run_cell('session', _yb_code, __import__('json').dumps({'workspace':'/workspace','outputs':'/workspace/outputs','read_roots':['/lib','/fonts','/tmp'], 'reset':_yb_reset}))`);
        self.postMessage({ type: "result", id: data.id, result: JSON.parse(result), files: snapshotFiles() });
    } catch {
        self.postMessage({ type: "execution_error", id: data.id });
    }
};
