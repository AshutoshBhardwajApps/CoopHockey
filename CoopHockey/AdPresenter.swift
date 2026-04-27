import SwiftUI

// Stable UIViewController anchor for presenting interstitial ads from SwiftUI
struct AdPresenter: UIViewControllerRepresentable {
    static weak var holder: UIViewController?

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        Self.holder = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        Self.holder = uiViewController
    }
}
