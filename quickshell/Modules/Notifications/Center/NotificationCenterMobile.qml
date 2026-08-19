pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root

    WlrLayershell.namespace: "dms:notification-center-mobile"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    screen: Quickshell.screens[0]
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    property bool _open: false
    property bool _mappedVisible: false

    visible: _mappedVisible

    function toggle() {
        if (_open) {
            _open = false
        } else {
            _mappedVisible = true
            Qt.callLater(() => {
                _open = true
            })
        }
    }

    Keys.onEscapePressed: {
        if (_open)
            _open = false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: slideContent.opacity

        MouseArea {
            anchors.fill: parent
            onClicked: root._open = false
        }
    }

    Item {
        id: slideContent
        width: parent.width
        height: parent.height

        property real slideY: root.height

        Connections {
            target: root
            function on_OpenChanged() {
                slideContent.slideY = root._open ? 0 : root.height
            }
        }

        y: slideY + dragArea.dragOffset
        opacity: Math.max(0, 1 - (slideY + dragArea.dragOffset) / (root.height > 0 ? root.height * 0.5 : 1))

        Behavior on slideY {
            NumberAnimation {
                id: slideAnim
                duration: Theme.mediumDuration
                easing.bezierCurve: Theme.variantPopoutEnterCurve

                onRunningChanged: {
                    if (!running && !root._open)
                        root._mappedVisible = false
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
        }

        Column {
            id: contentColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 48
            anchors.margins: Theme.spacingM
            spacing: 0

            NotificationHeader {
                id: notifHeader
                width: parent.width
            }

            NotificationEmptyState {
                width: parent.width
                height: 200
                visible: NotificationService.groupedNotifications.length === 0
            }

            KeyboardNavigatedNotificationList {
                id: notifList
                width: parent.width
                height: root.height - notifHeader.height - 48 - Theme.spacingM
                visible: NotificationService.groupedNotifications.length > 0
            }
        }

        MouseArea {
            id: dragArea
            anchors.top: parent.top
            width: parent.width
            height: 48
            z: 10

            property real _pressY: 0
            property real dragOffset: 0

            onPressed: mouse => {
                _pressY = mouse.y
                dragOffset = 0
            }

            onPositionChanged: mouse => {
                const delta = mouse.y - _pressY
                if (delta > 0)
                    dragOffset = delta
            }

            onReleased: {
                if (dragOffset > 60) {
                    root._open = false
                } else {
                    dragOffset = 0
                }
            }

            Behavior on dragOffset {
                enabled: dragArea.dragOffset === 0
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
