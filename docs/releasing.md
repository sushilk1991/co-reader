# Releasing Coreader (direct download)

`scripts/release.sh` builds the Release app, signs it and the embedded `coreader` command
with the hardened runtime, makes `dist/Coreader-<version>.dmg`, notarizes it through
`asc notarization` and staples the ticket. `SIGN_IDENTITY=- scripts/release.sh` is a dry
run with ad-hoc signing and no notarization.

## Signing identity

A "Developer ID Application" certificate for team `JZFVKGDPU4`, in the keychain of the Mac
that builds releases. The key is kept outside this repository. Where the keychain is locked
by default, run the release as `ios-build scripts/release.sh`.

Renewing it needs the Account Holder signed in at developer.apple.com (Certificates → + →
Developer ID Application, upload a new signing request): the App Store Connect API key is
refused for this certificate type.

## Checked

1.0.0 was built, signed, notarized (submission `89980e49`) and stapled on 2026-11-23.
Gatekeeper reports "Notarized Developer ID" for both the DMG and the app inside. The
hardened build was driven off-screen: it starts, finds the agent CLIs, imports an EPUB and
a PDF and opens the reader. Not checked: opening the DMG on another Mac.

## In-app updates

The app checks `https://api.github.com/repos/sushilk1991/co-reader/releases/latest` once a day
at launch and from **Coreader > Check for Updates…** (`Sources/CoreaderApp/App/Updater.swift`).
What a release needs for the app to offer it:

- a tag that is the version (`v1.0.3`), newer than the running app's;
- not a draft or pre-release;
- the `.dmg` attached, containing `Coreader.app` signed by the same team as the running copy.
  The updater refuses anything else, so an unsigned or re-signed build cannot be pushed this way.

The release notes are shown to the reader as "What's new", so write them for readers.

The repository is public, so the check needs no sign-in. If the anonymous request is refused
(GitHub's rate limit, or the repository made private again), the app retries with the token
of a signed-in `gh` on the same Mac, and otherwise offers the releases page.

To try the whole flow without publishing: copy a Release build somewhere, set its
`CFBundleShortVersionString` to an older version, sign it with the Developer ID, run it
off-screen and send `update check`, then `update install`.
