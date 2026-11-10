const appVersionName = String.fromEnvironment(
  'APP_VERSION_NAME',
  defaultValue: '0.9.2',
);
const appBuildNumber = int.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: 45,
);
const appVersion = '$appVersionName ($appBuildNumber)';
