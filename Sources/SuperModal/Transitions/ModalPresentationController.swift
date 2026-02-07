import UIKit

public enum ModalPresentationAlignment {
    case top
    case center
    case bottom
}

class ModalPresentationController: UIPresentationController {

    lazy var fadeView: UIView = .make(backgroundColor: UIColor.black.withAlphaComponent(0.3), alpha: 0.0)
    private let verticalPadding: CGFloat = 8.0
    private let modalTransitionDuration: TimeInterval = 0.5
    private let presentingTransform: CGAffineTransform = {
        var transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        transform = transform.translatedBy(x: 0.0, y: -8.0)
        return transform
    }()
    private var didTransformPresentingView = false
    private weak var transformedPresentingView: UIView?
    private var keyboardHeight: CGFloat = 0.0
    private var keyboardAnimator: UIViewPropertyAnimator?
    private var basePresentedFrame: CGRect = .zero
    private var lockedHeightWhileKeyboardVisible: CGFloat?

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }
        containerView.insertSubview(fadeView, at: 0)
        fadeView.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        fadeView.addGestureRecognizer(tapGesture)
        startObservingKeyboardNotifications()

        fadeView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fadeView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            fadeView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            fadeView.topAnchor.constraint(equalTo: containerView.topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        let shouldTransformPresentingModal = shouldTransformPresentingView()
        let animator = UIViewPropertyAnimator(duration: modalTransitionDuration, dampingRatio: 1.0) {
            self.fadeView.alpha = 1.0
            if shouldTransformPresentingModal {
                self.applyTransformToPresentingView()
                self.didTransformPresentingView = true
            }
        }
        animator.startAnimation()
    }

    @objc private func handleBackgroundTap() {
        presentedViewController.dismiss(animated: true)
    }

    override func dismissalTransitionWillBegin() {
        if presentedViewController.transitionCoordinator?.isInteractive == true {
            return
        }

        let animator = UIViewPropertyAnimator(duration: modalTransitionDuration, dampingRatio: 1.0) {
            self.fadeView.alpha = 0.0
            if self.didTransformPresentingView {
                self.resetTransformOnPresentingView()
                self.didTransformPresentingView = false
            }
        }
        animator.startAnimation()
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)
        if completed {
            if didTransformPresentingView {
                // UIKit may reset the presenting view's transform at the end of the transition.
                applyTransformToPresentingView()
            }
        } else if !completed, didTransformPresentingView {
            resetTransformOnPresentingView()
            didTransformPresentingView = false
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        if completed {
            resetTransformOnPresentingView()
            didTransformPresentingView = false
            stopObservingKeyboardNotifications()
            keyboardAnimator?.stopAnimation(true)
            keyboardAnimator = nil
            keyboardHeight = 0.0
            basePresentedFrame = .zero
            lockedHeightWhileKeyboardVisible = nil
        }
    }

    override func containerViewWillLayoutSubviews() {
        guard let presentedView else { return }
        presentedView.transform = .identity
        presentedView.frame = frameOfPresentedViewInContainerView
        basePresentedFrame = presentedView.frame
        applyKeyboardLift(in: containerView)
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView, let presentedView = presentedView else { return .zero }

        let inset: CGFloat = 16
        let safeAreaFrame = containerView.bounds.inset(by: containerView.safeAreaInsets)

        let availableWidth = safeAreaFrame.width - 2 * inset
        let maxRegularWidth: CGFloat = 550.0
        let targetWidth: CGFloat
        if presentedViewController.traitCollection.horizontalSizeClass == .regular {
            targetWidth = min(availableWidth, maxRegularWidth)
        } else {
            targetWidth = availableWidth
        }
        let fittingSize = CGSize(
            width: targetWidth,
            height: UIView.layoutFittingCompressedSize.height
        )

        // Ensure the hosted SwiftUI view has the same width it will be rendered at
        // before asking Auto Layout for the compressed fitting height.
        if presentedView.bounds.width != targetWidth {
            presentedView.bounds.size.width = targetWidth
        }
        let targetHeight = presentedView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .defaultLow
        ).height
        let resolvedHeight = lockedHeightWhileKeyboardVisible ?? targetHeight

        var frame = safeAreaFrame
        frame.origin.x = safeAreaFrame.minX + (safeAreaFrame.width - targetWidth) / 2.0
        frame.size.width = targetWidth
        frame.size.height = resolvedHeight

        let alignment = (presentedViewController as? CustomPresentable)?.presentationAlignment ?? .top
        switch alignment {
        case .top:
            frame.origin.y = safeAreaFrame.minY + verticalPadding
        case .center:
            frame.origin.y = safeAreaFrame.minY + (safeAreaFrame.height - resolvedHeight) / 2.0
        case .bottom:
            frame.origin.y = safeAreaFrame.maxY - resolvedHeight - verticalPadding
        }

        return frame
    }

    private func shouldTransformPresentingView() -> Bool {
        guard let presentingModal = presentingViewController as? CustomPresentable,
              let presentedModal = presentedViewController as? CustomPresentable else {
            return false
        }

        return presentingModal.presentationAlignment == presentedModal.presentationAlignment
    }

    private func applyTransformToPresentingView() {
        if let presentingModal = presentingViewController as? CustomPresentable,
           let targetView = presentingModal.presentationTransformTargetView ?? presentingViewController.presentationController?.presentedView {
            targetView.transform = presentingTransform
            transformedPresentingView = targetView
        } else if let presentingPresentedView = presentingViewController.presentationController?.presentedView {
            presentingPresentedView.transform = presentingTransform
            transformedPresentingView = presentingPresentedView
        } else {
            presentingViewController.view.transform = presentingTransform
            transformedPresentingView = presentingViewController.view
        }
    }

    private func resetTransformOnPresentingView() {
        transformedPresentingView?.transform = .identity
        transformedPresentingView = nil
    }

    func updatePresentingViewTransform(for progress: CGFloat) {
        guard didTransformPresentingView else { return }
        let clamped = min(max(progress, 0.0), 1.0)
        let from = presentingTransform
        let to = CGAffineTransform.identity

        let interpolated = CGAffineTransform(
            a: from.a + (to.a - from.a) * clamped,
            b: from.b + (to.b - from.b) * clamped,
            c: from.c + (to.c - from.c) * clamped,
            d: from.d + (to.d - from.d) * clamped,
            tx: from.tx + (to.tx - from.tx) * clamped,
            ty: from.ty + (to.ty - from.ty) * clamped
        )

        transformedPresentingView?.transform = interpolated
    }

    func setPresentingViewTransform(_ transform: CGAffineTransform) {
        guard didTransformPresentingView else { return }
        transformedPresentingView?.transform = transform
    }

    private func startObservingKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardNotification(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func stopObservingKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func handleKeyboardNotification(_ notification: Notification) {
        guard let containerView = containerView,
              let userInfo = notification.userInfo else {
            return
        }

        let previousKeyboardHeight = keyboardHeight
        if let endFrameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let endFrameInContainer = containerView.convert(endFrameValue.cgRectValue, from: nil)
            keyboardHeight = max(0.0, containerView.bounds.maxY - endFrameInContainer.minY)
        } else if notification.name == UIResponder.keyboardWillHideNotification {
            keyboardHeight = 0.0
        }

        if previousKeyboardHeight == 0.0, keyboardHeight > 0.0 {
            lockedHeightWhileKeyboardVisible = basePresentedFrame.height > 0.0 ? basePresentedFrame.height : presentedView?.bounds.height
            containerView.setNeedsLayout()
            containerView.layoutIfNeeded()
        }

        keyboardAnimator?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(duration: modalTransitionDuration, dampingRatio: 1.0) {
            self.applyKeyboardLift(in: containerView)
        }
        animator.addCompletion { [weak self] _ in
            guard let self else { return }
            self.keyboardAnimator = nil
            if self.keyboardHeight == 0.0 {
                self.lockedHeightWhileKeyboardVisible = nil
                containerView.setNeedsLayout()
                containerView.layoutIfNeeded()
            }
        }
        keyboardAnimator = animator
        animator.startAnimation()
    }

    private func applyKeyboardLift(in containerView: UIView?) {
        guard let containerView, let presentedView else { return }
        let safeAreaFrame = containerView.bounds.inset(by: containerView.safeAreaInsets)
        let keyboardGap = keyboardHeight > 0.0 ? verticalPadding : 0.0
        let allowedBottom = safeAreaFrame.maxY - keyboardHeight - keyboardGap

        let desiredLift = max(0.0, basePresentedFrame.maxY - allowedBottom)
        let minY = safeAreaFrame.minY + verticalPadding
        let maxLift = max(0.0, basePresentedFrame.minY - minY)
        let lift = min(desiredLift, maxLift)

        presentedView.transform = CGAffineTransform(translationX: 0.0, y: -lift)
    }
}
