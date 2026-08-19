import fs from "node:fs";
import path from "node:path";
import { run } from "./process.mjs";

const LIMIT = 8192;

function removeIfExists(file) {
    if (fs.existsSync(file)) fs.rmSync(file);
}

export function buildLua(repoRoot, build, options = {}) {
    const runProcess = options.run ?? run;
    const minifyCli = options.minifyCli ?? path.join(repoRoot, "node_modules", "storm-lua-minify", "dist", "cli.js");
    if (!fs.existsSync(minifyCli)) throw new Error(`storm-lua-minify CLI not found: ${minifyCli}`);

    const entry = path.resolve(repoRoot, build.entry);
    const output = path.resolve(repoRoot, build.output);
    if (!fs.existsSync(entry)) throw new Error(`Lua entry not found: ${entry}`);
    const entryDir = path.dirname(entry);
    const stem = path.basename(entry, path.extname(entry));
    const generated = path.join(entryDir, `${stem}.min.lua`);
    const generatedMap = path.join(entryDir, `${path.basename(entry)}.map`);
    const outputMap = `${output}.map`;
    const staged = [];

    fs.mkdirSync(path.dirname(output), { recursive: true });
    for (const item of build.stage ?? []) {
        const source = path.resolve(repoRoot, item.source);
        const destination = path.join(entryDir, item.as);
        if (!fs.existsSync(source)) throw new Error(`Lua stage source not found: ${source}`);
        if (fs.existsSync(destination)) throw new Error(`Refusing to overwrite staged path: ${destination}`);
        fs.copyFileSync(source, destination);
        staged.push(destination);
    }

    try {
        removeIfExists(generated);
        removeIfExists(generatedMap);
        runProcess(process.execPath, [minifyCli, entry], { cwd: repoRoot });
        if (!fs.existsSync(generated)) throw new Error(`Minifier did not create expected output: ${generated}`);
        const size = fs.readFileSync(generated, "utf8").length;
        if (size > LIMIT) throw new Error(`Lua output exceeds ${LIMIT} characters (${size}): ${build.output}`);
        removeIfExists(output);
        removeIfExists(outputMap);
        fs.renameSync(generated, output);
        if (fs.existsSync(generatedMap)) fs.renameSync(generatedMap, outputMap);
        return { output, size };
    } finally {
        removeIfExists(generated);
        removeIfExists(generatedMap);
        for (const file of staged) removeIfExists(file);
    }
}
