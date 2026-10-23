import Foundation

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

// Tre steder skriver til samme fil (Mac-en, iPhone-widgeten og assistenten). Hver endring leser derfor fila
// på nytt rett før lagring og legger seg oppå det som står der, i stedet for å skrive ut sin egen kopi.
final class TodoStore: ObservableObject {
    @Published private(set) var doc = TodoDocument()

    // Mens lista er åpen leses fila med en gang den endres. Ellers merkes den bare som utdatert til neste hover.
    var live = false
    private var stale = false

    private let path: String
    private var watcher: FileWatcher?
    private var undoStack: [TodoOp] = []
    private var redoStack: [TodoOp] = []

    init(path: String) {
        self.path = path
        // Lag fila bare hvis det ikke ligger noe der i det hele tatt (heller ikke en symlenke til en fil som ikke er lastet ned).
        let fm = FileManager.default
        if !fm.fileExists(atPath: path), (try? fm.destinationOfSymbolicLink(atPath: path)) == nil {
            try? "# Todo\n\n".write(toFile: path, atomically: true, encoding: .utf8)
        }
        load()
        watcher = FileWatcher(path: path) { [weak self] in self?.fileChanged() }
    }

    // Den virkelige fila bak symlenken, så atomisk lagring ikke erstatter selve lenken.
    private var url: URL { URL(fileURLWithPath: path).resolvingSymlinksInPath() }

    // MARK: Lesing

    func items(in section: Section) -> [TodoItem] { doc.ordered(in: section) }
    func openCount(in section: Section) -> Int { doc.items.filter { $0.section == section && !$0.done }.count }
    func item(_ id: UUID) -> TodoItem? { doc.items.first { $0.id == id } }
    var hasDone: Bool { doc.items.contains { $0.done } }

    private func fileChanged() {
        if live { load() } else { stale = true }
    }

    func refreshIfStale() {
        if stale { load() }
    }

    func load() {
        var text: String?
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &error) { u in
            text = try? String(contentsOf: u, encoding: .utf8)
        }
        stale = false
        guard let text else { return }  // behold det vi har hvis fila ikke kan leses akkurat nå
        publish(TodoDocument(parsing: text))
    }

    // Bare publiser når noe faktisk er endret, så visningen ikke tegnes på nytt for ingenting.
    private func publish(_ fresh: TodoDocument) {
        var fresh = fresh
        fresh.adoptIDs(from: doc)
        if fresh != doc { doc = fresh }
    }

    // MARK: Endringer

    func add(_ text: String, to section: Section) {
        record(.insert(text: text, done: false, section: section, before: nil))
    }

    func toggle(_ id: UUID) {
        guard let item = item(id), let r = doc.ref(for: id) else { return }
        record(.setDone(r, !item.done, before: nil))
    }

    func edit(_ id: UUID, to text: String) {
        guard let item = item(id), let r = doc.ref(for: id),
              item.text != text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        record(.edit(r, text))
    }

    func remove(_ id: UUID) {
        guard let r = doc.ref(for: id) else { return }
        record(.remove(r))
    }

    // Flytter til en seksjon, rett foran en annen oppgave eller nederst.
    func move(_ id: UUID, to section: Section, before: UUID? = nil) {
        guard let r = doc.ref(for: id) else { return }
        record(.move(r, to: section, before: before.flatMap(doc.ref(for:))))
    }

    func clearDone() {
        // Bakfra, så pekerne til like oppgaver lenger opp fortsatt stemmer.
        let refs = doc.items.indices.filter { doc.items[$0].done }.reversed().map { doc.ref(at: $0) }
        guard !refs.isEmpty else { return }
        record(.batch(refs.map { .remove($0) }))
    }

    @discardableResult
    func undo() -> Bool {
        guard let op = undoStack.popLast() else { return false }
        if let back = perform(op) { redoStack.append(back) }
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let op = redoStack.popLast() else { return false }
        if let back = perform(op) { undoStack.append(back) }
        return true
    }

    private func record(_ op: TodoOp) {
        guard let back = perform(op) else { return }
        undoStack.append(back)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    // Les fila på nytt, legg endringen oppå og skriv, alt mens fila er låst for andre som bruker NSFileCoordinator (iCloud).
    private func perform(_ op: TodoOp) -> TodoOp? {
        var undo: TodoOp?
        var result: TodoDocument?
        var error: NSError?
        let lastSeen = doc
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &error) { u in
            let text = try? String(contentsOf: u, encoding: .utf8)
            // Kan ikke fila leses (eller er den helt tom), bygger vi på det vi sist så, så ingenting forsvinner.
            var fresh = text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : TodoDocument(parsing: $0) }
                ?? lastSeen
            undo = fresh.apply(op)
            let out = fresh.serialized()
            if out != text {
                do { try out.write(to: u, atomically: true, encoding: .utf8) } catch { NSLog("NotchTodo: kunne ikke lagre: \(error)") }
            }
            result = fresh
        }
        if let error { NSLog("NotchTodo: fila er opptatt: \(error)") }
        if let result { publish(result) }
        return undo
    }
}

// Følger med på todo-fila uten å spørre hvert sekund. Fila er ofte en symlenke til iCloud Drive og byttes ut i sin helhet
// når noen lagrer (ny fil med samme navn), så vi følger lenken og åpner den nye fila når den gamle forsvinner.
final class FileWatcher {
    private let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var retryDelay: TimeInterval = 1
    private var missing = false

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        start()
    }

    deinit { source?.cancel() }

    private func start() {
        source?.cancel()
        source = nil
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let fd = open(target, O_EVTONLY)
        guard fd >= 0 else {
            // Fila finnes ikke akkurat nå (f.eks. midt i en lagring). Prøv igjen litt senere, sjeldnere og sjeldnere.
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in self?.start() }
            retryDelay = min(retryDelay * 2, 60)
            missing = true
            return
        }
        retryDelay = 1
        if missing { missing = false; changed() }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .revoke, .link], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            if !source.data.isDisjoint(with: [.delete, .rename, .revoke]) { self.start() }
            self.changed()
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    // Flere hendelser rett etter hverandre (én lagring) gir én ny lesing.
    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
