import { mkdir, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
const root = process.cwd();
for (const directory of ['plans', 'reports', 'docs/decisions', 'docs/product-specs']) await mkdir(path.join(root, directory), { recursive: true });
for (const file of ['plans/README.md', 'reports/.gitkeep']) try { await access(path.join(root, file)); } catch { await writeFile(path.join(root, file), file.endsWith('.md') ? '# Execution plans\n\nNon-trivial work has a task graph and evidence bundle.\n' : ''); }
console.log('PASS harness directories initialized without overwriting repository values.');
