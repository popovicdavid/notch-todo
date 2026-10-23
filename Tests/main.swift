import Foundation

// Enkle tester for lesing og skriving av todo-fila. Kjør med ./test.sh.

var failures = 0
var checks = 0

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FEIL (linje \(line)): \(what)") }
}

func equal<T: Equatable>(_ a: T, _ b: T, _ what: String, line: Int = #line) {
    check(a == b, "\(what)\n  fikk:    \(a)\n  ventet:  \(b)", line: line)
}

let sample = """
# Todo

## Viktig

- [ ] Svar på e-posten
- [x] Bestill time

## Frister

- [ ] Søknad (innen 2026-10-25)
- [ ] Lever rapporten, frist 2026-11-01
- [ ] Uten dato

## Generelle

- [ ] Gå gjennom ukenotatene

## Senere

- [ ] Søk sommerjobb, frist 2027-04-01

"""

func doc(_ text: String = sample) -> TodoDocument { TodoDocument(parsing: text) }
func texts(_ d: TodoDocument, _ s: Section) -> [String] { d.ordered(in: s).map(\.text) }

// MARK: Lesing

do {
    let d = doc()
    equal(d.items.count, 7, "antall oppgaver")
    equal(d.order, [.viktig, .frister, .generelle, .senere], "seksjonsrekkefølge")
    equal(d.preamble, ["# Todo"], "tittel")
    equal(texts(d, .viktig), ["Svar på e-posten", "Bestill time"], "Viktig")
    check(d.ordered(in: .viktig)[1].done, "avkrysset oppgave leses som ferdig")
    equal(d.serialized(), sample.trimmingCharacters(in: .newlines) + "\n", "lagres likt som den ble lest")
}

do {
    // Ukjente overskrifter og oppgaver før første overskrift havner i Viktig. Notater og rekkefølge tas vare på.
    let d = doc("""
    # Min liste
    Notat øverst
    - [ ] Løs oppgave

    ## Senere
    - [ ] Langt frem

    ## Prosjekter
    - [X] Ferdig med stor X
    Et notat i seksjonen
    """)
    equal(d.preamble, ["# Min liste", "Notat øverst"], "linjer før første overskrift")
    equal(d.order, [.senere, .viktig], "rekkefølgen fra fila")
    equal(texts(d, .viktig), ["Løs oppgave", "Ferdig med stor X"], "ukjent overskrift blir Viktig")
    equal(d.notes[.viktig] ?? [], ["Et notat i seksjonen"], "notat beholdes")
    let out = d.serialized()
    check(out.hasPrefix("# Min liste\nNotat øverst\n\n## Senere\n\n- [ ] Langt frem\n\n## Viktig\n"), "skrives i samme rekkefølge:\n\(out)")
    check(out.contains("Et notat i seksjonen"), "notatet skrives tilbake")
    check(out.contains("## Frister") && out.contains("## Generelle"), "manglende seksjoner legges til")
    equal(TodoDocument(parsing: out).serialized(), out, "lese → skrive → lese gir det samme")
}

// MARK: Datoer

do {
    equal(deadline(in: "Lever, frist 2026-11-01 (bygget 2026-01-01)"), "2026-11-01", "frist går foran andre datoer")
    equal(deadline(in: "Møte 2026-03-04"), "2026-03-04", "første dato uten frist")
    equal(deadline(in: "innen ca. 2026-05-06"), "2026-05-06", "innen ca.")
    equal(deadline(in: "Ingen dato"), nil, "ingen dato")

    let d = doc()
    equal(texts(d, .frister), ["Søknad (innen 2026-10-25)", "Lever rapporten, frist 2026-11-01", "Uten dato"],
          "Frister sorteres etter dato, uten dato nederst")

    let unsorted = doc("## Frister\n- [ ] Senest, frist 2026-12-01\n- [ ] Tidligst, frist 2026-10-01")
    equal(texts(unsorted, .frister), ["Tidligst, frist 2026-10-01", "Senest, frist 2026-12-01"], "sorteres ved lesing")
    let stable = doc("## Frister\n- [ ] B 2026-01-01\n- [ ] A\n- [ ] C 2026-01-01\n- [ ] D")
    equal(texts(stable, .frister), ["B 2026-01-01", "C 2026-01-01", "A", "D"], "lik dato beholder rekkefølgen")
}

do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Oslo")!
    let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15))!
    func chip(_ s: String) -> DueChip? { dueChip(for: s, today: today, calendar: cal) }
    equal(chip("frist 2026-10-22"), DueChip(label: "forfalt", urgent: true), "forfalt")
    equal(chip("frist 2026-10-23"), DueChip(label: "i dag", urgent: true), "i dag")
    equal(chip("frist 2026-10-24"), DueChip(label: "i morgen", urgent: true), "i morgen")
    equal(chip("frist 2026-10-26"), DueChip(label: "om 3 d", urgent: true), "om 3 d")
    equal(chip("frist 2026-10-27"), DueChip(label: "om 4 d", urgent: false), "om 4 d")
    equal(chip("frist 2026-10-30"), DueChip(label: "om 7 d", urgent: false), "om 7 d")
    equal(chip("frist 2026-12-12"), DueChip(label: "12. des.", urgent: false), "dato i år")
    equal(chip("frist 2027-05-01"), DueChip(label: "1. mai 2027", urgent: false), "dato neste år")
    equal(chip("ingen dato"), nil, "ingen brikke uten dato")

    equal(displayText("Lever rapporten, frist 2026-11-01", in: .frister), "Lever rapporten", "frist fjernes")
    equal(displayText("Søknad (innen 2026-10-25)", in: .frister), "Søknad", "tomme parenteser fjernes")
    equal(displayText("Søknad (NAV, frist 2026-10-25)", in: .senere), "Søknad (NAV)", "komma før parentes")
    equal(displayText("Møte 2026-03-04", in: .frister), "Møte 2026-03-04", "dato uten frist blir stående")
    equal(displayText("Lever, frist 2026-11-01", in: .viktig), "Lever, frist 2026-11-01", "ikke i Viktig")
    equal(displayText("frist 2026-11-01", in: .frister), "frist 2026-11-01", "tom tekst vises som den er")
}

// MARK: Endringer og sammenslåing

// Det appen så sist, og det som står i fila nå (iPhone har lagt til og krysset av i mellomtiden).
let seen = doc()
let onDisk = """
# Todo

## Viktig

- [ ] Ny fra iPhone
- [ ] Svar på e-posten
- [x] Bestill time

## Frister

- [x] Søknad (innen 2026-10-25)
- [ ] Lever rapporten, frist 2026-11-01
- [ ] Uten dato

## Generelle

- [ ] Gå gjennom ukenotatene

## Senere

- [ ] Søk sommerjobb, frist 2027-04-01
"""

func ref(_ text: String, in d: TodoDocument = seen) -> TaskRef {
    d.ref(for: d.items.first { $0.text == text }!.id)!
}

do {
    // Avkryssing på Mac-en legges oppå fila slik den er nå.
    var d = doc(onDisk)
    let undo = d.apply(.setDone(ref("Svar på e-posten"), true, before: nil))
    check(undo != nil, "avkryssing gir angre")
    equal(texts(d, .viktig), ["Ny fra iPhone", "Bestill time", "Svar på e-posten"], "avkrysset havner nederst")
    check(d.ordered(in: .viktig)[2].done, "oppgaven er krysset av")
    check(d.ordered(in: .frister).first { $0.text.hasPrefix("Søknad") }!.done, "avkryssing fra iPhone står")
    d.apply(undo!)
    equal(d.serialized(), doc(onDisk).serialized(), "angre gir fila tilbake")
}

do {
    // Ny oppgave fra Mac-en, og iPhone-oppgaven blir stående.
    var d = doc(onDisk)
    let undo = d.apply(.insert(text: "  Ny fra Mac\nmed linjeskift ", done: false, section: .generelle, before: nil))
    equal(texts(d, .generelle), ["Gå gjennom ukenotatene", "Ny fra Mac med linjeskift"], "ny oppgave, én linje")
    check(d.items.contains { $0.text == "Ny fra iPhone" }, "iPhone-oppgaven er med")
    d.apply(undo!)
    equal(texts(d, .generelle), ["Gå gjennom ukenotatene"], "angre fjerner den nye")
    check(d.apply(.insert(text: "   ", done: false, section: .viktig, before: nil)) == nil, "tom oppgave legges ikke til")
}

do {
    // Redigering av en oppgave som iPhone har krysset av i mellomtiden.
    var d = doc(onDisk)
    let undo = d.apply(.edit(ref("Søknad (innen 2026-10-25)"), "Søknad (innen 2026-10-28)"))
    let s = d.items.first { $0.text.hasPrefix("Søknad") }!
    equal(s.text, "Søknad (innen 2026-10-28)", "redigert tekst")
    check(s.done, "avkryssingen fra iPhone står")
    d.apply(undo!)
    check(d.items.contains { $0.text == "Søknad (innen 2026-10-25)" && $0.done }, "angre redigering")
}

do {
    // Sletting av noe som allerede er slettet et annet sted gjør ingenting.
    var d = doc(onDisk)
    d.apply(.remove(ref("Gå gjennom ukenotatene")))
    let before = d
    check(d.apply(.remove(ref("Gå gjennom ukenotatene"))) == nil, "allerede slettet")
    equal(d, before, "ingenting endret")

    var e = doc(onDisk)
    let undo = e.apply(.remove(ref("Svar på e-posten")))
    equal(texts(e, .viktig), ["Ny fra iPhone", "Bestill time"], "slettet")
    e.apply(undo!)
    equal(texts(e, .viktig), ["Ny fra iPhone", "Svar på e-posten", "Bestill time"], "angre legger den tilbake på plass")
}

do {
    // Flytting til en annen seksjon og innenfor seksjonen.
    var d = doc(onDisk)
    let undo = d.apply(.move(ref("Svar på e-posten"), to: .senere, before: nil))
    equal(texts(d, .senere), ["Søk sommerjobb, frist 2027-04-01", "Svar på e-posten"], "flyttet til Senere")
    d.apply(undo!)
    equal(texts(d, .viktig), ["Ny fra iPhone", "Svar på e-posten", "Bestill time"], "angre flytter tilbake")

    var e = doc(onDisk)
    let first = ref("Ny fra iPhone", in: e)
    e.apply(.move(ref("Svar på e-posten"), to: .viktig, before: first))
    equal(texts(e, .viktig), ["Svar på e-posten", "Ny fra iPhone", "Bestill time"], "flyttet øverst i seksjonen")
    check(e.apply(.move(ref("Svar på e-posten", in: e), to: .viktig, before: first)) == nil, "slipp på samme plass")
}

do {
    // «Fjern ferdige» og angre.
    var d = doc(onDisk)
    let done = d.items.indices.filter { d.items[$0].done }.reversed().map { d.ref(at: $0) }
    let undo = d.apply(.batch(done.map { .remove($0) }))
    check(!d.items.contains { $0.done }, "ingen ferdige igjen")
    d.apply(undo!)
    equal(d.serialized(), doc(onDisk).serialized(), "angre gir alle tilbake")
}

do {
    // Like oppgaver skilles med n.
    var d = doc("## Viktig\n- [ ] Ring\n- [ ] Ring\n- [ ] Ring")
    d.apply(.setDone(d.ref(at: 1), true, before: nil))
    equal(d.items.map(\.done), [false, false, true], "bare én av de like")
    equal(d.ref(at: 1).n, 1, "n teller like foran")
}

do {
    // Id-ene følger oppgavene når fila leses på nytt.
    let old = doc()
    var fresh = doc(onDisk)
    fresh.adoptIDs(from: old)
    let id = { (d: TodoDocument, t: String) in d.items.first { $0.text == t }!.id }
    equal(id(fresh, "Svar på e-posten"), id(old, "Svar på e-posten"), "samme id")
    equal(id(fresh, "Søknad (innen 2026-10-25)"), id(old, "Søknad (innen 2026-10-25)"), "samme id etter avkryssing")
    check(!old.items.contains { $0.id == id(fresh, "Ny fra iPhone") }, "ny oppgave får ny id")

    var edited = old
    edited.items[0].text = "Svar på e-posten i dag"
    var reread = doc(edited.serialized())
    reread.adoptIDs(from: old)
    equal(reread.items[0].id, old.items[0].id, "samme id etter redigering")
}

do {
    let d = doc()
    equal(d.markdown(for: .viktig), "- [ ] Svar på e-posten\n- [x] Bestill time", "seksjonen som markdown")
}

print("\(checks - failures) av \(checks) sjekker gikk bra.")
exit(failures == 0 ? 0 : 1)
