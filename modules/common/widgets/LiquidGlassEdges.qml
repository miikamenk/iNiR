pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick

// Liquid glass decorations: sheen, specular gleam and edge rim for liquid surfaces.
//
// Two interchangeable implementations, picked by Appearance.liquid.shaderEnabled:
//
//   Gradient path (default) — five stacked Rectangles, back to front:
//     1. Sheen — subtle top-down light gradient, like light catching the surface
//     2. Specular gleam — soft diagonal band raked across the pane
//     3. Refraction rim — hairline inset border on all four edges
//     4. Top edge highlight — 1px light-from-above inner border
//     5. Bottom edge shade — faint dark line that grounds the panel
//   Horizontal fades dissolve the lines into rounded corners.
//
//   Shader path (opt-in) — one ShaderEffect pass over a rounded-box SDF. Same
//   five effects, but the rim brightness follows the surface normal, so the
//   highlight wraps the rounded corners instead of running straight across the
//   top, and the edge picks up a chromatic fringe. Where a wallpaper texture is
//   available it also refracts it. Falls back to the gradient path whenever
//   effects are disabled (low power / game mode).
//
// Usage: place as the LAST child of the surface so it paints above content
// backgrounds; the parent must be clipped (clip: true or an OpacityMask) unless
// the shader path is active, which masks itself.
Item {
    id: root
    anchors.fill: parent

    // Sheen is a background-ish effect; edges are foreground details.
    // Set this false when placing the component above content (sheen would wash it out).
    property bool sheenOverContent: false
    // Corner radius of the surface, so the rim can follow it. Falls back to the
    // parent's radius when the parent is a Rectangle.
    property real surfaceRadius: parent?.radius ?? 0
    // The rim is what gives a see-through panel a defined edge, so it matters
    // most in real-glass mode — but it is cheap and looks right either way.
    property bool rimEnabled: true

    // ─── Optional backdrop, for the refracting shader variant ───
    // A texture provider holding the wallpaper (an Image is one natively, at no
    // FBO cost). Only pass one where the surface genuinely paints the wallpaper:
    // with real transparency on, the compositor shows the actual windows and a
    // refracted wallpaper fringe would be a lie.
    property Item backdropSource: null
    // Top-left of this surface in screen coordinates, and the screen size —
    // together they map panel-local UVs into the wallpaper texture.
    property point backdropOrigin: Qt.point(0, 0)
    property size backdropScreen: Qt.size(0, 0)

    visible: Appearance.liquidEverywhere
    z: 10

    readonly property bool shaderMode: Appearance.liquid.shaderEnabled && Appearance.effectsEnabled
    // At zero strength the refraction pass is a no-op, so drop to the cheaper
    // sampler-less shader rather than paying for texture fetches that do nothing.
    readonly property bool refracting: root.shaderMode && root.backdropSource !== null
        && root.backdropScreen.width > 0 && root.backdropScreen.height > 0
        && Appearance.liquid.shaderRefraction > 0

    // backdropUV = glassMap.xy + uv * glassMap.zw
    //
    // Two mappings composed: panel-local UV into screen-normalised coordinates,
    // then screen-normalised into the texture, undoing PreserveAspectCrop. The
    // crop math lives here rather than in the shader so it stays debuggable.
    readonly property vector4d glassMap: {
        const sw = root.backdropScreen.width;
        const sh = root.backdropScreen.height;
        if (sw <= 0 || sh <= 0)
            return Qt.vector4d(0, 0, 1, 1);

        const iw = root.backdropSource?.implicitWidth ?? 0;
        const ih = root.backdropSource?.implicitHeight ?? 0;
        // Before the image reports a size, sample it unstretched rather than
        // dividing by zero; it corrects itself on load.
        const imgAspect = (iw > 0 && ih > 0) ? (iw / ih) : (sw / sh);
        const scrAspect = sw / sh;

        // Fraction of the texture the cropped fill actually shows.
        const fw = Math.min(1, scrAspect / imgAspect);
        const fh = Math.min(1, imgAspect / scrAspect);
        const u0 = (1 - fw) / 2;
        const v0 = (1 - fh) / 2;

        return Qt.vector4d(
            u0 + fw * (root.backdropOrigin.x / sw),
            v0 + fh * (root.backdropOrigin.y / sh),
            fw * (root.width / sw),
            fh * (root.height / sh));
    }

    // `visible` reads as effective visibility, so a hidden popup holds no node.
    Loader {
        anchors.fill: parent
        active: root.visible && !root.shaderMode
        sourceComponent: gradientEdges
    }

    Loader {
        anchors.fill: parent
        active: root.visible && root.shaderMode
        sourceComponent: shaderEdges
    }

    Component {
        id: shaderEdges

        ShaderEffect {
            // These names must match the members of `buf` in LiquidGlass.frag /
            // LiquidGlassRefract.frag one for one. A mismatch is silent apart
            // from a "does not have a matching property" warning, and the
            // uniform reads as zero.
            property size glassSize: Qt.size(width, height)
            property real glassRadius: root.surfaceRadius
            property real glassBevel: Appearance.liquid.shaderBevel
            property real glassRim: Appearance.liquid.shaderRimWidth
            property real glassDisp: Appearance.liquid.shaderDispersion
            property point glassLight: Appearance.liquid.shaderLightDir

            // Refraction-only uniforms. Harmless on the sampler-less shader —
            // Qt only looks up members the shader actually declares.
            property real glassRefract: Appearance.liquid.shaderRefraction
            property vector4d glassMap: root.glassMap
            property variant backdrop: root.backdropSource

            // Disabled sub-effects pass a fully transparent colour rather than a
            // flag uniform: premultiplied "transparent" is vec4(0) and drops out
            // of the shader's accumulation for free.
            property color colEdge: (root.rimEnabled && Appearance.liquid.edgeHighlightEnabled)
                ? Appearance.liquid.colEdgeHighlight : "transparent"
            property color colShade: Appearance.liquid.edgeHighlightEnabled
                ? Appearance.liquid.colEdgeShade : "transparent"
            property color colSpecular: Appearance.liquid.specularEnabled
                ? Appearance.liquid.colSpecular : "transparent"
            property color colSheen: (Appearance.liquid.sheenEnabled && root.sheenOverContent)
                ? Appearance.liquid.colSheen : "transparent"

            blending: true
            fragmentShader: root.refracting ? "LiquidGlassRefract.qsb" : "LiquidGlass.qsb"

            onStatusChanged: {
                if (status === ShaderEffect.Error)
                    console.warn("[LiquidGlassEdges] shader error:", log);
            }
        }
    }

    Component {
        id: gradientEdges

        Item {
            // Sheen — subtle top-down light gradient
            Rectangle {
                anchors.fill: parent
                visible: Appearance.liquid.sheenEnabled && root.sheenOverContent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Appearance.liquid.colSheen }
                    GradientStop { position: 0.35; color: "transparent" }
                }
            }

            // Specular gleam — a soft diagonal band of light across the pane. Rotated
            // rather than using a diagonal gradient so it stays a single cheap draw.
            Item {
                anchors.fill: parent
                visible: Appearance.liquid.specularEnabled
                clip: true

                Rectangle {
                    width: parent.width * 2.2
                    height: parent.height * 0.55
                    // Centre it, then rake it across the surface.
                    x: -parent.width * 0.6
                    y: -parent.height * 0.1
                    transformOrigin: Item.Center
                    rotation: -18
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop {
                            position: 0.0
                            color: "transparent"
                        }
                        GradientStop {
                            position: 0.45
                            color: Appearance.liquid.colSpecular
                        }
                        GradientStop {
                            position: 0.62
                            color: Appearance.liquid.colSpecularSoft
                        }
                        GradientStop {
                            position: 1.0
                            color: "transparent"
                        }
                    }
                }
            }

            // Refraction rim — hairline inset border on all four edges. A translucent
            // panel otherwise fades into whatever is behind it with no defined edge.
            Rectangle {
                anchors.fill: parent
                visible: root.rimEnabled && Appearance.liquid.edgeHighlightEnabled
                color: "transparent"
                radius: root.surfaceRadius
                border.width: 1
                border.color: Appearance.liquid.colGlassRealBorder
            }

            // Top edge highlight — light-from-above
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                visible: Appearance.liquid.edgeHighlightEnabled
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.08; color: Appearance.liquid.colEdgeHighlight }
                    GradientStop { position: 0.92; color: Appearance.liquid.colEdgeHighlight }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Bottom edge shade — grounds the panel
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                visible: Appearance.liquid.edgeHighlightEnabled
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.08; color: Appearance.liquid.colEdgeShade }
                    GradientStop { position: 0.92; color: Appearance.liquid.colEdgeShade }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }
    }
}
