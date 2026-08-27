import SwiftUI

/// The five tabs, plus everything that is presented over them.
///
/// One root for iPhone, iPad, Mac and visionOS. The shape adapts to the size
/// class rather than each platform getting its own copy: the tabs, the router,
/// the family sheet and the structure sheet are identical everywhere, and
/// duplicating them is how four targets drift apart.
public struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var router = Router()
    @State private var structureCache = StructureCache()

    private let assets: PfamIEEngine.Assets

    public init(assets: PfamIEEngine.Assets) {
        self.assets = assets
    }

    private var theme: Theme {
        Theme.resolve(app.appearance.preferredColorScheme ?? systemScheme)
    }

    public var body: some View {
        Group {
            switch app.state {
            case .loading:
                LoadingView()
            case .failed(let message):
                LoadFailureView(message: message)
            case .ready:
                shell
            }
        }
        .environment(router)
        .environment(structureCache)
        .environment(\.theme, theme)
        .preferredColorScheme(app.appearance.preferredColorScheme)
        .tint(theme.accentNova)
        .background(theme.bgDeep)
        .task {
            if case .loading = app.state { await app.load(assets: assets) }
        }
        .sheet(item: Binding(
            get: { router.presentedFamily },
            set: { router.presentedFamily = $0 }
        )) { accession in
            FamilyCard(accession: accession)
                .environment(router)
                .environment(structureCache)
                .environment(\.theme, theme)
                .preferredColorScheme(app.appearance.preferredColorScheme)
        }
        .sheet(item: Binding(
            get: { router.presentedStructure },
            set: { router.presentedStructure = $0 }
        )) { request in
            StructureSheet(request: request)
                .environment(structureCache)
                .environment(\.theme, theme)
                .preferredColorScheme(app.appearance.preferredColorScheme)
        }
    }

    @ViewBuilder
    private var shell: some View {
        #if os(macOS)
        SidebarShell(router: $router)
        #elseif os(iOS) || os(visionOS)
        if sizeClass == .regular {
            SidebarShell(router: $router)
        } else {
            TabShell(router: $router)
        }
        #else
        TabShell(router: $router)
        #endif
    }
}

/// iPhone and any compact width: five tabs along the bottom.
struct TabShell: View {
    @Binding var router: Router

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    NavigationStack { destination(tab) }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(_ tab: AppTab) -> some View {
        switch tab {
        case .galaxy: GalaxyView()
        case .oracle: OracleView()
        case .grammarian: GrammarianView()
        case .prospector: ProspectorView()
        case .fieldGuide: FieldGuideView()
        }
    }
}

/// iPad and Mac: the tabs become a sidebar, and the detail pane is the tab.
struct SidebarShell: View {
    @Environment(\.theme) private var theme
    @Binding var router: Router

    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: Binding(
                get: { router.selectedTab as AppTab? },
                set: { if let new = $0 { router.selectedTab = new } }
            )) { tab in
                NavigationLink(value: tab) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tab.title)
                            Text(tab.strapline)
                                .font(.caption2)
                                .foregroundStyle(theme.inkSecondary)
                        }
                    } icon: {
                        Image(systemName: tab.symbol)
                    }
                }
            }
            .navigationTitle("PfamIE")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            NavigationStack {
                switch router.selectedTab {
                case .galaxy: GalaxyView()
                case .oracle: OracleView()
                case .grammarian: GrammarianView()
                case .prospector: ProspectorView()
                case .fieldGuide: FieldGuideView()
                }
            }
        }
    }
}

struct LoadingView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.bgDeep.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accentNova)
                    .symbolEffect(.pulse)
                Text("Mapping sequence space")
                    .font(.system(.headline, design: .rounded))
                Text("Loading 30,031 Pfam families")
                    .font(.footnote)
                    .foregroundStyle(theme.inkSecondary)
            }
        }
    }
}

struct LoadFailureView: View {
    @Environment(\.theme) private var theme
    let message: String

    var body: some View {
        ZStack {
            theme.bgDeep.ignoresSafeArea()
            ContentUnavailableView {
                Label("The Pfam data would not load", systemImage: "exclamationmark.triangle")
            } description: {
                // Name what failed. "Something went wrong" sends a user hunting
                // through Settings for a problem that is in the app bundle.
                Text(message)
                    .font(.footnote)
                    .monospaced()
            }
        }
    }
}
