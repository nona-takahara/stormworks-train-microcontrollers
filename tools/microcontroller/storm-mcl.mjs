import fs from "node:fs";
import path from "node:path";
import { run } from "./process.mjs";

// storm-mcl固有のサブコマンドと引数を、このアダプター以外へ漏らさない。
// #63の正式CLIが公開された際は、主にimportXmlだけを差し替える想定である。
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

    importXml() {
        // 現行xml2dslはobjectId由来の名前で既存DSLを再生成し、手動命名や
        // script_refを崩し得る。対応版がない間は不完全な取り込みより停止を選ぶ。
        throw new Error(
            "Import requires the storm-mcl #63 synchronization CLI, which is not available in the supported storm-mcl version. " +
            "The unsafe xml2dsl --out-dir fallback is intentionally disabled."
        );
    }
}
