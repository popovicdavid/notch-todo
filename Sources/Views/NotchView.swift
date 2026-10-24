import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: TodoStore
    let onClose: () -> Void

    @State private var newText: [Section: String] = [:]
    @FocusState private var focusedField: Section?
    @State private var editingRow: UUID?
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    private var notch: CGSize { model.geometry.notch }

    private var size: CGSize {
        if model.open { return model.listSize }
        if model.hovering { return model.geometry.hoverSize }
        return notch
    }

    private var radius: CGFloat { model.open ? 24 : 10 }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(model.open ? 0.45 : 0), radius: 14, y: 6)

            // Klokka og innholdet finnes bare når de vises, så ingenting tegnes eller oppdateres når lista er lukket.
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
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.laterCollapsed)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.hovering)
        .onChange(of: model.open) { _, open in
            if open {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focusedField = .viktig }
            } else {
                editingRow = nil
            }
        }
        .onChange(of: model.focusRequest) { _, section in
            guard let section else { return }
            focusedField = section
            model.focusRequest = nil
        }
        .onChange(of: focusedField) { _, field in
            model.fieldFocus = field
            if field != nil { model.select(nil) }
        }
        .onChange(of: model.selected) { _, id in if id != nil { focusedField = nil } }
        .onChange(of: editingRow) { _, id in model.editingRow = id }
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
                if store.hasDone {
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
                column(.viktig)
                divider
                column(.frister)
                divider
                column(.generelle)
                divider
                if model.laterCollapsed { laterStrip } else { column(.senere) }
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

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
    }

    // MARK: Kolonner

    private func column(_ section: Section) -> some View {
        let items = store.items(in: section)
        return VStack(alignment: .leading, spacing: 8) {
            header(section)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        if items.isEmpty {
                            Text("Tomt 🎉").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                        }
                        ForEach(items) { item in row(item).id(item.id) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.selected) { _, id in
                    guard let id, items.contains(where: { $0.id == id }) else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(dropHighlight(.column(section)))
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], isTargeted: dropBinding(.column(section))) { providers in
            drop(providers, into: section, before: nil)
        }
    }

    private func header(_ section: Section) -> some View {
        Hoverable { hovered in header(section, hovered: hovered) }
    }

    private func header(_ section: Section, hovered: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(section.rawValue).font(.system(size: 14, weight: .bold)).foregroundStyle(section.color)
            Text("\(store.openCount(in: section)) igjen").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            Group {
                Button { copySection(section) } label: { Image(systemName: "doc.on.doc") }
                    .help("Kopier hele seksjonen")
                    .opacity(hovered ? 1 : 0)
                if section == .senere {
                    Button { model.laterCollapsed = true } label: { Image(systemName: "chevron.right.2") }
                        .help("Klapp sammen Senere")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Kopier hele seksjonen") { copySection(section) }
        }
    }

    // Senere klappet sammen: en smal stripe. Klikk åpner kolonnen, og oppgaver kan slippes her.
    private var laterStrip: some View {
        Text("Senere (\(store.openCount(in: .senere)))")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Section.senere.color)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: 26)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(model.dropTarget == .column(.senere) ? 0.16 : 0.06))
            )
            .contentShape(Rectangle())
            .onTapGesture { model.laterCollapsed = false }
            .help("Vis Senere")
            .onDrop(of: [.plainText], isTargeted: dropBinding(.column(.senere))) { providers in
                drop(providers, into: .senere, before: nil)
            }
    }

    // MARK: Rader

    private func finishEditing(_ id: UUID) {
        guard editingRow == id else { return }
        store.edit(id, to: editText)
        editingRow = nil
    }

    private func beginEditing(_ item: TodoItem) {
        editText = item.text
        editingRow = item.id
        model.select(item.id)
        DispatchQueue.main.async { editFocused = true }
    }

    private func copySection(_ section: Section) {
        Clipboard.copy(store.doc.markdown(for: section))
    }

    private func row(_ item: TodoItem) -> some View {
        Hoverable { h in
            if h { model.hoveredRow = item.id } else if model.hoveredRow == item.id { model.hoveredRow = nil }
        } content: { hovered in
            row(item, hovered: hovered)
        }
    }

    private func row(_ item: TodoItem, hovered: Bool) -> some View {
        let color = item.section.color
        let chip = item.section.dated && !item.done ? dueChip(for: item.text) : nil

        return HStack(alignment: .top, spacing: 7) {
            Button { store.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.done ? Color.green : color.opacity(0.8))
            }
            .buttonStyle(.plain)

            if editingRow == item.id {
                TextField("", text: $editText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12)))
                    .focused($editFocused)
                    .onSubmit { finishEditing(item.id) }
                    .onExitCommand { editingRow = nil }
                    .onChange(of: editFocused) { _, focused in
                        if !focused && editingRow == item.id { finishEditing(item.id) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Vanlig SwiftUI-tekst, som før. Den valgte raden (klikk på den) får i tillegg en markerbar tekstvisning
                // oppå, så teksten kan markeres og kopieres. Å lage den ved hover ga hakking når musa gikk over lista.
                let shown = displayText(item.text, in: item.section)
                let selectable = model.selected == item.id
                Text(LocalizedStringKey(shown))
                    .font(.system(size: 12.5))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.white.opacity(0.4) : Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(selectable ? 0 : 1)
                    .onTapGesture(count: 2) { beginEditing(item) }
                    .overlay(alignment: .topLeading) {
                        if selectable {
                            TaskText(
                                text: shown,
                                done: item.done,
                                onClick: { model.select(item.id) },
                                onDoubleClick: { beginEditing(item) },
                                onCopy: { Clipboard.copy(item.text) },
                                onCopySection: { copySection(item.section) }
                            )
                        }
                    }

                if let chip { DueChipView(chip: chip, color: color) }
            }

            // Knappene har alltid sin plass og vises bare ved hover. Før tok de plass fra teksten når de dukket opp,
            // så teksten brøt om, raden endret høyde og alt under hoppet (det føltes som hakking og forsinkelse).
            let showButtons = hovered && editingRow != item.id
            HStack(spacing: 7) {
                Button { store.move(item.id, to: item.section.other) } label: {
                    Image(systemName: "arrow.right").font(.system(size: 10))
                }
                .help("Flytt til \(item.section.other.rawValue)")

                Button { store.remove(item.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .help("Slett")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .opacity(showButtons ? 1 : 0)
            .allowsHitTesting(showButtons)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(model.selected == item.id ? 0.1 : 0))
        )
        .overlay(alignment: .top) {
            if model.dropTarget == .row(item.id) {
                Capsule().fill(color).frame(height: 2).offset(y: -3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(item.id) }
        .contextMenu {
            Button("Kopier") { Clipboard.copy(item.text) }
            Button("Kopier hele seksjonen") { copySection(item.section) }
        }
        // Dra fra raden (utenfor selve teksten, som kan markeres). Andre apper får teksten.
        .onDrag {
            model.dragging = item.id
            return NSItemProvider(object: item.text as NSString)
        }
        .onDrop(of: [.plainText], isTargeted: dropBinding(.row(item.id))) { providers in
            drop(providers, into: item.section, before: item.id)
        }
    }

    // MARK: Dra og slipp

    private func dropBinding(_ spot: DropSpot) -> Binding<Bool> {
        Binding(
            get: { model.dropTarget == spot },
            set: { on in
                if on { if model.dropTarget != spot { model.dropTarget = spot } }
                else if model.dropTarget == spot { model.dropTarget = nil }
            }
        )
    }

    private func dropHighlight(_ spot: DropSpot) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(model.dropTarget == spot ? 0.05 : 0))
            .padding(-6)
    }

    // Godtar bare oppgaver dratt fra lista selv. Teksten sjekkes mot oppgaven, så en avbrutt dragning ikke henger igjen.
    private func drop(_ providers: [NSItemProvider], into section: Section, before: UUID?) -> Bool {
        guard let id = model.dragging, let provider = providers.first,
              provider.canLoadObject(ofClass: NSString.self) else { return false }
        let model = model, store = store
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            let text = (object as? NSString).map { $0 as String }
            DispatchQueue.main.async {
                guard model.dragging == id, let item = store.item(id), item.text == text else { return }
                model.dragging = nil
                if before != id { store.move(id, to: section, before: before) }
            }
        }
        return true
    }
}

// Hover som bare tegner denne delen på nytt, ikke hele lista.
struct Hoverable<Content: View>: View {
    var onChange: (Bool) -> Void = { _ in }
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovered = false

    var body: some View {
        content(hovered).onHover { h in
            guard h != hovered else { return }
            hovered = h
            onChange(h)
        }
    }
}

// Klokka i Norge (følger sommer-/vintertid selv), oppdatert hvert minutt mens den vises.
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
