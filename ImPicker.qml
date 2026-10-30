// 输入法选择器（长按底部地球打开）。
// 键盘内部的下拉框：从右下角弹出、内容可滚动。
import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property var controller: null

    anchors.fill: parent
    z: 100
    // 没有输入法列表时不该露出空面板（一片白色方块）
    visible: root.controller.imPickerOpen && root.controller.imRows.length > 0

// 地球键循环和这个列表必须同一份数据（controller.imRows）


    // 点面板外关闭
    MouseArea {
        anchors.fill: parent
        onClicked: root.controller.imPickerOpen = false
    }

    // ---- 下拉面板：贴着右下角（地球键上方）----
    Rectangle {
        id: panel

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Math.round(root.controller.gap * 1.5)
        anchors.bottomMargin: Math.round(root.controller.keyH * 0.6)
        width: Math.min(parent.width * 0.52, 400)
        // contentHeight 第一帧是 0，给个下限免得面板闪一下
        height: Math.max(Math.round(root.controller.keyH * 0.9),
                         Math.min(listView.contentHeight + padding * 2,
                                  parent.height * 0.75))
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surface, 0.99)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

        readonly property real padding: Math.round(root.controller.keyH * 0.14)

        // 吃掉面板内的点击，避免穿透到下面的关闭区域
        MouseArea {
            anchors.fill: parent
        }

        DListView {
            id: listView

            anchors.fill: parent
            anchors.margins: panel.padding
            clip: true
            model: root.controller.imRows
            spacing: Math.round(root.controller.gap * 0.6)

            delegate: Rectangle {
                id: rowItem
                required property var modelData

                width: listView.width
                height: Math.round(root.controller.keyH * 0.68)
                radius: Math.round(Theme.cornerRadius * 0.7)
                color: modelData.current
                       ? Theme.withAlpha(Theme.primary, 0.14)
                       : (rowMouse.containsMouse
                          ? Theme.withAlpha(root.controller.fg, 0.06)
                          : "transparent")

                // label 块：托盘上看到的那个字（万 / abc / en）
                Rectangle {
                    id: labelChip
                    width: Math.round(parent.height * 0.82)
                    height: width
                    anchors.left: parent.left
                    anchors.leftMargin: Math.round(root.controller.keyH * 0.12)
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Math.round(width * 0.28)
                    color: modelData.current
                           ? Theme.primary
                           : Theme.withAlpha(root.controller.fg, 0.09)

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: modelData.current ? Theme.onPrimary : root.controller.fg
                        font.pixelSize: Math.round(labelChip.height * 0.46)
                        font.weight: Font.DemiBold
                    }
                }

                // 图标：已经有 label 块就不重复画图标
                Image {
                    id: rowIcon
                    source: modelData.icon !== "" && modelData.label === ""
                            ? "file://" + modelData.icon : ""
                    visible: source !== ""
                    width: Math.round(parent.height * 0.56)
                    height: width
                    anchors.left: labelChip.right
                    anchors.leftMargin: Math.round(root.controller.keyH * 0.12)
                    anchors.verticalCenter: parent.verticalCenter
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                // 「输入法 - 子模式名称」
                Text {
                    anchors.left: rowIcon.visible ? rowIcon.right : labelChip.right
                    anchors.leftMargin: Math.round(root.controller.keyH * 0.12)
                    anchors.right: parent.right
                    anchors.rightMargin: Math.round(root.controller.keyH * 0.1)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    elide: Text.ElideRight
                    color: modelData.current ? Theme.primary : root.controller.fg
                    font.pixelSize: Math.round(root.controller.keyH * 0.3)
                    font.weight: modelData.current ? Font.DemiBold : Font.Normal
                }

                // 涟漪：输入法行没有底色，扩散范围留一点内边距
                DRipple {
                    id: rowRipple
                    anchors.fill: parent
                    anchors.margins: Math.round(root.controller.gap * 0.4)
                    cornerRadius: Theme.cornerRadius
                    rippleColor: modelData.current ? Theme.onPrimary : Theme.primary
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onPressed: mouse => rowRipple.trigger(mouse.x, mouse.y)
                    onClicked: {
                        // 纯键盘布局直接切；拼音类输入法走 selectImMode，
                        // 它会在切换生效后再校正中英文状态
                        if (modelData.keyboard)
                            root.controller.selectIm(modelData.name)
                        else
                            root.controller.selectImMode(modelData.name, modelData.ascii)
                        root.controller.imPickerOpen = false
                    }
                }
            }
        }
    }
}
