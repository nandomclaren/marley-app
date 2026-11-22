import SwiftUI
import UIKit

extension View {
    /// Em sheets: com alterações não salvas, o gesto de fechar não fecha e chama `onAttempt` (para pedir confirmação).
    func confirmDismiss(when dirty: Bool, onAttempt: @escaping () -> Void) -> some View {
        self
            .interactiveDismissDisabled(dirty) // garantia: mesmo sem o aviso abaixo, nada se perde
            .background(DismissAttemptHandler(onAttempt: onAttempt).frame(width: 0, height: 0))
    }
}

/// Fica de delegate da apresentação da sheet só para saber quando o usuário tentou fechar; repassa todo o resto
/// ao delegate original do SwiftUI, que continua cuidando do estado da sheet.
private struct DismissAttemptHandler: UIViewControllerRepresentable {
    let onAttempt: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(onAttempt: onAttempt) }
    func updateUIViewController(_ vc: Controller, context: Context) { vc.onAttempt = onAttempt }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void
        private weak var original: UIAdaptivePresentationControllerDelegate?
        init(onAttempt: @escaping () -> Void) { self.onAttempt = onAttempt; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            var top: UIViewController = self
            while let p = top.parent { top = p }
            guard let pc = top.presentationController, pc.delegate !== self else { return }
            original = pc.delegate
            pc.delegate = self
        }

        func presentationControllerDidAttemptToDismiss(_ pc: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(pc)
            onAttempt()
        }
        func presentationControllerShouldDismiss(_ pc: UIPresentationController) -> Bool {
            original?.presentationControllerShouldDismiss?(pc) ?? true
        }
        func presentationControllerWillDismiss(_ pc: UIPresentationController) { original?.presentationControllerWillDismiss?(pc) }
        func presentationControllerDidDismiss(_ pc: UIPresentationController) { original?.presentationControllerDidDismiss?(pc) }
    }
}
