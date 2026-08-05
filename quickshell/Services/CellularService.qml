pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root
    readonly property var log: Log.scoped("CellularService")

    property int refCount: 0

    onRefCountChanged: {
        if (refCount > 0) {
            ensureSubscription();
        } else if (refCount === 0 && DMSService.activeSubscriptions.includes("network.cellular")) {
            DMSService.removeSubscription("network.cellular");
        }
    }

    function ensureSubscription() {
        if (refCount <= 0)
            return;
        if (!DMSService.isConnected)
            return;
        if (DMSService.activeSubscriptions.includes("network.cellular"))
            return;
        if (DMSService.activeSubscriptions.includes("all"))
            return;
        DMSService.addSubscription("network.cellular");
        if (available) {
            getState();
        }
    }

    property bool available: false
    property bool stateInitialized: false

    property bool connected: false
    property bool enabled: false
    property string status: "disconnected"
    property var modems: []

    readonly property int signalStrength: {
        if (!available || modems.length === 0)
            return 0;
        let max = 0;
        for (const m of modems) {
            if (m.signal !== undefined && m.signal > max)
                max = m.signal;
        }
        return max;
    }

    readonly property string operator: {
        for (const m of modems) {
            if (m.operator)
                return m.operator;
        }
        return "";
    }

    readonly property string accessTech: {
        for (const m of modems) {
            if (m.accessTech && m.accessTech !== "unknown")
                return m.accessTech;
        }
        return "";
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkDMSCapabilities();
                ensureSubscription();
            }
        }
    }

    Connections {
        target: DMSService
        enabled: DMSService.isConnected

        function onCellularStateUpdate(data) {
            updateState(data);
        }

        function onCapabilitiesReceived() {
            checkDMSCapabilities();
        }
    }

    function checkDMSCapabilities() {
        if (!DMSService.isConnected)
            return;
        if (DMSService.capabilities.length === 0)
            return;
        const wasAvailable = available;
        // Availability is gated on a dedicated server capability, so it is
        // known even before the widget is instantiated.
        available = DMSService.capabilities.includes("cellular");
        if (!available)
            return;
        if (!stateInitialized) {
            stateInitialized = true;
            getState();
        }
        if (!wasAvailable)
            ensureSubscription();
    }

    function getState() {
        if (!available)
            return;
        DMSService.sendRequest("network.cellular.getState", null, response => {
            if (response.result) {
                available = true;
                updateState(response.result);
            }
        });
    }

    function updateState(data) {
        if (!data)
            return;
        connected = data.connected || false;
        enabled = data.enabled || false;
        status = data.status || "disconnected";
        modems = data.modems || [];
    }
}
