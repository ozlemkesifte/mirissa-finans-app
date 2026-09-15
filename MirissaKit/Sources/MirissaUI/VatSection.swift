import SwiftUI
import MirissaCore

/// Satış, gider ve alım formlarında ortak KDV bölümü.
/// KDV takibi kapalıysa hiç görünmez.
struct VatSection: View {
    @Environment(AppStore.self) private var store

    @Binding var rate: VatRate
    @Binding var included: Bool
    /// Girilen tutar — net/KDV önizlemesi için
    var amount: Kurus
    var label: String
    /// Kendi bölümünü açsın mı; false ise sadece satırları verir
    var asSection: Bool

    init(rate: Binding<VatRate>, included: Binding<Bool>, amount: Kurus,
         label: String = "Tutar", asSection: Bool = true) {
        self._rate = rate
        self._included = included
        self.amount = amount
        self.label = label
        self.asSection = asSection
    }

    private var split: VatSplit { Vat.split(amount, rate: rate, included: included) }

    var body: some View {
        if store.state.settings.vatEnabled {
            if asSection { bolum } else { satirlar }
        }
    }

    @ViewBuilder
    private var satirlar: some View {
        Picker("KDV oranı", selection: $rate) {
            ForEach(VatRate.allCases) { r in Text(r.displayName).tag(r) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if rate != .yok {
            Toggle("\(label) KDV dahil", isOn: $included)
            LabeledRow("KDV hariç", split.net.tl, tone: Palette.ink, strong: true)
            LabeledRow("KDV", split.vat.tl, tone: Palette.inkSoft)
        }
    }

    private var bolum: some View {
        Group {
            Section {
                Picker("KDV oranı", selection: $rate) {
                    ForEach(VatRate.allCases) { r in Text(r.displayName).tag(r) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if rate != .yok {
                    Toggle("\(label) KDV dahil", isOn: $included)
                    LabeledRow("KDV hariç", split.net.tl, tone: Palette.ink, strong: true)
                    LabeledRow("KDV", split.vat.tl, tone: Palette.inkSoft)
                }
            } header: {
                Text("KDV")
            } footer: {
                Text(rate == .yok
                     ? "Bu kayıtta KDV yok."
                     : "Kâr hesabı KDV hariç tutar üzerinden yapılır. KDV ayrıca takip edilir.")
            }
        }
    }
}
