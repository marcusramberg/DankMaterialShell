pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    readonly property bool active: Quickshell.env("DMS_MOBILE") === "1"
}
