import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Lo que cambia entre Mac e iPhone, en un solo lugar. El resto del código usa estos nombres y no
// importa AppKit ni UIKit directamente.

// MARK: - Imágenes

#if os(macOS)
typealias PlatformImage = NSImage

extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#else
typealias PlatformImage = UIImage

extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}

extension UIImage {
    /// Como `NSImage(contentsOf:)`, para leer imágenes de la caché.
    convenience init?(contentsOf url: URL) {
        self.init(contentsOfFile: url.path)
    }
}
#endif

// MARK: - Portapapeles

enum Clipboard {
    /// El texto del portapapeles, si hay.
    @MainActor static var string: String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }

    @MainActor static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Archivos

enum PlatformFiles {
    /// Borra un archivo de datos: en Mac va a la Papelera (se puede recuperar); en iPhone no hay papelera.
    static func discard(_ url: URL) throws {
        #if os(macOS)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        try FileManager.default.removeItem(at: url)
        #endif
    }

    #if os(macOS)
    /// Abre una carpeta en Finder o, si es un archivo, lo muestra seleccionado.
    @MainActor static func reveal(_ url: URL, selecting: Bool = false) {
        if selecting {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
}

// MARK: - Colores del sistema

extension Color {
    /// Fondo de la ventana.
    static var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// Fondo de tarjetas y paneles.
    static var controlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// Fondo de un campo de texto.
    static var textBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    /// Fondo detrás de una página (vista previa de impresión).
    static var underPageBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

// MARK: - Estilos que solo existen en Mac

extension View {
    /// Botón con aspecto de enlace en Mac; sin borde en iPhone.
    func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }

    /// Opciones como botones de radio en Mac; menú en iPhone.
    func radioGroupPickerStyle() -> some View {
        #if os(macOS)
        pickerStyle(.radioGroup)
        #else
        pickerStyle(.inline)
        #endif
    }

    /// La tecla ⌫ en Mac (en iPhone se borra con gestos o menús).
    func onDeleteKey(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onDeleteCommand(perform: action)
        #else
        self
        #endif
    }

    /// Subtítulo bajo el título de la ventana en Mac.
    func windowSubtitle(_ text: String) -> some View {
        #if os(macOS)
        navigationSubtitle(text)
        #else
        self
        #endif
    }
}
