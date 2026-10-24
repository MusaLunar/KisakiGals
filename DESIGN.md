# KisakiGals Design System — 「誌面」(Shimen Edition)

## 1. Visual Thesis & Own-World Anchor

KisakiGals is a Windows desktop visual novel collection manager, launcher, and playtime tracker styled after the feature spreads of classic Japanese Galgame magazines (*Dengeki Hime* / *TECH GIAN*). Rather than generic SaaS glassmorphism or dark-neon gaming clichés, the interface treats the application window as an open magazine issue:

- **Mode**: `Operate` — the editorial print world lends **typography**, **CMYK functional ink palette**, **tabular layout density**, and **one signature move** (Fore-Edge Index Tabs), while all controls remain fast, unambiguous desktop affordances.
- **Anti-Slop Guardrails**:
  - Zero meta-kicker / eyebrow labels above headings.
  - Declare elevation once: `1px` registration hairlines (`Elev.border`) on paper plates, or soft ambient shadows on floating overlays — never nested cards-inside-cards.
  - Wide editorial containers where display titles never wrap beyond 2 lines.

---

## 2. CMYK Four-Ink Functional Palette (`lib/ui/theme.dart`)

Every accent ink is assigned a single functional meaning across both Light (Coated Warm Ivory Stock) and Dark (Gravure Dark Stock) modes, maintaining $\ge 4.5:1$ contrast:

| Role | Token | Light Mode | Dark Mode | Functional Assignment |
| :--- | :--- | :--- | :--- | :--- |
| **Paper Ground** | `KisakiColors.pageSurface` | `#FAF7F2` | `#13151C` | Primary spread canvas |
| **Spine Ground** | `KisakiColors.spineSurface` | `#F0EAE1` | `#0B0C10` | Left fore-edge binding rail & masthead bar |
| **Plate Card** | `KisakiColors.creamCard` / `nightCard` | `#FFFFFF` | `#161820` | Game cards, Bento cells, and sheets |
| **Process Magenta (M)** | `KisakiColors.magenta` / `magentaDark` | `#E4005A` | `#FF2E7E` | Primary launch actions, active selection, spine registration bar |
| **Process Cyan (C)** | `KisakiColors.temporalInk` | `#0088B8` | `#29B6E8` | Playtime counters, live session timers, temporal trend charts |
| **Process Yellow-Gold (Y)** | `KisakiColors.ratingInk` | `#D49400` | `#FFC42E` | Star ratings, platform scores, honor badges |
| **Registration Ink (K)** | `KisakiColors.ink` / `nightInk` | `#16151A` | `#F4F1EA` | Body copy, headlines, and `1px` registration hairlines |

---

## 3. Optical Typography & Tabular Rhythm (`lib/ui/design.dart`)

All type styles in `Type` use size-specific optical tracking and leading, with `FontFeature.tabularFigures()` enforced on all numeric and temporal columns:

- **`Type.display` (`26px`, `w800`)**: Tight leading (`1.18`) and negative tracking (`-0.65`) for masthead titles.
- **`Type.title` (`18.5px`, `w700`)**: Leading `1.26`, tracking `-0.37` for feature spread titles and modal headers.
- **`Type.section` (`14px`, `w700`)**: Leading `1.32`, tracking `-0.14`, paired with a `3px` vertical ink registration bar (`KSectionTitle`).
- **`Type.body` (`13.5px`, `w400`)**: Comfortable reading leading (`1.55`) and neutral tracking (`0.0`).
- **`Type.mono` (`11.5px`, `w600`)**: Positive tracking (`+0.25`) and tabular numerals for release-schedule timestamps, index codes (`01`–`06`), and live timers.

---

## 4. Signature Move — Fore-Edge Index Tabs (`lib/ui/shell/app_shell.dart`)

The left navigation rail (`AppSidebar`) acts as a magazine fore-edge index:

1. Navigation items sit on the recessed spine ground (`KisakiColors.spineSurface`) and carry tabular index codes (`01` through `06`).
2. The active tab background (`_ForeEdgeTabPainter`) is driven by an unbounded `AnimationController` using `AppleSpringSimulation.fromResponse(dampingRatio: 1.0, response: 0.30)`.
3. When switching tabs mid-flight, the controller's live velocity is handed off to the new spring simulation (`velocity: inheritedVelocity`), preventing any abrupt velocity reset.
4. The active tab extends `1px` across the spine seam with `KisakiColors.pageSurface(dark)` fill, a `3.5px` Process Magenta left registration bar, and an open right edge so the active tab and page canvas read as one continuous sheet of paper.

---

## 5. Fluid Motion & Accessibility (`lib/ui/design.dart`)

- **Harmonic Oscillator Spring (`AppleSpringSimulation`)**:
  - Supports both direct `(dampingRatio, angularFrequency)` and designer-friendly `(dampingRatio, response)` where $\omega_0 = 2\pi / \text{response}$.
  - Navigation and structural transitions use critically damped springs ($\zeta = 1.0$, zero overshoot).
  - Press-and-release surfaces use gentle momentum springs ($\zeta = 0.80$).
- **Immediate $t = 0$ Touch & 10px Hysteresis (`FluidPressable`)**:
  - Responds on the exact frame of `onPointerDown`.
  - Tracks pointer movement (`onPointerMove`) against the widget's bounds inflated by `10px`: dragging outside smoothly springs back to `1.0` (canceling visual press), while dragging back inside before release re-engages the press state.
- **WWDC Momentum Projection & Rubber-Banding (`FluidPhysics`)**:
  - `FluidPhysics.project(initialVelocity, decelerationRate: 0.998)` implements the exact exponential-decay distance formula $(v_0 / 1000) \cdot d / (1 - d)$.
  - `FluidPhysics.clampWithRubberband` implements $f(x) = (x \cdot c \cdot d) / (d + c \cdot x)$ with $c = 0.55$.
- **Reduced Motion & High Contrast**:
  - Respects `MediaQuery.maybeDisableAnimationsOf(context)` and `MediaQuery.maybeHighContrastOf(context)` across springs, route transitions, pulsing indicators, and translucent surfaces.
