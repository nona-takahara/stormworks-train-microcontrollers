import { spawnSync } from "node:child_process";

export function run(command, args, options = {}) {
    // shellを介さず実行し、設定値やパスがコマンド文字列として再解釈されないようにする。
    // 通常時は子プロセスの進捗をそのまま見せ、結果解析が必要な呼出だけcaptureする。
    const result = spawnSync(command, args, {
        cwd: options.cwd,
        encoding: "utf8",
        stdio: options.capture ? "pipe" : "inherit",
        windowsHide: true,
    });
    // 起動自体の失敗と、起動後の非0終了を分ける。後者はcapture時だけ標準出力を
    // 付加し、通常時に同じエラーを二重表示しない。
    if (result.error) throw result.error;
    if (result.status !== 0) {
        const detail = options.capture ? `\n${result.stderr || result.stdout}` : "";
        throw new Error(`${command} exited with status ${result.status}${detail}`);
    }
    return result;
}
