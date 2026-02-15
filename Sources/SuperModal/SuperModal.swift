import SwiftUI
import UIKit

// Stored in a preference value and consumed on the main actor by UIKit presentation code.
// The closure only builds SwiftUI view values and is never shared across threads in practice.
private final class SuperModalBackgroundProvider: Equatable, @unchecked Sendable {
    let makeBackgroundView: () -> AnyView

    init(makeBackgroundView: @escaping () -> AnyView) {
        self.makeBackgroundView = makeBackgroundView
    }

    static func == (lhs: SuperModalBackgroundProvider, rhs: SuperModalBackgroundProvider) -> Bool {
        lhs === rhs
    }
}

private struct SuperModalBackgroundPreferenceKey: PreferenceKey {
    static let defaultValue: SuperModalBackgroundProvider? = nil

    static func reduce(value: inout SuperModalBackgroundProvider?, nextValue: () -> SuperModalBackgroundProvider?) {
        value = nextValue() ?? value
    }
}

private func makeDefaultModalBackgroundView() -> AnyView {
    AnyView(Rectangle().fill(Color(uiColor: .systemBackground)))
}

private struct SuperModalContentView<Content: View>: View {
    let content: Content
    let onModalBackgroundChange: (SuperModalBackgroundProvider?) -> Void

    var body: some View {
        content.onPreferenceChange(SuperModalBackgroundPreferenceKey.self) { provider in
            onModalBackgroundChange(provider)
        }
    }
}

final class SuperModalHostingController<Content: View>: UIViewController, CustomPresentable {
    var transitionManager: UIViewControllerTransitioningDelegate?
    var onDismiss: (() -> Void)?
    var presentationAlignment: ModalPresentationAlignment = .top
    var presentationTransformTargetView: UIView? { contentContainerView }

    private let contentContainerView = UIView()
    private var currentRootView: Content
    private var currentModalBackgroundProvider: SuperModalBackgroundProvider?
    private var modalBackgroundHostingController: UIHostingController<AnyView>?
    private var hostingController: UIHostingController<SuperModalContentView<Content>>

    var rootView: Content {
        get { currentRootView }
        set {
            currentRootView = newValue
            hostingController.rootView = wrappedRootView(newValue)
        }
    }

    init(rootView: Content) {
        currentRootView = rootView
        hostingController = UIHostingController(rootView: SuperModalContentView(content: rootView, onModalBackgroundChange: { _ in }))
        super.init(nibName: nil, bundle: nil)
        hostingController.rootView = wrappedRootView(rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.backgroundColor = .clear
        
        if #available(iOS 26.0, *) {
            contentContainerView.cornerConfiguration = .uniformCorners(radius: .containerConcentric(minimum: 20))
        } else {
            contentContainerView.layer.cornerRadius = 20.0
        }
        
        contentContainerView.layer.masksToBounds = true

        let backgroundHostingController = UIHostingController(rootView: makeDefaultModalBackgroundView())
        backgroundHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        backgroundHostingController.view.backgroundColor = .clear
        modalBackgroundHostingController = backgroundHostingController

        addChild(backgroundHostingController)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        
        if #available(iOS 16.4, *) {
            hostingController.safeAreaRegions = .container
        }

        view.addSubview(contentContainerView)
        contentContainerView.addSubview(backgroundHostingController.view)
        contentContainerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backgroundHostingController.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            backgroundHostingController.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            backgroundHostingController.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            backgroundHostingController.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),

            hostingController.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])

        backgroundHostingController.didMove(toParent: self)
        hostingController.didMove(toParent: self)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            onDismiss?()
        }
    }

    private func wrappedRootView(_ rootView: Content) -> SuperModalContentView<Content> {
        SuperModalContentView(content: rootView) { [weak self] provider in
            self?.setModalBackgroundProvider(provider)
        }
    }

    private func setModalBackgroundProvider(_ provider: SuperModalBackgroundProvider?) {
        if currentModalBackgroundProvider == nil, provider == nil {
            return
        }
        if let currentModalBackgroundProvider, let provider, currentModalBackgroundProvider === provider {
            return
        }
        currentModalBackgroundProvider = provider
        modalBackgroundHostingController?.rootView = provider?.makeBackgroundView() ?? makeDefaultModalBackgroundView()
    }
}

private struct SuperModalPresenter<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let interactiveDismissalType: InteractiveDismissalType
    let alignment: ModalPresentationAlignment
    let content: () -> Content
    
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented {
            if let presentedController = context.coordinator.presentedController {
                presentedController.rootView = content()
                presentedController.presentationAlignment = alignment
                presentedController.updatePresentationLayout(animated: true)
            } else {
                let hostingController = SuperModalHostingController(rootView: content())
                hostingController.presentationAlignment = alignment
                hostingController.onDismiss = { [weak coordinator = context.coordinator] in
                    coordinator?.isPresented.wrappedValue = false
                    coordinator?.presentedController = nil
                }
                uiViewController.present(hostingController, interactiveDismissalType: interactiveDismissalType)
                hostingController.presentationController?.delegate = context.coordinator
                context.coordinator.presentedController = hostingController
            }
        } else if let presentedController = context.coordinator.presentedController {
            if presentedController.presentingViewController != nil {
                presentedController.dismiss(animated: true)
            }
            context.coordinator.presentedController = nil
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }
    
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isPresented: Binding<Bool>
        weak var presentedController: SuperModalHostingController<Content>?
        
        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }
        
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            isPresented.wrappedValue = false
            presentedController = nil
        }
    }
}

private struct SuperModalItemPresenter<Item: Identifiable, Content: View>: UIViewControllerRepresentable {
    @Binding var item: Item?
    let interactiveDismissalType: InteractiveDismissalType
    let alignment: ModalPresentationAlignment
    let content: (Item) -> Content
    
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let currentItem = item {
            if let presentedController = context.coordinator.presentedController {
                presentedController.rootView = content(currentItem)
                presentedController.presentationAlignment = alignment
                presentedController.updatePresentationLayout(animated: true)
            } else {
                let hostingController = SuperModalHostingController(rootView: content(currentItem))
                hostingController.presentationAlignment = alignment
                
                hostingController.onDismiss = { [weak coordinator = context.coordinator] in
                    coordinator?.item.wrappedValue = nil
                    coordinator?.presentedController = nil
                }
                uiViewController.present(hostingController, interactiveDismissalType: interactiveDismissalType)
                hostingController.presentationController?.delegate = context.coordinator
                context.coordinator.presentedController = hostingController
            }
        } else if let presentedController = context.coordinator.presentedController {
            if presentedController.presentingViewController != nil {
                presentedController.dismiss(animated: true)
            }
            context.coordinator.presentedController = nil
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(item: $item)
    }
    
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var item: Binding<Item?>
        weak var presentedController: SuperModalHostingController<Content>?
        
        init(item: Binding<Item?>) {
            self.item = item
        }
        
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            item.wrappedValue = nil
            presentedController = nil
        }
    }
}

extension View {
    public func superModal<Content: View>(
        isPresented: Binding<Bool>,
        interactiveDismissalType: InteractiveDismissalType = .standard,
        alignment: ModalPresentationAlignment = .top,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(
            SuperModalPresenter(
                isPresented: isPresented,
                interactiveDismissalType: interactiveDismissalType,
                alignment: alignment,
                content: content
            )
        )
    }
    
    public func superModal<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        interactiveDismissalType: InteractiveDismissalType = .standard,
        alignment: ModalPresentationAlignment = .top,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        background(
            SuperModalItemPresenter(
                item: item,
                interactiveDismissalType: interactiveDismissalType,
                alignment: alignment,
                content: content
            )
        )
    }

    public func superModalBackground<S: ShapeStyle>(_ style: S) -> some View {
        preference(
            key: SuperModalBackgroundPreferenceKey.self,
            value: SuperModalBackgroundProvider {
                AnyView(Rectangle().fill(style))
            }
        )
    }
}

struct SuperModalPreviewContainer: View {
    @State var isPresented: Bool = false
    
    var body: some View {
        VStack {
            Color.green
            
            Button("Tap Me") {
                isPresented.toggle()
            }
        }
        .superModal(isPresented: $isPresented) {
           FirstModalView()
        }
    }
}

#Preview {
    SuperModalPreviewContainer()
}


struct FirstModalView: View {
    @State private var showSecond = false

    var body: some View {
        VStack(spacing: 16) {
            Text("First modal")
            Button("Show Second") { showSecond = true }
        }
        .padding(16)
        .superModal(isPresented: $showSecond) {
            SecondModalView()
        }
    }
}

struct SecondModalView: View {
    @State private var showThird = false

    var body: some View {
        VStack(spacing: 16) {
            Text("First modal")
            Button("Show Second") { showThird = true }
        }
        .padding(16)
        .superModal(isPresented: $showThird) {
            VStack(spacing: 16) {
                Text("Second modal")
                Button("Dismiss") { showThird = false }
            }
            .padding(16)
        }
    }
}
