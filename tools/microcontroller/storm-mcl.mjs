import fs from "node:fs";
import path from "node:path";
import { run } from "./process.mjs";

export class StormMclAdapter {
    constructor(repoRoot, options = {}) {
        this.repoRoot = repoRoot;
        this.node = options.node ?? process.execPath;
        this.cli = options.cli ?? path.join(repoRoot, "node_modules", "storm-microcontroller-language", "dist", "cli", "main.js");
        this.run = options.run ?? run;
        if (!fs.existsSync(this.cli)) throw new Error(`storm-mcl CLI not found: ${this.cli}`);
    }

    invoke(args, options = {}) {
        return this.run(this.node, [this.cli, ...args], { cwd: this.repoRoot, ...options });
    }

    check(projectPath) {
        this.invoke(["check-dsl", projectPath]);
        this.invoke(["typecheck-dsl", projectPath]);
    }

    exportXml(projectPath, outputPath) {
        this.invoke(["dsl2xml", projectPath, "--out", outputPath]);
    }

    importXml() {
        throw new Error(
            "Import requires the storm-mcl #63 synchronization CLI, which is not available in the supported storm-mcl version. " +
            "The unsafe xml2dsl --out-dir fallback is intentionally disabled."
        );
    }
}
