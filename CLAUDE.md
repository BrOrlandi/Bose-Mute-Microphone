# Bose-Mute-Microphone

macOS menu bar app (Swift Package, AppKit, Core Audio). See README.md for architecture and docs/DIAGNOSTICO.md for the hardware investigation.

## Release & Changelog

Structured convention: `.claude/release.json` (read by the `release` skill).

- Version in `Resources/Info.plist`: `CFBundleShortVersionString` (semver) and `CFBundleVersion` (build counter, +1 every release, never reused).
- Changelog: `CHANGELOG.md` (Keep a Changelog, English, public audience).
- Bump from conventional commits (breaking → major, `feat` → minor, otherwise patch), confirmed with the user.
- Build the installer with `./scripts/make-dmg.sh` → `build/Bose-Mute-Microphone-<version>.dmg`; check the built app reports the new version.
- Tag `vX.Y.Z` (annotated), push, then `gh release create vX.Y.Z` with the CHANGELOG section as notes and the DMG attached.
