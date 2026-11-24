const appVersionName = String.fromEnvironment(
  'APP_VERSION_NAME',
  defaultValue: '0.9.6',
);
const appBuildNumber = int.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: 49,
);
const appVersion = '$appVersionName ($appBuildNumber)';
