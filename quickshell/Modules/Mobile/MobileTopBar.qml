pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root

    signal swipeLeftDown
    signal swipeRightDown

    WlrLayershell.namespace: "dms:mobile-top-bar"
    WlrLayershell.layer: WlrLayershell.Top
    WlrLayershell.exclusiveZone: 36
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    screen: Quickshell.screens[0]
    color: "transparent"

    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 36

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool mediaPlaying: activePlayer !== null && activePlayer.playbackState === MprisPlaybackState.Playing

    property bool islandCollapsed: !mediaPlaying

    Timer {
        id: collapseTimer
        interval: 400
        onTriggered: root.islandCollapsed = true
    }

    onMediaPlayingChanged: {
        if (!mediaPlaying) {
            collapseTimer.restart();
        } else {
            collapseTimer.stop();
            islandCollapsed = false;
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 30
        anchors.rightMargin: 30

        Item {
            id: leftZone
            width: parent.width * 0.3
            height: parent.height

            MouseArea {
                anchors.fill: parent
                property real _startY: 0

                onPressed: mouse => {
                    _startY = mouse.y;
                }
                onReleased: mouse => {
                    if (mouse.y - _startY > 60)
                        root.swipeLeftDown();
                }
            }

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                StyledText {
                    text: {
                        const h = systemClock.date.getHours();
                        const m = systemClock.date.getMinutes();
                        return String(h).padStart(2, '0') + ":" + String(m).padStart(2, '0');
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.error
                    visible: NotificationService.notifications.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Item {
            id: centerZone
            width: parent.width * 0.4
            height: parent.height

            Rectangle {
                width: root.islandCollapsed ? 60 : 120
                height: 28
                radius: 14
                color: "black"
                anchors.centerIn: parent
                clip: true

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    visible: !root.islandCollapsed

                    DankIcon {
                        name: root.mediaPlaying ? "pause" : "play_arrow"
                        size: 14
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: {
                            if (!root.activePlayer)
                                return "";
                            const title = root.activePlayer.trackTitle || "";
                            const artist = root.activePlayer.trackArtist || "";
                            return artist ? artist + " - " + title : title;
                        }
                        font.pixelSize: 11
                        color: "white"
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 80)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: PopoutService.toggleDankDash(1, 0, 0, 0, "", Quickshell.screens[0])
                }
            }
        }

        Item {
            id: rightZone
            width: parent.width * 0.3
            height: parent.height

            MouseArea {
                anchors.fill: parent
                property real _startY: 0

                onPressed: mouse => {
                    _startY = mouse.y;
                }
                onReleased: mouse => {
                    if (mouse.y - _startY > 60)
                        root.swipeRightDown();
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                DankIcon {
                    name: NetworkService.wifiConnected ? "wifi" : "wifi_off"
                    size: Theme.iconSizeSmall
                    color: Theme.surfaceText
                    visible: NetworkService.wifiAvailable
                    anchors.verticalCenter: parent.verticalCenter
                }

                DankIcon {
                    name: BatteryService.getBatteryIcon()
                    size: Theme.iconSizeSmall
                    color: BatteryService.isLowBattery ? Theme.error : (BatteryService.isCharging ? Theme.primary : Theme.surfaceText)
                    visible: BatteryService.batteryAvailable
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: BatteryService.batteryLevel.toFixed(0) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: BatteryService.isLowBattery ? Theme.error : Theme.surfaceText
                    visible: BatteryService.batteryAvailable
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
