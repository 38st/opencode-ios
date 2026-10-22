#if os(iOS)
import UIKit
import SwiftUI

/// Only the one active editor is hosted. Code rows remain native drawn cells.
final class CodeEditorCell: UICollectionViewCell {
    private var host: UIHostingController<AnyView>?
    private var split = false
    private var oldSide = false
    func configure(_ content: AnyView, split: Bool, oldSide: Bool) {
        self.split = split; self.oldSide = oldSide; setNeedsLayout()
        if let host { host.rootView = content; return }
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        host.view.backgroundColor = UIColor(OCColor.background)
        contentView.addSubview(host.view)
        self.host = host
        attachHost()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { host?.willMove(toParent: nil); host?.removeFromParent() }
        else { attachHost() }
    }
    private func attachHost() {
        guard let host, host.parent == nil else { return }
        var responder: UIResponder? = next
        while let current = responder {
            if let parent = current as? UIViewController {
                parent.addChild(host); host.didMove(toParent: parent); return
            }
            responder = current.next
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let columnWidth = split ? bounds.width / 2 : bounds.width
        host?.view.frame = CGRect(x: split && !oldSide ? columnWidth : 0, y: 0, width: min(400, columnWidth), height: bounds.height)
    }
}

final class CodeImageCell: UICollectionViewCell {
    private let image = UIImageView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        image.contentMode = .scaleAspectFit
        contentView.addSubview(image)
        isAccessibilityElement = true
        accessibilityLabel = "Image preview"
    }
    required init?(coder: NSCoder) { nil }
    func configure(_ data: Data?) { image.image = data.flatMap { UIImage(data: $0) } }
    override func layoutSubviews() { super.layoutSubviews(); image.frame = contentView.bounds.insetBy(dx: 12, dy: 12) }
}
#endif
