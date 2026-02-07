import UIKit

class ModalTransitionAnimator: NSObject {

    private let presenting: Bool

    init(presenting: Bool) {
        self.presenting = presenting
        super.init()
    }
}

extension ModalTransitionAnimator: UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.5 }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if presenting {
            animatePresentation(using: transitionContext)
        } else {
            animateDismissal(using: transitionContext)
        }
    }

    @MainActor
    private func animatePresentation(using transitionContext: UIViewControllerContextTransitioning) {
        let presentedViewController = transitionContext.viewController(forKey: .to)!
        transitionContext.containerView.addSubview(presentedViewController.view)

        // Force an initial layout pass before computing final frame so SwiftUI content
        // that uses flexible sizing (e.g. maxWidth: .infinity) is measured up front.
        transitionContext.containerView.setNeedsLayout()
        transitionContext.containerView.layoutIfNeeded()
        presentedViewController.view.setNeedsLayout()
        presentedViewController.view.layoutIfNeeded()

        let presentedFrame = transitionContext.finalFrame(for: presentedViewController)
        let dismissedFrame = CGRect(x: presentedFrame.minX, y: transitionContext.containerView.bounds.height, width: presentedFrame.width, height: presentedFrame.height)

        presentedViewController.view.frame = dismissedFrame

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), dampingRatio: 1.0) {
            presentedViewController.view.frame = presentedFrame
        }

        animator.addCompletion { _ in
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }

        animator.startAnimation()
    }

    @MainActor private func animateDismissal(using transitionContext: UIViewControllerContextTransitioning) {
        let presentedViewController = transitionContext.viewController(forKey: .from)!
        let presentedFrame = transitionContext.finalFrame(for: presentedViewController)
        let dismissedFrame = CGRect(x: presentedFrame.minX, y: transitionContext.containerView.bounds.height, width: presentedFrame.width, height: presentedFrame.height)

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), dampingRatio: 1.0) {
            presentedViewController.view.frame = dismissedFrame
        }

        animator.addCompletion { _ in
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }

        animator.startAnimation()
    }
}
