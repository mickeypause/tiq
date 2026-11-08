import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cp, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';

const root = resolve(import.meta.dir, '..');
const pkg = JSON.parse(await readFile(resolve(root, 'packages/rn-qa-overlay/package.json'), 'utf8'));
const pack = Bun.spawn(['bun', 'run', 'pack'], { cwd: root, stdout: 'inherit', stderr: 'inherit' });
assert.equal(await pack.exited, 0, 'Package build/pack failed');
const archive = resolve(root, 'artifacts/npm', `${pkg.name.replace('/', '-').replace('@', '')}-${pkg.version}.tgz`);
const entries = execFileSync('tar', ['-tzf', archive], { encoding: 'utf8' }).trim().split('\n');
for (const name of ['app.plugin.js', 'build/index.js', 'build/index.d.ts', 'build/config.d.ts',
  'RnQaOverlay.podspec', 'expo-module.config.json', 'react-native.config.js', 'LICENSE', 'THIRD_PARTY_NOTICES.md',
  'ios/QaComposer.swift', 'ios/QaOverlayAppDelegateSubscriber.swift',
  'android/build.gradle', 'android/src/main/AndroidManifest.xml',
  'android/src/main/java/expo/modules/qaoverlay/QaOverlayPackage.kt']) {
  assert(entries.includes(`package/${name}`), `Missing package file: ${name}`);
}
assert.equal(entries.filter(name => name.endsWith('.svg')).length, 317);
assert.equal(entries.filter(name => /drawable\/qa_linear_.*\.xml$/.test(name)).length, 317);
assert(!entries.some(name => /(?:^|\/)(?:node_modules|example|artifacts|Pods|\.env[^/]*|\.DS_Store)(?:\/|$)/.test(name)
  || name.startsWith('package/android/build/') || name.includes('/src/test/') || name.endsWith('.test.ts')),
  'Development output or local configuration leaked into the archive');

// Outside the workspace: neither Bun nor Node can fall back to the source package.
const consumer = await mkdtemp(resolve(tmpdir(), 'rn-qa-overlay-package-'));
const environment: NodeJS.ProcessEnv = { ...process.env, CI: '1', EXPO_NO_DOTENV: '1', EXPO_NO_TELEMETRY: '1',
  LINEAR_CLIENT_ID: 'public-package-fixture', LINEAR_TEAM_ID: 'fixture-team' };
async function run(command: string[], env = environment) {
  const result = Bun.spawn(command, { cwd: consumer, env, stdout: 'pipe', stderr: 'pipe' });
  const [out, err, code] = await Promise.all([new Response(result.stdout).text(), new Response(result.stderr).text(), result.exited]);
  assert.equal(code, 0, `${command.join(' ')}\n${out.slice(-5000)}\n${err.slice(-5000)}`);
  return out;
}
try {
  for (const name of ['app.json', 'app.config.ts', 'assets', 'index.ts', 'App.tsx']) {
    await cp(resolve(root, 'example', name), resolve(consumer, name), { recursive: true });
  }
  const host = JSON.parse(await readFile(resolve(root, 'example/package.json'), 'utf8'));
  await writeFile(resolve(consumer, 'package.json'), JSON.stringify({ name: 'packed-qa-consumer', private: true,
    version: '1.0.0', main: 'index.ts', dependencies: { ...host.dependencies, [pkg.name]: archive }, devDependencies: host.devDependencies }));
  await run(['bun', 'install', '--ignore-scripts']);
  const installed = resolve(consumer, 'node_modules', pkg.name);
  const metadata = JSON.parse(await readFile(resolve(installed, 'package.json'), 'utf8'));
  assert.equal(metadata.name, '@mickeypause/tiq');
  assert.equal(metadata.private, true, 'Local package must block registry publication');
  assert((await realpath(installed)).startsWith(await realpath(consumer)), 'Consumer resolved a workspace symlink');
  await run(['node', '-e', "require('node:assert/strict').equal(typeof require('@mickeypause/tiq'), 'function')"]);
  await writeFile(resolve(consumer, 'package-types.ts'), `import plugin, { type QaOverlayOptions } from '@mickeypause/tiq';
import type { ConfigPlugin } from 'expo/config-plugins';
const typed: ConfigPlugin<QaOverlayOptions> = plugin;
const options: QaOverlayOptions = { allowedEnvironments: ['preview'], linear: { clientId: 'public-id', redirectUri: 'dev.test.qa://linear/callback' } };
// @ts-expect-error environments must be an explicit array
const invalid: QaOverlayOptions = { allowedEnvironments: 'preview' };
void [typed, options, invalid];
`);
  await writeFile(resolve(consumer, 'tsconfig.json'), JSON.stringify({ compilerOptions: {
    strict: true, noEmit: true, skipLibCheck: true, module: 'Preserve', moduleResolution: 'Bundler', target: 'ES2022', types: [],
  }, files: ['package-types.ts'] }));
  await run(['bunx', 'tsc', '--noEmit']);
  for (const platform of ['apple', 'android']) {
    const result = JSON.parse(await run(['bunx', 'expo-modules-autolinking', 'resolve', '--platform', platform, '--json']));
    const module = result.modules.find((item: { packageName: string }) => item.packageName === pkg.name);
    assert(module, `Packed native module was not discovered on ${platform}`);
    assert(JSON.stringify(module).includes(installed), `Autolinking did not resolve the installed ${platform} sources`);
  }
  for (const name of ['preview', 'production', 'unknown', 'missing']) {
    const env = { ...environment, APP_ENV: name };
    if (name === 'missing') delete (env as NodeJS.ProcessEnv).APP_ENV;
    await run(['bunx', 'expo', 'prebuild', '--clean', '--no-install'], env);
    const enabled = name === 'preview';
    const podfile = await readFile(resolve(consumer, 'ios/Podfile'), 'utf8');
    const gradle = await readFile(resolve(consumer, 'android/settings.gradle'), 'utf8');
    const plist = await readFile(resolve(consumer, 'ios/QAOverlayExample/Info.plist'), 'utf8');
    const manifest = await readFile(resolve(consumer, 'android/app/src/main/AndroidManifest.xml'), 'utf8');
    assert.equal(podfile.includes(':exclude => ["@mickeypause/tiq"]'), !enabled);
    assert.equal(gradle.includes('expoAutolinking.exclude ='), !enabled);
    for (const field of ['RnQaOverlayEnabled', 'RnQaOverlayLinearClientId', 'public-package-fixture']) assert.equal(plist.includes(field), enabled);
    for (const field of ['expo.modules.qaoverlay.ENABLED', 'QaLinearCallbackActivity', 'public-package-fixture']) assert.equal(manifest.includes(field), enabled);
    const publicConfig = await run(['bunx', 'expo', 'config', '--type', 'public', '--json'], env);
    if (!enabled) assert(!publicConfig.includes(pkg.name), 'Reporter leaked into public app config');
    console.log(`Packed consumer ${name}: ${enabled ? 'included' : 'excluded'} — native config and public manifest passed`);
  }
  await writeFile(resolve(root, 'artifacts/npm/verification.json'), JSON.stringify({ package: pkg.name, version: pkg.version,
    archive, files: entries.length, iconsPerPlatform: 317, standaloneInstall: true, nodePluginLoad: true,
    typeDeclarations: true, nativeDiscovery: ['apple', 'android'], environments: ['preview', 'production', 'unknown', 'missing'] }, null, 2) + '\n');
  console.log(`Verified installable package: ${archive}`);
} finally {
  await rm(consumer, { recursive: true, force: true });
}
