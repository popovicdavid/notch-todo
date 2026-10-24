import SwiftUI

// Mål som regnes ut fra skjermen appen står på, på nytt når skjermer kobles til eller fra.
struct NotchGeometry: Equatable {
    var screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    var notch = CGSize(width: 200, height: 32)

    static let margin: CGFloat = 24  // luft mot skjermkanten på hver side
    static let hoverExtra = CGSize(width: 150, height: 26)  // 6 rundt notchen + 20 til klokka

    var hoverSize: CGSize {
        CGSize(width: notch.width + Self.hoverExtra.width, height: notch.height + Self.hoverExtra.height)
    }

    // Lista: 1000 × 330, stor 1280 × 620, smalere når Senere er klappet sammen.
    // Aldri bredere eller høyere enn skjermen, så ingenting kuttes på små eller skalerte skjermer.
    func listSize(large: Bool, laterCollapsed: Bool) -> CGSize {
        var width: CGFloat = large ? 1280 : 1000
        if laterCollapsed { width *= 0.82 }
        let height: CGFloat = large ? 620 : 330
        let maxWidth = max(hoverSize.width, screen.width - 2 * Self.margin)
        let maxHeight = max(notch.height + 120, screen.height - notch.height - Self.margin)
        return CGSize(width: min(width, maxWidth).rounded(), height: min(height, maxHeight).rounded())
    }
}

enum DropSpot: Equatable {
    case row(UUID)       // rett foran denne oppgaven
    case column(Section) // nederst i seksjonen
}

final class NotchModel: ObservableObject {
    @Published var hovering = false { didSet { layoutChanged() } }
    @Published var open = false { didSet { layoutChanged() } }
    @Published var large = false { didSet { layoutChanged() } }
    @Published var geometry = NotchGeometry() { didSet { layoutChanged() } }

    // Senere er klappet sammen som standard, og valget huskes mellom oppstarter.
    @Published var laterCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(laterCollapsed, forKey: "senereSammenklappet")
            layoutChanged()
        }
    }

    @Published var selected: UUID?      // valgt med tastaturet eller et klikk
    @Published var dropTarget: DropSpot?
    @Published var focusRequest: Section?  // be visningen sette fokus på «Ny oppgave» i denne kolonnen

    // Ikke publisert: bare til tastaturet og dra og slipp, skal ikke tegne noe på nytt.
    var dragging: UUID?
    var hoveredRow: UUID?  // til cmd+C; selve hover-visningen ligger i hver rad
    var fieldFocus: Section?
    var editingRow: UUID?

    var onLayoutChange: (() -> Void)?

    init() {
        laterCollapsed = UserDefaults.standard.object(forKey: "senereSammenklappet") as? Bool ?? true
    }

    private func layoutChanged() { onLayoutChange?() }

    var listSize: CGSize { geometry.listSize(large: large, laterCollapsed: laterCollapsed) }

    // Seksjonene som vises som kolonner, i rekkefølge.
    var columns: [Section] { laterCollapsed ? [.viktig, .frister, .generelle] : Section.allCases }

    func select(_ id: UUID?) { if selected != id { selected = id } }
}
