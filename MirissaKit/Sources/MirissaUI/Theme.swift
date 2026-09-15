import SwiftUI
import MirissaCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Açık/koyu moda uyum sağlayan renk üretici.
/// Uygulama beyaz ağırlıklı tasarlandı; koyu modda da ferah kalması için
/// her renk ayrı ayrı tanımlandı.
func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
    #if os(iOS)
    return Color(UIColor { trait in
        let c = trait.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
    })
    #else
    // macOS'ta da dinamik: önizleme aracı koyu modu gerçekten çizebilsin
    return Color(NSColor(name: nil) { appearance in
        let koyu = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = koyu ? dark : light
        return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
    })
    #endif
}

public enum Palette {
    /// Sayfa zemini
    public static let bg = adaptive(light: (246, 246, 248), dark: (14, 14, 17))
    /// Kart zemini
    public static let card = adaptive(light: (255, 255, 255), dark: (28, 28, 32))
    /// Kart içi ikinci seviye zemin
    public static let inset = adaptive(light: (246, 247, 249), dark: (38, 38, 43))
    public static let separator = adaptive(light: (232, 232, 237), dark: (52, 52, 58))

    public static let ink = adaptive(light: (17, 17, 20), dark: (245, 245, 248))
    // Gri tonlar okunabilirlik eşiğini (4.5:1) her iki modda da geçecek
    // şekilde seçildi; aralarındaki ağırlık farkı korunuyor.
    public static let inkSoft = adaptive(light: (88, 88, 100), dark: (170, 170, 184))
    public static let inkFaint = adaptive(light: (112, 112, 126), dark: (142, 142, 156))

    public static let accent = adaptive(light: (13, 122, 101), dark: (46, 178, 148))
    public static let kar = adaptive(light: (13, 122, 101), dark: (46, 178, 148))
    public static let zarar = adaptive(light: (192, 57, 43), dark: (255, 105, 92))
    public static let uyari = adaptive(light: (191, 120, 0), dark: (240, 168, 48))
    public static let gider = adaptive(light: (74, 78, 105), dark: (160, 166, 200))

    /// Dolu butonların üzerindeki yazı. Koyu modda accent ve gider renkleri
    /// açıldığı için beyaz kontrastı düşüyordu; koyu bir ton kullanılıyor.
    public static let onFilled = adaptive(light: (255, 255, 255), dark: (10, 28, 24))

    public static let karYumusak = adaptive(light: (233, 246, 242), dark: (18, 52, 45))
    public static let zararYumusak = adaptive(light: (253, 236, 234), dark: (60, 24, 22))
    public static let uyariYumusak = adaptive(light: (253, 245, 230), dark: (56, 42, 14))
}

public extension String {
    /// Türkçe büyük harf: "gider" -> "GİDER" (varsayılan `uppercased()` "GIDER" üretir)
    var trUpper: String { uppercased(with: Locale(identifier: "tr_TR")) }
}

public enum Metrics {
    public static let cardRadius: CGFloat = 18
    public static let gap: CGFloat = 12
    public static let pad: CGFloat = 16
}

// MARK: - Kart

public struct Card<Content: View>: View {
    var padding: CGFloat
    var background: Color
    @ViewBuilder var content: Content

    public init(padding: CGFloat = Metrics.pad, background: Color = Palette.card, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.background = background
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

// MARK: - Platform farklarını kapatan küçük yardımcılar

public extension View {
    /// iOS'ta sayı klavyesi açar, diğer platformlarda bir şey yapmaz.
    @ViewBuilder func numericKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func largeTitleMode() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    func screenBackground() -> some View {
        self.background(Palette.bg.ignoresSafeArea())
    }
}

// MARK: - Sayı biçimleri

public extension Kurus {
    var tl: String { Money.format(self) }
    var tlCompact: String { Money.formatCompact(self) }
    var signedTL: String { self > 0 ? "+\(Money.format(self))" : Money.format(self) }
}
