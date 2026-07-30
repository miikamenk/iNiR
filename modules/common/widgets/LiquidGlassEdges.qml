import qs.modules.common
import QtQuick

// Liquid glass decorations: sheen, specular gleam and edge rim for liquid surfaces.
// Renders (in order, back to front):
//   1. Sheen — subtle top-down light gradient, like light catching the surface
//   2. Specular gleam — soft diagonal band raked across the pane
//   3. Refraction rim — hairline inset border on all four edges
//   4. Top edge highlight — 1px light-from-above inner border
//   5. Bottom edge shade — faint dark line that grounds the panel
// Horizontal fades dissolve the lines into rounded corners.
//
// Usage: place as the LAST child of the surface so it paints above content
// backgrounds; the parent must be clipped (clip: true or an OpacityMask).
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

    visible: Appearance.liquidEverywhere
    z: 10

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
