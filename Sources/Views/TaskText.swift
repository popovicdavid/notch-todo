import SwiftUI
import AppKit

extension Section {
    var color: Color {
        switch self {
        case .viktig: .orange
        case .frister: .pink
        case .generelle: .cyan
        case .senere: .purple
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

// Menyvalg med en closure i stedet for target/action.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) brukes ikke") }

    @objc private func run() { handler() }
}

// Datobrikke som på iPhone: sterkere farge når det er tre dager eller mindre igjen.
struct DueChipView: View {
    let chip: DueChip
    let color: Color

    var body: some View {
        Text(chip.label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(chip.urgent ? Color(red: 1, green: 0.56, blue: 0.64) : color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(chip.urgent ? 0.32 : 0.15)))
    }
}

// Oppgaveteksten. En tekstvisning fra AppKit, så teksten kan markeres og kopieres, mens dobbeltklikk fortsatt redigerer
// (SwiftUI sin markerbare tekst sluker dobbeltklikket). Markdown (fet, kursiv, kode, lenker) vises som før.
struct TaskText: NSViewRepresentable {
    let text: String
    let done: Bool
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onCopy: () -> Void
    let onCopySection: () -> Void

    func makeNSView(context: Context) -> TaskTextView {
        let v = TaskTextView(usingTextLayoutManager: false)
        v.isEditable = false
        v.isSelectable = true
        v.isRichText = true
        v.drawsBackground = false
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0
        v.textContainer?.widthTracksTextView = true
        v.isVerticallyResizable = false
        v.isHorizontallyResizable = false
        v.selectedTextAttributes = [.backgroundColor: NSColor.white.withAlphaComponent(0.25)]
        v.linkTextAttributes = [.foregroundColor: NSColor.systemBlue, .cursor: NSCursor.pointingHand]
        return v
    }

    func updateNSView(_ v: TaskTextView, context: Context) {
        v.onClick = onClick
        v.onDoubleClick = onDoubleClick
        v.onCopy = onCopy
        v.onCopySection = onCopySection
        let key = "\(done)|\(text)"
        if v.shown != key {
            v.shown = key
            v.textStorage?.setAttributedString(Self.attributed(text, done: done))
        }
    }

    // Målingen huskes til teksten eller bredden endres, så den ikke gjøres på nytt ved hver tegning.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: TaskTextView, context: Context) -> CGSize? {
        guard let lm = v.layoutManager, let tc = v.textContainer else { return nil }
        let fixed = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        if let m = v.measured, m.width == fixed, m.key == v.shown { return m.size }
        tc.containerSize = NSSize(width: fixed ?? 10_000, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let size = CGSize(width: fixed ?? ceil(used.width), height: max(ceil(used.height), 15))
        v.measured = (fixed, v.shown, size)
        return size
    }

    static func attributed(_ text: String, done: Bool) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: 12.5)
        let color = done ? NSColor.white.withAlphaComponent(0.4) : NSColor.white
        let md = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let out = NSMutableAttributedString()
        for run in md.runs {
            var font = base
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if intent.contains(.code) { font = .monospacedSystemFont(ofSize: 11.5, weight: .regular) }
            }
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let link = run.link { attrs[.link] = link }
            if done { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: String(md[run.range].characters), attributes: attrs))
        }
        return out
    }
}

final class TaskTextView: NSTextView {
    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onCopy: () -> Void = {}
    var onCopySection: () -> Void = {}
    var shown = ""
    var measured: (width: CGFloat?, key: String, size: CGSize)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick(); return }
        onClick()
        super.mouseDown(with: event)
    }

    // Høyreklikk: kopier markert tekst hvis noe er markert, ellers hele oppgaven.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if selectedRange().length > 0 {
            menu.addItem(ClosureMenuItem("Kopier") { [weak self] in self?.copy(nil) })
        } else {
            menu.addItem(ClosureMenuItem("Kopier", handler: onCopy))
        }
        menu.addItem(ClosureMenuItem("Kopier hele seksjonen", handler: onCopySection))
        return menu
    }
}
