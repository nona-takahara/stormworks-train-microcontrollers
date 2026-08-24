import fs from "node:fs";
import path from "node:path";
import { run } from "./process.mjs";

// storm-mcl固有のサブコマンドと引数を、このアダプター以外へ漏らさない。
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
        // 構文・参照解決と型検査は別の検査なので、XML生成前に両方を要求する。
        this.invoke(["check-dsl", projectPath]);
        this.invoke(["typecheck-dsl", projectPath]);
    }

    exportXml(projectPath, outputPath) {
        this.invoke(["dsl2xml", projectPath, "--out", outputPath]);
    }

    async importXml({ xmlPath, projectPath, confirm }) {
        // syncの診断を先に利用者へ見せ、承認された同じ入力だけを適用する。
        this.invoke(["xml2dsl", xmlPath, "--sync-with", projectPath, "--dry-run"]);
        if (!(await confirm(`Apply storm-mcl synchronization to ${projectPath}?`))) {
            return { changed: false, declined: true, projectPath };
        }
        this.invoke(["xml2dsl", xmlPath, "--sync-with", projectPath]);
        return { changed: true, projectPath };
    }
}
