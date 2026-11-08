import type { ConfigContext, ExpoConfig } from 'expo/config';
export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'QA Overlay Example',
  slug: 'qa-overlay-example',
  scheme: 'qa-overlay-example',
  userInterfaceStyle: 'automatic',
  ios: { ...config.ios, bundleIdentifier: 'dev.rnqaoverlay.example', supportsTablet: false },
  android: { ...config.android, package: 'dev.rnqaoverlay.example' },
  plugins: [['@mickeypause/tiq', { allowedEnvironments: ['preview', 'development'], teamName: 'Product',
    ...(process.env.LINEAR_CLIENT_ID ? { linear: { clientId: process.env.LINEAR_CLIENT_ID, redirectUri: process.env.LINEAR_REDIRECT_URI ?? 'dev.rnqaoverlay.example.qa://linear/callback', ...(process.env.LINEAR_TEAM_ID ? { teamId: process.env.LINEAR_TEAM_ID } : {}) } } : {}) }]],
});
