// 分组标题：直接复用 DMS 的 SettingsSectionLabel。
//
// 自己画过一版（12px、无上下 gap、无 Accessible），和 DMS 卡片标题的层级差一档；
// 换成现成的之后字号、间距、读屏角色都和系统设置页一致。

import QtQuick
import qs.Modules.Settings.Widgets

SettingsSectionLabel {
    id: root
}
