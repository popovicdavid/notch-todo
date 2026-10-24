import Foundation

// Alt som har med selve todo-fila å gjøre: lesing, skriving, datoer og sammenslåing av endringer.
// Bare Foundation her, så testene kan kjøres rett fra terminalen (./test.sh).
// iPhone-skriptet (scriptable/NotchTodo.js) følger de samme reglene.

// MARK: - Seksjoner

enum Section: String, CaseIterable {
    case viktig = "Viktig"
    case frister = "Frister"
    case generelle = "Generelle"
    case senere = "Senere"  // langt frem i tid, holdes utenfor tellerne i notchet

    // Frister og Senere sorteres etter dato og viser datoen som en brikke.
    var dated: Bool { self == .frister || self == .senere }

    // «Flytt»-knappen går til neste seksjon rundt i ring.
    var other: Section {
        let all = Section.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    // Overskriften etter «## ». Ukjente overskrifter havner i Viktig, som før.
    init(heading: String) {
        let name = heading.trimmingCharacters(in: .whitespaces).lowercased()
        self = name.hasPrefix("generell") ? .generelle : name.hasPrefix("frist") ? .frister
            : name.hasPrefix("senere") ? .senere : .viktig
    }
}

// MARK: - Datoer

private let shortMonths = ["jan", "feb", "mar", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "des"]
// 2026-12-01, eller kort norsk form: 1. des (eventuelt med år: 1. des 2027).
private let datePattern = #"(\d{4})-(\d{2})-(\d{2})|\b(\d{1,2})\.\s*(jan|feb|mar|apr|mai|jun|jul|aug|sep|okt|nov|des)[a-zæøå]*(?:\s+(\d{4}))?"#
private let dateRegexes = [#"(?:frist|innen)\s+(?:ca\.\s*)?(?:"# + datePattern + ")", datePattern]
    .map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

struct FoundDate {
    let iso: String          // YYYY-MM-DD
    let range: Range<String.Index>
    let marked: Bool         // står etter «frist»/«innen» eller er kort form, og tas bort fra teksten i Frister og Senere
}

// Datoen etter «frist» eller «innen» i teksten, ellers første dato. Samme regel som findDate() på iPhone.
// Uten år gjelder i år, eller neste år hvis datoen var for mer enn 30 dager siden.
func findDate(in text: String, today: Date = Date(), calendar: Calendar = .current) -> FoundDate? {
    let ns = text as NSString
    for (i, re) in dateRegexes.enumerated() {
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let range = Range(m.range, in: text) else { continue }
        let g = { (n: Int) -> String? in m.range(at: n).location == NSNotFound ? nil : ns.substring(with: m.range(at: n)) }
        if let y = g(1), let mo = g(2), let d = g(3) { return FoundDate(iso: "\(y)-\(mo)-\(d)", range: range, marked: i == 0) }
        guard let d = g(4).flatMap({ Int($0) }), let mo = g(5).flatMap({ shortMonths.firstIndex(of: $0.lowercased()) })
        else { return nil }
        var year = g(6).flatMap { Int($0) } ?? calendar.component(.year, from: today)
        if g(6) == nil, let date = calendar.date(from: DateComponents(year: year, month: mo + 1, day: d)),
           let limit = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: today)), date < limit {
            year += 1
        }
        return FoundDate(iso: String(format: "%04d-%02d-%02d", year, mo + 1, d), range: range, marked: true)
    }
    return nil
}

// Datoen som YYYY-MM-DD. Brukes til å sortere Frister og Senere.
func deadline(in text: String, today: Date = Date(), calendar: Calendar = .current) -> String? {
    findDate(in: text, today: today, calendar: calendar)?.iso
}

struct DueChip: Equatable {
    let label: String
    let urgent: Bool  // tre dager eller mindre igjen, eller forfalt
}

private let monthNames = ["jan.", "feb.", "mar.", "apr.", "mai", "jun.", "jul.", "aug.", "sep.", "okt.", "nov.", "des."]

// Datobrikken: «forfalt», «i dag», «i morgen», «om 3 d» eller «12. apr.» (med år når det ikke er i år). Samme som due() på iPhone.
func dueChip(for text: String, today: Date = Date(), calendar: Calendar = .current) -> DueChip? {
    guard let d = deadline(in: text, today: today, calendar: calendar) else { return nil }
    let parts = d.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]),
          let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
          let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: date).day
    else { return nil }

    let label: String
    switch days {
    case ..<0: label = "forfalt"
    case 0: label = "i dag"
    case 1: label = "i morgen"
    case 2...7: label = "om \(days) d"
    default:
        label = "\(parts[2]). \(monthNames[parts[1] - 1])"
            + (parts[0] != calendar.component(.year, from: today) ? " \(parts[0])" : "")
    }
    return DueChip(label: label, urgent: days <= 3)
}

// Teksten slik den vises: i Frister og Senere tas «frist 2026-11-01» og «1. des» bort, siden datoen står i brikken.
func displayText(_ text: String, in section: Section) -> String {
    guard section.dated, let f = findDate(in: text), f.marked else { return text }
    let before = text[..<f.range.lowerBound].replacingOccurrences(of: #",?\s*$"#, with: "", options: .regularExpression)
    var s = before + " " + text[f.range.upperBound...]
    s = s.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\(\s*,?\s*"#, with: "(", options: .regularExpression)
        .replacingOccurrences(of: #",?\s*\)"#, with: ")", options: .regularExpression)
        .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    return s.isEmpty ? text : s
}

// MARK: - Oppgaver og endringer

struct TodoItem: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done: Bool
    var section: Section
}

// Peker på en oppgave uten id, så den kan finnes igjen i en fil som er lest på nytt.
// n skiller like oppgaver fra hverandre (0 = den første).
struct TaskRef: Equatable {
    var section: Section
    var text: String
    var done: Bool
    var n = 0
}

// En endring fra brukeren. Den legges oppå det som står i fila akkurat nå, ikke oppå det vi leste sist,
// så endringer fra iPhone eller assistenten i mellomtiden blir stående.
// «before» er oppgaven den nye plassen er rett foran (nil = nederst i seksjonen).
enum TodoOp: Equatable {
    case insert(text: String, done: Bool, section: Section, before: TaskRef?)
    case setDone(TaskRef, Bool, before: TaskRef?)
    case edit(TaskRef, String)
    case remove(TaskRef)
    case move(TaskRef, to: Section, before: TaskRef?)
    case batch([TodoOp])
}

// Én linje, uten luft rundt.
private func oneLine(_ text: String) -> String {
    text.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Dokumentet

struct TodoDocument: Equatable {
    var preamble: [String] = ["# Todo"]  // linjene før første ##-overskrift
    var order: [Section] = []            // seksjonene i den rekkefølgen de står i fila
    var items: [TodoItem] = []
    var notes: [Section: [String]] = [:] // andre linjer i en seksjon (ikke oppgaver), tas vare på

    init() {}

    init(parsing text: String) {
        var preamble: [String] = []
        var section = Section.viktig
        var inSection = false
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") {
                section = Section(heading: String(t.dropFirst(3)))
                inSection = true
                if !order.contains(section) { order.append(section) }
                continue
            }
            if let item = Self.task(from: t, in: section) {
                items.append(item)
            } else if !t.isEmpty {
                if inSection { notes[section, default: []].append(t) } else { preamble.append(t) }
            }
        }
        if !preamble.isEmpty { self.preamble = preamble }
    }

    private static func task(from line: String, in section: Section) -> TodoItem? {
        for (prefix, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] where line.hasPrefix(prefix) {
            return TodoItem(text: String(line.dropFirst(prefix.count)), done: done, section: section)
        }
        return nil
    }

    // Seksjonene i filas rekkefølge, og de som mangler til slutt.
    var sections: [Section] { order + Section.allCases.filter { !order.contains($0) } }

    func serialized() -> String {
        var out = preamble.joined(separator: "\n") + "\n"
        for section in sections {
            out += "\n## \(section.rawValue)\n\n"
            let list = ordered(in: section)
            for item in list { out += "- [\(item.done ? "x" : " ")] \(item.text)\n" }
            if let n = notes[section], !n.isEmpty {
                out += (list.isEmpty ? "" : "\n") + n.joined(separator: "\n") + "\n"
            }
        }
        return out
    }

    // Åpne oppgaver først, avkryssede nederst. Frister og Senere: tidligste dato først, uten dato nederst.
    func ordered(in section: Section) -> [TodoItem] {
        let all = items.filter { $0.section == section }
        var open = all.filter { !$0.done }
        if section.dated {
            open = open.enumerated().sorted {
                let a = deadline(in: $0.element.text) ?? "9999", b = deadline(in: $1.element.text) ?? "9999"
                return a != b ? a < b : $0.offset < $1.offset
            }.map(\.element)
        }
        return open + all.filter { $0.done }
    }

    // Seksjonen som markdown-liste, til «Kopier hele seksjonen».
    func markdown(for section: Section) -> String {
        ordered(in: section).map { "- [\($0.done ? "x" : " ")] \($0.text)" }.joined(separator: "\n")
    }

    // MARK: Finne oppgaver

    func ref(at i: Int) -> TaskRef {
        let it = items[i]
        let n = items[..<i].filter { $0.section == it.section && $0.text == it.text && $0.done == it.done }.count
        return TaskRef(section: it.section, text: it.text, done: it.done, n: n)
    }

    func ref(for id: UUID) -> TaskRef? { items.firstIndex { $0.id == id }.map(ref(at:)) }

    // Finner oppgaven selv om den er krysset av, flyttet eller har fått like naboer et annet sted i mellomtiden.
    func locate(_ r: TaskRef) -> Int? {
        let exact = items.indices.filter {
            items[$0].section == r.section && items[$0].text == r.text && items[$0].done == r.done
        }
        if !exact.isEmpty { return exact[min(r.n, exact.count - 1)] }
        return items.firstIndex { $0.section == r.section && $0.text == r.text }
            ?? items.firstIndex { $0.text == r.text && $0.done == r.done }
            ?? items.firstIndex { $0.text == r.text }
    }

    // Neste oppgave i samme seksjon fra plass i, brukt for å legge noe tilbake der det var.
    private func anchor(from i: Int, in section: Section) -> TaskRef? {
        (i..<items.count).first { items[$0].section == section }.map(ref(at:))
    }

    private func insertIndex(before: TaskRef?, in section: Section) -> Int {
        if let before, let j = locate(before), items[j].section == section { return j }
        return items.count
    }

    // MARK: Endringer

    // Gjør endringen og gir tilbake den som angrer den (nil hvis ingenting skjedde,
    // f.eks. fordi oppgaven er slettet et annet sted).
    @discardableResult
    mutating func apply(_ op: TodoOp) -> TodoOp? {
        switch op {
        case let .insert(text, done, section, before):
            let t = oneLine(text)
            guard !t.isEmpty else { return nil }
            let i = insertIndex(before: before, in: section)
            items.insert(TodoItem(text: t, done: done, section: section), at: i)
            return .remove(ref(at: i))

        case let .setDone(r, value, before):
            guard let i = locate(r), items[i].done != value else { return nil }
            var item = items.remove(at: i)
            let back = anchor(from: i, in: item.section)
            item.done = value
            let j = insertIndex(before: before, in: item.section)
            items.insert(item, at: j)
            return .setDone(ref(at: j), !value, before: back)

        case let .edit(r, text):
            let t = oneLine(text)
            guard !t.isEmpty, let i = locate(r), items[i].text != t else { return nil }
            let old = items[i].text
            items[i].text = t
            return .edit(ref(at: i), old)

        case let .remove(r):
            guard let i = locate(r) else { return nil }
            let item = items.remove(at: i)
            return .insert(text: item.text, done: item.done, section: item.section,
                           before: anchor(from: i, in: item.section))

        case let .move(r, to, before):
            guard let i = locate(r) else { return nil }
            var item = items.remove(at: i)
            let from = item.section
            let back = anchor(from: i, in: from)
            item.section = to
            let j = insertIndex(before: before, in: to)
            items.insert(item, at: j)
            if from == to && j == i { return nil }
            return .move(ref(at: j), to: from, before: back)

        case let .batch(ops):
            let undo = ops.compactMap { apply($0) }
            return undo.isEmpty ? nil : .batch(undo.reversed())
        }
    }

    // Gir oppgavene samme id som i forrige utgave når de finnes igjen,
    // så valg, hover og redigering overlever at fila leses på nytt.
    mutating func adoptIDs(from old: TodoDocument) {
        var used = Set<UUID>()
        var assigned = [UUID?](repeating: nil, count: items.count)
        func take(_ match: (TodoItem) -> Bool) -> UUID? {
            guard let o = old.items.first(where: { !used.contains($0.id) && match($0) }) else { return nil }
            used.insert(o.id)
            return o.id
        }
        for i in items.indices {
            let it = items[i]
            assigned[i] = take { $0.section == it.section && $0.text == it.text && $0.done == it.done }
        }
        for i in items.indices where assigned[i] == nil {
            let it = items[i]
            assigned[i] = take { $0.text == it.text }
        }
        // Redigert tekst: samme plass i samme seksjon.
        for i in items.indices where assigned[i] == nil && i < old.items.count {
            let o = old.items[i]
            if o.section == items[i].section && !used.contains(o.id) { used.insert(o.id); assigned[i] = o.id }
        }
        for i in items.indices { if let id = assigned[i] { items[i].id = id } }
    }
}
