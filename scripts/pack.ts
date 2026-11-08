import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dir, '..');
const destination = resolve(root, 'artifacts/npm');
await mkdir(destination, { recursive: true });
const result = Bun.spawn(['bun', 'pm', 'pack', '--destination', destination, '--quiet'], {
  cwd: resolve(root, 'packages/rn-qa-overlay'), stdout: 'inherit', stderr: 'inherit',
});
process.exitCode = await result.exited;
