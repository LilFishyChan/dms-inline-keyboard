// 同一组设置项的容器：组内卡片紧挨着（间距很小），组与组之间由外层 Column 的 spacing 隔开。
// 内容放进内部 Column，default property 不能 alias 到自己。
import QtQuick
import qs.Common

Item {
    id: root

    default property alias content: inner.data

    width: parent.width
    height: inner.implicitHeight

    Column {
        id: inner

        width: parent.width
        spacing: Theme.groupedListGap
        // 组内卡片挨在一起：首张只圆上面两个角，末张只圆下面两个角，中间四角都小
        onChildrenChanged: {
            const n = children.length;
            for (let i = 0; i < n; i++) {
                const c = children[i];
                if (c.topLeftRadius === undefined)
                    continue;

                const first = i === 0;
                const last = i === n - 1;
                c.radius = 0;
                c.topLeftRadius = first ? Theme.cornerRadiusM : Theme.cornerRadiusXS;
                c.topRightRadius = c.topLeftRadius;
                c.bottomLeftRadius = last ? Theme.cornerRadiusM : Theme.cornerRadiusXS;
                c.bottomRightRadius = c.bottomLeftRadius;
            }
        }
    }

}
