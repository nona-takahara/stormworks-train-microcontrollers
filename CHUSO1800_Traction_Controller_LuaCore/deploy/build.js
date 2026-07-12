// Builds the single Stormworks-pasteable script for the CHUSO1800 traction
// controller.
//
// storm-lua-minify only resolves dofile(...)/require(...) targets by
// descending from the ENTRY file's own directory -- it has no ".."
// support (verified empirically against storm-lua-minify 0.1.3; see
// main.lua's header comment and DESIGN_LOG.md #12). ../../lib/state_sync.lua
// and ../src/chuso1800_core.lua are siblings of this deploy/ directory, not
// descendants of it, so they can't be referenced directly. This script
// stages temporary copies of both as direct siblings of main.lua before
// running storm-lua-minify, then removes the copies afterward -- the
// staged files are never committed (see .gitignore).
//
// Written in Node.js (not a shell script) so it runs the same way on
// Windows as anywhere else.
//
// Usage: node build.js   (run from anywhere -- all paths below are
// resolved relative to this script's own location, not the working
// directory)

import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, renameSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../..");

const stateSyncSrc = path.join(repoRoot, "lib", "state_sync.lua");
const coreSrc = path.join(here, "..", "src", "chuso1800_core.lua");
const stateSyncStaged = path.join(here, "state_sync.lua");
const coreStaged = path.join(here, "chuso1800_core.lua");
const entry = path.join(here, "main.lua");
const minifyCli = path.join(repoRoot, "node_modules", "storm-lua-minify", "dist", "cli.js");
const output = path.join(here, "chuso1800_deploy.lua");
const outputMap = path.join(here, "chuso1800_deploy.lua.map");

function removeIfExists(filePath) {
    if (existsSync(filePath)) rmSync(filePath);
}

function cleanupStaged() {
    removeIfExists(stateSyncStaged);
    removeIfExists(coreStaged);
}

if (!existsSync(minifyCli)) {
    console.error(
        `storm-lua-minify not found at ${minifyCli}\n` +
        "Run `npm install` (it's a devDependency of the repo root package.json) first."
    );
    process.exit(1);
}

cleanupStaged();
copyFileSync(stateSyncSrc, stateSyncStaged);
copyFileSync(coreSrc, coreStaged);

try {
    // No -m (module-like-lua) flag: neither state_sync.lua nor
    // chuso1800_core.lua is require()'d -- both are plain dofile()'d,
    // non-module files (see main.lua's header comment and DESIGN_LOG.md
    // #15). storm-lua-minify's `-m` mode only matters for require(); with
    // nothing require()'d, plain mode and `-m` mode produce the same
    // output for this build, so plain mode is used to avoid emitting an
    // unused require() dispatcher.
    execFileSync(process.execPath, [minifyCli, entry], { stdio: "inherit" });
} finally {
    cleanupStaged();
}

const generated = path.join(here, "main.min.lua");
const generatedMap = path.join(here, "main.lua.map");
removeIfExists(output);
removeIfExists(outputMap);
renameSync(generated, output);
if (existsSync(generatedMap)) renameSync(generatedMap, outputMap);

console.log(`Wrote ${path.relative(repoRoot, output)}`);
