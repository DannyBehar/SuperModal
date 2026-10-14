import SwiftUI
import Testing
import UIKit
@testable import SuperModal

// Synthetic regions exercise the same controller math without depending on the
// simulator's fold angle. Notification tests use real screen/view conversions.
@Suite(.serialized)
@MainActor
struct SuperModalTests {
    private let tabletop = CGRect(x: 0, y: 390, width: 800, height: 20)
    private let book = CGRect(x: 390, y: 0, width: 20, height: 800)

    @Test
    func noDivisionPreservesAlignment() {
        for name in ["top", "center", "bottom"] {
            let alignment: ModalPresentationAlignment = switch name {
            case "top": .top
            case "center": .center
            default: .bottom
            }
            let fixture = ModalFixture(alignment: alignment)
            defer { fixture.close() }
            fixture.layout()
            let frame = fixture.content.frame
            #expect(frame.width == 550)
            #expect(frame.midX == 400)
            switch alignment {
            case .top: #expect(frame.minY == 8)
            case .center: #expect(frame.midY == 400)
            case .bottom: #expect(frame.maxY == 792)
            }
        }
    }

    @Test
    func asymmetricSafeAreaInsetsAreRespected() {
        let fixture = ModalFixture()
        defer { fixture.close() }
        fixture.container.insets = UIEdgeInsets(top: 30, left: 90, bottom: 20, right: 10)
        fixture.layout()
        #expect(fixture.content.frame.midX == 440)
        #expect(fixture.content.frame.maxY == 772)
    }

    @available(iOS 27.1, *)
    @Test
    func inactiveDivisionsDoNotDisplaceModal() {
        for name in ["top", "center", "bottom"] {
            let alignment: ModalPresentationAlignment = switch name {
            case "top": .top
            case "center": .center
            default: .bottom
            }
            let fixture = ModalFixture(alignment: alignment)
            defer { fixture.close() }
            fixture.layout()
            let original = fixture.content.frame
            fixture.controller.regions = [(book, false), (tabletop, false)]
            fixture.layout()
            #expect(fixture.content.frame == original)
        }
    }

    @available(iOS 27.1, *)
    @Test
    func bookPoseKeepsModalToRightOfCrease() {
        for name in ["top", "center", "bottom"] {
            let alignment: ModalPresentationAlignment = switch name {
            case "top": .top
            case "center": .center
            default: .bottom
            }
            let fixture = ModalFixture(alignment: alignment)
            defer { fixture.close() }
            fixture.controller.regions = [(book, true)]
            fixture.layout()
            #expect(fixture.content.frame.minX == 426)
            #expect(fixture.content.frame.maxX == 784)
            #expect(!fixture.content.frame.intersects(book))
        }
    }

    @available(iOS 27.1, *)
    @Test
    func tabletopRespectsVerticalAlignment() {
        for name in ["top", "bottom"] {
            let alignment: ModalPresentationAlignment = switch name {
            case "top": .top
            case "center": .center
            default: .bottom
            }
            let fixture = ModalFixture(alignment: alignment)
            defer { fixture.close() }
            fixture.controller.regions = [(tabletop, true)]
            fixture.layout()
            if alignment == .top {
                #expect(fixture.content.frame.minY == 8)
            } else {
                #expect(fixture.content.frame.maxY == 792)
            }
            #expect(!fixture.content.frame.intersects(tabletop))
        }
    }

    @available(iOS 27.1, *)
    @Test
    func centerChoosesLargestRegion() {
        let fixture = ModalFixture(alignment: .center)
        defer { fixture.close() }
        fixture.controller.regions = [(CGRect(x: 0, y: 290, width: 800, height: 20), true)]
        fixture.layout()
        #expect(fixture.content.frame.midY == 555)
    }

    @available(iOS 27.1, *)
    @Test
    func outsideAndEmptyDivisionsLeaveFrameUnchanged() {
        let fixture = ModalFixture()
        defer { fixture.close() }
        fixture.layout()
        let original = fixture.content.frame
        fixture.controller.regions = [
            (CGRect(x: 900, y: 0, width: 20, height: 800), true),
            (.zero, true)
        ]
        fixture.layout()
        #expect(fixture.content.frame == original)
    }

    @available(iOS 27.1, *)
    @Test
    func multipleDivisionsAreAvoided() {
        let fixture = ModalFixture(height: 100)
        defer { fixture.close() }
        fixture.controller.regions = [(book, true), (tabletop, true)]
        fixture.layout()
        #expect(fixture.content.frame.minX == 426)
        #expect(fixture.content.frame.maxY == 792)
        #expect(!fixture.content.frame.intersects(book))
        #expect(!fixture.content.frame.intersects(tabletop))
    }

    @Test
    func overlappingKeyboardLiftsModalWithPadding() {
        let fixture = ModalFixture()
        defer { fixture.close() }
        fixture.showKeyboard(CGRect(x: 0, y: 550, width: 800, height: 250))
        #expect(fixture.content.frame.maxY == 542)
        #expect(fixture.content.frame.minY >= 8)
    }

    @Test
    func horizontallyDisjointKeyboardDoesNotLiftModal() {
        let fixture = ModalFixture()
        defer { fixture.close() }
        fixture.layout()
        let original = fixture.content.frame
        fixture.showKeyboard(CGRect(x: 900, y: 500, width: 300, height: 300))
        #expect(fixture.content.frame == original)
    }

    @available(iOS 27.1, *)
    @Test
    func keyboardBelowUpperRegionDoesNotLiftCenteredModal() {
        let fixture = ModalFixture(alignment: .center)
        defer { fixture.close() }
        fixture.controller.regions = [(tabletop, true)]
        fixture.layout()
        let original = fixture.content.frame
        fixture.showKeyboard(CGRect(x: 0, y: 500, width: 800, height: 300))
        #expect(fixture.content.frame == original)
    }

    @available(iOS 27.1, *)
    @Test
    func tabletopMovesAboveCreaseAndReturnsWhenKeyboardHides() {
        let fixture = ModalFixture(height: 200)
        defer { fixture.close() }
        fixture.controller.regions = [(tabletop, true)]
        fixture.layout()
        let original = fixture.content.frame
        fixture.showKeyboard(CGRect(x: 0, y: 500, width: 800, height: 300))
        #expect(fixture.content.frame.maxY == 382)
        #expect(!fixture.content.frame.intersects(tabletop))
        fixture.hideKeyboard()
        #expect(fixture.content.frame == original)
    }

    @available(iOS 27.1, *)
    @Test
    func lowerRegionIsRetainedWhenModalFitsAboveKeyboard() {
        let fixture = ModalFixture(height: 100)
        defer { fixture.close() }
        fixture.controller.regions = [(tabletop, true)]
        fixture.showKeyboard(CGRect(x: 0, y: 650, width: 800, height: 150))
        #expect(fixture.content.frame.minY >= 418)
        #expect(fixture.content.frame.maxY == 642)
    }

    @available(iOS 27.1, *)
    @Test
    func noFittingAlternativePreservesPreferredRegionAndLiftLimit() {
        let fixture = ModalFixture(height: 500)
        defer { fixture.close() }
        fixture.controller.regions = [(tabletop, true)]
        fixture.layout()
        let original = fixture.content.frame
        fixture.showKeyboard(CGRect(x: 0, y: 500, width: 800, height: 300))
        // Oversized content remains an explicit limitation, not a false fit.
        #expect(fixture.content.frame == original)
    }

    @Test
    func keyboardCoordinatesAreReconvertedWhenContainerMoves() {
        let fixture = ModalFixture()
        defer { fixture.close() }
        fixture.showKeyboard(CGRect(x: 0, y: 550, width: 800, height: 250))
        #expect(fixture.content.frame.maxY == 542)
        fixture.container.frame.origin.y = 100
        fixture.layout() // Deliberately do not send another keyboard notification.
        #expect(fixture.content.frame.maxY == 442)
    }

    @Test
    func finalKeyboardNotificationReconcilesResize() {
        let fixture = ModalFixture()
        defer { fixture.close() }
        fixture.showKeyboard(CGRect(x: 0, y: 550, width: 800, height: 250))
        fixture.container.frame.size = CGSize(width: 600, height: 1000)
        fixture.sendKeyboard(UIResponder.keyboardDidChangeFrameNotification,
                             frame: CGRect(x: 0, y: 700, width: 600, height: 300))
        #expect(fixture.content.frame.maxY == 692)
        #expect(fixture.content.frame.midX == 300)
    }

    @Test
    func changingContentInvalidatesKeyboardHeightLock() {
        let fixture = ModalFixture(height: 100)
        defer { fixture.close() }
        fixture.showKeyboard(CGRect(x: 0, y: 550, width: 800, height: 250))
        fixture.content.fittingHeight = 200
        fixture.layout()
        #expect(fixture.content.frame.height == 100)
        fixture.controller.invalidateContentSize()
        fixture.layout()
        #expect(fixture.content.frame.height == 200)
        #expect(fixture.content.frame.maxY == 542)
        fixture.content.fittingHeight = 100
        fixture.controller.invalidateContentSize()
        fixture.layout()
        #expect(fixture.content.frame.height == 100)
    }

    @available(iOS 27.1, *)
    @Test
    func poseChangesRemeasureWidth() {
        let fixture = ModalFixture()
        defer { fixture.close() }
        fixture.layout()
        #expect(fixture.content.frame.width == 550)
        fixture.controller.regions = [(book, true)]
        fixture.layout()
        #expect(fixture.content.frame.width == 358)
        #expect(fixture.content.lastFittingWidth == 358)
        fixture.controller.regions = []
        fixture.layout()
        #expect(fixture.content.frame.width == 550)
    }

    @Test
    func dismissalClearsKeyboardStateAndObservers() {
        let fixture = ModalFixture()
        defer { fixture.close() }
        fixture.showKeyboard(CGRect(x: 0, y: 550, width: 800, height: 250))
        fixture.controller.dismissalTransitionDidEnd(true)
        fixture.layout()
        #expect(fixture.content.frame.maxY == 792)
        fixture.showKeyboard(CGRect(x: 0, y: 550, width: 800, height: 250))
        #expect(fixture.content.frame.maxY == 792)
    }

    @Test
    func presentedModalAutomaticallyResizesWhenRowsChange() async throws {
        let presenter = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        presenter.loadViewIfNeeded()
        window.addSubview(presenter.view)
        let modal = SuperModalHostingController(rootView: RowsContent(rows: 1))
        let container = LayoutContainer(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        presenter.view.addSubview(container)
        let presentation = SyntheticPresentationController(presentedViewController: modal, presenting: presenter)
        presentation.testContainer = container
        let manager = TestTransitionDelegate(controller: presentation)
        modal.modalPresentationStyle = .custom
        modal.transitionManager = manager
        modal.transitioningDelegate = manager
        presenter.present(modal, animated: false)
        #expect(modal.presentationController === presentation)
        container.addSubview(modal.view)
        container.onLayout = { [weak presentation] in presentation?.containerViewWillLayoutSubviews() }
        defer {
            presentation.dismissalTransitionDidEnd(true)
            container.onLayout = nil
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(abs(modal.view.bounds.height - 40) < 1)
        for rows in [2, 1] {
            modal.rootView = RowsContent(rows: rows)
            let expectedHeight: CGFloat = rows == 2 ? 90 : 40
            // Service pending layout without invalidating it. Only the production
            // preferred-content-size callback should request a new presentation layout.
            for _ in 0..<100 {
                container.layoutIfNeeded()
                if abs(modal.view.bounds.height - expectedHeight) < 1 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(abs(modal.view.bounds.height - expectedHeight) < 1)
        }
    }

    @Test
    func hostingControllerTracksOneAndTwoRowContent() async throws {
        let controller = SuperModalHostingController(rootView: RowsContent(rows: 1))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.loadViewIfNeeded()
        let host = try #require(controller.children.last)
        func height() -> CGFloat {
            controller.view.systemLayoutSizeFitting(
                CGSize(width: 350, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .defaultLow
            ).height
        }
        controller.view.bounds.size.width = 350
        for _ in 0..<5 { controller.view.layoutIfNeeded(); await Task.yield() }
        let oneRow = height()
        #expect(abs(host.preferredContentSize.height - 40) < 1)
        controller.rootView = RowsContent(rows: 2)
        for _ in 0..<5 { controller.view.layoutIfNeeded(); await Task.yield() }
        let twoRows = height()
        #expect(abs(host.preferredContentSize.height - 90) < 1)
        #expect(abs(twoRows - oneRow - 50) < 1)
        controller.rootView = RowsContent(rows: 1)
        for _ in 0..<5 { controller.view.layoutIfNeeded(); await Task.yield() }
        #expect(abs(height() - oneRow) < 1)
    }
}

private struct RowsContent: View {
    let rows: Int
    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: 40)
            if rows == 2 { Color.clear.frame(height: 40) }
        }
    }
}

@MainActor
private final class ModalFixture {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
    let container = LayoutContainer(frame: CGRect(x: 0, y: 0, width: 800, height: 800))
    let content = FittingView()
    let presented = ModalContentController()
    let controller: SyntheticPresentationController

    init(alignment: ModalPresentationAlignment = .bottom, height: CGFloat = 200) {
        let presenter = UIViewController()
        window.rootViewController = presenter
        presenter.loadViewIfNeeded()
        window.addSubview(presenter.view)
        presenter.view.addSubview(container)
        #expect(container.window === window)
        content.fittingHeight = height
        presented.view = content
        presented.presentationAlignment = alignment
        presented.traitOverrides.horizontalSizeClass = .regular
        controller = SyntheticPresentationController(presentedViewController: presented, presenting: presenter)
        controller.testContainer = container
        container.addSubview(content)
        container.onLayout = { [weak controller] in controller?.containerViewWillLayoutSubviews() }
        controller.presentationTransitionWillBegin()
        layout()
    }

    func layout() {
        container.setNeedsLayout()
        container.layoutIfNeeded()
    }

    func sendKeyboard(_ name: Notification.Name, frame: CGRect) {
        let screenFrame = container.convert(frame, to: window.screen.coordinateSpace)
        NotificationCenter.default.post(name: name, object: window.screen, userInfo: [
            UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: screenFrame)
        ])
        layout()
    }

    func showKeyboard(_ frame: CGRect) {
        sendKeyboard(UIResponder.keyboardWillChangeFrameNotification, frame: frame)
        sendKeyboard(UIResponder.keyboardDidChangeFrameNotification, frame: frame)
    }

    func hideKeyboard() {
        sendKeyboard(UIResponder.keyboardWillHideNotification,
                     frame: CGRect(x: 0, y: 1100, width: 800, height: 300))
        sendKeyboard(UIResponder.keyboardDidChangeFrameNotification,
                     frame: CGRect(x: 0, y: 1100, width: 800, height: 300))
    }

    func close() {
        controller.dismissalTransitionDidEnd(true)
        container.onLayout = nil
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
private final class SyntheticPresentationController: ModalPresentationController {
    var testContainer: UIView?
    var regions: [(frame: CGRect, isActive: Bool)] = []
    override var containerView: UIView? { testContainer }
    override var presentedView: UIView? { presentedViewController.view }
    override func divisionRegions(in containerView: UIView) -> [(frame: CGRect, isActive: Bool)] {
        regions
    }
}

@MainActor
private final class LayoutContainer: UIView {
    var insets: UIEdgeInsets = .zero
    var onLayout: (() -> Void)?
    override var safeAreaInsets: UIEdgeInsets { insets }
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

@MainActor
private final class FittingView: UIView {
    var fittingHeight: CGFloat = 200
    var lastFittingWidth: CGFloat = 0
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        lastFittingWidth = targetSize.width
        return CGSize(width: targetSize.width, height: fittingHeight)
    }
}

@MainActor
private final class ModalContentController: UIViewController, CustomPresentable {
    var transitionManager: UIViewControllerTransitioningDelegate?
    var presentationAlignment: ModalPresentationAlignment = .bottom
}

@MainActor
private final class TestTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    let controller: UIPresentationController
    init(controller: UIPresentationController) {
        self.controller = controller
    }
    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        controller
    }
}
