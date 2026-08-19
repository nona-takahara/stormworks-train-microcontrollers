import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { buildLua } from "./lua-build.mjs";

// Windowsでファイル名に使えない":"を避けたISO時刻。バックアップを対象名と
// 時刻だけで追跡でき、同名を黙って上書きしない構成にする。
function timestamp(date = new Date()) {
    return date.toISOString().replace(/[:.]/gu, "-");
}

export async function confirmOverwrite(message, io = {}) {
    const input = io.input ?? stdin;
    const output = io.output ?? stdout;
    // CIやリダイレクト下で既定値が承認扱いになる事故を避ける。
    // 自動上書き用のforceフラグは、この小規模ツールでは意図的に用意しない。
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
    // deploy成果物はリポジトリ内のscriptsへ直接戻さない。export用に複製した
    // DSLツリーだけを書き換え、再インポート側とLuaビルド側の書込先を分離する。
    for (const build of project.luaBuilds) {
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

function installWithRollback(generatedXml, destination, backup, fsApi = fs) {
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

export async function exportProject(config, project, adapter, dependencies = {}) {
    // exportは「Lua生成→一時DSLへ差替え→DSL検査→XML生成→利用者確認→配置」の順。
    // Stormworks側へ触るのは全生成・検査が成功した後だけにする。
    buildProject(config, project, dependencies);
    const sourceProject = path.resolve(config.repoRoot, project.project);
    if (!fs.existsSync(sourceProject)) throw new Error(`Project file not found: ${sourceProject}`);
    const sourceRoot = path.dirname(sourceProject);
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "stormworks-export-"));
    const stagedRoot = path.join(tempRoot, "project");
    const generatedXml = path.join(tempRoot, project.stormworksFile);
    try {
        // project.jsonと相対参照される.sw-net/scriptsを一体で扱うため、
        // project.json単体ではなく所属ディレクトリ全体を複製する。
        fs.cpSync(sourceRoot, stagedRoot, { recursive: true });
        copyOverlays(config, project, stagedRoot);
        const stagedProject = path.join(stagedRoot, path.basename(sourceProject));
        adapter.check(stagedProject);
        adapter.exportXml(stagedProject, generatedXml);
        if (!fs.existsSync(generatedXml)) throw new Error(`storm-mcl did not create XML: ${generatedXml}`);

        const destination = path.join(config.stormworksDir, project.stormworksFile);
        // 内容が同じなら確認もバックアップも不要。mtimeだけを変える書込みを避ける。
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
        // XML生成や確認が失敗・拒否された場合も、一時DSLとLua差替えを残さない。
        fs.rmSync(tempRoot, { recursive: true, force: true });
    }
}

export async function importProject(config, project, adapter, dependencies = {}) {
    // Stormworks側XMLを直接アダプターへ渡さず、処理開始時点のスナップショットを
    // 一時領域へ固定する。ゲーム側で同時に保存されても、同期途中で入力が変わらない。
    const source = path.join(config.stormworksDir, project.stormworksFile);
    if (!fs.existsSync(source)) throw new Error(`Stormworks XML not found: ${source}`);
    const projectPath = path.resolve(config.repoRoot, project.project);
    if (!fs.existsSync(projectPath)) throw new Error(`Project file not found: ${projectPath}`);
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "stormworks-import-"));
    const importedXml = path.join(tempRoot, project.stormworksFile);
    try {
        fs.copyFileSync(source, importedXml);
        // 実際の同期・差分表示・atomicな適用はstorm-mcl #63対応アダプターの責務。
        // この層は入出力場所と確認関数だけを渡し、旧xml2dslへは迂回しない。
        return await adapter.importXml({
            xmlPath: importedXml,
            projectPath,
            confirm: dependencies.confirm ?? confirmOverwrite,
        });
    } finally {
        fs.rmSync(tempRoot, { recursive: true, force: true });
    }
}
