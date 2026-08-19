import fs from "node:fs";
import path from "node:path";
import { run } from "./process.mjs";

// StormworksのLuaノードへ保存できるスクリプト長。バイト数ではなく、ゲーム側の
// 制限と既存運用に合わせてJavaScript文字列の文字数で判定する。
const LIMIT = 8192;

function removeIfExists(file) {
    if (fs.existsSync(file)) fs.rmSync(file);
}

export function buildLua(repoRoot, build, options = {}) {
    // storm-lua-minifyのCLIを直接起動する。pnpm経由にしないことで、Windowsでも
    // 引数の再解釈やshell依存を挟まず、同じNodeランタイムを使える。
    const runProcess = options.run ?? run;
    const minifyCli = options.minifyCli ?? path.join(repoRoot, "node_modules", "storm-lua-minify", "dist", "cli.js");
    if (!fs.existsSync(minifyCli)) throw new Error(`storm-lua-minify CLI not found: ${minifyCli}`);

    const entry = path.resolve(repoRoot, build.entry);
    const output = path.resolve(repoRoot, build.output);
    if (!fs.existsSync(entry)) throw new Error(`Lua entry not found: ${entry}`);
    const entryDir = path.dirname(entry);
    const stem = path.basename(entry, path.extname(entry));
    // minifierの出力名は指定できず、entryの隣に規定名で生成される。
    // いったんその名前を受け、検査後に設定されたdeployパスへ移動する。
    const generated = path.join(entryDir, `${stem}.min.lua`);
    const generatedMap = path.join(entryDir, `${path.basename(entry)}.map`);
    const outputMap = `${output}.map`;
    const staged = [];

    fs.mkdirSync(path.dirname(output), { recursive: true });
    // 親ディレクトリを参照できないminifierの制約を吸収するためのステージング。
    // 既存ファイルは、同名の本物を誤って消さないよう上書きせず停止する。
    for (const item of build.stage ?? []) {
        const source = path.resolve(repoRoot, item.source);
        const destination = path.join(entryDir, item.as);
        if (!fs.existsSync(source)) throw new Error(`Lua stage source not found: ${source}`);
        if (fs.existsSync(destination)) throw new Error(`Refusing to overwrite staged path: ${destination}`);
        fs.copyFileSync(source, destination);
        staged.push(destination);
    }

    try {
        // 前回異常終了時のminifier中間物は入力として信用せず、毎回作り直す。
        removeIfExists(generated);
        removeIfExists(generatedMap);
        runProcess(process.execPath, [minifyCli, entry], { cwd: repoRoot });
        if (!fs.existsSync(generated)) throw new Error(`Minifier did not create expected output: ${generated}`);
        const size = fs.readFileSync(generated, "utf8").length;
        if (size > LIMIT) throw new Error(`Lua output exceeds ${LIMIT} characters (${size}): ${build.output}`);
        // サイズ検査まで成功したものだけを正式なdeploy成果物へ昇格させる。
        // mapもLua本体と同じ基底名に揃え、生成元を後から追跡できるようにする。
        removeIfExists(output);
        removeIfExists(outputMap);
        fs.renameSync(generated, output);
        if (fs.existsSync(generatedMap)) fs.renameSync(generatedMap, outputMap);
        return { output, size };
    } finally {
        // 成否に関係なく、生成途中のファイルと一時依存はentry側へ残さない。
        // deploy成果物は成功時に既に移動済みなので、この後始末の対象外である。
        removeIfExists(generated);
        removeIfExists(generatedMap);
        for (const file of staged) removeIfExists(file);
    }
}
