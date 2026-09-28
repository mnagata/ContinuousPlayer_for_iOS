#if targetEnvironment(macCatalyst)
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import OSLog

/// Keep the native panel's lifetime separate from SwiftUI's player presentation.
/// Deliver the selection only after dismissal, when a player or alert can be shown.
struct CatalystDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let folder: Bool
    let directory: URL?
    let completion: (Result<URL, Error>) -> Void

    final class Controller: UIViewController, UIDocumentPickerDelegate {
        var requested = false
        var folder = false
        var directory: URL?
        var completion: ((Result<URL, Error>) -> Void)?
        private var picker: UIDocumentPickerViewController?
        private var finishing = false
        private let logger = Logger(subsystem: "jp.nagu.ContinuousPlayer-for-iOS", category: "FileSelection")

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfReady()
        }

        func presentIfReady() {
            guard requested, picker == nil, viewIfLoaded?.window != nil else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: folder ? [.folder] : [.data], asCopy: false)
            picker.allowsMultipleSelection = false
            picker.directoryURL = directory
            picker.delegate = self
            self.picker = picker
            logger.notice("Presenting native picker")
            present(picker, animated: true)
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            logger.notice("Native picker selected \(urls.count) items")
            finish(urls.first.map { .success($0) } ?? .failure(CocoaError(.userCancelled)))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            logger.notice("Native picker cancelled")
            finish(.failure(CocoaError(.userCancelled)))
        }

        private func finish(_ result: Result<URL, Error>) {
            guard !finishing, let picker else { return }
            finishing = true
            let deliver = { [weak self] in
                guard let self else { return }
                self.requested = false
                self.picker = nil
                self.finishing = false
                self.logger.notice("Delivering native picker result")
                self.completion?(result)
            }
            if picker.presentingViewController == nil {
                deliver()
            } else if picker.isBeingDismissed, let transition = picker.transitionCoordinator {
                transition.animate(alongsideTransition: nil) { _ in deliver() }
            } else {
                picker.dismiss(animated: true, completion: deliver)
            }
        }
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.requested = isPresented
        controller.folder = folder
        controller.directory = directory
        controller.completion = { result in
            isPresented = false
            completion(result)
        }
        controller.presentIfReady()
    }
}
#endif
