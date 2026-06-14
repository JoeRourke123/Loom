import Foundation

extension Notification.Name {
    static let loomProjectFolderChanged = Notification.Name("LoomProjectFolderChanged")
}

final class ProjectFolderPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .main

    init(folderURL: URL) {
        self.presentedItemURL = folderURL
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() {
        NotificationCenter.default.post(
            name: .loomProjectFolderChanged,
            object: nil,
            userInfo: ["folderURL": presentedItemURL as Any]
        )
    }
}
