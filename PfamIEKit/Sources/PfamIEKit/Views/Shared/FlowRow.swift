import SwiftUI

/// A layout that wraps its subviews onto as many lines as they need.
///
/// Chips are the app's main currency and there is no stock SwiftUI layout that
/// wraps them: `HStack` overflows and `LazyVGrid` forces a column width that a
/// name like "PK_Tyr_Ser-Thr" does not respect.
public struct FlowRow: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } +
            lineSpacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, max(widest, 0)), height: height)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = layout(subviews: subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var range: Range<Int>
        var width: CGFloat
        var height: CGFloat
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var start = 0
        var x: CGFloat = 0
        var height: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let advance = size.width + (x > 0 ? spacing : 0)
            if x + advance > width && index > start {
                rows.append(Row(range: start..<index, width: x, height: height))
                start = index
                x = size.width
                height = size.height
            } else {
                x += advance
                height = max(height, size.height)
            }
        }
        if start < subviews.count {
            rows.append(Row(range: start..<subviews.count, width: x, height: height))
        }
        return rows
    }
}
