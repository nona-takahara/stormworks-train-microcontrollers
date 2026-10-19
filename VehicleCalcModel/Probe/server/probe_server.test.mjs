// `node --test server/probe_server.test.mjs` : request/reply contract of probe_server.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createServer, HEADER } from "./probe_server.mjs";

test("log rows are appended, queued commands are returned once, state is reported", async () => {
    const log = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "probe-")), "log.csv");
    const server = createServer(log);
    await new Promise((r) => server.listen(0, "127.0.0.1", r));
    const base = `http://127.0.0.1:${server.address().port}`;
    const text = async (u, o) => (await fetch(base + u, o)).text();

    await text("/ctl", { method: "POST", body: "2" });
    const rec = "10,5.00,1.0,2.0,3.000,0.100,0.000,0.950,1,0";
    assert.equal(await text(`/l?d=0&r=${rec};11,6.00,1.0,2.0,3.000,0.100,0.000,0.950,1,0`), "2");
    assert.equal(await text("/l?d=3&r="), "0");

    const rows = fs.readFileSync(log, "utf8").trim().split("\n");
    assert.equal(rows[0], HEADER);
    assert.equal(rows.length, 3);
    assert.ok(rows[1].includes(`,0,${rec},`)); // short (older) rows are padded to the full column count
    const state = JSON.parse(await text("/state"));
    assert.equal(state.last.t, 11);
    assert.deepEqual(state.queue, []);
    server.close();
});

test("state 3 is notified once", async () => {
    const log = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "probe-")), "log.csv");
    const sent = [];
    const server = createServer(log, (row) => sent.push(row));
    await new Promise((r) => server.listen(0, "127.0.0.1", r));
    const base = `http://127.0.0.1:${server.address().port}`;
    const fell = "20,5.00,1.0,2.0,3.000,0,1,0.950,3,4";
    await fetch(`${base}/l?d=0&r=10,5.00,1.0,2.0,3.000,0,0,0.950,0,0`);
    assert.equal(sent.length, 0);
    await fetch(`${base}/l?d=0&r=${fell}`);
    await fetch(`${base}/l?d=0&r=${fell}`);
    assert.deepEqual(sent, [fell]);
    server.close();
});

test("a silent probe is notified once and re-armed by the next request", async () => {
    const log = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "probe-")), "log.csv");
    const sent = [];
    const server = createServer(log, (row, kind) => sent.push(kind ?? "fallen"), 200);
    await new Promise((r) => server.listen(0, "127.0.0.1", r));
    const base = `http://127.0.0.1:${server.address().port}`;
    await fetch(`${base}/l?d=0&r=10,5.00,1.0,2.0,3.000,0,0,0.950,0,0`);
    await new Promise((r) => setTimeout(r, 600));
    assert.deepEqual(sent, ["silent"]);
    await new Promise((r) => setTimeout(r, 400));
    assert.deepEqual(sent, ["silent"]);          // not repeated
    await fetch(`${base}/l?d=0&r=20,5.00,1.0,2.0,3.000,0,0,0.950,0,0`);
    await new Promise((r) => setTimeout(r, 600));
    assert.deepEqual(sent, ["silent", "silent"]); // re-armed
    server.close();
});
