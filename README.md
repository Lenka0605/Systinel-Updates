# Systinel Updates

This public repository hosts the signed update feed and binary releases for
Systinel. The application source code is not published here.

## Download Systinel

New users should open the
[latest release](https://github.com/Lenka0605/Systinel-Updates/releases/latest)
and download the single `.dmg` file shown under Assets. Open the DMG and drag
Systinel into Applications.

Users who already have Build 37 or later installed should update from inside
Systinel instead of downloading another installer.

## Update infrastructure

- Update feed: `appcast.xml`
- Sparkle-only archives: `updates/`
- Release notes: `release-notes/`
- Security: update archives are verified with Sparkle EdDSA signatures

Sparkle-only ZIP archives are intentionally not attached to GitHub Releases,
so the manual download page has one clear installer choice.

Systinel 1.1.1 Build 37 is the first release with in-app update support.
