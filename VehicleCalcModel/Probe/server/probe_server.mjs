#!/usr/bin/env node
// Receiving end of the vehicle probe (src/probe.lua).
//   GET  /l?d=&r=   from Stormworks: append the records to the CSV, reply with
//                   the next queued command line ("0" when none).
//   POST /ctl       body = one command line (see src/probe.lua); queued.
//   GET  /state     JSON: last record, queue, time since the last request.
// A record with state 3 (cannot continue) triggers one Discord notification, sent to
// PROBE_WEBHOOK_URL from the repository's .env (git-ignored). Without it, nothing is sent.
// When no request has arrived for 5 minutes after the first one (the game closed or the script
// stopped), the same webhook gets one "silent" notification; the next request re-arms it.
// Usage: node probe_server.mjs [port] [log.csv]
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const HEADER = "recv_ms,dropped,t,x,y,z,v,motor,brake,batt,state,reason,slip,aux1,aux2";

export function createServer(logPath, notify = () => {}, silenceMs = 5 * 60 * 1000) {
    fs.mkdirSync(path.dirname(logPath), { recursive: true });
    if (!fs.existsSync(logPath)) fs.writeFileSync(logPath, HEADER + "\n");
    const queue = [];
    let last = null, lastSeen = null, notified = false, silent = false;

    const server = http.createServer((req, res) => {
        const url = new URL(req.url, "http://localhost");
        const send = (body, type = "text/plain") => { res.writeHead(200, { "content-type": type }); res.end(body); };
        if (req.method === "GET" && url.pathname === "/l") {
            const now = Date.now();
            const dropped = url.searchParams.get("d") ?? "0";
            const rows = (url.searchParams.get("r") ?? "").split(";").filter(Boolean);
            fs.appendFileSync(logPath, rows.map((r) => `${now},${dropped},${r}${",".repeat(Math.max(0, 13 - r.split(",").length))}`).join("\n") + (rows.length ? "\n" : ""));
            if (rows.length) last = rows[rows.length - 1];
            const fallen = rows.find((r) => r.split(",")[8] === "3");
            if (fallen && !notified) { notified = true; notify(fallen); }
            lastSeen = now;
            silent = false;
            send(queue.shift() ?? "0");
        } else if (req.method === "POST" && url.pathname === "/ctl") {
            let body = "";
            req.on("data", (c) => { body += c; });
            req.on("end", () => { queue.push(body.trim()); send(`queued ${queue.length}`); });
        } else if (req.method === "GET" && url.pathname === "/state") {
            const f = last?.split(",") ?? [];
            const [t, x, y, z, v, motor, brake, batt, state, reason] = f.map(Number);
            send(JSON.stringify({
                last: last ? { t, x, y, z, v, motor, brake, batt, state, reason } : null,
                queue: [...queue], sinceLastRequestMs: lastSeen === null ? null : Date.now() - lastSeen,
            }), "application/json");
        } else {
            res.writeHead(404); res.end();
        }
    });
    // no request for `silenceMs`: tell once (notify gets the last record, or "")
    const watch = setInterval(() => {
        if (lastSeen !== null && !silent && Date.now() - lastSeen > silenceMs) { silent = true; notify(last ?? "", "silent"); }
    }, Math.min(30000, Math.max(50, silenceMs / 4)));
    watch.unref();
    return server;
}

function discordNotifier(url) {
    return (row, kind) => {
        const [t, x, y, z, v] = row.split(",");
        const content = kind === "silent"
            ? `車両プローブ: 5 分以上リクエストが途絶えました (ゲームが閉じたか、スクリプトが止まった可能性)。最後の記録 t=${t} x=${x} v=${v}`
            : `車両プローブ: 続行不能 (y が急に下がった)。t=${t} x=${x} y=${y} z=${z} v=${v}`;
        fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ content }) })
            .then((r) => { if (!r.ok) console.error(`webhook failed: ${r.status}`); })
            .catch((e) => console.error(`webhook failed: ${e.message}`));
    };
}

function webhookUrl(here) {
    try {
        const env = fs.readFileSync(path.join(here, "../../../.env"), "utf8");
        return /^PROBE_WEBHOOK_URL\s*=\s*(\S+)/mu.exec(env)?.[1];
    } catch { return undefined; }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    const port = Number(process.argv[2] ?? 8765);
    const logPath = process.argv[3] ?? path.join(path.dirname(fileURLToPath(import.meta.url)), "../data/log.csv");
    const url = webhookUrl(path.dirname(fileURLToPath(import.meta.url)));
    if (!url) console.warn("PROBE_WEBHOOK_URL is not set in .env: no notification will be sent");
    createServer(logPath, url ? discordNotifier(url) : undefined).listen(port, "0.0.0.0", () => console.log(`probe server on :${port}, log ${logPath}`));
}
