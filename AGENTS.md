# Working on Kinwall for iPhone, iPad and Android

The shared rules for all Kinwall repos are in [kinwall's AGENTS.md](https://github.com/JohnDuprey/kinwall/blob/main/AGENTS.md): test first,
Conventional Commits (checked in CI), docs with every change, the design and content rules. This
file adds what's specific to this repo, an Expo React Native app that wraps the Kinwall web app,
plus native widgets, a Watch app and a share extension. See [README.md](README.md) and
[docs/PLAN.md](docs/PLAN.md).

## Checks

```bash
npx tsc --noEmit
CI=1 npx expo prebuild --clean     # must apply; delete the generated ios/ and android/ afterward
```
Swift in `targets/` and `native/` is type-checked against the iOS simulator SDK
(`xcrun swiftc -typecheck -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) …`). Pure logic in
`src/` (routing, parsing) gets a `node:test` test when you change it.

## Rules

- Screens belong in the web app; native code is only for what the web can't do (widgets, share
  sheet, notifications, keychain). Features land in kinwall first.
- Only documented Apple and Android APIs. No private APIs or responder-chain tricks.
- Never change the signing team or bundle IDs, and never commit signing files or keys.
- `scripts/install-device.sh` must stop on a failed build; never install a stale build.
- Scopes for commits: `ios`, `android`, `widgets`, `watch`, `share`, `shell`, `native`, `docs`.
