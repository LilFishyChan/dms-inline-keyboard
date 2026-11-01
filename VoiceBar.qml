// 语音输入时占据顶部那一行（快捷栏 / 候选栏共用同一块高度）。
// 布局按「以功能栏为基础」来：两端是圆形按钮，中间是内容区。
import "alpha.js" as Alpha
import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: voiceBar

    property var controller: null
    // daemon 上没有 keyH/pad 这些度量，由宿主把 KeyboardMetrics 传进来
    property var metrics: null
    property real dragOriginX: 0
    property real dragOriginY: 0
    // 正在识别到的文字。vinput 录音时只 setPreedit、从不设候选，所以这里读的是预编辑字符串。
    readonly property string text: (controller.fcitxPreedit || "")
    // 度量来源有两种：
    //   · 主键盘里 controller 是卡片，card 上直接有 keyH / pad / quickH
    readonly property var src: metrics ? metrics : controller
    readonly property real mkeyH: src && src.keyH ? src.keyH : 44
    // 这一行的高度是 quickH（顶部动作栏那一行），不是底部把手的 handleH：拿 handleH 算会小一圈（图标 16 vs 24，按钮 28 vs 41）。
    readonly property real mrowH: src && src.quickH ? Math.max(src.quickH, src.candH || 0) : 48
    readonly property real mpad: src && src.pad ? src.pad : 8
    // 和功能栏（QuickBar）保持一致：按钮就是整行高度，图标半行高
    readonly property real btn: Math.round(mrowH)
    readonly property real icon: Math.round(mrowH * 0.5)
    // 胶囊是大圆角，两侧按钮留出和上下对称的边距
    //（(行高 - 按钮)/2），否则圆形按钮会压到圆角的切线上。
    readonly property real sidePad: Math.max(0, Math.round((height - btn) / 2))

    // 拖动请求交给宿主窗口处理（layer-shell 的位置只能由窗口的 margins 改）
    signal dragRequested(real dx, real dy)

    // 整行背景：和键盘卡片同色。
    // 不加的话这一行是透明的，在表情页 / 功能页上会透过分类条、列表看到重叠的内容。
    Rectangle {
        anchors.fill: parent
        radius: Theme.fullRadius(width, height)
        color: Theme.withAlpha(Theme.hostSurface, voiceBar.controller ? voiceBar.controller.bgOpacity : 1)
    }

    // 左：向下箭头 → 小模式
    DActionButton {
        id: collapseBtn

        anchors.left: parent.left
        anchors.leftMargin: voiceBar.sidePad
        anchors.verticalCenter: parent.verticalCenter
        buttonSize: voiceBar.btn
        // 和调整大小面板的「铺满 / 收起」用同一对图标
        iconName: voiceBar.controller.voiceMinimal ? "expand_content" : "collapse_content"
        iconSize: voiceBar.icon
        iconColor: Theme.surfaceText
        backgroundColor: Theme.chipSurface
        stateColor: Theme.surfaceText
        tooltipText: I18n.trFor("inlineKeyboard", "Voice input")

        onClicked: voiceBar.controller.voiceMinimalRequested()
    }

    // 中：识别文字
    // 用 Item 夹在两端按钮之间，文字在里面左对齐；超长时从**前面**省略，让最近说的几个字留在视野里。
    Item {
        id: textArea

        anchors.left: collapseBtn.right
        anchors.right: micBtn.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: voiceBar.sidePad
        anchors.rightMargin: voiceBar.sidePad
        clip: true

        // 拖动只挂在中间这块：挂在 VoiceBar 根上会先抢事件，两侧按钮的 MouseArea 就再也收不到点击了
        DragHandler {
            target: null
            onActiveChanged: {
                if (active) {
                    voiceBar.dragOriginX = 0;
                    voiceBar.dragOriginY = 0;
                }
            }
            onTranslationChanged: {
                if (!active)
                    return ;

                // 逐帧增量：每次把本次位移发出去，窗口那边累加到 posX/posY
                voiceBar.dragRequested(translation.x - voiceBar.dragOriginX, translation.y - voiceBar.dragOriginY);
                voiceBar.dragOriginX = translation.x;
                voiceBar.dragOriginY = translation.y;
            }
        }

        StyledText {
            id: label

            // 和左边那个圆形按钮之间留一点空隙（textArea 的左 margin 在主键盘里是 0，紧贴着按钮看起来像粘在一起）
            readonly property real leadGap: Math.round(voiceBar.mkeyH * 0.35)

            anchors.verticalCenter: parent.verticalCenter
            x: leadGap
            width: Math.max(0, textArea.width - leadGap)
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideLeft
            wrapMode: Text.NoWrap
            text: voiceBar.text
            color: Theme.surfaceText
            font.pixelSize: Math.max(Theme.fontSizeSmall, Math.round(voiceBar.mkeyH * 0.3))
            font.weight: Font.Medium

            // 点文字 = 关掉语音
            TapHandler {
                enabled: voiceBar.text !== ""
                onTapped: voiceBar.controller.voiceMicRequested()
            }

        }

        // 只在没激活时提示，录音中不占位
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            x: label.x
            visible: voiceBar.text === "" && !voiceBar.controller.voiceActive
            text: I18n.trFor("inlineKeyboard", "Tap the mic on the right to start")
            color: Theme.withAlpha(Theme.surfaceText, Alpha.Muted)
            font.pixelSize: label.font.pixelSize
        }

    }

    // 右：麦克风
    DActionButton {
        id: micBtn

        anchors.right: parent.right
        anchors.rightMargin: voiceBar.sidePad
        anchors.verticalCenter: parent.verticalCenter
        buttonSize: voiceBar.btn
        iconName: "mic"
        iconSize: voiceBar.icon
        iconColor: voiceBar.controller.voiceActive ? Theme.onPrimary : Theme.withAlpha(Theme.surfaceText, Alpha.Strong)
        // 激活态用主色实心，和固定框同一套
        backgroundColor: voiceBar.controller.voiceActive ? Theme.primary : Theme.chipSurface
        stateColor: voiceBar.controller.voiceActive ? Theme.onPrimary : Theme.surfaceText
        tooltipText: I18n.trFor("inlineKeyboard", "Pause recording")

        onClicked: voiceBar.controller.voiceMicRequested()
    }

}
