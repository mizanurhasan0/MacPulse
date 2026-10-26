# MacPulse interface direction

## Reference review

The review used product owners' current pages and Apple's native macOS guidance. It establishes useful patterns rather than a ranking of products or a pixel-for-pixel copy.

- [Apple: Windows](https://developer.apple.com/design/human-interface-guidelines/windows) recommends fluid window resizing, useful size limits, and standard macOS window controls. MacPulse keeps the native split view and window chrome, with a 680 × 500 minimum and a 1180 × 780 initial size.
- [Sensei](https://cindori.com/sensei) emphasizes an overview of system measurements, dedicated monitoring tools, and appearance customization. MacPulse uses a focused set of real metrics, consistent cards, and saved appearance preferences.
- [CleanMyMac](https://cleanmymac.com/) combines a central review workflow with dedicated tools. MacPulse keeps a visible Scan and Review action alongside module navigation and explains each supported action before it can change app state.

## Layout decisions

- Group the native sidebar into monitoring, workspace tools, and app preferences/history.
- Keep one toolbar refresh action and support Command-R. Command-Comma opens Settings.
- Use a shared page viewport that fills the detail area. Apply the reading-width limit to the document inside it, so the scrollbar remains at the pane's outer edge.
- Replace Settings' width-constrained, internally scrolling Form with cards inside the shared viewport.
- Adapt dashboard columns to available width. Stack text and actions at compact widths instead of squeezing them into one row.
- Show a process table when the detail pane is wide enough and application cards when it is narrow. Keep search and safety feedback visible above the results.
- Use neutral native surfaces, subtle borders, a restrained accent, consistent spacing, and semantic warning colors. Accent palettes have separate light and dark values for legibility.
- Preserve native right-to-left behavior for Arabic. Recreate the native navigation container when the language changes while retaining the selected module in the shared model.

## Verification

A temporary native renderer exercised all eight modules at 680 × 500, 1180 × 780, and 1600 × 1000, plus compact Bangla and Arabic dark layouts: 40 combinations. The scroll-view frames span the available window width, with no document wider than its scroll viewport. Rendered previews were inspected for compact dashboard, startup, settings, process table, and Arabic layout.

Native vibrancy and window chrome are composited separately by macOS, so offscreen bitmap previews do not reproduce every sidebar material. These layout checks complement the live SwiftUI app-scene checks; they do not assert that every product workflow is implemented. See FEATURES.md for functional limits.

The live SwiftUI scene completed another 18 scenarios, including resizing each module, switching into Arabic and back to Bangla, and scrolling Settings to its final controls. It exited successfully and reported 11 realized sidebar rows throughout navigation.

## Storage workspace refinement

Storage uses a capacity overview with available bytes, used/total bytes and a labeled usage bar. It shows only measured totals; it does not invent a breakdown of unknown file categories. High utilization receives an amber accent. Open Trash remains a secondary action beside the overview.

Three selectable category cards replace the thin segmented control. They include descriptions at wide widths, concise icon/title layouts at compact widths, visible selection, hover feedback, accessibility labels and reduced-motion support. Compact layouts stack scan actions rather than compressing controls.

The initial empty state sits inside the scan panel, beside the task's explanation and action. Cache results have a distinct heading and aggregate size, and the selection review action has its own surface. File scans show an explicit selected-folder panel; the minimum-size control appears for large-file discovery. Dark-mode primary actions use dark text on the lighter accent for contrast; disabled actions use neutral colors.

Thirteen native preview scenarios cover initial and fixture-result states, all three scan categories, 420- and 940-point detail panes, a 500-point viewport, light/dark appearance, and English/Bangla/Arabic RTL. Scroll document widths were checked against their viewports. Fixture scans confirmed results still populate the redesigned views, and the 94 existing regression tests passed. Preview data is synthetic; the actual app continues to show live disk measurements.
