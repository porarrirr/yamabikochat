// The mobile extension host owns an ephemeral directory. Credentials never go here.
// This module must initialize before pi-subagents evaluates its directory constants.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const mobileAgentDir = path.join(os.tmpdir(), `yamabiko-pi-subagents-${process.pid}`);
process.env.PI_CODING_AGENT_DIR = mobileAgentDir;
// Mobile ships its extensions and agents. Never discover/install global npm packages.
// Pi's offline flag affects package discovery, not provider inference.
process.env.PI_OFFLINE = "1";
process.env.YAMABIKO_PI_MOBILE = "1";
const directory = path.join(mobileAgentDir, "extensions", "subagent");
fs.mkdirSync(directory, { recursive: true });
fs.writeFileSync(path.join(directory, "config.json"), JSON.stringify({
  asyncByDefault: false,
  intercomBridge: { mode: "off" },
  waitTool: { enabled: false },
  defaultSubagentContext: "fresh",
  toolActivation: "eager",
  maxSubagentDepth: 1,
  maxSubagentSpawnsPerRun: 16,
  globalConcurrencyLimit: 3,
  fleetView: false,
  asyncWidget: false,
  scheduledRuns: { enabled: false },
  missions: { enabled: false, globalIndex: false },
  artifactConfig: { enabled: false },
  disabledFeatures: ["workflow-scripts", "external-machines", "agent-management", "panes", "missions", "lane-management", "extension-bindings"]
}));
