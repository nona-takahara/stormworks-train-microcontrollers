#!/usr/bin/env node
// Stormworksとの入出力に関する唯一のコマンド入口。
// 個々のマイコン名やローカルパスはここへ埋め込まず、Git管理外の設定から読む。
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadConfiguration, selectProjects } from "./config.mjs";
import { StormMclAdapter } from "./storm-mcl.mjs";
import { buildProject, checkProject, exportProject, importProject } from "./operations.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../..");

function usage() {
    return `Usage:
  pnpm microcontroller build <name...> | --all
  pnpm microcontroller check <name...> | --all
  pnpm microcontroller export <name...> | --all
  pnpm microcontroller import <name...> | --all`;
}

function parseArguments(argv) {
    const [command, ...rest] = argv;
    if (!["build", "check", "export", "import"].includes(command)) {
        throw new Error(`${usage()}${command ? `\n\nUnknown command: ${command}` : ""}`);
    }
    let all = false;
    const names = [];
    // 引数なしで全件を処理すると、設定追加後に操作範囲が暗黙に広がる。
    // そのため全件操作だけは、常に利用者が--allを明記する契約にしている。
    for (const argument of rest) {
        if (argument === "--all") all = true;
        else if (argument.startsWith("-")) throw new Error(`Unknown option: ${argument}`);
        else names.push(argument);
    }
    return { command, names, all };
}

export async function main(argv = process.argv.slice(2), dependencies = {}) {
    const parsed = parseArguments(argv);
    const config = (dependencies.loadConfiguration ?? loadConfiguration)(repoRoot);
    const projects = selectProjects(config.projects, parsed.names, parsed.all);
    // Lua単体のbuildはstorm-mclを使わない。依存CLIが未導入でもLua生成だけは
    // 実行できるよう、この場合はアダプターの生成自体を避ける。
    const adapter = parsed.command === "build"
        ? dependencies.adapter
        : dependencies.adapter ?? new StormMclAdapter(repoRoot);

    // 複数対象は設定順／指定順に直列実行する。途中で失敗したとき、どの対象まで
    // 完了したかをログの順序から判断できることを並列実行より優先している。
    for (const project of projects) {
        console.log(`[${project.name}] ${parsed.command}`);
        if (parsed.command === "build") buildProject(config, project, dependencies);
        if (parsed.command === "check") checkProject(config, project, adapter);
        if (parsed.command === "export") {
            const result = await exportProject(config, project, adapter, dependencies);
            console.log(result.changed ? `Wrote ${result.destination}` : `No write: ${result.destination}`);
        }
        if (parsed.command === "import") await importProject(config, project, adapter, dependencies);
    }
}

// 他のNodeスクリプトからmainを呼べるようにしつつ、直接実行時だけCLIとして終了値を設定する。
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main().catch((error) => {
        console.error(`[error] ${error.message}`);
        process.exitCode = 1;
    });
}
