const appVersionName = String.fromEnvironment(
  'APP_VERSION_NAME',
  defaultValue: '0.9.3',
);
const appBuildNumber = int.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: 46,
);
const appVersion = '$appVersionName ($appBuildNumber)';
