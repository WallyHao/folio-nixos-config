import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { SessionManager, SettingsManager } from "@earendil-works/pi-coding-agent";

// No model requests: exercise discovery, settings persistence and session storage
// through a real extension command in the installed Pi runtime.
export default function (pi: any) {
  pi.registerProvider("folio-fixture", {
    baseUrl: "http://127.0.0.1:1/v1",
    apiKey: "disposable-test-key",
    api: "openai-completions",
    models: [{ id: "fixture", name: "Fixture", reasoning: false,
      input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 8192, maxTokens: 1024 }],
  });
  pi.registerCommand("folio-fixture", {
    description: "Verify Folio configuration and private session state",
    handler: async () => {
      for (const command of ["npm", "git"]) {
        const result = await pi.exec(command, ["--version"]);
        if (result.code !== 0) throw new Error(`${command} is unavailable`);
      }
      const agentDir = process.env.PI_CODING_AGENT_DIR!;
      const settings = SettingsManager.create(process.cwd(), agentDir);
      settings.setTheme("dark");
      await settings.flush();
      const errors = settings.drainErrors();
      if (errors.length) throw errors[0].error;
      pi.appendEntry("folio-fixture", { loaded: true });
      const persisted = SessionManager.create(process.cwd());
      persisted.appendMessage({ role: "user", content: "disposable fixture", timestamp: Date.now() });
      writeFileSync(join(agentDir, "fixture-loaded"), "loaded\n");
      process.stdout.write("folio-fixture-loaded\n");
    },
  });
}
