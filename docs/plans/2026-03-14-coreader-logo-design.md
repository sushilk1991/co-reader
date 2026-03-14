# CoReader Logo Design

## Goal

Create a symbol-only logo and app icon for CoReader that feels premium, macOS-native, and consistent with the product’s reading-plus-AI positioning.

## Chosen Direction

Build a restrained icon centered on a fused open-book and intelligence motif.

- Background: deep graphite field that feels like a serious reading tool rather than a bright consumer app.
- Primary form: a brass open-book silhouette with crisp, architectural geometry.
- Secondary signal: a teal node-orbit or mesh arc running through the book gutter, suggesting local intelligence without falling into generic AI clichés.
- Shape language: square icon composition with large, readable masses so it survives Dock and Finder sizes.

The symbol should read in this order:

1. book / reading object
2. structured intelligence
3. premium desktop utility

## Alternatives Considered

### 1. Book-first editorial monogram

Cleaner and more understated, but too quiet for a new app that still needs a distinct identity at small sizes.

### 2. AI-first mesh mark

More startup-forward, but it risks looking like a generic assistant or developer tool rather than a co-reader.

### 3. Wordmark with symbol

Not necessary for the Dock or titlebar surfaces. Symbol-only is more flexible and cleaner for the current macOS app.

## Visual System

### Color palette

- Graphite base: near-black blue-gray
- Brass book form: warm metallic gold, muted rather than glossy
- Teal intelligence accent: vivid but controlled, used sparingly

This keeps the icon aligned with the in-app palette already used across `ReaderTheme`.

### Composition

- Symmetric or near-symmetric core mark
- Strong center gutter for the “reader spine” metaphor
- Minimal internal detail
- No text or letterforms
- Flat or gently shaded rendering, not 3D and not skeuomorphic

### In-app integration

Reuse the symbol in:

- the sidebar/title area
- empty states where a brand anchor helps
- packaged app icon assets

The in-app symbol should use the same silhouette as the Dock icon, not a different mark.

## Asset Strategy

Generate one high-resolution master artwork, then derive:

- macOS app icon set assets in `Assets.xcassets/AppIcon.appiconset`
- a reusable PNG for in-app branding in the asset catalog

Use a generated master large enough for clean downscaling. Keep filenames stable so future iterations can replace the art without changing code.

## Testing Strategy

- Verify the asset catalog is compiled into the app bundle.
- Build and launch the macOS app to confirm the asset catalog is recognized.
- Confirm in-app views render the branded symbol without layout regressions.

## Non-Goals

- animated logo
- alternate seasonal themes
- full wordmark system
- marketing-site brand package
