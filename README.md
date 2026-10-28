<img src="./branding.png" width="400" />

`SuperModal` is a SwiftUI wrapper around a custom UIViewController modal transition system.

It provides a simple and familiar SwiftUI API for:
- slide-in modal presentation
- interactive drag-to-dismiss
- configurable alignment (`top`, `center`, `bottom`)
- keyboard-aware positioning
- iPhone and iPad support

## Origin / Attribution

This project is based on [@danielmgauthier](https://github.com/danielmgauthier)'s UIKit transition work:

- [ViewControllerTransitionExample](https://github.com/danielmgauthier/ViewControllerTransitionExample)

From Daniel's blog posts: 

[Make  your custom transitions reusable](https://danielgauthier.me/2020/02/24/indie5-1.html)

[Make your custom transitions feel natural](https://danielgauthier.me/2020/02/27/indie5-2.html)

[Make your custom transitions resizable](https://danielgauthier.me/2020/03/03/indie5-3.html)

## Demo
Bottom aligned with stacking

https://github.com/user-attachments/assets/9aacc31e-4798-458d-bf17-f5cc5ecdfd1b

Top aligned

https://github.com/user-attachments/assets/26814fcd-3933-4c65-8825-6ba925e628f8



## Requirements

- iOS 16.0+
- Swift 6.2 toolchain (per `Package.swift`)

## Installation (Swift Package Manager)

Add this package in Xcode with your repository URL, or add it in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<your-org-or-user>/SuperModal.git", branch: "main")
]
```

Then add the product to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "SuperModal", package: "SuperModal")
    ]
)
```

## Usage

Import:

```swift
import SuperModal
```

Available modifiers:

- `superModal(isPresented:interactiveDismissalType:alignment:side:content:)`
- `superModal(item:interactiveDismissalType:alignment:side:content:)`
- `superModalBackground(_:)` where the argument conforms to `ShapeStyle`

Options:

- `InteractiveDismissalType`: `.none`, `.standard`
- `ModalPresentationAlignment`: `.top`, `.center`, `.bottom`
- `ModalPresentationSide`: `.automatic` (default), `.left`, `.right`

On a folded iPhone Duo, automatic side selection uses the position of the view carrying
`.superModal`. Attach the modifier to the invoking pane or button. If the modifier is on
a view spanning both panes, pass the side from the action that opens the modal:

```swift
@State private var showModal = false
@State private var modalSide: ModalPresentationSide = .left

var body: some View {
    HStack {
        Button("Open from left") {
            modalSide = .left
            showModal = true
        }
        Spacer()
        Button("Open from right") {
            modalSide = .right
            showModal = true
        }
    }
    .superModal(isPresented: $showModal, alignment: .bottom, side: modalSide) {
        Text("Modal content").padding()
    }
}
```

Automatic placement follows the source view as a sheet or split-view pane moves during
fold transitions. While the source spans both panes or lies within the crease, the last
resolved side is retained. An explicit side stays fixed for that presentation. `alignment`
continues to control top, center, or bottom placement, including tabletop pose. Keyboard avoidance
can use another region when the preferred region cannot fit the content. Both modal
overloads accept `side`.

## Example 1: Boolean Presentation

```swift
import SwiftUI
import SuperModal

struct ContentView: View {
    @State private var showModal = false

    var body: some View {
        VStack(spacing: 16) {
            Button("Show Modal") {
                showModal = true
            }
        }
        .superModal(
            isPresented: $showModal,
            interactiveDismissalType: .standard,
            alignment: .bottom
        ) {
            VStack(spacing: 12) {
                Text("Hello from SuperModal")
                Button("Close") { showModal = false }
            }
            .padding(16)
        }
    }
}
```

## Example 2: Item-based Presentation

```swift
import SwiftUI
import SuperModal

struct SheetItem: Identifiable {
    let id = UUID()
    let title: String
}

struct ItemModalExample: View {
    @State private var selectedItem: SheetItem?

    var body: some View {
        List {
            Button("Open Profile") {
                selectedItem = SheetItem(title: "Profile")
            }
            Button("Open Settings") {
                selectedItem = SheetItem(title: "Settings")
            }
        }
        .superModal(
            item: $selectedItem,
            interactiveDismissalType: .standard,
            alignment: .center
        ) { item in
            VStack(spacing: 12) {
                Text(item.title)
                    .font(.headline)
                Button("Dismiss") {
                    selectedItem = nil
                }
            }
            .padding(20)
        }
    }
}
```
