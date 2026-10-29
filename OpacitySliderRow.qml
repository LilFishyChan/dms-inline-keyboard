// 透明度面板的一行：左边标签、右边百分比、下面一条滑块。
// 由 TransparencyPanel 实例化两次（背景 / 按键），改值通过 moved 信号交给调用方。
import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

Item {
    id: root

    property string label: ""
    // 0.1 ~ 1.0（与插件设置里的百分数一致）
    property real value: 1.0
    property real minimum: 0.1
    property real maximum: 1.0
    // 文字大小按键高换算，跟键盘缩放一起变
    property real keyH: 64
    property color textColor: Theme.surfaceText

    signal moved(real newValue)

    readonly property int labelPixelSize: Math.max(12, Math.round(keyH * 0.27))

    implicitHeight: labelRow.height + 10 + valueSlider.height

    Column {
        width: parent.width
        spacing: 10

        Item {
            id: labelRow
            width: parent.width
            height: labelText.implicitHeight

            Text {
                id: labelText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: root.textColor
                font.pixelSize: root.labelPixelSize
            }
        }

        DCommon.DSlider {
            id: valueSlider
            width: parent.width
            value: Math.round(root.value * 100)
            minimum: Math.round(root.minimum * 100)
            maximum: Math.round(root.maximum * 100)
            onSliderValueChanged: v => root.moved(v / 100.0)
        }
    }
}
