import Foundation
import UIKit
import WebKit
import AVFoundation

public final class GodotRunner: NSObject, GameRunnerProtocol {
    public let bottle: Bottle
    private var viewController: GodotViewController?

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init()
    }

    public func makeViewController() -> UIViewController {
        let vc = GodotViewController(bottle: bottle)
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

public final class GodotViewController: UIViewController, WKScriptMessageHandler, WKURLSchemeHandler, WKNavigationDelegate {
    private let bottle: Bottle
    private var webView: WKWebView!
    private let customScheme = "kinw-godot"
    private var activePCKPath = ""
    public private(set) var capturedLogs: [String] = []

    private var extractOverlay: UIView?
    private var extractProgressBar: UIProgressView?
    private var extractStatusLabel: UILabel?

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

        checkAndStartGame()
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
            addLog("[Godot-Audio] Failed to set AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.setURLSchemeHandler(self, forURLScheme: customScheme)

        let userContentController = WKUserContentController()
        let polyfillScript = """
        (function() {
            document.addEventListener('contextmenu', function(e) { e.preventDefault(); });
            document.addEventListener('selectstart', function(e) { e.preventDefault(); });
            if (document.documentElement) {
                document.documentElement.style.backgroundColor = '#08090C';
            }

            window.addEventListener('error', function(e) {
                try {
                    var errText = (e.message || 'Error') + ' at ' + (e.filename || '') + ':' + (e.lineno || 0);
                    window.webkit.messageHandlers.kinwLog.postMessage('[JS-ERR] ' + errText);
                } catch(err) {}
            });

            var oldErr = console.error;
            console.error = function() {
                try {
                    var msg = Array.prototype.slice.call(arguments).map(String).join(' ');
                    window.webkit.messageHandlers.kinwLog.postMessage('[CONSOLE-ERR] ' + msg);
                } catch(e) {}
                oldErr.apply(console, arguments);
            };

            function unlockAudio() {
                var AudioContextClass = window.AudioContext || window.webkitAudioContext;
                if (AudioContextClass) {
                    var ctx = new AudioContextClass();
                    if (ctx.state === 'suspended') ctx.resume();
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

    private func checkAndStartGame() {
        let bottleDir = BottleManager.shared.bottleDirectory(for: bottle.id)

        // 1. Check if .pck exists
        if let pck = findPCK(in: bottleDir) {
            self.activePCKPath = pck
            loadGodotRuntime(pckRelativePath: pck)
            return
        }

        // 2. If no .pck, check if there are nested split APKs to unpack
        let contents = (try? FileManager.default.contentsOfDirectory(at: bottleDir, includingPropertiesForKeys: nil)) ?? []
        let apks = contents.filter { $0.pathExtension.lowercased() == "apk" }

        if !apks.isEmpty {
            showExtractingUI()
            Task {
                await BottleManager.shared.unpackNestedAPKs(in: bottleDir) { [weak self] status, progress in
                    DispatchQueue.main.async {
                        self?.extractStatusLabel?.text = status
                        self?.extractProgressBar?.setProgress(progress, animated: true)
                    }
                }

                await MainActor.run {
                    self.hideExtractingUI()
                    if let found = self.findPCK(in: bottleDir) {
                        self.activePCKPath = found
                        self.loadGodotRuntime(pckRelativePath: found)
                    } else {
                        self.showError("Extracted game pack, but no Godot .pck file was found.")
                    }
                }
            }
        } else {
            showError("No Godot .pck archive found in bottle.")
        }
    }

    private func findPCK(in root: URL) -> String? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "pck" {
                return fileURL.relativePath(from: root)
            }
        }

        // Secondary check: look for Godot GDPC magic header
        if let enumerator2 = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator2 {
                if !fileURL.hasDirectoryPath && isGodotPCK(url: fileURL) {
                    return fileURL.relativePath(from: root)
                }
            }
        }
        return nil
    }

    private func isGodotPCK(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 4)
        return header == Data([0x47, 0x44, 0x50, 0x43]) // "GDPC"
    }

    private func showExtractingUI() {
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UILabel()
        icon.text = "📦"
        icon.font = .systemFont(ofSize: 56)

        let title = UILabel()
        title.text = "Unpacking Game Data"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .white

        let status = UILabel()
        status.text = "Extracting multi-part Play Asset Delivery package..."
        status.font = .systemFont(ofSize: 13)
        status.textColor = .lightGray
        status.textAlignment = .center
        status.numberOfLines = 0
        self.extractStatusLabel = status

        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor = .cyan
        progress.trackTintColor = UIColor(white: 0.2, alpha: 1.0)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 240).isActive = true
        progress.setProgress(0.1, animated: false)
        self.extractProgressBar = progress

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(progress)

        overlay.addSubview(stack)
        view.addSubview(overlay)
        self.extractOverlay = overlay

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -30)
        ])
    }

    private func hideExtractingUI() {
        UIView.animate(withDuration: 0.3, animations: {
            self.extractOverlay?.alpha = 0.0
        }) { _ in
            self.extractOverlay?.removeFromSuperview()
            self.extractOverlay = nil
        }
    }

    private func loadGodotRuntime(pckRelativePath: String) {
        addLog("[KINW-Godot] Mounting Godot PCK: \(pckRelativePath)")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <title>\(bottle.title)</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { background: #08090C; color: #fff; font-family: -apple-system, system-ui, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
                #canvas { width: 100vw; height: 100vh; object-fit: contain; background: #000; display: block; }
                .loader-box { text-align: center; max-width: 420px; padding: 24px; }
                .spinner { width: 50px; height: 50px; border: 4px solid rgba(0,229,255,0.2); border-top-color: #00e5ff; border-radius: 50%; animation: spin 1s infinite linear; margin: 0 auto 16px; }
                @keyframes spin { 100% { transform: rotate(360deg); } }
                h2 { font-size: 20px; font-weight: 700; margin-bottom: 8px; }
                p { font-size: 13px; color: #8E8E93; line-height: 1.5; }
                .badge { display: inline-block; background: rgba(0,229,255,0.15); color: #00e5ff; font-size: 11px; font-weight: 700; padding: 4px 10px; border-radius: 6px; margin-top: 12px; }
            </style>
        </head>
        <body>
            <div id="loader" class="loader-box">
                <div class="spinner"></div>
                <h2>\(bottle.title)</h2>
                <p>Mounting Godot PCK archive (\(pckRelativePath))...</p>
                <div class="badge">Godot Engine Active</div>
            </div>
            <canvas id="canvas" style="display:none;"></canvas>
            <script>
                console.log("[KINW-Godot] Godot runtime initializing for PCK: \(pckRelativePath)");
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "\(customScheme)://localhost/"))
    }

    public func reload() {
        addLog("[KINW-Godot] Reload requested")
        checkAndStartGame()
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

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "kinwLog", let logText = message.body as? String {
            addLog(logText)
        }
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        capturedLogs.append("[\(timestamp)] \(message)")
        if capturedLogs.count > 100 {
            capturedLogs.removeFirst()
        }
        print("[KINW-Godot] \(message)")
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

    // MARK: - WKURLSchemeHandler
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bottleDir = BottleManager.shared.bottleDirectory(for: bottle.id)

        let target = bottleDir.appendingPathComponent(rawPath)
        let resolved = bottleDir.resolvingSymlinksInPath().appendingPathComponent(rawPath)

        var matchedURL: URL?
        if FileManager.default.fileExists(atPath: target.path) {
            matchedURL = target
        } else if FileManager.default.fileExists(atPath: resolved.path) {
            matchedURL = resolved
        }

        if let finalURL = matchedURL, let data = try? Data(contentsOf: finalURL) {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Access-Control-Allow-Origin": "*"]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } else {
            addLog("[Godot-404] Missing: \(rawPath)")
            let notFound = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Access-Control-Allow-Origin": "*"]
            )!
            urlSchemeTask.didReceive(notFound)
            urlSchemeTask.didReceive(Data())
            urlSchemeTask.didFinish()
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "KINW Godot Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            self?.dismiss(animated: true)
        }))
        present(alert, animated: true)
    }
}
