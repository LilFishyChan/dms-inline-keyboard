// Inline Keyboard 插件设置页：外观（缩放 / 透明度）、行为（避让 / 默认模式）、动作列表。
// 文案一律走 tr()，源串保持英文，译文在 translations/<locale>.json。
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "actions.js" as Actions
import qs.Common
import qs.DCommon.Widgets as DCommon
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginSettings {
    id: root

    // DMS 会在插件翻译表就绪之前预实例化设置页，文案会停在英文。
    // 用短轮询把「表就绪」变成属性变化，让绑定重算（同 KeyboardCard 里的做法）
    property int localeVersion: 0
    property int translationPollCount: 0
    // ydotoold 状态：没有它什么键都发不出去，所以摆在最上面
    property bool ydotooldUp: true
    // 设置值：SettingsRow 不自带存取，这里自己 load / save
    property int repeatInterval: 60
    // 调试 IPC（只读诊断 + 模拟点击 / 长按 / 拖动）给 scripts/acceptance.py 用，
    // 普通使用用不到，所以打开前必须过一次确认框。
    property bool debugModeOn: false
    property bool debugConfirmOpen: false
    // 可选扩展：fcitx5 桥接
    // 装了 addon 才有候选、拼音串和地球键切换；没装也能打字（按键走 ydotool）
    property bool bridgeUp: false
    // 安装命令直接摆出来，省得用户回 README 找
    readonly property string installCommands: "git clone https://github.com/LilFishyChan/fcitx5-inline-keyboard-status\n" + "cd fcitx5-inline-keyboard-status && cmake -B build -G Ninja && ninja -C build\n" + "cmake --install build --prefix ~/.local\n" + "systemctl --user restart 'app-org.fcitx.Fcitx5@autostart.service'"
    // 正在改图标的动作索引（-1 = 没在选）
    // 内置动作的 id 集合：ListSetting 直接读文件里的原始数组（不经 sanitize），
    // 老数据没有 builtin 字段，靠这张表兜底
    readonly property var builtinIds: {
        const map = {
        };
        const defaults = Actions.defaultActions();
        for (let i = 0; i < defaults.length; i++) map[defaults[i].id] = true
        return map;
    }
    // 添加 / 编辑自定义动作的表单状态（editingId 非空 = 正在改已有动作）
    property string editingId: ""
    property bool adding: false
    property string draftLabel: ""
    property string draftIcon: "label"
    property string draftCmd: ""

    function reloadSettings() {
        root.repeatInterval = root.loadValue("repeatInterval", 60);
    }

    function refreshDebugMode() {
        root.debugModeOn = PluginService.loadPluginData(root.pluginId, "debugMode", false);
    }

    function writeDebugMode(on) {
        PluginService.savePluginData(root.pluginId, "debugMode", on);
        root.debugModeOn = on;
    }

    // 动作数据由下面的 ListSetting 持有（它自带读写设置，设置页没有 pluginService 可用）。
    // 修改一律走 actions.js 的纯函数，保证和 daemon / 卡片用的是同一套规则。
    function patchAction(id, patch) {
        actionList.items = Actions.updateAction(Actions.toArray(actionList.items), id, patch);
    }

    function removeActionById(id) {
        actionList.items = Actions.removeAction(Actions.toArray(actionList.items), id).actions;
    }

    function startAdd() {
        root.editingId = "";
        root.draftLabel = "";
        root.draftIcon = "label";
        root.draftCmd = "";
        root.adding = true;
    }

    function startEdit(action) {
        if (!action || action.builtin === true || root.builtinIds[action.id] === true)
            return ;

        root.editingId = action.id;
        root.draftLabel = action.label || "";
        root.draftIcon = action.icon || "label";
        root.draftCmd = action.cmd || "";
        root.adding = true;
    }

    function confirmAdd() {
        const label = root.draftLabel.trim();
        if (label === "")
            return ;

        // 编辑模式：直接改这一条
        if (root.editingId !== "") {
            root.patchAction(root.editingId, {
                "label": label,
                "icon": root.draftIcon || "label",
                "cmd": root.draftCmd.trim()
            });
            root.adding = false;
            root.editingId = "";
            return ;
        }
        let list = Actions.toArray(actionList.items);
        // 防御：内置动作一个都不在列表里，说明数据被写空过，先补回默认表
        if (!list.some((a) => {
            return a && a.builtin === true;
        }))
            list = Actions.defaultActions().concat(list.filter((a) => {
            return a && a.builtin !== true;
        }));

        actionList.items = Actions.appendAction(list, {
            "label": label,
            "icon": root.draftIcon || "label",
            "cmd": root.draftCmd.trim()
        }).actions;
        root.adding = false;
    }

    // 缺词条时回退英文原串
    function tr(term) {
        const version = root.localeVersion; // 让调用处的绑定跟随版本重算
        if (typeof I18n === "undefined" || !I18n || !I18n.trFor)
            return term;

        return I18n.trFor("inlineKeyboard", term);
    }

    pluginId: "inlineKeyboard"
    // 只在打开设置页时探一次；Start/Enable 按钮的 onExited 里还会再探
    Component.onCompleted: {
        daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "$XDG_RUNTIME_DIR/.ydotool_socket"'];
        daemonCheck.running = true;
        bridgeCheck.running = true;
        root.reloadSettings();
        root.refreshDebugMode();
    }

    Timer {
        interval: 100
        repeat: true
        running: root.localeVersion === 0 && root.translationPollCount < 100
        onTriggered: {
            root.translationPollCount++;
            const tables = (typeof I18n !== "undefined" && I18n) ? I18n.pluginTranslations : null;
            if (tables && tables[root.pluginId])
                root.localeVersion = 1;

        }
    }

    Process {
        id: daemonCheck

        running: false
        // 同时看进程和 socket：ydotoold 停掉后 socket 文件会残留，只测 socket 会误判
        onExited: (code) => {
            return root.ydotooldUp = (code === 0);
        }
    }

    Process {
        id: daemonStart

        running: false
        command: ["systemctl", "--user", "start", "ydotool"]
        onExited: (code) => {
            daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "$XDG_RUNTIME_DIR/.ydotool_socket"'];
            daemonCheck.running = true;
        }
    }

    Process {
        id: daemonEnable

        running: false
        command: ["systemctl", "--user", "enable", "--now", "ydotool"]
        onExited: (code) => {
            daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "$XDG_RUNTIME_DIR/.ydotool_socket"'];
            daemonCheck.running = true;
        }
    }

    Process {
        id: bridgeCheck

        running: false
        // 和 daemonCheck 同理由：文件残留会误判，所以测的是 socket 本身
        command: ["sh", "-c", 'test -S "$XDG_RUNTIME_DIR/inline-keyboard.sock"']
        onExited: (code) => {
            return root.bridgeUp = (code === 0);
        }
    }

    Process {
        id: copyInstall

        running: false
        command: ["dms", "cl", "copy", root.installCommands]
    }

    // ydotoold 没跑：警告 + 两种做法（临时启动 / 设为开机自启）
    DCommon.DCard {
        width: parent.width
        visible: !root.ydotooldUp
        // DTone 只有 primary/secondary/tertiary，错误色得自己覆盖
        color: Theme.withAlpha(Theme.error, 0.12)
        border.color: Theme.withAlpha(Theme.error, 0.5)
        implicitHeight: warnColumn.implicitHeight + pad * 2

        Column {
            id: warnColumn

            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: root.tr("ydotoold is not running — the keyboard cannot type until it starts.")
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeMedium
            }

            StyledText {
                width: parent.width
                text: root.tr("Start it once below, or enable it permanently so it survives a reboot: systemctl --user enable --now ydotool")
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                spacing: Theme.spacingS

                DCommon.DButton {
                    text: root.tr("Start")
                    onClicked: daemonStart.running = true
                }

                DCommon.DButton {
                    text: root.tr("Enable at login")
                    backgroundColor: Theme.withAlpha(Theme.surfaceText, 0.12)
                    textColor: Theme.surfaceText
                    onClicked: daemonEnable.running = true
                }

            }

        }

    }

    StyledText {
        width: parent.width
        text: root.tr("Toggle it with `dms ipc call inlineKeyboard toggle`, or add the widget to your DankBar.")
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // 装了就收成一行「已连接」，没装才展开安装步骤 —— 已经把说明塞满页面了
    Column {
        width: parent.width
        spacing: Math.round(Theme.spacingS)

        StyledText {
            width: parent.width
            text: root.tr("Optional: fcitx5 bridge")
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
            topPadding: Theme.spacingL
        }

        StyledText {
            width: parent.width
            text: root.bridgeUp ? root.tr("Connected — candidates, preedit and the globe switcher are live.") : root.tr("Candidates, the pinyin preedit and the globe input-method switcher come from a small fcitx5 addon. Without it the keyboard still types (keys go through ydotool), but the candidate strip stays empty.")
            font.pixelSize: Theme.fontSizeMedium
            color: root.bridgeUp ? Theme.primary : Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            visible: !root.bridgeUp
            // height 和 visible 互相引用会成环：高度由 implicitHeight 一次算清
            implicitHeight: cmdText.implicitHeight + 28
            height: implicitHeight
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceText, 0.06)

            StyledText {
                id: cmdText

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                text: root.installCommands
                color: Theme.surfaceText
                font.family: "monospace"
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WrapAnywhere
            }

        }

        DCommon.DButton {
            visible: !root.bridgeUp
            text: root.tr("Copy install commands")
            backgroundColor: Theme.withAlpha(Theme.surfaceText, 0.12)
            textColor: Theme.surfaceText
            onClicked: copyInstall.running = true
        }

    }

    SettingsSection {
        text: root.tr("Appearance")
    }

    SettingsCardGroup {
        SettingsCard {
            StyledText {
                width: parent.width
                text: root.tr("Key repeat interval")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: root.tr("Delay between repeated keystrokes while a key is held down.")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.Wrap
            }

            DCommon.DSlider {
                width: parent.width
                minimum: 20
                maximum: 200
                step: 10
                value: root.repeatInterval
                unit: " ms"
                onValueChanged: {
                    if (root.repeatInterval !== value) {
                        root.repeatInterval = value;
                        root.saveValue("repeatInterval", value);
                    }
                }
            }

        }

    }

    SettingsSection {
        text: root.tr("Behaviour")
    }

    SettingsCardGroup {
        SettingsCard {
            ToggleSetting {
                settingKey: "avoidWindows"
                label: root.tr("Avoid windows when docked")
                description: root.tr("Shrink other windows so the keyboard does not cover them.")
                defaultValue: true
            }

        }

        SettingsCard {
            ToggleSetting {
                settingKey: "alwaysShowPreedit"
                label: root.tr("Always show the preedit in the keyboard")
                description: root.tr("Some apps draw the pinyin string inside the text field themselves; turn this on to also show it in the keyboard.")
                defaultValue: false
            }

        }

        SettingsCard {
            ToggleSetting {
                settingKey: "defaultFloating"
                label: root.tr("Use the floating keyboard by default")
                description: root.tr("Off opens the docked keyboard.")
                defaultValue: false
            }

        }

        SettingsCard {
            SelectionSetting {
                settingKey: "modifierMode"
                label: root.tr("Modifier tap behaviour")
                description: root.tr("How Shift / Ctrl / Alt / Win respond to touch. Caps Lock always toggles.")
                defaultValue: "doubleTapLock"
                options: [{
                    "label": root.tr("Active while held"),
                    "value": "noLock"
                }, {
                    "label": root.tr("Tap to activate; any key clears it"),
                    "value": "toggle"
                }, {
                    "label": root.tr("Tap to lock (tap again to unlock)"),
                    "value": "tapLock"
                }, {
                    "label": root.tr("Tap to toggle, double-tap to lock"),
                    "value": "doubleTapLock"
                }]
            }

        }

        // 特殊键的表现形式。三个选项对应 layouts/special-keys.js 的 STYLES；
        // 「完整」形态下过长的文字由 Key.qml 的 Text.HorizontalFit 自动缩字号。
        SettingsCard {
            SelectionSetting {
                settingKey: "specialKeyStyle"
                label: root.tr("Special key labels")
                description: root.tr("How Backspace, Enter, Shift, Ctrl, Alt and Tab are drawn. Full names shrink to fit the key.")
                defaultValue: "full"
                options: [{
                    "label": root.tr("Icon"),
                    "value": "icon"
                }, {
                    "label": root.tr("Short"),
                    "value": "short"
                }, {
                    "label": root.tr("Full name"),
                    "value": "full"
                }]
            }

        }

    }

    SettingsSection {
        text: root.tr("Win key")
    }

    SettingsCardGroup {
        // Win 键实际发的是 Super_L，叫 Win 只对 Windows 用户成立，默认显示 Mod
        SettingsCard {
            SelectionSetting {
                id: winLookSetting

                settingKey: "winKeyStyle"
                label: root.tr("Win key label")
                description: root.tr("This key sends Super. Show it as text or an icon.")
                defaultValue: "mod"
                options: [{
                    "label": "Mod",
                    "value": "mod"
                }, {
                    "label": "Super",
                    "value": "super"
                }, {
                    "label": "⌘",
                    "value": "system"
                }, {
                    "label": root.tr("Custom icon"),
                    "value": "custom"
                }]
            }

        }

        // 自定义图标：DIconPicker 选 Material 图标，或者直接填图片路径
        SettingsCard {
            visible: winLookSetting.value === "custom"

            // 和动作编辑表单里的图标行同一种布局：左侧 48px 标签，右侧选择器 + 路径
            Row {
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    width: 48
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.tr("Icon")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                DCommon.DIconPicker {
                    id: winIconPicker2

                    width: Math.min(160, parent.width * 0.3)
                    currentIcon: String(winIconSetting.value || "")
                    onIconSelected: (iconName, iconType) => {
                        winIconSetting.value = iconName;
                        root.saveValue("winKeyCustomIcon", iconName);
                    }
                }

                DCommon.DTextField {
                    width: parent.width - 48 - winIconPicker2.width - parent.spacing * 2
                    placeholderText: root.tr("svg/png path")
                    text: String(winIconSetting.value || "").indexOf("/") >= 0 ? winIconSetting.value : ""
                    onTextEdited: {
                        const v = text.trim();
                        winIconSetting.value = v;
                        root.saveValue("winKeyCustomIcon", v);
                    }
                }

            }

        }

    }

    // 值的持有者（设置项的读写都靠它），界面由上面那块负责
    StringSetting {
        id: winIconSetting

        visible: false
        settingKey: "winKeyCustomIcon"
        label: root.tr("Custom icon")
        description: ""
        defaultValue: ""
    }

    SettingsSection {
        text: root.tr("Actions")
    }

    SettingsCardGroup {
        SettingsCard {
            // 用 ListSetting 而不是自己读写 pluginData：设置页没有 pluginService 可用，
            // ListSetting 自带存取，并提供 items / addItem / removeItem。
            ToggleSetting {
                settingKey: "escSwap"
                label: root.tr("Esc on the top-left key")
                description: root.tr("Swap the \`~ key with Esc. Fn layer keeps the other one.")
                defaultValue: false
            }

            // 动作表单：编辑时内联在那一行下面，新增时排在列表底部，两处共用这一份定义
            Component {
                id: actionFormComponent

                Column {
                    id: actionForm

                    function loadDraft() {
                        labelField.text = root.draftLabel;
                        cmdField.text = root.draftCmd;
                    }

                    width: parent.width
                    spacing: Math.round(Theme.spacingS)

                    // TextInput.text 不能用绑定（用户一打字绑定就断），所以由事件驱动重填
                    Connections {
                        function onEditingIdChanged() {
                            actionForm.loadDraft();
                        }

                        function onAddingChanged() {
                            if (root.adding)
                                actionForm.loadDraft();

                        }

                        function onDraftLabelChanged() {
                            if (!labelField.activeFocus)
                                labelField.text = root.draftLabel;

                        }

                        function onDraftCmdChanged() {
                            if (!cmdField.activeFocus)
                                cmdField.text = root.draftCmd;

                        }

                        target: root
                    }

                    StyledText {
                        width: parent.width
                        text: root.editingId !== "" ? root.tr("Edit action") : root.tr("New action")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    Row {
                        width: parent.width
                        spacing: Math.round(Theme.spacingM)

                        StyledText {
                            width: 48
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.tr("Name")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        DCommon.DTextField {
                            id: labelField

                            width: parent.width - 48 - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            onTextEdited: root.draftLabel = text
                        }

                    }

                    Row {
                        width: parent.width
                        spacing: Math.round(Theme.spacingS)

                        StyledText {
                            width: 48
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.tr("Icon")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        DCommon.DIconPicker {
                            id: iconField

                            width: Math.min(160, parent.width * 0.3)
                            anchors.verticalCenter: parent.verticalCenter
                            currentIcon: root.draftIcon
                            onIconSelected: (iconName, iconType) => {
                                root.draftIcon = iconName;
                            }
                        }

                        DCommon.DTextField {
                            width: parent.width - 48 - iconField.width - parent.spacing * 2
                            anchors.verticalCenter: parent.verticalCenter
                            placeholderText: root.tr("svg/png path")
                            text: root.draftIcon.indexOf("/") >= 0 ? root.draftIcon : ""
                            onTextEdited: {
                                const v = text.trim();
                                root.draftIcon = v !== "" ? v : "label";
                            }
                        }

                    }

                    Row {
                        width: parent.width
                        spacing: Math.round(Theme.spacingM)

                        StyledText {
                            width: 48
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.tr("Command")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        DCommon.DTextField {
                            id: cmdField

                            width: parent.width - 48 - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            placeholderText: root.tr("e.g. grim -g \"$(slurp)\"")
                            onTextEdited: root.draftCmd = text
                        }

                    }

                    Row {
                        spacing: Math.round(Theme.spacingS)

                        DCommon.DButton {
                            text: root.editingId !== "" ? root.tr("Save") : root.tr("Add")
                            onClicked: root.confirmAdd()
                        }

                        DCommon.DButton {
                            text: root.tr("Cancel")
                            backgroundColor: Theme.withAlpha(Theme.surfaceText, 0.12)
                            textColor: Theme.surfaceText
                            onClicked: root.adding = false
                        }

                    }

                }

            }

        }

        SettingsCard {
            ListSetting {
                id: actionList

                settingKey: "actions"
                label: root.tr("Actions")
                description: root.tr("Built-in actions can only be hidden; the ones you add can be removed. Tap an icon to change it.")
                defaultValue: Actions.defaultActions()

                delegate: Component {
                    Column {
                        required property int index
                        required property var modelData
                        readonly property bool isHidden: modelData.hidden === true
                        readonly property bool isBuiltin: modelData.builtin === true || root.builtinIds[modelData.id] === true

                        width: parent.width
                        // 和设置项一致：行与行之间留 2px，首尾行由 DListRow 自己圆角
                        spacing: 2

                        DCommon.DListRow {
                            width: parent.width
                            // 行高按内容算；firstInGroup/lastInGroup 给出分组的圆角
                            implicitHeight: Math.max(Theme.listItemHeight, actionRow.implicitHeight + Theme.spacingM * 2)
                            firstInGroup: index === 0
                            lastInGroup: index === actionList.items.length - 1

                            Row {
                                id: actionRow

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.spacingL
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingM

                                // 非编辑态只展示图标，改图标走那一行的编辑
                                ActionIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    action: modelData
                                    size: 20
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    width: parent.width - 20 - actionButtons.implicitWidth - parent.spacing * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: isHidden ? Theme.withAlpha(Theme.surfaceText, 0.55) : Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                Row {
                                    id: actionButtons

                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS

                                    // 隐藏态：底色 primary，图标用 onPrimary 保证对比度
                                    DCommon.DActionButton {
                                        iconName: isHidden ? "visibility_off" : "visibility"
                                        backgroundColor: isHidden ? Theme.primary : "transparent"
                                        iconColor: isHidden ? Theme.onPrimary : Theme.withAlpha(Theme.surfaceText, 0.65)
                                        tooltipText: isHidden ? root.tr("Show") : root.tr("Hide")
                                        onClicked: root.patchAction(modelData.id, {
                                            "hidden": !isHidden
                                        })
                                    }

                                    DCommon.DActionButton {
                                        visible: !isBuiltin
                                        iconName: "edit"
                                        iconColor: Theme.withAlpha(Theme.surfaceText, 0.75)
                                        tooltipText: root.tr("Edit")
                                        onClicked: root.startEdit(modelData)
                                    }

                                    DCommon.DActionButton {
                                        visible: !isBuiltin
                                        iconName: "delete"
                                        iconColor: Theme.withAlpha(Theme.error, 0.85)
                                        tooltipText: root.tr("Remove")
                                        onClicked: root.removeActionById(modelData.id)
                                    }

                                }

                            }

                            // 编辑这一行时，表单就展开在它下面
                            Loader {
                                id: inlineForm

                                width: parent.width
                                active: root.editingId === modelData.id
                                // 卸载后 implicitHeight 会留着上次的高度，显式收成 0
                                height: active ? implicitHeight : 0
                                sourceComponent: actionFormComponent
                                onLoaded: item.loadDraft()
                            }

                            // 行底色比整块卡片高一档，两者要能分开
                            background: Rectangle {
                                color: isHidden ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                border.width: Theme.layerOutlineWidth
                                border.color: Theme.outlineMedium
                                topLeftRadius: parent.firstInGroup ? Theme.cornerRadiusM : 2
                                topRightRadius: topLeftRadius
                                bottomLeftRadius: parent.lastInGroup ? Theme.cornerRadiusM : 2
                                bottomRightRadius: bottomLeftRadius
                            }

                        }

                    }

                }

            }

            // 新增动作：表单排在列表底部
            Loader {
                id: bottomForm

                width: parent.width
                active: root.adding && root.editingId === ""
                height: active ? implicitHeight : 0
                sourceComponent: actionFormComponent
                onLoaded: item.loadDraft()
            }

            DCommon.DButton {
                width: parent.width
                visible: !root.adding
                text: root.tr("Add a custom action")
                iconName: "add"
                backgroundColor: Theme.withAlpha(Theme.primary, 0.08)
                textColor: Theme.primary
                onClicked: root.startAdd()
            }

        }

    }

    SettingsSection {
        text: root.tr("Debugging")
    }

    SettingsCardGroup {
        SettingsCard {
            // 调试 IPC：只读诊断 + 模拟操作（点击 / 长按 / 拖动），给 scripts/acceptance.py 用。
            // 开关走受控 DToggle：点开只弹确认框，确认后才落盘。
            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width - debugToggle.width - Theme.spacingM
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        text: root.tr("Debug mode")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: root.tr("Exposes the IPC that scripts/acceptance.py drives. Normal use does not need it.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                    }

                }

                DCommon.DToggle {
                    id: debugToggle

                    anchors.verticalCenter: parent.verticalCenter
                    hideText: true
                    text: root.tr("Debug mode")
                    checked: root.debugModeOn
                    onToggled: (value) => {
                        if (value)
                            root.debugConfirmOpen = true;
                        else
                            root.writeDebugMode(false);
                    }
                }

            }

        }

    }

    // 确认框：embedded 默认 true 会把整块排进设置页列表，浮起必须显式关掉
    DCommon.DDialog {
        id: debugConfirm

        // embedded: false 会浮起，但关着的时候仍占一行高度 → 用 visible 收掉
        embedded: false
        popout: true
        visible: root.debugConfirmOpen
        opened: root.debugConfirmOpen
        title: root.tr("Turn on debug mode?")
        supportingText: root.tr("Debug mode loads the plugin's debug IPC so scripts/acceptance.py can drive it: read-only diagnostics, geometry readout, and simulated taps on keys, candidates, actions and the floating toggle.\n\nNormal use does not need it. Turn it off again when you are done testing.")
        maximumWidth: 420
        onRejected: root.debugConfirmOpen = false
        actions: [
            DCommon.DButton {
                text: root.tr("Cancel")
                backgroundColor: Theme.withAlpha(Theme.surfaceText, 0.12)
                textColor: Theme.surfaceText
                onClicked: root.debugConfirmOpen = false
            },
            DCommon.DButton {
                text: root.tr("Enable")
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: {
                    root.writeDebugMode(true);
                    root.debugConfirmOpen = false;
                }
            }
        ]
    }

}
