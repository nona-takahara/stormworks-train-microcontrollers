#!/usr/bin/env node
// Teinishi/soya_chuso_train_vehicle の route_data.json を取得し、コミットSHAを
// 固定してこのリポジトリ内にスナップショットとして保存する。
//
// 「乖離した独自複製」を避けるため、常に最新のHEADではなく、取得時点の
// コミットSHAを route_data.snapshot.meta.json に記録する（ロックファイルに
// 近い性質）。route_data.jsonの内容自体はTeinishi氏が更新を担当している
// ため（EXTERNAL_SOURCE_NOTES.md参照）、そのまま採用してよい。
//
// 使い方: node tools/route-data-sync/fetch.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const OWNER = "Teinishi";
const REPO = "soya_chuso_train_vehicle";
const BRANCH = "main";
const SOURCE_PATH = "route_data.json";

const here = path.dirname(fileURLToPath(import.meta.url));
const vendorDir = path.join(here, "vendor");
const snapshotPath = path.join(vendorDir, "route_data.snapshot.json");
const metaPath = path.join(vendorDir, "route_data.snapshot.meta.json");

function authHeaders() {
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
  const headers = { Accept: "application/vnd.github+json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

async function resolveCommitSha() {
  const url = `https://api.github.com/repos/${OWNER}/${REPO}/commits/${BRANCH}`;
  const res = await fetch(url, { headers: authHeaders() });
  if (!res.ok) {
    throw new Error(`failed to resolve HEAD commit for ${OWNER}/${REPO}@${BRANCH}: ${res.status} ${res.statusText}`);
  }
  const json = await res.json();
  return json.sha;
}

async function fetchFileAtCommit(sha) {
  const url = `https://raw.githubusercontent.com/${OWNER}/${REPO}/${sha}/${SOURCE_PATH}`;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`failed to fetch ${SOURCE_PATH} at ${sha}: ${res.status} ${res.statusText}`);
  }
  return res.text();
}

async function main() {
  const sha = await resolveCommitSha();
  console.error(`resolved ${OWNER}/${REPO}@${BRANCH} -> ${sha}`);

  const text = await fetchFileAtCommit(sha);
  // JSONとして妥当か検証してから書き出す(壊れたスナップショットを残さない)。
  JSON.parse(text);

  fs.mkdirSync(vendorDir, { recursive: true });
  fs.writeFileSync(snapshotPath, text);

  const meta = {
    source: `https://github.com/${OWNER}/${REPO}`,
    path: SOURCE_PATH,
    branch: BRANCH,
    commit: sha,
    fetchedAt: new Date().toISOString(),
  };
  fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2) + "\n");

  console.error(`wrote ${path.relative(process.cwd(), snapshotPath)}`);
  console.error(`wrote ${path.relative(process.cwd(), metaPath)}`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
