# Releasing Coreader (direct download)

`scripts/release.sh` builds the Release app, signs it and the embedded `coreader` command
with the hardened runtime, makes `dist/Coreader-<version>.dmg`, notarizes it through
`asc notarization` and staples the ticket. `SIGN_IDENTITY=- scripts/release.sh` is a dry
run with ad-hoc signing and no notarization.

## Signing identity

"Developer ID Application: Sushil Kumar (JZFVKGDPU4)" (certificate `XJSB4P7Y5Q`, expires
2027-12-23) is in the Mac mini's signing keychain; its key and `.p12` are in
`~/.config/ios-signing/developer-id/`. Run the release there as `ios-build scripts/release.sh`.

Renewing it needs the Account Holder signed in at developer.apple.com (Certificates → + →
Developer ID Application, upload a new signing request): the App Store Connect API key is
refused for this certificate type.

## Checked

1.0.0 was built, signed, notarized (submission `89980e49`) and stapled on 2026-11-23.
Gatekeeper reports "Notarized Developer ID" for both the DMG and the app inside. The
hardened build was driven off-screen: it starts, finds the agent CLIs, imports an EPUB and
a PDF and opens the reader. Not checked: opening the DMG on another Mac.
