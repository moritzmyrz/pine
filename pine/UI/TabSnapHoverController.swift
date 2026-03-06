import CoreGraphics
import Foundation

struct TabSnapHoverController {
    private let edgeThresholdRatio: CGFloat = 0.3

    func splitSide(for location: CGPoint, in size: CGSize) -> SplitDropSide {
        let safeWidth = max(size.width, 1)
        let safeHeight = max(size.height, 1)
        let x = location.x
        let y = location.y

        let leftThreshold = safeWidth * edgeThresholdRatio
        let rightThreshold = safeWidth * (1 - edgeThresholdRatio)
        let bottomThreshold = safeHeight * edgeThresholdRatio
        let topThreshold = safeHeight * (1 - edgeThresholdRatio)

        let candidates: [(SplitDropSide, CGFloat)] = [
            (.left, abs(x)),
            (.right, abs(safeWidth - x)),
            (.bottom, abs(y)),
            (.top, abs(safeHeight - y))
        ]

        let inLeft = x <= leftThreshold
        let inRight = x >= rightThreshold
        let inBottom = y <= bottomThreshold
        let inTop = y >= topThreshold
        guard inLeft || inRight || inBottom || inTop else {
            return .none
        }

        let allowed = candidates.filter { candidate in
            switch candidate.0 {
            case .left: return inLeft
            case .right: return inRight
            case .bottom: return inBottom
            case .top: return inTop
            case .none: return false
            }
        }

        return allowed.min(by: { $0.1 < $1.1 })?.0 ?? .none
    }
}
