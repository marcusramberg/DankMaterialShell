pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root

    WlrLayershell.namespace: "dms:control-center-mobile"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    // Not exclusive: that starves stacked modals, and the VPN fields still need keys.
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    screen: Quickshell.screens[0]
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    property bool _open: false
    property bool _mappedVisible: false
    property bool editMode: false
    property string expandedSection: ""

    /// Set by DMSShell, which owns the modals.
    property var colorPickerModal: null
    property var powerMenuModalLoader: null

    signal lockRequested

    visible: _mappedVisible

    // The host interface ControlCenterContent expects from DankPopout. The
    // sheet is the whole screen here, so every alignment is the origin.
    readonly property var triggerScreen: root.screen
    readonly property bool shouldBeVisible: _open
    readonly property bool headerTogglesClose: false
    readonly property real sheetContentWidth: width
    readonly property real availableHeight: height - dragArea.height
    readonly property vector4d surfaceCornerRadii: Qt.vector4d(0, 0, 0, 0)
    readonly property real alignedX: 0
    readonly property real alignedY: 0
    readonly property real renderedAlignedX: 0
    readonly property real renderedAlignedY: 0
    readonly property real alignedWidth: width
    readonly property real alignedHeight: height
    readonly property real popupWidth: width
    readonly property real popupHeight: height
    readonly property bool powerMenuOpen: powerMenuModalLoader?.item?.shouldBeVisible ?? false

    function alignedXFor(w) {
        return 0
    }

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

    function close() {
        _open = false
    }

    function collapseAll() {
        expandedSection = ""
    }

    function openSettings() {
        _open = false
        PopoutService.focusOrToggleSettings()
    }

    function openColorPicker() {
        _open = false
        colorPickerModal?.show()
    }

    on_OpenChanged: {
        if (!_open) {
            collapseAll()
            editMode = false
        }
    }

    // Full screen, so it would cover the power menu.
    onPowerMenuOpenChanged: {
        if (powerMenuOpen)
            _open = false
    }

    onLockRequested: {
        _open = false
        IdleService.lockRequested()
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

        ControlCenterContent {
            host: root
            anchors.fill: parent
            anchors.topMargin: dragArea.height
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
