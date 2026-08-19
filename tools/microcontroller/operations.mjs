import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { buildLua } from "./lua-build.mjs";

function timestamp(date = new Date()) {
    return date.toISOString().replace(/[:.]/gu, "-");
}

export async function confirmOverwrite(message, io = {}) {
    const input = io.input ?? stdin;
    const output = io.output ?? stdout;
    if (!input.isTTY || !output.isTTY) {
        throw new Error("Refusing to overwrite in a non-interactive terminal");
    }
    const prompt = readline.createInterface({ input, output });
    try {
        const answer = (await prompt.question(`${message} [y/N] `)).trim().toLowerCase();
        return answer === "y" || answer === "yes";
    } finally {
        prompt.close();
    }
}

export function buildProject(config, project, dependencies = {}) {
    const builder = dependencies.buildLua ?? buildLua;
    return project.luaBuilds.map((build) => builder(config.repoRoot, build, dependencies.luaOptions));
}

export function checkProject(config, project, adapter) {
    const projectPath = path.resolve(config.repoRoot, project.project);
    if (!fs.existsSync(projectPath)) throw new Error(`Project file not found: ${projectPath}`);
    adapter.check(projectPath);
}

function copyOverlays(config, project, stagedRoot) {
    for (const build of project.luaBuilds) {
        const source = path.resolve(config.repoRoot, build.output);
        if (!fs.existsSync(source)) throw new Error(`Lua build output not found: ${source}`);
        const destination = path.resolve(stagedRoot, build.overlay);
        const relative = path.relative(stagedRoot, destination);
        if (relative.startsWith("..") || path.isAbsolute(relative)) {
            throw new Error(`Lua overlay escapes staged project: ${build.overlay}`);
        }
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.copyFileSync(source, destination);
    }
}

function installWithRollback(generatedXml, destination, backup, fsApi = fs) {
    fsApi.mkdirSync(path.dirname(backup), { recursive: true });
    const replacement = `${destination}.storm-mcl-new-${process.pid}`;
    const rollback = `${destination}.storm-mcl-old-${process.pid}`;
    fsApi.copyFileSync(generatedXml, replacement);
    let movedOld = false;
    try {
        if (fsApi.existsSync(destination)) {
            fsApi.copyFileSync(destination, backup, fs.constants.COPYFILE_EXCL);
            fsApi.renameSync(destination, rollback);
            movedOld = true;
        }
        fsApi.renameSync(replacement, destination);
        if (movedOld) fsApi.rmSync(rollback);
    } catch (error) {
        if (fsApi.existsSync(replacement)) fsApi.rmSync(replacement);
        if (movedOld && fsApi.existsSync(rollback) && !fsApi.existsSync(destination)) {
            fsApi.renameSync(rollback, destination);
        }
        throw error;
    }
}

export async function exportProject(config, project, adapter, dependencies = {}) {
    buildProject(config, project, dependencies);
    const sourceProject = path.resolve(config.repoRoot, project.project);
    if (!fs.existsSync(sourceProject)) throw new Error(`Project file not found: ${sourceProject}`);
    const sourceRoot = path.dirname(sourceProject);
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "stormworks-export-"));
    const stagedRoot = path.join(tempRoot, "project");
    const generatedXml = path.join(tempRoot, project.stormworksFile);
    try {
        fs.cpSync(sourceRoot, stagedRoot, { recursive: true });
        copyOverlays(config, project, stagedRoot);
        const stagedProject = path.join(stagedRoot, path.basename(sourceProject));
        adapter.check(stagedProject);
        adapter.exportXml(stagedProject, generatedXml);
        if (!fs.existsSync(generatedXml)) throw new Error(`storm-mcl did not create XML: ${generatedXml}`);

        const destination = path.join(config.stormworksDir, project.stormworksFile);
        if (fs.existsSync(destination) && fs.readFileSync(destination).equals(fs.readFileSync(generatedXml))) {
            return { changed: false, destination };
        }
        const confirm = dependencies.confirm ?? confirmOverwrite;
        if (!(await confirm(`Overwrite Stormworks microcontroller ${destination}?`))) {
            return { changed: false, declined: true, destination };
        }
        const backup = path.join(config.backupDir, project.name,
            `${path.basename(project.stormworksFile, ".xml")}-${timestamp(dependencies.now?.())}.xml`);
        installWithRollback(generatedXml, destination, backup, dependencies.fs ?? fs);
        return { changed: true, destination, backup: fs.existsSync(backup) ? backup : undefined };
    } finally {
        fs.rmSync(tempRoot, { recursive: true, force: true });
    }
}

export async function importProject(config, project, adapter, dependencies = {}) {
    const source = path.join(config.stormworksDir, project.stormworksFile);
    if (!fs.existsSync(source)) throw new Error(`Stormworks XML not found: ${source}`);
    const projectPath = path.resolve(config.repoRoot, project.project);
    if (!fs.existsSync(projectPath)) throw new Error(`Project file not found: ${projectPath}`);
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "stormworks-import-"));
    const importedXml = path.join(tempRoot, project.stormworksFile);
    try {
        fs.copyFileSync(source, importedXml);
        return await adapter.importXml({
            xmlPath: importedXml,
            projectPath,
            confirm: dependencies.confirm ?? confirmOverwrite,
        });
    } finally {
        fs.rmSync(tempRoot, { recursive: true, force: true });
    }
}
