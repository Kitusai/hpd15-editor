import SwiftUI
import HPD15Core

/// Feuille « Enregistrer sous… » : copie le set en cours dans un nouveau fichier sur le Mac.
struct SaveAsSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.presentationMode) private var presentation
    @State private var name = ""
    @State private var details = ""
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Enregistrer le set sous…")).font(.headline)
            Text(L("Le set tel qu'il sonne sur le HPD-15 est copié dans un fichier de votre bibliothèque. Rien n'est écrit dans les mémoires du HPD-15. Les 10 premiers caractères du nom deviennent le nom du set sur l'appareil."))
                .font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            TextField(L("Nom"), text: $name).textFieldStyle(.roundedBorder)
            Text(L("Description")).font(.system(size: 11)).foregroundColor(Theme.dim)
            TextEditor(text: $details).frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15)))
            TextField(L("Étiquettes (séparées par des virgules)"), text: $tags).textFieldStyle(.roundedBorder)
            Text(Lf("Dossier : %@", m.library.folder.path)).font(.system(size: 10)).foregroundColor(Theme.dim)
                .lineLimit(1).truncationMode(.head)
            HStack {
                Spacer()
                Button(L("Annuler")) { presentation.wrappedValue.dismiss() }.buttonStyle(SoftButtonStyle())
                Button(L("Enregistrer")) {
                    m.saveAs(name: name, details: details, tags: splitTags(tags))
                    presentation.wrappedValue.dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 480)
        .onAppear {
            if let e = m.loadedEntry {
                name = e.item.name + L(" copie")
                details = e.item.details
                tags = e.item.tags.joined(separator: ", ")
            } else {
                name = m.image.name ?? ""
            }
        }
    }
}

func splitTags(_ s: String) -> [String] {
    s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// Écran « Bibliothèque » : les sets enregistrés sur le Mac.
struct LibraryView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject var library: LibraryStore
    @ObservedObject private var palette = Palette.shared
    @State private var query = ""
    @State private var selection: UUID?
    @State private var draftName = ""
    @State private var draftDetails = ""
    @State private var draftTags = ""
    @State private var confirmTrash = false
    @State private var confirmSend = false

    private var filtered: [LibraryStore.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return library.entries }
        return library.entries.filter { e in
            e.item.name.lowercased().contains(q) || e.item.details.lowercased().contains(q)
                || e.item.tags.contains(where: { $0.lowercased().contains(q) })
                || e.item.zones.contains(where: { $0.sound.lowercased().contains(q) })
                || e.item.origin.lowercased().contains(q)
        }
    }

    private var current: LibraryStore.Entry? { library.entry(selection) }

    private var draftChanged: Bool {
        guard let e = current else { return false }
        return draftName != e.item.name || draftDetails != e.item.details || splitTags(draftTags) != e.item.tags
    }

    var body: some View {
        HStack(spacing: 0) {
            list
            Divider().overlay(Theme.stroke)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selection == nil, let id = m.loadedEntryID, let e = library.entry(id) { select(e) }
        }
        .alert(L("Mettre à la corbeille ?"), isPresented: $confirmTrash) {
            Button(L("Annuler"), role: .cancel) {}
            Button(L("Mettre à la corbeille"), role: .destructive) {
                if let e = current { library.trash(e) }
                if m.loadedEntryID == selection { m.loadedEntryID = nil }
                selection = nil
            }
        } message: {
            Text(current.map { Lf("Le fichier « %@ » sera déplacé dans la corbeille du Mac.", $0.url.lastPathComponent) } ?? "")
        }
        .alert(L("Remplacer le set en cours ?"), isPresented: $confirmSend) {
            Button(L("Annuler"), role: .cancel) {}
            Button(L("Envoyer quand même"), role: .destructive) { if let e = current { m.sendToDevice(e) } }
        } message: {
            Text(L("Le set en cours a des modifications non enregistrées. Elles seront perdues."))
        }
    }

    // MARK: Liste

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Bibliothèque")).font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Text("\(library.entries.count)").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.dim)
            }
            TextField(L("Rechercher (nom, son, étiquette)…"), text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filtered) { e in
                        Button { select(e) } label: { row(e) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(L("Envoyer au HPD-15")) { select(e); send(e) }
                                Button(L("Dupliquer")) { try? library.duplicate(e) }
                                Button(L("Afficher dans le Finder")) { library.reveal(e) }
                                Divider()
                                Button(L("Mettre à la corbeille")) { select(e); confirmTrash = true }
                            }
                    }
                    if filtered.isEmpty {
                        Text(library.entries.isEmpty
                             ? L("Aucun set enregistré.\nDans l'écran Set, utilisez « Enregistrer sous… ».")
                             : L("Aucun résultat"))
                            .font(.system(size: 12)).foregroundColor(Theme.dim).multilineTextAlignment(.center).padding(24)
                    }
                }
            }
            if let p = library.problem { Text(p).font(.system(size: 11)).foregroundColor(Theme.danger) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button { library.chooseFolder() } label: { Label(L("Dossier…"), systemImage: "folder") }.buttonStyle(SoftButtonStyle())
                    Text(library.folder.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        .help(library.folder.path)
                    Spacer()
                    Button { library.reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(SoftButtonStyle())
                        .help(L("Relire le dossier"))
                }
                Text(library.folder.deletingLastPathComponent().path).font(.system(size: 10)).foregroundColor(Theme.dim)
                    .lineLimit(1).truncationMode(.head)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Theme.panel)
    }

    private func row(_ e: LibraryStore.Entry) -> some View {
        let loaded = m.loadedEntryID == e.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.item.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(e.item.details.isEmpty ? e.item.origin : e.item.details)
                    .font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(1)
            }
            Spacer()
            if loaded { Chip(text: L("en cours"), color: Theme.accent.opacity(0.25), textColor: Theme.accent) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(selection == e.id ? Theme.accent.opacity(0.22) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 7))
    }

    private func select(_ e: LibraryStore.Entry) {
        selection = e.id
        draftName = e.item.name
        draftDetails = e.item.details
        draftTags = e.item.tags.joined(separator: ", ")
    }

    private func send(_ e: LibraryStore.Entry) {
        if m.dirty { confirmSend = true } else { m.sendToDevice(e) }
    }

    // MARK: Fiche

    @ViewBuilder private var detail: some View {
        if let e = current {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField(L("Nom"), text: $draftName)
                        .font(.system(size: 24, weight: .bold, design: .rounded)).textFieldStyle(.plain)
                    Text(Lf("%@ · créé le %@ · modifié le %@", e.item.origin, e.item.created.formatted(date: .abbreviated, time: .shortened), e.item.modified.formatted(date: .abbreviated, time: .shortened)))
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                    Text(L("Description")).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.dim)
                    TextEditor(text: $draftDetails)
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15)))
                    TextField(L("Étiquettes (séparées par des virgules)"), text: $draftTags).textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Button { send(e) } label: { Label(L("Envoyer au HPD-15"), systemImage: "arrow.up.forward.square") }
                            .buttonStyle(PrimaryButtonStyle()).disabled(!m.connected || m.busy)
                            .help(L("Charge ce set dans le patch en cours du HPD-15 (jamais dans une mémoire User), puis vérifie."))
                        Button(L("Enregistrer nom et description")) {
                            m.updateInfo(e, name: draftName, details: draftDetails, tags: splitTags(draftTags))
                            if let ne = library.entries.first(where: { $0.id == e.id }) { select(ne) }
                        }
                        .buttonStyle(SoftButtonStyle()).disabled(!draftChanged)
                        .help(L("Actif dès que le nom, la description ou les étiquettes changent. Pour enregistrer les sons, utilisez « Enregistrer » dans l'écran Set."))
                        Button(L("Dupliquer")) { try? library.duplicate(e) }.buttonStyle(SoftButtonStyle())
                        Button(L("Finder")) { library.reveal(e) }.buttonStyle(SoftButtonStyle())
                        Spacer()
                        Button { confirmTrash = true } label: { Label(L("Supprimer"), systemImage: "trash") }.buttonStyle(SoftButtonStyle())
                    }

                    HStack(spacing: 16) {
                        Label(Lf("Réverbération : %@", e.item.reverb), systemImage: "dot.radiowaves.left.and.right")
                        Label(Lf("Multi-effet : %@", e.item.multiEffect), systemImage: "sparkles")
                    }
                    .font(.system(size: 12)).foregroundColor(Theme.dim)

                    Text(L("Sons")).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.dim)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 4) {
                        ForEach(e.item.zones, id: \.zone) { z in
                            HStack(spacing: 6) {
                                Circle().fill(palette.color(m.catalog?.instruments.first(where: { $0.code == z.code })?.category))
                                    .frame(width: 7, height: 7)
                                Text(z.zone).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(Theme.accent)
                                    .frame(width: 58, alignment: .leading)
                                Text(z.sound).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                .padding(20)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "folder").font(.system(size: 34)).foregroundColor(Theme.dim)
                Text(L("Sélectionnez un set")).foregroundColor(Theme.dim)
            }
        }
    }
}
