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
        "Make photos, PDFs and videos smaller while keeping them sharp":
            ("Fotos, PDFs und Videos verkleinern, ohne dass sie unscharf werden",
             "Réduire la taille des photos, des PDF et des vidéos tout en gardant leur netteté"),
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
        "Show New File in Finder": ("Neue Datei im Finder zeigen", "Afficher le nouveau fichier dans le Finder"),
        "Show New Files in Finder": ("Neue Dateien im Finder zeigen", "Afficher les nouveaux fichiers dans le Finder"),
        "Show Original in Finder": ("Original im Finder zeigen", "Afficher l’original dans le Finder"),

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

        // New photo and PDF tools
        "Crop": ("Zuschneiden", "Recadrer"),
        "Remove Background": ("Hintergrund entfernen", "Supprimer l’arrière-plan"),
        "Watermark": ("Wasserzeichen", "Filigrane"),
        "Black & White": ("Schwarzweiss", "Noir et blanc"),
        "Make Icons": ("Symbole erstellen", "Créer des icônes"),
        "Contact Sheet": ("Kontaktbogen", "Planche contact"),
        "Find Duplicates": ("Duplikate suchen", "Chercher les doublons"),
        "Recognize Text": ("Text erkennen", "Reconnaître le texte"),
        "Make Searchable": ("Durchsuchbar machen", "Rendre consultable"),
        "Page Numbers": ("Seitenzahlen", "Numéros de page"),
        "Password": ("Passwort", "Mot de passe"),
        "Flatten": ("Reduzieren", "Aplatir"),
        "Photos": ("Fotos", "Photos"),
        "PDF": ("PDF", "PDF"),
        "Cut photos to a standard shape or trim away plain borders":
            ("Fotos auf ein Standardformat zuschneiden oder einfarbige Ränder abschneiden",
             "Recadrer des photos à un format standard ou supprimer les bords unis"),
        "Cut the subject out of a photo": ("Das Motiv aus einem Foto freistellen", "Détourer le sujet d’une photo"),
        "Stamp text or a logo on photos and PDFs":
            ("Text oder Logo auf Fotos und PDFs setzen", "Apposer un texte ou un logo sur des photos et des PDF"),
        "Turn photos and PDFs into black and white":
            ("Fotos und PDFs in Schwarzweiss umwandeln", "Convertir des photos et des PDF en noir et blanc"),
        "Make Mac and Windows icon files from a picture":
            ("Mac- und Windows-Symboldateien aus einem Bild erstellen",
             "Créer des fichiers d’icônes Mac et Windows à partir d’une image"),
        "Put many photos on one overview sheet":
            ("Viele Fotos auf einen Übersichtsbogen setzen", "Réunir de nombreuses photos sur une seule planche"),
        "Find photos that are the same or look alike":
            ("Fotos finden, die gleich sind oder sich ähneln", "Trouver les photos identiques ou similaires"),
        "Read the text in photos and scanned PDFs into a text file":
            ("Den Text in Fotos und gescannten PDFs in eine Textdatei einlesen",
             "Lire le texte des photos et des PDF numérisés dans un fichier texte"),
        "Add a hidden text layer to scanned PDFs so you can search and copy":
            ("Gescannten PDFs eine unsichtbare Textebene hinzufügen, damit man suchen und kopieren kann",
             "Ajouter une couche de texte invisible aux PDF numérisés pour pouvoir chercher et copier"),
        "Add page numbers to a PDF": ("Einem PDF Seitenzahlen hinzufügen", "Ajouter des numéros de page à un PDF"),
        "Protect a PDF with a password or remove its password":
            ("Ein PDF mit einem Passwort schützen oder sein Passwort entfernen",
             "Protéger un PDF par un mot de passe ou supprimer son mot de passe"),
        "Burn form fields and notes into the PDF so they can't be edited":
            ("Formularfelder und Notizen fest ins PDF einbetten, damit sie nicht mehr bearbeitet werden können",
             "Intégrer définitivement les champs de formulaire et les notes au PDF pour qu’ils ne soient plus modifiables"),
        "Add Watermark": ("Wasserzeichen hinzufügen", "Ajouter le filigrane"),
        "Create Sheet": ("Bogen erstellen", "Créer la planche"),
        "Add Numbers": ("Zahlen hinzufügen", "Ajouter les numéros"),
        "Protect": ("Schützen", "Protéger"),
        "Unlock": ("Entsperren", "Déverrouiller"),
        "Trim borders": ("Ränder abschneiden", "Supprimer les bords"),
        "Transparent": ("Transparent", "Transparent"),
        "White": ("Weiss", "Blanc"),
        "Text": ("Text", "Texte"),
        "Logo": ("Logo", "Logo"),
        "Bottom right": ("Unten rechts", "En bas à droite"),
        "Center": ("Mitte", "Centre"),
        "Diagonal": ("Diagonal", "En diagonale"),
        "Tiled": ("Gekachelt", "En mosaïque"),
        "Mac and Windows": ("Mac und Windows", "Mac et Windows"),
        "Mac (.icns)": ("Mac (.icns)", "Mac (.icns)"),
        "Windows (.ico)": ("Windows (.ico)", "Windows (.ico)"),
        "JPG": ("JPG", "JPG"),
        "Look alike": ("Ähnliche", "Similaires"),
        "Identical files": ("Identische Dateien", "Fichiers identiques"),
        "1 of 12": ("1 von 12", "1 sur 12"),
        "1 / 12": ("1 / 12", "1 / 12"),
        "Bottom center": ("Unten Mitte", "En bas au centre"),
        "Top right": ("Oben rechts", "En haut à droite"),
        "Add password": ("Passwort hinzufügen", "Ajouter un mot de passe"),
        "Remove password": ("Passwort entfernen", "Supprimer le mot de passe"),
        "Shape": ("Form", "Forme"),
        "Background": ("Hintergrund", "Arrière-plan"),
        "Mark": ("Zeichen", "Marque"),
        "Position": ("Position", "Position"),
        "Style": ("Stil", "Style"),
        "Mode": ("Modus", "Mode"),
        "Icon formats": ("Symbolformate", "Formats d’icônes"),
        "Opacity": ("Deckkraft", "Opacité"),
        "Crop to subject": ("Auf Motiv zuschneiden", "Recadrer sur le sujet"),
        "Watermark text": ("Wasserzeichentext", "Texte du filigrane"),
        "Choose Logo…": ("Logo wählen…", "Choisir un logo…"),
        "No logo chosen": ("Kein Logo gewählt", "Aucun logo choisi"),
        "File names": ("Dateinamen", "Noms de fichiers"),
        "Skip first page": ("Erste Seite auslassen", "Ignorer la première page"),
        "Move to Trash": ("In den Papierkorb legen", "Mettre à la corbeille"),
        "Cuts away plain borders of one colour around the picture.":
            ("Schneidet einfarbige Ränder rund um das Bild ab.", "Supprime les bords unis autour de l’image."),
        "Cuts from the centre. The shape follows the photo: wide photos stay wide, tall photos stay tall.":
            ("Schneidet von der Mitte aus. Die Form richtet sich nach dem Foto: Querformat bleibt Querformat, Hochformat bleibt Hochformat.",
             "Recadre depuis le centre. Le format suit la photo : les photos en paysage restent en paysage, celles en portrait restent en portrait."),
        "Saved as PNG with a transparent background.":
            ("Wird als PNG mit transparentem Hintergrund gesichert.", "Enregistré en PNG avec un arrière-plan transparent."),
        "Saved as JPG on a white background.":
            ("Wird als JPG auf weissem Hintergrund gesichert.", "Enregistré en JPG sur fond blanc."),
        "Size is the width of the mark compared to the photo or page. Photo info is kept.":
            ("Die Grösse ist die Breite des Zeichens im Verhältnis zum Foto oder zur Seite. Fotoinfos bleiben erhalten.",
             "La taille est la largeur de la marque par rapport à la photo ou à la page. Les infos de la photo sont conservées."),
        "Photos keep their format and photo info. PDFs are made grey, text and vectors stay sharp.":
            ("Fotos behalten Format und Fotoinfos. PDFs werden grau, Text und Vektoren bleiben scharf.",
             "Les photos gardent leur format et leurs infos. Les PDF passent en gris, le texte et les vecteurs restent nets."),
        "Pictures that aren't square get transparent edges. Use a square picture of at least 1024 px for the best result.":
            ("Nicht quadratische Bilder erhalten transparente Ränder. Für das beste Ergebnis ein quadratisches Bild mit mindestens 1024 px verwenden.",
             "Les images non carrées reçoivent des bords transparents. Pour un meilleur résultat, utilisez une image carrée d’au moins 1024 px."),
        "All photos go on one sheet in list order. Drag to reorder or use Sort.":
            ("Alle Fotos kommen in der Reihenfolge der Liste auf einen Bogen. Zum Umordnen ziehen oder «Sortieren» verwenden.",
             "Toutes les photos sont placées sur une planche, dans l’ordre de la liste. Glissez pour réordonner ou utilisez Trier."),
        "The best copy of each photo is kept. You can put the others back from the Trash.":
            ("Die beste Kopie jedes Fotos bleibt erhalten. Die anderen lassen sich aus dem Papierkorb zurücklegen.",
             "La meilleure copie de chaque photo est conservée. Vous pouvez remettre les autres depuis la corbeille."),
        "Finds the same photo even when it was resized, saved again or turned. Nothing is deleted until you confirm.":
            ("Findet dasselbe Foto auch, wenn es verkleinert, neu gesichert oder gedreht wurde. Es wird nichts gelöscht, bevor du bestätigst.",
             "Trouve la même photo même redimensionnée, réenregistrée ou pivotée. Rien n’est supprimé avant votre confirmation."),
        "Finds files with exactly the same content. Nothing is deleted until you confirm.":
            ("Findet Dateien mit genau demselben Inhalt. Es wird nichts gelöscht, bevor du bestätigst.",
             "Trouve les fichiers au contenu strictement identique. Rien n’est supprimé avant votre confirmation."),
        "Reads German, English and French. Saves a .txt file next to each photo or PDF. PDF pages that already have text are copied as they are.":
            ("Liest Deutsch, Englisch und Französisch. Sichert eine .txt-Datei neben jedem Foto oder PDF. PDF-Seiten, die bereits Text haben, werden unverändert übernommen.",
             "Lit l’allemand, l’anglais et le français. Enregistre un fichier .txt à côté de chaque photo ou PDF. Les pages PDF qui contiennent déjà du texte sont copiées telles quelles."),
        "Adds an invisible text layer to scanned pages so you can search and copy. The pages look the same. Pages that already have text stay unchanged.":
            ("Fügt gescannten Seiten eine unsichtbare Textebene hinzu, damit man suchen und kopieren kann. Die Seiten sehen gleich aus. Seiten, die bereits Text haben, bleiben unverändert.",
             "Ajoute une couche de texte invisible aux pages numérisées pour pouvoir chercher et copier. Les pages gardent le même aspect. Les pages qui contiennent déjà du texte restent inchangées."),
        "Links and form fields in the PDF are not kept. Text and images stay sharp.":
            ("Links und Formularfelder im PDF bleiben nicht erhalten. Text und Bilder bleiben scharf.",
             "Les liens et les champs de formulaire du PDF ne sont pas conservés. Le texte et les images restent nets."),
        "The PDF is saved as a new file that needs the password to open. Don't forget it: it can't be recovered.":
            ("Das PDF wird als neue Datei gesichert, die zum Öffnen das Passwort braucht. Nicht vergessen: Es lässt sich nicht wiederherstellen.",
             "Le PDF est enregistré dans un nouveau fichier qui demande le mot de passe pour s’ouvrir. Ne l’oubliez pas : il est impossible à récupérer."),
        "Enter the current password. The PDF is saved as a new file without a password.":
            ("Das aktuelle Passwort eingeben. Das PDF wird als neue Datei ohne Passwort gesichert.",
             "Saisissez le mot de passe actuel. Le PDF est enregistré dans un nouveau fichier sans mot de passe."),
        "Form fields, notes and stamps become part of the page, so they can no longer be edited. PDFs without any are skipped.":
            ("Formularfelder, Notizen und Stempel werden Teil der Seite und lassen sich nicht mehr bearbeiten. PDFs ohne solche werden übersprungen.",
             "Les champs de formulaire, les notes et les tampons font partie de la page et ne sont plus modifiables. Les PDF qui n’en contiennent pas sont ignorés."),

        // New tools: status, summaries and errors
        "%d icons": ("%d Symbole", "%d icônes"),
        "%d words": ("%d Wörter", "%d mots"),
        "%d pages recognised": ("%d Seiten erkannt", "%d pages reconnues"),
        "Created “%@”, %@": ("«%@» erstellt, %@", "« %@ » créé, %@"),
        "Checking…": ("Wird geprüft…", "Vérification…"),
        "Same as “%@”": ("Gleich wie «%@»", "Identique à « %@ »"),
        "Looks like “%@”": ("Sieht aus wie «%@»", "Ressemble à « %@ »"),
        "Kept": ("Behalten", "Conservé"),
        "Unique": ("Einzigartig", "Unique"),
        "No duplicates found": ("Keine Duplikate gefunden", "Aucun doublon trouvé"),
        "%d duplicates found": ("%d Duplikate gefunden", "%d doublons trouvés"),
        "1 duplicate found": ("1 Duplikat gefunden", "1 doublon trouvé"),
        "Moved 1 file to the Trash": ("1 Datei in den Papierkorb gelegt", "1 fichier mis à la corbeille"),
        "Moved %d files to the Trash": ("%d Dateien in den Papierkorb gelegt", "%d fichiers mis à la corbeille"),
        "Text recognition failed": ("Texterkennung fehlgeschlagen", "Échec de la reconnaissance du texte"),
        "No text found": ("Kein Text gefunden", "Aucun texte trouvé"),
        "Already searchable": ("Bereits durchsuchbar", "Déjà consultable"),
        "No subject found": ("Kein Motiv gefunden", "Aucun sujet trouvé"),
        "Already this shape": ("Bereits in dieser Form", "Déjà à ce format"),
        "No borders to trim": ("Keine Ränder zum Abschneiden", "Aucun bord à supprimer"),
        "Cropping failed": ("Zuschneiden fehlgeschlagen", "Échec du recadrage"),
        "%d of %d": ("%d von %d", "%1$d sur %2$d"),
        "Enter a text or choose a logo first": ("Zuerst einen Text eingeben oder ein Logo wählen", "Saisissez d’abord un texte ou choisissez un logo"),
        "Enter a password first": ("Zuerst ein Passwort eingeben", "Saisissez d’abord un mot de passe"),
        "Already password protected": ("Bereits passwortgeschützt", "Déjà protégé par un mot de passe"),
        "Has no password": ("Hat kein Passwort", "N’a pas de mot de passe"),
        "Wrong password": ("Falsches Passwort", "Mot de passe incorrect"),
        "Nothing to flatten": ("Nichts zu reduzieren", "Rien à aplatir"),
        "no background": ("ohne Hintergrund", "sans arrière-plan"),
        "black & white": ("schwarzweiss", "noir et blanc"),
        "searchable": ("durchsuchbar", "consultable"),
        "numbered": ("nummeriert", "numéroté"),
        "watermarked": ("mit Wasserzeichen", "avec filigrane"),
        "protected": ("geschützt", "protégé"),
        "unlocked": ("entsperrt", "déverrouillé"),
        "flattened": ("reduziert", "aplati"),

        // Merge of the language switch with presets and the new tools
        "Stopped. The remaining files were not read.": ("Gestoppt. Die übrigen Dateien wurden nicht gelesen.", "Arrêté. Les fichiers restants n’ont pas été lus."),
        "A preset runs several steps one after another on every file. This one starts with “%@” and its current settings.":
            ("Eine Voreinstellung führt mehrere Schritte nacheinander mit jeder Datei aus. Diese beginnt mit «%@» und den aktuellen Einstellungen.",
             "Un préréglage applique plusieurs étapes l’une après l’autre à chaque fichier. Celui-ci commence par « %@ » avec ses réglages actuels."),
        "Add as step to “%@”": ("Als Schritt zu «%@» hinzufügen", "Ajouter comme étape à « %@ »"),
        "Delete “%@”": ("«%@» löschen", "Supprimer « %@ »"),
        "PDF %d": ("PDF %d", "PDF %d"),
        "1 image in “%@”": ("1 Bild in «%@»", "1 image dans « %@ »"),
        "%d images in “%@”": ("%d Bilder in «%@»", "%d images dans « %@ »"),
        "%d columns": ("%d Spalten", "%d colonnes"),
        "Move 1 duplicate to the Trash?": ("1 Duplikat in den Papierkorb legen?", "Placer 1 doublon dans la corbeille ?"),
        "Move %d duplicates to the Trash?": ("%d Duplikate in den Papierkorb legen?", "Placer %d doublons dans la corbeille ?"),
        "Move Duplicates to Trash": ("Duplikate in den Papierkorb legen", "Placer les doublons dans la corbeille"),
        "Start at %d": ("Beginnen bei %d", "Commencer à %d"),

        // Favorites
        "Favorites": ("Favoriten", "Favoris"),
        "Add to Favorites": ("Zu Favoriten hinzufügen", "Ajouter aux favoris"),
        "Remove from Favorites": ("Aus Favoriten entfernen", "Retirer des favoris"),

        // Presets and quick actions
        "Presets": ("Voreinstellungen", "Préréglages"),
        "Preset · ": ("Voreinstellung · ", "Préréglage · "),
        "1 step": ("1 Schritt", "1 étape"),
        "%d steps": ("%d Schritte", "%d étapes"),
        "Save as Preset": ("Als Voreinstellung sichern", "Enregistrer comme préréglage"),
        "Save as Preset…": ("Als Voreinstellung sichern…", "Enregistrer comme préréglage…"),
        "Save this tool and its settings as a preset": ("Dieses Werkzeug samt Einstellungen als Voreinstellung sichern", "Enregistrer cet outil et ses réglages comme préréglage"),
        "Save as": ("Sichern als", "Enregistrer comme"),
        "New preset": ("Neue Voreinstellung", "Nouveau préréglage"),
        "Preset name": ("Name der Voreinstellung", "Nom du préréglage"),
        "Steps, in this order": ("Schritte in dieser Reihenfolge", "Étapes, dans cet ordre"),
        "Add Step": ("Schritt hinzufügen", "Ajouter une étape"),
        "Delete Step": ("Schritt löschen", "Supprimer l’étape"),
        "Delete this step": ("Diesen Schritt löschen", "Supprimer cette étape"),
        "No Steps": ("Keine Schritte", "Aucune étape"),
        "Add a step to get started.": ("Füge einen Schritt hinzu, um zu beginnen.", "Ajoutez une étape pour commencer."),
        "Delete Preset…": ("Voreinstellung löschen…", "Supprimer le préréglage…"),
        "Delete this preset?": ("Diese Voreinstellung löschen?", "Supprimer ce préréglage ?"),
        "The preset is removed. Your files are not touched.": ("Die Voreinstellung wird entfernt. Deine Dateien bleiben unberührt.", "Le préréglage est supprimé. Vos fichiers ne sont pas modifiés."),
        "Edit Preset…": ("Voreinstellung bearbeiten…", "Modifier le préréglage…"),
        "Edit…": ("Bearbeiten…", "Modifier…"),
        "Duplicate": ("Duplizieren", "Dupliquer"),
        "Delete…": ("Löschen…", "Supprimer…"),
        "copy": ("Kopie", "copie"),
        "Run Preset": ("Voreinstellung ausführen", "Exécuter le préréglage"),
        "Run Preset Again": ("Voreinstellung nochmals ausführen", "Exécuter à nouveau le préréglage"),
        "Step %d of %d: %@": ("Schritt %d von %d: %@", "Étape %1$d sur %2$d : %3$@"),
        "Nothing to do for this file": ("Für diese Datei gibt es nichts zu tun", "Rien à faire pour ce fichier"),
        "Not a per-file tool": ("Kein Werkzeug für einzelne Dateien", "Pas un outil par fichier"),
        "Web Upload": ("Web-Upload", "Envoi sur le web"),
        "For Email": ("Für E-Mail", "Pour l’e-mail"),
        "Share Safely": ("Sicher teilen", "Partage sécurisé"),
        "Searchable Scan": ("Durchsuchbarer Scan", "Scan consultable"),
        "%@, quality %d %%": ("%@, Qualität %d %%", "%1$@, qualité %2$d %%"),
        "Level: %@": ("Stufe: %@", "Niveau : %@"),
        "Smaller than %@ MB": ("Kleiner als %@ MB", "Moins de %@ Mo"),
        "Longest side %d px": ("Längste Seite %d px", "Côté le plus long %d px"),
        "Width %d px": ("Breite %d px", "Largeur %d px"),
        "Height %d px": ("Höhe %d px", "Hauteur %d px"),
        "%d %% of the size": ("%d %% der Grösse", "%d %% de la taille"),
        "180°": ("180°", "180°"),
        "crop to subject": ("auf Motiv zuschneiden", "recadrer sur le sujet"),
        "Photos and PDFs": ("Fotos und PDFs", "Photos et PDF"),
        "Add a text layer to scans": ("Textebene zu Scans hinzufügen", "Ajouter une couche de texte aux scans"),
        "Burn in form fields and notes": ("Formularfelder und Notizen einbrennen", "Intégrer les champs de formulaire et les notes"),
        "Word layout": ("Word-Layout", "Mise en page Word"),
        "Save the text as .txt": ("Text als .txt sichern", "Enregistrer le texte en .txt"),

        // Video, stitch, scans, redact, tables, smart rename, watch folders
        "Stitch Images": ("Bilder zusammenfügen", "Assembler des images"),
        "Clean Up Scans": ("Scans aufbereiten", "Nettoyer les scans"),
        "Redact": ("Schwärzen", "Caviarder"),
        "Extract Tables": ("Tabellen extrahieren", "Extraire les tableaux"),
        "Video to GIF": ("Video in GIF", "Vidéo en GIF"),
        "Put photos together into one long or wide image":
            ("Fotos zu einem langen oder breiten Bild zusammenfügen", "Assembler des photos en une seule image longue ou large"),
        "Straighten and brighten photos of documents":
            ("Fotos von Dokumenten geraderichten und aufhellen", "Redresser et éclaircir des photos de documents"),
        "Black out names, numbers and other text for good":
            ("Namen, Nummern und anderen Text endgültig schwärzen", "Caviarder définitivement des noms, des numéros et d’autres textes"),
        "Save the tables in PDFs and photos as CSV files":
            ("Tabellen aus PDFs und Fotos als CSV-Dateien sichern", "Enregistrer les tableaux des PDF et des photos en fichiers CSV"),
        "Make an animated GIF from a video": ("Aus einem Video ein animiertes GIF machen", "Créer un GIF animé à partir d’une vidéo"),
        "Stitch": ("Zusammenfügen", "Assembler"),
        "Clean Up": ("Aufbereiten", "Nettoyer"),
        "Make GIF": ("GIF erstellen", "Créer le GIF"),
        "Colour": ("Farbe", "Couleur"),
        "Greyscale": ("Graustufen", "Niveaux de gris"),
        "Searchable PDF": ("Durchsuchbares PDF", "PDF consultable"),
        "Top to bottom": ("Von oben nach unten", "De haut en bas"),
        "Side by side": ("Nebeneinander", "Côte à côte"),
        "Semicolon": ("Strichpunkt", "Point-virgule"),
        "Comma": ("Komma", "Virgule"),
        "From content": ("Aus dem Inhalt", "D’après le contenu"),
        "clean": ("bereinigt", "nettoyé"),
        "redacted": ("geschwärzt", "caviardé"),
        "No matches found": ("Keine Treffer gefunden", "Aucune correspondance trouvée"),
        "Document": ("Dokument", "Document"),
        "Choose at least 2 photos": ("Mindestens 2 Fotos wählen", "Choisissez au moins 2 photos"),
        "No tables found": ("Keine Tabellen gefunden", "Aucun tableau trouvé"),
        "Page %d, table %d": ("Seite %d, Tabelle %d", "Page %1$d, tableau %2$d"),
        "Table %d": ("Tabelle %d", "Tableau %d"),
        "Table recognition failed": ("Tabellenerkennung fehlgeschlagen", "Échec de la reconnaissance des tableaux"),
        "Compressing video (%d of %d)": ("Video wird komprimiert (%d von %d)", "Compression de la vidéo (%1$d sur %2$d)"),
        "Could not compress this video": ("Dieses Video konnte nicht komprimiert werden", "Impossible de compresser cette vidéo"),
        "Could not create the GIF": ("Das GIF konnte nicht erstellt werden", "Impossible de créer le GIF"),
        "No video track": ("Keine Videospur", "Aucune piste vidéo"),
        "Add Folder…": ("Ordner hinzufügen…", "Ajouter un dossier…"),
        "Add a folder and choose a preset to run on every new file.":
            ("Ordner hinzufügen und eine Voreinstellung wählen, die auf jede neue Datei angewendet wird.",
             "Ajoutez un dossier et choisissez un préréglage à appliquer à chaque nouveau fichier."),
        "Choose a folder to watch": ("Ordner zum Überwachen wählen", "Choisir un dossier à surveiller"),
        "Error: %@": ("Fehler: %@", "Erreur : %@"),
        "Folder not found": ("Ordner nicht gefunden", "Dossier introuvable"),
        "No Watched Folders": ("Keine überwachten Ordner", "Aucun dossier surveillé"),
        "Preset": ("Voreinstellung", "Préréglage"),
        "Preset was deleted": ("Voreinstellung wurde gelöscht", "Le préréglage a été supprimé"),
        "Processed": ("Verarbeitet", "Traités"),
        "Stop Watching": ("Nicht mehr überwachen", "Arrêter la surveillance"),
        "Stop watching this folder": ("Diesen Ordner nicht mehr überwachen", "Arrêter de surveiller ce dossier"),
        "Watch": ("Überwachen", "Surveiller"),
        "Watch Folders": ("Ordner überwachen", "Surveiller des dossiers"),
        "Watch Folders…": ("Ordner überwachen…", "Surveiller des dossiers…"),
        "Works while File Tools is open. Results go into a “Processed” folder inside the watched folder. Files already in the folder are left alone.":
            ("Funktioniert, solange File Tools geöffnet ist. Die Ergebnisse landen im Ordner «Verarbeitet» im überwachten Ordner. Dateien, die schon im Ordner liegen, bleiben unberührt.",
             "Fonctionne tant que File Tools est ouvert. Les résultats vont dans un dossier « Traités » à l’intérieur du dossier surveillé. Les fichiers déjà présents dans le dossier ne sont pas touchés."),
        "%@ saved (−%d %%)": ("%@ gespart (−%d %%)", "%1$@ économisés (−%2$d %%)"),
        "%d done": ("%d fertig", "%d terminés"),
        "%d skipped": ("%d übersprungen", "%d ignorés"),
        "%d failed": ("%d fehlgeschlagen", "%d en échec"),
        "1 name suggested. Check it, then click Rename.":
            ("1 Name vorgeschlagen. Prüfen, dann auf «Umbenennen» klicken.", "1 nom suggéré. Vérifiez-le, puis cliquez sur « Renommer »."),
        "%d names suggested. Check them, then click Rename.":
            ("%d Namen vorgeschlagen. Prüfen, dann auf «Umbenennen» klicken.", "%d noms suggérés. Vérifiez-les, puis cliquez sur « Renommer »."),
        "Created “%@”: %d × %d px, %@": ("«%@» erstellt: %d × %d px, %@", "« %1$@ » créé : %2$d × %3$d px, %4$@"),
        "Reading…": ("Wird gelesen…", "Lecture…"),
        "Suggested": ("Vorgeschlagen", "Suggéré"),
        "Stitched": ("Zusammengefügt", "Assemblé"),
        "1 word": ("1 Wort", "1 mot"),
        "Email addresses": ("E-Mail-Adressen", "Adresses e-mail"),
        "IBANs": ("IBANs", "IBAN"),
        "Phone numbers": ("Telefonnummern", "Numéros de téléphone"),
        "Nothing to black out yet": ("Noch nichts zum Schwärzen", "Rien à caviarder pour l’instant"),
        "%d frames": ("%d Bilder", "%d images"),
        "1 match": ("1 Treffer", "1 correspondance"),
        "%d matches": ("%d Treffer", "%d correspondances"),
        "on 1 page": ("auf 1 Seite", "sur 1 page"),
        "on %d pages": ("auf %d Seiten", "sur %d pages"),
        "1 table": ("1 Tabelle", "1 tableau"),
        "%d tables": ("%d Tabellen", "%d tableaux"),
        "Frame %d of %d…": ("Bild %d von %d…", "Image %d sur %d…"),
        "No page edges found, colours cleaned up":
            ("Keine Seitenränder gefunden, Farben bereinigt", "Bords de page introuvables, couleurs nettoyées"),
        "Drop videos here": ("Videos hierher ziehen", "Déposez des vidéos ici"),
        "Drop photos, PDFs, videos or folders here":
            ("Fotos, PDFs, Videos oder Ordner hierher ziehen", "Déposez des photos, des PDF, des vidéos ou des dossiers ici"),
        "Colours": ("Farben", "Couleurs"),
        "Direction": ("Richtung", "Direction"),
        "Names": ("Namen", "Noms"),
        "Separator": ("Trennzeichen", "Séparateur"),
        "Frame rate": ("Bildrate", "Fréquence d’images"),
        "Words to black out": ("Zu schwärzende Wörter", "Mots à caviarder"),
        "Gap %d px": ("Abstand %d px", "Écart %d px"),
        "Suggest Names (%d)": ("Namen vorschlagen (%d)", "Proposer des noms (%d)"),
        "Quick Look": ("Übersicht", "Coup d’œil"),
        "Quick Look Result": ("Ergebnis in der Übersicht zeigen", "Afficher le résultat en coup d’œil"),
        "Show Result in Finder": ("Ergebnis im Finder zeigen", "Afficher le résultat dans le Finder"),
        "Preview the new files (⌘Y)": ("Neue Dateien ansehen (⌘Y)", "Prévisualiser les nouveaux fichiers (⌘Y)"),
        "Drag the result to another app or folder":
            ("Das Ergebnis in ein anderes Programm oder einen Ordner ziehen", "Faites glisser le résultat vers une autre app ou un dossier"),
        "Names or words, separated by commas": ("Namen oder Wörter, durch Kommas getrennt", "Noms ou mots, séparés par des virgules"),
        "Names like 261014-SwisscomInvoice.pdf, from each file's date and content. Click Suggest Names, check them, then Rename.":
            ("Namen wie 261014-SwisscomRechnung.pdf, aus Datum und Inhalt jeder Datei. Namen vorschlagen, prüfen, dann umbenennen.",
             "Noms comme 261014-FactureSwisscom.pdf, d’après la date et le contenu. Proposez des noms, vérifiez-les, puis renommez."),
        "Uses Apple Intelligence on this Mac.": ("Verwendet Apple Intelligence auf diesem Mac.", "Utilise Apple Intelligence sur ce Mac."),
        "Photos are put together in list order. Drag to reorder or use Sort. They are scaled to the same width (or height), never enlarged.":
            ("Fotos werden in der Reihenfolge der Liste zusammengefügt. Zum Ändern ziehen oder «Sortieren» verwenden. Sie werden auf gleiche Breite (oder Höhe) gebracht, nie vergrössert.",
             "Les photos sont assemblées dans l’ordre de la liste. Faites glisser pour réordonner ou utilisez Trier. Elles sont mises à la même largeur (ou hauteur), jamais agrandies."),
        "Finds the page in the photo, straightens it and makes the paper white. If no page edges are found, only the colours are cleaned up.":
            ("Findet die Seite im Foto, richtet sie gerade und macht das Papier weiss. Werden keine Seitenränder gefunden, werden nur die Farben bereinigt.",
             "Repère la page dans la photo, la redresse et blanchit le papier. Si les bords de la page sont introuvables, seules les couleurs sont nettoyées."),
        "Matching text is covered and removed for good. Pages with matches become images with a hidden text layer.":
            ("Passender Text wird abgedeckt und endgültig entfernt. Seiten mit Treffern werden zu Bildern mit versteckter Textebene.",
             "Le texte correspondant est recouvert et supprimé définitivement. Les pages concernées deviennent des images avec une couche de texte cachée."),
        "Each table becomes a CSV file that opens in Excel. For PDFs, only the selected pages are searched (all if none selected).":
            ("Jede Tabelle wird zu einer CSV-Datei, die sich in Excel öffnen lässt. Bei PDFs werden nur die ausgewählten Seiten durchsucht (alle, wenn keine ausgewählt).",
             "Chaque tableau devient un fichier CSV qui s’ouvre dans Excel. Pour les PDF, seules les pages choisies sont analysées (toutes si aucune n’est choisie)."),
        "Only the first 60 seconds are used. The GIF loops forever and is never wider than the video.":
            ("Es werden nur die ersten 60 Sekunden verwendet. Das GIF läuft endlos und ist nie breiter als das Video.",
             "Seules les 60 premières secondes sont utilisées. Le GIF tourne en boucle et n’est jamais plus large que la vidéo."),
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
