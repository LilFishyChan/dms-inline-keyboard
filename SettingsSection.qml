// 分组标题：小字，和 DMS 设置页的章节标题一致。
import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    property alias text: titleText.text

    width: parent.width
    height: titleText.implicitHeight

    StyledText {
        id: titleText

        width: parent.width
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: Theme.primary
    }

}
