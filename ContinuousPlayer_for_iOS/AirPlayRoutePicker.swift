#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftUI
import AVKit

struct AirPlayRoutePicker: UIViewRepresentable {
    var prioritizesVideoDevices: Bool
    var onPresentationChange: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var onPresentationChange: (Bool) -> Void

        init(onPresentationChange: @escaping (Bool) -> Void) {
            self.onPresentationChange = onPresentationChange
        }

        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            onPresentationChange(true)
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            onPresentationChange(false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPresentationChange: onPresentationChange) }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.delegate = context.coordinator
        view.tintColor = .white
        view.activeTintColor = .cyan
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        context.coordinator.onPresentationChange = onPresentationChange
        view.prioritizesVideoDevices = prioritizesVideoDevices
        view.isUserInteractionEnabled = isEnabled
        view.alpha = isEnabled ? 1 : 0.3
    }

    static func dismantleUIView(_ view: AVRoutePickerView, coordinator: Coordinator) {
        view.delegate = nil
    }
}
#endif
