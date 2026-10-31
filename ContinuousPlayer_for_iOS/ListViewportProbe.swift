import SwiftUI
import UIKit

/// Query the List's current native cells at input time. Cached SwiftUI row
/// frames can remain at old positions after cell reuse or a page transition.
@MainActor final class ListViewport {
    weak var anchor: UIView?
    func pageSize() -> Int? {
        func collection(in view: UIView) -> UIScrollView? {
            if let collection = view as? UICollectionView { return collection }
            if let table = view as? UITableView { return table }
            for child in view.subviews { if let found = collection(in: child) { return found } }
            return nil
        }
        var parent = anchor?.superview
        while let view = parent {
            if let list = collection(in: view), let anchor {
                let frames = (list as? UICollectionView)?.visibleCells.map(\.frame)
                    ?? (list as? UITableView)?.visibleCells.map(\.frame) ?? []
                let visible = list.bounds.intersection(anchor.convert(anchor.bounds, to: list))
                if !frames.isEmpty && visible.height > 0 {
                    return FileListInput.pageSize(frames: frames, viewport: visible)
                }
            }
            parent = view.superview
        }
        return nil
    }
}
struct ListViewportProbe: UIViewRepresentable {
    let viewport: ListViewport
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.isUserInteractionEnabled = false
        viewport.anchor = view
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { viewport.anchor = view }
}
