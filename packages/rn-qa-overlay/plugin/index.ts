import { AndroidConfig, withAndroidManifest, withInfoPlist, withPodfile, withSettingsGradle, type ConfigPlugin } from 'expo/config-plugins';
import { PACKAGE_NAME, configurePodfile, configureSettingsGradle, isOverlayEnabled, validateLinearConfig, type QaOverlayOptions } from './config';

const withQaOverlay: ConfigPlugin<QaOverlayOptions> = (config, options) => {
  if (!options || !Array.isArray(options.allowedEnvironments) || options.allowedEnvironments.some(value => typeof value !== 'string' || !value)) {
    throw new Error('@mickeypause/tiq: supply allowedEnvironments as an explicit array of non-empty APP_ENV values.');
  }
  const enabled = isOverlayEnabled(process.env.APP_ENV, options.allowedEnvironments);
  config = withPodfile(config, mod => {
    mod.modResults.contents = configurePodfile(mod.modResults.contents, enabled);
    return mod;
  });
  config = withSettingsGradle(config, mod => {
    mod.modResults.contents = configureSettingsGradle(mod.modResults.contents, enabled);
    return mod;
  });
  if (!enabled) {
    // Expo embeds public app config; remove our build-only entry from that manifest too.
    config.plugins = config.plugins?.filter(entry => (Array.isArray(entry) ? entry[0] : entry) !== PACKAGE_NAME);
    return config;
  }
  const linear = validateLinearConfig(options.linear);
  config = withInfoPlist(config, mod => {
    mod.modResults.RnQaOverlayEnabled = true;
    if (linear) {
      mod.modResults.RnQaOverlayLinearClientId = linear.clientId;
      mod.modResults.RnQaOverlayLinearRedirectUri = linear.redirectUri;
      if (linear.teamId) mod.modResults.RnQaOverlayLinearTeamId = linear.teamId;
      const types = mod.modResults.CFBundleURLTypes ?? [];
      if (!types.some(type => type.CFBundleURLSchemes?.includes(linear.scheme))) types.push({ CFBundleURLName: 'rn-qa-overlay.linear', CFBundleURLSchemes: [linear.scheme] });
      mod.modResults.CFBundleURLTypes = types;
    }
    mod.modResults.RnQaOverlayTeam = options.teamName ?? 'Product';
    mod.modResults.NSCameraUsageDescription ??= 'Attach a photo or camera video to a QA report.';
    mod.modResults.NSMicrophoneUsageDescription ??= 'Record audio with a QA camera video.';
    return mod;
  });
  return withAndroidManifest(config, mod => {
    const application = AndroidConfig.Manifest.getMainApplicationOrThrow(mod.modResults);
    AndroidConfig.Manifest.addMetaDataItemToMainApplication(application, 'expo.modules.qaoverlay.ENABLED', 'true');
    AndroidConfig.Manifest.addMetaDataItemToMainApplication(application, 'expo.modules.qaoverlay.TEAM', options.teamName ?? 'Product');
    if (linear) {
      AndroidConfig.Manifest.addMetaDataItemToMainApplication(application, 'expo.modules.qaoverlay.LINEAR_CLIENT_ID', linear.clientId);
      AndroidConfig.Manifest.addMetaDataItemToMainApplication(application, 'expo.modules.qaoverlay.LINEAR_REDIRECT_URI', linear.redirectUri);
      if (linear.teamId) AndroidConfig.Manifest.addMetaDataItemToMainApplication(application, 'expo.modules.qaoverlay.LINEAR_TEAM_ID', linear.teamId);
      application.activity ??= [];
      const name = 'expo.modules.qaoverlay.QaLinearCallbackActivity';
      const activity = application.activity.find(item => item.$['android:name'] === name) ?? { $: { 'android:name': name, 'android:exported': 'true', 'android:theme': '@style/QaOverlayActivityTheme' } };
      activity['intent-filter'] = [{ action: [{ $: { 'android:name': 'android.intent.action.VIEW' } }], category: [{ $: { 'android:name': 'android.intent.category.DEFAULT' } }, { $: { 'android:name': 'android.intent.category.BROWSABLE' } }], data: [{ $: { 'android:scheme': linear.scheme, 'android:host': linear.host, 'android:path': linear.path } }] }];
      if (!application.activity.includes(activity)) application.activity.push(activity);
    }
    return mod;
  });
};
export default withQaOverlay;

export type { QaOverlayOptions } from './config';
