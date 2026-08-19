#!/usr/bin/env node
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
    const adapter = parsed.command === "build"
        ? dependencies.adapter
        : dependencies.adapter ?? new StormMclAdapter(repoRoot);

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

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main().catch((error) => {
        console.error(`[error] ${error.message}`);
        process.exitCode = 1;
    });
}
