import Foundation
import Observation
import PinaxCore

@MainActor @Observable
final class AppSettings {
    static let cleanKey = "pinax.cleanSettings"
    static let langKey = "pinax.language"

    let home = FileManager.default.homeDirectoryForCurrentUser
    let applicationRoots: [URL]

    var clean: CleanSettings {
        didSet {
            if let data = try? JSONEncoder().encode(clean) { UserDefaults.standard.set(data, forKey: Self.cleanKey) }
        }
    }

    var langPref: LangPref {
        didSet {
            Loc.lang = langPref.resolved
            UserDefaults.standard.set(langPref.rawValue, forKey: Self.langKey)
        }
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        applicationRoots = [URL(fileURLWithPath: "/Applications"),
                            home.appendingPathComponent("Applications", isDirectory: true)]
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: Self.cleanKey),
           let decoded = try? JSONDecoder().decode(CleanSettings.self, from: data) {
            clean = decoded
        } else {
            clean = .defaults(home: home)
        }
        let pref = LangPref(rawValue: ud.integer(forKey: Self.langKey)) ?? .system
        langPref = pref
        Loc.lang = pref.resolved
    }

    func makeScanContext() -> ScanContext {
        ScanContext(home: home, applicationRoots: applicationRoots, now: Date(),
                    lastUsed: SpotlightLastUsedProvider(),
                    installedApps: FileSystemInstalledApps(roots: applicationRoots),
                    settings: clean)
    }
}
