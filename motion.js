// 动画时长。数值是「DMS 默认 250ms 动画速度」下的手感，实际毫秒数按系统设置等比缩放。
//
// 按用途分组，不是按数值大小：同为「位移」，功能栏让位是 160、动作列表是 140 ——
// 列表位移距离更短，快一点才跟手，压成同一个值会让两边手感变得一样。
// 缓动没有放进来的必要：全仓库 26 处都是 OutCubic，本来就没有分叉。
//
// 用法：import "motion.js" as Motion → duration: Motion.dur(Motion.shift)

// 手感基准：下表的毫秒数都是在这个系统动画时长下测的
const BASE = 250

// 点按反馈：按住时的高亮收敛
const quick = 90 / BASE

// 颜色、缩放这类微交互
const micro = 120 / BASE

// 淡入淡出
const fade = 140 / BASE

// 功能栏让位：动作块的 x / width 滑动
const shift = 160 / BASE

// 动作列表让位（位移距离比功能栏短，快一点）
const listShift = 140 / BASE

// 拖动幽灵块退出
const ghost = 180 / BASE

// 面板 / 候选栏展开
const expand = 200 / BASE

// 整块面板切换（动作列表整体滑出、抽屉）
const panel = 220 / BASE

// 按系统动画速度等比缩放：AnimationSpeed.None 时基准为 0，直接落终态
function dur(ratio) {
    return Math.round(Theme.currentAnimationBaseDuration * ratio)
}
