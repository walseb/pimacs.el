import { appendFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { once } from "node:events";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const tapesDir = path.join(__dirname, "../tapes");
const mode = process.env.FIXTURE_MODE || "replay";
const scenario = process.env.FIXTURE_SCENARIO || "default";

const binPath = path.join(__dirname, "../node_modules/.bin/proxay");

function initialize() {
  const proxay = spawn(binPath, [
    "--mode",
    mode,
    "--tapes-dir",
    tapesDir,
    "--default-tape",
    scenario,
    "--host",
    "http://100.126.93.103:11434",
    "--port",
    "5544",
  ]);

  const logFile = "/tmp/proxay.log";

  proxay.stdout.on("data", (data) => {
    appendFileSync(logFile, `[stdout] ${data.toString()}`);
  });

  proxay.stderr.on("data", (data) => {
    appendFileSync(logFile, `[stderr] ${data.toString()}`);
  });

  proxay.on("exit", (code) => {
    appendFileSync(logFile, `[exit] code=${code}\n`);
  });
}

export default function (pi: ExtensionAPI) {
  initialize();
  pi.registerProvider("fixture", {
    api: "openai-completions",
    baseUrl: "http://127.0.0.1:5544/v1",
    apiKey: "ollama",
    models: [
      {
        id: "qwen3.5:4b",
        name: "Qwen 3.5:4b",
        reasoning: true,
        input: ["text"],
        cost: {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
        },
        contextWindow: 200000,
        maxTokens: 100000,
      },
    ],
  });
}
