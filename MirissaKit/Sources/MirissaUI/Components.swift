import SwiftUI
import MirissaCore

// MARK: - Sayı girişi ayrıştırma

public enum NumberInput {
    /// Miktar ve yüzde: "0,125" / "0.125" / "2,5" / "2.5" -> ondalık. Tek nokta her zaman
    /// ondalıktır (0.125 kg, 125 kg okunmasın). Birden çok nokta binlik ayracıdır (1.234.567).
    public static func parse(_ raw: String) -> Double? { ayristir(raw, para: false) }

    /// Para: "5.000,50" / "5000,50" / "5000.50" / "5.000" -> 5000.5 / 5000.
    /// Tek nokta ve arkasında 3 hane varsa binlik ayracıdır ("0." ile başlıyorsa değil).
    static func ayristir(_ raw: String, para: Bool) -> Double? {
        var t = raw.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "TL", with: "")
            .replacingOccurrences(of: "₺", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard !t.isEmpty else { return nil }
        let hasDot = t.contains("."), hasComma = t.contains(",")
        if hasDot && hasComma {
            // Sonda gelen ayraç ondalıktır: "1.234,56" (Türkçe) ya da yapıştırılan "1,234.56"
            if let v = t.lastIndex(of: ","), let n = t.lastIndex(of: "."), n > v {
                t = t.replacingOccurrences(of: ",", with: "")
            } else {
                t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
        } else if hasComma {
            t = t.replacingOccurrences(of: ",", with: ".")
        } else if hasDot {
            let parts = t.split(separator: ".", omittingEmptySubsequences: false)
            let rakamlar = t.hasPrefix("-") ? String(t.dropFirst()) : t
            let sifirla = rakamlar.hasPrefix("0.")
            // Birden çok nokta: binlik ayracı (1.234.567). Tek nokta: parada 3 haneli grup binliktir
            // (5.000 TL); miktar ve yüzdede ondalıktır. "0." ile başlayan hiçbir zaman binlik değildir.
            if !sifirla, parts.count > 1, parts.dropFirst().allSatisfy({ $0.count == 3 }),
               parts.count > 2 || para {
                t = parts.joined()
            }
        }
        return Double(t)
    }

    /// Alan başka bir kayıt için yeniden kullanıldığında ekrandaki metni tazeler.
    /// Kullanıcının yazdığı metin bağlı değerle aynı sayıya işaret ediyorsa
    /// dokunulmaz — böylece "5," gibi yarım yazımlar bozulmaz.
    /// Farklıysa yeni değerin metni döner; değer sıfırsa alan boşalır.
    public static func senkron(metin: String, deger: Double) -> String? {
        if (parse(metin) ?? 0) == deger { return nil }
        return deger == 0 ? "" : display(deger)
    }

    public static func senkron(metin: String, kurus deger: Kurus) -> String? {
        if (Self.kurus(metin) ?? 0) == deger { return nil }
        return deger == 0 ? "" : display(deger)
    }

    /// Boş bırakılabilen alanlar için: nil ise alan boşalır.
    public static func senkron(metin: String, opsiyonel deger: Double?) -> String? {
        let simdiki = metin.trimmingCharacters(in: .whitespaces).isEmpty ? nil : parse(metin)
        if simdiki == deger { return nil }
        return deger.map { display($0) } ?? ""
    }

    public static func senkron(metin: String, opsiyonelKurus deger: Kurus?) -> String? {
        let simdiki = metin.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Self.kurus(metin)
        if simdiki == deger { return nil }
        return deger.map { display($0) } ?? ""
    }

    public static func kurus(_ raw: String) -> Kurus? {
        ayristir(raw, para: true).map { Money.fromTL($0) }
    }

    public static func display(_ k: Kurus) -> String {
        k == 0 ? "" : Money.format(k, withSymbol: false)
    }

    public static func display(_ d: Double) -> String {
        if d == 0 { return "" }
        if d == d.rounded() { return String(Int(d)) }
        return String(format: "%g", d).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Alanlar

public struct MoneyField: View {
    var title: String
    var placeholder: String
    @Binding var value: Kurus
    @State private var text: String = ""

    public init(_ title: String, placeholder: String = "0", value: Binding<Kurus>) {
        self.title = title
        self.placeholder = placeholder
        self._value = value
    }

    public var body: some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Spacer(minLength: 12)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .numericKeyboard()
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: 160)
            Text("TL").foregroundStyle(Palette.inkFaint).font(.subheadline)
        }
        // Görünüm başka bir kayıt için yeniden kullanıldığında eski metin
        // ekranda kalmasın: bağlı değer değişince alan tazelenir.
        .onAppear { text = value == 0 ? "" : NumberInput.display(value) }
        .onChange(of: text) { _, new in value = NumberInput.kurus(new) ?? 0 }
        .onChange(of: value) { _, new in
            if let taze = NumberInput.senkron(metin: text, kurus: new) { text = taze }
        }
    }
}

/// Boş bırakılabilen tutar alanı — "elle gir, yoksa otomatik hesapla" için
public struct OptionalMoneyField: View {
    var title: String
    var autoValue: Kurus
    @Binding var value: Kurus?
    @State private var text: String = ""

    public init(_ title: String, autoValue: Kurus, value: Binding<Kurus?>) {
        self.title = title
        self.autoValue = autoValue
        self._value = value
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Palette.ink)
                Text(value == nil ? "Otomatik: \(autoValue.tl)" : "Elle girildi")
                    .font(.caption)
                    .foregroundStyle(value == nil ? Palette.inkFaint : Palette.accent)
            }
            Spacer(minLength: 12)
            TextField(NumberInput.display(autoValue), text: $text)
                .multilineTextAlignment(.trailing)
                .numericKeyboard()
                .frame(maxWidth: 130)
            Text("TL").foregroundStyle(Palette.inkFaint).font(.subheadline)
        }
        .onAppear { text = value.map { NumberInput.display($0) } ?? "" }
        .onChange(of: text) { _, new in
            value = new.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (NumberInput.kurus(new) ?? 0)
        }
        .onChange(of: value) { _, new in
            if let taze = NumberInput.senkron(metin: text, opsiyonelKurus: new) { text = taze }
        }
    }
}

public struct QtyField: View {
    var title: String
    var suffix: String?
    @Binding var value: Double
    @State private var text: String = ""

    public init(_ title: String, suffix: String? = nil, value: Binding<Double>) {
        self.title = title
        self.suffix = suffix
        self._value = value
    }

    public var body: some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Spacer(minLength: 12)
            TextField("0", text: $text)
                .multilineTextAlignment(.trailing)
                .numericKeyboard()
                .frame(maxWidth: 120)
            if let suffix { Text(suffix).foregroundStyle(Palette.inkFaint).font(.subheadline) }
        }
        .onAppear { text = value == 0 ? "" : NumberInput.display(value) }
        .onChange(of: text) { _, new in value = NumberInput.parse(new) ?? 0 }
        .onChange(of: value) { _, new in
            if let taze = NumberInput.senkron(metin: text, deger: new) { text = taze }
        }
    }
}

public struct OptionalQtyField: View {
    var title: String
    var suffix: String?
    @Binding var value: Double?
    @State private var text: String = ""

    public init(_ title: String, suffix: String? = nil, value: Binding<Double?>) {
        self.title = title
        self.suffix = suffix
        self._value = value
    }

    public var body: some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Spacer(minLength: 12)
            TextField("—", text: $text)
                .multilineTextAlignment(.trailing)
                .numericKeyboard()
                .frame(maxWidth: 120)
            if let suffix { Text(suffix).foregroundStyle(Palette.inkFaint).font(.subheadline) }
        }
        .onAppear { text = value.map { NumberInput.display($0) } ?? "" }
        .onChange(of: text) { _, new in
            value = new.trimmingCharacters(in: .whitespaces).isEmpty ? nil : NumberInput.parse(new)
        }
        .onChange(of: value) { _, new in
            if let taze = NumberInput.senkron(metin: text, opsiyonel: new) { text = taze }
        }
    }
}

public struct PercentField: View {
    var title: String
    @Binding var value: Double
    @State private var text: String = ""

    public init(_ title: String, value: Binding<Double>) {
        self.title = title
        self._value = value
    }

    public var body: some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Spacer(minLength: 12)
            TextField("0", text: $text)
                .multilineTextAlignment(.trailing)
                .numericKeyboard()
                .frame(maxWidth: 90)
            Text("%").foregroundStyle(Palette.inkFaint).font(.subheadline)
        }
        .onAppear { text = value == 0 ? "" : NumberInput.display(value) }
        .onChange(of: text) { _, new in value = NumberInput.parse(new) ?? 0 }
        .onChange(of: value) { _, new in
            if let taze = NumberInput.senkron(metin: text, deger: new) { text = taze }
        }
    }
}

// MARK: - Gösterim parçaları

public struct SectionTitle: View {
    var text: String
    var action: (() -> Void)?
    var actionLabel: String?

    public init(_ text: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.trUpper)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.inkFaint)
            Spacer()
            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 4)
    }
}

public struct BigStat: View {
    var title: String
    var value: String
    var tone: Color
    var caption: String?

    public init(title: String, value: String, tone: Color = Palette.ink, caption: String? = nil) {
        self.title = title
        self.value = value
        self.tone = tone
        self.caption = caption
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.trUpper)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
            }
        }
    }
}

public struct LabeledRow: View {
    var label: String
    var value: String
    var tone: Color
    var badge: String?
    var strong: Bool

    public init(_ label: String, _ value: String, tone: Color = Palette.ink, badge: String? = nil, strong: Bool = false) {
        self.label = label
        self.value = value
        self.tone = tone
        self.badge = badge
        self.strong = strong
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(strong ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(strong ? Palette.ink : Palette.inkSoft)
            if let badge { Pill(badge) }
            Spacer(minLength: 8)
            Text(value)
                .font(strong ? .headline : .subheadline.weight(.medium))
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

public struct Pill: View {
    var text: String
    var tone: Color
    var background: Color

    public init(_ text: String, tone: Color = Palette.inkFaint, background: Color = Palette.inset) {
        self.text = text
        self.tone = tone
        self.background = background
    }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
    }
}

public struct EmptyHint: View {
    var icon: String
    var title: String
    var message: String

    public init(icon: String = "tray", title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle.weight(.light))
                .foregroundStyle(Palette.inkFaint)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

public struct BigButton: View {
    var title: String
    var icon: String?
    var tone: Color
    var action: () -> Void

    public init(_ title: String, icon: String? = nil, tone: Color = Palette.accent, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(tone)
            .foregroundStyle(Palette.onFilled)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Açılır detay bloğu — ekranı doldurmadan derinlik verir
public struct Disclosure<Header: View, Content: View>: View {
    @State private var open: Bool
    var header: Header
    var content: Content

    public init(open: Bool = false, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self._open = State(initialValue: open)
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { open.toggle() }
            } label: {
                HStack {
                    header
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 10) { content }
                    .padding(.top, 12)
            }
        }
    }
}
