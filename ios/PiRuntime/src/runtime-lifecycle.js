import fs from "node:fs";
import readline from "node:readline";
import { once } from "node:events";

// iOS may reclaim a listening TCP socket while suspended without notifying Node.
// Lifecycle commands travel over an anonymous pipe, independent of that socket.
// Only the HTTP listener changes; the Pi agent, runs and credentials stay alive.
export function createRuntimeListener({ createServer, port, log }) {
  let server = null;
  let activeRequests = 0;
  let finishPause = null;
  const closeListener = () => {
    if (!server) return;
    const closing = server;
    server = null;
    // close() releases the listening handle synchronously. Its callback waits
    // for accepted connections, which may still be serving an active Pi run.
    closing.close(() => log("serverClosed", { port }));
    log("serverListenerPaused", { port });
  };
  const completePause = () => {
    finishPause?.();
    finishPause = null;
  };
  return (state) => {
    if (state === "pause") {
      if (activeRequests === 0) { closeListener(); return; }
      // Tool-result POSTs still need the listener while an accepted Pi run is
      // finishing within iOS's background execution allowance.
      if (finishPause) return;
      return new Promise((resolve) => { finishPause = resolve; });
    } else if (state === "suspend") {
      closeListener();
      completePause();
    } else if (state === "resume") {
      completePause();
      if (server) return;
      server = createServer();
      server.on("request", (_req, res) => {
        activeRequests++;
        res.once("close", () => {
          activeRequests--;
          if (finishPause && activeRequests === 0) {
            closeListener();
            completePause();
          }
        });
      });
      server.on("listening", () => log("serverListening", { port }));
      server.on("error", (error) => {
        log("serverError", { port, errorCode: error.code, errorMessage: error.message });
        // Do not silently retry on another port or leave a failed listener cached.
        throw error;
      });
      const ready = once(server, "listening");
      server.listen(port, "127.0.0.1");
      return ready;
    } else {
      throw new Error(`Invalid runtime lifecycle state: ${state}`);
    }
  };
}

export function installRuntimeLifecycle(options) {
  const transition = createRuntimeListener(options);
  if (options.commandFD === undefined) {
    transition("resume"); // Android has no iOS lifecycle pipe.
    return;
  }
  const commandFD = Number(options.commandFD);
  const acknowledgementFD = Number(options.acknowledgementFD);
  if (!Number.isInteger(commandFD) || !Number.isInteger(acknowledgementFD)) {
    throw new Error("Invalid runtime lifecycle pipe descriptors");
  }
  const commands = readline.createInterface({
    input: fs.createReadStream(null, { fd: commandFD, autoClose: false }),
    crlfDelay: Infinity
  });
  commands.on("line", (line) => {
    const [state, generation] = line.split(":");
    if (!/^\d+$/.test(generation)) throw new Error("Invalid runtime lifecycle generation");
    // A pause can drain active runs asynchronously. Do not block a subsequent
    // resume or expiration command behind that drain.
    Promise.resolve(transition(state)).then(() => {
      options.log("nativeLifecycleApplied", { state, generation });
      fs.writeSync(acknowledgementFD, `${generation}\n`);
    });
  });
  commands.on("close", () => { throw new Error("Runtime lifecycle pipe closed"); });
}
