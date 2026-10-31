import SwiftUI

struct FieldTestView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = Measurement()
    @State private var eci = ""
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Un peu de terrain.", systemImage: "waveform.path.ecg").font(.title2.bold())
                    Text("Pour regarder ce que ton iPhone reçoit vraiment, on passe par son menu Field Test. Pylo t’aide à comprendre et à garder tes relevés.")
                }
                Section("Ouvrir Field Test") {
                    Text("1. Ouvre l’app Téléphone.\n2. Saisis le code ci-dessous sur le clavier.\n3. Appuie sur Appeler.")
                    HStack { Text("*3001#12345#*").font(.title3.monospaced()); Spacer(); Button("Copier") { UIPasteboard.general.string = "*3001#12345#*" } }
                    Text("Les menus et les valeurs disponibles changent selon l’iPhone, iOS et l’opérateur. iOS ne permet pas à Pylo de lire automatiquement le RSRP, le RSRQ, le SINR ou la cellule connectée.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Mon relevé manuel") {
                    Picker("Réseau", selection: $draft.generation) { ForEach(["3G","4G","5G"], id: \.self) { Text($0) } }
                    TextField("RSRP (dBm), ex. −95", text: $draft.rsrp).keyboardType(.numbersAndPunctuation)
                    TextField("RSRQ (dB), ex. −12", text: $draft.rsrq).keyboardType(.numbersAndPunctuation)
                    TextField("SINR (dB), ex. 20", text: $draft.sinr).keyboardType(.numbersAndPunctuation)
                    TextField("Identifiant de cellule", text: $draft.cellID)
                    TextField("Lieu, contexte, petite remarque…", text: $draft.note, axis: .vertical)
                    Button("Enregistrer sur mon iPhone", systemImage: "square.and.arrow.down") {
                        draft.date = Date(); store.measurements.insert(draft, at: 0); draft = Measurement(); saved = true
                    }.disabled([draft.rsrp,draft.rsrq,draft.sinr,draft.cellID,draft.note].allSatisfy { $0.isEmpty })
                }
                Section("Décoder un ECI 4G") {
                    TextField("ECI décimal", text: $eci).keyboardType(.numberPad)
                    if let number = UInt32(eci), number <= 268435455 { LabeledContent("eNodeB", value: String(Radio.enodeB(number))); LabeledContent("Secteur", value: String(Radio.sector(number))) }
                    Text("ECI ÷ 256 = eNodeB, reste = secteur. L’eNodeB n’est pas l’identifiant ANFR. Cette formule ne s’applique pas au NCI 5G.").font(.footnote)
                }
                Section("Mes relevés · \(store.measurements.count)") {
                    ForEach(store.measurements) { m in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(m.generation) · \(m.date.formatted(date: .abbreviated, time: .shortened))").font(.headline)
                            Text("RSRP \(m.rsrp.isEmpty ? "—" : m.rsrp) · RSRQ \(m.rsrq.isEmpty ? "—" : m.rsrq) · SINR \(m.sinr.isEmpty ? "—" : m.sinr)").font(.caption)
                            if !m.cellID.isEmpty { Text("Cellule : \(m.cellID)").font(.caption) }
                            if !m.note.isEmpty { Text(m.note).font(.subheadline) }
                        }
                    }.onDelete { store.measurements.remove(atOffsets: $0) }
                    if !store.measurements.isEmpty {
                        ShareLink("Exporter mes relevés JSON", item: String(data: (try? JSONEncoder().encode(store.measurements)) ?? Data(), encoding: .utf8) ?? "[]")
                    }
                }
            }.navigationTitle("Field Test").alert("Relevé enregistré", isPresented: $saved) { Button("OK", role: .cancel) {} }
        }
    }
}
