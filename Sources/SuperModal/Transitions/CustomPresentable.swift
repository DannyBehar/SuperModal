import UIKit

protocol CustomPresentable: UIViewController {
    var transitionManager: UIViewControllerTransitioningDelegate? { get set }
    var dismissalHandlingScrollView: UIScrollView? { get }
    var presentationAlignment: ModalPresentationAlignment { get }
    var presentationTransformTargetView: UIView? { get }
    func updatePresentationLayout(animated: Bool)
}

extension CustomPresentable {
    var dismissalHandlingScrollView: UIScrollView? { nil }
    var presentationAlignment: ModalPresentationAlignment { .top }
    var presentationTransformTargetView: UIView? { nil }

    func updatePresentationLayout(animated: Bool = false) {
        presentationController?.containerView?.setNeedsLayout()
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: .allowUserInteraction, animations: {
                self.presentationController?.containerView?.layoutIfNeeded()
            }, completion: nil)
        } else {
            presentationController?.containerView?.layoutIfNeeded()
        }
    }
}
