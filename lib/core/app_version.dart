const appVersionName = String.fromEnvironment(
  'APP_VERSION_NAME',
  defaultValue: '0.9.7',
);
const appBuildNumber = int.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: 50,
);
const appVersion = '$appVersionName ($appBuildNumber)';
