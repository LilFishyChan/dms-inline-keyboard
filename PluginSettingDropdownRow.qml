import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon
import qs.Modules.Settings.Widgets

// 带自己读写的下拉行。values 是存盘用的值，labels 是显示文本，两者同下标。
//
// 为什么不用 DMS 的 SettingsDropdownRow：它内部把 DDropdown 的 valueChanged 转发成
// 自己的 valueChanged，但转发出来的参数是 undefined（DMS 2.0 实测，四个下拉一个样），
// 于是 labels.indexOf(v) 拿不到项、静默 return —— 表现就是「点了没反应，也不报错」。
// 这里自己摆一个 DDropdown、盯 currentValue 变化：点击时它一定先把 currentValue
// 写成选中项，这条路径是可靠的。
SettingsRow {
    id: root

    required property string settingKey
    // 指向设置页根（PluginSettings）：写入要过它的权限检查，不能直接调 PluginService
    property var pluginRoot: null
    property string defaultValue: ""
    property var values: []
    property var labels: []
    // 当前值：存盘用的是它，不是显示文本
    property string value: defaultValue
    // 调用点沿用 text / description 这两个名字（SettingsRow 自己叫 title / subtitle）
    property string text: ""
    property string description: ""

    readonly property string displayValue: labels[Math.max(0, values.indexOf(value))]

    title: text
    subtitle: description

    DCommon.DDropdown {
        id: dropdown

        // SettingsRow 的默认槽是右侧的 trailing；DDropdown 不带隐式宽度（Item 默认 0），
        // 不写 width 就是「有标题、右边空一块」，看着像控件没渲染出来
        width: Math.min(240, root.width - SettingsMetrics.rowPaddingH * 2)
        options: root.labels
        currentValue: root.displayValue
        onCurrentValueChanged: root.commit(currentValue)
    }

    // 用户点选会打断 currentValue 的绑定，之后外部再改 value（reloadSettings、
    // 另一个设置页实例）就同步不到下拉上，所以这里手动拉回来
    onDisplayValueChanged: dropdown.currentValue = displayValue

    function commit(label) {
        const i = labels.indexOf(label);
        if (i < 0)
            return ;

        const next = values[i];
        if (next === value)
            return ;

        value = next;
        if (pluginRoot)
            pluginRoot.saveValue(settingKey, next);

    }

    function loadValue() {
        if (pluginRoot)
            value = pluginRoot.loadValue(settingKey, defaultValue);

    }

    Component.onCompleted: Qt.callLater(loadValue)

    // pluginService 由 PluginSettingsHost 在 Loader.onLoaded 才注入，晚于 Component.onCompleted；
    // 注入那一刻补读一次，否则值停在 defaultValue
    Connections {
        target: root.pluginRoot
        enabled: target !== null

        function onPluginServiceChanged() {
            root.loadValue();
        }

    }

    Connections {
        target: root.pluginRoot ? root.pluginRoot.pluginService : null
        enabled: target !== null

        function onPluginDataChanged(id) {
            if (root.pluginRoot && id === root.pluginRoot.pluginId)
                root.loadValue();

        }

    }

}
