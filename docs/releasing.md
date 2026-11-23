# Releasing Coreader (direct download)

`scripts/release.sh` builds the Release app, signs it and the embedded `coreader` command
with the hardened runtime, makes `dist/Coreader-<version>.dmg`, notarizes it through
`asc notarization` and staples the ticket. `SIGN_IDENTITY=- scripts/release.sh` is a dry
run with ad-hoc signing and no notarization.

## The one-time step: a Developer ID certificate

Notarized direct downloads need a "Developer ID Application" identity for team
`JZFVKGDPU4`. Only the Account Holder can create one, and only signed in at
developer.apple.com: the App Store Connect API key is refused.

Either:

- **New certificate for the Mac mini.** A key and signing request are already at
  `~/.config/ios-signing/developer-id/` (`devid.key`, `devid.csr`). At
  developer.apple.com → Certificates → + → Developer ID Application (G2 Sub-CA), upload
  `devid.csr` and download the `.cer` into that folder. Then pair it with the key and
  import it:

  ```bash
  cd ~/.config/ios-signing/developer-id
  openssl x509 -inform DER -in developerID_application.cer -out devid.pem
  openssl pkcs12 -export -legacy -inkey devid.key -in devid.pem -out devid.p12 -passout pass:coreader
  echo coreader | ios-signing import devid.p12
  ```

- **Reuse the existing one** (certificate `F3L6465NDU`, expires 2027-02-01): export it
  with its private key from Keychain Access on the Mac that created it, then
  `ios-signing import <file.p12>` on the Mac mini (passphrase on stdin).

Then: `ios-build scripts/release.sh`.

## Checked

The dry run was built and driven off-screen: with the hardened runtime the app starts,
finds the agent CLIs, imports an EPUB and a PDF and opens the reader. Signing with a real
Developer ID, notarization and stapling have not run yet.
