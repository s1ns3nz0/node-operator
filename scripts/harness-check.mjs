import { readdir, readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';

const root = process.cwd();
const config = JSON.parse(await readFile(path.join(root, 'harness.config.json'), 'utf8'));
const failures = [];
if (config.schemaVersion !== 1) failures.push('schemaVersion must be 1');
for (const tier of ['sol', 'terra', 'luna']) if (!config.models?.tiers?.[tier]?.model) failures.push(`missing model tier: ${tier}`);
for (const file of ['harness/paperthin.lock', 'harness/grill-me.lock']) try { JSON.parse(await readFile(path.join(root, file), 'utf8')); } catch { failures.push(`invalid lock: ${file}`); }
async function graphs(directory) { try { const entries = await readdir(directory, { withFileTypes: true }); return (await Promise.all(entries.map((entry) => entry.isDirectory() ? graphs(path.join(directory, entry.name)) : entry.name === 'graph.json' ? [path.join(directory, entry.name)] : []))).flat(); } catch { return []; } }
const graphFiles = await graphs(path.join(root, config.graphs.directory));
for (const file of graphFiles) { try { const graph = JSON.parse(await readFile(file, 'utf8')); const ids = new Set(graph.nodes?.map((node) => node.id)); if (!graph.task_id || !Array.isArray(graph.nodes) || !Array.isArray(graph.edges) || graph.edges.some((edge) => !ids.has(edge.from) || !ids.has(edge.to))) failures.push(`invalid graph: ${path.relative(root, file)}`); } catch { failures.push(`invalid graph JSON: ${path.relative(root, file)}`); } }
if (failures.length) { failures.forEach((failure) => console.error(`FAIL ${failure}`)); process.exit(1); }
console.log(`PASS harness configuration; checked ${graphFiles.length} task graph(s).`);
if (!process.argv.includes('--run-adapters')) process.exit(0);
for (const [name, command] of Object.entries(config.adapters.definitions.policy.commands)) { console.log(`RUN policy:${name}`); const code = await new Promise((resolve) => spawn(command, { cwd: root, shell: true, stdio: 'inherit' }).on('exit', (status) => resolve(status ?? 1))); if (code) failures.push(`adapter ${name} failed`); }
if (failures.length) process.exit(1);
console.log('PASS policy adapter commands.');
