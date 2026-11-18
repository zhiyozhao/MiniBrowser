import AppKit
import Darwin
import QuartzCore
import SwiftUI
import Testing
import WebKit
@testable import MiniBrowser

/// The same test can be copied unchanged to the pre-change checkout. Normal
/// checks use deterministic local heavy pages; real-site measurements are opt-in.
@Suite("标签切换性能", .serialized)
@MainActor
struct TabSwitchPerformanceTests {
    @Test("12 个已加载页面通过真实 BrowserView 切换")
    func switchingLoadedTabs() async throws {
        let server = try LocalHTTPServer { _ in .init("""
        <html><head><title>Heavy local fixture</title></head><body>
        <canvas width="1200" height="800"></canvas><video controls></video><div id="timer"></div><script>
        const c = document.querySelector('canvas').getContext('2d');
        for (let i=0;i<3000;i++) {
            c.fillStyle = `hsl(${i%360},60%,50%)`; c.fillRect(i%1200,i%800,35,35);
            const p=document.createElement('p'); p.textContent='Document row '+i; document.body.append(p);
        }
        let tick = 0;
        setInterval(() => {
            tick++;
            document.getElementById('timer').textContent = 'timer tick ' + tick;
        }, 50);
        </script></body></html>
        """) }
        try await server.start()
        defer { server.stop() }
        let environment = ProcessInfo.processInfo.environment
        let baselineWebContentPIDs = webContentProcesses().map(\.pid)
        let realPages = environment["MINIBROWSER_REAL_PAGES"] == "1"
        let realPageURLs = [
            "https://www.theguardian.com/world", "https://www.theguardian.com/international",
            "https://www.cnn.com", "https://www.theguardian.com/technology",
            "https://developer.apple.com/documentation/webkit", "https://developer.mozilla.org/en-US/docs/Web/JavaScript",
            "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/",
            "https://en.wikipedia.org/wiki/Web_browser", "https://www.bilibili.com",
            "https://www.youtube.com/watch?v=jfKfPfyJRdk", "https://github.com/swiftlang/swift",
            "https://www.notion.com/help"
        ].compactMap(URL.init(string:))
        let requestedCount = max(12, Int(environment["MINIBROWSER_PERF_TAB_COUNT"] ?? "12") ?? 12)
        let urls = realPages ? realPageURLs : (0..<requestedCount).map { server.baseURL.appendingPathComponent("heavy/\($0)") }
        let model = BrowserWindowModel(initialTab: BrowserTab(url: urls[0]))
        for url in urls.dropFirst() { model.newTab(url: url) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if environment["MINIBROWSER_BENCHMARK_APPEARANCE"] == "light" {
            window.appearance = NSAppearance(named: .aqua)
        }
        if let screen = NSScreen.screens.first(where: { $0.localizedName == "Mi Monitor" }) {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 90, y: screen.visibleFrame.minY + 90))
        }
        let hosting = NSHostingController(rootView: BrowserView(model: model))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.orderFront(nil)
        window.setContentSize(NSSize(width: 1100, height: 760))
        hosting.view.layoutSubtreeIfNeeded()
        #expect(window.contentView!.bounds.width == 1100)
        #expect(window.contentView!.bounds.height == 760)
        defer {
            for tab in model.tabs { tab.webView.stopLoading() }
            window.contentViewController = nil
            window.close()
        }

        var pageResults: [[String: String]] = []
        var pageFailures: [String] = []
        // Let the initially presented tab finish its first navigation before
        // detaching it in the original checkout. Otherwise the old delegate
        // lifetime bug leaves that navigation's policy decision pending.
        if let initial = model.selectedTab {
            try await waitUntil("initial navigation complete", timeout: 30) {
                (realPages || !initial.webView.isLoading) && initial.webView.title?.isEmpty == false
            }
        }
        for tab in model.tabs {
            model.selectedID = tab.id
            hosting.view.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            do {
                try await waitUntil("loaded \(tab.webView.url?.absoluteString ?? "page")", timeout: realPages ? 30 : 10) {
                    guard tab.webView.title?.isEmpty == false else { return false }
                    if !realPages { return !tab.webView.isLoading }
                    let count = try? await tab.webView.evaluateJavaScript("document.body.innerText.length") as? Int
                    return (count ?? 0) > 300
                }
                let chars = try await tab.webView.evaluateJavaScript("document.body.innerText.length")
                pageResults.append(["url": tab.webView.url?.absoluteString ?? "", "title": tab.webView.title ?? "", "bodyCharacters": "\(chars ?? 0)"])
            } catch {
                print("LOAD FAILURE url=\(tab.webView.url?.absoluteString ?? "nil") title=\(tab.webView.title ?? "nil") loading=\(tab.webView.isLoading) window=\(tab.webView.window != nil)")
                pageResults.append(["url": tab.webView.url?.absoluteString ?? "", "error": "\(error)"])
                if realPages {
                    pageFailures.append(tab.webView.url?.absoluteString ?? "(unknown URL)")
                } else {
                    throw error
                }
            }
            if realPages { tab.webView.stopLoading() }
        }
        let sampler: Process? = try environment["MINIBROWSER_BENCHMARK_SAMPLE"].map { path in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "2", "1", "-file", path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }
        defer { if let sampler, sampler.isRunning { sampler.terminate(); sampler.waitUntilExit() } }
        var mainThread: [Double] = []
        var synchronous: [Double] = []
        var visible: [Double] = []
        var snapshot: [Double] = []
        let tabs = model.tabs
        for index in 0..<132 {
            let tab = tabs[index % tabs.count]
            let start = CACurrentMediaTime()
            let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            model.selectedID = tab.id
            hosting.view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            let mainEnd = CACurrentMediaTime()
            // SwiftUI can defer representable updates to the next run-loop turn.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            hosting.view.layoutSubtreeIfNeeded()
            CATransaction.flush()
            let deadline = CACurrentMediaTime() + 1
            while (tab.webView.window !== window || tab.webView.isHiddenOrHasHiddenAncestor),
                  CACurrentMediaTime() < deadline {
                try await Task.sleep(for: .milliseconds(1))
                hosting.view.layoutSubtreeIfNeeded()
                CATransaction.flush()
            }
            #expect(tab.webView.window === window && !tab.webView.isHiddenOrHasHiddenAncestor)
            let cpuEnd = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let visibleEnd = CACurrentMediaTime()
            if index >= 12 {
                mainThread.append(Double(cpuEnd-cpuStart)/1_000_000)
                synchronous.append((mainEnd-start)*1000)
                visible.append((visibleEnd-start)*1000)
                if index % 12 == 0 {
                    _ = try await tab.webView.takeSnapshot(configuration: nil)
                    snapshot.append((CACurrentMediaTime()-start)*1000)
                }
            }
        }
        func stats(_ values: [Double]) -> [String: Double] {
            let sorted = values.sorted()
            return ["p50": sorted[sorted.count/2], "p95": sorted[Int(ceil(Double(sorted.count)*0.95))-1], "max": sorted.last!]
        }
        let currentWebContent = webContentProcesses().filter { !baselineWebContentPIDs.contains($0.pid) }
        let report: [String: Any] = ["realPages": realPages, "pagesMeasured": urls.map(\.absoluteString),
            "pageFailures": pageFailures, "samples": mainThread.count,
            "webContentRSSKB": currentWebContent.reduce(0) { $0 + $1.rssKB },
            "webContentProcessCount": currentWebContent.count,
            "mainThreadMs": stats(mainThread), "synchronousActionMs": stats(synchronous),
            "viewVisibleMs": stats(visible), "snapshotReadyMs": stats(snapshot), "pages": pageResults]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if let path = environment["MINIBROWSER_BENCHMARK_REPORT"] { try data.write(to: URL(fileURLWithPath: path)) }
        sampler?.waitUntilExit()
        if let path = environment["MINIBROWSER_BENCHMARK_SHOT"] {
            model.selectedID = tabs[0].id
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            hosting.view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            _ = try await tabs[0].webView.takeSnapshot(configuration: nil)
            let view = try #require(window.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path))
        }
        #expect(stats(mainThread)["p95"]! < 16)
        #expect(pageFailures.isEmpty, "real page load failures: \(pageFailures.joined(separator: ", "))")
    }

    private func webContentProcesses() -> [(pid: Int, rssKB: Int)] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,rss=,command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text.split(separator: "\n").compactMap { line in
            guard line.contains("com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent") else { return nil }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, let pid = Int(fields[0]), let rssKB = Int(fields[1]) else { return nil }
            return (pid, rssKB)
        }
    }
}
