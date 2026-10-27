import Foundation

/// Interface language, switchable at runtime (no .lproj bundles: the app is built without Xcode)
enum Lang: String, CaseIterable, Identifiable, Sendable {
    case en, de, fr
    var id: String { rawValue }
    var name: String {
        switch self {
        case .en: "English"
        case .de: "Deutsch"
        case .fr: "Français"
        }
    }
}

enum L10n {
    static let defaultsKey = "language"

    /// Saved choice, otherwise the system language if it's German or French
    nonisolated(unsafe) static var lang: Lang = {
        if let s = UserDefaults.standard.string(forKey: defaultsKey), let l = Lang(rawValue: s) { return l }
        let sys = Locale.preferredLanguages.first?.prefix(2) ?? "en"
        return Lang(rawValue: String(sys)) ?? .en
    }()

    /// Switches the interface language. AppleLanguages makes macOS's own menus follow after a restart.
    static func set(_ new: Lang) {
        lang = new
        UserDefaults.standard.set([new.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.set(new.rawValue, forKey: defaultsKey)   // last: views observe this key
    }

    static func text(_ key: String, _ lang: Lang) -> String {
        switch lang {
        case .en: key
        case .de: table[key]?.de ?? key
        case .fr: table[key]?.fr ?? key
        }
    }

    /// English text → German (Swiss spelling) and French. Keys with %d / %@ are format strings.
    static let table: [String: (de: String, fr: String)] = [
        // Tools
        "Convert": ("Konvertieren", "Convertir"),
        "Compress": ("Komprimieren", "Compresser"),
        "Resize": ("Grösse ändern", "Redimensionner"),
        "Rotate": ("Drehen", "Pivoter"),
        "Remove Info": ("Infos entfernen", "Supprimer les infos"),
        "Rename": ("Umbenennen", "Renommer"),
        "Combine to PDF": ("Zu PDF kombinieren", "Combiner en PDF"),
        "Split PDF": ("PDF teilen", "Diviser un PDF"),
        "Reorder Pages": ("Seiten ordnen", "Réordonner les pages"),
        "Word to PDF": ("Word zu PDF", "Word en PDF"),
        "Save Word documents as PDFs with the exact Word layout":
            ("Word-Dokumente als PDF sichern, mit genau dem Layout aus Word",
             "Enregistrer des documents Word en PDF avec la mise en page exacte de Word"),
        "Create PDFs": ("PDFs erstellen", "Créer les PDF"),
        "Turn photos into another format, or PDF pages into images":
            ("Fotos in ein anderes Format umwandeln oder PDF-Seiten in Bilder",
             "Convertir des photos dans un autre format, ou des pages PDF en images"),
        "Make photos and PDFs smaller while keeping them sharp":
            ("Fotos und PDFs verkleinern, ohne dass sie unscharf werden",
             "Réduire la taille des photos et des PDF tout en gardant leur netteté"),
        "Scale photos down to a given size":
            ("Fotos auf eine bestimmte Grösse verkleinern", "Réduire les photos à une taille donnée"),
        "Turn photos or PDF pages": ("Fotos oder PDF-Seiten drehen", "Faire pivoter des photos ou des pages PDF"),
        "Remove camera, date and location info before sharing":
            ("Kamera-, Datums- und Ortsangaben vor dem Teilen entfernen",
             "Supprimer les infos d’appareil, de date et de lieu avant de partager"),
        "Change file names: add text or number them":
            ("Dateinamen ändern: Text hinzufügen oder durchnummerieren",
             "Modifier les noms de fichiers : ajouter du texte ou les numéroter"),
        "Put photos and PDFs together into one PDF":
            ("Fotos und PDFs zu einem PDF zusammenfügen", "Réunir des photos et des PDF en un seul PDF"),
        "Take pages out of a PDF or cut it into parts":
            ("Seiten aus einem PDF herausnehmen oder es in Teile zerlegen",
             "Extraire des pages d’un PDF ou le découper en parties"),
        "Drag PDF pages into a new order":
            ("PDF-Seiten in eine neue Reihenfolge ziehen", "Glisser les pages d’un PDF dans un nouvel ordre"),
        "Create PDF": ("PDF erstellen", "Créer le PDF"),
        "Split": ("Teilen", "Diviser"),
        "Save": ("Sichern", "Enregistrer"),
        "%@ Again": ("%@ wiederholen", "%@ à nouveau"),

        // Sidebar
        "Convert & Compress": ("Konvertieren & Komprimieren", "Convertir et compresser"),
        "Edit": ("Bearbeiten", "Modifier"),
        "Language": ("Sprache", "Langue"),

        // Items and status
        "All %d pages": ("Alle %d Seiten", "Toutes les %d pages"),
        "%d of %d pages": ("%d von %d Seiten", "%1$d pages sur %2$d"),
        "1 PDF": ("1 PDF", "1 PDF"),
        "%d PDFs": ("%d PDFs", "%d PDF"),
        "Original order": ("Ursprüngliche Reihenfolge", "Ordre d’origine"),
        "New order: ": ("Neue Reihenfolge: ", "Nouvel ordre : "),
        "Ready": ("Bereit", "Prêt"),
        "Working…": ("In Arbeit…", "En cours…"),
        "Waiting…": ("Wartet…", "En attente…"),
        "Adding…": ("Wird hinzugefügt…", "Ajout…"),
        "Added": ("Hinzugefügt", "Ajouté"),
        "Error: ": ("Fehler: ", "Erreur : "),
        "Page %d of %d…": ("Seite %d von %d…", "Page %d sur %d…"),
        "%d images": ("%d Bilder", "%d images"),
        ", smallest possible": (", kleinstmöglich", ", taille minimale atteinte"),
        "Compressed copy moved to Trash": ("Komprimierte Kopie in den Papierkorb gelegt", "Copie compressée placée dans la corbeille"),
        "Not used by this tool": ("Von diesem Werkzeug nicht verwendet", "Non utilisé par cet outil"),
        "Choose": ("Auswählen", "Choisir"),

        // Combine
        "Combined": ("Kombiniert", "Combiné"),
        "Created “%@”: %d pages, %@": ("«%@» erstellt: %d Seiten, %@", "« %@ » créé : %d pages, %@"),
        "Nothing to combine": ("Nichts zum Kombinieren", "Rien à combiner"),

        // Rename
        "Photo ###": ("Foto ###", "Photo ###"),
        "“%@” already exists": ("«%@» existiert bereits", "« %@ » existe déjà"),
        "Nothing renamed: a file with one of the new names already exists":
            ("Nichts umbenannt: Eine Datei mit einem der neuen Namen existiert bereits",
             "Rien n’a été renommé : un fichier portant l’un des nouveaux noms existe déjà"),
        "Nothing renamed: ": ("Nichts umbenannt: ", "Rien n’a été renommé : "),
        "✓ was “%@”": ("✓ war «%@»", "✓ anciennement « %@ »"),
        "Renamed 1 file": ("1 Datei umbenannt", "1 fichier renommé"),
        "Renamed %d files": ("%d Dateien umbenannt", "%d fichiers renommés"),
        "Undo failed: ": ("Rückgängig fehlgeschlagen: ", "Échec de l’annulation : "),
        "Original names restored": ("Ursprüngliche Namen wiederhergestellt", "Noms d’origine rétablis"),

        // New names (Rename, Word to PDF)
        "Keep name": ("Name behalten", "Garder le nom"),
        "Add text": ("Text hinzufügen", "Ajouter du texte"),
        "New name + number": ("Neuer Name + Nummer", "Nouveau nom + numéro"),
        "Document ###": ("Dokument ###", "Document ###"),
        "Text before the name": ("Text vor dem Namen", "Texte avant le nom"),
        "Text after the name": ("Text nach dem Namen", "Texte après le nom"),
        "Before": ("Davor", "Avant"),
        "After": ("Danach", "Après"),
        "+ name +": ("+ Name +", "+ nom +"),
        "first number %d": ("erste Nummer %d", "premier numéro %d"),
        "Report": ("Bericht", "Rapport"),
        "Adds text in front of and/or behind the current name: “%@” becomes “%@”.":
            ("Fügt Text vor und/oder nach dem bisherigen Namen ein: «%@» wird zu «%@».",
             "Ajoute du texte avant et/ou après le nom actuel : « %@ » devient « %@ »."),
        "Example: “%@”, “%@”, …": ("Beispiel: «%@», «%@», …", "Exemple : « %@ », « %@ », …"),
        "The whole name is replaced. # marks where the number goes (### = 3 digits).":
            ("Der ganze Name wird ersetzt. # zeigt, wo die Nummer steht (### = 3 Stellen).",
             "Tout le nom est remplacé. # indique où va le numéro (### = 3 chiffres)."),
        "Files are renamed in place. The arrow in the list shows the new name.":
            ("Die Dateien werden direkt umbenannt. Der Pfeil in der Liste zeigt den neuen Namen.",
             "Les fichiers sont renommés sur place. La flèche dans la liste indique le nouveau nom."),

        // Word to PDF
        "The PDFs get the names of the Word documents. Microsoft Word makes them, so they look exactly like the document in Word.":
            ("Die PDFs erhalten die Namen der Word-Dokumente. Microsoft Word erstellt sie, sie sehen also genau gleich aus wie in Word.",
             "Les PDF portent le nom des documents Word. Microsoft Word les crée, ils sont donc identiques au document dans Word."),
        "1 page": ("1 Seite", "1 page"),
        "%d pages": ("%d Seiten", "%d pages"),
        "Word is creating the PDF…": ("Word erstellt das PDF…", "Word crée le PDF…"),
        "Drop Word documents or folders here":
            ("Word-Dokumente oder Ordner hierher ziehen", "Déposez des documents Word ou des dossiers ici"),
        "Microsoft Word is needed for this": ("Dafür wird Microsoft Word benötigt", "Microsoft Word est nécessaire pour cela"),
        "Word didn't respond. Is the file password protected, or is a dialog open in Word?":
            ("Word reagiert nicht. Ist die Datei passwortgeschützt oder ist in Word ein Dialog offen?",
             "Word ne répond pas. Le fichier est-il protégé par un mot de passe, ou une boîte de dialogue est-elle ouverte dans Word ?"),
        "Word didn't open the file. Is a dialog open in Word?":
            ("Word hat die Datei nicht geöffnet. Ist in Word ein Dialog offen?",
             "Word n’a pas ouvert le fichier. Une boîte de dialogue est-elle ouverte dans Word ?"),
        "Not allowed to control Word: turn on File Tools › Microsoft Word in System Settings › Privacy & Security › Automation":
            ("Keine Berechtigung für Word: In den Systemeinstellungen › Datenschutz & Sicherheit › Automation «File Tools › Microsoft Word» einschalten",
             "Pas autorisé à contrôler Word : activez File Tools › Microsoft Word dans Réglages Système › Confidentialité et sécurité › Automatisation"),
        "Word: ": ("Word: ", "Word : "),
        "Not converted: Word wasn't responding":
            ("Nicht konvertiert: Word hat nicht reagiert", "Non converti : Word ne répondait pas"),
        "Combine into one PDF": ("Zu einem PDF zusammenfügen", "Réunir en un seul PDF"),
        "Without tracked changes and comments": ("Ohne Änderungen und Kommentare", "Sans modifications suivies ni commentaires"),
        "Accepts all tracked changes and removes comments in the copy Word works on. The Word document itself stays unchanged.":
            ("Nimmt alle nachverfolgten Änderungen an und entfernt Kommentare in der Kopie, mit der Word arbeitet. Das Word-Dokument selbst bleibt unverändert.",
             "Accepte toutes les modifications suivies et supprime les commentaires dans la copie utilisée par Word. Le document Word lui-même reste inchangé."),
        "Update fields and table of contents": ("Felder und Inhaltsverzeichnis aktualisieren", "Mettre à jour les champs et la table des matières"),
        "Updates page numbers, cross-references and tables of contents before the PDF is made, as Word does before printing.":
            ("Aktualisiert Seitenzahlen, Querverweise und Inhaltsverzeichnisse, bevor das PDF entsteht, wie Word es vor dem Drucken tut.",
             "Met à jour les numéros de page, les renvois et les tables des matières avant de créer le PDF, comme Word le fait avant l’impression."),
        "Documents are added in list order, each with a bookmark. Drag to reorder or use Sort.":
            ("Die Dokumente werden in der Reihenfolge der Liste angefügt, jedes mit einem Lesezeichen. Zum Umordnen ziehen oder «Sortieren» verwenden.",
             "Les documents sont ajoutés dans l’ordre de la liste, chacun avec un signet. Glissez pour réordonner ou utilisez Trier."),
        "Compressing…": ("Wird komprimiert…", "Compression…"),

        // Engine messages
        "Already under %@": ("Bereits unter %@", "Déjà sous %@"),
        "Trying step %d of %d…": ("Versuch %d von %d…", "Essai %d sur %d…"),
        "Already small, original kept": ("Bereits klein, Original behalten", "Déjà léger, original conservé"),
        "File can't be read": ("Datei kann nicht gelesen werden", "Impossible de lire le fichier"),
        "Image can't be read": ("Bild kann nicht gelesen werden", "Impossible de lire l’image"),
        "Can't write to destination": ("Ziel kann nicht beschrieben werden", "Impossible d’écrire à la destination"),
        "Writing failed": ("Schreiben fehlgeschlagen", "Échec de l’écriture"),
        "Invalid size": ("Ungültige Grösse", "Taille non valide"),
        "Already %d×%d, left as is": ("Bereits %d×%d, unverändert", "Déjà %d×%d, laissé tel quel"),
        "Not enough memory": ("Nicht genug Speicher", "Mémoire insuffisante"),
        "Rotating failed": ("Drehen fehlgeschlagen", "Échec de la rotation"),
        "macOS can't save this format, convert it first":
            ("macOS kann dieses Format nicht sichern, zuerst konvertieren",
             "macOS ne peut pas enregistrer ce format, convertissez-le d’abord"),
        "No location stored": ("Kein Ort gespeichert", "Aucun lieu enregistré"),
        "PDF can't be read": ("PDF kann nicht gelesen werden", "Impossible de lire le PDF"),
        "PDF is password protected": ("PDF ist passwortgeschützt", "Le PDF est protégé par un mot de passe"),
        "Page %d can't be rendered": ("Seite %d kann nicht dargestellt werden", "Impossible d’afficher la page %d"),
        "Compression filter unavailable": ("Komprimierungsfilter nicht verfügbar", "Filtre de compression indisponible"),
        "Page order doesn't match the PDF":
            ("Seitenreihenfolge passt nicht zum PDF", "L’ordre des pages ne correspond pas au PDF"),
        "%@ can't be read": ("%@ kann nicht gelesen werden", "Impossible de lire %@"),
        "PDF can't be created": ("PDF kann nicht erstellt werden", "Impossible de créer le PDF"),

        // Output file names: "photo (compressed).jpg", "doc - page 3.pdf"
        "compressed": ("komprimiert", "compressé"),
        "rotated": ("gedreht", "pivoté"),
        "no info": ("ohne Infos", "sans infos"),
        "no location": ("ohne Ort", "sans lieu"),
        "reordered": ("neu geordnet", "réordonné"),
        "page": ("Seite", "page"),
        "pages": ("Seiten", "pages"),
        "part": ("Teil", "partie"),

        // Settings
        "Works everywhere": ("Funktioniert überall", "Compatible partout"),
        "Lossless, keeps transparency": ("Verlustfrei, behält Transparenz", "Sans perte, conserve la transparence"),
        "Small files, best on Apple devices":
            ("Kleine Dateien, ideal für Apple-Geräte", "Fichiers légers, idéal sur les appareils Apple"),
        "Smallest files, for the web": ("Kleinste Dateien, fürs Web", "Fichiers les plus légers, pour le web"),
        "Lossless, for print and archiving":
            ("Verlustfrei, für Druck und Archiv", "Sans perte, pour l’impression et l’archivage"),
        "High quality": ("Hohe Qualität", "Haute qualité"),
        "Balanced": ("Ausgewogen", "Équilibré"),
        "Smallest": ("Am kleinsten", "Le plus léger"),
        "Barely visible difference, good for printing":
            ("Kaum sichtbarer Unterschied, gut zum Drucken", "Différence à peine visible, idéal pour l’impression"),
        "Looks the same on screen, much smaller":
            ("Am Bildschirm gleich, viel kleiner", "Identique à l’écran, beaucoup plus léger"),
        "For email and web, still sharp on screen":
            ("Für E-Mail und Web, am Bildschirm noch scharf", "Pour l’e-mail et le web, toujours net à l’écran"),
        "Quality level": ("Qualitätsstufe", "Niveau de qualité"),
        "Target size": ("Zielgrösse", "Taille cible"),
        "Longest side": ("Längste Seite", "Côté le plus long"),
        "Width": ("Breite", "Largeur"),
        "Height": ("Höhe", "Hauteur"),
        "Percentage": ("Prozent", "Pourcentage"),
        "Everything": ("Alles", "Tout"),
        "Location only": ("Nur Ort", "Lieu uniquement"),
        "Same as image": ("Wie Bild", "Comme l’image"),
        "Each page separately": ("Jede Seite einzeln", "Chaque page séparément"),
        "Every few pages": ("Alle paar Seiten", "Par groupes de pages"),

        // Tool view
        "Save to:": ("Sichern in:", "Enregistrer dans :"),
        "same folder as original": ("gleicher Ordner wie Original", "même dossier que l’original"),
        "Reset": ("Zurücksetzen", "Réinitialiser"),
        "Choose Folder…": ("Ordner wählen…", "Choisir un dossier…"),
        "Choose Files…": ("Dateien wählen…", "Choisir des fichiers…"),
        "Drop photos or folders here": ("Fotos oder Ordner hierher ziehen", "Déposez des photos ou des dossiers ici"),
        "Drop PDFs here": ("PDFs hierher ziehen", "Déposez des PDF ici"),
        "Drop photos, PDFs or folders here":
            ("Fotos, PDFs oder Ordner hierher ziehen", "Déposez des photos, des PDF ou des dossiers ici"),
        "Compare": ("Vergleichen", "Comparer"),
        "Format": ("Format", "Format"),
        "Quality": ("Qualität", "Qualité"),
        "PDF pages at": ("PDF-Seiten mit", "Pages PDF en"),
        "72 dpi (screen)": ("72 dpi (Bildschirm)", "72 dpi (écran)"),
        "300 dpi (print)": ("300 dpi (Druck)", "300 dpi (impression)"),
        "Smaller than": ("Kleiner als", "Moins de"),
        "MB": ("MB", "Mo"),
        "Tries gentle settings first and only goes further when needed":
            ("Versucht zuerst schonende Einstellungen und geht nur wenn nötig weiter",
             "Essaie d’abord des réglages doux et ne va plus loin que si nécessaire"),
        "pixels": ("Pixel", "pixels"),
        "Only makes photos smaller. Format and photo info are kept.":
            ("Macht Fotos nur kleiner. Format und Fotoinfos bleiben erhalten.",
             "Ne fait que réduire les photos. Le format et les infos sont conservés."),
        "90° right": ("90° rechts", "90° à droite"),
        "90° left": ("90° links", "90° à gauche"),
        "For PDFs, only the selected pages are turned (all if none selected)":
            ("Bei PDFs werden nur die ausgewählten Seiten gedreht (alle, wenn keine ausgewählt)",
             "Pour les PDF, seules les pages choisies sont pivotées (toutes si aucune n’est choisie)"),
        "Removes camera, date and location. The image itself stays exactly the same.":
            ("Entfernt Kamera, Datum und Ort. Das Bild selbst bleibt genau gleich.",
             "Supprime l’appareil, la date et le lieu. L’image elle-même reste identique."),
        "Removes only where the photo was taken. The image itself stays exactly the same.":
            ("Entfernt nur, wo das Foto aufgenommen wurde. Das Bild selbst bleibt genau gleich.",
             "Supprime uniquement le lieu de la prise de vue. L’image elle-même reste identique."),
        "For PDFs, removes author, title and other document info.":
            ("Bei PDFs werden Autor, Titel und weitere Dokumentinfos entfernt.",
             "Pour les PDF, supprime l’auteur, le titre et les autres infos du document."),
        "New name": ("Neuer Name", "Nouveau nom"),
        "Undo Rename": ("Umbenennen widerrufen", "Annuler le renommage"),
        "Name": ("Name", "Nom"),
        "Photo pages": ("Fotoseiten", "Pages photo"),
        "Margin": ("Rand", "Marge"),
        "Files are added in list order. Drag to reorder or use Sort. PDF pages are added unchanged.":
            ("Die Dateien werden in der Reihenfolge der Liste hinzugefügt. Zum Umordnen ziehen oder «Sortieren» verwenden. PDF-Seiten werden unverändert übernommen.",
             "Les fichiers sont ajoutés dans l’ordre de la liste. Glissez pour réordonner ou utilisez Trier. Les pages PDF sont ajoutées telles quelles."),
        "%d pages each": ("je %d Seiten", "%d pages chacun"),
        "Add…": ("Hinzufügen…", "Ajouter…"),
        "Clear List": ("Liste leeren", "Vider la liste"),
        "Sort": ("Sortieren", "Trier"),
        "By Name": ("Nach Name", "Par nom"),
        "By Date Taken": ("Nach Aufnahmedatum", "Par date de prise de vue"),
        "Reverse Order": ("Reihenfolge umkehren", "Inverser l’ordre"),
        "Show in Finder": ("Im Finder zeigen", "Afficher dans le Finder"),

        // Sheets
        "%d of %d selected": ("%d von %d ausgewählt", "%1$d sur %2$d sélectionnées"),
        "Pages, e.g. 1-3, 5, 8-": ("Seiten, z. B. 1-3, 5, 8-", "Pages, p. ex. 1-3, 5, 8-"),
        "Apply": ("Anwenden", "Appliquer"),
        "All": ("Alle", "Toutes"),
        "None": ("Keine", "Aucune"),
        "Cancel": ("Abbrechen", "Annuler"),
        "Done": ("Fertig", "OK"),
        "New PDF": ("Neues PDF", "Nouveau PDF"),
        "Pages for PDF %d, e.g. 1-3, 5": ("Seiten für PDF %d, z. B. 1-3, 5", "Pages pour le PDF %d, p. ex. 1-3, 5"),
        "Add": ("Hinzufügen", "Ajouter"),
        "All Remaining": ("Alle übrigen", "Toutes les restantes"),
        "Clear All": ("Alles zurücksetzen", "Tout effacer"),
        "Remove PDF %d": ("PDF %d entfernen", "Supprimer le PDF %d"),
        "Remove this PDF": ("Dieses PDF entfernen", "Supprimer ce PDF"),
        "Original · %@": ("Original · %@", "Original · %@"),
        "Compressed · %@": ("Komprimiert · %@", "Compressé · %@"),
        "Drag to compare": ("Zum Vergleichen ziehen", "Faites glisser pour comparer"),
        "Page %d of %d": ("Seite %d von %d", "Page %d sur %d"),
        "Zoom": ("Zoom", "Zoom"),
        "Fit": ("Einpassen", "Ajuster"),
        "Move Compressed Copy to Trash": ("Komprimierte Kopie in den Papierkorb legen", "Placer la copie compressée dans la corbeille"),
        "Keep": ("Behalten", "Conserver"),
        // Page overview
        "Selected pages": ("Ausgewählte Seiten", "Pages choisies"),
        "No pages selected yet": ("Noch keine Seiten ausgewählt", "Aucune page choisie pour l’instant"),
        "No pages selected yet: click pages in the overview first":
            ("Noch keine Seiten ausgewählt: zuerst in der Übersicht Seiten anklicken",
             "Aucune page choisie : cliquez d’abord sur des pages dans l’aperçu"),
        "No pages selected = all pages are used":
            ("Keine Seiten ausgewählt = alle Seiten werden verwendet",
             "Aucune page choisie = toutes les pages sont utilisées"),
        "%d of %d pages selected": ("%d von %d Seiten ausgewählt", "%1$d pages choisies sur %2$d"),
        "Click pages to add them to the new PDF, shift-click for a range. Use New PDF to make several PDFs at once, each in its own colour.":
            ("Seiten anklicken, um sie zum neuen PDF hinzuzufügen, Shift-Klick für einen Bereich. Mit «Neues PDF» lassen sich mehrere PDFs auf einmal erstellen, jedes in eigener Farbe.",
             "Cliquez sur les pages pour les ajouter au nouveau PDF, Maj-clic pour une plage. « Nouveau PDF » permet d’en créer plusieurs d’un coup, chacun dans sa couleur."),
        "Makes a new PDF from the pages you click above. Add more PDFs to split into several at once.":
            ("Erstellt ein neues PDF aus den Seiten, die oben angeklickt sind. Mit weiteren PDFs lässt sich in einem Schritt in mehrere aufteilen.",
             "Crée un nouveau PDF à partir des pages cliquées ci-dessus. Ajoutez d’autres PDF pour en créer plusieurs d’un coup."),
        "Makes one PDF per page. The page selection above limits which pages (all if none selected).":
            ("Erstellt ein PDF pro Seite. Die Seitenauswahl oben schränkt die Seiten ein (alle, wenn keine ausgewählt).",
             "Crée un PDF par page. La sélection ci-dessus limite les pages concernées (toutes si aucune n’est choisie)."),
        "Cuts the PDF into parts of %d pages. The page selection above limits which pages (all if none selected).":
            ("Teilt das PDF in Teile zu je %d Seiten. Die Seitenauswahl oben schränkt die Seiten ein (alle, wenn keine ausgewählt).",
             "Découpe le PDF en parties de %d pages. La sélection ci-dessus limite les pages concernées (toutes si aucune n’est choisie)."),
        "Drag the pages above into the order you want. Click another PDF in the list to arrange its pages. The PDF is saved as a new file.":
            ("Die Seiten oben in die gewünschte Reihenfolge ziehen. Ein anderes PDF in der Liste anklicken, um dessen Seiten anzuordnen. Das PDF wird als neue Datei gesichert.",
             "Glissez les pages ci-dessus dans l’ordre voulu. Cliquez sur un autre PDF de la liste pour arranger ses pages. Le PDF est enregistré dans un nouveau fichier."),
        "Drag pages to move them. Right-click a page to move it to the beginning or end.":
            ("Seiten ziehen, um sie zu verschieben. Rechtsklick auf eine Seite, um sie an den Anfang oder ans Ende zu setzen.",
             "Glissez les pages pour les déplacer. Clic droit sur une page pour la placer au début ou à la fin."),
        "File name for PDF %d": ("Dateiname für PDF %d", "Nom de fichier du PDF %d"),
        "Optional": ("Optional", "Facultatif"),
        "Reverse": ("Umkehren", "Inverser"),
        "Order changed": ("Reihenfolge geändert", "Ordre modifié"),
        "Move to Beginning": ("An den Anfang", "Placer au début"),
        "Move to End": ("Ans Ende", "Placer à la fin"),
        "was %d": ("vorher %d", "avant %d"),
        // Window, toolbar, menus
        "1 file": ("1 Datei", "1 fichier"),
        "%d files": ("%d Dateien", "%d fichiers"),
        "Add Files": ("Dateien hinzufügen", "Ajouter des fichiers"),
        "Add Files…": ("Dateien hinzufügen…", "Ajouter des fichiers…"),
        "Add photos, PDFs or folders (⌘O)": ("Fotos, PDFs oder Ordner hinzufügen (⌘O)", "Ajouter des photos, des PDF ou des dossiers (⌘O)"),
        "Choose Output Folder…": ("Zielordner wählen…", "Choisir le dossier de destination…"),
        "Sort the list": ("Liste sortieren", "Trier la liste"),
        "Remove all files from the list. The files themselves are not touched.":
            ("Alle Dateien aus der Liste entfernen. Die Dateien selbst bleiben unverändert.",
             "Retirer tous les fichiers de la liste. Les fichiers eux-mêmes ne sont pas modifiés."),
        "Remove from List": ("Aus Liste entfernen", "Retirer de la liste"),
        "Remove from list": ("Aus Liste entfernen", "Retirer de la liste"),
        "Show the new files in Finder (⇧⌘R)": ("Neue Dateien im Finder zeigen (⇧⌘R)", "Afficher les nouveaux fichiers dans le Finder (⇧⌘R)"),
        "Save to": ("Sichern in", "Enregistrer dans"),
        "Same folder as original": ("Gleicher Ordner wie das Original", "Même dossier que l’original"),
        "Use Original Folder": ("Originalordner verwenden", "Utiliser le dossier d’origine"),
        "Tool": ("Werkzeug", "Outil"),
        "Start": ("Starten", "Lancer"),
        "Extract": ("Extrahieren", "Extraire"),
        "Extract Images": ("Bilder extrahieren", "Extraire les images"),
        "Save the pictures inside a PDF as separate image files":
            ("Bilder aus einem PDF als einzelne Bilddateien sichern", "Enregistrer les images d’un PDF comme fichiers séparés"),
        "Compress by": ("Komprimieren nach", "Compresser selon"),
        "Level": ("Stufe", "Niveau"),
        "Maximum size in MB": ("Maximale Grösse in MB", "Taille maximale en Mo"),
        "Resize by": ("Grösse nach", "Redimensionner selon"),
        "Size": ("Grösse", "Taille"),
        "Rotation": ("Drehung", "Rotation"),
        "Remove": ("Entfernen", "Supprimer"),
        "Split mode": ("Teilen nach", "Mode de division"),
        "Page %d": ("Seite %d", "Page %d"),
        "Skip small images (icons, lines, logos under %d px)":
            ("Kleine Bilder überspringen (Symbole, Linien, Logos unter %d px)",
             "Ignorer les petites images (icônes, lignes, logos de moins de %d px)"),
        "Pictures are saved at their original resolution into a new folder. JPEGs are copied unchanged, others are saved as PNG.":
            ("Die Bilder werden in Originalauflösung in einen neuen Ordner gesichert. JPEGs werden unverändert kopiert, alle anderen als PNG gesichert.",
             "Les images sont enregistrées dans leur résolution d’origine dans un nouveau dossier. Les JPEG sont copiés tels quels, les autres enregistrés en PNG."),
        "Menus that come from macOS switch language after the app is restarted.":
            ("Menüs, die von macOS stammen, wechseln die Sprache nach einem Neustart der App.",
             "Les menus fournis par macOS changent de langue après le redémarrage de l’app."),
        // List undo, sharing, dragging out, stopping
        "Move": ("Verschieben", "Déplacer"),
        "Share": ("Teilen", "Partager"),
        "Send the new files by Mail, Messages, AirDrop and more":
            ("Die neuen Dateien per Mail, Nachrichten, AirDrop und mehr senden",
             "Envoyer les nouveaux fichiers par Mail, Messages, AirDrop, etc."),
        "Drag to put “%@” somewhere else": ("Ziehen, um «%@» woanders abzulegen", "Faire glisser pour déposer « %@ » ailleurs"),
        "Stop": ("Stoppen", "Arrêter"),
        "Stopping…": ("Wird gestoppt…", "Arrêt…"),
        "Stops after the file that is being worked on (Esc)":
            ("Stoppt nach der Datei, die gerade bearbeitet wird (Esc)", "S’arrête après le fichier en cours (Échap)"),
        "Stopped. The remaining files were not processed.":
            ("Gestoppt. Die übrigen Dateien wurden nicht bearbeitet.", "Arrêté. Les fichiers restants n’ont pas été traités."),
        "Stopped. No PDF was created.": ("Gestoppt. Es wurde kein PDF erstellt.", "Arrêté. Aucun PDF n’a été créé."),
    ]
}

/// Translates English UI text into the current language; extra arguments fill a format string
func tr(_ key: String, _ args: CVarArg...) -> String {
    let s = L10n.text(key, L10n.lang)
    return args.isEmpty ? s : String(format: s, arguments: args)
}
