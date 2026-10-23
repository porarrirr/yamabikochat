import { build } from "esbuild";
import "./patch-pi-contract.mjs";
import fs from "node:fs";
import path from "node:path";

// Preserve package-relative data lookups after bundling (agent definitions, guide,
// version manifest and SDK theme data). No source is downloaded at app runtime.
const modules = path.resolve("node_modules");
const assets = path.resolve("bundle/PiAssets/node_modules");
fs.rmSync(path.resolve("bundle/PiAssets"), { recursive: true, force: true });
for (const name of ["pi-subagents", "@earendil-works/pi-coding-agent", "@earendil-works/pi-tui"]) {
  fs.cpSync(path.join(modules, name), path.join(assets, name), {
    recursive: true,
    filter: source => fs.statSync(source).isDirectory() || /\.(json|md|yaml|yml|txt|css|html|wasm)$/.test(source) || /LICENSE$/.test(source)
  });
}
// The upstream workflow worker loads its parser with createRequire(), outside
// esbuild's static import graph. Ship that exact dependency beside the data.
fs.cpSync(path.join(modules, "acorn"), path.join(assets, "acorn"), {
  recursive: true, filter: source => fs.statSync(source).isDirectory() || /\.(json|[cm]?js|md)$/.test(source) || /LICENSE$/.test(source)
});
await build({
  entryPoints: ["src/main.js"], bundle: true, platform: "node", format: "esm", target: "node24",
  banner: { js: "import{createRequire as __yamabikoCreateRequire}from'node:module';const require=__yamabikoCreateRequire(import.meta.url);" },
  outfile: "bundle/main.js",
  plugins: [{ name: "package-data-urls", setup(build) {
    build.onLoad({ filter: /node_modules\/.*\.[cm]?js$/ }, async args => {
      let contents = await fs.promises.readFile(args.path, "utf8");
      if (!contents.includes("import.meta.url")) return;
      const relative = path.relative(modules, args.path).split(path.sep).join("/");
      contents = contents.replaceAll("import.meta.url", `new URL(${JSON.stringify(`./PiAssets/node_modules/${relative}`)}, import.meta.url).href`);
      return { contents, loader: "js", resolveDir: path.dirname(args.path) };
    });
  } }]
});
