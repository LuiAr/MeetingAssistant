# MeetingAssistant — Design System
> Things-inspired editorial restraint applied to a native macOS app: cool-gray canvas, white card surfaces, system SF Pro, and a single Signal Blue accent at every interactive moment.

**Theme:** light only (`preferredColorScheme(.light)` at app root)

---

## Philosophy

The design borrows from Things 3's visual language — generous whitespace, near-grayscale neutrals, and a single vivid blue accent. Applied to a native macOS app, this means:

- **Canvas / card surface language:** `Color.mist` (#f2f5f7) as the full-bleed window background; pure `Color.paper` (#ffffff) for elevated cards, panels, and inputs.
- **Accent = Signal Blue only:** `Color.signalBlue` (#2576eb) tints interactive moments — links, icons, primary actions. Never paint a large surface blue.
- **Functional color overrides:** Red and orange remain for live recording status (record dot, stop button, mute indicator). These are semantic, not brand.
- **System font throughout:** SF Pro via `.font(.system(...))` — no custom fonts. Weight and size carry hierarchy.
- **Elevation through shadow:** Cards float on the canvas via a two-layer ambient shadow. No borders.

---

## Tokens — Colors

Defined in `Sources/MeetingAssistantCore/Support/Theme.swift`:

```swift
extension Color {
    static let ink        = Color(hex: "#303336") // primary text
    static let paper      = Color.white           // card surface
    static let mist       = Color(hex: "#f2f5f7") // canvas background
    static let fog        = Color(hex: "#838b96") // secondary / helper text
    static let ash        = Color(hex: "#55606e") // tertiary text, icon strokes
    static let smoke      = Color(hex: "#44474b") // mid-emphasis body text
    static let silver     = Color(hex: "#9299a4") // disabled / de-emphasised
    static let hairline   = Color(hex: "#dfe3e8") // input borders, subtle dividers
    static let signalBlue = Color(hex: "#2576eb") // accent — links, icons, CTAs
    static let skyBlue    = Color(hex: "#5c9cf5") // secondary blue, lighter accents
}
```

| Token | Hex | Role |
|---|---|---|
| `ink` | `#303336` | Primary text — never pure black |
| `paper` | `#ffffff` | Elevated card surfaces, inputs |
| `mist` | `#f2f5f7` | Window canvas, section band backgrounds |
| `fog` | `#838b96` | Supporting / secondary copy |
| `ash` | `#55606e` | Tertiary text, icon strokes |
| `smoke` | `#44474b` | Mid-emphasis inline text |
| `silver` | `#9299a4` | Disabled or de-emphasised states |
| `hairline` | `#dfe3e8` | Input borders, list separators |
| `signalBlue` | `#2576eb` | Accent — interactive moments |
| `skyBlue` | `#5c9cf5` | Secondary blue, softer highlights |

### Functional / Semantic Colors (not design tokens)

These are not overridden by the design system — they remain system colors:

| Use | Color |
|---|---|
| Recording live dot | `.red` |
| Paused state | `.orange` |
| Success / model ready | `.green` |
| Error text | `.red` |
| Level meter clipping (>72%) | `.red` |

---

## Tokens — Typography

All text uses `Font.system(size:weight:design:)`. SF Pro is the system font on macOS — no loading required.

```swift
extension Font {
    static let caption    = Font.system(size: 13, weight: .regular)
    static let bodyText   = Font.system(size: 15, weight: .regular)
    static let subheading = Font.system(size: 18, weight: .semibold)
    static let headingSm  = Font.system(size: 20, weight: .semibold)
    static let heading    = Font.system(size: 24, weight: .bold)
    static let display    = Font.system(size: 36, weight: .bold)
}
```

| Role | Size | Weight | SwiftUI |
|---|---|---|---|
| caption | 13 | 400 | `.caption` or `.system(size: 13)` |
| body | 15 | 400 | `.system(size: 15)` |
| subheading | 18 | 600 | `.system(size: 18, weight: .semibold)` |
| heading-sm | 20 | 600 | `.system(size: 20, weight: .semibold)` |
| heading | 24 | 700 | `.system(size: 24, weight: .bold)` |
| display | 36 | 700 | `.system(size: 36, weight: .bold)` |

**Line spacing:** Apply `.lineSpacing(4)` on body paragraphs to approximate the 1.6 rhythm. Titles and single-line labels don't need extra leading.

**Timecodes / digits:** Use `.monospacedDigit()` modifier. Never `.monospaced()` for prose.

---

## Tokens — Spacing

Base unit: 4pt

```swift
enum Spacing {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let base: CGFloat = 16
    static let lg:   CGFloat = 20
    static let xl:   CGFloat = 24
    static let xl2:  CGFloat = 28
    static let xl3:  CGFloat = 36
    static let xl4:  CGFloat = 40
    static let section: CGFloat = 80
}
```

Use `Spacing.xl4` (40pt) for outer view padding. Use `Spacing.xl` (24pt) for card internal padding. Use `Spacing.md`–`Spacing.lg` for element gaps within a card.

---

## Tokens — Shape & Elevation

### Border Radius

```swift
enum Radius {
    static let icon:   CGFloat = 3
    static let input:  CGFloat = 6
    static let button: CGFloat = 6
    static let card:   CGFloat = 18
    static let pill:   CGFloat = 9999
}
```

| Element | Value |
|---|---|
| Cards, panels, GroupBox overlays | 18pt |
| Inputs, text fields | 6pt |
| Buttons (custom styled) | 6pt |
| Icon backgrounds | 3pt |
| Pill / capsule badges | Capsule() |

### Shadows

```swift
extension View {
    func cardShadow() -> some View {
        self.shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
            .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 0)
    }
}
```

Apply `.cardShadow()` to any white surface that should float above the mist canvas. Do not apply shadows to text, icons, or non-elevated elements.

---

## Surfaces

| Level | Token | Value | Purpose |
|---|---|---|---|
| Canvas | `Color.mist` | `#f2f5f7` | Window background, full-bleed bands |
| Card | `Color.paper` | `#ffffff` | Elevated panels, GroupBoxes, input areas |
| Accent | `Color(hex: "#4f91fb")` | — | Filled circular record/start control only |

---

## Components

### Canvas Background

Apply to any full-screen content area (detail pane, landing view, recorder panel):

```swift
.background(Color.mist.ignoresSafeArea())
```

For the `List`/sidebar specifically, hide the default system material and replace with mist:

```swift
List { ... }
    .scrollContentBackground(.hidden)
    .background(Color.mist)
```

---

### Card Surface

A white floating panel on the mist canvas:

```swift
VStack(alignment: .leading, spacing: Spacing.lg) {
    // content
}
.padding(Spacing.xl)
.background(Color.paper, in: RoundedRectangle(cornerRadius: Radius.card))
.cardShadow()
```

---

### Text Field

Replace `.textFieldStyle(.roundedBorder)` with a custom overlay for the hairline-border look:

```swift
TextField("Meeting title", text: $title)
    .font(.system(size: 17))
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(Color.paper, in: RoundedRectangle(cornerRadius: Radius.input))
    .overlay(
        RoundedRectangle(cornerRadius: Radius.input)
            .stroke(Color.hairline, lineWidth: 1)
    )
```

---

### Primary Action Button (Start Recording)

The design avoids rectangular filled CTAs on marketing pages, but native functional apps need clear affordances. Use a pill-shaped button with Signal Blue fill — this maps to the "circular play control" spirit:

```swift
Button(action: start) {
    Label("Start Recording", systemImage: "record.circle")
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(Color.signalBlue, in: Capsule())
        .foregroundStyle(.white)
}
.buttonStyle(.plain)
```

---

### Secondary / Destructive Buttons

Functional recording controls (Pause, Stop, Mute) keep `.buttonStyle(.bordered)` / `.buttonStyle(.borderedProminent)` with semantic tints — these are operational, not decorative.

```swift
Button { recorder.pause() } label: {
    Label("Pause", systemImage: "pause.fill")
}
.buttonStyle(.bordered)
.controlSize(.large)

Button { Task { await recorder.stop() } } label: {
    Label("Stop & Save", systemImage: "stop.fill")
}
.buttonStyle(.borderedProminent)
.tint(.red)
.controlSize(.large)
```

---

### Sidebar List Row

```swift
HStack(spacing: Spacing.sm) {
    Image(systemName: iconName)
        .foregroundStyle(Color.signalBlue)
        .frame(width: 16)

    VStack(alignment: .leading, spacing: 2) {
        Text(recording.title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.ink)

        Text(detailText)
            .font(.system(size: 13))
            .foregroundStyle(Color.fog)
    }
}
```

---

### Section Header Text

```swift
Text("Recordings")
    .font(.system(size: 13, weight: .semibold))
    .foregroundStyle(Color.ash)
    .textCase(nil)
```

---

### Hero Stack (Landing View)

Centered vertical stack on the mist canvas:

```swift
VStack(spacing: Spacing.xl2) {
    Image(systemName: "waveform.badge.mic")
        .font(.system(size: 48))
        .foregroundStyle(Color.signalBlue)

    VStack(spacing: Spacing.sm) {
        Text("MeetingAssistant")
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(Color.ink)

        Text("Capture a meeting and transcribe it locally on this Mac.")
            .font(.system(size: 17))
            .foregroundStyle(Color.fog)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: 420)
    }
    // primary action button
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.background(Color.mist.ignoresSafeArea())
```

---

### Status Badge / Pill

```swift
Text(label)
    .font(.caption2.weight(.semibold))
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(tint.opacity(0.15), in: Capsule())
    .foregroundStyle(tint)
```

---

### Inline Label + Value Row (detail panel)

```swift
LabeledContent("Duration", value: durationString)
```

Use SwiftUI's built-in `LabeledContent` inside a `.formStyle(.grouped)` form for the info inspector.

---

### Error / Warning Banner

```swift
HStack(spacing: Spacing.sm) {
    Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.callout.weight(.semibold))
        Text(subtitle).font(.caption).foregroundStyle(Color.fog)
    }
    Spacer()
    Button("Action") { ... }.buttonStyle(.bordered)
}
.padding(.vertical, Spacing.sm)
.padding(.horizontal, Spacing.md)
.background(Color.paper, in: RoundedRectangle(cornerRadius: Radius.input))
.cardShadow()
```

---

## macOS Layout

### Window / NavigationSplitView

```swift
NavigationSplitView {
    // Sidebar: mist background, no default system material
    SidebarView(...)
        .scrollContentBackground(.hidden)
        .background(Color.mist)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
} detail: {
    // Detail: mist canvas fills the full pane
    DetailView()
        .background(Color.mist.ignoresSafeArea())
}
.preferredColorScheme(.light)
```

### Toolbar

Toolbar buttons use system styling. Keep toolbar minimal — only New Recording and Settings. Do not add a background or border.

```swift
.toolbarBackground(.clear, for: .windowToolbar)
```

### Inspector Panel

The recording info panel uses `.inspector(isPresented:)` — keep this native pattern. Style its internal `Form` with `.formStyle(.grouped)` and let macOS render the standard inspector chrome.

---

## Do's and Don'ts

### Do
- Use `Color.mist` as the default background for all full-screen views.
- Use `Color.paper` + `.cardShadow()` for any panel or card floating above the canvas.
- Tint the app root with `Color.signalBlue`: `.tint(Color.signalBlue)`.
- Use `Color.ink` for primary text, `Color.fog` for supporting/secondary copy.
- Apply `.preferredColorScheme(.light)` at the `WindowGroup` level — this is a light-only design.
- Use `.monospacedDigit()` for timecodes and numeric readouts.
- Keep section/group gaps at 24–40pt; outer view padding at 40pt.
- Use `Capsule()` or `RoundedRectangle(cornerRadius: Radius.card)` for card shapes; 6pt for inputs and buttons.

### Don't
- Don't use pure `Color.black` for text — `Color.ink` is the darkest text value.
- Don't apply `.cardShadow()` to text, icons, toolbars, or list rows — only elevated card surfaces.
- Don't override semantic status colors (red for recording, orange for paused) — they are functional, not branded.
- Don't use `Color.signalBlue` as a large surface fill — accent color is for icons, links, and compact control fills only.
- Don't use `.monospacedDigit()` or `.monospaced()` for prose body text.
- Don't hardcode magic color or spacing literals in view files — always use the tokens from `Theme.swift`.
- Don't apply `.toolbarBackground(.automatic)` — toolbar should float on the canvas without a fill.

---

## Swift Quick Start — `Theme.swift`

Create `Sources/MeetingAssistantCore/Support/Theme.swift`:

```swift
import SwiftUI

// MARK: - Colors

extension Color {
    static let ink        = Color(hex: "#303336")
    static let paper      = Color.white
    static let mist       = Color(hex: "#f2f5f7")
    static let fog        = Color(hex: "#838b96")
    static let ash        = Color(hex: "#55606e")
    static let smoke      = Color(hex: "#44474b")
    static let silver     = Color(hex: "#9299a4")
    static let hairline   = Color(hex: "#dfe3e8")
    static let signalBlue = Color(hex: "#2576eb")
    static let skyBlue    = Color(hex: "#5c9cf5")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Typography

extension Font {
    static let designCaption    = Font.system(size: 13, weight: .regular)
    static let designBody       = Font.system(size: 15, weight: .regular)
    static let designSubheading = Font.system(size: 18, weight: .semibold)
    static let designHeadingSm  = Font.system(size: 20, weight: .semibold)
    static let designHeading    = Font.system(size: 24, weight: .bold)
    static let designDisplay    = Font.system(size: 36, weight: .bold)
}

// MARK: - Spacing

enum Spacing {
    static let xs:      CGFloat = 4
    static let sm:      CGFloat = 8
    static let md:      CGFloat = 12
    static let base:    CGFloat = 16
    static let lg:      CGFloat = 20
    static let xl:      CGFloat = 24
    static let xl2:     CGFloat = 28
    static let xl3:     CGFloat = 36
    static let xl4:     CGFloat = 40
    static let section: CGFloat = 80
}

// MARK: - Border Radius

enum Radius {
    static let icon:   CGFloat = 3
    static let input:  CGFloat = 6
    static let button: CGFloat = 6
    static let card:   CGFloat = 18
}

// MARK: - Elevation

extension View {
    func cardShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
            .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 0)
    }
}
```
