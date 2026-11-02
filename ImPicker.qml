import QtQuick
// 输入法选择器（长按底部地球打开）。
// 键盘内部的下拉框：从右下角弹出、内容可滚动；上半是输入法、下半是它的开关，带子菜单的点进去看下一层
import "alpha.js" as Alpha
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    // 地球键循环和这个列表必须同一份数据（KeyboardCard.imRows，带 text / current）

    id: picker

    property var controller: null
    // 子菜单栈：非空时显示栈顶那一层，返回时弹一层
    property var subStack: []
    // 状态区开关（addon 的 status: 帧），keyboard-us 这类没有开关时是空数组
    readonly property var statusRows: picker.controller && picker.controller.statusItems ? picker.controller.statusItems : []
    // 当前显示的行。type: im（输入法）/ status（开关）/ separator（分隔线）/ back（返回上一层）
    readonly property var rows: {
        if (picker.subStack.length > 0)
            return picker.subStack[picker.subStack.length - 1];

        const out = [];
        const ims = picker.controller ? picker.controller.imRows : [];
        for (let i = 0; i < ims.length; i++) out.push({
            "type": "im",
            "im": ims[i]
        })
        if (picker.statusRows.length > 0) {
            out.push({
                "type": "separator"
            });
            for (let j = 0; j < picker.statusRows.length; j++) {
                const it = picker.statusRows[j];
                out.push(it.separator ? {
                    "type": "separator"
                } : {
                    "type": "status",
                    "item": it
                });
            }
        }
        return out;
    }

    function openSub(item) {
        const layer = [{
            "type": "back"
        }];
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) {
            const kid = kids[i];
            layer.push(kid.separator ? {
                "type": "separator"
            } : {
                "type": "status",
                "item": kid
            });
        }
        picker.subStack = picker.subStack.concat([layer]);
    }

    function goBack() {
        picker.subStack = picker.subStack.slice(0, picker.subStack.length - 1);
    }

    anchors.fill: parent
    z: 100
    // 没有可显示的内容时不该露出空面板（一片白色方块）
    visible: picker.controller.imPickerOpen && picker.rows.length > 0
    // 面板一关就把子菜单栈清掉，下次打开从顶层开始
    onVisibleChanged: {
        if (!visible)
            picker.subStack = [];

    }

    // 点面板外关闭
    MouseArea {
        anchors.fill: parent
        onClicked: picker.controller.imPickerOpen = false
    }

    // 下拉面板贴着右下角，在地球键上方
    Rectangle {
        id: panel

        readonly property real padding: Math.round(picker.controller.keyH * 0.14)

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Math.round(picker.controller.gap * 1.5)
        anchors.bottomMargin: Math.round(picker.controller.keyH * 0.6)
        width: Math.min(parent.width * 0.52, Theme.dialogMaxWidth * 0.72)
        // contentHeight 第一帧是 0，给个下限免得面板闪一下；上限挡住长列表，超出的滚动看
        height: Math.max(Math.round(picker.controller.keyH * 0.9), Math.min(listView.contentHeight + padding * 2, parent.height * 0.75))
        radius: Theme.cornerRadiusL
        color: Theme.floatingWindowSurface
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium

        // 吃掉面板内的点击，避免穿透到下面的关闭区域
        MouseArea {
            anchors.fill: parent
        }

        DListView {
            id: listView

            anchors.fill: parent
            anchors.margins: panel.padding
            clip: true
            model: picker.rows
            spacing: Math.round(picker.controller.gap * 0.6)

            // delegate 直接用 DListView 递的 modelData，不经过 Loader 转手
            delegate: Item {
                id: rowRoot

                required property var modelData
                readonly property bool isIm: modelData.type === "im"
                readonly property bool isStatus: modelData.type === "status"
                readonly property bool isSeparator: modelData.type === "separator"
                readonly property bool isBack: modelData.type === "back"
                readonly property var im: isIm ? modelData.im : null
                readonly property var item: isStatus ? modelData.item : null
                readonly property bool current: im !== null && im.current === true
                readonly property bool hasChildren: item !== null && (item.children || []).length > 0
                // 选择器给的是图片路径才画图标，图标名交给文字
                readonly property string iconSrc: item !== null && item.icon !== "" && item.icon.charAt(0) === "/" ? "file://" + item.icon : ""

                width: listView.width
                // 键盘缩到最小时 keyH 的下限是 28，0.68 倍只剩 19px，触摸目标太窄；给个下限兜住
                // 分隔行只占一条线的高度；留白交给 ListView 的 spacing，不然两层叠加会空出一大块
                height: isSeparator ? 1 : Math.max(Math.round(picker.controller.keyH * 0.68), Math.round(Theme.listItemHeight * 0.8))
                // 读屏用：整行是一个按钮，分隔线不参与
                Accessible.role: isSeparator ? Accessible.Separator : Accessible.Button
                Accessible.name: isSeparator ? "" : (isIm ? (im.label + " — " + im.name) : (isBack ? I18n.trFor("inlineKeyboard", "Back") : (item !== null ? item.text : "")))
                Accessible.ignored: isSeparator

                // 分隔线：高度按 gap 留，线画在中间。outlineMedium 是半透明的，浅底上看不见，这里用实色
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: rowRoot.isSeparator
                    width: parent.width
                    height: 1
                    color: Theme.outline
                }

                // 「← 返回」：子菜单的第一行
                Rectangle {
                    anchors.fill: parent
                    visible: rowRoot.isBack
                    radius: Theme.cornerRadiusS
                    color: backMouse.containsMouse ? Theme.withAlpha(picker.controller.fg, Alpha.Whisper) : "transparent"

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(picker.controller.keyH * 0.12)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "← " + I18n.trFor("inlineKeyboard", "Back")
                        color: picker.controller.fg
                        font.pixelSize: Math.round(picker.controller.keyH * 0.3)
                    }

                    MouseArea {
                        id: backMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: picker.goBack()
                    }

                }

                // 输入法行 / 开关行
                Rectangle {
                    id: rowItem

                    anchors.fill: parent
                    visible: rowRoot.isIm || rowRoot.isStatus
                    radius: Theme.cornerRadiusS
                    color: rowRoot.current ? Theme.selectedContainer : (rowMouse.containsMouse ? Theme.withAlpha(picker.controller.fg, Alpha.Whisper) : "transparent")

                    // 行内容：Row 从左到右排，visible 为 false 的不占位；有 chip 是 [chip][文字]、有图标是 [图标][文字]、都没有就 [文字] 顶到最左
                    Row {
                        id: rowContent

                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(picker.controller.keyH * 0.12)
                        anchors.right: arrow.visible ? arrow.left : parent.right
                        anchors.rightMargin: Math.round(picker.controller.keyH * 0.1)
                        anchors.verticalCenter: parent.verticalCenter
                        // chip / 图标和文字之间留一点点，用主题间距而不是写死像素
                        spacing: Theme.spacingS

                        // label 块：托盘上看到的那个字（万 / abc / en），只有输入法行有
                        Rectangle {
                            id: labelChip

                            visible: rowRoot.isIm
                            width: Math.round(rowRoot.height * 0.82)
                            height: width
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Math.round(width * 0.28)
                            color: rowRoot.current ? Theme.accentOnSelectedContainer : Theme.withAlpha(picker.controller.fg, Alpha.Ghost)

                            StyledText {
                                anchors.centerIn: parent
                                text: rowRoot.isIm ? rowRoot.im.label : ""
                                color: rowRoot.current ? Theme.onPrimary : picker.controller.fg
                                font.pixelSize: Math.round(labelChip.height * 0.46)
                                font.weight: Font.DemiBold
                            }

                        }

                        Image {
                            id: rowIcon

                            source: rowRoot.iconSrc
                            visible: rowRoot.iconSrc !== ""
                            width: Math.round(rowRoot.height * 0.5)
                            height: width
                            anchors.verticalCenter: parent.verticalCenter
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        // 主文字：「输入法 - 子模式名称」或者开关的 shortText
                        StyledText {
                            id: mainText

                            readonly property string label: rowRoot.isIm ? rowRoot.im.text : (rowRoot.item !== null ? rowRoot.item.text : "")

                            width: Math.max(0, rowContent.width - (labelChip.visible ? labelChip.width + rowContent.spacing : 0) - (rowIcon.visible ? rowIcon.width + rowContent.spacing : 0))
                            anchors.verticalCenter: parent.verticalCenter
                            text: label
                            elide: Text.ElideRight
                            color: rowRoot.current ? Theme.primary : picker.controller.fg
                            font.pixelSize: Math.round(picker.controller.keyH * 0.3)
                            font.weight: rowRoot.current ? Font.DemiBold : Font.Normal
                        }

                    }

                    // 有子菜单的右侧标一个箭头
                    StyledText {
                        id: arrow

                        visible: rowRoot.hasChildren
                        anchors.right: parent.right
                        anchors.rightMargin: Math.round(picker.controller.keyH * 0.12)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: Theme.withAlpha(picker.controller.fg, Alpha.Strong)
                        font.pixelSize: Math.round(picker.controller.keyH * 0.34)
                    }

                    // 涟漪：输入法行没有底色，扩散范围留一点内边距
                    DRipple {
                        id: rowRipple

                        anchors.fill: parent
                        anchors.margins: Math.round(picker.controller.gap * 0.4)
                        cornerRadius: Theme.cornerRadius
                        rippleColor: rowRoot.current ? Theme.onPrimary : Theme.primary
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        onPressed: (mouse) => {
                            return rowRipple.trigger(mouse.x, mouse.y);
                        }
                        onClicked: {
                            if (rowRoot.item !== null) {
                                // 有子菜单就翻到下一层
                                if (rowRoot.hasChildren) {
                                    picker.openSub(rowRoot.item);
                                    return ;
                                }
                                // 交给 fcitx5 执行：子菜单里点完退回上一层，顶层点完收起面板
                                picker.controller.activateStatusItem(rowRoot.item);
                                if (picker.subStack.length > 0)
                                    picker.goBack();
                                else
                                    picker.controller.imPickerOpen = false;
                                return ;
                            }
                            // 纯键盘布局直接切；拼音类输入法走 selectImMode，它会在切换生效后再校正中英文状态
                            if (rowRoot.im.keyboard)
                                picker.controller.selectIm(rowRoot.im.name);
                            else
                                picker.controller.selectImMode(rowRoot.im.name, rowRoot.im.ascii);
                            picker.controller.imPickerOpen = false;
                        }
                    }

                }

            }

        }

    }

}
