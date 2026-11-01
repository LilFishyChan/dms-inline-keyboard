// Inline Keyboard 底部把手行：左侧收起键、中间「拼」/输入法状态、右侧 fcitx5 托盘图标。
// 高度是半个标准键高；图标裸画不加深色底块。由 KeyboardCard 实例化。
import "alpha.js" as Alpha
import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Services

Item {
    id: handleBar

    property var controller: null
    // 中间拖动把手的外观。宽度跟随把手行高度（≈2.6 倍），键盘尺寸变化时比例不变。
    readonly property real gripWidth: Math.round(controller.handleH * 2.6)
    readonly property real gripHeightRatio: 0.12
    // 两端的圆形按钮尺寸：和顶部动作栏固定按钮同一套比例
    readonly property real endBtn: Math.round(controller.handleH * 0.86)
    readonly property real endIcon: Math.round(controller.handleH * 0.5)

    // 模拟使用流程：底部两个按钮（close = 关闭键盘 / lang = 地球键）
    function pointerTap(which) {
        if (which === "close") {
            hideBtn.tapAt();
            return true;
        }
        if (which === "lang") {
            langBtn.tapAt();
            return true;
        }
        return false;
    }

    width: parent.width
    height: controller.handleH
    visible: controller.showHandle

    // 左端：收起。圆形触控区，背景透明、图标用正文色，和底部整行的观感一致（不额外压一个色块）。
    DActionButton {
        id: hideBtn

        anchors.left: parent.left
        anchors.leftMargin: controller.pad
        anchors.verticalCenter: parent.verticalCenter
        buttonSize: handleBar.endBtn
        iconName: "expand_more"
        iconSize: handleBar.endIcon
        iconColor: controller.fg
        backgroundColor: "transparent"
        stateColor: controller.fg
        tooltipText: controller.tooltips ? I18n.trFor("inlineKeyboard", "Collapse keyboard") : ""

        function tapAt() {
            controller.quickAction("close");
        }

        onClicked: tapAt()
    }

    // 中间：拖动把手（仅浮动模式）
    Rectangle {
        id: grip

        visible: controller.dragEnabled
        anchors.centerIn: parent
        width: handleBar.gripWidth
        height: Math.max(3, controller.handleH * handleBar.gripHeightRatio)
        radius: Theme.fullRadius(width, height)
        color: Theme.withAlpha(controller.fg, Alpha.Half)
    }

    // 拖动区：整条把手（两端图标除外）
    Item {
        id: dragArea

        anchors.left: hideBtn.right
        anchors.right: langBtn.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: controller.dragEnabled

        DragHandler {
            target: null
            onActiveChanged: {
                if (active)
                    controller.dragStarted();

            }
            onTranslationChanged: controller.dragMoved(translation.x, translation.y)
        }

    }

    // 右端：地球 —— 点击切换输入法。样式同左端。
    DActionButton {
        id: langBtn

        anchors.right: parent.right
        anchors.rightMargin: controller.pad
        anchors.verticalCenter: parent.verticalCenter
        buttonSize: handleBar.endBtn
        iconName: "language"
        iconSize: handleBar.endIcon
        iconColor: controller.fg
        backgroundColor: "transparent"
        stateColor: controller.fg
        tooltipText: controller.tooltips ? I18n.trFor("inlineKeyboard", "Cycle input method") : ""

        // 长按开选择器，短按循环切换；按钮自己不带长按，按住计时器判定
        property bool longFired: false

        // 单击逻辑抽成函数：模拟点击和手指点走同一份
        function tapAt() {
            controller.imCycleRequested();
        }

        onPressed: {
            longFired = false;
            holdTimer.restart();
        }
        onReleased: holdTimer.stop()
        onCanceled: {
            holdTimer.stop();
            longFired = false;
        }
        onClicked: {
            if (!longFired)
                tapAt();
        }

        Timer {
            id: holdTimer

            interval: 500
            onTriggered: {
                langBtn.longFired = true;
                // 清单是 addon 推来的；空的时候置 imPickerOpen 只会让面板稍后自己弹出来
                if (controller.imRows.length === 0) {
                    ToastService.showInfo(I18n.trFor("inlineKeyboard", "Input method list is empty — is the fcitx5 addon running?"));
                    return;
                }
                controller.imPickerOpen = true;
            }
        }
    }

}
