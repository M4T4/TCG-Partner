import DeckKit
import SwiftUI

/// Próximos eventos y eventos pasados (con el récord que hiciste en cada uno).
struct EventsView: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var matches: MatchStore
    @EnvironmentObject private var events: EventStore
    let actions: AppActions

    private var upcoming: [TournamentEvent] {
        events.items.filter { $0.isUpcoming() }.sorted { $0.startDate < $1.startDate }
    }

    private var past: [TournamentEvent] {
        events.items.filter { !$0.isUpcoming() }.sorted { $0.startDate > $1.startDate }
    }

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 14)]
    @CompactWidth private var compact

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    // En iPhone el título ya está en la barra de navegación.
                    if !compact { Text("Eventos").font(.title.bold()) }
                    let cost = upcoming.compactMap(\.cost).reduce(0, +)
                    Text("\(upcoming.count) próximos" + (cost > 0 ? " · \(cost.formatted(.currency(code: upcoming.first?.currency ?? "MXN"))) en inscripciones" : ""))
                        .foregroundStyle(.secondary)
                }
                section("Próximos", upcoming)
                if !past.isEmpty { section("Pasados", past) }
            }
            .padding(compact ? 16 : 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppBackground())
        .overlay {
            if events.items.isEmpty {
                ContentUnavailableView {
                    Label("Sin eventos", systemImage: "calendar")
                } description: {
                    Text("Guarda los torneos a los que piensas ir: enlace, costo, fechas, lugar y el mazo que planeas jugar.")
                } actions: {
                    Button("Nuevo evento") { actions.editEvent(nil) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { actions.editEvent(nil) } label: {
                    Label("Nuevo evento", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [TournamentEvent]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.bold())
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(items) { event in
                        VStack(alignment: .leading, spacing: 0) {
                            EventSummary(event: event, deckName: event.plannedDeckID.flatMap(decks.deck)?.name,
                                         showsPlacementBanner: true, fixedHeight: true)
                            // La línea de resultado ocupa su lugar aunque no haya partidas,
                            // para que las tarjetas de una misma fila queden alineadas.
                            let record = matches.items.filter { $0.eventID == event.id }.stats
                            Text(record.total > 0 ? "Resultado: \(record.record) · \(percentText(record.winRate))" : " ")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(winRateColor(record.winRate))
                                .padding(.top, 6)
                                .padding(.leading, 4)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { actions.select(.event(event.id)) }
                        .help("Abrir la página del evento")
                        .contextMenu {
                            Button("Abrir") { actions.select(.event(event.id)) }
                            Button("Editar…") { actions.editEvent(event) }
                            if let url = event.url { Link("Abrir enlace del evento", destination: url) }
                            Button("Duplicar") {
                                var copy = event
                                copy.id = UUID()
                                copy.name += " (copia)"
                                events.save(copy)
                            }
                            Divider()
                            Button("Eliminar evento", role: .destructive) { events.delete(event.id) }
                        }
                    }
                }
            }
        }
    }
}

/// Campo numérico con flechas para subir y bajar (como un input de número).
/// Vacío = sin valor; las flechas empiezan desde el mínimo.
struct NumberField: View {
    @Binding var value: Int?
    var prompt = ""
    var range: ClosedRange<Int> = 1...9999
    @FocusState private var focused: Bool

    /// Ajusta el número al rango. Solo al salir del campo o pulsar Enter: si se hiciera en cada tecla,
    /// el «1» de «15» se convertiría en el mínimo antes de poder escribir el «5».
    private func clamp() {
        if let current = value, !range.contains(current) {
            value = min(max(current, range.lowerBound), range.upperBound)
        }
    }

    private var stepperValue: Binding<Int> {
        Binding(get: { value ?? range.lowerBound - 1 },
                set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: $value, format: .number.grouping(.never), prompt: Text(prompt))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 80)
                .focused($focused)
                .onSubmit(clamp)
                .onChange(of: focused) { if !focused { clamp() } }
            Stepper("", value: stepperValue, in: (range.lowerBound - 1)...range.upperBound)
                .labelsHidden()
        }
    }
}

/// Formulario de un evento: enlace, costo, fechas, lugar, mazo planeado…
struct EventEditor: View {
    @EnvironmentObject private var decks: DeckStore
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss

    @State var event: TournamentEvent
    let isNew: Bool

    private static let currencies = ["MXN", "USD", "EUR", "CAD", "GBP", "JPY"]

    private var hasEndDate: Binding<Bool> {
        Binding(get: { event.endDate != nil },
                set: { event.endDate = $0 ? Calendar.current.date(byAdding: .day, value: 1, to: event.startDate) : nil })
    }

    private var endDate: Binding<Date> {
        Binding(get: { event.endDate ?? event.startDate }, set: { event.endDate = $0 })
    }

    private var cost: Binding<Double?> {
        Binding(get: { event.cost }, set: { event.cost = $0 })
    }

    var body: some View {
        EditorSheet(title: isNew ? "Nuevo evento" : "Editar evento",
                    confirmLabel: isNew ? "Crear evento" : "Guardar",
                    canConfirm: !event.name.trimmingCharacters(in: .whitespaces).isEmpty,
                    onDelete: isNew ? nil : {
                        events.delete(event.id)
                        dismiss()
                    },
                    onConfirm: save) {
            Form {
                Section("Evento") {
                    TextField("Nombre", text: $event.name, prompt: Text("Ej. Regional Monterrey"))
                        .formLabel("Nombre")
                    Picker("Tipo", selection: $event.kind) {
                        ForEach(EventKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Formato", selection: $event.format) {
                        ForEach(GameFormat.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        TextField("Enlace", text: $event.link, prompt: Text("https://…"))
                            .formLabel("Enlace")
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        if let url = event.url {
                            Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                                .help("Abrir el enlace")
                        }
                    }
                }
                Section("Fecha y lugar") {
                    DatePicker("Inicio", selection: $event.startDate)
                    Toggle("Dura más de un día", isOn: hasEndDate)
                    if event.endDate != nil {
                        DatePicker("Fin", selection: endDate, in: event.startDate..., displayedComponents: .date)
                    }
                    TextField("Lugar", text: $event.location, prompt: Text("Tienda, ciudad o «En línea»"))
                        .formLabel("Lugar")
                }
                Section("Inscripción") {
                    HStack {
                        TextField("Costo", value: cost, format: .number.precision(.fractionLength(0...2)), prompt: Text("0"))
                            .decimalKeyboard()
                            .formLabel("Costo")
                        Picker("Moneda", selection: $event.currency) {
                            ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Toggle("Ya estoy inscrito", isOn: $event.registered)
                    Picker("Mazo que planeo jugar", selection: $event.plannedDeckID) {
                        Text("Sin decidir").tag(UUID?.none)
                        Divider()
                        ForEach(decks.decks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { deck in
                            Text(deck.name).tag(UUID?.some(deck.id))
                        }
                    }
                }
                Section {
                    LabeledContent("Posición final") {
                        NumberField(value: $event.placement, prompt: "Ej. 3", range: 1...(event.players ?? 9999))
                    }
                    LabeledContent("Jugadores en el evento") {
                        NumberField(value: $event.players, prompt: "Ej. 64", range: max(event.placement ?? 1, 2)...9999)
                    }
                    if let finish = event.finish {
                        LabeledContent("Quedaste") { PlacementBadge(placement: finish) }
                    }
                } header: {
                    Text("Resultado")
                } footer: {
                    Text("Anótala cuando termine el evento. Escribe el número o usa las flechas; el número de jugadores es opcional.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Notas") {
                    TextField("Notas", text: $event.notes, prompt: Text("Hotel, transporte, horarios de registro…"), axis: .vertical)
                        .lineLimit(3...6)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
        }
        .sheetFrame(width: 500, height: 720)
    }

    private func save() {
        event.name = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Posiciones o jugadores en 0 o negativos no cuentan.
        if (event.placement ?? 1) < 1 { event.placement = nil }
        if (event.players ?? 1) < 1 { event.players = nil }
        // Por si se guardó sin salir del campo: no puede haber menos jugadores que tu posición.
        if let players = event.players, let place = event.placement, players < place { event.players = place }
        events.save(event)
        dismiss()
    }
}
