// 语音输入时占据顶部那一行（快捷栏 / 候选栏共用同一块高度）。
//
// 布局按「以功能栏为基础」来：两端是圆形按钮，中间是内容区。
//   左：四角向内 —— 点击进入小模式（浮动 + 只留这一行），图标随之翻成四角向外
//   中：当前识别到的文字，过长时省略**前面**（和候选栏首项同一套习惯）
//   右：麦克风 —— 正在录音
//
// 优先级由外层保证：语音 > 候选 > 功能。本组件只在录音中显示。
import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: voiceBar


    property var controller: null
    // daemon 上没有 keyH/pad 这些度量，由宿主把 KeyboardMetrics 传进来
    property var metrics: null
    // 拖动请求交给宿主窗口处理（layer-shell 的位置只能由窗口的 margins 改）
    signal dragRequested(real dx, real dy)
    property real dragOriginX: 0
    property real dragOriginY: 0

    // 正在识别到的文字。vinput 录音时只 setPreedit、从不设候选，
    // 所以这里读的是预编辑字符串。
    readonly property string text: (controller.fcitxPreedit || "")

    // 度量来源有两种：
    //   · 主键盘里 controller 是卡片，card 上直接有 keyH / pad / quickH
    //   · 语音胶囊里 controller 是 daemon（没有这些），由宿主传 metrics
    // 所以这里优先用 metrics，没有就退回 controller，两者都没有才用兜底值。
    readonly property var src: metrics ? metrics : controller
    readonly property real mkeyH: src && src.keyH ? src.keyH : 44
    // 这一行的高度是 quickH（顶部动作栏那一行），不是底部把手的 handleH：
    // 拿 handleH 算会小一圈（图标 16 vs 24，按钮 28 vs 41）。
    readonly property real mrowH: src && src.quickH
        ? Math.max(src.quickH, src.candH || 0) : 48
    readonly property real mpad: src && src.pad ? src.pad : 8
    // 和功能栏（QuickBar）保持一致：按钮就是整行高度，图标半行高。
    // 之前乘了 0.86，比功能栏小一圈。
    readonly property real btn: Math.round(mrowH)
    readonly property real icon: Math.round(mrowH * 0.5)
    // 胶囊是大圆角，两侧按钮留出和上下对称的边距
    //（(行高 - 按钮)/2），否则圆形按钮会压到圆角的切线上。
    // 注意主键盘里这一行的高度正好等于按钮高，算出来是 0 —— 那里按钮本来就
    // 贴着键盘左右内沿（和 QuickBar 两端按钮同一套位置），不是漏了边距。
    readonly property real sidePad: Math.max(0, Math.round((height - btn) / 2))

    // 整行背景：和键盘卡片同色。
    // 不加的话这一行是透明的，在表情页 / 功能页上会透过分类条、列表看到重叠的内容。
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.withAlpha(Theme.surface,
                               voiceBar.controller ? voiceBar.controller.bgOpacity : 1.0)
    }

    // ---- 左：向下箭头 → 小模式 ----
    Rectangle {
        id: collapseBtn
        anchors.left: parent.left
        anchors.leftMargin: voiceBar.sidePad
        anchors.verticalCenter: parent.verticalCenter
        width: voiceBar.btn
        height: voiceBar.btn
        radius: width / 2
        color: Theme.surfaceContainer

        DankIcon {
            anchors.centerIn: parent
            // 和调整大小面板的「铺满 / 收起」用同一对图标：
            //   普通模式 → collapse_content（收成语音条）
            //   语音模式 → expand_content（恢复全键盘）
            name: voiceBar.controller.voiceMinimal ? "expand_content" : "collapse_content"
            size: voiceBar.icon
            // 文字色，和这一行的其它文字一致
            color: Theme.surfaceText
        }

        Ripple {
            id: collapseRipple
            anchors.fill: parent
            cornerRadius: width / 2
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => collapseRipple.press(mouse.x, mouse.y)
            onReleased: collapseRipple.release()
            onCanceled: collapseRipple.release()
            onClicked: voiceBar.controller.voiceMinimalRequested()
        }
    }

    // ---- 中：识别文字 ----
    // 用 Item 夹在两端按钮之间，文字在里面左对齐；超长时从**前面**省略，
    // 和候选栏首项一致 —— 正在说的话，末尾才是刚刚识别到的部分。
    Item {
        id: textArea
        anchors.left: collapseBtn.right
        anchors.right: micBtn.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: voiceBar.sidePad
        anchors.rightMargin: voiceBar.sidePad
        clip: true

        // 拖动只挂在中间这块：挂在 VoiceBar 根上会先抢事件，
        // 两侧按钮的 MouseArea 就再也收不到点击了
        DragHandler {
            target: null
            onActiveChanged: {
                if (active) {
                    voiceBar.dragOriginX = 0
                    voiceBar.dragOriginY = 0
                }
            }
            onTranslationChanged: {
                if (!active)
                    return
                // 逐帧增量：每次把本次位移发出去，窗口那边累加到 posX/posY
                voiceBar.dragRequested(translation.x - voiceBar.dragOriginX,
                                       translation.y - voiceBar.dragOriginY)
                voiceBar.dragOriginX = translation.x
                voiceBar.dragOriginY = translation.y
            }
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            // 和左边那个圆形按钮之间留一点空隙（textArea 的左 margin 在主键盘里是 0，
            // 紧贴着按钮看起来像粘在一起）
            readonly property real leadGap: Math.round(voiceBar.mkeyH * 0.35)
            x: leadGap
            width: Math.max(0, textArea.width - leadGap)
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideLeft
            wrapMode: Text.NoWrap
            text: voiceBar.text
            color: Theme.surfaceText
            font.pixelSize: Math.max(12, Math.round(voiceBar.mkeyH * 0.3))
            font.weight: Font.Medium

            // 点文字 = 关掉语音
            TapHandler {
                enabled: voiceBar.text !== ""
                onTapped: voiceBar.controller.voiceMicRequested()
            }
        }

        // 只在没激活时提示，录音中不占位
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: label.x
            visible: voiceBar.text === "" && !voiceBar.controller.voiceActive
            text: I18n.trFor("inlineKeyboard", "Tap the mic on the right to start")
            color: Theme.withAlpha(Theme.surfaceText, 0.55)
            font.pixelSize: label.font.pixelSize
        }
    }

    // ---- 右：麦克风 ----
    Rectangle {
        id: micBtn
        anchors.right: parent.right
        anchors.rightMargin: voiceBar.sidePad
        anchors.verticalCenter: parent.verticalCenter
        width: voiceBar.btn
        height: voiceBar.btn
        radius: width / 2
        // 激活态用主色实心，和固定框同一套：底色 primary、图标 onPrimary
        color: voiceBar.controller.voiceActive ? Theme.primary : Theme.surfaceContainer

        DankIcon {
            anchors.centerIn: parent
            name: "mic"
            size: voiceBar.icon
            // 激活态图标转 onPrimary；未激活用正文色
            //（不能写 controller.fg —— 胶囊窗口里 controller 是 daemon，
            //  没有 fg 属性，取到 undefined 会让图标整个透明）
            color: voiceBar.controller.voiceActive
                   ? Theme.onPrimary
                   : Theme.withAlpha(Theme.surfaceText, 0.8)
        }

        Ripple {
            id: micRipple
            anchors.fill: parent
            cornerRadius: width / 2
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => micRipple.press(mouse.x, mouse.y)
            onReleased: micRipple.release()
            onCanceled: micRipple.release()
            onClicked: voiceBar.controller.voiceMicRequested()
        }
    }
}
