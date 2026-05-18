import SwiftUI
import UIKit

/// Adds a keyboard accessory toolbar with a single "Done" button that resigns
/// the first responder. Apply via `.keyboardDoneToolbar()` on any view whose
/// descendants take keyboard input.
struct KeyboardDoneToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
                .foregroundColor(BubbleUpTheme.primary)
                .font(.system(size: 16, weight: .semibold))
            }
        }
    }
}

extension View {
    func keyboardDoneToolbar() -> some View {
        modifier(KeyboardDoneToolbar())
    }
}
