import SwiftUI

public extension View {
    /// Fast fönsterstorlek för sheets på macOS; på iPhone/iPad fyller sheeten
    /// själv skärmen - ett `minWidth` större än skärmbredden gjorde att
    /// innehållet skars av i kanterna (rapporterat 2026-10-13).
    @ViewBuilder
    func sheetFrame(minWidth: CGFloat, idealWidth: CGFloat, minHeight: CGFloat, idealHeight: CGFloat, maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil) -> some View {
        #if os(macOS)
        self.frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth, minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight)
        #else
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

/// En enda delad `CIContext` - att skapa en ny per rendering (som
/// tjänsterna gjorde) är dyrt och läckte minne på iPhone vid många
/// renderingar i rad (t.ex. när ett reglage drogs).
enum SharedCIContext {
    static let shared = CIContext()
}
