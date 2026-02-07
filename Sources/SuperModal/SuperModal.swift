import SwiftUI
import UIKit

final class SuperModalHostingController<Content: View>: UIViewController, CustomPresentable {
    var transitionManager: UIViewControllerTransitioningDelegate?
    var onDismiss: (() -> Void)?
    var presentationAlignment: ModalPresentationAlignment = .top
    var presentationTransformTargetView: UIView? { contentContainerView }

    private let contentContainerView = UIView()
    private var hostingController: UIHostingController<Content>

    var rootView: Content {
        get { hostingController.rootView }
        set { hostingController.rootView = newValue }
    }

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.backgroundColor = .systemBackground
        
        if #available(iOS 26.0, *) {
            contentContainerView.cornerConfiguration = .uniformCorners(radius: .containerConcentric(minimum: 20))
        } else {
            contentContainerView.layer.cornerRadius = 20.0
        }
        
        contentContainerView.layer.masksToBounds = true

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        hostingController.safeAreaRegions = .container

        view.addSubview(contentContainerView)
        contentContainerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            hostingController.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            onDismiss?()
        }
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
}


#Preview {
    @Previewable @State var isPresented: Bool = false
    
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
