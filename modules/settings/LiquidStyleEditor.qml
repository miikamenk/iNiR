import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

// Liquid glass tuning. The headline control is real transparency: niri cannot
// blur behind a layer surface, so panels either paint a blurred copy of the
// wallpaper (frosted, but opaque to windows) or carry genuine alpha and let the
// compositor show what is actually behind them. This picks between the two.
ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 16

    // ─── Helper: percentage slider row with label + value readout ───
    component SliderRow: RowLayout {
        id: sliderRowRoot
        Layout.fillWidth: true
        spacing: 8

        property string label: ""
        property string icon: ""
        property string description: ""
        property real configValue: 0.0
        property real from: 0.0
        property real to: 1.0
        property real stepSize: 0.01
        property string configPath: ""

        MaterialSymbol {
            text: sliderRowRoot.icon
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
            visible: sliderRowRoot.icon !== ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                text: sliderRowRoot.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: sliderRowRoot.description !== ""
                text: sliderRowRoot.description
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        StyledText {
            text: Math.round(slider.value * 100) + "%"
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colPrimary
            Layout.preferredWidth: 45
            horizontalAlignment: Text.AlignRight
        }

        StyledSlider {
            id: slider
            Layout.preferredWidth: 160
            from: sliderRowRoot.from
            to: sliderRowRoot.to
            stepSize: sliderRowRoot.stepSize
            value: sliderRowRoot.configValue
            configuration: StyledSlider.Configuration.S

            onMoved: {
                if (sliderRowRoot.configPath !== "")
                    Config.setNestedValue(sliderRowRoot.configPath, Math.round(value * 100) / 100);
            }
        }
    }

    // ─── Real transparency ───
    ConfigSwitch {
        Layout.fillWidth: true
        text: Translation.tr("Real transparency")
        checked: Config.options?.appearance?.liquid?.realGlass?.enable ?? true
        onCheckedChanged: Config.setNestedValue("appearance.liquid.realGlass.enable", checked)
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("On: panels carry genuine alpha, so windows behind them actually show through. Off: panels paint a blurred copy of the wallpaper instead — frosted, but nothing behind them is ever visible. Niri cannot blur behind panels, so these are the two available looks.")
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
        opacity: 0.7
        wrapMode: Text.WordWrap
    }

    SliderRow {
        label: Translation.tr("Glass opacity")
        icon: "opacity"
        description: Translation.tr("How solid the panels read. Lower shows more of what is behind; too low and text over busy windows gets hard to read.")
        from: 0.15
        to: 1.0
        configValue: Config.options?.appearance?.liquid?.realGlass?.opacity ?? 0.62
        configPath: "appearance.liquid.realGlass.opacity"
        enabled: Config.options?.appearance?.liquid?.realGlass?.enable ?? true
    }

    // ─── Glass detailing ───
    ConfigSwitch {
        Layout.fillWidth: true
        text: Translation.tr("Specular gleam")
        checked: Config.options?.appearance?.liquid?.specular?.enable ?? true
        onCheckedChanged: Config.setNestedValue("appearance.liquid.specular.enable", checked)
    }

    SliderRow {
        label: Translation.tr("Gleam strength")
        icon: "flare"
        description: Translation.tr("Diagonal band of light raked across the glass.")
        from: 0.0
        to: 0.25
        configValue: Config.options?.appearance?.liquid?.specular?.opacity ?? 0.07
        configPath: "appearance.liquid.specular.opacity"
        enabled: Config.options?.appearance?.liquid?.specular?.enable ?? true
    }

    ConfigSwitch {
        Layout.fillWidth: true
        text: Translation.tr("Edge highlight")
        checked: Config.options?.appearance?.liquid?.edgeHighlight?.enable ?? true
        onCheckedChanged: Config.setNestedValue("appearance.liquid.edgeHighlight.enable", checked)
    }

    SliderRow {
        label: Translation.tr("Edge strength")
        icon: "line_weight"
        description: Translation.tr("Brightness of the rim and the light-from-above hairline. This is what gives a see-through panel a defined edge.")
        from: 0.0
        to: 1.0
        configValue: Config.options?.appearance?.liquid?.edgeHighlight?.opacity ?? 0.5
        configPath: "appearance.liquid.edgeHighlight.opacity"
        enabled: Config.options?.appearance?.liquid?.edgeHighlight?.enable ?? true
    }

    ConfigSwitch {
        Layout.fillWidth: true
        text: Translation.tr("Sheen")
        checked: Config.options?.appearance?.liquid?.sheen?.enable ?? true
        onCheckedChanged: Config.setNestedValue("appearance.liquid.sheen.enable", checked)
    }
}
