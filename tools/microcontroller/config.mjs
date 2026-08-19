import fs from "node:fs";
import path from "node:path";

// 実際の対象一覧にはPC固有のファイル名や運用中のマイコンが含まれるため、
// サンプルとは分けてGit管理外に置く。
export const LOCAL_CONFIG_NAME = "microcontrollers.local.json";

function parseEnv(text) {
    // 外部パッケージを増やさず、今回必要なKEY=VALUEだけを読む小さな.envパーサー。
    // shell展開や変数参照は意図的に扱わない。
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
    // 作業ディレクトリに依存した誤配置を避けるため、入出力先は絶対パスに限定する。
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
    // 設定に誤りがあっても、Luaの生成・overlayがリポジトリ外へ出ないようにする。
    if (typeof value !== "string" || !value || path.isAbsolute(value) || value.split(/[\\/]/u).includes("..")) {
        throw new Error(`${label} must be a non-empty repository-relative path`);
    }
}

function validateProject(name, project) {
    // 設定エラーはファイル操作を始める前にまとめて検出する。各操作側が不完全な
    // 設定を補完し始めると、コマンドごとに解釈が分かれるためである。
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
    // luaBuildsは一つのマイコンに複数あるLuaノードを独立に生成するための宣言。
    // overlayは実ファイルの書込先ではなく、export用一時ツリー内の差替え先である。
    for (const [index, build] of builds.entries()) {
        const prefix = `projects.${name}.luaBuilds[${index}]`;
        assertRelativeRepoPath(build.entry, `${prefix}.entry`);
        assertRelativeRepoPath(build.output, `${prefix}.output`);
        assertRelativeRepoPath(build.overlay, `${prefix}.overlay`);
        if (build.stage !== undefined && !Array.isArray(build.stage)) {
            throw new Error(`${prefix}.stage must be an array`);
        }
        // storm-lua-minifyはentryの親方向を探索できないため、共有Luaだけを
        // entry直下へ一時コピーする。asを単一ファイル名に限るのはそのため。
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

    // .envは必須だが、呼出側が明示した値は後勝ちにする。通常利用では使わず、
    // 将来GUI等から呼ぶ場合にも設定読込処理を再実装しないための注入口である。
    const envValues = { ...parseEnv(fsApi.readFileSync(envPath, "utf8")), ...options.environment };
    const stormworksDir = requiredAbsoluteDirectory("STORMWORKS_MICROPROCESSORS_DIR", envValues, fsApi, pathApi);
    const backupDir = requiredAbsoluteDirectory("STORMWORKS_BACKUP_DIR", envValues, fsApi, pathApi);
    // バックアップを同じ管理領域へ置くと、リポジトリ整理やStormworks側の削除に
    // 巻き込まれる。復旧経路として独立させるため、両方の外側を要求する。
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
    // 対象名はCLI引数やバックアップのディレクトリ名にも使う。空白や区切り文字を
    // 許すより、シェルから安定して指定できる短い識別子へ制限する。
    const projects = Object.fromEntries(Object.entries(raw.projects).map(([name, value]) => {
        if (!/^[a-z0-9][a-z0-9_-]*$/u.test(name)) {
            throw new Error(`Invalid project name: ${name}`);
        }
        return [name, validateProject(name, value)];
    }));
    return { repoRoot, stormworksDir, backupDir, projects };
}

export function selectProjects(projects, names, all) {
    // 「指定なし＝全件」にはしない。対象追加が既存の手順の作用範囲を変えないことを
    // 優先し、全件操作には--allという明示的な意思表示を要求する。
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
