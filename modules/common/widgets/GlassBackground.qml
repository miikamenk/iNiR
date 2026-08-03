import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import Quickshell

// Hidden instances release their blur FBO; decoded wallpaper pixmaps remain shared.
Rectangle {
    id: root
    
    property color fallbackColor: Appearance.colors.colLayer1
    property color inirColor: Appearance.inir.colLayer1
    // Real-glass surface tint. Defaults to the same wallpaper-blended layer0
    // the bar and sidebars use (see below), so every glass surface reads as
    // one material — raw colLayer0Base is near-black next to them.
    property color realGlassColor: ColorUtils.applyAlpha(
        root.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0,
        Appearance.panelSurfaceAlpha)

    // Wallpaper-blended tint, same recipe as SidebarRightContent/BarContent.
    // The quantizer only runs when a glass style actually paints with it.
    ColorQuantizer {
        id: glassQuantizer
        source: (Appearance.liquidRealGlass || root.useWallpaperBackdrop || Appearance.angelEverywhere)
            ? Wallpapers.effectiveWallpaperUrl : ""
        depth: 0
        rescaleSize: 10
    }
    readonly property color wallpaperDominantColor: glassQuantizer.colors?.[0] ?? Appearance.colors.colPrimary
    readonly property QtObject blendedColors: AdaptedMaterialScheme {
        color: ColorUtils.mix(root.wallpaperDominantColor, Appearance.colors.colPrimaryContainer, 0.8)
            || Appearance.m3colors.m3secondaryContainer
    }
    property real auroraTransparency: Appearance.aurora.popupTransparentize
    property bool wallpaperBackdropEnabled: true
    
    // Screen-relative position for blur alignment (set by parent)
    property real screenX: 0
    property real screenY: 0
    property real screenWidth: Quickshell.screens[0]?.width ?? 1920
    property real screenHeight: Quickshell.screens[0]?.height ?? 1080
    
    readonly property bool angelEverywhere: Appearance.angelEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere
    readonly property bool inirEverywhere: Appearance.inirEverywhere
    // Bypasses the style gate, which is what its callers always documented it as
    // doing. It used to be AND-ed inside the backend check, so a surface asking
    // for a backdrop outside aurora — island glass, or a backdrop the user turned
    // on explicitly — silently got nothing. The effects gate still applies.
    property bool forceBackdrop: false
    // Blur radius as a fraction of blurMax. 1 is the house default every existing
    // caller inherits; lower values are for surfaces that expose it to the user.
    property real blurStrength: 1
    readonly property bool liquidEverywhere: Appearance.liquidEverywhere
    // Real glass paints genuine alpha and lets the compositor show what is
    // actually behind the panel, so the blurred wallpaper copy is skipped.
    readonly property bool realGlass: Appearance.liquidRealGlass
    readonly property bool useWallpaperBackdrop: root.realGlass ? false
        : root.forceBackdrop
            ? Appearance.effectsEnabled
            : (Appearance.blurBackendFor("panels", Appearance.blurTopology.unsupported) === "wallpaper"
                && root.wallpaperBackdropEnabled)
    // The shader's edge refraction needs a wallpaper texture even in real-glass
    // mode, where nothing is painted from it. Loading it here (without painting)
    // is what lets panels refract at all — the bar already had one, because it
    // paints its wallpaper copy regardless of realGlass.
    readonly property bool wantsRefractionTexture: root.liquidEverywhere
        && Appearance.liquid.shaderEnabled && Appearance.effectsEnabled
        && Appearance.liquid.shaderRefraction > 0

    color: root.realGlass ? root.realGlassColor
        : root.useWallpaperBackdrop ? "transparent"
        : root.inirEverywhere ? root.inirColor
        : root.fallbackColor
    
    property bool hovered: false

    border.width: 0
    border.color: "transparent"

    clip: true
    
    // Hidden persistent surfaces must not retain their mask FBO. The decoded
    // wallpaper stays in Qt's shared image cache, so remapping remains warm.
    layer.enabled: root.useWallpaperBackdrop && root.visible
    layer.effect: GE.OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
        }
    }
    
    // Blurred wallpaper backdrop for aurora/angel styles.
    // OPTIMIZATION: layer.enabled is only active when the GlassBackground is
    // actually visible, reducing GPU memory when panels are hidden.
    Image {
        id: blurredWallpaper
        x: -root.screenX
        y: -root.screenY
        width: root.screenWidth
        height: root.screenHeight
        visible: root.useWallpaperBackdrop && status === Image.Ready
        // Loaded — but not painted — when only the shader wants it. An Image is
        // a texture provider regardless of visibility (the documented Qt
        // ShaderEffect pattern), so this costs a shared pixmap, not a draw.
        source: (root.useWallpaperBackdrop || root.wantsRefractionTexture)
            ? Wallpapers.effectiveWallpaperUrl : ""
        fillMode: Image.PreserveAspectCrop
        // All GlassBackground instances share the same wallpaper URL and sourceSize,
        // so Qt's QPixmapCache serves a single decoded pixmap to all of them.
        cache: true
        asynchronous: true
        // Constrain decoded size to screen dimensions — the blur doesn't need more.
        sourceSize.width: root.screenWidth
        sourceSize.height: root.screenHeight

        // CRITICAL: Only enable blur layer when VISIBLE AND enabled.
        // This releases the FBO when the panel is hidden, saving ~16 MiB per instance.
        layer.enabled: Appearance.effectsEnabled && root.useWallpaperBackdrop && root.visible
        layer.effect: MultiEffect {
            source: blurredWallpaper
            anchors.fill: source
            saturation: root.angelEverywhere
                ? (Appearance.angel.blurSaturation * Appearance.angel.colorStrength)
                : root.liquidEverywhere
                    ? Appearance.liquid.blurSaturation
                    : (Appearance.effectsEnabled ? 0.2 : 0)
            blurEnabled: Appearance.effectsEnabled
            blurMax: 64
            blur: Appearance.effectsEnabled
                ? (root.angelEverywhere ? Appearance.angel.blurIntensity
                    : root.liquidEverywhere ? Appearance.liquid.blurIntensity
                    : root.blurStrength)
                : 0
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.useWallpaperBackdrop
        color: root.angelEverywhere
            ? ColorUtils.transparentize(Appearance.colors.colLayer0Base, Appearance.angel.overlayOpacity)
            : root.liquidEverywhere
                ? ColorUtils.transparentize(Appearance.colors.colLayer0Base, Appearance.liquid.popupTransparentize)
                : ColorUtils.transparentize(Appearance.colors.colLayer0Base, root.auroraTransparency)
    }

    // ─── Liquid glass decorations (liquid only) ───
    LiquidGlassEdges {
        sheenOverContent: root.useWallpaperBackdrop || root.realGlass
        surfaceRadius: root.radius
        // The shader can refract the wallpaper at the rim, but only where the
        // surface genuinely paints it. In real-glass mode the compositor shows
        // the actual windows, so there is nothing of ours to bend.
        // An Image is a texture provider natively, so this costs no extra FBO —
        // and it hands over the *sharp* wallpaper, since an item's provider
        // exposes its pre-effect content rather than the MultiEffect blur. That
        // is the right source anyway: a real bevel is sharper than the body.
        // Ready rather than visible: in real-glass mode the image is loaded for
        // the shader but never painted. Sampling an unloaded provider would fall
        // back to Qt's dummy texture.
        backdropSource: blurredWallpaper.status === Image.Ready ? blurredWallpaper : null
        backdropOrigin: Qt.point(root.screenX, root.screenY)
        backdropScreen: Qt.size(root.screenWidth, root.screenHeight)
    }

    // Inset glow — light-from-above on top edge, angel only
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Appearance.angel.insetGlowHeight
        visible: root.angelEverywhere
        color: Appearance.angel.colInsetGlow
    }

    // Partial border — elegant half-borders, angel only
    AngelPartialBorder {
        targetRadius: root.radius
        hovered: root.hovered
    }
}
