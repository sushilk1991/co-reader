# Reader Visual Refresh Design

## Goal

Replace the current gray-heavy reader shell with a calmer, editorial macOS aesthetic that keeps the document surface visually primary and makes the supporting tools feel lighter, clearer, and easier on the eyes.

## Problems in the Current UI

- Too many surfaces use the same low-contrast gray treatment, so the hierarchy collapses.
- The toolbar, reader canvas, and inspector all compete for attention instead of reinforcing one primary reading flow.
- The ask panel reads like a prototype utility pane rather than a premium reading workspace.
- Accent color is used inconsistently, so availability, action, and selection states blur together.

## Chosen Direction

Use a warm editorial desktop palette:

- Paper-forward background with ivory and oat neutrals.
- Dark ink typography with stronger contrast for titles and body copy.
- Teal reserved for active AI actions and selected controls.
- Brass reserved for secondary metadata and document position.
- Muted clay used only for error or unavailable states.

## Structural Changes

- Make the document canvas the brightest and cleanest area in the window.
- Convert the sidebar and inspector from generic material cards into soft, solid editorial panels.
- Reduce toolbar bulk and make it read like a compact control rail instead of a banner.
- Improve the ask panel with clearer sections, better scope controls, and a more legible empty state.

## Expected Outcome

The app should feel closer to a native reading desk than a generic AI dashboard: quieter frame, stronger document focus, clearer controls, and less eye fatigue during long reading sessions.
