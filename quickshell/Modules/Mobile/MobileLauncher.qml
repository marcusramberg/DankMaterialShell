pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modals.DankLauncherV2

PanelWindow {
    id: root

    WlrLayershell.namespace: "dms:mobile-launcher"
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

    // Keep the layer surface mapped at all times. Toggling `visible` would
    // destroy/recreate the wlr_layer_surface, and the trailing unmap commit
    // trips a smithay pre_commit_hook bug that kills the whole client.
    visible: true

    // Surface stays mapped, so drop the input region when closed to let touches
    // pass through to apps below.
    mask: _open ? null : _noInputRegion
    Region {
        id: _noInputRegion
    }

    function toggle() {
        if (_open) {
            _open = false
        } else {
            _open = true
            Qt.callLater(() => {
                for (var i = 0; i < appController.sectionDefinitions.length; i++) {
                    appController.setSectionViewMode(appController.sectionDefinitions[i].id, "grid");
                }
                appController.performSearch();
                searchInput.forceActiveFocus();
            })
        }
    }

    Keys.onEscapePressed: {
        if (_open)
            _open = false
    }

    // Dark overlay
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
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
        opacity: Math.max(0, 1 - (slideY + dragArea.dragOffset) / (root.height > 0 ? root.height * 0.4 : 1))

        Behavior on slideY {
            NumberAnimation {
                id: slideAnim
                duration: Theme.mediumDuration
                easing.bezierCurve: Theme.variantPopoutEnterCurve
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.popupLayerColor(Theme.surfaceContainer)
        }

        // Drag handle at top
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

        // Status bar spacer + search bar
        Column {
            id: headerColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 48
            anchors.leftMargin: Theme.spacingL
            anchors.rightMargin: Theme.spacingL
            spacing: Theme.spacingM

            // Search field
            DankTextField {
                id: searchInput
                width: parent.width
                cornerRadius: Theme.cornerRadius
                backgroundColor: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                normalBorderColor: Theme.withAlpha(Theme.outline, Theme.layerOutlineOpacity)
                focusedBorderColor: Theme.withAlpha(Theme.primary, 1.0)
                borderWidth: 1
                focusedBorderWidth: 2
                leftIconName: "search"
                leftIconSize: Theme.iconSize
                leftIconColor: Theme.surfaceVariantText
                leftIconFocusedColor: Theme.primary
                showClearButton: true
                textColor: Theme.surfaceText
                font.pixelSize: Theme.fontSizeLarge
                placeholderText: I18n.tr("Search apps...")
                keyForwardTargets: [root]

                onTextChanged: {
                    appController.setSearchQuery(text);
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root._open = false;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        appController.selectNext();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        appController.executeSelected();
                        event.accepted = true;
                    }
                }
            }

            // Mode chips
            Row {
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: [
                        { id: "all", label: I18n.tr("All"), icon: "search" },
                        { id: "apps", label: I18n.tr("Apps"), icon: "apps" },
                        { id: "files", label: I18n.tr("Files"), icon: "folder" },
                        { id: "plugins", label: I18n.tr("Plugins"), icon: "extension" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: chipContent.width + Theme.spacingM * 2
                        height: 28
                        radius: Theme.cornerRadius
                        color: appController.searchMode === modelData.id
                               ? Theme.primaryContainer
                               : chipArea.containsMouse ? Theme.surfaceHover : "transparent"

                        Row {
                            id: chipContent
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            DankIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.icon
                                size: 14
                                color: appController.searchMode === modelData.id
                                       ? Theme.primary
                                       : Theme.surfaceVariantText
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: appController.searchMode === modelData.id
                                        ? Theme.primary
                                        : Theme.surfaceText
                            }
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: appController.setMode(modelData.id)
                        }
                    }
                }
            }
        }

        // App grid
        ResultsList {
            anchors.top: headerColumn.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: Theme.spacingM
            anchors.leftMargin: Theme.spacingL
            anchors.rightMargin: Theme.spacingL
            anchors.bottomMargin: Theme.spacingL

            controller: appController
            onItemRightClicked: (flatIndex, item, sceneX, sceneY) => {}
        }
    }

    // Controller for app data
    Controller {
        id: appController
        active: true
        viewModeContext: "appDrawer"

        onItemExecuted: {
            root._open = false;
        }
    }
}
