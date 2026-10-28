import UIKit

public enum ModalPresentationAlignment {
    case top
    case center
    case bottom
}

/// The horizontal region used when a vertical crease divides the presentation.
public enum ModalPresentationSide: Sendable {
    /// Follows the view carrying the modal modifier as its layout changes.
    case automatic
    case left
    case right
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
    private var keyboardFrameInScreen: CGRect = .null
    private weak var keyboardScreen: UIScreen?
    private var keyboardAnimator: UIViewPropertyAnimator?
    private var basePresentedFrame: CGRect = .zero
    private var lockedHeightWhileKeyboardVisible: CGFloat?
    private var sourceAnchorX: CGFloat?
    private var sourceSide: ModalPresentationSide?
    private var lastAutomaticSourceFrame: CGRect?

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
        if !completed {
            sourceAnchorX = nil
            sourceSide = nil
            lastAutomaticSourceFrame = nil
        }
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
            keyboardFrameInScreen = .null
            keyboardScreen = nil
            basePresentedFrame = .zero
            lockedHeightWhileKeyboardVisible = nil
            sourceAnchorX = nil
            sourceSide = nil
            lastAutomaticSourceFrame = nil
        }
    }

    override func containerViewWillLayoutSubviews() {
        guard let presentedView else { return }
        presentedView.transform = .identity
        presentedView.frame = frameOfPresentedViewInContainerView
        basePresentedFrame = presentedView.frame
        applyKeyboardLift(in: containerView)
    }

    func invalidateContentSize() {
        // A changed row count must be measured again even while the keyboard is visible.
        lockedHeightWhileKeyboardVisible = nil
        containerView?.setNeedsLayout()
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView, let presentedView = presentedView else { return .zero }

        let inset: CGFloat = 16
        let alignment = (presentedViewController as? CustomPresentable)?.presentationAlignment ?? .top
        let safeAreaFrame = safeAreaFrame(in: containerView, for: alignment)

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
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardNotification(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    private func stopObservingKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    @objc private func handleKeyboardNotification(_ notification: Notification) {
        guard let containerView = containerView,
              let userInfo = notification.userInfo else {
            return
        }

        let previousKeyboardHeight = keyboardHeight
        if notification.name == UIResponder.keyboardWillHideNotification {
            keyboardHeight = 0.0
            keyboardFrameInScreen = .null
            keyboardScreen = nil
        } else if let endFrameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            keyboardFrameInScreen = endFrameValue.cgRectValue
            keyboardScreen = (notification.object as? UIScreen) ?? containerView.window?.screen
            let intersection = containerView.bounds.intersection(keyboardFrame(in: containerView))
            keyboardHeight = intersection.isNull || intersection.isEmpty ? 0.0 : intersection.height
        }

        if previousKeyboardHeight == 0.0, keyboardHeight > 0.0 {
            lockedHeightWhileKeyboardVisible = basePresentedFrame.height > 0.0 ? basePresentedFrame.height : presentedView?.bounds.height
        }

        keyboardAnimator?.stopAnimation(true)
        if notification.name == UIResponder.keyboardDidChangeFrameNotification {
            keyboardAnimator = nil
            if keyboardHeight == 0.0 {
                lockedHeightWhileKeyboardVisible = nil
            }
            // Reconcile the final keyboard frame after rotation has finished laying out.
            containerView.setNeedsLayout()
            containerView.layoutIfNeeded()
            return
        }
        let animator = UIViewPropertyAnimator(duration: modalTransitionDuration, dampingRatio: 1.0) {
            // Region selection also depends on the keyboard, so recompute the base frame.
            containerView.setNeedsLayout()
            containerView.layoutIfNeeded()
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

    private func keyboardFrame(in containerView: UIView) -> CGRect {
        guard !keyboardFrameInScreen.isNull,
              let screen = keyboardScreen ?? containerView.window?.screen,
              containerView.window?.screen === screen else { return .null }

        // Convert on every layout pass; the container may have moved since the notification.
        return containerView.convert(keyboardFrameInScreen, from: screen.coordinateSpace)
    }

    private func applyKeyboardLift(in containerView: UIView?) {
        guard let containerView, let presentedView else { return }
        let alignment = (presentedViewController as? CustomPresentable)?.presentationAlignment ?? .top
        let safeAreaFrame = safeAreaFrame(in: containerView, for: alignment)
        let keyboardIntersection = safeAreaFrame.intersection(keyboardFrame(in: containerView))
        let allowedBottom: CGFloat
        if keyboardIntersection.isNull || keyboardIntersection.isEmpty {
            allowedBottom = safeAreaFrame.maxY
        } else {
            // Only reserve space where the keyboard overlaps the selected region.
            allowedBottom = keyboardIntersection.minY - verticalPadding
        }

        let desiredLift = max(0.0, basePresentedFrame.maxY - allowedBottom)
        let minY = safeAreaFrame.minY + verticalPadding
        let maxLift = max(0.0, basePresentedFrame.minY - minY)
        let lift = min(desiredLift, maxLift)

        presentedView.transform = CGAffineTransform(translationX: 0.0, y: -lift)
    }

    // Keep the hardware query separate so layout can be exercised with synthetic regions.
    func divisionRegions(in containerView: UIView) -> [(frame: CGRect, isActive: Bool)] {
        if #available(iOS 27.1, *) {
            return containerView.reservedRegions(kind: .division).map { ($0.frame, $0.isActive) }
        }
        return []
    }

    private func systemSafeAreaFrame(in containerView: UIView) -> CGRect {
        guard let window = containerView.window else {
            return containerView.bounds.inset(by: containerView.safeAreaInsets)
        }

        // The presentation container's insets can change as the modal moves. Use
        // the window's current safe area to avoid that feedback without caching it.
        let windowSafeArea = window.bounds.inset(by: window.safeAreaInsets)
        return containerView.bounds.intersection(containerView.convert(windowSafeArea, from: window))
    }

    private func safeAreaFrame(
        in containerView: UIView,
        for alignment: ModalPresentationAlignment
    ) -> CGRect {
        let safeAreaFrame = systemSafeAreaFrame(in: containerView)
        captureSourceAnchor(in: containerView)

        if #available(iOS 27.1, *) {
            let divisions = divisionRegions(in: containerView)
                .filter(\.isActive)
                .map(\.frame)
            let availableFrames = divisions
                .reduce([safeAreaFrame]) { frames, region in
                    frames.flatMap { availableFrames(in: $0, avoiding: region) }
                }

            guard !availableFrames.isEmpty else { return safeAreaFrame }

            let preferredFrame = preferredFrame(
                from: sourceFrames(from: availableFrames, avoiding: divisions, in: containerView),
                alignment: alignment,
                fallback: safeAreaFrame
            )

            let keyboardFrame = keyboardFrame(in: containerView)
            let keyboardIntersection = preferredFrame.intersection(keyboardFrame)
            guard !keyboardIntersection.isNull, !keyboardIntersection.isEmpty else {
                return preferredFrame
            }

            func fitsAboveKeyboard(in region: CGRect) -> Bool {
                guard let presentedView else { return false }
                let availableWidth = max(0.0, region.width - 32.0)
                let width = presentedViewController.traitCollection.horizontalSizeClass == .regular
                    ? min(availableWidth, 550.0) : availableWidth
                guard width > 0.0 else { return false }

                let height = lockedHeightWhileKeyboardVisible ?? presentedView.systemLayoutSizeFitting(
                    CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .defaultLow
                ).height
                let intersection = region.intersection(keyboardFrame)
                let bottom = intersection.isNull || intersection.isEmpty ? region.maxY : intersection.minY
                return height + 2 * verticalPadding <= bottom - region.minY
            }

            if fitsAboveKeyboard(in: preferredFrame) {
                return preferredFrame
            }

            // The keyboard can occupy the lower half in tabletop pose. Move to a
            // different division region only when the preferred region cannot fit.
            return availableFrames
                .filter { $0 != preferredFrame && fitsAboveKeyboard(in: $0) }
                .min { abs($0.midY - preferredFrame.midY) < abs($1.midY - preferredFrame.midY) }
                ?? preferredFrame
        }

        return safeAreaFrame
    }

    private func sourceFrame(in containerView: UIView) -> CGRect? {
        guard let sourceView = (presentedViewController as? CustomPresentable)?.presentationSourceView,
              !sourceView.bounds.isEmpty,
              let sourceWindow = sourceView.window,
              let window = containerView.window,
              sourceWindow.screen === window.screen,
              sourceWindow.windowScene === window.windowScene else { return nil }

        // Sheets can present in another window in the same scene. Convert through
        // the windows rather than requiring both views to share a window.
        let frameInSourceWindow = sourceView.convert(sourceView.bounds, to: sourceWindow)
        let frameInWindow = sourceWindow.convert(frameInSourceWindow, to: window)
        return containerView.convert(frameInWindow, from: window)
    }

    private func captureSourceAnchor(in containerView: UIView) {
        guard sourceAnchorX == nil, sourceSide == nil,
              let presentable = presentedViewController as? CustomPresentable else { return }
        if presentable.presentationSide != .automatic {
            sourceSide = presentable.presentationSide
            return
        }
        guard let frame = sourceFrame(in: containerView),
              let window = containerView.window,
              window.bounds.width > 0.0 else { return }

        // Only a fallback for a detached or ambiguous source. A sheet-sized
        // presentation container can later expand, so normalize in the window.
        let frameInWindow = containerView.convert(frame, to: window)
        sourceAnchorX = (frameInWindow.midX - window.bounds.minX) / window.bounds.width
    }

    private func sourceFrames(
        from frames: [CGRect],
        avoiding divisions: [CGRect],
        in containerView: UIView
    ) -> [CGRect] {
        // Horizontal creases continue to use vertical alignment, including when
        // a source lies in the opposite tabletop region.
        guard let division = divisions.map({ $0.intersection(containerView.bounds) }).first(where: {
            !$0.isNull && !$0.isEmpty && $0.width < $0.height
        }) else { return frames }

        let automatic = (presentedViewController as? CustomPresentable)?.presentationSide == .automatic
        if automatic, let frame = sourceFrame(in: containerView), let window = containerView.window {
            let frameInWindow = containerView.convert(frame, to: window)
            // A moving crease must not masquerade as a moving source.
            if sourceSide == nil || frameInWindow != lastAutomaticSourceFrame {
                let extendsLeft = frame.minX < division.minX
                let extendsRight = frame.maxX > division.maxX
                if extendsLeft && !extendsRight {
                    sourceSide = .left
                } else if extendsRight && !extendsLeft {
                    sourceSide = .right
                }
            }
            lastAutomaticSourceFrame = frameInWindow
        }

        if sourceSide == nil, let sourceAnchorX, let window = containerView.window {
            let sourceX = containerView.convert(
                CGPoint(x: window.bounds.minX + sourceAnchorX * window.bounds.width, y: window.bounds.midY),
                from: window
            ).x
            if sourceX < division.minX {
                sourceSide = .left
            } else if sourceX >= division.maxX {
                sourceSide = .right
            } else {
                sourceSide = sourceAnchorX < 0.5 ? .left : .right
            }
        }

        // Follow a source that clearly moves to one pane. Keep the last side
        // while the source spans both panes, detaches, or lies in the crease.
        guard let sourceSide else { return frames }
        let preferred = frames.filter {
            sourceSide == .left ? $0.maxX <= division.minX : $0.minX >= division.maxX
        }
        return preferred.isEmpty ? frames : preferred
    }

    private func preferredFrame(
        from availableFrames: [CGRect],
        alignment: ModalPresentationAlignment,
        fallback: CGRect
    ) -> CGRect {
        switch alignment {
        case .top:
            return availableFrames.min { lhs, rhs in
                if lhs.minY != rhs.minY {
                    return lhs.minY < rhs.minY
                }
                return lhs.maxX > rhs.maxX
            } ?? fallback
        case .center:
            return availableFrames.max { lhs, rhs in
                let lhsArea = lhs.width * lhs.height
                let rhsArea = rhs.width * rhs.height
                if lhsArea != rhsArea {
                    return lhsArea < rhsArea
                }
                return lhs.maxX < rhs.maxX
            } ?? fallback
        case .bottom:
            return availableFrames.max { lhs, rhs in
                if lhs.maxY != rhs.maxY {
                    return lhs.maxY < rhs.maxY
                }
                return lhs.maxX < rhs.maxX
            } ?? fallback
        }
    }

    private func availableFrames(in frame: CGRect, avoiding reservedFrame: CGRect) -> [CGRect] {
        let intersection = frame.intersection(reservedFrame)
        guard !intersection.isNull, !intersection.isEmpty else { return [frame] }

        if intersection.width < intersection.height {
            return [
                CGRect(x: frame.minX, y: frame.minY, width: max(0.0, intersection.minX - frame.minX), height: frame.height),
                CGRect(x: intersection.maxX, y: frame.minY, width: max(0.0, frame.maxX - intersection.maxX), height: frame.height)
            ].filter { !$0.isEmpty }
        }

        return [
            CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(0.0, intersection.minY - frame.minY)),
            CGRect(x: frame.minX, y: intersection.maxY, width: frame.width, height: max(0.0, frame.maxY - intersection.maxY))
        ].filter { !$0.isEmpty }
    }
}
