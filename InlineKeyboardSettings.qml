// Inline Keyboard 插件设置页：外观（缩放 / 透明度）、行为（避让 / 默认模式）、动作列表。
// 文案一律走 tr()，源串保持英文，译文在 translations/<locale>.json。
import QtQuick
import Quickshell
import Quickshell.Io
import "actions.js" as Actions
import "alpha.js" as Alpha
import qs.Common
import qs.DCommon.Widgets as DCommon
import qs.Modals.Common
import qs.Modules.Plugins
// 分组视觉直接复用 DMS 应用内部的设置组件：SettingsGroup / SettingsRow /
// SettingsToggleRow / SettingsDropdownRow / SettingsSliderRow / SettingsMetrics。
// 这几个不是插件 API，DMS 改签名时整页会挂；升级 DMS 后先看这里。
import qs.Modules.Settings.Widgets
import qs.Services
import qs.Widgets

PluginSettings {
    id: root

    // ydotoold 状态：没有它什么键都发不出去，所以摆在最上面
    property bool ydotooldUp: true
    // 标准设置组件不自带存取，这里自己 load / save
    property int repeatInterval: 60
    // 按键和卡片的描边粗细，0 = 不画
    property int borderWidth: 0
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
    // 自定义图标的当前值，由 reloadSettings 填（读写都走 root 的 loadValue/saveValue）
    property string winIconValue: ""
    // 宿主按 "popoutService" in item 判断是否注入，不声明就永远拿不到
    property var popoutService: null
    // 手写下拉：DDropdown 只认显示文本，值要自己映射（SelectionSetting 会把 defaultValue 写回文件）
    readonly property var modifierModeValues: ["noLock", "toggle", "tapLock", "doubleTapLock"]
    readonly property var modifierModeLabels: [I18n.trFor("inlineKeyboard", "Active while held"), I18n.trFor("inlineKeyboard", "Tap to activate; any key clears it"), I18n.trFor("inlineKeyboard", "Tap to lock (tap again to unlock)"), I18n.trFor("inlineKeyboard", "Tap to toggle, double-tap to lock")]
    readonly property var specialStyleValues: ["icon", "short", "full"]
    readonly property var specialStyleLabels: [I18n.trFor("inlineKeyboard", "Icon"), I18n.trFor("inlineKeyboard", "Short"), I18n.trFor("inlineKeyboard", "Full name")]
    // DDropdown 初始化时也会发一次 valueChanged（带默认值），这时不能写盘
    // loadValue() 是函数调用，直接绑到 checked / visible 上不会随点击重算，这里各留一份镜像
    // 自定义图标那一组的显示开关：下拉是封装组件，拿不到它的回调，这里订阅读一次
    property string winKeyStyleValue: "mod"
    property bool settingsReady: false

    // 只留给没被封装成组件的项：滑块、动作表、调试开关、自定义图标。
    // 开关和下拉各自带 loadValue()，值变化靠 PluginService.pluginDataChanged 自己同步。
    function reloadSettings() {
        root.repeatInterval = root.loadValue("repeatInterval", 60);
        root.borderWidth = root.loadValue("borderWidth", 0);
        root.winKeyStyleValue = root.loadValue("winKeyStyle", "mod");
        root.winIconValue = root.loadValue("winKeyCustomIcon", "");
        // 动作表在 SettingsGroup 里深两层，PluginSettings 的 reloadChildValues 够不到它
        if (actionList)
            actionList.loadValue();

        root.refreshDebugMode();
    }

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

        // 顺序有讲究：草稿先就位，editingId 次之（它一变编辑行的 Loader 就激活，要读到这条的值），
        // adding 放最后，否则 editingId 还空着的瞬间底部新增表单会闪一下
        root.draftLabel = action.label || "";
        root.draftIcon = action.icon || "label";
        root.draftCmd = action.cmd || "";
        root.editingId = action.id;
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

    // DMS 注入的 pluginService 上只有 availablePlugins，没有 load/savePluginData，直接走单例
    // loadValue 直接用基类（走注入的 pluginService，带默认值兜底）
    // saveValue 只加一道「初始化那一次不写盘」的门，权限检查和 settingChanged 照基类补齐
    function saveValue(key, val) {
        if (!root.settingsReady || !root.pluginService)
            return ;

        if (!root.hasPermission) {
            console.warn("inlineKeyboard: 没有 settings_write 权限，忽略写入 " + key);
            return ;
        }
        root.pluginService.savePluginData(root.pluginId, key, val);
        root.settingChanged();
    }

    // 内置动作名来自 actions.js，是运行时数据；提取工具只认字面量 trFor，所以逐个列出来
    function tr(term) {
        if (typeof I18n === "undefined" || !I18n || typeof I18n.trFor !== "function")
            return term;

        switch (term) {
        case "Undo":
            return I18n.trFor("inlineKeyboard", "Undo");
        case "Redo":
            return I18n.trFor("inlineKeyboard", "Redo");
        case "Settings":
            return I18n.trFor("inlineKeyboard", "Settings");
        case "Float":
            return I18n.trFor("inlineKeyboard", "Float");
        case "Size":
            return I18n.trFor("inlineKeyboard", "Size");
        case "Opacity":
            return I18n.trFor("inlineKeyboard", "Opacity");
        case "Next input method":
            return I18n.trFor("inlineKeyboard", "Next input method");
        case "Clipboard":
            return I18n.trFor("inlineKeyboard", "Clipboard");
        case "Avoid windows":
            return I18n.trFor("inlineKeyboard", "Avoid windows");
        case "Voice input":
            return I18n.trFor("inlineKeyboard", "Voice input");
        case "Minimize":
            return I18n.trFor("inlineKeyboard", "Minimize");
        case "Auto show":
            return I18n.trFor("inlineKeyboard", "Auto show");
        default:
            return term;
        }
    }

    pluginId: "inlineKeyboard"
    // 只在打开设置页时探一次；Start/Enable 按钮的 onExited 里还会再探
    // pluginService 由 PluginSettingsHost 在 Loader.onLoaded 注入，晚于 Component.onCompleted
    onPluginServiceChanged: root.reloadSettings()
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

    // 自定义图标分组跟着 winKeyStyle 显示：下拉是封装组件，值只在它内部，
    // 这里订阅一次写盘信号把派生值捞回来
    Connections {
        function onPluginDataChanged(id) {
            if (id !== root.pluginId)
                return ;

            root.winKeyStyleValue = root.loadValue("winKeyStyle", "mod");
            root.winIconValue = root.loadValue("winKeyCustomIcon", "");
        }

        target: root.pluginService
        enabled: target !== null
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

    SettingsGroup {
        width: parent.width
        slotColor: SettingsMetrics.paneColor

        PluginSettingRow {
            settingKey: "alwaysShowPreedit"
            pluginRoot: root
            defaultValue: false
            text: I18n.trFor("inlineKeyboard", "Always show the preedit in the keyboard")
            description: I18n.trFor("inlineKeyboard", "Some apps draw the pinyin string inside the text field themselves; turn this on to also show it in the keyboard.")
        }

        // 特殊键的表现形式，对应 layouts/specialKeys.js 的 STYLES；过长的文字由 Key.qml 的 HorizontalFit 缩字号
        // 不用 SelectionSetting：它初始化时会把 defaultValue 写回文件（DDropdown 的 valueChanged 回环）
        PluginSettingDropdownRow {
            settingKey: "specialKeyStyle"
            pluginRoot: root
            defaultValue: "full"
            values: root.specialStyleValues
            labels: root.specialStyleLabels
            text: I18n.trFor("inlineKeyboard", "Special key labels")
            description: I18n.trFor("inlineKeyboard", "How Backspace, Enter, Shift, Ctrl, Alt and Tab are drawn. Full names shrink to fit the key.")
        }

        // Win 键实际发的是 Super_L，叫 Win 只对 Windows 用户成立，默认显示 Mod
        PluginSettingDropdownRow {
            settingKey: "winKeyStyle"
            pluginRoot: root
            defaultValue: "mod"
            values: ["mod", "super", "system", "custom"]
            labels: ["Mod", "Super", "⌘", I18n.trFor("inlineKeyboard", "Custom icon")]
            text: I18n.trFor("inlineKeyboard", "Win key label")
            description: I18n.trFor("inlineKeyboard", "This key sends Super. Show it as text or an icon.")
        }

        SettingsSliderRow {
            text: I18n.trFor("inlineKeyboard", "Key and keyboard border")
            description: I18n.trFor("inlineKeyboard", "Border width for the keys and the keyboard card. 0 draws no border.")
            minimum: 0
            maximum: 4
            step: 1
            unit: " px"
            value: root.borderWidth
            onSliderValueChanged: (value) => {
                if (root.borderWidth !== value) {
                    root.borderWidth = value;
                    root.saveValue("borderWidth", value);
                }
            }
        }

    }

    // 自定义图标：DIconPicker 选 Material 图标，或者直接填图片路径
    SettingsGroup {
        width: parent.width
        slotColor: SettingsMetrics.paneColor
        visible: root.winKeyStyleValue === "custom"

        SettingsRow {
            title: I18n.trFor("inlineKeyboard", "Icon")

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DCommon.DIconPicker {
                    id: winIconPicker2

                    width: Math.min(Theme.iconSizeLarge * 5, parent.width * 0.3)
                    currentIcon: root.winIconValue
                    onIconSelected: (iconName, iconType) => {
                        return root.setWinIcon(iconName);
                    }
                }

                DCommon.DTextField {
                    width: parent.width - winIconPicker2.width - parent.spacing
                    placeholderText: I18n.trFor("inlineKeyboard", "svg/png path")
                    text: root.winIconValue.indexOf("/") >= 0 ? root.winIconValue : ""
                    // 每敲一个字符都写盘会触发 reloadChildValues 重建动作列表，编辑结束再提交
                    onEditingFinished: root.setWinIcon(text.trim())
                }

            }

        }

    }

    SettingsSection {
        text: I18n.trFor("inlineKeyboard", "Behaviour")
    }

    SettingsGroup {
        width: parent.width
        slotColor: SettingsMetrics.paneColor

        PluginSettingRow {
            settingKey: "tooltips"
            pluginRoot: root
            defaultValue: true
            text: I18n.trFor("inlineKeyboard", "Button tooltips")
            description: I18n.trFor("inlineKeyboard", "Show hints when hovering over keyboard buttons.")
        }

        PluginSettingRow {
            settingKey: "longPressNote"
            pluginRoot: root
            defaultValue: false
            text: I18n.trFor("inlineKeyboard", "Long-press candidate for pinyin")
            description: I18n.trFor("inlineKeyboard", "Keeps the candidate when there is no pinyin")
        }

        PluginSettingRow {
            settingKey: "autoShow"
            pluginRoot: root
            defaultValue: false
            text: I18n.trFor("inlineKeyboard", "Auto show")
            description: I18n.trFor("inlineKeyboard", "Show the keyboard when a text field gets focus.")
        }

        PluginSettingRow {
            settingKey: "blockTtySwitch"
            pluginRoot: root
            defaultValue: true
            text: I18n.trFor("inlineKeyboard", "Block Ctrl+Alt+F1-F12")
            description: I18n.trFor("inlineKeyboard", "These combinations switch to a TTY at the kernel level, so the compositor cannot stop them. Keep this on unless you need to reach a TTY from the keyboard.")
        }

        PluginSettingRow {
            settingKey: "avoidWindows"
            pluginRoot: root
            defaultValue: true
            text: I18n.trFor("inlineKeyboard", "Avoid windows when docked")
            description: I18n.trFor("inlineKeyboard", "Shrink other windows so the keyboard does not cover them.")
        }

        PluginSettingRow {
            settingKey: "defaultFloating"
            pluginRoot: root
            defaultValue: false
            text: I18n.trFor("inlineKeyboard", "Use the floating keyboard by default")
            description: I18n.trFor("inlineKeyboard", "Off opens the docked keyboard.")
        }

        PluginSettingDropdownRow {
            settingKey: "modifierMode"
            pluginRoot: root
            defaultValue: "doubleTapLock"
            values: root.modifierModeValues
            labels: root.modifierModeLabels
            text: I18n.trFor("inlineKeyboard", "Modifier tap behaviour")
            description: I18n.trFor("inlineKeyboard", "How Shift / Ctrl / Alt / Win respond to touch. Caps Lock always toggles.")
        }

        PluginSettingRow {
            settingKey: "escSwap"
            pluginRoot: root
            defaultValue: false
            text: I18n.trFor("inlineKeyboard", "Esc on the top-left key")
            description: I18n.trFor("inlineKeyboard", "Swap the `~ key with Esc. Fn layer keeps the other one.")
        }

    }

    SettingsGroup {
        width: parent.width
        slotColor: SettingsMetrics.paneColor

        SettingsSliderRow {
            text: I18n.trFor("inlineKeyboard", "Key repeat interval")
            description: I18n.trFor("inlineKeyboard", "Delay between repeated keystrokes while a key is held down.")
            minimum: 20
            maximum: 200
            step: 10
            unit: " ms"
            value: root.repeatInterval
            onSliderValueChanged: (value) => {
                if (root.repeatInterval !== value) {
                    root.repeatInterval = value;
                    root.saveValue("repeatInterval", value);
                }
            }
        }

    }

    SettingsSection {
        text: I18n.trFor("inlineKeyboard", "Actions")
    }

    SettingsGroup {
        width: parent.width
        slotColor: SettingsMetrics.paneColor

        // 动作表单：编辑时内联在那一行下面，新增时排在列表底部，两处共用这一份定义
        Component {
            id: actionFormComponent

            Column {
                id: actionForm

                function loadDraft() {
                    labelField.text = root.draftLabel;
                    cmdField.text = root.draftCmd;
                }

                // 容器已经带内边距（行里是 SettingsRow 的 paddingH），这里只管撑满和行距
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

    SettingsGroup {
        width: parent.width
        slotColor: SettingsMetrics.paneColor

        // 只放数据与存取；布局交给设置组，行才能真正参与分组排版
        QtObject {
            id: actionList

            property var items: []
            property bool loading: false

            // 只在创建时读一次；pluginService 晚到时 reloadSettings() 再补
            function loadValue() {
                loading = true;
                // 和 daemon 用同一套清洗：坏数据（重复 id、缺 label）在设置页也该被滤掉
                items = Actions.sanitizeActions(root.loadValue("actions", Actions.defaultActions()), Actions.defaultActions());
                loading = false;
            }

            Component.onCompleted: loadValue()
            onItemsChanged: {
                if (loading)
                    return ;

                root.saveValue("actions", items);
            }
        }

        StyledText {
            width: parent.width
            text: I18n.trFor("inlineKeyboard", "Built-in actions can only be hidden; the ones you add can be removed.")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: actionList.items

            Component {
                SettingsRow {
                    required property int index
                    required property var modelData
                    readonly property bool isHidden: modelData.hidden === true
                    readonly property bool isBuiltin: modelData.builtin === true || root.builtinIds[modelData.id] === true

                    title: root.tr(modelData.label)
                    titleColor: isHidden ? Theme.withAlpha(Theme.surfaceText, Alpha.Muted) : Theme.surfaceText

                    Row {
                        id: actionButtons

                        spacing: Theme.spacingXS

                        // 隐藏态：底色 primary，图标用 onPrimary 保证对比度
                        DCommon.DActionButton {
                            iconName: isHidden ? "visibility_off" : "visibility"
                            backgroundColor: isHidden ? Theme.primary : "transparent"
                            iconColor: isHidden ? Theme.onPrimary : Theme.withAlpha(Theme.surfaceText, Alpha.Medium)
                            tooltipText: isHidden ? I18n.trFor("inlineKeyboard", "Show") : I18n.trFor("inlineKeyboard", "Hide")
                            Accessible.name: tooltipText
                            onClicked: root.patchAction(modelData.id, {
                                "hidden": !isHidden
                            })
                        }

                        DCommon.DActionButton {
                            visible: !isBuiltin
                            iconName: "edit"
                            iconColor: Theme.withAlpha(Theme.surfaceText, Alpha.High)
                            tooltipText: I18n.trFor("inlineKeyboard", "Edit")
                            Accessible.name: tooltipText
                            onClicked: root.startEdit(modelData)
                        }

                        DCommon.DActionButton {
                            visible: !isBuiltin
                            iconName: "delete"
                            iconColor: Theme.withAlpha(Theme.error, Alpha.Bright)
                            tooltipText: I18n.trFor("inlineKeyboard", "Remove")
                            Accessible.name: tooltipText
                            onClicked: root.removeActionById(modelData.id)
                        }

                    }

                    // 非编辑态只展示图标，改图标走那一行的编辑
                    leading: ActionIcon {
                        action: modelData
                        size: Theme.iconSizeMedium
                        color: Theme.surfaceText
                    }

                    // 编辑这一行时，表单就展开在它下面
                    body: Loader {
                        width: parent.width
                        active: root.editingId === modelData.id
                        // 卸掉之后 implicitHeight 会留着上次的高度，显式收成 0 行高才回得去
                        height: active ? implicitHeight : 0
                        sourceComponent: actionFormComponent
                        onLoaded: item.loadDraft()
                    }

                }

            }

        }

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

    SettingsSection {
        text: I18n.trFor("inlineKeyboard", "Debugging")
    }

    SettingsGroup {
        width: parent.width
        slotColor: SettingsMetrics.paneColor

        // 调试 IPC：只读诊断 + 模拟操作（点击 / 长按 / 拖动），给 scripts/acceptance.py 用
        // 点开只弹确认框，确认后才落盘（toggling 期间开关显示为待定）
        SettingsToggleRow {
            text: I18n.trFor("inlineKeyboard", "Debug mode")
            description: I18n.trFor("inlineKeyboard", "Exposes the IPC that scripts/acceptance.py drives. Normal use does not need it.")
            checked: root.debugModeOn
            toggling: root.debugConfirmOpen
            onToggled: (value) => {
                if (value)
                    root.debugConfirmOpen = true;
                else
                    root.writeDebugMode(false);
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
