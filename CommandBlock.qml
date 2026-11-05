// 安装 / 更新命令的展示块：等宽字体、自动换行、圆角浅底。
//
// 只在「没装」或「版本过期」时由调用方 visible 控制，内容也由调用方决定
// （安装命令 vs 更新命令），这里只管长相。

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Rectangle {
    id: root

    property string commandText: ""

    // height 和 visible 互相引用会成环：高度由 implicitHeight 一次算清
    implicitHeight: commandLabel.implicitHeight + Theme.spacingL * 2
    height: implicitHeight
    width: parent ? parent.width : 0
    radius: Theme.cornerRadius
    color: SettingsMetrics.controlSurface

    StyledText {
        id: commandLabel

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingL
        text: root.commandText
        color: Theme.surfaceText
        isMonospace: true
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WrapAnywhere
    }

}
