---
name: Editorial Tactility
colors:
  surface: '#fff8f8'
  surface-dim: '#ebd5d9'
  surface-bright: '#fff8f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#fff0f2'
  surface-container: '#ffe8ec'
  surface-container-high: '#f9e3e7'
  surface-container-highest: '#f3dde1'
  on-surface: '#24181b'
  on-surface-variant: '#564243'
  inverse-surface: '#3a2d30'
  inverse-on-surface: '#ffecef'
  outline: '#897173'
  outline-variant: '#ddc0c1'
  surface-tint: '#a4384a'
  primary: '#4b0014'
  on-primary: '#ffffff'
  primary-container: '#6e0d25'
  on-primary-container: '#f77788'
  inverse-primary: '#ffb2b9'
  secondary: '#ba0032'
  on-secondary: '#ffffff'
  secondary-container: '#e41944'
  on-secondary-container: '#fffbff'
  tertiary: '#242022'
  on-tertiary: '#ffffff'
  tertiary-container: '#3a3538'
  on-tertiary-container: '#a49ea0'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffdadc'
  primary-fixed-dim: '#ffb2b9'
  on-primary-fixed: '#400010'
  on-primary-fixed-variant: '#852034'
  secondary-fixed: '#ffdada'
  secondary-fixed-dim: '#ffb3b5'
  on-secondary-fixed: '#40000b'
  on-secondary-fixed-variant: '#920025'
  tertiary-fixed: '#e9e0e3'
  tertiary-fixed-dim: '#ccc4c7'
  on-tertiary-fixed: '#1e1b1d'
  on-tertiary-fixed-variant: '#4a4548'
  background: '#fff8f8'
  on-background: '#24181b'
  surface-variant: '#f3dde1'
typography:
  headline-xl:
    fontFamily: Newsreader
    fontSize: 48px
    fontWeight: '400'
    lineHeight: 54px
    letterSpacing: -0.02em
  headline-xl-mobile:
    fontFamily: Newsreader
    fontSize: 32px
    fontWeight: '400'
    lineHeight: 38px
    letterSpacing: -0.015em
  headline-lg:
    fontFamily: Newsreader
    fontSize: 36px
    fontWeight: '400'
    lineHeight: 42px
    letterSpacing: -0.015em
  headline-lg-mobile:
    fontFamily: Newsreader
    fontSize: 26px
    fontWeight: '400'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Newsreader
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 30px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Newsreader
    fontSize: 20px
    fontWeight: '500'
    lineHeight: 26px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 13px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.04em
  label-micro:
    fontFamily: Plus Jakarta Sans
    fontSize: 9px
    fontWeight: '700'
    lineHeight: 12px
    letterSpacing: 0.08em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1.25rem
  gutter-mobile: 0.75rem
  margin: 2.5rem
  margin-mobile: 1.25rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

The design system establishes an unapologetically deliberate, tactile, and editorial atmosphere for high-fidelity, album-centric listening. Rooted in the visual weight of independent print journals, prestige vinyl packaging, and analog playback equipment, the interface rejects algorithmic modernism—dispensing with generic blurred gradients, floating pill bubbles, and ungrounded elevation.

Visual tension is created by pairing stately, literary serif display typography with austere, Swiss-inspired typographic utility. The experience treats album art and track structures as sacred cultural artifacts: sharp structural anchors, physical framing rules, and tactile micro-states evoke the precision of Dieter Rams audio gear combined with the literary severity of broadsheet editorial culture. The user feels like a curator and archivist, not an unthinking subscriber processing an infinite feed.

## Colors

The palette is anchored by the tactile tact of raw exhibition paper, vintage vinyl liner notes, and deep, vintage wine-red inks:

- **Base Canvas (`#F9F8F6` - Chalk):** The primary paper substrate. A warm, mineral-hued white that prevents screen glare and sets a quiet, library-grade tone.
- **Surface Elevation (`#ECEAE6` - Linen Paper):** Reserved for nested cards, tracklist headers, player trays, and modal sidebars.
- **Deep Charcoal (`#1A0F12`):** Rich, ink-weight neutral black with an imperceptible warm undertone. Used for main titles, active typography, and structural lines.
- **Muted Dust (`#7A7274`):** Mid-tone neutral for supporting metadata (sample rate, release year, duration, track artists, liner notes).
- **Subtle Borders (`#E2DFD9`):** Thin hairline rules that delimit layout sections, track rows, and structural panes without visual heaviness.
- **Bordeaux Accent (`#6E0D25`):** The primary brand anchor. Evokes aged red bookcloth and classic jazz record center-labels. Applied to active navigation indicators, elapsed waveform tracks, active audio routings, and primary controls.
- **Punch Highlight (`#FF3355`):** A razor-sharp neon-crimson used exclusively in micro-doses: the active heart/favorite state, a live recording indicator dot, or high-res lossless streaming badging.
- **Waveform Inactive (`#D5CDD0`):** Neutral taupe-grey reserved for upcoming, unplayed audio ticks and secondary track scrub lines.

## Typography

The typographical hierarchy is constructed on deliberate contrast: literary contemplation juxtaposed with crisp, high-precision technical information.

- **Headlines & Editorial Statements (`Newsreader`):** Rendered with natural proportional rhythm and classic serif flourishes. Album titles, section overtures, editorial essays, and artist narratives live exclusively here. It grounds the player in archival authenticity.
- **Interface, Track Data & Metrics (`Plus Jakarta Sans`):** Clean, structural, and neutral. Track names, timecodes, bitrates (`24-bit / 192kHz FLAC`), audio controls, and index numbering use this sans-serif for absolute clarity.
- **Micro Labels & Counters:** Track numbers are styled with monospaced tabular alignment (`font-variant-numeric: tabular-nums;`) to form immaculate linear columns down tracklists.

## Layout & Spacing

The layout operates on a disciplined 12-column grid for desktop views, collapsing to 6 columns on tablet and 4 columns on mobile. 

- **Desktop (>= 1200px):** 2.5rem (`margin`) canvas margins with 1.25rem (`gutter`) gutters. The player follows a split architecture: an expansive left or bottom deck anchored to the current album sleeve and tactile waveform console, leaving the primary columns for multi-column record crate exploration and rich tracklist liner notes.
- **Tablet (768px - 1199px):** 2rem canvas margins with 1rem gutters. Artwork drops to fixed aspect ratios, and controls condense into a persistent bottom dock.
- **Mobile (< 768px):** 1.25rem (`margin-mobile`) margins with 0.75rem (`gutter-mobile`) gutters. Spacing pivots from sprawling margins to vertical rhythm, maintaining density without claustrophobia.

The spacing rhythm is calculated: internal element padding sits tight (`space-xs` and `space-sm`) to emulate physical instrument dials and printed indices, while structural whitespace (`space-lg` and `space-xl`) provides breathing room between master sections.

## Elevation & Depth

This system avoids software skeuomorphism like artificial drop shadows, blurred or semi-transparent backdrops, and synthetic neon halos. Visual hierarchy and layer separation are built through **tonal paper layering** and **fine architectural rules**:

1. **Substrate Separation:** The core background is Chalk (`#F9F8F6`). Floating decks, transport drawers, and drawer trays sit on Linen (`#ECEAE6`).
2. **Hairline Delimitation:** Surfaces are bound by 1px solid borders (`#E2DFD9`). Never use thick heavy borders. Structure is felt through clean edge contrast rather than drop shadow offset.
3. **Physical Pressed States:** Hover states employ subtle background shifts (`#E2DFD9` at 40% tint), while active mouse-down states shift elements inward by 1px translateY with a darker keyline, imitating a physical micro-switch.
4. **Artwork Depth:** Album artwork uses an imperceptible, tight contact edge (`box-shadow: 0 1px 2px rgba(26, 15, 18, 0.08)`) simulating the physical thickness of heavy-stock vinyl sleeves resting on a drafting desk.

## Shapes

The shape system strictly uses **Soft (`roundedness: 1`)** geometry:
- Default elements (buttons, inputs, status badges, artwork frame containers) maintain a crisp 4px (`0.25rem`) corner radius.
- Larger nested panels, playback docks, and dialogs utilize an 8px (`0.5rem`) corner radius.
- Circular shapes (100% radius) are reserved strictly for circular controls (play/pause main button, needle drop indicators, volume knobs).

Pill-shaped bubbles, rounded stadium tags, and soft, gelatinous edges are forbidden; sharp geometric purity preserves the tactile feel of physical hi-fi components.

## Components

### Waveform Playback Bar (Signature)
- **Structure:** A dense sequence of discrete 2px-wide vertical bars spaced 2px apart across the full container width.
- **States:**
  - *Elapsed:* Filled with Bordeaux Accent (`#6E0D25`).
  - *Unplayed:* Filled with Waveform Neutral (`#D5CDD0`).
  - *Hover Scrubber:* A 1px vertical hairline in Deep Charcoal (`#1A0F12`) accompanies a floating micro-tooltip showing precise MM:SS.
  - *Playhead Indicator:* A 4px sharp tick capping the active point.

### Buttons & Transport Controls
- **Primary Action (Play/Pause, Purchase Album):** Solid Bordeaux (`#6E0D25`) fill with Chalk (`#F9F8F6`) typography, 4px border radius, strictly no shadows. Tactile depression on press.
- **Secondary Action (Shuffle, Repeat, Queue):** Chalk background with a 1px border (`#E2DFD9`), text in Deep Charcoal (`#1A0F12`). On active toggling, border and icon transition to Bordeaux (`#6E0D25`) with a 4px square tint badge.
- **Micro Controls:** Minimal padding (`4px 8px`), uppercase `label-micro` typography.

### Tracklist & List Items
- **Row Architecture:** 40px fixed height for high density. Separated by hairline borders (`1px solid #E2DFD9`).
- **Columns:** Fixed index number (tabular sans), track title (Deep Charcoal medium), audio quality chip (Lossless/Hi-Res), and right-aligned duration.
- **Active Track State:** Row background tints to Linen Paper (`#ECEAE6`); track title shifts to Bordeaux (`#6E0D25`); an animated 3-bar miniature equalizer micro-icon rendered in Bordeaux displays beside the track index.

### Badges & Chips
- **Format:** Tight rectangular tags with 2px corner radius. No rounded pills.
- **Hi-Res Audio Badges:** Subtle Linen fill (`#ECEAE6`), hairline border (`#E2DFD9`), text in Muted Dust (`#7A7274`) at `label-micro`.
- **Live / Dynamic Status:** Neutral background with a single 4px circular dot colored in Punch (`#FF3355`).

### Album Cards & Grid
- **Framing:** 1:1 square ratio for artwork with a 1px protective hairline border (`#E2DFD9`). 
- **Typography Block:** Positioned immediately below the sleeve; Album Title in `Newsreader` (headline-sm), Artist in `Plus Jakarta Sans` (body-sm, Muted Dust).
- **Physicality:** Artwork does not zoom on hover; instead, an archival linen slip-shadow shifts down 2px.

### Inputs & Volume Slider
- **Search & Fields:** Flat Chalk canvas with a bottom hairline border that darkens to Bordeaux on focus. No surrounding bubble enclosure.
- **Volume Fader:** A continuous horizontal 2px line in Waveform Neutral (`#D5CDD0`), filled with Deep Charcoal (`#1A0F12`), anchored by a 10px square notched brass-style thumb.