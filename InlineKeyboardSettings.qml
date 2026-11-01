// Inline Keyboard 插件设置页：外观（缩放 / 透明度）、行为（避让 / 默认模式）、动作列表。
// 文案一律走 tr()，源串保持英文，译文在 translations/<locale>.json。
import QtQuick
import Quickshell
import Quickshell.Io
import "actions.js" as Actions
import "alpha.js" as Alpha
import qs.Common
import qs.DCommon.Widgets as DCommon
import qs.Modules.Plugins
import qs.Modals.Common
import qs.Services
import qs.Widgets

PluginSettings {
    id: root

    // ydotoold 状态：没有它什么键都发不出去，所以摆在最上面
    property bool ydotooldUp: true
    // 标准设置组件不自带存取，这里自己 load / save
    property int repeatInterval: 60

    // 调试 IPC（只读诊断 + 模拟点击 / 长按 / 拖动）给 scripts/acceptance.py 用，普通使用用不到，所以打开前必须过一次确认框。
    property bool debugModeOn: false
    property bool debugConfirmOpen: false
    // 可选扩展：fcitx5 桥接
    // 装了 addon 才有候选、拼音串和地球键切换；没装也能打字（按键走 ydotool）
    property bool bridgeUp: false
    // 安装命令直接摆出来，省得用户回 README 找
    readonly property string installCommands: "git clone https://github.com/LilFishyChan/fcitx5-inline-keyboard-status\n" + "cd fcitx5-inline-keyboard-status && cmake -B build -G Ninja && ninja -C build\n" + "cmake --install build --prefix ~/.local\n" + "systemctl --user restart 'app-org.fcitx.Fcitx5@autostart.service'"
    // 正在改图标的动作索引（-1 = 没在选）
    // 内置动作的 id 集合：ListSetting 直接读文件里的原始数组（不经 sanitize），老数据没有 builtin 字段，靠这张表兜底
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

    // 自定义图标的当前值，读写都走 root 的 loadValue/saveValue
    property string winIconValue: root.loadValue("winKeyCustomIcon", "")

    function setWinIcon(v) {
        root.winIconValue = v;
        root.saveValue("winKeyCustomIcon", v);
    }

    function refreshDebugMode() {
        root.debugModeOn = root.loadValue("debugMode", false);
    }

    function writeDebugMode(on) {
        root.saveValue("debugMode", on);
        root.debugModeOn = on;
    }

    // 动作数据由下面的 ListSetting 持有（它自带读写设置，设置页没有 pluginService 可用）。
    // 修改一律走 actions.js 的纯函数，保证和 daemon / 卡片用的是同一套规则。
    function patchAction(id, patch) {
        actionList.items = Actions.updateAction(Actions.toArray(actionList.items), id, patch);
    }

    function removeActionById(id) {
        actionList.items = Actions.removeAction(Actions.toArray(actionList.items), id).actions;
        // 删掉的正是正在编辑的那条时，表单也要跟着收
        if (root.editingId === id)
            root.cancelForm();
    }

    // 收起表单：editingId 决定编辑态那一行是否展开，只清 adding 是不够的
    function cancelForm() {
        root.adding = false;
        root.editingId = "";
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

    pluginId: "inlineKeyboard"
    // 宿主按 "popoutService" in item 判断是否注入，不声明就永远拿不到
    property var popoutService: null

    // DMS 注入的 pluginService 上只有 availablePlugins，没有 load/savePluginData，直接走单例
    function loadValue(key, def) {
        return PluginService.loadPluginData(root.pluginId, key, def);
    }

    function saveValue(key, val) {
        // 各设置组件初始化时都会带着默认值发一次变化，那一次不能写盘
        if (!root.settingsReady)
            return ;

        PluginService.savePluginData(root.pluginId, key, val);
    }
    // 手写下拉用：DDropdown 只认显示文本，值要自己映射
    readonly property var specialStyleValues: ["icon", "short", "full"]
    // 下面的 label 表在初始化时求值，那一刻 I18n 单例可能还没就绪
    function tr(term) {
        if (typeof I18n === "undefined" || !I18n || typeof I18n.trFor !== "function")
            return term;

        return I18n.trFor("inlineKeyboard", term);
    }

    readonly property var specialStyleLabels: [I18n.trFor("inlineKeyboard", "Icon"), I18n.trFor("inlineKeyboard", "Short"), I18n.trFor("inlineKeyboard", "Full name")]
    // DDropdown 初始化时也会发一次 valueChanged（带默认值），这时不能写盘
    property bool settingsReady: false
    // 只在打开设置页时探一次；Start/Enable 按钮的 onExited 里还会再探
    Component.onCompleted: {
        daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "${YDOTOOL_SOCKET:-$XDG_RUNTIME_DIR/.ydotool_socket}"'];
        daemonCheck.running = true;
        Qt.callLater(function() {
            root.settingsReady = true;
        });

        bridgeCheck.running = true;
        root.reloadSettings();
        root.refreshDebugMode();
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
            if (code !== 0)
                ToastService.showError(I18n.trFor("inlineKeyboard", "Could not start ydotoold"));
            daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "${YDOTOOL_SOCKET:-$XDG_RUNTIME_DIR/.ydotool_socket}"'];
            daemonCheck.running = true;
        }
    }

    Process {
        id: daemonEnable

        running: false
        command: ["systemctl", "--user", "enable", "--now", "ydotool"]
        onExited: (code) => {
            if (code !== 0)
                ToastService.showError(I18n.trFor("inlineKeyboard", "Could not enable ydotoold"));
            daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "${YDOTOOL_SOCKET:-$XDG_RUNTIME_DIR/.ydotool_socket}"'];
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
        color: Theme.withAlpha(Theme.error, Alpha.Focus)
        border.color: Theme.withAlpha(Theme.error, Alpha.Half)
        implicitHeight: warnColumn.implicitHeight + pad * 2

        Column {
            id: warnColumn

            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: I18n.trFor("inlineKeyboard", "ydotoold is not running — the keyboard cannot type until it starts.")
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeMedium
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("inlineKeyboard", "Start it once below, or enable it permanently so it survives a reboot: systemctl --user enable --now ydotool")
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                spacing: Theme.spacingS

                DCommon.DButton {
                    text: I18n.trFor("inlineKeyboard", "Start")
                    onClicked: daemonStart.running = true
                }

                DCommon.DButton {
                    text: I18n.trFor("inlineKeyboard", "Enable at login")
                    backgroundColor: Theme.withAlpha(Theme.surfaceText, Alpha.Focus)
                    textColor: Theme.surfaceText
                    onClicked: daemonEnable.running = true
                }

            }

        }

    }

    StyledText {
        width: parent.width
        text: I18n.trFor("inlineKeyboard", "Toggle it with `dms ipc call inlineKeyboard toggle`, or add the widget to your DankBar.")
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
            text: I18n.trFor("inlineKeyboard", "Optional: fcitx5 bridge")
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
            topPadding: Theme.spacingL
        }

        StyledText {
            width: parent.width
            text: root.bridgeUp ? I18n.trFor("inlineKeyboard", "Connected — candidates, preedit and the globe switcher are live.") : I18n.trFor("inlineKeyboard", "Candidates, the pinyin preedit and the globe input-method switcher come from a small fcitx5 addon. Without it the keyboard still types (keys go through ydotool), but the candidate strip stays empty.")
            font.pixelSize: Theme.fontSizeMedium
            color: root.bridgeUp ? Theme.primary : Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            visible: !root.bridgeUp
            // height 和 visible 互相引用会成环：高度由 implicitHeight 一次算清
            implicitHeight: cmdText.implicitHeight + Theme.spacingL * 2
            height: implicitHeight
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceText, Alpha.Whisper)

            StyledText {
                id: cmdText

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingL
                text: root.installCommands
                color: Theme.surfaceText
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WrapAnywhere
            }

        }

        DCommon.DButton {
            visible: !root.bridgeUp
            text: I18n.trFor("inlineKeyboard", "Copy install commands")
            backgroundColor: Theme.withAlpha(Theme.surfaceText, Alpha.Focus)
            textColor: Theme.surfaceText
            onClicked: copyInstall.running = true
        }

    }

    SettingsSection {
        text: I18n.trFor("inlineKeyboard", "Appearance")
    }

    SettingsCardGroup {
        SettingsCard {
            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width - tooltipToggle.width - Theme.spacingM
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        text: I18n.trFor("inlineKeyboard", "Button tooltips")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.trFor("inlineKeyboard", "Show hints when hovering over keyboard buttons.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                    }

                }

                DCommon.DToggle {
                    id: tooltipToggle

                    anchors.verticalCenter: parent.verticalCenter
                    hideText: true
                    text: I18n.trFor("inlineKeyboard", "Button tooltips")
                    checked: root.loadValue("tooltips", true)
                    onToggled: (value) => root.saveValue("tooltips", value)
                }

            }

        }

        SettingsCard {
            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width - autoShowToggle.width - Theme.spacingM
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        text: I18n.trFor("inlineKeyboard", "Auto show")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.trFor("inlineKeyboard", "Show the keyboard when a text field gets focus.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                    }

                }

                DCommon.DToggle {
                    id: autoShowToggle

                    anchors.verticalCenter: parent.verticalCenter
                    hideText: true
                    text: I18n.trFor("inlineKeyboard", "Auto show")
                    checked: root.loadValue("autoShow", false)
                    onToggled: (value) => root.saveValue("autoShow", value)
                }

            }

        }

        SettingsCard {
            StyledText {
                width: parent.width
                text: I18n.trFor("inlineKeyboard", "Key repeat interval")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("inlineKeyboard", "Delay between repeated keystrokes while a key is held down.")
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
        text: I18n.trFor("inlineKeyboard", "Behaviour")
    }

    SettingsCardGroup {
        SettingsCard {
            ToggleSetting {
                settingKey: "avoidWindows"
                label: I18n.trFor("inlineKeyboard", "Avoid windows when docked")
                description: I18n.trFor("inlineKeyboard", "Shrink other windows so the keyboard does not cover them.")
                defaultValue: true
            }

        }

        SettingsCard {
            ToggleSetting {
                settingKey: "alwaysShowPreedit"
                label: I18n.trFor("inlineKeyboard", "Always show the preedit in the keyboard")
                description: I18n.trFor("inlineKeyboard", "Some apps draw the pinyin string inside the text field themselves; turn this on to also show it in the keyboard.")
                defaultValue: false
            }

        }

        SettingsCard {
            ToggleSetting {
                settingKey: "defaultFloating"
                label: I18n.trFor("inlineKeyboard", "Use the floating keyboard by default")
                description: I18n.trFor("inlineKeyboard", "Off opens the docked keyboard.")
                defaultValue: false
            }

        }

        SettingsCard {
            id: modifierModeCard

            // 同样不用 SelectionSetting：它初始化时会把 defaultValue 写回文件
            readonly property var modifierModeValues: ["noLock", "toggle", "tapLock", "doubleTapLock"]
            readonly property var modifierModeLabels: [I18n.trFor("inlineKeyboard", "Active while held"), I18n.trFor("inlineKeyboard", "Tap to activate; any key clears it"), I18n.trFor("inlineKeyboard", "Tap to lock (tap again to unlock)"), I18n.trFor("inlineKeyboard", "Tap to toggle, double-tap to lock")]

            StyledText {
                width: parent.width
                text: I18n.trFor("inlineKeyboard", "Modifier tap behaviour")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("inlineKeyboard", "How Shift / Ctrl / Alt / Win respond to touch. Caps Lock always toggles.")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.Wrap
            }

            DCommon.DDropdown {
                width: parent.width
                options: modifierModeCard.modifierModeLabels
                currentValue: modifierModeCard.modifierModeLabels[Math.max(0, modifierModeCard.modifierModeValues.indexOf(root.loadValue("modifierMode", "doubleTapLock")))]

                onValueChanged: v => {
                    if (!root.settingsReady)
                        return ;

                    const i = modifierModeCard.modifierModeLabels.indexOf(v);
                    if (i >= 0)
                        root.saveValue("modifierMode", modifierModeCard.modifierModeValues[i]);

                }
            }

        }

        // 特殊键的表现形式。三个选项对应 layouts/specialKeys.js 的 STYLES；
        // 「完整」形态下过长的文字由 Key.qml 的 Text.HorizontalFit 自动缩字号。
        SettingsCard {
            Column {
                spacing: Theme.spacingS
                width: parent.width

                StyledText {
                    width: parent.width
                    text: I18n.trFor("inlineKeyboard", "Special key labels")
                    font.pixelSize: Theme.fontSizeMedium
                }

                StyledText {
                    width: parent.width
                    text: I18n.trFor("inlineKeyboard", "How Backspace, Enter, Shift, Ctrl, Alt and Tab are drawn. Full names shrink to fit the key.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.Wrap
                }

                // 不用 SelectionSetting：它初始化时会把 defaultValue 写回文件（DDropdown 的 valueChanged 回环）
                DCommon.DDropdown {
                    width: parent.width
                    options: root.specialStyleLabels
                    currentValue: root.specialStyleLabels[Math.max(0, root.specialStyleValues.indexOf(root.loadValue("specialKeyStyle", "full")))]

                    onValueChanged: v => {
                        if (!root.settingsReady)
                            return ;

                        const i = root.specialStyleLabels.indexOf(v);
                        if (i >= 0)
                            root.saveValue("specialKeyStyle", root.specialStyleValues[i]);
                    }
                }
            }
        }

    }

    SettingsSection {
        text: I18n.trFor("inlineKeyboard", "Win key")
    }

    SettingsCardGroup {
        // Win 键实际发的是 Super_L，叫 Win 只对 Windows 用户成立，默认显示 Mod
        SettingsCard {
            id: winLookCard

            // 不用 SelectionSetting：它初始化时会把 defaultValue 写回文件（DDropdown 的 valueChanged 回环），
            // 表现就是每次打开设置页都回到默认值
            readonly property var winLookValues: ["mod", "super", "system", "custom"]
            readonly property var winLookLabels: ["Mod", "Super", "⌘", I18n.trFor("inlineKeyboard", "Custom icon")]

            StyledText {
                width: parent.width
                text: I18n.trFor("inlineKeyboard", "Win key label")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("inlineKeyboard", "This key sends Super. Show it as text or an icon.")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.Wrap
            }

            DCommon.DDropdown {
                width: parent.width
                options: winLookCard.winLookLabels
                currentValue: winLookCard.winLookLabels[Math.max(0, winLookCard.winLookValues.indexOf(root.loadValue("winKeyStyle", "mod")))]

                onValueChanged: v => {
                    if (!root.settingsReady)
                        return ;

                    const i = winLookCard.winLookLabels.indexOf(v);
                    if (i >= 0)
                        root.saveValue("winKeyStyle", winLookCard.winLookValues[i]);

                }
            }

        }

        // 自定义图标：DIconPicker 选 Material 图标，或者直接填图片路径
        SettingsCard {
            visible: root.loadValue("winKeyStyle", "mod") === "custom"

            // 和动作编辑表单里的图标行同一种布局：左侧 48px 标签，右侧选择器 + 路径
            Row {
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    width: Theme.spacingXL * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.trFor("inlineKeyboard", "Icon")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                DCommon.DIconPicker {
                    id: winIconPicker2

                    width: Math.min(Theme.iconSizeLarge * 5, parent.width * 0.3)
                    currentIcon: root.winIconValue
                    onIconSelected: (iconName, iconType) => root.setWinIcon(iconName)
                }

                DCommon.DTextField {
                    width: parent.width - Theme.spacingXL * 2 - winIconPicker2.width - parent.spacing * 2
                    placeholderText: I18n.trFor("inlineKeyboard", "svg/png path")
                    text: root.winIconValue.indexOf("/") >= 0 ? root.winIconValue : ""
                    onTextEdited: root.setWinIcon(text.trim())
                }

            }

        }

    }

    SettingsSection {
        text: I18n.trFor("inlineKeyboard", "Actions")
    }

    SettingsCardGroup {
        SettingsCard {
            // 用 ListSetting 而不是自己读写 pluginData：设置页没有 pluginService 可用，ListSetting 自带存取，并提供 items / addItem / removeItem。
            ToggleSetting {
                settingKey: "escSwap"
                label: I18n.trFor("inlineKeyboard", "Esc on the top-left key")
                description: I18n.trFor("inlineKeyboard", "Swap the `~ key with Esc. Fn layer keeps the other one.")
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
                        text: root.editingId !== "" ? I18n.trFor("inlineKeyboard", "Edit action") : I18n.trFor("inlineKeyboard", "New action")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    Row {
                        width: parent.width
                        spacing: Math.round(Theme.spacingM)

                        StyledText {
                            width: Theme.spacingXL * 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.trFor("inlineKeyboard", "Name")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        DCommon.DTextField {
                            id: labelField

                            width: parent.width - Theme.spacingXL * 2 - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            onTextEdited: root.draftLabel = text
                        }

                    }

                    Row {
                        width: parent.width
                        spacing: Math.round(Theme.spacingS)

                        StyledText {
                            width: Theme.spacingXL * 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.trFor("inlineKeyboard", "Icon")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        DCommon.DIconPicker {
                            id: iconField

                            width: Math.min(Theme.iconSizeLarge * 5, parent.width * 0.3)
                            anchors.verticalCenter: parent.verticalCenter
                            currentIcon: root.draftIcon
                            onIconSelected: (iconName, iconType) => {
                                root.draftIcon = iconName;
                            }
                        }

                        DCommon.DTextField {
                            width: parent.width - Theme.spacingXL * 2 - iconField.width - parent.spacing * 2
                            anchors.verticalCenter: parent.verticalCenter
                            placeholderText: I18n.trFor("inlineKeyboard", "svg/png path")
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
                            width: Theme.spacingXL * 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.trFor("inlineKeyboard", "Command")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        DCommon.DTextField {
                            id: cmdField

                            width: parent.width - Theme.spacingXL * 2 - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            placeholderText: I18n.trFor("inlineKeyboard", "e.g. grim -g \"$(slurp)\"")
                            onTextEdited: root.draftCmd = text
                        }

                    }

                    Row {
                        spacing: Math.round(Theme.spacingS)

                        DCommon.DButton {
                            text: root.editingId !== "" ? I18n.trFor("inlineKeyboard", "Save") : I18n.trFor("inlineKeyboard", "Add")
                            onClicked: root.confirmAdd()
                        }

                        DCommon.DButton {
                            text: I18n.trFor("inlineKeyboard", "Cancel")
                            backgroundColor: Theme.withAlpha(Theme.surfaceText, Alpha.Focus)
                            textColor: Theme.surfaceText
                            onClicked: root.cancelForm()
                        }

                    }

                }

            }

        }

        SettingsCard {
            ListSetting {
                id: actionList

                settingKey: "actions"
                label: I18n.trFor("inlineKeyboard", "Actions")
                description: I18n.trFor("inlineKeyboard", "Built-in actions can only be hidden; the ones you add can be removed. Tap an icon to change it.")
                defaultValue: Actions.defaultActions()

                delegate: Component {
                    Column {
                        required property int index
                        required property var modelData
                        readonly property bool isHidden: modelData.hidden === true
                        readonly property bool isBuiltin: modelData.builtin === true || root.builtinIds[modelData.id] === true

                        width: parent.width
                        // 和设置项一致：行与行之间留 2px，首尾行由 DListRow 自己圆角
                        spacing: Theme.groupedListGap

                        DCommon.DListRow {
                            width: parent.width
                            // 行高要把展开的表单算进去，否则表单会压到下一行上
                            implicitHeight: Math.max(Theme.listItemHeight, actionRow.implicitHeight + Theme.spacingM * 2) + (inlineForm.active ? inlineForm.height + Theme.spacingS : 0)
                            firstInGroup: index === 0
                            lastInGroup: index === actionList.items.length - 1

                            Row {
                                id: actionRow

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.spacingL
                                anchors.rightMargin: Theme.spacingM
                                anchors.top: parent.top
                                anchors.topMargin: Theme.spacingM
                                spacing: Theme.spacingM

                                // 非编辑态只展示图标，改图标走那一行的编辑
                                ActionIcon {
                                    id: actionIcon

                                    anchors.verticalCenter: parent.verticalCenter
                                    action: modelData
                                    size: Theme.iconSizeMedium
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    width: parent.width - actionIcon.width - actionButtons.implicitWidth - parent.spacing * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.tr(modelData.label)
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: isHidden ? Theme.withAlpha(Theme.surfaceText, Alpha.Muted) : Theme.surfaceText
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
                                        iconColor: isHidden ? Theme.onPrimary : Theme.withAlpha(Theme.surfaceText, Alpha.Medium)
                                        tooltipText: isHidden ? I18n.trFor("inlineKeyboard", "Show") : I18n.trFor("inlineKeyboard", "Hide")
                                        onClicked: root.patchAction(modelData.id, {
                                            "hidden": !isHidden
                                        })
                                    }

                                    DCommon.DActionButton {
                                        visible: !isBuiltin
                                        iconName: "edit"
                                        iconColor: Theme.withAlpha(Theme.surfaceText, Alpha.High)
                                        tooltipText: I18n.trFor("inlineKeyboard", "Edit")
                                        onClicked: root.startEdit(modelData)
                                    }

                                    DCommon.DActionButton {
                                        visible: !isBuiltin
                                        iconName: "delete"
                                        iconColor: Theme.withAlpha(Theme.error, Alpha.Bright)
                                        tooltipText: I18n.trFor("inlineKeyboard", "Remove")
                                        onClicked: root.removeActionById(modelData.id)
                                    }

                                }

                            }

                            // 编辑这一行时，表单就展开在它下面
                            Loader {
                                id: inlineForm

                                // 不给锚点会叠在行的左上角
                                anchors.top: actionRow.bottom
                                anchors.topMargin: Theme.spacingS
                                width: parent.width
                                active: root.editingId === modelData.id
                                // 卸载后 implicitHeight 会留着上次的高度，显式收成 0
                                height: active ? implicitHeight : 0
                                sourceComponent: actionFormComponent
                                onLoaded: item.loadDraft()
                            }

                            // 行底色比整块卡片高一档，两者要能分开
                            background: Rectangle {
                                color: isHidden ? Theme.chipSurfaceNested : Theme.chipSurface
                                border.width: Theme.layerOutlineWidth
                                border.color: Theme.outlineMedium
                                topLeftRadius: parent.firstInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                                topRightRadius: topLeftRadius
                                bottomLeftRadius: parent.lastInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
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
                text: I18n.trFor("inlineKeyboard", "Add a custom action")
                iconName: "add"
                backgroundColor: Theme.withAlpha(Theme.primary, Alpha.Ghost)
                textColor: Theme.primary
                onClicked: root.startAdd()
            }

        }

    }

    SettingsSection {
        text: I18n.trFor("inlineKeyboard", "Debugging")
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
                        text: I18n.trFor("inlineKeyboard", "Debug mode")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.trFor("inlineKeyboard", "Exposes the IPC that scripts/acceptance.py drives. Normal use does not need it.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                    }

                }

                DCommon.DToggle {
                    id: debugToggle

                    anchors.verticalCenter: parent.verticalCenter
                    hideText: true
                    text: I18n.trFor("inlineKeyboard", "Debug mode")
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

    // 确认框：DDialog 直接放在设置页里只会占列表一行，必须包进独立的 DModal
    DModal {
        id: debugConfirm

        modalWidth: Math.min(Theme.dialogMaxWidth, screenWidth - Theme.spacingXL * 2)
        modalHeight: Math.min(screenHeight * 0.7, 360)
        onBackgroundClicked: root.debugConfirmOpen = false

        content: Component {
            DCommon.DDialog {
                title: I18n.trFor("inlineKeyboard", "Turn on debug mode?")
                supportingText: I18n.trFor("inlineKeyboard", "Debug mode loads the plugin's debug IPC so scripts/acceptance.py can drive it: read-only diagnostics, geometry readout, and simulated taps on keys, candidates, actions and the floating toggle.\n\nNormal use does not need it. Turn it off again when you are done testing.")
                // inline Component 的作用域是文件根对象，拿不到 DModal 的 screenWidth
                maximumWidth: Math.min(Theme.dialogMaxWidth, debugConfirm.screenWidth - Theme.spacingXL * 2)
                onRejected: root.debugConfirmOpen = false
                actions: [
                    DCommon.DButton {
                        text: I18n.trFor("inlineKeyboard", "Cancel")
                        backgroundColor: Theme.withAlpha(Theme.surfaceText, Alpha.Focus)
                        textColor: Theme.surfaceText
                        onClicked: root.debugConfirmOpen = false
                    },
                    DCommon.DButton {
                        text: I18n.trFor("inlineKeyboard", "Enable")
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
    }

    // 显式开关：DModal 的 shouldBeVisible 只同步状态，不建窗口
    Connections {
        function onDebugConfirmOpenChanged() {
            if (root.debugConfirmOpen)
                debugConfirm.open();
            else
                debugConfirm.close();
        }

        target: root
    }

}
