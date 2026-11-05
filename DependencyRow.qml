// 依赖状态行：标题 + 状态文本 + 一排操作按钮 + 可选的行内附加内容。
//
// 设置页顶部用它统一描述「这个功能依赖的外部东西现在什么状态」：
// ydotool（必需）、fcitx5 addon（可选）、触控板后端（可选）三行共用一套视觉，
// 免得每加一个依赖就往页面里塞一块各写各的说明卡。
//
// 顺序固定：状态 → 按钮 → 附加内容。

import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon
import qs.Modules.Settings.Widgets

SettingsRow {
    id: root

    // 状态文本（三段式：已启动 · 开机自启 · 用户级）
    property string stateText: ""
    // false 时用错误色（缺依赖 / 服务挂了）
    property bool stateOk: true
    // [{ text: "...", enabled: true, variant: "filled", onClicked: function () {} }]
    // enabled 省略视为可用；variant 只有 "filled" 有特殊含义（主色实心）
    property var buttons: []
    // 行内附加内容：写在 DependencyRow 里的子项会落在这里，排在按钮之后。
    // 用来放安装命令、详细说明 —— 让它留在自己那一行里，而不是散在分组外面。
    default property alias extraContent: extraSlot.data

    // 状态文字交给基类的 subtitle：字体跟标题一致，读屏器也能读到（Accessible.description）
    subtitle: root.stateText
    subtitleColor: root.stateOk ? root.supportingContentColor : Theme.error

    body: Column {
        width: parent.width
        spacing: Theme.spacingS

        // 用 Flow 而不是 Row：行宽不够时按钮自己换到下一行，
        // 不会像 Row 那样整体往右溢出（长标题 + 长按钮很容易撞上）
        Flow {
            width: parent.width
            spacing: Theme.spacingS
            visible: root.buttons.length > 0

            Repeater {
                model: root.buttons

                DCommon.DButton {
                    required property var modelData

                    // 不写 width：DMS 设置页的按钮都是内容宽度、左对齐。
                    // 撑满整行会让「停止」这种两个字的按钮拖一大片空白，视觉也很重。
                    text: modelData.text
                    // visible 要显式接：按钮数组里声明 visible 但组件不认，会出现
                    // 「不该出现的按钮一直挂在那」（比如版本没过期却显示复制更新命令）
                    visible: modelData.visible === undefined ? true : modelData.visible
                    enabled: modelData.enabled === undefined ? true : modelData.enabled
                    // DCommon.DButton 没有 variant 属性，只能自己映射三档：
                    // filled = 主题色实心（主操作）/ tonal = 修饰键同色（次主操作）/
                    // outlined = 透明底 + 主色字（最弱）
                    readonly property string buttonStyle: modelData.variant || "tonal"
                    backgroundColor: buttonStyle === "filled" ? Theme.primary : (buttonStyle === "tonal" ? Theme.chipSurface : "transparent")
                    textColor: buttonStyle === "filled" ? Theme.onPrimary : (buttonStyle === "outlined" ? Theme.primary : Theme.surfaceText)
                    onClicked: {
                        if (modelData.onClicked)
                            modelData.onClicked();

                    }
                }

            }

        }

        // 行内附加内容（安装命令等）挂在这里，排在按钮之后
        Column {
            id: extraSlot

            width: parent.width
            spacing: Theme.spacingS
        }

    }

}
