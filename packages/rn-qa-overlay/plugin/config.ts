export const PACKAGE_NAME = '@mickeypause/tiq';

export interface QaOverlayOptions {
  /** Explicit allowlist. Production, absent and unknown environments are always excluded. */
  allowedEnvironments: string[];
  teamName?: string;
  /** Public OAuth configuration only. Never bundle a client secret or access token. */
  linear?: { clientId: string; redirectUri: string; teamId?: string };

}

export function isOverlayEnabled(environment: string | undefined, allowed: string[]): boolean {
  return Boolean(environment && environment !== 'production' && allowed.includes(environment));
}

export function configurePodfile(source: string, enabled: boolean): string {
  const clean = source.replace(/^([ \t]*)# rn-qa-overlay autolinking\n.*\n/gm, '$1use_expo_modules!\n');
  if (enabled) return clean;
  if (!/^\s*use_expo_modules!\s*$/m.test(clean)) {
    throw new Error('@mickeypause/tiq: expected the Expo SDK 58 use_expo_modules! call. Configure its :exclude option before building production.');
  }
  return clean.replace(/^([ \t]*)use_expo_modules![ \t]*$/m,
    `$1# rn-qa-overlay autolinking\n$1use_expo_modules!(:exclude => ["${PACKAGE_NAME}"])`);
}

export function configureSettingsGradle(source: string, enabled: boolean): string {
  const clean = source.replace(/^\/\/ rn-qa-overlay autolinking\n.*\n/gm, '');
  if (enabled) return clean;
  if (!clean.includes('expoAutolinking.useExpoModules()')) {
    throw new Error('@mickeypause/tiq: expected Expo SDK 58 expoAutolinking.useExpoModules(). Configure native exclusion before building production.');
  }
  return clean.replace('expoAutolinking.useExpoModules()',
    `// rn-qa-overlay autolinking\nexpoAutolinking.exclude = ((expoAutolinking.exclude ?: []) + ["${PACKAGE_NAME}"]).unique()\nexpoAutolinking.useExpoModules()`);
}

export function validateLinearConfig(linear: QaOverlayOptions['linear']) {
  if (!linear) return undefined;
  if (Object.keys(linear).some(key => !['clientId', 'redirectUri', 'teamId'].includes(key))) {
    throw new Error('@mickeypause/tiq: linear accepts only public clientId, redirectUri and optional teamId.');
  }
  if (typeof linear.clientId !== 'string' || !linear.clientId.trim() || typeof linear.redirectUri !== 'string') {
    throw new Error('@mickeypause/tiq: Linear requires clientId and redirectUri.');
  }
  const redirect = new URL(linear.redirectUri);
  if (!/^[a-z][a-z0-9+.-]*\.[a-z0-9+.-]+$/.test(redirect.protocol.slice(0, -1)) || ['http:', 'https:', 'javascript:', 'file:'].includes(redirect.protocol) || !redirect.hostname || !redirect.pathname || redirect.username || redirect.password || redirect.port || redirect.search || redirect.hash) {
    throw new Error('@mickeypause/tiq: use a dedicated reverse-domain callback, e.g. dev.example.qa://linear/callback, with no query or fragment.');
  }
  if (linear.teamId !== undefined && (typeof linear.teamId !== 'string' || !linear.teamId.trim())) throw new Error('@mickeypause/tiq: teamId must be a non-empty Linear team ID.');
  return { ...linear, scheme: redirect.protocol.slice(0, -1), host: redirect.hostname, path: redirect.pathname };
}
