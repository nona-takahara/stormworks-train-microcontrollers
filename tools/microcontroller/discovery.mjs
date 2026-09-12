import fs from "node:fs";
import path from "node:path";

export const BUILD_CONFIG_NAME = "build.json";
export const PROJECT_JSON_NAME = "project.json";

const IGNORED_DIRECTORY_NAMES = new Set(["node_modules", ".git", ".backup", ".claude"]);

function toProjectId(repoRoot, directory, pathApi) {
    return pathApi.relative(repoRoot, directory).split(pathApi.sep).join("/");
}

function readBuildJson(buildJsonPath, fsApi) {
    let raw;
    try {
        raw = JSON.parse(fsApi.readFileSync(buildJsonPath, "utf8"));
    } catch (error) {
        throw new Error(`Invalid JSON in ${buildJsonPath}: ${error.message}`);
    }
    const stormworksFile = raw?.stormworksFile;
    if (typeof stormworksFile !== "string" || !stormworksFile.endsWith(".xml") ||
        path.basename(stormworksFile) !== stormworksFile) {
        throw new Error(`${buildJsonPath}: stormworksFile must be an XML file name without directories`);
    }
    return stormworksFile;
}

function walk(directory, repoRoot, fsApi, pathApi, results) {
    const entries = fsApi.readdirSync(directory, { withFileTypes: true });
    const buildJsonPath = pathApi.join(directory, BUILD_CONFIG_NAME);
    if (fsApi.existsSync(buildJsonPath)) {
        const projectJsonPath = pathApi.join(directory, PROJECT_JSON_NAME);
        if (!fsApi.existsSync(projectJsonPath)) {
            throw new Error(`${buildJsonPath} has no sibling ${PROJECT_JSON_NAME}`);
        }
        results.push({
            id: toProjectId(repoRoot, directory, pathApi),
            directory,
            projectJsonPath,
            buildJsonPath,
            stormworksFile: readBuildJson(buildJsonPath, fsApi),
        });
    }
    // build.jsonの有無に関わらず子ディレクトリは辿る。プロジェクトディレクトリの
    // 中(src/やdeploy/)にはbuild.jsonがないので何も追加されずに終わるだけである。
    for (const entry of entries) {
        if (!entry.isDirectory() || IGNORED_DIRECTORY_NAMES.has(entry.name)) continue;
        walk(pathApi.join(directory, entry.name), repoRoot, fsApi, pathApi, results);
    }
}

export function discoverProjects(repoRoot, options = {}) {
    const fsApi = options.fs ?? fs;
    const pathApi = options.path ?? path;
    const results = [];
    walk(repoRoot, repoRoot, fsApi, pathApi, results);
    return results;
}

export function selectProjects(projects, ids, all) {
    // 「指定なし＝全件」にはしない。対象追加が既存の手順の作用範囲を変えないことを
    // 優先し、全件操作には--allという明示的な意思表示を要求する。
    if (all && ids.length > 0) throw new Error("Do not combine project ids with --all");
    if (!all && ids.length === 0) throw new Error("Specify at least one project id, or use --all");
    const byId = new Map(projects.map((project) => [project.id, project]));
    if (all) {
        return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
    }
    const seen = new Set();
    return ids.map((id) => {
        const normalized = id.split(/[\\/]/u).join("/").replace(/\/+$/u, "");
        if (seen.has(normalized)) throw new Error(`Project specified more than once: ${normalized}`);
        seen.add(normalized);
        if (!byId.has(normalized)) throw new Error(`Unknown project: ${normalized}`);
        return byId.get(normalized);
    });
}
