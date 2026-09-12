import fs from "node:fs";
import path from "node:path";
import {
    loadProjectSourceFromProjectJsonFile,
    resolveProjectSource,
    createFileSystemProjectSourceDocumentLoader,
    flattenSwNetProject,
    hasErrorDiagnostics,
    formatDiagnostics,
    resolveRelativeSwNetAssetPath,
} from "storm-microcontroller-language/node";

const DEPLOY_SUFFIX = /_deploy$/u;

// script_refはLuaノードの最終成果物の置き場所であり、entry(手書きソース)の名前とは
// 独立に選ばれている場合がある(例: deploy/chuso1800_deploy.lua)。拡張子と生成物の
// サフィックスを取り除いた残りを、src/配下を探すための候補名として使う。
export function deriveCandidateName(scriptRef) {
    const stem = path.basename(scriptRef, path.extname(scriptRef));
    return stem.replace(DEPLOY_SUFFIX, "");
}

function assertOk(result, contextPath) {
    if (hasErrorDiagnostics(result.diagnostics) || !result.value) {
        throw new Error(`Failed to resolve project graph for ${contextPath}:\n${formatDiagnostics(result.diagnostics)}`);
    }
    return result.value;
}

export async function resolveLuaBuilds(repoRoot, project, options = {}) {
    const loadSource = options.loadProjectSourceFromProjectJsonFile ?? loadProjectSourceFromProjectJsonFile;
    const resolveSource = options.resolveProjectSource ?? resolveProjectSource;
    const flatten = options.flattenSwNetProject ?? flattenSwNetProject;
    const createLoader = options.createFileSystemProjectSourceDocumentLoader ?? createFileSystemProjectSourceDocumentLoader;
    const resolveAssetPath = options.resolveRelativeSwNetAssetPath ?? resolveRelativeSwNetAssetPath;
    const fsApi = options.fs ?? fs;
    const log = options.log ?? console.log;

    const projectSource = assertOk(await loadSource(project.projectJsonPath), project.projectJsonPath);
    const resolved = assertOk(
        await resolveSource(projectSource, { loadImportedDocument: createLoader() }),
        project.projectJsonPath,
    );
    const flattened = assertOk(
        flatten(resolved.swNet, { entryModuleId: projectSource.entryModuleId }),
        project.projectJsonPath,
    );

    const usedNames = new Map(); // name -> instanceId、管理対象同士の衝突検出用
    const builds = [];
    for (const statement of flattened.module.statements) {
        if (statement.kind !== "inst" || statement.typeId !== "LUA") continue;
        const scriptRefAttribute = statement.attributes.find(
            (attribute) => attribute.key === "script_ref" && attribute.value.kind === "string",
        );
        const scriptRef = scriptRefAttribute?.value.value;
        if (!scriptRef) continue;

        const name = deriveCandidateName(scriptRef);
        const entryAbsolute = path.join(project.directory, "src", `${name}.lua`);
        if (!fsApi.existsSync(entryAbsolute)) {
            log(`[${project.id}] LUA node "${statement.instanceId}" (script_ref=${scriptRef}) has no src/${name}.lua; not managed by the build pipeline`);
            continue;
        }

        if (usedNames.has(name)) {
            throw new Error(
                `[${project.id}] Lua name collision: instances "${usedNames.get(name)}" and "${statement.instanceId}" both derive name "${name}" from their script_ref`,
            );
        }
        usedNames.set(name, statement.instanceId);

        const declaringDocumentPath = flattened.documentPathByInstanceId[statement.instanceId];
        const overlayAbsolute = resolveAssetPath(declaringDocumentPath, scriptRef);
        const overlay = path.relative(project.directory, overlayAbsolute);
        if (overlay.startsWith("..") || path.isAbsolute(overlay)) {
            throw new Error(`[${project.id}] script_ref escapes project directory for "${statement.instanceId}": ${scriptRef}`);
        }

        builds.push({
            entry: path.relative(repoRoot, entryAbsolute),
            output: path.relative(repoRoot, path.join(project.directory, "deploy", `${name}_deploy.lua`)),
            overlay,
        });
    }
    return builds;
}
