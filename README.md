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

<!-- windows-preview-start -->
## Windows preview

For Windows 10 22H2 and Windows 11 on Intel/AMD x64, download the single
[`Setup.exe` installer](https://github.com/Lenka0605/Systinel-Updates/releases/tag/windows-v1.8.0-74) from the Windows preview release.
The runtime is included and installation does not require an administrator account.

Use **Settings → Software Update** in the Windows app for later preview updates.
Windows uses its own RSA-PSS/SHA-256 signed `windows/preview.json` feed; it never
uses the macOS Sparkle feed. Settings are preserved during updates.

This preview does not provide generic fan control or charge limits. Sensor
readings depend on compatible hardware/providers. The Windows executables do
not yet have an Authenticode certificate, so Windows may show an unknown publisher.
The repository's Latest Release remains the macOS release.
<!-- windows-preview-end -->
