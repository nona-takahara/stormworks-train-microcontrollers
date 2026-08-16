// Builds the deploy artifacts for n61.lua / n141.lua from their src/ entry
// files, resolving dofile("route_data_position") / dofile("route_data_arc")
// via storm-lua-minify.
//
// Output intentionally does NOT land at scripts/n61.lua / scripts/n141.lua:
// those two files are written by reimport.sh (pnpm exec storm-mcl xml2dsl),
// which round-trips the Stormworks save XML back into this repo. Writing
// the minified build there too would create two writers for the same path
// -- whichever ran last would silently clobber the other. See
// CHUSO2000_Driver_Assistance_IV/DESIGN_LOG.md #2. Applying deploy/n61_deploy.lua
// / deploy/n141_deploy.lua to scripts/ is a separate, explicit, manual step.
//
// Written in Node.js (not a shell script) so it runs the same way on
// Windows as anywhere else (see LUA_CODING_GUIDE.md).
//
// Usage: node deploy/build.js   (run from anywhere -- all paths below are
// resolved relative to this script's own location, not the working
// directory)

import { execFileSync } from "node:child_process";
import { existsSync, renameSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../..");
const srcDir = path.join(here, "..", "src");
const minifyCli = path.join(repoRoot, "node_modules", "storm-lua-minify", "dist", "cli.js");

const NODES = ["n61", "n141"];

function removeIfExists(filePath) {
    if (existsSync(filePath)) rmSync(filePath);
}

if (!existsSync(minifyCli)) {
    console.error(
        `storm-lua-minify not found at ${minifyCli}\n` +
        "Run `pnpm install` (it's a devDependency of the repo root package.json) first."
    );
    process.exit(1);
}

for (const node of NODES) {
    const entry = path.join(srcDir, `${node}.lua`);
    const output = path.join(here, `${node}_deploy.lua`);
    const outputMap = path.join(here, `${node}_deploy.lua.map`);
    const generated = path.join(srcDir, `${node}.min.lua`);
    const generatedMap = path.join(srcDir, `${node}.lua.map`);

    if (!existsSync(entry)) {
        console.error(`entry not found: ${entry}`);
        process.exit(1);
    }

    // No -m (module-like-lua) flag: route_data_arc.lua / route_data_position.lua
    // are plain dofile()'d, non-module files (global assignments only, no
    // return), matching the repo's dofile-only convention (LUA_CODING_GUIDE.md).
    execFileSync(process.execPath, [minifyCli, entry], { stdio: "inherit" });

    removeIfExists(output);
    removeIfExists(outputMap);
    renameSync(generated, output);
    if (existsSync(generatedMap)) renameSync(generatedMap, outputMap);

    console.log(`Wrote ${path.relative(repoRoot, output)}`);
}
