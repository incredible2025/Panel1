const appVersionName = String.fromEnvironment(
  'APP_VERSION_NAME',
  defaultValue: '0.9.1',
);
const appBuildNumber = int.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: 44,
);
const appVersion = '$appVersionName ($appBuildNumber)';
