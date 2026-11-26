import Cocoa

func installFilePanelsHooks() {
    FilePanelsHooks.install(FilePanelsHooks(showSavedPathSuccess: { path in
        appDelegate?.showSavedPathSuccess(path)
    }))
}
