import SwiftUI
import MirissaCore

// MARK: - Sayı girişi ayrıştırma

public enum NumberInput {
    /// "5.000,50" / "5000,50" / "5000.50" / "5000" -> 5000.5
    public static func parse(_ raw: String) -> Double? {
        var t = raw.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "TL", with: "")
            .replacingOccurrences(of: "₺", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard !t.isEmpty else { return nil }
        let hasDot = t.contains("."), hasComma = t.contains(",")
        if hasDot && hasComma {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if hasComma {
            t = t.replacingOccurrences(of: ",", with: ".")
        } else if hasDot {
            // Tek nokta: son parça 3 haneliyse binlik ayracı sayılır (5.000)
            let parts = t.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 1, parts.dropFirst().allSatisfy({ $0.count == 3 }) {
                t = parts.joined()
            }
        }
        return Double(t)
    }

    public static func kurus(_ raw: String) -> Kurus? {
        parse(raw).map { Money.fromTL($0) }
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
        .onAppear { if text.isEmpty { text = NumberInput.display(value) } }
        .onChange(of: text) { _, new in value = NumberInput.kurus(new) ?? 0 }
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
        .onAppear { if text.isEmpty, let v = value { text = NumberInput.display(v) } }
        .onChange(of: text) { _, new in
            value = new.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (NumberInput.kurus(new) ?? 0)
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
        .onAppear { if text.isEmpty { text = NumberInput.display(value) } }
        .onChange(of: text) { _, new in value = NumberInput.parse(new) ?? 0 }
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
        .onAppear { if text.isEmpty, let v = value { text = NumberInput.display(v) } }
        .onChange(of: text) { _, new in
            value = new.trimmingCharacters(in: .whitespaces).isEmpty ? nil : NumberInput.parse(new)
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
        .onAppear { if text.isEmpty { text = NumberInput.display(value) } }
        .onChange(of: text) { _, new in value = NumberInput.parse(new) ?? 0 }
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
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
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
                .font(.system(size: 28, weight: .light))
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
            .foregroundStyle(.white)
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
