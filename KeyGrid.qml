// 键位网格。
//
// 绝对定位而不是 Grid/Row：布局里同一行可能有跨行键（span 拉高），
// 用布局容器反而要写一堆 Layout 特例。每个 Key 的 x/y 由 flatKeys
// 里预计算好的 col/row 直接算，简单可预测。
//
// 空格键的正中间显示当前输入法标识（文字标签优先，没有标签才用图标），
// 点击仍然是空格键——那层显示不接收鼠标事件。
import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: grid

    // 卡片实例：键位数据、尺寸、修饰键状态全从它读
    required property var controller

    readonly property var c: controller

    // 表情页还没做：给一句明确的占位，别让用户对着空面板发呆
    Text {
        visible: grid.c.page === "emoji"
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -grid.c.keyH * 0.5
        text: grid.c.tr("Not implemented yet")
        color: Theme.withAlpha(grid.c.fg, 0.45)
        font.pixelSize: Math.round(grid.c.keyH * 0.42)
    }

    Repeater {
        model: grid.c.flatKeys

        delegate: Key {
            id: keyItem

            required property var modelData

            keyData: modelData.key
            unit: grid.c.unit
            keyH: grid.c.keyH
            gap: grid.c.gap
            span: modelData.rs
            fnActive: grid.c.fnActive
            // 字母大小写：shift 激活 / caps 锁定 → 大写
            upperMode: (grid.c.modifierStates.shift || 0) > 0
                       || (grid.c.modifierStates.caps || 0) > 0
            modifierState: grid.c.modifierStateFor(modelData.key)
            keyOpacity: grid.c.keyOpacity
            active: modelData.key.active === true
            x: modelData.col * (grid.c.unit + grid.c.gap)
            y: modelData.row * (grid.c.keyH + grid.c.gap)

            MouseArea {
                anchors.fill: parent
                enabled: !keyItem.isSpacer
                onPressed: mouse => {
                    keyItem.pressRipple(mouse.x, mouse.y)
                    grid.c.modifierPressed(keyItem.keyData)
                }
                onReleased: {
                    keyItem.releaseRipple()
                    grid.c.modifierReleased(keyItem.keyData)
                }
                onCanceled: {
                    keyItem.releaseRipple()
                    grid.c.modifierReleased(keyItem.keyData)
                }
                onClicked: grid.c.keyPressed(keyItem.effectiveKeyData)
            }
        }
    }

    // 空格键正中间：当前输入法标识（点击仍然是空格键）
    // 有文字标签（「万」/「en」/「abc」）就显示文字，和托盘一致；
    // 没有标签才退回图标。
    Image {
        visible: grid.c.spaceEntry !== null && grid.c.fcitxImLabel === ""
                 && source !== ""
        // addon 直接给绝对路径（从 icon theme 解析），不需要缓存破除参数
        source: grid.c.fcitxImIcon === "" ? "" : "file://" + grid.c.fcitxImIcon
        width: Math.round(grid.c.keyH * 0.4)
        height: width
        x: grid.c.spaceX + (grid.c.spaceW - width) / 2
        y: grid.c.spaceY + (grid.c.keyH - height) / 2
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    Text {
        visible: grid.c.spaceEntry !== null && grid.c.fcitxImLabel !== ""
        text: grid.c.fcitxImLabel
        font.pixelSize: Math.max(10, Math.round(grid.c.keyH * 0.42))
        font.weight: Font.Medium
        color: Theme.onSurface
        x: grid.c.spaceX + (grid.c.spaceW - width) / 2
        y: grid.c.spaceY + (grid.c.keyH - height) / 2
    }
}
