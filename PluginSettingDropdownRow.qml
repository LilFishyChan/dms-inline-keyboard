import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

// 带自己读写的下拉行。values 是存盘用的值，labels 是显示文本，两者同下标。
SettingsDropdownRow {
    id: root

    required property string settingKey
    property var pluginRoot: null
    property string defaultValue: ""
    property var values: []
    property var labels: []
    // 当前值：存盘用的是它，不是显示文本
    property string value: defaultValue
    // 初始化时 DDropdown 会发一次 valueChanged（回环），那一次不能写盘
    property bool ready: false

    function loadValue() {
        if (pluginRoot)
            value = pluginRoot.loadValue(settingKey, defaultValue);

        ready = true;
    }

    options: labels
    currentValue: labels[Math.max(0, values.indexOf(value))]
    onValueChanged: (v) => {
        if (!ready)
            return ;

        const i = labels.indexOf(v);
        if (i < 0)
            return ;

        value = values[i];
        if (pluginRoot)
            pluginRoot.saveValue(settingKey, value);

    }
    Component.onCompleted: Qt.callLater(loadValue)

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
