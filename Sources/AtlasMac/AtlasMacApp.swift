import SwiftUI
import WebKit

@main
struct AtlasMacApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView()
                .frame(minWidth: 780, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    @Published var title = "New Tab"
    @Published var address = "https://www.google.com"
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false

    init(url: String = "https://www.google.com") {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        load(url)
    }

    func load(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            candidate = "https://" + trimmed
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            candidate = "https://www.google.com/search?q=" + encoded
        }
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        address = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func refreshState() {
        title = webView.title ?? "New Tab"
        address = webView.url?.absoluteString ?? address
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }
}

struct BrowserPage: NSViewRepresentable {
    @ObservedObject var tab: BrowserTab

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.navigationDelegate = context.coordinator
        return tab.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.tab = tab
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var tab: BrowserTab?

        init(tab: BrowserTab) { self.tab = tab }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor [weak tab] in tab?.refreshState() }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak tab] in tab?.refreshState() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak tab] in tab?.refreshState() }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak tab] in tab?.refreshState() }
        }
    }
}

struct BrowserView: View {
    @State private var tabs: [BrowserTab] = [BrowserTab()]
    @State private var selectedID: UUID?
    @State private var editedAddress = ""
    @FocusState private var addressFocused: Bool

    private var active: BrowserTab? {
        tabs.first(where: { $0.id == selectedID }) ?? tabs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    Button {
                        selectedID = tab.id
                        editedAddress = tab.address
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.title).lineLimit(1)
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .onTapGesture { close(tab) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(active?.id == tab.id ? Color.accentColor.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 180)
                }
                Button { addTab() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            Divider()
            if let tab = active {
                HStack(spacing: 10) {
                    Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!tab.canGoBack)
                    Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!tab.canGoForward)
                    Button {
                        if tab.isLoading { tab.webView.stopLoading() }
                        else { tab.webView.reload() }
                    } label: { Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise") }
                    TextField("Search or enter URL", text: $editedAddress)
                        .textFieldStyle(.roundedBorder)
                        .focused($addressFocused)
                        .onSubmit { tab.load(editedAddress); addressFocused = false }
                    Button {
                        if let url = tab.webView.url { NSWorkspace.shared.open(url) }
                    } label: { Image(systemName: "arrow.up.right.square") }
                    .help("Open in default browser")
                }
                .buttonStyle(.borderless)
                .padding(12)
                Divider()
                BrowserPage(tab: tab)
                    .id(tab.id)
                    .onReceive(tab.$address) { newValue in
                        if !addressFocused { editedAddress = newValue }
                    }
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = tabs.first?.id }
            editedAddress = active?.address ?? ""
        }
    }

    private func addTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        selectedID = tab.id
        editedAddress = tab.address
    }

    private func close(_ tab: BrowserTab) {
        guard tabs.count > 1 else {
            tab.load("https://www.google.com")
            return
        }
        tabs.removeAll { $0.id == tab.id }
        if selectedID == tab.id { selectedID = tabs.first?.id }
        editedAddress = active?.address ?? ""
    }
}