import SwiftUI
import AppKit

// Stien til todo-filen står i ~/.config/notch-todo/path (én linje). Uten den brukes ~/todo.md.
let todoPath: String = {
    let home = NSHomeDirectory() as NSString
    let config = home.appendingPathComponent(".config/notch-todo/path")
    if let line = try? String(contentsOfFile: config, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
        return (line as NSString).expandingTildeInPath
    }
    return home.appendingPathComponent("todo.md")
}()

// MARK: - Data

enum Section: String, CaseIterable {
    case viktig = "Viktig"
    case frister = "Frister"
    case generelle = "Generelle"

    // «Flytt»-knappen går til neste seksjon rundt i ring.
    var other: Section {
        let all = Section.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

// Datoen (YYYY-MM-DD) etter «frist» eller «innen» i teksten, ellers første dato. Brukes til å sortere Frister.
func deadline(in text: String) -> String? {
    for pattern in [#"(?:frist|innen)\s+(?:ca\.\s*)?(\d{4}-\d{2}-\d{2})"#, #"(\d{4}-\d{2}-\d{2})"#] {
        if let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
           let d = text[r].range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(text[r][d])
        }
    }
    return nil
}

struct TodoItem: Identifiable {
    let id = UUID()
    var text: String
    var done: Bool
    var section: Section
}

final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = []
    private var lastMod: Date?

    init() {
        if !FileManager.default.fileExists(atPath: todoPath) {
            try? "# Todo\n\n".write(toFile: todoPath, atomically: true, encoding: .utf8)
        }
        load()
    }

    var openCount: Int { items.filter { !$0.done }.count }

    // Åpne oppgaver først, avkryssede nederst.
    func items(in section: Section) -> [TodoItem] {
        let all = items.filter { $0.section == section }
        var open = all.filter { !$0.done }
        // Frister: tidligste dato først, uten dato nederst (sorteringen er stabil).
        if section == .frister {
            open.sort { (deadline(in: $0.text) ?? "9999") < (deadline(in: $1.text) ?? "9999") }
        }
        return open + all.filter { $0.done }
    }
    func openCount(in section: Section) -> Int { items(in: section).filter { !$0.done }.count }

    private func modDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: todoPath))?[.modificationDate] as? Date
    }

    func reloadIfChanged() {
        if modDate() != lastMod { load() }
    }

    func load() {
        lastMod = modDate()
        guard let text = try? String(contentsOfFile: todoPath, encoding: .utf8) else { items = []; return }
        // Oppgaver under «## Generelle» og «## Frister» får egne kolonner, alt annet havner i «Viktig».
        var section = Section.viktig
        var parsed: [TodoItem] = []
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") {
                let name = t.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                section = name.hasPrefix("generell") ? .generelle : name.hasPrefix("frist") ? .frister : .viktig
                continue
            }
            for (prefix, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] where t.hasPrefix(prefix) {
                parsed.append(TodoItem(text: String(t.dropFirst(prefix.count)), done: done, section: section))
            }
        }
        items = parsed
    }

    func save() {
        var out = "# Todo\n"
        for section in Section.allCases {
            out += "\n## \(section.rawValue)\n\n"
            for item in items(in: section) { out += "- [\(item.done ? "x" : " ")] \(item.text)\n" }
        }
        try? out.write(toFile: todoPath, atomically: true, encoding: .utf8)
        lastMod = modDate()
    }

    func add(_ text: String, to section: Section) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        items.append(TodoItem(text: t, done: false, section: section))
        save()
    }

    func move(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].section = items[i].section.other
        save()
    }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: i)
        item.done.toggle()
        items.append(item)  // havner nederst blant åpne eller avkryssede
        save()
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id }; save() }
    func clearDone() { items.removeAll { $0.done }; save() }
}

// MARK: - Visning

final class NotchModel: ObservableObject {
    @Published var hovering = false
    @Published var open = false
    @Published var large = false
}

enum Layout {
    static let openSize = CGSize(width: 800, height: 330)
    static let largeSize = CGSize(width: 1120, height: 620)
    static let hoverExtra = CGSize(width: 150, height: 26)  // 6 rundt notchen + 20 til klokka
}

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TodoStore
    let notch: CGSize
    let onOpen: () -> Void
    let onClose: () -> Void

    @State private var newText: [Section: String] = [:]
    @State private var hoveredRow: UUID?
    @FocusState private var focusedField: Section?

    private var size: CGSize {
        if model.open { return model.large ? Layout.largeSize : Layout.openSize }
        if model.hovering {
            return CGSize(width: notch.width + Layout.hoverExtra.width, height: notch.height + Layout.hoverExtra.height)
        }
        return notch
    }

    private var radius: CGFloat { model.open ? 24 : 10 }

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(model.open ? 0.45 : 0), radius: 14, y: 6)

            if model.open {
                openContent
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            } else if model.hovering {
                hoverContent
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.open)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.large)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.hovering)
        .onChange(of: model.open) { _, open in
            if open {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focusedField = .viktig }
            }
        }
        .preferredColorScheme(.dark)
    }

    // Viktige til venstre, generelle til høyre – på hver sin side av kameraet.
    private var hoverContent: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Label("\(store.openCount(in: .viktig))", systemImage: "exclamationmark.circle")
                    Label("\(store.openCount(in: .frister))", systemImage: "calendar")
                }
                Spacer()
                Label("\(store.openCount(in: .generelle))", systemImage: "repeat")
            }
            .labelStyle(CompactLabel())
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: notch.height + 6)

            NorwayClock()
                .frame(height: 20)
        }
    }

    private var openContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { model.large.toggle() } label: {
                    Image(systemName: model.large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if store.items.contains(where: { $0.done }) {
                    Button { store.clearDone() } label: {
                        Text("Fjern ferdige")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(height: 18)
            .overlay { NorwayClock() }

            HStack(alignment: .top, spacing: 14) {
                column(.viktig, color: .orange)
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                column(.frister, color: .pink)
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                column(.generelle, color: .cyan)
            }
        }
        .foregroundStyle(.white)
        .contextMenu {
            Button("Avslutt NotchTodo") { NSApp.terminate(nil) }
        }
        .padding(.top, notch.height + 4)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func column(_ section: Section, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(section.rawValue).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
                Text("\(store.openCount(in: section)) igjen").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    if store.items(in: section).isEmpty {
                        Text("Tomt 🎉").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    }
                    ForEach(store.items(in: section)) { item in row(item, color: color) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("Ny oppgave …", text: Binding(
                get: { newText[section, default: ""] },
                set: { newText[section] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.09)))
            .focused($focusedField, equals: section)
            .onSubmit {
                store.add(newText[section, default: ""], to: section)
                newText[section] = ""
                focusedField = section
            }
            .onExitCommand { onClose() }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ item: TodoItem, color: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Button { store.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.done ? Color.green : color.opacity(0.8))
            }
            .buttonStyle(.plain)

            Text(LocalizedStringKey(item.text))
                .font(.system(size: 12.5))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? Color.white.opacity(0.4) : Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hoveredRow == item.id {
                Button { store.move(item.id) } label: {
                    Image(systemName: "arrow.right").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .help("Flytt til \(item.section.other.rawValue)")

                Button { store.remove(item.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Slett")
            }
        }
        .contentShape(Rectangle())
        .onHover { h in
            if h { hoveredRow = item.id } else if hoveredRow == item.id { hoveredRow = nil }
        }
    }
}

// Klokka i Norge (følger sommer-/vintertid selv), oppdatert hvert minutt.
struct NorwayClock: View {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Oslo")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 5) {
                Text("Norge").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                Text(Self.formatter.string(from: context.date))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .allowsHitTesting(false)
    }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

// MARK: - Vindu ved notchet

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// Første klikk skal virke selv om panelet ikke er aktivt fra før.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private let model = NotchModel()
    private let store = TodoStore()
    private var screenFrame = NSRect.zero
    private var notch = CGSize(width: 200, height: 32)
    private var timer: Timer?
    private let windowSize = CGSize(width: 1160, height: 660)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notch = CGSize(width: screen.frame.width - l.width - r.width, height: screen.safeAreaInsets.top)
        } else {
            notch = CGSize(width: 200, height: screen.frame.maxY - screen.visibleFrame.maxY)
        }

        let frame = NSRect(x: screenFrame.midX - windowSize.width / 2, y: screenFrame.maxY - windowSize.height,
                           width: windowSize.width, height: windowSize.height)
        panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let view = NotchView(model: model, store: store, notch: notch,
                             onOpen: { [weak self] in self?.open() },
                             onClose: { [weak self] in self?.close() })
        let host = FirstClickHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = host
        panel.orderFrontRegardless()

        // Klikk utenfor (i andre apper) lukker lista.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }

        // Reager bare når musa beveger seg, i stedet for å sjekke hele tiden.
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.tick()
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.tick()
            return event
        }

        // Hvert trykk på notchen åpner eller lukker lista.
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.model.open {
                let notchArea = self.rect(CGSize(width: self.notch.width + 10, height: self.notch.height))
                if notchArea.contains(NSEvent.mouseLocation) { self.close(); return nil }
                return event
            }
            self.tick()
            if self.model.hovering { self.open(); return nil }
            return event
        }
    }

    private func rect(_ s: CGSize) -> NSRect {
        NSRect(x: screenFrame.midX - s.width / 2, y: screenFrame.maxY - s.height, width: s.width, height: s.height + 2)
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let active: NSRect
        if model.open {
            active = rect(model.large ? Layout.largeSize : Layout.openSize)
        } else if model.hovering {
            active = rect(CGSize(width: notch.width + Layout.hoverExtra.width, height: notch.height + Layout.hoverExtra.height))
        } else {
            active = rect(CGSize(width: notch.width + 10, height: notch.height))
        }
        let inside = active.contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if !model.open && inside != model.hovering {
            if inside { store.reloadIfChanged() }
            model.hovering = inside
        }
    }

    private func open() {
        guard !model.open else { return }
        store.reloadIfChanged()
        model.open = true
        panel.makeKeyAndOrderFront(nil)
        // Følg med på endringer i todo.md bare mens lista er åpen.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.store.reloadIfChanged() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func close() {
        guard model.open else { return }
        model.open = false
        model.large = false
        model.hovering = false
        timer?.invalidate()
        timer = nil
        // Gi tastaturet tilbake til appen du var i.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
