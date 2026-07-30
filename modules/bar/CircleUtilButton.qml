import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

RippleButton {
    id: button

    required default property Item content
    property bool extraActiveCondition: false

    implicitHeight: Math.max(content.implicitHeight, 26, content.implicitHeight)
    implicitWidth: implicitHeight
    // Square and standalone, so the face stays organic in cookie mode.
    cookieMorphing: true
    contentItem: content
    buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.full
    colBackground: Appearance.liquidEverywhere ? Appearance.liquid.colGlassChip : "transparent"
    colBackgroundHover: Appearance.zzzEverywhere ? "transparent"
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : Appearance.inirEverywhere ? Appearance.inir.colLayer1Hover
        : Appearance.liquidEverywhere ? Appearance.liquid.colGlassCardHover
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover
        : Appearance.colors.colLayer1Hover
    colRipple: Appearance.zzzEverywhere ? ColorUtils.applyAlpha(Appearance.zzz.accent, 0.20)
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
        : Appearance.inirEverywhere ? Appearance.inir.colLayer1Active
        : Appearance.liquidEverywhere ? Appearance.liquid.colGlassCardActive
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive
        : Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.liquidEverywhere
        ? ColorUtils.transparentize(Appearance.liquid.colPrimary, 0.4)
        : Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.liquidEverywhere
        ? ColorUtils.transparentize(Appearance.liquid.colPrimary, 0.25)
        : Appearance.colors.colPrimaryHover

    ZzzPlate {
        anchors.fill: parent
        visible: Appearance.zzzEverywhere
        chamfer: button.buttonHovered ? Appearance.zzz.cutCorner * 0.7 : Appearance.zzz.cutCorner * 0.35
        fillColor: button.buttonHovered ? Appearance.zzz.sticker : "transparent"
        strokeColor: button.buttonHovered ? Appearance.zzz.accentSoft : "transparent"
        strokeWidth: 1
        z: -1
    }
}
