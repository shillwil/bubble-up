import SwiftUI

/// Horizontal scrollable tag filter bar for the library view.
struct TagFilterBar: View {
    let tags: [String]
    @Binding var selectedTag: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "ALL" pill - selected when selectedTag is nil
                TagPill(label: "ALL", isSelected: selectedTag == nil) {
                    selectedTag = nil
                }

                ForEach(tags, id: \.self) { tag in
                    TagPill(label: tag, isSelected: selectedTag == tag) {
                        selectedTag = selectedTag == tag ? nil : tag
                    }
                }
            }
        }
    }
}
