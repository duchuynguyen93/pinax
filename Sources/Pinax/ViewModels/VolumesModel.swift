import AppKit
import Observation

struct Volume: Identifiable, Hashable {
    let url: URL
    let name: String
    let isRoot: Bool
    let canEject: Bool
    var id: URL { url }
}

/// Các volume đang mount (mục Locations), cập nhật theo mount / unmount.
@MainActor @Observable
final class VolumesModel {
    private(set) var volumes: [Volume] = []
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private let toast: ToastModel

    init(toast: ToastModel) {
        self.toast = toast
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
                                      .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let isRoot = v?.volumeIsRootFileSystem ?? (url.path == "/")
            return Volume(url: url, name: v?.volumeLocalizedName ?? url.lastPathComponent, isRoot: isRoot,
                          canEject: !isRoot && ((v?.volumeIsEjectable ?? false) || (v?.volumeIsRemovable ?? false)))
        }
    }

    func eject(_ volume: Volume) {
        guard volume.canEject else { return }
        let url = volume.url
        Task {
            let error = await Task.detached { () -> Error? in
                do { try NSWorkspace.shared.unmountAndEjectDevice(at: url); return nil } catch { return error }
            }.value
            if let error {
                toast.show(L("Couldn't eject “\(volume.name)”: \(error.localizedDescription)",
                             "Không đẩy được “\(volume.name)”: \(error.localizedDescription)"))
            }
            refresh()
        }
    }
}
