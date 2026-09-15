import SwiftUI
import MirissaCore

/// Veri bütünlüğü uyarısı. Yalnızca gerçekten bozuk bir durum varsa görünür.
/// Amaç: yanlış ama düzgün görünen bir rakamı sessizce göstermemek.
struct ButunlukKarti: View {
    @Environment(AppStore.self) private var store
    @State private var acik = false

    private var sorunlar: [IntegrityIssue] { Integrity.check(store.state) }
    private var bozuk: [IntegrityIssue] { sorunlar.filter { $0.severity == .bozuk } }

    var body: some View {
        if !bozuk.isEmpty {
            Card(background: Palette.zararYumusak) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.zarar)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bu rakamlara güvenme")
                                .font(.headline)
                                .foregroundStyle(Palette.zarar)
                            Text("\(bozuk.count) kayıtta tutarsızlık var")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    if acik {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(bozuk.prefix(8)) { s in
                                Text("• \(s.area): \(s.message)")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if bozuk.count > 8 {
                                Text("… ve \(bozuk.count - 8) kayıt daha")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                    }
                    Button(acik ? "Gizle" : "Neler bozuk?") {
                        withAnimation { acik.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.zarar)
                }
            }
        }
    }
}

/// Ayarlardaki tam liste — şüpheli kayıtlar da görünür.
struct ButunlukBolumu: View {
    @Environment(AppStore.self) private var store

    private var sorunlar: [IntegrityIssue] { Integrity.check(store.state) }

    var body: some View {
        Section {
            if sorunlar.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.kar)
                    Text("Veriler tutarlı").foregroundStyle(Palette.ink)
                }
            } else {
                ForEach(sorunlar) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: s.severity == .bozuk
                              ? "exclamationmark.triangle.fill" : "questionmark.circle")
                            .foregroundStyle(s.severity == .bozuk ? Palette.zarar : Palette.uyari)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.message)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(s.area)
                                .font(.caption)
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
            }
        } header: {
            Text("Veri kontrolü")
        } footer: {
            Text("Bir kayıt imkânsız bir duruma işaret ediyorsa burada görünür. "
                 + "Bozuk kayıt varsa ana sayfada da uyarı çıkar; rakamlar düzeltilene kadar "
                 + "güvenilmez sayılmalıdır.")
        }
    }
}
