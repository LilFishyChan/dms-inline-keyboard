import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

// Optional DankBar pill. Toggles the same global var the daemon owns, so the
// pill and `dms ipc call inlineKeyboard toggle` never disagree.
PluginComponent {
    id: root

    property bool keyboardOpen: PluginService.getGlobalVar(root.pluginId, "open", false)

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === root.pluginId && varName === "open")
                root.keyboardOpen = PluginService.getGlobalVar(root.pluginId, "open", false)
        }
    }

    pillClickAction: () => {
        PluginService.setGlobalVar(root.pluginId, "open", !root.keyboardOpen)
    }

    horizontalBarPill: Component {
        DankIcon {
            name: "keyboard"
            size: root.iconSize
            color: root.keyboardOpen ? Theme.primary : Theme.surfaceText
        }
    }

    verticalBarPill: horizontalBarPill
}
