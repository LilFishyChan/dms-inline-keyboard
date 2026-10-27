// 单个按键：主/副两行键帽文字、Fn 层替换、按下高亮与涟漪。
// 布局数据来自 layouts/phone.js，本文件只负责画一个键。

import QtQuick
import qs.Common
import qs.Widgets
import Qt5Compat.GraphicalEffects

// 单个按键。宽度/高度都由 unit、keyH、gap 推出来，布局只负责给单位宽和跨行数。
Item {
    id: root

    required property var keyData
    property real unit: 63
    property real keyH: 64
    property real gap: 6
    // 跨几行（小键盘的 + 和 Enter 是 2）
    property int span: 1
    property bool fnActive: false
    // 修饰键状态：0 未激活 / 1 一次性 / 2 锁定（卡片按 keyData 推出来）
    property int modifierState: 0
    // 当前页指示（第二页按钮在两页里都显示，靠它表现激活态）
    property bool active: false
    // 插件自己维护的按键透明度
    property real keyOpacity: 1.0
    // 字母是否大写：shift 激活 / caps 锁定时为 true（默认小写）
    property bool upperMode: false

    readonly property string kind: keyData.k || "char"
    readonly property real wUnits: keyData.w || 1
    readonly property bool isSpacer: kind === "spacer"
    readonly property bool useFn: fnActive && !!keyData.fn
    // 单个字母的字符键：默认小写，shift/caps 时大写
    readonly property bool isLetter: kind === "char" && !!keyData.l
                                     && /^[A-Za-z]$/.test(keyData.l)
    // 有上下档两个标签的键（1/!、;/: …）
    readonly property bool hasShiftPair: kind === "char" && !!keyData.s

    readonly property string mainLabel: {
        if (useFn)
            return keyData.fn.l
        if (isLetter)
            return upperMode ? keyData.l.toUpperCase() : keyData.l.toLowerCase()
        return keyData.l || ""
    }

    // 双标签键：**当前会输入的那个**用大字号（和字母键一样），另一个小字。
    // 默认：上=上档(小)、下=下档(大)；shift 激活时位置和字号整体互换 → 上=下档(小)、下=上档(大)
    // ⚠ 双标签只在「不在 Fn 层」时成立：Fn 层的键（F1/F2…）没有上下档，
    // 直接用 mainLabel，否则数字键会一直显示 1/! 而不切到 F1
    readonly property string pairBig: (hasShiftPair && !useFn)
        ? (upperMode ? keyData.s : keyData.l) : mainLabel
    readonly property string pairSmall: (hasShiftPair && !useFn)
        ? (upperMode ? keyData.l : keyData.s) : ""

    // 上面那行文字 / 下面那行文字
    readonly property string topLabel: useFn ? "" : (hasShiftPair
        ? (upperMode ? pairBig : pairSmall) : "")
    readonly property string bottomLabel: hasShiftVariant
        ? effectiveLabel
        : ((hasShiftPair && !useFn) ? (upperMode ? pairSmall : pairBig) : mainLabel)
    // 两行各自的字号比例：大字永远当前输入项
    readonly property real topRatio: (hasShiftPair && !useFn && upperMode)
        ? mainLabelRatio : upperLabelRatio
    readonly property real bottomRatio: (hasShiftPair && !useFn && upperMode)
        ? upperLabelRatio : mainLabelRatio
    // 「非当前状态会输入」的那一行：比正文色再淡一档，层次更清楚
    readonly property color minorLabelColor: Theme.withAlpha(Theme.onSurfaceVariant, 0.6)
    // 键面图标（表情、第二页、菜单…）。可以是 Material 名字，也可以是图片路径
    readonly property string iconName: keyData.icon || ""
    readonly property bool iconIsImage: {
        const n = root.iconName
        if (n === "")
            return false
        return n.indexOf("file://") === 0 || n.indexOf("/") === 0
               || /\.(svg|png|jpe?g|webp)$/i.test(n)
    }
    readonly property string iconSource: {
        const n = root.iconName
        if (!root.iconIsImage)
            return ""
        if (n.indexOf("://") > 0 || n.indexOf("file:") === 0)
            return n
        if (n.indexOf("/") === 0)
            return "file://" + n
        return Qt.resolvedUrl(n)
    }

    // Shift 下的替代键：Enter 在 Shift 激活时变 Del（显示和执行都换）
    readonly property bool hasShiftVariant: !!keyData.shift && upperMode
    readonly property string effectiveLabel: hasShiftVariant ? keyData.shift.l : mainLabel
    // 真正要注入的键码：Fn 层的键（F1-F12）和 Shift 变体（Enter→Del）都在这儿定
    readonly property int effectiveCode: {
        if (hasShiftVariant && keyData.shift && keyData.shift.c)
            return keyData.shift.c
        if (useFn && keyData.fn && keyData.fn.c)
            return keyData.fn.c
        return keyData.c || 0
    }
    // 交给卡片的 keyData：标签和键码都换成当前生效的（信号签名不用动）
    readonly property var effectiveKeyData: ({
        k: keyData.k,
        l: effectiveLabel,
        c: effectiveCode,
        w: keyData.w,
        to: keyData.to
    })
    // 底行右三个图标键（菜单/表情/第二页）图标放大
    readonly property bool bigIcon: keyData.big === true
    readonly property bool isModifier: kind === "key" || kind === "shift" || kind === "fn"
                                     || kind === "stub" || kind === "page"
    // ---- 键面配色 ----
    // 用 M3 的语义色，不自己叠 alpha 造层级：
    //   普通键      surfaceContainer        修饰键 surfaceContainerHighest
    //   激活(1)     底色不变 + primary 描边 + primary 文字（"待生效"）
    //   锁定(2)     primary 实心 + onPrimary 文字（"持续生效"）
    // 用「有没有填充」区分两档，不靠透明度：alpha 叠加在浅/深主题下混合结果不同，
    // 形状差异才是稳的。Theme.primaryContainer 也不能用——DMS 会给它叠 elevation 淡化。
    readonly property bool lockedLook: (isModifier && modifierState > 1) || active
    readonly property bool activeLook: isModifier && modifierState === 1

    readonly property color fillColor: {
        if (lockedLook) return Theme.primary
        // Fn 和其它修饰键一样：激活靠描边、锁定靠实心，不再单独用淡底
        if (isModifier) return Theme.surfaceContainerHighest
        return Theme.surfaceContainer
    }

    readonly property color labelColor: {
        if (lockedLook) return Theme.onPrimary
        if (activeLook) return Theme.primary      // 描边态：主题色文字
        return fg
    }

    readonly property color fg: Theme.surfaceText

    // ---- 字号比例 ----
    readonly property real activeBorderWidth: 2        // 激活态描边宽度（px）
    readonly property real cornerRatio: 0.18           // 键帽圆角相对键高
    readonly property real iconRatio: 0.34
    readonly property real bigIconRatio: 0.51
    readonly property real upperLabelRatio: 0.2
    readonly property real mainLabelRatio: 0.32
    readonly property real mainLabelWithUpperRatio: 0.3
    readonly property real labelGapRatio: -0.02

    function pressRipple(px, py) {
        ripple.press(px, py)
    }

    function releaseRipple() {
        ripple.release()
    }

    // 宽度补偿：w 个单位 = w*unit + (w-1) 个间距。
    // 这样"一行若干键"的总宽恒等于 15 个单位对应的宽度，与这一行有几个键无关 ——
    // 底行只有 8 个键，也能和上面 15 个键的行右边缘对齐。
    width: unit * wUnits + Math.max(0, wUnits - 1) * gap
    height: keyH * span + Math.max(0, span - 1) * gap
    enabled: !isSpacer

    Rectangle {
        id: bg
        anchors.fill: parent
        visible: !root.isSpacer
        opacity: root.keyOpacity
        clip: true
        radius: Math.min(Theme.cornerRadius, root.keyH * root.cornerRatio)
        // 底色见上面的 fillColor；激活态不改底色，靠下面这圈描边表示
        color: root.fillColor
        border.width: root.activeLook ? root.activeBorderWidth : 0
        border.color: Theme.primary

        Ripple {
            id: ripple
            anchors.fill: parent
            cornerRadius: bg.radius
        }

        Column {
            anchors.centerIn: parent
            spacing: root.keyH * root.labelGapRatio

            Text {
                visible: root.topLabel !== ""
                text: root.topLabel
                width: Math.max(10, bg.width - 8)
                horizontalAlignment: Text.AlignHCenter
                // shift 激活时这行是「当前输入的大字」，用正文色；否则是次要标签，淡一档
                color: root.topRatio === root.mainLabelRatio
                       ? root.labelColor : root.minorLabelColor
                font.pixelSize: Math.round(root.keyH * root.topRatio)
                font.weight: root.topRatio === root.mainLabelRatio ? Font.Medium : Font.Normal
            }

            // 图标键（表情 / 第二页 / 菜单）。icon 是图片路径时用 Image 渲染
            DankIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.iconName !== "" && !root.iconIsImage
                name: root.iconName
                size: Math.round(root.keyH * (root.bigIcon ? root.bigIconRatio : root.iconRatio))
                color: root.labelColor
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.iconIsImage
                source: root.iconSource
                readonly property int px: Math.round(root.keyH * (root.bigIcon
                                                                 ? root.bigIconRatio : root.iconRatio))
                width: px
                height: px
                sourceSize: Qt.size(px, px)
                fillMode: Image.PreserveAspectFit
                smooth: true
                // 染成按键文字色，跟字体图标一致
                layer.enabled: visible
                layer.effect: ColorOverlay { color: root.labelColor }
            }

            Text {
                visible: root.iconName === ""
                width: Math.max(10, bg.width - 8)
                horizontalAlignment: Text.AlignHCenter
                text: root.bottomLabel
                color: root.bottomRatio === root.mainLabelRatio
                       ? root.labelColor : root.minorLabelColor
                // 长标签（Backspace / Caps Lock）自动缩到放得下
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 7
                font.pixelSize: Math.round(root.keyH * root.bottomRatio)
                font.weight: Font.Medium
            }
        }
    }
}
