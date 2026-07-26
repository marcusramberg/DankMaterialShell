pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.ControlCenter.Components
import qs.Modules.ControlCenter.Models

PanelWindow {
    id: root

    WlrLayershell.namespace: "dms:control-center-mobile"
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
    property bool editMode: false

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

    WidgetModel {
        id: widgetModel
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
            color: Theme.popupLayerColor(Theme.surfaceContainer)
        }

        Flickable {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 48
            height: parent.height - 48
            contentWidth: width
            contentHeight: Math.max(height, mainColumn.implicitHeight + Theme.spacingM)
            clip: true
            interactive: contentHeight > height

            Column {
                id: mainColumn
                width: parent.width - Theme.spacingL * 2
                x: Theme.spacingL
                y: Theme.spacingL
                spacing: Theme.spacingS

                HeaderPane {
                    id: headerPane
                    width: parent.width
                    editMode: root.editMode
                    onEditModeToggled: root.editMode = !root.editMode
                    onLockRequested: root._open = false
                    onSettingsButtonClicked: root._open = false
                }

                DragDropGrid {
                    id: widgetGrid
                    width: parent.width
                    editMode: root.editMode
                    maxPopoutHeight: root.height - 100
                    expandedSection: ""
                    expandedWidgetIndex: -1
                    expandedWidgetData: null
                    model: widgetModel
                    screenName: root.screen?.name || ""
                    screenModel: root.screen?.model || ""
                    parentScreen: root.screen
                    onExpandClicked: (widgetData, globalIndex) => {}
                    onRemoveWidget: index => widgetModel.removeWidget(index)
                    onMoveWidget: (fromIndex, toIndex) => widgetModel.moveWidget(fromIndex, toIndex)
                    onToggleWidgetSize: index => widgetModel.toggleWidgetSize(index)
                    onCollapseRequested: {}
                }

                EditControls {
                    width: parent.width
                    visible: root.editMode
                    popupScreen: root.screen
                    popoutX: 0
                    popoutY: 0
                    popoutWidth: root.width
                    popoutHeight: root.height
                    availableWidgets: {
                        if (!root.editMode)
                            return []
                        const existingIds = (SettingsData.controlCenterWidgets || []).map(w => w.id)
                        const allWidgets = widgetModel.baseWidgetDefinitions.concat(widgetModel.getPluginWidgets())
                        return allWidgets.filter(w => w.allowMultiple || !existingIds.includes(w.id))
                    }
                    onAddWidget: widgetId => widgetModel.addWidget(widgetId)
                    onResetToDefault: () => widgetModel.resetToDefault()
                    onClearAll: () => widgetModel.clearAll()
                }
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
