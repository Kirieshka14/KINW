import Foundation
import UIKit
import WebKit
import AVFoundation

public final class WebNovelRunner: NSObject, GameRunnerProtocol {
    public let bottle: Bottle
    private var viewController: WebNovelViewController?

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init()
    }

    public func makeViewController() -> UIViewController {
        let vc = WebNovelViewController(bottle: bottle)
        self.viewController = vc
        return vc
    }

    public func pause() {
        viewController?.evaluateJavaScript("if (window.onPause) window.onPause();")
    }

    public func resume() {
        viewController?.evaluateJavaScript("if (window.onResume) window.onResume();")
    }

    public func stop() {
        viewController?.stop()
    }

    public func reload() {
        viewController?.reload()
    }

    public func sendKey(code: String, key: String, down: Bool) {
        viewController?.dispatchKeyEvent(code: code, key: key, down: down)
    }

    public var consoleLogs: [String] {
        return viewController?.capturedLogs ?? []
    }
}

public final class WebNovelViewController: UIViewController, WKScriptMessageHandler, WKURLSchemeHandler, WKNavigationDelegate {
    private let bottle: Bottle
    private var webView: WKWebView!
    private let customScheme = "kinw-app"
    private var entryBaseDirectory = ""
    public private(set) var capturedLogs: [String] = []

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0)

        setupAudioSession()
        setupWebView()
        loadGame()
    }

    override public var prefersStatusBarHidden: Bool {
        return true
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return bottle.config.orientation == "portrait" ? .portrait : .landscape
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            addLog("[KINW-Audio] Failed to set AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.setURLSchemeHandler(self, forURLScheme: customScheme)

        let userContentController = WKUserContentController()

        // Comprehensive game polyfill script
        let polyfillScript = """
        (function() {
            // Disable context menu and text selection for native app feel
            document.addEventListener('contextmenu', function(e) { e.preventDefault(); });
            document.addEventListener('selectstart', function(e) { e.preventDefault(); });

            // Ensure document canvas or body has dark background initially
            if (document.documentElement) {
                document.documentElement.style.backgroundColor = '#000000';
            }

            // Sync localStorage into KINW saves every 5 seconds
            window.kinwSaveStorage = function() {
                try {
                    var data = JSON.stringify(window.localStorage);
                    window.webkit.messageHandlers.saveSync.postMessage(data);
                } catch(e) {}
            };
            setInterval(window.kinwSaveStorage, 5000);

            // Capture JavaScript errors
            window.addEventListener('error', function(e) {
                try {
                    var errText = (e.message || 'Error') + ' at ' + (e.filename || '') + ':' + (e.lineno || 0);
                    window.webkit.messageHandlers.kinwLog.postMessage('[JS-ERR] ' + errText);
                } catch(err) {}
            });

            // Intercept console.error and console.warn
            var oldErr = console.error;
            console.error = function() {
                try {
                    var msg = Array.prototype.slice.call(arguments).map(String).join(' ');
                    window.webkit.messageHandlers.kinwLog.postMessage('[CONSOLE-ERR] ' + msg);
                } catch(e) {}
                oldErr.apply(console, arguments);
            };

            // Cordova / PhoneGap / Capacitor compatibility event
            function fireDeviceReady() {
                try {
                    var evt = document.createEvent('Event');
                    evt.initEvent('deviceready', true, true);
                    document.dispatchEvent(evt);
                    console.log('[KINW] Dispatched deviceready event');
                } catch(e) {}
            }
            if (document.readyState === 'complete') {
                setTimeout(fireDeviceReady, 100);
            } else {
                window.addEventListener('DOMContentLoaded', function() { setTimeout(fireDeviceReady, 100); });
            }

            // Android WebView JSInterface Polyfill
            if (!window.Android) {
                window.Android = {
                    showToast: function(s) { console.log('[Android.showToast]', s); },
                    exitApp: function() { console.log('[Android.exitApp]'); },
                    getLanguage: function() { return navigator.language || 'en'; }
                };
            }

            // WebAudio automatic unlock on first touch
            function unlockAudio() {
                var AudioContextClass = window.AudioContext || window.webkitAudioContext;
                if (AudioContextClass) {
                    var ctx = new AudioContextClass();
                    if (ctx.state === 'suspended') {
                        ctx.resume();
                    }
                }
                window.removeEventListener('touchstart', unlockAudio);
                window.removeEventListener('click', unlockAudio);
            }
            window.addEventListener('touchstart', unlockAudio, { passive: true });
            window.addEventListener('click', unlockAudio, { passive: true });
        })();
        """

        let userScript = WKUserScript(source: polyfillScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)
        userContentController.add(self, name: "saveSync")
        userContentController.add(self, name: "kinwLog")

        config.userContentController = userContentController

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = self

        view.addSubview(webView)
    }

    private func loadGame() {
        let bottleDir = BottleManager.shared.bottleDirectory(for: bottle.id)
        var entryRelative = bottle.entryPoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Check if entryPoint is an actual HTML file
        let fullPath = bottleDir.appendingPathComponent(entryRelative).path
        let isHtml = entryRelative.lowercased().hasSuffix(".html") || entryRelative.lowercased().hasSuffix(".htm")

        if !FileManager.default.fileExists(atPath: fullPath) || !isHtml {
            // Smart auto-discovery: find any valid HTML file inside the bottle
            if let discovered = findFirstHTML(in: bottleDir) {
                addLog("[KINW-VFS] Auto-selected HTML entry: \(discovered)")
                entryRelative = discovered
            } else {
                // No HTML found at all! Present informative UI instead of blank white screen
                showEngineMismatchView(currentEntry: bottle.entryPoint)
                return
            }
        }

        // Compute base directory of HTML entry point for relative path resolution
        let parentDir = (entryRelative as NSString).deletingLastPathComponent
        self.entryBaseDirectory = parentDir.isEmpty ? "" : parentDir

        restoreSaves()

        let urlString = "\(customScheme)://localhost/\(entryRelative)"
        if let url = URL(string: urlString) {
            addLog("[KINW-VFS] Loading: \(urlString)")
            webView.load(URLRequest(url: url))
        } else {
            showError("Invalid entry URL: \(urlString)")
        }
    }

    private func findFirstHTML(in root: URL) -> String? {
        let candidates = [
            "assets/www/index.html",
            "assets/index.html",
            "www/index.html",
            "index.html",
            "assets/game/index.html",
            "game/index.html"
        ]

        for c in candidates {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(c).path) {
                return c
            }
        }

        // Recursive search for any .html
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "html" || fileURL.pathExtension.lowercased() == "htm" {
                    let rel = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                    return rel
                }
            }
        }
        return nil
    }

    private func showEngineMismatchView(currentEntry: String) {
        let errorBox = UIView()
        errorBox.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
        errorBox.layer.cornerRadius = 16
        errorBox.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UILabel()
        icon.text = "⚠️"
        icon.font = .systemFont(ofSize: 48)

        let title = UILabel()
        title.text = "No HTML Entry Point Found"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center

        let desc = UILabel()
        desc.text = "This bottle contains native libraries (\(currentEntry)), but the runner is set to Web/HTML5.\n\nTo run this game, open Bottle Settings and select the matching engine (Native C++, Ren'Py, or inspect package files)."
        desc.font = .systemFont(ofSize: 14)
        desc.textColor = UIColor(white: 0.7, alpha: 1.0)
        desc.textAlignment = .center
        desc.numberOfLines = 0

        var btnConfig = UIButton.Configuration.filled()
        btnConfig.title = "Back to Library"
        btnConfig.baseBackgroundColor = .systemBlue
        btnConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        let closeBtn = UIButton(configuration: btnConfig)
        closeBtn.addTarget(self, action: #selector(handleClose), for: .touchUpInside)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(desc)
        stack.addArrangedSubview(closeBtn)

        errorBox.addSubview(stack)
        view.addSubview(errorBox)

        NSLayoutConstraint.activate([
            errorBox.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            errorBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            stack.topAnchor.constraint(equalTo: errorBox.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: errorBox.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: errorBox.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: errorBox.trailingAnchor, constant: -20)
        ])
    }

    @objc private func handleClose() {
        dismiss(animated: true)
    }

    public func reload() {
        addLog("[KINW] Reload requested")
        webView.reload()
    }

    public func evaluateJavaScript(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public func dispatchKeyEvent(code: String, key: String, down: Bool) {
        let type = down ? "keydown" : "keyup"
        let js = """
        (function() {
            var evt = new KeyboardEvent('\(type)', {
                key: '\(key)',
                code: '\(code)',
                bubbles: true,
                cancelable: true
            });
            document.dispatchEvent(evt);
            window.dispatchEvent(evt);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    public func stop() {
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
    }

    private func restoreSaves() {
        let savesFile = BottleManager.shared.savesDirectory(for: bottle.id).appendingPathComponent("localstorage.json")
        guard let data = try? Data(contentsOf: savesFile),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        let escaped = jsonString.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "'", with: "\\'")
        let restoreScript = """
        try {
            var saved = JSON.parse('\(escaped)');
            for (var k in saved) {
                window.localStorage.setItem(k, saved[k]);
            }
        } catch(e) {}
        """
        webView.evaluateJavaScript(restoreScript, completionHandler: nil)
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "saveSync", let json = message.body as? String {
            let savesFile = BottleManager.shared.savesDirectory(for: bottle.id).appendingPathComponent("localstorage.json")
            try? json.data(using: .utf8)?.write(to: savesFile)
        } else if message.name == "kinwLog", let logText = message.body as? String {
            addLog(logText)
        }
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        capturedLogs.append("[\(timestamp)] \(message)")
        if capturedLogs.count > 100 {
            capturedLogs.removeFirst()
        }
        print("[KINW-Web] \(message)")
    }

    // MARK: - WKNavigationDelegate
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        addLog("[NAV-ERR] Failed provisional navigation: \(error.localizedDescription)")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        addLog("[NAV-ERR] Navigation failed: \(error.localizedDescription)")
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        addLog("[NAV] Page loaded successfully")
    }

    // MARK: - WKURLSchemeHandler (Multi-Path VFS)
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bottleDir = BottleManager.shared.bottleDirectory(for: bottle.id)

        // Try multiple paths to resolve root-relative vs relative URLs
        var candidates: [URL] = [
            bottleDir.appendingPathComponent(rawPath)
        ]

        if !entryBaseDirectory.isEmpty {
            candidates.append(bottleDir.appendingPathComponent(entryBaseDirectory).appendingPathComponent(rawPath))
        }

        candidates.append(bottleDir.appendingPathComponent("assets").appendingPathComponent(rawPath))
        candidates.append(bottleDir.appendingPathComponent("assets/www").appendingPathComponent(rawPath))

        var matchedURL: URL?
        for cand in candidates {
            if FileManager.default.fileExists(atPath: cand.path) {
                matchedURL = cand
                break
            }
        }

        guard let targetURL = matchedURL,
              let data = try? Data(contentsOf: targetURL) else {
            addLog("[VFS-404] Missing: \(rawPath)")
            let notFoundResponse = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Access-Control-Allow-Origin": "*"]
            )!
            urlSchemeTask.didReceive(notFoundResponse)
            urlSchemeTask.didReceive(Data())
            urlSchemeTask.didFinish()
            return
        }

        let mime = mimeType(for: targetURL.pathExtension)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*"
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "css": return "text/css"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "wasm": return "application/wasm"
        case "ttf": return "font/ttf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "KINW Launch Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            self?.dismiss(animated: true)
        }))
        present(alert, animated: true)
    }
}
