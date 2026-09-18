import SwiftUI
import UserNotifications
import MirissaCore

/// Telefonun bildirim merkezine hatırlatmaları kurar.
/// Uygulamanın kurduğu bildirimlerin hepsi "mirissa-" ile başlar; her seferinde yenilenir.
@MainActor
enum BildirimPlanlayici {
    static let onEk = "mirissa-"

    static func izinIste() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func planla(_ liste: [PlanliHatirlatma]) async {
        let merkez = UNUserNotificationCenter.current()
        await temizle()
        for h in liste {
            let icerik = UNMutableNotificationContent()
            icerik.title = h.baslik
            icerik.body = h.metin
            icerik.sound = .default
            var c = DateComponents()
            c.year = Dates.year(of: Dates.month(of: h.gun))
            c.month = Dates.monthNumber(of: Dates.month(of: h.gun))
            c.day = Dates.day(of: h.gun)
            c.hour = 10
            let tetik = UNCalendarNotificationTrigger(dateMatching: c, repeats: false)
            try? await merkez.add(UNNotificationRequest(identifier: onEk + h.id, content: icerik, trigger: tetik))
        }
    }

    static func temizle() async {
        let merkez = UNUserNotificationCenter.current()
        let bekleyen = await merkez.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(onEk) }
        merkez.removePendingNotificationRequests(withIdentifiers: bekleyen)
    }

    /// Ayar açıksa güncel listeyle yeniden kurar
    static func yenile(_ store: AppStore) {
        guard store.state.settings.ek.hatirlatmalarAcik == true else { return }
        let liste = store.engine.hatirlatmalar()
        Task { await planla(liste) }
    }
}

/// Ayarlar → Hatırlatmalar
struct HatirlatmaAyari: View {
    @Environment(AppStore.self) private var store
    @State private var mesaj: String?

    var body: some View {
        Section {
            Toggle("Hatırlatmalar", isOn: Binding(
                get: { store.state.settings.ek.hatirlatmalarAcik == true },
                set: { ac in
                    if ac {
                        Task {
                            if await BildirimPlanlayici.izinIste() {
                                store.ekAyarla { $0.hatirlatmalarAcik = true }
                                BildirimPlanlayici.yenile(store)
                                mesaj = "\(store.engine.hatirlatmalar().count) hatırlatma kuruldu."
                            } else {
                                mesaj = "Bildirim izni verilmedi. iPhone Ayarlar → Mirissa Finans → Bildirimler'den açabilirsin."
                            }
                        }
                    } else {
                        store.ekAyarla { $0.hatirlatmalarAcik = false }
                        Task { await BildirimPlanlayici.temizle() }
                        mesaj = nil
                    }
                }))
            if let mesaj { Text(mesaj).font(.footnote).foregroundStyle(Palette.accent) }
        } header: {
            Text("Hatırlatmalar")
        } footer: {
            Text("Her ayın 2'sinde satış girişi, 24'ünde KDV, pazarları yedek, taksit ve borç vadeleri, sipariş zamanı, "
                 + "geçici vergi ve üç ayda bir maliyet kontrolü için sabah 10'da bildirim gelir.")
        }
    }
}
