import assert from 'node:assert/strict';
import { cp, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dir, '..');
for (const environment of ['preview', 'production', 'unknown', '']) {
  const destination = resolve(root, 'artifacts', 'exclusion', environment || 'missing');
  await rm(destination, { recursive: true, force: true });
  await mkdir(destination, { recursive: true });
  for (const name of ['app.json', 'app.config.ts', 'assets', 'index.ts', 'App.tsx']) {
    await cp(resolve(root, 'example', name), resolve(destination, name), { recursive: true });
  }
  const pkg = JSON.parse(await readFile(resolve(root, 'example/package.json'), 'utf8'));
  pkg.name = `exclusion-${environment || 'missing'}`;
  await writeFile(resolve(destination, 'package.json'), JSON.stringify(pkg));
  await symlink(resolve(root, 'example/node_modules'), resolve(destination, 'node_modules'));
  const env: NodeJS.ProcessEnv = { ...process.env, CI: '1', APP_ENV: environment, LINEAR_CLIENT_ID: 'public-exclusion-fixture', LINEAR_TEAM_ID: 'fixture-team' };
  if (!environment) delete env.APP_ENV;
  const processResult = Bun.spawn(['bunx', 'expo', 'prebuild', '--clean', '--no-install'], { cwd: destination, env, stdout: 'pipe', stderr: 'pipe' });
  const [out, err, code] = await Promise.all([new Response(processResult.stdout).text(), new Response(processResult.stderr).text(), processResult.exited]);
  assert.equal(code, 0, `${environment}: ${out}\n${err}`);
  const podfile = await readFile(resolve(destination, 'ios/Podfile'), 'utf8');
  const gradle = await readFile(resolve(destination, 'android/settings.gradle'), 'utf8');
  const plist = await readFile(resolve(destination, 'ios/QAOverlayExample/Info.plist'), 'utf8');
  const manifest = await readFile(resolve(destination, 'android/app/src/main/AndroidManifest.xml'), 'utf8');
  const enabled = environment === 'preview';
  assert.equal(podfile.includes(':exclude => ["@mickeypause/tiq"]'), !enabled);
  assert.equal(gradle.includes('expoAutolinking.exclude ='), !enabled);
  assert.equal(plist.includes('RnQaOverlayEnabled'), enabled);
  assert.equal(plist.includes('NSCameraUsageDescription'), enabled);
  assert.equal(plist.includes('NSMicrophoneUsageDescription'), enabled);
  assert.equal(manifest.includes('expo.modules.qaoverlay.ENABLED'), enabled);
  assert.equal(plist.includes('RnQaOverlayLinearClientId'), enabled);
  assert.equal(plist.includes('dev.rnqaoverlay.example.qa'), enabled);
  assert.equal(manifest.includes('QaLinearCallbackActivity'), enabled);
  assert.equal(manifest.includes('expo.modules.qaoverlay.LINEAR_CLIENT_ID'), enabled);
  assert.equal(manifest.includes('public-exclusion-fixture'), enabled);
  assert.equal(plist.includes('public-exclusion-fixture'), enabled);
  const publicConfig = Bun.spawn(['bunx', 'expo', 'config', '--type', 'public', '--json'], { cwd: destination, env, stdout: 'pipe', stderr: 'pipe' });
  const [serialized, configError, configCode] = await Promise.all([new Response(publicConfig.stdout).text(), new Response(publicConfig.stderr).text(), publicConfig.exited]);
  assert.equal(configCode, 0, configError);
  if (!enabled) assert.equal(serialized.includes('@mickeypause/tiq'), false, 'Reporter plugin leaked into public config');
  console.log(`${environment || 'missing'}: ${enabled ? 'included' : 'excluded'} — generated native config and public manifest passed`);
}
