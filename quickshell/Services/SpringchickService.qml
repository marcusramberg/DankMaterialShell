pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    function quit() {
        Quickshell.execDetached(["springchick", "ipc", "quit"]);
    }
}
