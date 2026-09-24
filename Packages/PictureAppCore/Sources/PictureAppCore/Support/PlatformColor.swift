import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
#else
import UIKit
public typealias PlatformColor = UIColor
#endif

public extension Color {
    /// Konverterar en SwiftUI-`Color` till `CGColor` via plattformens
    /// färgtyp, som en direkt `.cgColor` på `Color` inte finns på båda
    /// plattformarna.
    var resolvedCGColor: CGColor {
        PlatformColor(self).cgColor
    }
}
