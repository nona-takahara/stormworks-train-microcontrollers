import fs from "node:fs";
import path from "node:path";

export const LOCAL_CONFIG_NAME = "microcontrollers.local.json";

function parseEnv(text) {
    const values = {};
    for (const rawLine of text.split(/\r?\n/u)) {
        const line = rawLine.trim();
        if (!line || line.startsWith("#")) continue;
        const match = /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/u.exec(line);
        if (!match) throw new Error(`Invalid .env line: ${rawLine}`);
        let value = match[2].trim();
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
            value = value.slice(1, -1);
        }
        values[match[1]] = value;
    }
    return values;
}

function requiredAbsoluteDirectory(name, values, fsApi, pathApi) {
    const value = values[name];
    if (!value) throw new Error(`${name} is required in .env`);
    if (!pathApi.isAbsolute(value)) throw new Error(`${name} must be an absolute path: ${value}`);
    if (!fsApi.existsSync(value) || !fsApi.statSync(value).isDirectory()) {
        throw new Error(`${name} directory does not exist: ${value}`);
    }
    return pathApi.resolve(value);
}

function isWithin(candidate, parent, pathApi) {
    const relative = pathApi.relative(parent, candidate);
    return relative === "" || (!relative.startsWith("..") && !pathApi.isAbsolute(relative));
}

function assertRelativeRepoPath(value, label) {
    if (typeof value !== "string" || !value || path.isAbsolute(value) || value.split(/[\\/]/u).includes("..")) {
        throw new Error(`${label} must be a non-empty repository-relative path`);
    }
}

function validateProject(name, project) {
    if (!project || typeof project !== "object" || Array.isArray(project)) {
        throw new Error(`projects.${name} must be an object`);
    }
    assertRelativeRepoPath(project.project, `projects.${name}.project`);
    if (typeof project.stormworksFile !== "string" || !project.stormworksFile.endsWith(".xml") ||
        path.basename(project.stormworksFile) !== project.stormworksFile) {
        throw new Error(`projects.${name}.stormworksFile must be an XML file name without directories`);
    }
    const builds = project.luaBuilds ?? [];
    if (!Array.isArray(builds)) throw new Error(`projects.${name}.luaBuilds must be an array`);
    for (const [index, build] of builds.entries()) {
        const prefix = `projects.${name}.luaBuilds[${index}]`;
        assertRelativeRepoPath(build.entry, `${prefix}.entry`);
        assertRelativeRepoPath(build.output, `${prefix}.output`);
        assertRelativeRepoPath(build.overlay, `${prefix}.overlay`);
        if (build.stage !== undefined && !Array.isArray(build.stage)) {
            throw new Error(`${prefix}.stage must be an array`);
        }
        for (const [stageIndex, staged] of (build.stage ?? []).entries()) {
            assertRelativeRepoPath(staged.source, `${prefix}.stage[${stageIndex}].source`);
            if (typeof staged.as !== "string" || !staged.as || path.basename(staged.as) !== staged.as) {
                throw new Error(`${prefix}.stage[${stageIndex}].as must be a file name`);
            }
        }
    }
    return { ...project, luaBuilds: builds };
}

export function loadConfiguration(repoRoot, options = {}) {
    const fsApi = options.fs ?? fs;
    const pathApi = options.path ?? path;
    const envPath = pathApi.join(repoRoot, ".env");
    const configPath = pathApi.join(repoRoot, LOCAL_CONFIG_NAME);
    if (!fsApi.existsSync(envPath)) throw new Error(`Missing required file: ${envPath}`);
    if (!fsApi.existsSync(configPath)) throw new Error(`Missing required file: ${configPath}`);

    const envValues = { ...parseEnv(fsApi.readFileSync(envPath, "utf8")), ...options.environment };
    const stormworksDir = requiredAbsoluteDirectory("STORMWORKS_MICROPROCESSORS_DIR", envValues, fsApi, pathApi);
    const backupDir = requiredAbsoluteDirectory("STORMWORKS_BACKUP_DIR", envValues, fsApi, pathApi);
    if (isWithin(backupDir, repoRoot, pathApi) || isWithin(backupDir, stormworksDir, pathApi)) {
        throw new Error("STORMWORKS_BACKUP_DIR must be outside the repository and Stormworks microprocessors directory");
    }

    let raw;
    try {
        raw = JSON.parse(fsApi.readFileSync(configPath, "utf8"));
    } catch (error) {
        throw new Error(`Invalid JSON in ${configPath}: ${error.message}`);
    }
    if (!raw || typeof raw !== "object" || Array.isArray(raw) ||
        !raw.projects || typeof raw.projects !== "object" || Array.isArray(raw.projects)) {
        throw new Error(`${configPath} must contain a projects object`);
    }
    const projects = Object.fromEntries(Object.entries(raw.projects).map(([name, value]) => {
        if (!/^[a-z0-9][a-z0-9_-]*$/u.test(name)) {
            throw new Error(`Invalid project name: ${name}`);
        }
        return [name, validateProject(name, value)];
    }));
    return { repoRoot, stormworksDir, backupDir, projects };
}

export function selectProjects(projects, names, all) {
    if (all && names.length > 0) throw new Error("Do not combine project names with --all");
    if (!all && names.length === 0) throw new Error("Specify at least one project name, or use --all");
    const selectedNames = all ? Object.keys(projects) : names;
    if (selectedNames.length === 0) throw new Error("No projects are configured");
    const seen = new Set();
    return selectedNames.map((name) => {
        if (seen.has(name)) throw new Error(`Project specified more than once: ${name}`);
        seen.add(name);
        if (!Object.hasOwn(projects, name)) throw new Error(`Unknown project: ${name}`);
        return { name, ...projects[name] };
    });
}
