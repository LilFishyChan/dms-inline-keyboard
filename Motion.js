// 动画时长（毫秒）。改手感只改这里。
//
// 按用途分组，不是按数值大小：同为「位移」，功能栏让位是 160、动作列表是 140 ——
// 列表位移距离更短，快一点才跟手，压成同一个值会让两边手感变得一样。
// 缓动没有放进来的必要：全仓库 26 处都是 OutCubic，本来就没有分叉。
//
// 用法：import "Motion.js" as Motion → duration: Motion.shift

// 点按反馈：按住时的高亮收敛
const quick = 90

// 颜色、缩放这类微交互
const micro = 120

// 淡入淡出
const fade = 140

// 功能栏让位：动作块的 x / width 滑动
const shift = 160

// 动作列表让位（位移距离比功能栏短，快一点）
const listShift = 140

// 拖动幽灵块退出
const ghost = 180

// 面板 / 候选栏展开
const expand = 200

// 整块面板切换（动作列表整体滑出、抽屉）
const panel = 220
