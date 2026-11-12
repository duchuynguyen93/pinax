import AppKit

/// Chấm tag màu kiểu Finder: tối đa 3 chấm 8 pt chồng nhau 3 pt, viền 1 pt màu nền để tách chấm.
final class TagDotsView: NSView {
    static let dot: CGFloat = 8, step: CGFloat = 5, maxDots = 3, height: CGFloat = 10

    var tags: [String] = [] {
        didSet {
            guard tags != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
            isHidden = count == 0
        }
    }

    /// Thu về 0 pt (ô đang đổi tên tại chỗ).
    var collapsed = false {
        didSet {
            guard collapsed != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
            isHidden = count == 0
        }
    }

    override var isFlipped: Bool { true }

    var count: Int { collapsed ? 0 : min(tags.count, Self.maxDots) }

    override var intrinsicContentSize: NSSize {
        guard count > 0 else { return NSSize(width: 0, height: Self.height) }
        return NSSize(width: Self.dot + Self.step * CGFloat(count - 1) + 2, height: Self.height)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Vẽ từ chấm cuối lên chấm đầu: tag đầu nằm trên cùng.
        for i in stride(from: count - 1, through: 0, by: -1) {
            let rect = NSRect(x: 1 + Self.step * CGFloat(i), y: 1, width: Self.dot, height: Self.dot)
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1)).fill()
            TagSupport.color(forTagNamed: tags[i]).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }
}
