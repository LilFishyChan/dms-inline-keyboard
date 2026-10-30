// 最小化模式：键盘收起，屏幕上只留一个浮动圆按钮，点一下叫回键盘。
// 和语音模式（一条胶囊）是两种布局。主键盘窗口在最小化期间被销毁
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

PanelWindow {
    id: miniWindow

    property var controller: null

    // 用主键盘的度量算按钮大小，切到不同键盘尺寸时自动跟着变
    KeyboardMetrics {
        id: metrics
        kbWidth: controller ? controller.savedW : 1050
        kbHeight: controller ? controller.kbHeight : 444
        screenW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920
        screenH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080
    }

    readonly property real btnSize: Math.round(metrics.keyH * 1.15)
    readonly property real edge: Math.round(metrics.pad * 2)

    visible: controller ? controller.minimized : false
    color: "transparent"

    // 可拖动：锚点 + margins（layer-shell 不能直接改 x/y）。
    // 位置存在 daemon 里，下次最小化还回到用户拖到的地方
    property real posRight: controller && controller.miniPosRight >= 0
                            ? controller.miniPosRight : edge
    property real posBottom: controller && controller.miniPosBottom >= 0
                             ? controller.miniPosBottom : edge
    property real dragOriginX: 0
    property real dragOriginY: 0
    // 这次按下有没有真的挪动过：原地点击不该写盘（每次点恢复按钮都会走一遍）
    property bool dragMoved: false

    anchors {
        bottom: true
        right: true
    }

    margins {
        right: Math.round(Math.max(0, Math.min(metrics.screenW - btnSize, posRight)))
        bottom: Math.round(Math.max(0, Math.min(metrics.screenH - btnSize, posBottom)))
    }

    // 每次出现都夹回屏幕内（保存的值可能来自分辨率变化的上一块屏）
    onVisibleChanged: {
        if (visible) {
            posRight = Math.round(Math.max(0, Math.min(metrics.screenW - btnSize, posRight)))
            posBottom = Math.round(Math.max(0, Math.min(metrics.screenH - btnSize, posBottom)))
        }
    }

    WlrLayershell.namespace: "dms:plugins:inlineKeyboard:minimized"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    implicitWidth: btnSize
    implicitHeight: btnSize

    // mask 同时是指针输入区域；不可见时收成 0，否则隐藏后仍会吃点击
    mask: Region {
        x: 0
        y: 0
        width: miniWindow.visible ? Math.round(miniWindow.width) : 0
        height: miniWindow.visible ? Math.round(miniWindow.height) : 0
    }

    Rectangle {
        id: bubble
        anchors.fill: parent
        radius: width / 2
        color: Theme.withAlpha(Theme.surface, controller ? controller.bgOpacity : 1.0)
        border.width: 2
        border.color: Theme.withAlpha(Theme.primary, 0.5)

        DIcon {
            anchors.centerIn: parent
            name: "keyboard"
            size: Math.round(miniWindow.btnSize * 0.5)
            color: Theme.primary
        }

        DRipple {
            id: bubbleRipple
            anchors.fill: parent
            cornerRadius: width / 2
        }

        // 拖动和点击共存：DragHandler 只在超过阈值后接管，
        // 手指原地抬起仍然是一次正常点击
        DragHandler {
            target: null
            onActiveChanged: {
                if (active) {
                    miniWindow.dragOriginX = 0
                    miniWindow.dragOriginY = 0
                    miniWindow.dragMoved = false
                } else if (miniWindow.dragMoved && miniWindow.controller) {
                    // 松手落盘：下次最小化回到这个位置
                    miniWindow.controller.saveMiniPos(
                        Math.round(Math.max(0, miniWindow.posRight)),
                        Math.round(Math.max(0, miniWindow.posBottom)))
                }
            }
            onTranslationChanged: {
                if (!active)
                    return
                miniWindow.dragMoved = true
                miniWindow.posRight = miniWindow.posRight - (translation.x - miniWindow.dragOriginX)
                miniWindow.posBottom = miniWindow.posBottom - (translation.y - miniWindow.dragOriginY)
                miniWindow.dragOriginX = translation.x
                miniWindow.dragOriginY = translation.y
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => bubbleRipple.trigger(mouse.x, mouse.y)
            onClicked: {
                if (miniWindow.controller)
                    miniWindow.controller.restoreFromMinimize()
            }
        }
    }
}
