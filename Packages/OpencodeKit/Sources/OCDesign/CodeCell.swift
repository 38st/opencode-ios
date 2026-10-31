#if os(iOS)
import UIKit
import SwiftUI
import OCRender
import OCModels

final class CodeCell: UICollectionViewCell {
    private var row = DiffRow(id: 0)
    private var split = false, wrap = true
    private var fontSize: CGFloat = 13, offset: CGFloat = 0
    private var gutter: CGFloat = 76
    private var source = false
    private var left = NSAttributedString(), right = NSAttributedString()
    private var selection: LineSelection?
    private var comments: [LineComment] = []
    private var matches: [NSRange] = []
    private var currentMatch: CodeSearchMatch?
    private let more = UIButton(type: .system)
    var comment: ((LineSelection.Side) -> Void)?
    var extend: ((LineSelection.Side) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = true; isAccessibilityElement = true; contentView.isHidden = true
        more.setImage(UIImage(named: "dot-grid", in: .module, compatibleWith: nil), for: .normal)
        more.tintColor = UIColor(OCColor.iconMuted); more.showsMenuAsPrimaryAction = true
        more.accessibilityLabel = localized("More options"); addSubview(more)
    }
    required init?(coder: NSCoder) { nil }
    func configure(_ row: DiffRow, split: Bool, wrap: Bool, fontSize: CGFloat, offset: CGFloat, selected: LineSelection?, comments: [LineComment], gutter: CGFloat, source: Bool, matches: [NSRange], currentMatch: CodeSearchMatch?) {
        self.gutter = gutter; self.source = source
        self.row = row; self.split = split; self.wrap = wrap; self.fontSize = fontSize; self.offset = offset; selection = selected; self.comments = comments
        self.matches = matches; self.currentMatch = currentMatch
        more.isHidden = row.commentID == nil
        left = attributed(row.left); right = attributed(row.right)
        let line = row.right ?? row.left
        let number = line?.newLine ?? line?.oldLine ?? 0, text = line?.text ?? ""
        accessibilityLabel = row.label ?? (line?.kind == .addition ? localized("Line \(number), added, \(text)", comment: "Diff line; %lld is the line number, %@ its text") : line?.kind == .deletion ? localized("Line \(number), deleted, \(text)", comment: "Diff line; %lld is the line number, %@ its text") : localized("Line \(number), context, \(text)", comment: "Unchanged diff line; %lld is the line number, %@ its text"))
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: localized("Comment on line")) { [weak self] _ in self?.comment?(line?.kind == .deletion ? .deletions : .additions); return true },
            UIAccessibilityCustomAction(name: localized("Extend selection to this line")) { [weak self] _ in self?.extend?(line?.kind == .deletion ? .deletions : .additions); return true },
            UIAccessibilityCustomAction(name: localized("Copy line")) { _ in OCCopy.text(line?.text ?? ""); return true }
        ]
        if split, let deleted = row.left, deleted.oldLine != nil {
            accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: localized("Comment on deleted line")) { [weak self] _ in self?.comment?(.deletions); return true })
            accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: localized("Extend selection to deleted line")) { [weak self] _ in self?.extend?(.deletions); return true })
            accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: localized("Copy deleted line")) { _ in OCCopy.text(deleted.text); return true })
            accessibilityLabel = localized("Old line \(deleted.oldLine ?? 0), \(deleted.text). \(accessibilityLabel ?? "")", comment: "Split diff row; %1$lld is the old line number, %2$@ its text, %3$@ the new line's description")
        }
        setNeedsDisplay()
    }
    func commentActions(edit: @escaping () -> Void, delete: @escaping () -> Void) {
        more.menu = UIMenu(title: localized("More options"), children: [UIAction(title: localized("Edit", comment: "Menu action that edits a line comment")) { _ in edit() }, UIAction(title: localized("Delete", comment: "Menu action that deletes a line comment"), attributes: .destructive) { _ in delete() }])
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: localized("Edit", comment: "Menu action that edits a line comment")) { _ in edit(); return true }, UIAccessibilityCustomAction(name: localized("Delete", comment: "Menu action that deletes a line comment")) { _ in delete(); return true }]
    }
    func contextActions(above: @escaping () -> Void, below: @escaping () -> Void, all: @escaping () -> Void) {
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: localized("Expand 20 lines above")) { _ in above(); return true },
            UIAccessibilityCustomAction(name: localized("Expand 20 lines below")) { _ in below(); return true },
            UIAccessibilityCustomAction(name: localized("Expand all", comment: "Reveals every hidden unchanged line in a diff")) { _ in all(); return true },
        ]
    }
    func fileAction(_ open: @escaping () -> Void) {
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: localized("Open file")) { _ in open(); return true }]
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        more.frame = CGRect(x: commentFrame.maxX - 44, y: 4, width: 44, height: 44)
    }
    private var font: UIFont { OCFonts.register(); return UIFont(name: "JetBrainsMonoNFM-Regular", size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    private func attributed(_ line: DiffLine?) -> NSAttributedString {
        guard let line else { return NSAttributedString() }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = wrap ? .byCharWrapping : .byClipping
        paragraph.minimumLineHeight = max(24, ceil(fontSize * 1.65)); paragraph.maximumLineHeight = paragraph.minimumLineHeight
        let value = NSMutableAttributedString(string: line.displayText, attributes: [.font: font, .foregroundColor: UIColor(OCColor.text), .paragraphStyle: paragraph])
        func displayRange(_ range: NSRange) -> NSRange? {
            guard let r = Range(range, in: line.text) else { return nil }
            let before = String(line.text[..<r.lowerBound]).replacingOccurrences(of: "\t", with: "  ")
            let content = String(line.text[r]).replacingOccurrences(of: "\t", with: "  ")
            return NSRange(location: before.utf16.count, length: content.utf16.count)
        }
        for span in line.syntax { if let range = displayRange(span.range), NSMaxRange(range) <= value.length { value.addAttribute(.foregroundColor, value: color(span.kind), range: range) } }
        for span in line.words { if let range = displayRange(span), NSMaxRange(range) <= value.length {
            value.addAttribute(.backgroundColor, value: UIColor(line.kind == .addition ? OCColor.diffAddStrong : OCColor.diffRemoveStrong), range: range)
            value.addAttribute(.foregroundColor, value: UIColor(line.kind == .addition ? OCColor.diffAddText : OCColor.diffRemoveText), range: range)
        } }
        for match in matches { if let range = displayRange(match), NSMaxRange(range) <= value.length {
            let active = currentMatch?.line == line.newLine && currentMatch?.range == match
            value.addAttribute(.backgroundColor, value: UIColor(OCColor.warning).withAlphaComponent(active ? 0.55 : 0.25), range: range)
        } }
        return value
    }
    override func draw(_ rect: CGRect) {
        UIColor(OCColor.backgroundDeep).setFill(); UIRectFill(bounds)
        if let label = row.label {
            if row.commentID != nil {
                let card = commentFrame
                let shape = UIBezierPath(roundedRect: card, cornerRadius: 6)
                UIColor(OCColor.layer1).setFill(); shape.fill()
                UIColor(OCColor.border).setStroke(); shape.lineWidth = 0.5; shape.stroke()
                let parts = label.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let body = parts.count > 1 ? String(parts[1]) : label
                let meta = parts.count > 1 ? String(parts[0]) : localized("Comment", comment: "Noun: label on a line comment card")
                let bodyFont = UIFont(name: "Inter-Regular", size: fontSize) ?? font
                let metaFont = UIFont(name: "Inter-Regular", size: max(11, fontSize * 11 / 13)) ?? font
                let area = CGRect(x: card.minX + 12, y: card.minY + 12, width: max(1, card.width - 68), height: card.height - 24)
                let bodySize = (body as NSString).boundingRect(with: CGSize(width: area.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: bodyFont], context: nil).size
                (body as NSString).draw(in: CGRect(origin: area.origin, size: CGSize(width: area.width, height: ceil(bodySize.height))), withAttributes: [.font: bodyFont, .foregroundColor: UIColor(OCColor.text)])
                (meta as NSString).draw(in: CGRect(x: area.minX, y: area.minY + ceil(bodySize.height) + 8, width: area.width, height: metaFont.lineHeight), withAttributes: [.font: metaFont, .foregroundColor: UIColor(OCColor.textFaint)])
                accessibilityHint = localized("More options: Edit or Delete")
                return
            }
            let area = row.commentID == nil ? bounds.insetBy(dx: 12, dy: 3) : commentFrame.insetBy(dx: 12, dy: 12)
            let labelFont = row.commentID == nil ? font : UIFont(name: "Inter-Regular", size: fontSize) ?? font
            let display = DiffPlaceholder.opensFile(label) ? label + "  ·  " + localized("Open file") : label
            (display as NSString).draw(in: area, withAttributes: [.font: labelFont, .foregroundColor: UIColor(OCColor.textMuted)])
            return
        }
        let width = split ? bounds.width / 2 : bounds.width
        draw(row.left, attributed: left, in: CGRect(x: 0, y: 0, width: width, height: bounds.height), old: split)
        if split { draw(row.right, attributed: right, in: CGRect(x: width, y: 0, width: width, height: bounds.height), old: false) }
    }
    private var commentFrame: CGRect {
        let width = split ? bounds.width / 2 : bounds.width
        return CGRect(x: (split && !row.commentOnOldSide ? width : 0) + 12, y: 4, width: min(400, width - 24), height: bounds.height - 8)
    }
    private func draw(_ line: DiffLine?, attributed: NSAttributedString, in rect: CGRect, old: Bool) {
        guard let line else { return }
        let tint = line.kind == .addition ? OCColor.diffAddWeak : line.kind == .deletion ? OCColor.diffRemoveWeak : OCColor.backgroundDeep
        UIColor(tint).setFill(); UIRectFillUsingBlendMode(rect, .normal)
        let number = old ? line.oldLine : line.newLine ?? line.oldLine
        let oldSide = split ? old : line.kind == .deletion
        func contains(_ selection: LineSelection) -> Bool {
            guard let number, selection.side != selection.endSide || (selection.side == .deletions) == oldSide else { return false }
            return (oldSide ? selection.lower...selection.upper : selection.newRange).contains(number)
        }
        let marked = selection.map(contains) == true || comments.contains(where: { $0.selection.map(contains) ?? false })
        if marked {
            UIColor(OCColor.accentBackground).withAlphaComponent(0.2).setFill(); UIRectFillUsingBlendMode(rect, .normal)
        }
        if line.kind == .addition || line.kind == .deletion {
            UIColor(line.kind == .addition ? OCColor.diffAddNumber : OCColor.diffRemoveNumber).setFill(); UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height))
        }
        let p = NSMutableParagraphStyle(); p.alignment = .right
        let numberColor = marked ? OCColor.accent : line.kind == .addition ? OCColor.diffAddNumber : line.kind == .deletion ? OCColor.diffRemoveNumber : OCColor.textFaint
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(numberColor), .paragraphStyle: p]
        if split || source {
            ((number.map(String.init) ?? "") as NSString).draw(in: CGRect(x: rect.minX + 4, y: 3, width: gutter - 12, height: rect.height), withAttributes: attributes)
        } else {
            let column = (gutter - 20) / 2
            for (index, number) in [line.oldLine, line.newLine].enumerated() {
                ((number.map(String.init) ?? "") as NSString).draw(in: CGRect(x: rect.minX + 4 + CGFloat(index) * column, y: 3, width: column - 4, height: rect.height), withAttributes: attributes)
            }
        }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); context.clip(to: CGRect(x: rect.minX + gutter, y: 0, width: max(0, rect.width - gutter), height: rect.height))
        attributed.draw(with: CGRect(x: rect.minX + gutter - (wrap ? 0 : offset), y: 0, width: wrap ? max(1, rect.width - gutter) : max(rect.width, CGFloat(attributed.length) * fontSize), height: rect.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        context.restoreGState()
    }
    private func color(_ kind: HighlightSpan.Kind) -> UIColor {
        let value: Color = switch kind { case .comment: OCColor.syntaxComment; case .keyword: OCColor.syntaxKeyword; case .string: OCColor.syntaxString; case .number: OCColor.syntaxConstant; case .type: OCColor.syntaxType; case .property: OCColor.syntaxProperty; case .punctuation: OCColor.syntaxPunctuation }
        return UIColor(value)
    }
}

final class CodeHeader: UICollectionReusableView {
    private let toggle = UIButton(type: .system), open = UIButton(type: .system)
    private var toggled: (() -> Void)?, opened: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = UIColor(OCColor.band)
        addSubview(toggle); addSubview(open)
        toggle.addTarget(self, action: #selector(toggleAction), for: .touchUpInside)
        open.addTarget(self, action: #selector(openAction), for: .touchUpInside)
        toggle.contentHorizontalAlignment = .leading; open.contentHorizontalAlignment = .leading
    }
    required init?(coder: NSCoder) { nil }
    func configure(title: String, summary: String, expanded: Bool, toggle: @escaping () -> Void, open: @escaping () -> Void) {
        OCFonts.register()
        let font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: UIFont(name: "Inter-Regular", size: 13) ?? .preferredFont(forTextStyle: .footnote))
        self.toggle.titleLabel?.font = font; self.open.titleLabel?.font = font
        self.toggle.setTitleColor(UIColor(OCColor.text), for: .normal); self.open.setTitleColor(UIColor(OCColor.textMuted), for: .normal)
        self.toggle.setImage(UIImage(named: expanded ? "chevron-down" : "chevron-right", in: .module, compatibleWith: nil), for: .normal)
        self.toggle.tintColor = UIColor(OCColor.textMuted)
        self.toggle.imageView?.contentMode = .scaleAspectFit
        self.toggle.titleLabel?.lineBreakMode = .byTruncatingMiddle
        self.open.isHidden = !expanded
        self.toggle.accessibilityValue = expanded ? localized("Expanded") : localized("Collapsed")
        self.toggle.setTitle(title, for: .normal); self.open.setTitle(summary + "  ·  " + localized("Open file"), for: .normal)
        self.toggle.accessibilityLabel = summary.isEmpty ? title : localized("\(title), \(summary)", comment: "Diff file header; %1$@ is the file path, %2$@ its change summary"); self.toggle.accessibilityIdentifier = title; self.open.accessibilityLabel = localized("Open file \(title)", comment: "%@ is a file path")
        toggled = toggle; opened = open; setNeedsLayout()
    }
    override func layoutSubviews() { super.layoutSubviews(); toggle.frame = CGRect(x: 12, y: 0, width: bounds.width - 24, height: 44); open.frame = CGRect(x: 12, y: 44, width: bounds.width - 24, height: 44) }
    @objc private func toggleAction() { toggled?() }
    @objc private func openAction() { opened?() }
}
#endif
