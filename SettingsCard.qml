// 设置页的分组卡片：内容竖排，高度按内容撑开。
// 插件不能依赖 DMS 应用内部的 SettingsGroup/SettingsRow，示例插件也是自带一套。
import QtQuick
import qs.Common
import qs.Widgets

StyledRect {
    id: root

    default property alias content: contentColumn.data

    width: parent.width
    height: contentColumn.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainer
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium
    // 内容超出卡片时裁掉，避免滑块之类按自己的最小宽度顶出去
    clip: true

    Column {
        id: contentColumn

        width: parent.width - Theme.spacingL * 2
        anchors.centerIn: parent
        spacing: Theme.spacingM
    }

}
