// 透明度调整面板：预览 + 背景 / 按键两行滑块，改值直接写回卡片。
// 进入时记录原值、取消时恢复由 KeyboardCard + QuickBar 负责（面板本身不管撤销）。
// 预览直接用 Key 组件画三个真键（普通 / 激活态 / 锁定态），尺寸与配色天然和键盘一致，
// 不加外框 —— 背景透明度本身就体现在整块键盘（含本面板）透出的桌面上。
import QtQuick
import qs.Common

Item {
    id: root

    property var controller: null

    Column {
        anchors.centerIn: parent
        spacing: Math.round(root.controller.keyH * 0.75)
        width: parent.width * 0.7

        // ---- 预览：A / Shift（激活态）/ Win（锁定态） ----
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.controller.gap

            Key {
                keyData: ({ k: "char", l: "A", w: 1.2 })
                unit: root.controller.unit
                keyH: root.controller.keyH
                gap: root.controller.gap
                keyOpacity: root.controller.keyOpacity
            }

            Key {
                keyData: ({ k: "shift", l: "Shift", w: 1.8 })
                unit: root.controller.unit
                keyH: root.controller.keyH
                gap: root.controller.gap
                keyOpacity: root.controller.keyOpacity
                modifierState: 1
            }

            Key {
                keyData: ({ k: "key", l: "Win", w: 1.5 })
                unit: root.controller.unit
                keyH: root.controller.keyH
                gap: root.controller.gap
                keyOpacity: root.controller.keyOpacity
                modifierState: 2
            }
        }

        OpacitySliderRow {
            width: parent.width
            keyH: root.controller.keyH
            textColor: Theme.withAlpha(root.controller.fg, 0.85)
            label: root.controller.tr("Background opacity")
            value: root.controller.bgOpacity
            onMoved: v => {
                root.controller.bgOpacity = v;
                root.controller.opacityAdjusted(root.controller.bgOpacity, root.controller.keyOpacity);
            }
        }

        OpacitySliderRow {
            width: parent.width
            keyH: root.controller.keyH
            textColor: Theme.withAlpha(root.controller.fg, 0.85)
            label: root.controller.tr("Key opacity")
            value: root.controller.keyOpacity
            onMoved: v => {
                root.controller.keyOpacity = v;
                root.controller.opacityAdjusted(root.controller.bgOpacity, root.controller.keyOpacity);
            }
        }
    }
}
