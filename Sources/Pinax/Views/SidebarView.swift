import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        List(SidebarSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.symbol)
                .tag(section)
        }
        .listStyle(.sidebar)
    }
}
