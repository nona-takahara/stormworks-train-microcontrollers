import { spawnSync } from "node:child_process";

export function run(command, args, options = {}) {
    const result = spawnSync(command, args, {
        cwd: options.cwd,
        encoding: "utf8",
        stdio: options.capture ? "pipe" : "inherit",
        windowsHide: true,
    });
    if (result.error) throw result.error;
    if (result.status !== 0) {
        const detail = options.capture ? `\n${result.stderr || result.stdout}` : "";
        throw new Error(`${command} exited with status ${result.status}${detail}`);
    }
    return result;
}
