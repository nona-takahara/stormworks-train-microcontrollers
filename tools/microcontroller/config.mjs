import fs from "node:fs";
import path from "node:path";

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

export function loadConfiguration(repoRoot, options = {}) {
    const fsApi = options.fs ?? fs;
    const pathApi = options.path ?? path;
    const envPath = pathApi.join(repoRoot, ".env");
    if (!fsApi.existsSync(envPath)) throw new Error(`Missing required file: ${envPath}`);

    // .envは必須だが、呼出側が明示した値は後勝ちにする。通常利用では使わず、
    // 将来GUI等から呼ぶ場合にも設定読込処理を再実装しないための注入口である。
    const envValues = { ...parseEnv(fsApi.readFileSync(envPath, "utf8")), ...options.environment };
    const stormworksDir = requiredAbsoluteDirectory("STORMWORKS_MICROPROCESSORS_DIR", envValues, fsApi, pathApi);
    const backupDir = requiredAbsoluteDirectory("STORMWORKS_BACKUP_DIR", envValues, fsApi, pathApi);
    // Stormworksの現用保存領域内だけは、ゲーム側の削除や置換に巻き込まれて
    // バックアップにならないため拒否する。リポジトリ内の.gitignore済み領域は許可する。
    if (isWithin(backupDir, stormworksDir, pathApi)) {
        throw new Error("STORMWORKS_BACKUP_DIR must be outside the Stormworks microprocessors directory");
    }

    return { repoRoot, stormworksDir, backupDir };
}
