# Theming, Animations, and Resource Patterns

Reference for implementing visual features in iNiR: blur backdrops, panel slide animations, entry/exit choreography, and design token usage.

## Blur Backdrop Pattern

Wayland layer-shell surfaces cannot capture what's beneath them. iNiR fakes blur by rendering a copy of the wallpaper at screen size and applying `MultiEffect` blur.

### Standard implementation (GlassBackground.qml)

```qml
// Parent must supply screenX, screenY for correct blur positioning
Image {
    x: -root.screenX
    y: -root.screenY
    width: root.screenWidth
    height: root.screenHeight
    source: root.wallpaperUrl     // from Wallpapers.effectiveWallpaperUrl
    fillMode: Image.PreserveAspectCrop
    cache: true
    asynchronous: true
    sourceSize.width: root.screenWidth
    sourceSize.height: root.screenHeight

    layer.enabled: Appearance.effectsEnabled
    layer.effect: MultiEffect {
        blurEnabled: Appearance.effectsEnabled
        blurMax: 100
        blur: Appearance.effectsEnabled ? 1 : 0
        saturation: 0.2
    }
}
```

### Fullscreen blur (e.g. WallpaperCoverflow)

For fullscreen overlays, use edge compensation to prevent blur fade at boundaries:

```qml
readonly property int blurOverflow: 64

Item {
    id: blurSource
    anchors.fill: parent
    anchors.margins: -blurOverflow

    Image {
        anchors.fill: parent
        anchors.margins: blurOverflow   // counteract parent overflow
        source: WallpaperListener.wallpaperUrlForScreen(panelWindow.screen)
        fillMode: Image.PreserveAspectCrop
        cache: true
        asynchronous: true
        sourceSize.width: screen.width
        sourceSize.height: screen.height
    }
}

MultiEffect {
    source: blurSource
    anchors.fill: parent
    anchors.margins: -blurOverflow
    blurEnabled: Appearance.effectsEnabled
    blurMax: 64
    blur: 1.0
    saturation: 0.15
}
```

### Wallpaper URL resolution

- **Single monitor:** `Wallpapers.effectiveWallpaperUrl`
- **Per-screen:** `WallpaperListener.wallpaperUrlForScreen(screen)` — requires dependency triggers:
  ```qml
  source: {
      const _dep1 = WallpaperListener.multiMonitorEnabled
      const _dep2 = WallpaperListener.effectivePerMonitor
      const _dep3 = Wallpapers.effectiveWallpaperUrl
      return WallpaperListener.wallpaperUrlForScreen(panelWindow.screen)
  }
  ```

### Scrim over blur

Always add a semi-transparent Rectangle over the blur for readability:
```qml
Rectangle {
    anchors.fill: parent
    color: Appearance.colors.colScrim
    opacity: 0.55
}
```

Optional vignette for depth:
```qml
GE.RadialGradient {
    anchors.fill: parent
    gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.6; color: "transparent" }
        GradientStop { position: 1.0; color: ColorUtils.applyAlpha(Appearance.colors.colScrim, 0.4) }
    }
}
```

## Panel Slide Animation Pattern

### How auto-hide works (Bar, Dock, VerticalBar)

Panels use anchor margins to slide off-screen. The key is using negative margins equal to the panel's height/width.

**Bar (top):**
```qml
anchors.topMargin: shouldHide ? -Appearance.sizes.barHeight : 0
Behavior on anchors.topMargin {
    animation: NumberAnimation {
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }
}
```

**Dock (bottom):**
```qml
property real hideOffset: reveal ? 0 : (hoverToReveal ? (implicitHeight - hoverRegion) : (implicitHeight + 1))
anchors.topMargin: position === "bottom" ? hideOffset : 0
```

### Adding a new hide condition

To make panels react to a global state (e.g. `coverflowSelectorOpen`), add it with `||` to the existing hide condition:

```qml
// Bar: topMargin hides when autoHide active OR coverflow open
topMargin: ((Config?.options.bar.autoHide.enable && !mustShow) || GlobalStates.coverflowSelectorOpen) ? -Appearance.sizes.barHeight : 0

// Dock: prepend to reveal condition
reveal: !GlobalStates.coverflowSelectorOpen && (root.pinned || ...)

// Bar exclusiveZone: also drop to 0 during hide
exclusiveZone: (GlobalStates.coverflowSelectorOpen || (autoHide && ...)) ? 0 : normalZone
```

The existing Behaviors handle the animation automatically — no new animation code needed.

### Files to edit for each panel type

| Panel | File | Hide mechanism |
|-------|------|---------------|
| Top bar | `modules/bar/Bar.qml` | `anchors.topMargin` / `anchors.bottomMargin` (bottom state) + `exclusiveZone` |
| Vertical bar | `modules/verticalBar/VerticalBar.qml` | `anchors.leftMargin` / `anchors.rightMargin` (right state) + `exclusiveZone` |
| Dock | `modules/dock/Dock.qml` | `reveal` property → `hideOffset` / `hideOffsetV` margins |

## Entry/Exit Animation Pattern for Overlay Panels

### Problem
`Loader { active: someState }` destroys the component instantly when `someState` becomes false. No exit animation is possible.

### Solution: _closing gate pattern

```qml
Scope {
    property bool _closing: false

    Connections {
        target: GlobalStates
        function onSomeStateChanged() {
            if (!GlobalStates.someState && theLoader.item) {
                _closing = true
                theLoader.item._entryReady = false
                theLoader.item._contentReady = false
                _closeTimer.start()
            }
        }
    }

    Timer {
        id: _closeTimer
        interval: Appearance.animationsEnabled ? 450 : 0
        onTriggered: _closing = false
    }

    Loader {
        active: GlobalStates.someState || root._closing

        sourceComponent: PanelWindow {
            property bool _entryReady: false
            property bool _contentReady: false

            // Keyboard focus off during close to not block input
            WlrLayershell.keyboardFocus: root._closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand

            // Entry: set _entryReady and _contentReady to true with stagger
            Component.onCompleted: {
                Qt.callLater(() => _entryReady = true)
                contentEntryTimer.start()
            }

            // The scrim/backdrop binds opacity to _entryReady
            // The content binds scale/opacity/y to _contentReady
            // Behaviors animate both directions automatically
        }
    }
}
```

### Staggered entry choreography

1. Loader creates the PanelWindow
2. `Component.onCompleted` → `Qt.callLater(() => _entryReady = true)` (scrim fades in)
3. After 80ms delay → `_contentReady = true` (content scales/fades in)
4. Behaviors on opacity, scale, y animate the transition

### Exit choreography

1. `_closing = true` keeps Loader alive
2. `_entryReady = false` → scrim fades out
3. `_contentReady = false` → content reverses (scale, opacity, y)
4. Timer (450ms) → `_closing = false` → Loader destroys

### Important: CompositorFocusGrab during close

```qml
CompositorFocusGrab {
    active: CompositorService.isHyprland && theLoader.active && !root._closing
}
```

## Design Token Usage

### ii (Material Design)
- Colors: `Appearance.colors.col*` (colPrimary, colOnSurface, colLayer0, etc.)
- M3 colors: `Appearance.m3colors.*` (m3background, m3onSurface, darkmode)
- Font: `Appearance.font.family.main`, `Appearance.font.pixelSize.*`
- Rounding: `Appearance.rounding.normal`, `Appearance.rounding.large`
- Animation: `Appearance.animation.elementMoveFast.*` (duration, type, bezierCurve)
- Curves: `Appearance.animationCurves.emphasizedDecel`, `.emphasizedAccel`
- Duration helper: `Appearance.calcEffectiveDuration(ms)` — respects animation speed settings
- Effects check: `Appearance.effectsEnabled`, `Appearance.animationsEnabled`

### Waffle (Windows 11)
- Colors: `Looks.colors.*` (bg0, bg1, fg, subfg, accent)
- Font: `Looks.font.family.ui`, `Looks.font.pixelSize.*`
- Radius: `Looks.radius.*` (small, medium, large, xLarge)
- Curves: `Looks.transition.easing.bezierCurve.decelerate`, `.accelerate`

### NEVER
- Hardcode colors, radii, fonts, or durations
- Use `Appearance.*` in waffle components or `Looks.*` in ii components
- Use `ColorUtils.transparentize()` without checking which color system you're in

## Icon Colorization

To tint an SVG icon with a theme color:
```qml
Image {
    source: "path/to/icon.svg"
    layer.enabled: Appearance.effectsEnabled
    layer.effect: MultiEffect {
        colorization: 1.0
        colorizationColor: Appearance.colors.colOnPrimaryContainer
    }
}
```

## Color Snapshotting for Transitions

When a transition overlay runs while the theme is changing (e.g. panel family switch triggers a palette rebuild), snapshot colors at the start:

```qml
property color _snapPrimary: "transparent"
// In the trigger:
root._snapPrimary = Appearance.colors.colPrimary
// Use _snapPrimary in the overlay, not the live binding
```

## Anti-aliasing for Masked Shapes

For shapes using `layer.effect: OpacityMask` (like parallelogram cards):
- Mask source items: `layer.samples: 8`
- Image container: `layer.samples: 4`
- Lower values cause jagged edges, higher values are unnecessary GPU cost

## Files Reference

| Pattern | Primary example | Notes |
|---------|----------------|-------|
| Glass blur | `modules/common/widgets/GlassBackground.qml` | Position-aware, reusable |
| Fullscreen blur | `modules/wallpaperSelector/WallpaperCoverflow.qml` | blurOverflow compensation |
| Backdrop blur | `modules/background/Backdrop.qml` | Multiple blur sources |
| Panel slide | `modules/bar/Bar.qml`, `modules/dock/Dock.qml` | Margin-based with Behaviors |
| Entry/exit overlay | `modules/wallpaperSelector/WallpaperCoverflow.qml` | _closing gate pattern |
| Family transition | `FamilyTransitionOverlay.qml` | Explicit NumberAnimation choreography |
| Color pipeline | `services/MaterialThemeLoader.qml` → `Appearance.qml` | File watch + token injection |
