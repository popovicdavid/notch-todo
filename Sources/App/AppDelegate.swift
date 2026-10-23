import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private let model = NotchModel()
    private let store = TodoStore(path: todoPath)
    private var activeRect = NSRect.zero  // området der musa holder notchen åpen, regnes ut når tilstanden endres
    private var shrink: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.geometry = currentGeometry()

        panel = NotchPanel(contentRect: panelFrame(), styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let view = NotchView(model: model, store: store, onClose: { [weak self] in self?.close() })
        let host = FirstClickHostingView(rootView: view)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()

        model.onLayoutChange = { [weak self] in self?.layoutChanged() }
        updateActiveRect()

        // Skjermer kobles til eller fra, eller oppløsningen endres: finn notchen og regn ut målene på nytt.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

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
                let g = self.model.geometry
                let notchArea = self.rect(CGSize(width: g.notch.width + 10, height: g.notch.height))
                if notchArea.contains(NSEvent.mouseLocation) { self.close(); return nil }
                return event
            }
            self.tick()
            if self.model.hovering { self.open(); return nil }
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKey(event) ?? event
        }
    }

    // MARK: Skjerm og størrelse

    private func currentGeometry() -> NotchGeometry {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            return model.geometry
        }
        var g = NotchGeometry(screen: screen.frame)
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            g.notch = CGSize(width: screen.frame.width - l.width - r.width, height: screen.safeAreaInsets.top)
        } else {
            g.notch = CGSize(width: 200, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        }
        return g
    }

    @objc private func screensChanged() {
        let g = currentGeometry()
        guard g != model.geometry else { return }
        model.geometry = g
        shrink?.cancel()
        panel.setFrame(panelFrame(), display: true)
    }

    // Størrelsen på den svarte formen i tilstanden vi er i nå.
    private var shapeSize: CGSize {
        if model.open { return model.listSize }
        if model.hovering { return model.geometry.hoverSize }
        return model.geometry.notch
    }

    // Panelet er bare så stort som tilstanden trenger (pluss plass til skyggen), ikke hele tiden 1160 × 660.
    private func panelFrame() -> NSRect {
        let s = shapeSize
        let pad = model.open ? CGSize(width: 30, height: 40) : CGSize(width: 10, height: 10)
        return centered(CGSize(width: s.width + 2 * pad.width, height: s.height + pad.height))
    }

    private func centered(_ size: CGSize) -> NSRect {
        let sf = model.geometry.screen
        return NSRect(x: (sf.midX - size.width / 2).rounded(), y: sf.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func layoutChanged() {
        updateActiveRect()
        guard let panel else { return }
        let target = panelFrame()
        let current = panel.frame
        guard target != current else { return }
        shrink?.cancel()
        // Større: med en gang, så animasjonen har plass. Mindre: etter animasjonen, så den ikke kuttes.
        let grown = centered(CGSize(width: max(target.width, current.width), height: max(target.height, current.height)))
        if grown != current { panel.setFrame(grown, display: true) }
        if grown != target {
            let work = DispatchWorkItem { [weak self] in self?.panel.setFrame(target, display: true) }
            shrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    private func rect(_ s: CGSize) -> NSRect {
        let sf = model.geometry.screen
        return NSRect(x: sf.midX - s.width / 2, y: sf.maxY - s.height, width: s.width, height: s.height + 2)
    }

    private func updateActiveRect() {
        let g = model.geometry
        if model.open {
            activeRect = rect(model.listSize)
        } else if model.hovering {
            activeRect = rect(g.hoverSize)
        } else {
            activeRect = rect(CGSize(width: g.notch.width + 10, height: g.notch.height))
        }
    }

    // MARK: Mus

    // Kjøres ved hver musebevegelse, så den gjør så lite som mulig og endrer bare noe når musa krysser kanten.
    private func tick() {
        let inside = activeRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if !model.open && inside != model.hovering {
            // Mens tellerne vises følger vi med på fila. Ellers gjøres ingenting før neste hover.
            store.live = inside
            if inside { store.refreshIfStale() }
            model.hovering = inside
        }
    }

    private func open() {
        guard !model.open else { return }
        store.live = true
        store.refreshIfStale()
        model.open = true
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        guard model.open else { return }
        store.live = false
        model.open = false
        model.large = false
        model.hovering = false
        model.select(nil)
        model.hover(nil)
        // Gi tastaturet tilbake til appen du var i.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        // Når lista er borte: gi minnet den brukte tilbake til systemet, i stedet for å holde på det til neste gang.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard self?.model.open == false else { return }
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    // MARK: Tastatur

    private func section(of id: UUID) -> Section? { store.item(id)?.section }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard model.open else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        let textView = panel.firstResponder as? NSTextView
        let typing = textView?.isEditable == true
        let hasSelection = (textView?.selectedRange().length ?? 0) > 0

        // cmd+C: markert tekst kopieres som vanlig, ellers oppgaven musa er over eller den som er valgt.
        if flags == .command, key == "c" {
            if hasSelection { return event }
            guard let id = model.hoveredRow ?? model.selected, let item = store.item(id) else { return event }
            Clipboard.copy(item.text)
            return nil
        }

        // cmd+Z / cmd+shift+Z: angre i lista (i et tekstfelt med tekst angrer det skrivingen som vanlig).
        if flags.subtracting(.shift) == .command, key == "z" {
            if typing && !(textView?.string.isEmpty ?? true) { return event }
            let done = flags.contains(.shift) ? store.redo() : store.undo()
            if !done { NSSound.beep() }
            return nil
        }

        guard flags.subtracting([.shift, .numericPad, .function]).isEmpty else { return event }

        if typing {
            // I «Ny oppgave»-feltet: pil opp går inn i lista, Tab går til neste kolonne.
            guard model.editingRow == nil, let field = model.fieldFocus else { return event }
            switch event.keyCode {
            case 126:
                guard let last = store.items(in: field).last else { return event }
                panel.makeFirstResponder(nil)
                model.select(last.id)
            case 48:
                moveColumn(from: field, by: flags.contains(.shift) ? -1 : 1, toField: true)
            default:
                return event
            }
            return nil
        }

        switch event.keyCode {
        case 126: moveSelection(by: -1)
        case 125: moveSelection(by: 1)
        case 48: moveColumn(from: model.selected.flatMap(section(of:)), by: flags.contains(.shift) ? -1 : 1, toField: false)
        case 49, 36, 76:
            guard let id = model.selected else { return event }
            store.toggle(id)
        case 53: close()
        default: return event
        }
        return nil
    }

    private func moveSelection(by step: Int) {
        guard let id = model.selected, let s = section(of: id) else {
            // Ingenting valgt: begynn øverst i første kolonne som har oppgaver.
            let first = model.columns.lazy.compactMap { self.store.items(in: $0).first }.first
            model.select(first?.id)
            return
        }
        let list = store.items(in: s)
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = i + step
        if j >= list.count {
            // Forbi den siste: til «Ny oppgave»-feltet i samme kolonne.
            model.select(nil)
            model.focusRequest = s
        } else if j >= 0 {
            model.select(list[j].id)
        }
    }

    // Til samme plass i neste kolonne, eller til «Ny oppgave» der (fra et tekstfelt, eller hvis kolonnen er tom).
    private func moveColumn(from current: Section?, by step: Int, toField: Bool) {
        let cols = model.columns
        let row = model.selected.flatMap { id in current.flatMap { store.items(in: $0).firstIndex { $0.id == id } } } ?? 0
        let ci = current.flatMap { cols.firstIndex(of: $0) } ?? (step > 0 ? cols.count - 1 : 0)
        let next = cols[(ci + step + cols.count) % cols.count]
        let list = store.items(in: next)
        if list.isEmpty || toField {
            model.select(nil)
            model.focusRequest = next
        } else {
            panel.makeFirstResponder(nil)
            model.select(list[min(row, list.count - 1)].id)
        }
    }
}
