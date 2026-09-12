import fs from "node:fs";
import path from "node:path";
import { run } from "./process.mjs";

// StormworksのLuaノードへ保存できるスクリプト長。バイト数ではなく、ゲーム側の
// 制限と既存運用に合わせてJavaScript文字列の文字数で判定する。
const LIMIT = 8192;

function removeIfExists(file) {
    if (fs.existsSync(file)) fs.rmSync(file);
}

function copyDirectoryFilesInto(sourceDir, destinationDir, fsApi, staged, { skipIfExists } = {}) {
    if (!fsApi.existsSync(sourceDir)) return;
    for (const entry of fsApi.readdirSync(sourceDir, { withFileTypes: true })) {
        if (!entry.isFile()) continue;
        const destination = path.join(destinationDir, entry.name);
        if (skipIfExists && fsApi.existsSync(destination)) continue;
        fsApi.copyFileSync(path.join(sourceDir, entry.name), destination);
        staged.push(destination);
    }
}

export function buildLua(repoRoot, build, options = {}) {
    // storm-lua-minifyのCLIを直接起動する。pnpm経由にしないことで、Windowsでも
    // 引数の再解釈やshell依存を挟まず、同じNodeランタイムを使える。
    const fsApi = options.fs ?? fs;
    const runProcess = options.run ?? run;
    const minifyCli = options.minifyCli ?? path.join(repoRoot, "node_modules", "storm-lua-minify", "dist", "cli.js");
    // ソース側の--@storm exportに加え、対応前のminifierでもコールバック名を
    // 保護する。どちらか一方の欠落でVehicle Luaが無言で停止しないための二重化。
    const reservedGlobals = options.reservedGlobals ?? path.join(
        repoRoot, "tools", "microcontroller", "stormworks-reserved-globals.json",
    );
    const libDir = options.libDir ?? path.join(repoRoot, "lib");
    if (!fsApi.existsSync(minifyCli)) throw new Error(`storm-lua-minify CLI not found: ${minifyCli}`);
    if (!fsApi.existsSync(reservedGlobals)) throw new Error(`Reserved globals config not found: ${reservedGlobals}`);

    const entry = path.resolve(repoRoot, build.entry);
    const output = path.resolve(repoRoot, build.output);
    if (!fsApi.existsSync(entry)) throw new Error(`Lua entry not found: ${entry}`);
    const srcDir = path.dirname(entry);
    const deployDir = path.dirname(output);
    // minifierはentryの親方向を参照できないため、entryとその依存物一式を
    // 生成物専用のdeployDirへコピーしてからそこで実行する。src/は読み取り専用のまま。
    const entryCopy = path.join(deployDir, path.basename(entry));
    const stem = path.basename(entryCopy, path.extname(entryCopy));
    const generated = path.join(deployDir, `${stem}.min.lua`);
    const generatedMap = path.join(deployDir, `${path.basename(entryCopy)}.map`);
    const outputMap = `${output}.map`;
    const staged = [];

    fsApi.mkdirSync(deployDir, { recursive: true });
    // entry自身とその兄弟(同じプロジェクトのsrc/配下)は、実行のたびに作り直す
    // 一時コピーなので無条件に上書きする。
    copyDirectoryFilesInto(srcDir, deployDir, fsApi, staged);
    // 共有ライブラリはsrc側と同名なら上書きしない(src側優先。何もしない=stagedに
    // 加えない=finallyで消さない、なので既存のプロジェクト固有ファイルは無傷)。
    copyDirectoryFilesInto(libDir, deployDir, fsApi, staged, { skipIfExists: true });

    try {
        // 前回異常終了時のminifier中間物は入力として信用せず、毎回作り直す。
        removeIfExists(generated);
        removeIfExists(generatedMap);
        runProcess(process.execPath, [
            minifyCli, entryCopy, "--config", reservedGlobals,
        ], { cwd: repoRoot });
        if (!fsApi.existsSync(generated)) throw new Error(`Minifier did not create expected output: ${generated}`);
        const size = fsApi.readFileSync(generated, "utf8").length;
        if (size > LIMIT) throw new Error(`Lua output exceeds ${LIMIT} characters (${size}): ${build.output}`);
        // サイズ検査まで成功したものだけを正式なdeploy成果物へ昇格させる。
        // mapもLua本体と同じ基底名に揃え、生成元を後から追跡できるようにする。
        removeIfExists(output);
        removeIfExists(outputMap);
        fsApi.renameSync(generated, output);
        if (fsApi.existsSync(generatedMap)) fsApi.renameSync(generatedMap, outputMap);
        return { output, size };
    } finally {
        // 成否に関係なく、生成途中のファイルと一時コピーはdeploy側へ残さない。
        // output/outputMapはstagedに入っていないため、ここでは消えない。
        removeIfExists(generated);
        removeIfExists(generatedMap);
        for (const file of staged) removeIfExists(file);
    }
}
