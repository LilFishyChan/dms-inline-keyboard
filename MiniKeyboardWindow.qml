// 最小化模式：整个键盘收起来，屏幕上只留一个浮动的小圆按钮。
//
// 和语音模式（VoiceMiniWindow）是两回事：
//   · 语音模式 → 一条胶囊，承载语音行
//   · 最小化   → 一个圆按钮，什么都不承载，点一下把键盘叫回来
//
// 主键盘窗口在最小化期间被销毁（不是隐藏 —— 隐藏时 layer surface 的
// 输入区域还留在屏幕上，会吃掉点击）。点击、拖动都由本窗口自己处理。
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

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
    // （miniPosRight/miniPosBottom 为 -1 表示还没拖过，用默认边距）
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
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    implicitWidth: btnSize
    implicitHeight: btnSize

    // PanelWindow 的 mask 同时是指针输入区域，不设就收不到点击。
    // 不可见时必须收成 0：layer surface 隐藏后 mask 仍留在屏幕上继续吃点击
    //（和 KeyboardWindow 里那条实测结论同一个坑），否则关闭状态下会挡住右下角。
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

        DankIcon {
            anchors.centerIn: parent
            name: "keyboard"
            size: Math.round(miniWindow.btnSize * 0.5)
            color: Theme.primary
        }

        Ripple {
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
            onPressed: mouse => bubbleRipple.press(mouse.x, mouse.y)
            onReleased: bubbleRipple.release()
            onCanceled: bubbleRipple.release()
            onClicked: {
                if (miniWindow.controller)
                    miniWindow.controller.restoreFromMinimize()
            }
        }
    }
}
