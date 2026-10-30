// Inline Keyboard 插件设置页：外观（缩放 / 透明度）、行为（避让 / 默认模式）、动作列表。
// 文案一律走 tr()，源串保持英文，译文在 translations/<locale>.json。
import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as DCommon
import qs.Modules.Plugins
import "actions.js" as Actions

PluginSettings {
    id: root

    pluginId: "inlineKeyboard"

    // DMS 会在插件翻译表就绪之前预实例化设置页，文案会停在英文。
    // 用短轮询把「表就绪」变成属性变化，让绑定重算（同 KeyboardCard 里的做法）
    property int localeVersion: 0
    property int translationPollCount: 0

    Timer {
        interval: 100
        repeat: true
        running: root.localeVersion === 0 && root.translationPollCount < 100
        onTriggered: {
            root.translationPollCount++
            const tables = (typeof I18n !== "undefined" && I18n) ? I18n.pluginTranslations : null
            if (tables && tables[root.pluginId])
                root.localeVersion = 1
        }
    }

    // ---- ydotoold 状态：没有它什么键都发不出去，所以直接摆在最上面 ----
    property bool ydotooldUp: true

    Process {
        id: daemonCheck
        running: false
        // 同时看进程和 socket：ydotoold 停掉后 socket 文件会残留，只测 socket 会误判
        onExited: code => root.ydotooldUp = (code === 0)
    }

    Process {
        id: daemonStart
        running: false
        command: ["systemctl", "--user", "start", "ydotool"]
        onExited: code => {
            daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "$XDG_RUNTIME_DIR/.ydotool_socket"']
            daemonCheck.running = true
        }
    }

    Process {
        id: daemonEnable
        running: false
        command: ["systemctl", "--user", "enable", "--now", "ydotool"]
        onExited: code => {
            daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "$XDG_RUNTIME_DIR/.ydotool_socket"']
            daemonCheck.running = true
        }
    }

    // 只在打开设置页时探一次；Start/Enable 按钮的 onExited 里还会再探
    Component.onCompleted: {
        daemonCheck.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "$XDG_RUNTIME_DIR/.ydotool_socket"']
        daemonCheck.running = true
        bridgeCheck.running = true
    }

    // ---- 可选扩展：fcitx5 桥接 ----
    // 装了 addon 才有候选、拼音串和地球键切换；没装也能打字（按键走 ydotool）
    property bool bridgeUp: false

    Process {
        id: bridgeCheck
        running: false
        // 和 daemonCheck 同理由：文件残留会误判，所以测的是 socket 本身
        command: ["sh", "-c", 'test -S "$XDG_RUNTIME_DIR/inline-keyboard.sock"']
        onExited: code => root.bridgeUp = (code === 0)
    }

    // 安装命令直接摆出来，省得用户回 README 找
    readonly property string installCommands:
        "git clone https://github.com/LilFishyChan/fcitx5-inline-keyboard-status\n" +
        "cd fcitx5-inline-keyboard-status && cmake -B build -G Ninja && ninja -C build\n" +
        "cmake --install build --prefix ~/.local\n" +
        "systemctl --user restart 'app-org.fcitx.Fcitx5@autostart.service'"

    Process {
        id: copyInstall
        running: false
        command: ["dms", "cl", "copy", root.installCommands]
    }

    // 正在改图标的动作索引（-1 = 没在选）
    property int pickerIndex: -1

    // 内置动作的 id 集合：ListSetting 直接读文件里的原始数组（不经 sanitize），
    // 老数据没有 builtin 字段，靠这张表兜底
    readonly property var builtinIds: {
        const map = {}
        const defaults = Actions.defaultActions()
        for (let i = 0; i < defaults.length; i++)
            map[defaults[i].id] = true
        return map
    }

    readonly property var iconChoices: [
        // 动作 / 编辑
        "undo", "redo", "settings", "tune", "dashboard", "apps", "close", "add", "check",
        "edit", "delete", "save", "download", "upload", "share", "link", "content_copy",
        "content_paste", "content_cut", "select_all", "search", "filter_list", "sort",
        "visibility", "visibility_off", "lock", "lock_open", "refresh", "sync", "restart_alt",
        // 键盘 / 输入
        "keyboard", "keyboard_alt", "keyboard_hide", "backspace", "space_bar", "input",
        "language", "translate", "mic", "mic_off", "volume_up", "volume_off", "volume_down",
        "record_voice_over", "speaker", "graphic_eq", "spellcheck", "text_fields", "abc",
        // 窗口 / 布局
        "dock", "open_in_new", "open_in_full", "close_fullscreen", "fullscreen",
        "fullscreen_exit", "aspect_ratio", "crop_free", "picture_in_picture", "layers",
        "window", "view_agenda", "view_compact", "grid_view", "view_sidebar", "unfold_more",
        "unfold_less", "swap_vert", "swap_horiz",
        // 媒体
        "play_arrow", "pause", "stop", "skip_next", "skip_previous", "fast_forward",
        "fast_rewind", "replay", "shuffle", "repeat", "queue_music", "music_note",
        "movie", "photo_camera", "photo", "videocam", "screenshot_monitor", "image",
        // 文件 / 存储
        "folder", "folder_open", "description", "article", "note", "insert_drive_file",
        "cloud", "cloud_upload", "cloud_download", "storage", "archive", "inventory",
        // 设备 / 系统
        "computer", "smartphone", "tablet", "watch", "headphones", "bluetooth", "wifi",
        "signal_cellular_4_bar", "battery_full", "power_settings_new", "memory", "terminal",
        "code", "bug_report", "build", "construction", "science", "bolt", "flash_on",
        "light_mode", "dark_mode", "brightness_auto", "brightness_6", "nightlight",
        "contrast", "palette", "format_paint", "colorize", "opacity", "blur_on",
        // 状态 / 提示
        "info", "help", "warning", "error", "check_circle", "cancel", "block", "star",
        "star_border", "favorite", "favorite_border", "bookmark", "flag", "label", "sell",
        "notifications", "notifications_off", "schedule", "timer", "alarm", "calendar_month",
        "today", "history", "update", "pending", "hourglass_empty", "task_alt",
        // 导航 / 方向
        "arrow_upward", "arrow_downward", "arrow_back", "arrow_forward", "chevron_left",
        "chevron_right", "expand_less", "expand_more", "first_page", "last_page",
        "home", "menu", "more_vert", "more_horiz", "drag_indicator", "open_with",
        "pan_tool", "touch_app", "gesture", "swipe",
        // 人 / 社交
        "person", "group", "face", "mood", "emoji_emotions", "psychology", "school",
        "work", "business", "mail", "chat", "send", "call", "public",
        // 杂项
        "eco", "cake", "local_fire_department", "water_drop", "air", "wb_sunny",
        "umbrella", "shopping_cart", "payments", "receipt_long", "calculate", "map",
        "place", "near_me", "explore", "pin_drop"
    ]

    // 添加 / 编辑自定义动作的表单状态（editingId 非空 = 正在改已有动作）
    property string editingId: ""
    property bool adding: false
    property string draftLabel: ""
    property string draftIcon: "label"
    property string draftCmd: ""

    // 图标选择器：浮窗 + 搜索
    property bool pickingIcon: false
    property string iconQuery: ""
    property bool pickForDraft: false          // 选择器当前服务于「添加表单」而不是某个已有动作
    property bool pickForWin: false             // 选择器当前服务于 Win 键的自定义图标

    // 用户可能输入的是目录路径（/home/x/icons 或 ~/icons），这时不搜图标名，
    // 直接把那个目录里的 svg / png 列出来让他挑。
    readonly property string queryPath: {
        const q = root.iconQuery.trim()
        if (q === "")
            return ""
        // 含路径分隔符或以 ~ 开头才算路径，避免把普通搜索词误判
        return (q.indexOf("/") >= 0 || q.charAt(0) === "~") ? q : ""
    }
    property var iconFiles: []

    Process {
        id: iconDirLister
        running: false
        command: ["sh", "-c",
                  // $1 走位置参数，避免把用户输入拼进脚本（不经过二次解析）
                  'd="$1"; case "$d" in "~"*) d="$HOME${d#"~"}";; esac; ' +
                  '[ -d "$d" ] && find "$d" -maxdepth 1 -type f ' +
                  '\( -iname "*.svg" -o -iname "*.png" \) 2>/dev/null | sort | head -300',
                  "sh", root.queryPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text || "").split("\n").filter(l => l.length > 0)
                root.iconFiles = lines
            }
        }
    }

    // 路径变了就重新列目录
    onQueryPathChanged: {
        if (root.queryPath === "") {
            root.iconFiles = []
            iconDirLister.running = false
            return
        }
        root.iconFiles = []
        iconDirLister.running = false
        iconDirLister.running = true
    }

    readonly property var filteredIcons: {
        // 输入是路径：只显示那个目录里的图片文件
        if (root.queryPath !== "")
            return root.iconFiles
        const q = root.iconQuery.trim().toLowerCase()
        if (q === "")
            return root.iconChoices
        return root.iconChoices.filter(name => name.indexOf(q) >= 0)
    }

    // 动作数据由下面的 ListSetting 持有（它自带读写设置，设置页没有 pluginService 可用）。
    // 修改一律走 actions.js 的纯函数，保证和 daemon / 卡片用的是同一套规则。
    function patchAction(id, patch) {
        actionList.items = Actions.updateAction(Actions.toArray(actionList.items), id, patch)
    }

    function removeActionById(id) {
        actionList.items = Actions.removeAction(Actions.toArray(actionList.items), id).actions
    }

    function startAdd() {
        root.editingId = ""
        root.draftLabel = ""
        root.draftIcon = "label"
        root.draftCmd = ""
        root.adding = true
        Qt.callLater(root.syncFormInputs)
    }

    // 编辑自己添加的动作（内置动作只能隐藏，没有编辑入口）
    // 表单打开时把 draft 灌进输入框（TextInput.text 不能用绑定，用户一打字绑定就断）
    function syncFormInputs() {
        if (typeof labelInput !== "undefined")
            labelInput.text = root.draftLabel
        if (typeof cmdInput !== "undefined")
            cmdInput.text = root.draftCmd
    }

    function startEdit(action) {
        if (!action || action.builtin === true || root.builtinIds[action.id] === true)
            return
        root.editingId = action.id
        root.draftLabel = action.label || ""
        root.draftIcon = action.icon || "label"
        root.draftCmd = action.cmd || ""
        root.adding = true
        Qt.callLater(root.syncFormInputs)
    }

    function confirmAdd() {
        const label = root.draftLabel.trim()
        if (label === "")
            return
        // 编辑模式：直接改这一条
        if (root.editingId !== "") {
            root.patchAction(root.editingId, {
                label: label,
                icon: root.draftIcon || "label",
                cmd: root.draftCmd.trim()
            })
            root.adding = false
            root.editingId = ""
            return
        }
        let list = Actions.toArray(actionList.items)
        // 防御：内置动作一个都不在列表里，说明数据被写空过，先补回默认表
        if (!list.some(a => a && a.builtin === true)) {
            list = Actions.defaultActions().concat(list.filter(a => a && a.builtin !== true))
        }
        actionList.items = Actions.appendAction(list, {
            label: label,
            icon: root.draftIcon || "label",
            cmd: root.draftCmd.trim()
        }).actions
        root.adding = false
    }

    function openIconPicker(index) {
        const list = Actions.toArray(actionList.items)
        root.pickForDraft = false
        root.pickForWin = false
        root.pickerIndex = (index >= 0 && index < list.length) ? index : -1
        root.iconQuery = ""
        if (root.pickerIndex >= 0) {
            root.pickingIcon = true
            iconPopup.open()
        }
    }

    function openIconPickerForWin() {
        root.pickForWin = true
        root.pickForDraft = false
        root.pickerIndex = -1
        root.pickingIcon = true
        iconPopup.open()
    }

    function openIconPickerForDraft() {
        root.pickForDraft = true
        root.pickForWin = false
        root.pickerIndex = -1
        root.iconQuery = ""
        root.pickingIcon = true
        iconPopup.open()
    }

    function applyIcon(name) {
        const value = (name || "").trim()
        if (value === "")
            return
        if (root.pickForWin) {
            winIconSetting.value = value
            // ⚠ DMS 的 StringSetting 只在输入框 commit()（回车/失焦）时写盘，
            // 这个值走的是图标选择器、没有输入框参与，只赋值不会持久化。
            // 表现就是「选完图标当时看着对了，重开设置又变回未设置」。
            root.saveValue("winKeyCustomIcon", value)
        } else if (root.pickForDraft) {
            root.draftIcon = value
        } else {
            const list = Actions.toArray(actionList.items)
            const action = list[root.pickerIndex]
            if (action)
                root.patchAction(action.id, { icon: value })
        }
        iconPopup.close()
    }

    // 缺词条时回退英文原串
    function tr(term) {
        const version = root.localeVersion      // 让调用处的绑定跟随版本重算
        if (typeof I18n === "undefined" || !I18n || !I18n.trFor)
            return term
        return I18n.trFor(root.pluginId, term)
    }

    // ydotoold 没跑：警告 + 两种做法（临时启动 / 设为开机自启）
    Rectangle {
        visible: !root.ydotooldUp
        width: parent.width
        height: visible ? 132 : 0
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceText, 0.07)

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            anchors.topMargin: Theme.spacingM
            text: root.tr("ydotoold is not running — the keyboard cannot type until it starts.")
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeMedium
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            anchors.topMargin: 40
            text: root.tr("Start it once below, or enable it permanently so it survives a reboot: "
                          + "systemctl --user enable --now ydotool")
            color: Theme.withAlpha(Theme.surfaceText, 0.7)
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
        }

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: Theme.spacingM
            anchors.bottomMargin: Theme.spacingM
            spacing: Theme.spacingS

            DCommon.DButton {
                text: root.tr("Start")
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
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

    StyledText {
        width: parent.width
        text: root.tr("Toggle it with `dms ipc call inlineKeyboard toggle`, or add the widget to your DankBar.")
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ---------------- 可选扩展 ----------------
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
            text: root.bridgeUp
                  ? root.tr("Connected — candidates, preedit and the globe switcher are live.")
                  : root.tr("Candidates, the pinyin preedit and the globe input-method switcher come from a small fcitx5 addon. Without it the keyboard still types (keys go through ydotool), but the candidate strip stays empty.")
            font.pixelSize: Theme.fontSizeMedium
            color: root.bridgeUp ? Theme.primary : Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            visible: !root.bridgeUp
            height: visible ? cmdText.implicitHeight + 28 : 0
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceText, 0.06)

            Text {
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

    // ---------------- 外观 ----------------
    StyledText {
        width: parent.width
        text: root.tr("Appearance")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    SliderSetting {
        settingKey: "repeatInterval"
        label: root.tr("Key repeat interval")
        description: root.tr("Delay between repeated keystrokes while a key is held down.")
        minimum: 20
        maximum: 200
        defaultValue: 60
        unit: " ms"
    }

    // ---------------- 行为 ----------------
    StyledText {
        width: parent.width
        text: root.tr("Behaviour")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    ToggleSetting {
        settingKey: "avoidWindows"
        label: root.tr("Avoid windows when docked")
        description: root.tr("Shrink other windows so the keyboard does not cover them.")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "defaultFloating"
        label: root.tr("Use the floating keyboard by default")
        description: root.tr("Off opens the docked keyboard.")
        defaultValue: false
    }

    // 输入注入后端：用户自己装、自己选，不做自动探测

    SelectionSetting {
        settingKey: "modifierMode"
        label: root.tr("Modifier tap behaviour")
        description: root.tr("How Shift / Ctrl / Alt / Win respond to touch. Caps Lock always toggles.")
        defaultValue: "doubleTapLock"
        options: [
            { label: root.tr("Active while held"), value: "noLock" },
            { label: root.tr("Tap to activate; any key clears it"), value: "toggle" },
            { label: root.tr("Tap to lock (tap again to unlock)"), value: "tapLock" },
            { label: root.tr("Tap to toggle, double-tap to lock"), value: "doubleTapLock" }
        ]
    }

    // 特殊键的表现形式。三个选项对应 layouts/special-keys.js 的 STYLES；
    // 「完整」形态下过长的文字由 Key.qml 的 Text.HorizontalFit 自动缩字号。
    SelectionSetting {
        settingKey: "specialKeyStyle"
        label: root.tr("Special key labels")
        description: root.tr("How Backspace, Enter, Shift, Ctrl, Alt and Tab are drawn. Full names shrink to fit the key.")
        defaultValue: "full"
        options: [
            { label: root.tr("Icon"), value: "icon" },
            { label: root.tr("Short"), value: "short" },
            { label: root.tr("Full name"), value: "full" }
        ]
    }

    // Win 键实际发的是 Super_L，叫 Win 只对 Windows 用户成立，默认显示 Mod
    SelectionSetting {
        id: winLookSetting
        settingKey: "winKeyStyle"
        label: root.tr("Win key label")
        description: root.tr("This key sends Super. Show it as text or an icon.")
        defaultValue: "mod"
        options: [
            { label: "Mod", value: "mod" },
            { label: "Super", value: "super" },
            // 系统图标直接显示它本身（keyboard_command_key 渲出来就是 ⌘）
            { label: "⌘", value: "system" },
            { label: root.tr("Custom icon"), value: "custom" }
        ]
    }

    // 自定义图标：点按钮打开和动作编辑同一个图标选择器
    Rectangle {
        visible: winLookSetting.value === "custom"
        width: parent ? parent.width : 0
        height: 64
        radius: Theme.cornerRadius
        color: "transparent"

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(Theme.spacingM)

            // 当前选中图标的预览：有值就渲染（图标名走 DankIcon，路径走 Image）
            Rectangle {
                width: 44
                height: 44
                radius: width / 2
                color: Theme.surfaceContainer

                DankIcon {
                    visible: !String(winIconSetting.value || "").startsWith("/")
                    anchors.centerIn: parent
                    name: String(winIconSetting.value || "") || "keyboard_command_key"
                    size: 20
                    color: Theme.surfaceText
                }

                Image {
                    visible: String(winIconSetting.value || "").startsWith("/")
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    source: visible ? "file://" + winIconSetting.value : ""
                    sourceSize.width: 52
                    sourceSize.height: 52
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openIconPickerForWin()
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    text: root.tr("Custom icon")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: String(winIconSetting.value || "") || root.tr("Not set — tap the icon to choose")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.withAlpha(Theme.surfaceVariantText, 0.9)
                }
            }
        }
    }

    // 值的持有者（设置项的读写都靠它），界面由上面那块负责
    StringSetting {
        visible: false
        id: winIconSetting
        settingKey: "winKeyCustomIcon"
        label: root.tr("Custom icon")
        description: ""
        defaultValue: ""
    }

    // ---------------- 动作 ----------------
    StyledText {
        width: parent.width
        text: root.tr("Actions")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    // ---------------- 动作管理 ----------------
    // 用 ListSetting 而不是自己读写 pluginData：设置页没有 pluginService 可用，
    // ListSetting 自带存取，并提供 items / addItem / removeItem。
    ToggleSetting {
        settingKey: "escSwap"
        label: root.tr("Esc on the top-left key")
        description: root.tr("Swap the \`~ key with Esc. Fn layer keeps the other one.")
        defaultValue: false
    }

    ListSetting {
        id: actionList
        settingKey: "actions"
        label: root.tr("Actions")
        description: root.tr("Built-in actions can only be hidden; the ones you add can be removed. Tap an icon to change it.")
        defaultValue: Actions.defaultActions()

        delegate: Component {
            Rectangle {
                required property int index
                required property var modelData
                readonly property bool isHidden: modelData.hidden === true
                readonly property bool isBuiltin: modelData.builtin === true
                                                  || root.builtinIds[modelData.id] === true

                width: parent.width
                height: 52
                radius: Theme.cornerRadius
                // 隐藏的行压深一档（沉下去），显示的行用浅底
                color: isHidden ? Theme.surfaceContainer : Theme.surfaceContainerLow

                // 图标：点一下打开选择器
                Rectangle {
                    id: iconButton
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: width / 2
                    color: Theme.surfaceContainerHigh

                    ActionIcon {
                        anchors.centerIn: parent
                        action: modelData
                        size: 20
                        color: Theme.surfaceText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openIconPicker(index)
                    }
                }

                StyledText {
                    anchors.left: iconButton.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: hideButton.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    font.pixelSize: Theme.fontSizeMedium
                    color: isHidden ? Theme.withAlpha(Theme.surfaceText, 0.55) : Theme.surfaceText
                    elide: Text.ElideRight
                }

                // 隐藏开关（内置动作只能这样处理）
                Rectangle {
                    id: hideButton
                    anchors.right: parent.right
                    anchors.rightMargin: isBuiltin ? Theme.spacingS : 74
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: width / 2
                    color: isHidden ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"

                    DankIcon {
                        anchors.centerIn: parent
                        name: isHidden ? "visibility_off" : "visibility"
                        size: 19
                        color: isHidden ? Theme.primary
                                        : Theme.withAlpha(Theme.surfaceText, 0.65)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.patchAction(modelData.id, { hidden: !isHidden })
                    }
                }

                // 编辑：只有自定义动作有
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 42
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !isBuiltin
                    width: 32
                    height: 32
                    radius: width / 2
                    color: "transparent"

                    DankIcon {
                        anchors.centerIn: parent
                        name: "edit"
                        size: 19
                        color: Theme.withAlpha(Theme.surfaceText, 0.75)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.startEdit(modelData)
                    }
                }

                // 删除：只有自定义动作有
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !isBuiltin
                    width: 32
                    height: 32
                    radius: width / 2
                    color: "transparent"

                    DankIcon {
                        anchors.centerIn: parent
                        name: "delete"
                        size: 19
                        color: Theme.withAlpha(Theme.error, 0.85)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeActionById(modelData.id)
                    }
                }
            }
        }
    }

    // 添加自定义动作：表单（名称 / 图标 / 命令）
    Rectangle {
        width: parent.width
        visible: root.adding
        height: visible ? addColumn.height + Theme.spacingM * 2 : 0
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerLow
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.35)

        Column {
            id: addColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Math.round(Theme.spacingS)

            StyledText {
                width: parent.width
                text: root.editingId !== "" ? root.tr("Edit action") : root.tr("New action")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            // 名称
            DCommon.DTextField {
                id: labelInput
                width: parent.width
                placeholderText: root.tr("Name")
                onTextEdited: root.draftLabel = text
            }

            // 图标 + 命令
            Row {
                width: parent.width
                spacing: Math.round(Theme.spacingS)

                Rectangle {
                    width: 36
                    height: 36
                    radius: width / 2
                    color: Theme.surfaceContainer

                    ActionIcon {
                        anchors.centerIn: parent
                        action: ({ id: "", label: "", icon: root.draftIcon })
                        size: 20
                        color: Theme.surfaceText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openIconPickerForDraft()
                    }
                }

                DCommon.DTextField {
                    id: cmdInput
                    width: parent.width - 36 - Theme.spacingS
                    placeholderText: root.tr("Command, e.g. grim -g \"$(slurp)\"")
                    onTextEdited: root.draftCmd = text
                }
            }

            Row {
                spacing: Math.round(Theme.spacingS)

                Rectangle {
                    width: 80
                    height: 32
                    radius: Theme.cornerRadius
                    color: Theme.primary

                    StyledText {
                        anchors.centerIn: parent
                        text: root.tr("Add")
                        color: Theme.surface
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmAdd()
                    }
                }

                Rectangle {
                    width: 80
                    height: 32
                    radius: Theme.cornerRadius
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

                    StyledText {
                        anchors.centerIn: parent
                        text: root.tr("Cancel")
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.adding = false
                    }
                }
            }
        }
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

    // 图标选择器浮窗：搜索 + 可滚动网格
    Popup {
        id: iconPopup
        parent: Overlay.overlay
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        width: Math.min(620, parent ? parent.width - 80 : 620)
        height: Math.min(580, parent ? parent.height - 90 : 580)
        modal: true
        padding: Theme.spacingM
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        // visible 是只读的，只能 open()/close()；关掉时把状态同步回去
        onClosed: {
            root.pickingIcon = false
            root.pickerIndex = -1
            root.pickForDraft = false
            root.pickForWin = false
        }

        background: Rectangle {
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius
            border.width: 1
            border.color: Theme.withAlpha(Theme.outlineVariant, 0.6)
        }

        Column {
            anchors.fill: parent
            spacing: Math.round(Theme.spacingS)

            StyledText {
                width: parent.width
                text: root.tr("Choose an icon")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            // 搜索框：回车直接采用输入的名字（自定义图标名）
            DCommon.DTextField {
                id: iconQueryInput
                width: parent.width
                placeholderText: root.tr("Search, or type a name and press Enter")
                onTextEdited: root.iconQuery = text
                onAccepted: root.applyIcon(text)
            }

            GridView {
                id: iconGrid
                width: parent.width
                // 给标题 / 搜索框 / 底部说明（可能两行）都留足空间
                height: parent.height - 120
                cellWidth: 48
                cellHeight: 48
                clip: true
                model: root.filteredIcons
                ScrollBar.vertical: DCommon.DScrollbar { targetFlickable: iconGrid }

                delegate: Rectangle {
                    required property string modelData
                    readonly property bool selected: {
                        if (root.pickForWin)
                            return String(winIconSetting.value || "") === modelData
                        if (root.pickForDraft)
                            return root.draftIcon === modelData
                        const list = Actions.toArray(actionList.items)
                        const current = root.pickerIndex >= 0 ? list[root.pickerIndex] : null
                        return !!current && current.icon === modelData
                    }
                    // 以 / 开头的是搜出来的图片文件，其余是 Material Symbols 图标名
                    readonly property bool isFile: modelData.charAt(0) === "/"

                    width: 44
                    height: 44
                    radius: width / 2
                    color: selected ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"

                    // 图标字体
                    DankIcon {
                        visible: !parent.isFile
                        anchors.centerIn: parent
                        name: parent.isFile ? "" : parent.modelData
                        size: 20
                        color: parent.selected ? Theme.primary : Theme.surfaceText
                    }

                    // 目录里找到的 svg / png 直接渲染缩略图
                    Image {
                        visible: parent.isFile
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        source: parent.isFile ? "file://" + parent.modelData : ""
                        sourceSize.width: 52
                        sourceSize.height: 52
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyIcon(modelData)
                    }
                }
            }

            StyledText {
                width: parent.width
                text: root.queryPath !== ""
                      ? root.tr("Showing image files in that folder. Pick one, or press Enter to use the path itself.")
                      : root.tr("Material Symbols names, or a path to your own image (/home/you/icon.svg). Press Enter to use what you typed.")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.withAlpha(Theme.surfaceVariantText, 0.9)
                wrapMode: Text.WordWrap
            }
        }
    }
}
