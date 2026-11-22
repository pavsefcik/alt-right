import AppKit

@MainActor
enum BookmarkOpener {
    /// Returns whether something was actually opened. A missing path shows its
    /// recovery alert and reports `false`, so the caller does not count it as
    /// a use for ranking.
    @discardableResult
    static func open(
        _ bookmark: Bookmark,
        onEdit: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) -> Bool {
        open(
            path: bookmark.path,
            title: bookmark.title,
            onEdit: onEdit,
            onRemove: onRemove
        )
    }

    @discardableResult
    static func open(
        path: String,
        title: String? = nil,
        onEdit: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) -> Bool {
        if let url = URL(string: path),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            return true
        }

        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: path,
            isDirectory: &isDirectory
        )

        guard exists else {
            showMissing(path: path, title: title, onEdit: onEdit, onRemove: onRemove)
            return false
        }

        if isDirectory.boolValue {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        return true
    }

    private static func showMissing(
        path: String,
        title: String?,
        onEdit: (() -> Void)?,
        onRemove: (() -> Void)?
    ) {
        AppActivation.activate()

        let alert = NSAlert()
        alert.messageText = L("Path Not Found")
        alert.informativeText = String(
            format: L("“%@” doesn’t exist."),
            title ?? path
        )
        alert.alertStyle = .warning

        if onEdit != nil {
            alert.addButton(withTitle: L("Edit Bookmark"))
        }
        if onRemove != nil {
            alert.addButton(withTitle: L("Remove Bookmark"))
        }
        alert.addButton(withTitle: L("Cancel"))

        let response = alert.runModal()
        if onEdit != nil, response == .alertFirstButtonReturn {
            onEdit?()
            return
        }
        if onRemove != nil {
            let removeResponse: NSApplication.ModalResponse = onEdit != nil
                ? .alertSecondButtonReturn
                : .alertFirstButtonReturn
            if response == removeResponse {
                onRemove?()
            }
        }
    }
}
