// app.json, plus the release build number: CI sets KINWALL_BUILD_NUMBER (major*10000 + minor*100 +
// patch, .github/workflows/build.yml) so every release's iOS buildNumber and Android versionCode
// go up with its version. Local builds keep app.json's.
const build = process.env.KINWALL_BUILD_NUMBER
module.exports = ({ config }) =>
  build ? { ...config, ios: { ...config.ios, buildNumber: build }, android: { ...config.android, versionCode: Number(build) } } : config
