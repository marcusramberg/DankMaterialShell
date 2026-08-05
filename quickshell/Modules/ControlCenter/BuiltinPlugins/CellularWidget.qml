import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    Ref {
        service: CellularService
    }

    ccWidgetIcon: signalIcon
    ccWidgetPrimaryText: I18n.tr("Cellular")
    ccWidgetSecondaryText: {
        if (!CellularService.available)
            return I18n.tr("Not available", "Cellular/ModemManager not available");
        if (!CellularService.connected)
            return I18n.tr("Disconnected", "Cellular data disconnected");
        const parts = [];
        if (CellularService.operator)
            parts.push(CellularService.operator);
        if (CellularService.accessTech)
            parts.push(CellularService.accessTech);
        parts.push(CellularService.signalStrength + "%");
        return parts.join(" \u2022 ");
    }
    ccWidgetIsActive: CellularService.connected

    readonly property string signalIcon: {
        if (!CellularService.available)
            return "signal_cellular_off";
        if (!CellularService.connected)
            return "signal_cellular_off";
        if (CellularService.signalStrength >= 75)
            return "signal_cellular_alt";
        if (CellularService.signalStrength >= 50)
            return "signal_cellular_alt_2_bar";
        if (CellularService.signalStrength >= 25)
            return "signal_cellular_alt_1_bar";
        return "signal_cellular_0_bar";
    }

    onCcWidgetToggled: {}

    ccDetailContent: Component {
        Rectangle {
            implicitHeight: detailColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: detailColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                // Not available state
                Column {
                    visible: !CellularService.available
                    width: parent.width
                    spacing: Theme.spacingS

                    Item {
                        width: parent.width
                        height: 80

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "signal_cellular_off"
                                size: 36
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            StyledText {
                                text: I18n.tr("ModemManager not available", "Cellular service not running")
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // Connected content
                Column {
                    visible: CellularService.available
                    width: parent.width
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        Column {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXS

                            StyledText {
                                text: CellularService.operator || I18n.tr("Unknown Network")
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: {
                                    const parts = [];
                                    if (CellularService.accessTech)
                                        parts.push(CellularService.accessTech);
                                    parts.push(CellularService.signalStrength + "%");
                                    if (CellularService.connected)
                                        parts.push(I18n.tr("Connected", "Cellular data connected"));
                                    return parts.join(" \u2022 ");
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                            }
                        }

                        DankIcon {
                            name: root.signalIcon
                            size: 48
                            color: CellularService.connected ? Theme.primary : Theme.surfaceVariantText
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    StyledText {
                        text: I18n.tr("%1 modem(s)", "Number of detected cellular modems").arg(CellularService.modems.length)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Repeater {
                        model: CellularService.modems

                        delegate: Rectangle {
                            required property var modelData

                            width: parent.width
                            height: modemColumn.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHighest

                            Column {
                                id: modemColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingS
                                spacing: 2

                                StyledText {
                                    text: [modelData.manufacturer, modelData.model].filter(Boolean).join(" ") || modelData.path
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                StyledText {
                                    visible: !!modelData.operator
                                    text: I18n.tr("Operator: %1", "Cellular operator name").arg(modelData.operator)
                                    font.pixelSize: 10
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    visible: !!modelData.imei
                                    text: I18n.tr("IMEI: %1", "Cellular modem IMEI").arg(modelData.imei)
                                    font.pixelSize: 10
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    visible: !!modelData.simIccid
                                    text: I18n.tr("SIM: %1", "Cellular SIM ICCID").arg(modelData.simIccid)
                                    font.pixelSize: 10
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: I18n.tr("State: %1 \u2022 Signal: %2%", "Cellular modem state and signal").arg(modelData.state || "unknown").arg(modelData.signal !== undefined ? modelData.signal : 0)
                                    font.pixelSize: 10
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
