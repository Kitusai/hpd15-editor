import Foundation

/// Langue de l'interface : automatique (langue du Mac), français ou anglais.
/// Les textes sont écrits en français dans le code ; `L()` renvoie leur traduction anglaise si besoin.
enum AppLanguage: String, CaseIterable, Identifiable {
    case auto, fr, en
    var id: String { rawValue }
    static let key = "appLanguage"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "auto") ?? .auto
    }

    /// Langue réellement utilisée.
    static var isEnglish: Bool {
        switch current {
        case .fr: return false
        case .en: return true
        case .auto: return !(Locale.preferredLanguages.first ?? "fr").lowercased().hasPrefix("fr")
        }
    }
}

/// Texte traduit (clé = texte français).
func L(_ fr: String) -> String {
    AppLanguage.isEnglish ? (englishStrings[fr] ?? fr) : fr
}

/// Texte traduit avec valeurs (`%@` pour du texte, `%d` pour un entier).
func Lf(_ fr: String, _ args: CVarArg...) -> String {
    String(format: L(fr), arguments: args)
}

/// Traductions anglaises. Toute clé absente reste en français (à compléter ici).
let englishStrings: [String: String] = [
    // Écrans
    "Set": "Set",
    "Effets du set": "Set effects",
    "Bibliothèque": "Library",
    "Réglages": "Settings",

    // Familles de sons
    "Latin": "Latin",
    "Afrique": "African",
    "Inde": "Indian",
    "Asie": "Asian",
    "Orchestre": "Orchestra",
    "Batterie": "Drums",
    "Dance": "Dance",
    "Effets": "SFX",
    "Mélodiques": "Melodic",

    // Zones
    "Ruban G": "Ribbon L",
    "Ruban D": "Ribbon R",
    "Ruban gauche": "Left ribbon",
    "Ruban droit": "Right ribbon",
    "Pédale": "Pedal",
    "RUBAN G": "RIBBON L",
    "RUBAN D": "RIBBON R",
    "PÉDALE": "PEDAL",
    "Pad %@": "Pad %@",

    // Fenêtre, barre latérale, connexion, journal
    "Editeur HPD-15": "HPD-15 Editor",
    "Erreur": "Error",
    "Information": "Information",
    "Journal MIDI (diagnostic)": "MIDI log (diagnostics)",
    "Pads : canal %d": "Pads: channel %d",
    "Canal des pads inconnu": "Pad channel unknown",
    "Non connecté": "Not connected",
    "HPD-15 connecté": "HPD-15 connected",
    "HPD-15 non trouvé": "HPD-15 not found",
    "Connexion MIDI": "MIDI connection",
    "Entrée": "Input",
    "Sortie": "Output",
    "Le HPD-15 est relié par ses prises MIDI à l'interface UM-ONE. Device ID d'usine : 17.":
        "The HPD-15 is connected through its MIDI ports to the UM-ONE interface. Factory Device ID: 17.",
    "Actualiser": "Refresh",
    "Connecter et lire": "Connect and read",
    "Journal MIDI": "MIDI log",
    "Copier": "Copy",
    "Effacer": "Clear",
    "Fermer": "Close",
    "Le HPD-15 a changé de patch": "The HPD-15 changed patch",
    "Renvoyer mon set": "Resend my set",
    "Lire %@": "Read %@",
    "L'appareil est passé sur %@. Le set « %@ » affiché ici a des modifications non enregistrées : il n'est plus sur le HPD-15. Renvoyez-le pour continuer à l'éditer (puis enregistrez-le), ou lisez le nouveau patch (les modifications seront perdues).":
        "The device switched to %@. The set “%@” shown here has unsaved changes: it is no longer on the HPD-15. Resend it to keep editing (then save it), or read the new patch (the changes will be lost).",

    // Messages du modèle
    "Le catalogue des sons (catalog-hpd15.json) est introuvable.": "The sound catalogue (catalog-hpd15.json) cannot be found.",
    "Connexion — entrée : %@ · sortie : %@ · Device ID %d": "Connection — input: %@ · output: %@ · Device ID %d",
    "le HPD-15 ne répond pas. Vérifiez le câblage MIDI (UM-ONE) et le Device ID.":
        "the HPD-15 does not answer. Check the MIDI cabling (UM-ONE) and the Device ID.",
    "lecture incomplète (manquent : %@).": "incomplete read (missing: %@).",
    "Le set n'est pas complet : relisez le HPD-15.": "The set is incomplete: read the HPD-15 again.",
    "Fichier « %@ »": "File “%@”",
    "Enregistrement : %@": "Saving: %@",
    "Sans titre": "Untitled",
    "Le fichier « %@ » est incomplet ou abîmé.": "The file “%@” is incomplete or damaged.",
    "Envoi de « %@ »": "Sending “%@”",
    "Envoi de « %@ »… %d/%d": "Sending “%@”… %d/%d",
    " (2e passage)": " (2nd pass)",
    "Vérification…": "Checking…",
    "%@ (octets %@)": "%@ (bytes %@)",
    "Envoyé, mais le HPD-15 n'a pas tout repris : %@. L'écran montre l'état réel de l'appareil.":
        "Sent, but the HPD-15 did not take everything: %@. The screen shows the device's actual state.",
    "Lecture du HPD-15": "Reading the HPD-15",
    "HPD-15 (patch en cours)": "HPD-15 (current patch)",
    "Modifications non enregistrées abandonnées (%@).": "Unsaved changes discarded (%@).",
    "Chargement de %@": "Loading %@",
    "canal des pads sur OFF dans le HPD-15.": "the pad channel is OFF on the HPD-15.",
    "Écriture : %@": "Write: %@",
    "banque %d n° %d": "bank %d no. %d",
    "Le HPD-15 est passé sur %@.": "The HPD-15 switched to %@.",
    "Lecture de %@": "Reading %@",

    // Contrôles
    "Double-clic : valeur par défaut (%d)": "Double-click: default value (%d)",
    "Valeur par défaut (%d)": "Default value (%d)",

    // Écran Set
    "Aucun set lu pour l'instant": "No set read yet",
    "HPD-15 non connecté": "HPD-15 not connected",
    "Choisissez l'entrée et la sortie « UM-ONE » (en bas à gauche), puis lisez le set en cours ou chargez un patch.":
        "Choose the “UM-ONE” input and output (bottom left), then read the current set or load a patch.",
    "Lire le set en cours du HPD-15": "Read the HPD-15 current set",
    "SET": "SET",
    "Nom (10 caractères)": "Name (10 characters)",
    "Nom du set sur le HPD-15 (validez avec Entrée).": "Set name on the HPD-15 (press Return to apply).",
    "modifié": "modified",
    "VOLUME DU SET  %d": "SET VOLUME  %d",
    "Enregistrer": "Save",
    "Écrase « %@ » avec le set en cours (⌘S).": "Overwrites “%@” with the current set (⌘S).",
    "Aucun fichier chargé : utilisez « Enregistrer sous… ».": "No file loaded: use “Save as…”.",
    "Enregistrer sous…": "Save as…",
    "Relire le HPD-15 : reprend le set en cours sur l'appareil (y compris les réglages faits sur l'appareil lui-même).":
        "Read the HPD-15 again: takes the device's current set (including settings made on the device itself).",
    "Presets d'usine": "Factory presets",
    "Mémoires User": "User memories",
    "Groupe U%02d": "Group U%02d",
    "Charger": "Load",
    "Charger %@": "Load %@",
    "Sélectionne le patch sur le HPD-15 puis le lit : il devient la base du set.":
        "Selects the patch on the HPD-15 then reads it: it becomes the base of the set.",
    "Remplacer le set en cours ?": "Replace the current set?",
    "Le set en cours a des modifications non enregistrées. Elles seront perdues.":
        "The current set has unsaved changes. They will be lost.",
    "Annuler": "Cancel",
    "Écouter": "Listen",
    "Fait sonner ce pad sur le HPD-15 (ou cliquez à nouveau sur le pad).": "Plays this pad on the HPD-15 (or click the pad again).",
    "Son %d": "Sound %d",
    "Niveau": "Level",
    "Durée (decay)": "Decay",
    "Balayage (sweep)": "Sweep",
    "Couleur": "Color",
    "Envoi réverbération": "Reverb send",
    "La réverbération du set est sur OFF : l'envoi n'a pas d'effet (choisissez-la dans « Effets du set »).":
        "The set reverb is OFF: the send has no effect (choose one in “Set effects”).",
    "Ce pad passe par le multi-effet": "This pad goes through the multi-effect",
    "Le type de multi-effet est commun à tout le set (écran « Effets du set »).":
        "The multi-effect type is shared by the whole set (“Set effects” screen).",
    "Multi-effet du set désactivé : à activer dans « Effets du set ».": "The set multi-effect is off: turn it on in “Set effects”.",
    "Zone non lue.": "Zone not read.",
    "Accord": "Tuning",
    "0 cent": "0 cent",
    "%+.0f dt": "%+.0f st",
    "Panoramique": "Pan",
    "Fixe (centre)": "Fixed (center)",
    "Aléatoire": "Random",
    "Alterné G/D": "Alternate L/R",
    "G%d": "L%d",
    "D%d": "R%d",
    "Aléa.": "Rnd",
    "Alt.": "Alt",
    "SONS": "SOUNDS",
    "— un clic remplace le son de %@": "— one click replaces the sound of %@",
    "Rechercher parmi les 601 sons (nom ou code, ex. « conga », « L11 »)": "Search the 601 sounds (name or code, e.g. “conga”, “L11”)",
    "Tous": "All",
    "%d sons": "%d sounds",

    // Écran Effets
    "— réglages communs à tous les pads de « %@ »": "— settings shared by all pads of “%@”",
    "Aucun set lu : lisez le HPD-15 ou chargez un patch depuis l'écran Set.": "No set read: read the HPD-15 or load a patch from the Set screen.",
    "Réverbération": "Reverb",
    "Type": "Type",
    "OFF (valeur 0)": "OFF (value 0)",
    "OFF (aucune réverbération)": "OFF (no reverb)",
    "Réverbération coupée : les envois des pads n'ont aucun effet.": "Reverb off: the pad sends have no effect.",
    "Durée": "Time",
    "Atténuation des aigus": "High damp",
    "Réinjection (délais)": "Feedback (delays)",
    "Algorithme": "Algorithm",
    "Multi-effet": "Multi-effect",
    "Actif": "On",
    "Bouton [MULTI EFFECTS] du HPD-15, mémorisé dans le set.": "The HPD-15 [MULTI EFFECTS] button, stored in the set.",
    "Multi-effet désactivé : aucune zone ne l'entend, même celles qui « passent par le multi-effet ».":
        "Multi-effect off: no zone is heard through it, even those routed to the multi-effect.",
    "00  (valeur 0)": "00  (value 0)",
    "Profondeur": "Depth",
    "Volume de sortie": "Output level",
    "Envoi vers réverb.": "Send to reverb",
    "Paramètres détaillés (valeurs brutes, codage non vérifié)": "Detailed parameters (raw values, encoding not verified)",
    "ZONES QUI PASSENT PAR LE MULTI-EFFET": "ZONES ROUTED TO THE MULTI-EFFECT",
    "Toutes": "All",
    "Aucune": "None",
    "Réglage propre à chaque zone (aussi dans l'inspecteur de l'écran Set). Le multi-effet lui-même est celui du set, ci-dessus.":
        "Per-zone setting (also in the Set screen inspector). The multi-effect itself is the set's one, above.",
    "Fixé par le HPD-15 selon le type choisi (lecture seule).": "Set by the HPD-15 according to the chosen type (read-only).",

    // Bibliothèque
    "Enregistrer le set sous…": "Save set as…",
    "Le set tel qu'il sonne sur le HPD-15 est copié dans un fichier de votre bibliothèque. Rien n'est écrit dans les mémoires du HPD-15. Les 10 premiers caractères du nom deviennent le nom du set sur l'appareil.":
        "The set as it sounds on the HPD-15 is copied to a file in your library. Nothing is written to the HPD-15 memories. The first 10 characters of the name become the set name on the device.",
    "Nom": "Name",
    "Description": "Description",
    "Étiquettes (séparées par des virgules)": "Tags (comma separated)",
    "Dossier : %@": "Folder: %@",
    " copie": " copy",
    "Mettre à la corbeille ?": "Move to Trash?",
    "Mettre à la corbeille": "Move to Trash",
    "Le fichier « %@ » sera déplacé dans la corbeille du Mac.": "The file “%@” will be moved to the Trash.",
    "Envoyer quand même": "Send anyway",
    "Rechercher (nom, son, étiquette)…": "Search (name, sound, tag)…",
    "Envoyer au HPD-15": "Send to HPD-15",
    "Dupliquer": "Duplicate",
    "Afficher dans le Finder": "Show in Finder",
    "Aucun set enregistré.\nDans l'écran Set, utilisez « Enregistrer sous… ».": "No saved set.\nIn the Set screen, use “Save as…”.",
    "Aucun résultat": "No result",
    "Dossier…": "Folder…",
    "Relire le dossier": "Reload folder",
    "en cours": "current",
    "%@ · créé le %@ · modifié le %@": "%@ · created %@ · modified %@",
    "Charge ce set dans le patch en cours du HPD-15 (jamais dans une mémoire User), puis vérifie.":
        "Loads this set into the HPD-15 current patch (never into a User memory), then checks it.",
    "Enregistrer nom et description": "Save name and description",
    "Actif dès que le nom, la description ou les étiquettes changent. Pour enregistrer les sons, utilisez « Enregistrer » dans l'écran Set.":
        "Enabled when the name, description or tags change. To save the sounds, use “Save” in the Set screen.",
    "Finder": "Finder",
    "Supprimer": "Delete",
    "Réverbération : %@": "Reverb: %@",
    "Multi-effet : %@": "Multi-effect: %@",
    "Sons": "Sounds",
    "Sélectionnez un set": "Select a set",
    " (désactivé)": " (off)",
    "Fichier(s) illisible(s) ignoré(s) : %@": "Unreadable file(s) ignored: %@",
    "Choisir": "Choose",

    // Réglages
    "ÉCOUTE": "LISTENING",
    "Faire sonner une zone quand on clique dessus": "Play a zone when clicking it",
    "Faire sonner le son choisi dans la liste": "Play the sound picked in the list",
    "Le son est joué par le HPD-15 lui-même (note envoyée sur le canal des pads).":
        "The sound is played by the HPD-15 itself (note sent on the pad channel).",
    "COULEURS DES FAMILLES DE SONS": "SOUND FAMILY COLORS",
    "Couleurs par défaut": "Default colors",
    "LANGUE": "LANGUAGE",
    "Langue de l'interface": "Interface language",
    "Automatique (langue du Mac)": "Automatic (Mac language)",
]
