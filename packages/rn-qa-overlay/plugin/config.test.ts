import { expect, test } from 'bun:test';
import { configurePodfile, configureSettingsGradle, isOverlayEnabled, validateLinearConfig } from './config';

test('inclusion fails closed, including production accidentally allowlisted', () => {
  for (const env of [undefined, '', 'production', 'typo', 'PREVIEW']) expect(isOverlayEnabled(env, ['preview', 'production'])).toBe(false);
  expect(isOverlayEnabled('preview', ['preview'])).toBe(true);
  expect(isOverlayEnabled('release', ['preview'])).toBe(false);
});
test('iOS exclusion is idempotent and reversible', () => {
  const original = 'target "Example" do\n  use_expo_modules!\nend\n';
  const excluded = configurePodfile(original, false);
  expect(excluded).toContain(':exclude => ["@mickeypause/tiq"]');
  expect(configurePodfile(excluded, false)).toBe(excluded);
  expect(configurePodfile(excluded, true)).toBe(original);
});
test('Android exclusion preserves existing exclusions and can be reversed', () => {
  const original = 'expoAutolinking.useExpoModules()\n';
  const excluded = configureSettingsGradle(original, false);
  expect(excluded).toContain('expoAutolinking.exclude ?: []');
  expect(configureSettingsGradle(excluded, false)).toBe(excluded);
  expect(configureSettingsGradle(excluded, true)).toBe(original);
});
test('unsupported native templates fail instead of silently shipping the reporter', () => {
  expect(() => configurePodfile('custom pod setup', false)).toThrow();
  expect(() => configureSettingsGradle('custom gradle setup', false)).toThrow();
});

test('Linear config accepts public native callbacks and rejects unsafe or secret-bearing options', () => {
  expect(validateLinearConfig(undefined)).toBeUndefined();
  expect(validateLinearConfig({ clientId: 'public-id', redirectUri: 'dev.example.qa://linear/callback' })?.scheme).toBe('dev.example.qa');
  for (const redirectUri of ['https://example.com/callback', 'javascript:alert(1)', 'qa://callback', 'dev.example.qa://linear/callback?code=x', 'dev.example.qa://linear/callback#x']) {
    expect(() => validateLinearConfig({ clientId: 'public-id', redirectUri })).toThrow();
  }
  expect(() => validateLinearConfig({ clientId: '', redirectUri: 'dev.example.qa://linear/callback' })).toThrow();
  expect(() => validateLinearConfig({ clientId: 'public-id', redirectUri: 'dev.example.qa://linear/callback', clientSecret: 'must-not-ship' } as never)).toThrow();
});
