import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import readline from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { buildLua } from "./lua-build.mjs";
import { resolveLuaBuilds } from "./lua-node-resolution.mjs";

// Windowsでファイル名に使えない":"を避けたISO時刻。バックアップを対象名と
// 時刻だけで追跡でき、同名を黙って上書きしない構成にする。
export function timestamp(date = new Date()) {
    return date.toISOString().replace(/[:.]/gu, "-");
}

// 非対話の呼び出し(エージェントなど)への承認は、利用者があらかじめリポジトリ直下の
// このファイルに、確認の文面を一行そのまま書くことで渡す。承認は一度使うと行ごと消える。
// 消えるのは、古い承認が残って、後の別の上書きを黙って通すことを避けるため。
export const APPROVAL_FILE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..", "MICROCONTROLLER_APPROVAL.txt");

function consumeApproval(message, file) {
    if (!fs.existsSync(file)) return false;
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/u);
    const index = lines.findIndex((line) => line.trim() === message);
    if (index < 0) return false;
    lines.splice(index, 1);
    fs.writeFileSync(file, lines.join("\n"));
    return true;
}

export async function confirmOverwrite(message, io = {}) {
    const input = io.input ?? stdin;
    const output = io.output ?? stdout;
    // CIやリダイレクト下で既定値が承認扱いになる事故を避ける。
    // 自動上書き用のforceフラグは、この小規模ツールでは意図的に用意しない。
    if (!input.isTTY || !output.isTTY) {
        if (consumeApproval(message, io.approvalFile ?? APPROVAL_FILE)) return true;
        throw new Error(`Refusing to overwrite in a non-interactive terminal. To approve, write this line to ${APPROVAL_FILE}:\n${message}`);
    }
    const prompt = readline.createInterface({ input, output });
    try {
        const answer = (await prompt.question(`${message} [y/N] `)).trim().toLowerCase();
        return answer === "y" || answer === "yes";
    } finally {
        prompt.close();
    }
}

export async function buildProject(config, project, dependencies = {}) {
    const resolve = dependencies.resolveLuaBuilds ?? resolveLuaBuilds;
    const builder = dependencies.buildLua ?? buildLua;
    const luaBuilds = await resolve(config.repoRoot, project, dependencies.resolveOptions);
    const results = luaBuilds.map((build) => builder(config.repoRoot, build, dependencies.luaOptions));
    return { luaBuilds, results };
}

export function checkProject(config, project, adapter) {
    if (!fs.existsSync(project.projectJsonPath)) throw new Error(`Project file not found: ${project.projectJsonPath}`);
    adapter.check(project.projectJsonPath);
}

function copyOverlays(config, luaBuilds, stagedRoot) {
    // deploy成果物はリポジトリ内のscriptsへ直接戻さない。export用に複製した
    // DSLツリーだけを書き換え、XML同期とLuaビルドの書込先を分離する。
    for (const build of luaBuilds) {
        const source = path.resolve(config.repoRoot, build.output);
        if (!fs.existsSync(source)) throw new Error(`Lua build output not found: ${source}`);
        const destination = path.resolve(stagedRoot, build.overlay);
        // overlayは設定ファイル由来なので、resolve後にも一時ツリー内か確認する。
        // Windowsドライブ差もpath.isAbsolute(relative)で拒否する。
        const relative = path.relative(stagedRoot, destination);
        if (relative.startsWith("..") || path.isAbsolute(relative)) {
            throw new Error(`Lua overlay escapes staged project: ${build.overlay}`);
        }
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.copyFileSync(source, destination);
    }
}

export function installWithRollback(generatedXml, destination, backup, fsApi = fs) {
    // 完成XMLを先にStormworks側と同じディレクトリへコピーしてからrenameする。
    // renameを同一ファイルシステム内に限定し、途中状態をできるだけ短くする。
    fsApi.mkdirSync(path.dirname(backup), { recursive: true });
    const replacement = `${destination}.storm-mcl-new-${process.pid}`;
    const rollback = `${destination}.storm-mcl-old-${process.pid}`;
    fsApi.copyFileSync(generatedXml, replacement);
    let movedOld = false;
    try {
        if (fsApi.existsSync(destination)) {
            // 外部バックアップを確定させてから現行ファイルを退避する。
            // COPYFILE_EXCLにより、同時刻のバックアップを黙って上書きしない。
            fsApi.copyFileSync(destination, backup, fs.constants.COPYFILE_EXCL);
            fsApi.renameSync(destination, rollback);
            movedOld = true;
        }
        fsApi.renameSync(replacement, destination);
        if (movedOld) fsApi.rmSync(rollback);
    } catch (error) {
        // 新版の設置に失敗し、旧版を一時名へ移動済みなら元の名前へ戻す。
        // destinationが既に存在する場合は、原因調査に必要な状態を上書きしない。
        if (fsApi.existsSync(replacement)) fsApi.rmSync(replacement);
        if (movedOld && fsApi.existsSync(rollback) && !fsApi.existsSync(destination)) {
            fsApi.renameSync(rollback, destination);
        }
        throw error;
    }
}

// プロジェクトから完成XMLを作り、callbackへ渡す。作業用の一時領域はcallbackの後に必ず消す。
// 流れは「Lua生成→一時DSLへ差替え→DSL検査→XML生成」。exportとビークル差し替えが共有する。
export async function withGeneratedXml(config, project, adapter, dependencies, callback) {
    const { luaBuilds } = await buildProject(config, project, dependencies);
    const sourceProject = project.projectJsonPath;
    const sourceRoot = path.dirname(sourceProject);
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "stormworks-export-"));
    const stagedRoot = path.join(tempRoot, "project");
    const generatedXml = path.join(tempRoot, project.stormworksFile);
    try {
        // project.jsonと相対参照される.sw-net/scriptsを一体で扱うため、
        // project.json単体ではなく所属ディレクトリ全体を複製する。
        fs.cpSync(sourceRoot, stagedRoot, { recursive: true });
        copyOverlays(config, luaBuilds, stagedRoot);
        const stagedProject = path.join(stagedRoot, path.basename(sourceProject));
        adapter.check(stagedProject);
        adapter.exportXml(stagedProject, generatedXml);
        if (!fs.existsSync(generatedXml)) throw new Error(`storm-mcl did not create XML: ${generatedXml}`);
        return await callback(generatedXml);
    } finally {
        // XML生成や確認が失敗・拒否された場合も、一時DSLとLua差替えを残さない。
        fs.rmSync(tempRoot, { recursive: true, force: true });
    }
}

export async function exportProject(config, project, adapter, dependencies = {}) {
    // Stormworks側へ触るのは全生成・検査が成功した後だけにする。
    return withGeneratedXml(config, project, adapter, dependencies, async (generatedXml) => {
        const destination = path.join(config.stormworksDir, project.stormworksFile);
        // 内容が同じなら確認もバックアップも不要。mtimeだけを変える書込みを避ける。
        if (fs.existsSync(destination) && fs.readFileSync(destination).equals(fs.readFileSync(generatedXml))) {
            return { changed: false, destination };
        }
        // 上書きの確認は取らない。installWithRollbackが置き換えの前に必ずバックアップを取り、
        // 取れなければ止まるので、戻れる手段はツールが保証する。
        const backup = path.join(config.backupDir, ...project.id.split("/"),
            `${path.basename(project.stormworksFile, ".xml")}-${timestamp(dependencies.now?.())}.xml`);
        installWithRollback(generatedXml, destination, backup, dependencies.fs ?? fs);
        return { changed: true, destination, backup: fs.existsSync(backup) ? backup : undefined };
    });
}

export async function importProject(config, project, adapter, dependencies = {}) {
    // Stormworks側XMLを直接アダプターへ渡さず、処理開始時点のスナップショットを
    // 一時領域へ固定する。ゲーム側で同時に保存されても、同期途中で入力が変わらない。
    const source = path.join(config.stormworksDir, project.stormworksFile);
    if (!fs.existsSync(source)) throw new Error(`Stormworks XML not found: ${source}`);
    const projectPath = project.projectJsonPath;
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "stormworks-import-"));
    const importedXml = path.join(tempRoot, project.stormworksFile);
    try {
        fs.copyFileSync(source, importedXml);
        // 実際の同期・差分表示・atomicな適用はstorm-mclアダプターの責務。
        // この層は入出力場所と確認関数だけを渡す。
        return await adapter.importXml({
            xmlPath: importedXml,
            projectPath,
            confirm: dependencies.confirm ?? confirmOverwrite,
        });
    } finally {
        fs.rmSync(tempRoot, { recursive: true, force: true });
    }
}
