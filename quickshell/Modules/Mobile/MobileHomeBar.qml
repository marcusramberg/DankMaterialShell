pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

PanelWindow {
    id: root

    WlrLayershell.namespace: "dms:mobile-home-bar"
    WlrLayershell.layer: WlrLayershell.Top
    WlrLayershell.exclusiveZone: 14
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    screen: Quickshell.screens[0]
    color: "transparent"

    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 14

    signal openLauncher

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        property real _startY: 0
        property real _startX: 0
        property bool _isSwipe: false

        onPressed: mouse => {
            _startY = mouse.y;
            _startX = mouse.x;
            _isSwipe = false;
        }

        onPositionChanged: mouse => {
            let dy = Math.abs(mouse.y - _startY);
            let dx = Math.abs(mouse.x - _startX);
            if (dy > 10 || dx > 10) {
                _isSwipe = true;
                mouse.accepted = true;
            }
        }

        onReleased: mouse => {
            if (!_isSwipe) {
                mouse.accepted = false;
                return;
            }
            if (_startY - mouse.y > 60 && Math.abs(mouse.x - _startX) < 30) {
                root.openLauncher();
            } else if (_startX - mouse.x > 60 && Math.abs(mouse.y - _startY) < 30) {
                NiriService.moveColumnRight();
            } else if (mouse.x - _startX > 60 && Math.abs(mouse.y - _startY) < 30) {
                NiriService.moveColumnLeft();
            }
        }
    }

    Rectangle {
        width: 120
        height: 4
        radius: 2
        color: Theme.withAlpha(Theme.surfaceText, 0.3)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }
}
