import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

// 带自己读写的开关行。DMS 的 SettingsToggleRow 是受控组件（只有 checked + toggled），
// 直接用就要在调用点手写「镜像属性 + reloadSettings 填充 + onToggled 回写」三处，
// 漏一处就静默失效。这里把这三件事收进组件，调用点只声明 settingKey。
SettingsToggleRow {
    id: root

    required property string settingKey
    // 指向设置页根（PluginSettings）：写入要过它的权限检查，不能直接调 PluginService
    property var pluginRoot: null
    property bool defaultValue: false
    // 当前值：UI 读它显示，任何来源的写盘都同步回这里
    property bool value: defaultValue

    function loadValue() {
        if (pluginRoot)
            value = pluginRoot.loadValue(settingKey, defaultValue);

    }

    checked: value
    onToggled: (v) => {
        value = v;
        if (pluginRoot)
            pluginRoot.saveValue(settingKey, v);

    }
    Component.onCompleted: Qt.callLater(loadValue)

    // 订阅写盘信号：daemon、另一个设置页实例、手改设置文件都能同步回来，
    // 不用在 reloadSettings() 里逐个列 key
    // pluginService 由 PluginSettingsHost 在 Loader.onLoaded 才注入，晚于 Component.onCompleted；
    // 注入那一刻补读一次，否则值停在 defaultValue
    Connections {
        function onPluginServiceChanged() {
            root.loadValue();
        }

        target: root.pluginRoot
        enabled: target !== null
    }

    Connections {
        function onPluginDataChanged(id) {
            if (root.pluginRoot && id === root.pluginRoot.pluginId)
                root.loadValue();

        }

        target: root.pluginRoot ? root.pluginRoot.pluginService : null
        enabled: target !== null
    }

}
