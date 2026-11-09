import DeckKit
#if os(macOS)
import AppKit
import PDFKit
#endif
import SwiftUI
import UniformTypeIdentifiers

/// Hoja para preparar la impresión: datos del jugador, notas, tipografía y vista previa en vivo.
struct PrintDeckSheet: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var playerStore: PlayerStore
    @Environment(\.dismiss) private var dismiss
    let deckID: Deck.ID

    /// Jugador actual (UUID); vacío = hoja en blanco para rellenar a mano.
    @AppStorage(currentPlayerKey) private var selectedPlayerID = ""
    @AppStorage("print.format") private var format = GameFormat.standard
    @AppStorage("print.language") private var language = PrintLanguage.spanish
    @AppStorage("print.typography") private var typography = PrintTypography.modern
    @AppStorage("print.paper") private var paper = PaperSize.letter
    @AppStorage("print.color") private var color = true
    @AppStorage("print.includeNotes") private var includeNotes = true

    private var deck: Deck? { store.deck(deckID) }

    private var selectedPlayer: Player? {
        UUID(uuidString: selectedPlayerID).flatMap(playerStore.player)
    }

    private var player: PlayerInfo {
        selectedPlayer?.info(format: format) ?? PlayerInfo(name: "", playerID: "", birthDate: nil, format: format)
    }

    private var options: PrintOptions {
        PrintOptions(language: language, typography: typography, paper: paper, color: color, includeNotes: includeNotes)
    }

    var body: some View {
        HStack(spacing: 0) {
            form
                .frame(width: 330)
            Divider()
            preview
        }
        .frame(minWidth: 1000, idealWidth: 1080, minHeight: 700, idealHeight: 780)
        .alert("Error", isPresented: Binding(get: { playerStore.errorMessage != nil },
                                             set: { if !$0 { playerStore.errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(playerStore.errorMessage ?? "")
        }
    }

    // MARK: - Formulario

    private var form: some View {
        VStack(spacing: 0) {
            Form {
                Section("Jugador") {
                    PlayerFields(blankOption: "En blanco (rellenar a mano)")
                    Picker("Formato", selection: $format) {
                        ForEach(GameFormat.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("Notas del mazo") {
                    TextField("Notas", text: notes, prompt: Text("Se imprimen al final de la hoja"), axis: .vertical)
                        .lineLimit(3...6)
                        .labelsHidden()
                    Toggle("Incluir notas en la hoja", isOn: $includeNotes)
                }

                Section("Tipografía") {
                    Picker("Tipografía", selection: $typography) {
                        ForEach(PrintTypography.allCases) { option in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Aa  \(option.title)")
                                    .font(.system(size: 14, weight: .semibold, design: option.design))
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(option)
                        }
                    }
                    .radioGroupPickerStyle()
                    .labelsHidden()
                }

                Section("Página") {
                    Picker("Idioma de la hoja", selection: $language) {
                        ForEach(PrintLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Papel", selection: $paper) {
                        ForEach(PaperSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Tinta", selection: $color) {
                        Text("Color").tag(true)
                        Text("Blanco y negro").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                #if os(macOS)
                Button("Exportar PDF…", action: exportPDF)
                Button("Imprimir…", action: printPDF)
                    .keyboardShortcut(.defaultAction)
                #else
                // En iPhone, el menú de compartir ya ofrece imprimir, guardar en Archivos o enviar.
                if let deck {
                    ShareLink(item: DecklistPDFExport(name: "\(deck.name) - decklist.pdf", render: pdfData),
                              preview: SharePreview("\(deck.name) - decklist.pdf")) {
                        Label("Compartir o imprimir PDF", systemImage: "square.and.arrow.up")
                    }
                }
                #endif
            }
            .padding(14)
            .disabled(deck == nil)
        }
    }

    private var notes: Binding<String> {
        Binding(get: { deck?.notes ?? "" },
                set: { text in store.update(deckID) { $0.notes = text } })
    }

    // MARK: - Vista previa

    private var preview: some View {
        GeometryReader { proxy in
            let page = paper.size
            let scale = min((proxy.size.width - 48) / page.width, (proxy.size.height - 48) / page.height)
            ZStack {
                Color.underPageBackground
                if let deck {
                    DecklistPage(deck: deck, player: player, options: options)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                        .scaleEffect(scale)
                        .frame(width: page.width * scale, height: page.height * scale)
                }
            }
        }
    }

    // MARK: - PDF

    private func pdfData() -> Data? {
        guard let deck else { return nil }
        return DecklistPDF.render(DecklistPage(deck: deck, player: player, options: options), size: paper.size)
    }

    #if os(macOS)
    private func exportPDF() {
        guard let deck, let data = pdfData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(deck.name) - decklist.pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            PlatformFiles.reveal(url, selecting: true)
        } catch {
            store.errorMessage = "No se pudo guardar el PDF: \(error.localizedDescription)"
        }
    }

    private func printPDF() {
        guard let data = pdfData(), let document = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: paper.size.width, height: paper.size.height)
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.orientation = .portrait
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: false) else {
            store.errorMessage = "No se pudo preparar la impresión."
            return
        }
        operation.jobTitle = deck?.name ?? "Decklist"
        operation.run()
    }
    #endif
}

/// El PDF de la hoja para el menú de compartir. Se dibuja solo cuando se comparte.
struct DecklistPDFExport: Transferable {
    let name: String
    let render: @MainActor () -> Data?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { export in
            await MainActor.run { export.render() ?? Data() }
        }
        .suggestedFileName { $0.name }
    }
}

enum DecklistPDF {
    /// Dibuja la vista en un PDF vectorial de una página (el texto queda seleccionable y nítido).
    @MainActor
    static func render(_ page: some View, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: page.frame(width: size.width, height: size.height))
        let data = NSMutableData()
        var ok = false
        renderer.render { _, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            ok = true
        }
        return ok ? data as Data : nil
    }
}
