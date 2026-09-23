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

    // Thread-safe tracking of active WKURLSchemeTasks
    private let taskLock = NSLock()
    private var activeTasks = Set<ObjectIdentifier>()

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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            addLog("[Godot-Audio] Failed to set AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        config.setURLSchemeHandler(self, forURLScheme: customScheme)

        let userContentController = WKUserContentController()
        let polyfillScript = """
        (function() {
            document.addEventListener('contextmenu', function(e) { e.preventDefault(); });
            document.addEventListener('selectstart', function(e) { e.preventDefault(); });
            if (document.documentElement) {
                document.documentElement.style.backgroundColor = '#08090C';
            }

            // Secure Context polyfill for local custom scheme
            try {
                if (window.isSecureContext === undefined || window.isSecureContext === false) {
                    Object.defineProperty(window, 'isSecureContext', { value: true, configurable: true });
                }
            } catch(e) {}

            // Safe WebAssembly streaming instantiation fallback
            if (window.WebAssembly && window.WebAssembly.instantiateStreaming) {
                var origInstantiate = window.WebAssembly.instantiateStreaming;
                window.WebAssembly.instantiateStreaming = function(source, imports) {
                    return Promise.resolve(source).then(function(res) {
                        return origInstantiate(res, imports).catch(function(err) {
                            console.warn('[KINW-Wasm] instantiateStreaming failed, falling back to arrayBuffer:', err);
                            return res.arrayBuffer().then(function(bytes) {
                                return WebAssembly.instantiate(bytes, imports);
                            });
                        });
                    });
                };
            }

            // Console log forwarding
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

            var oldWarn = console.warn;
            console.warn = function() {
                try {
                    var msg = Array.prototype.slice.call(arguments).map(String).join(' ');
                    window.webkit.messageHandlers.kinwLog.postMessage('[CONSOLE-WARN] ' + msg);
                } catch(e) {}
                oldWarn.apply(console, arguments);
            };

            var oldLog = console.log;
            console.log = function() {
                try {
                    var msg = Array.prototype.slice.call(arguments).map(String).join(' ');
                    window.webkit.messageHandlers.kinwLog.postMessage('[CONSOLE] ' + msg);
                } catch(e) {}
                oldLog.apply(console, arguments);
            };

            function unlockAudio() {
                var AudioContextClass = window.AudioContext || window.webkitAudioContext;
                if (AudioContextClass) {
                    var ctx = new AudioContextClass();
                    if (ctx.state === 'suspended') ctx.resume();
                }
                if (window.GodotAudio && window.GodotAudio.ctx && window.GodotAudio.ctx.state === 'suspended') {
                    window.GodotAudio.ctx.resume();
                }
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

    private func findGodotRuntimeFile(named name: String) -> URL? {
        // 1. Direct bundle search
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "GodotRuntime") {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let direct = resourceURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            let sub = resourceURL.appendingPathComponent("GodotRuntime").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: sub.path) { return sub }
        }

        // 2. Documents / Runtimes directory fallback
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let runtimeDir = docs.appendingPathComponent("Runtimes/Godot4").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: runtimeDir.path) { return runtimeDir }
        }

        return nil
    }

    private func findPCK(in root: URL) -> String? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }

        var candidates: [(url: URL, size: Int64)] = []

        for case let fileURL as URL in enumerator {
            guard !fileURL.hasDirectoryPath else { continue }
            let ext = fileURL.pathExtension.lowercased()
            if ext == "pck" || isGodotPCK(url: fileURL) {
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                candidates.append((url: fileURL, size: Int64(size)))
            }
        }

        // Sort descending by size so the main pack is picked
        candidates.sort { $0.size > $1.size }

        if let best = candidates.first {
            return best.url.relativePath(from: root)
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

        let escapedTitle = bottle.title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0">
            <title>\(escapedTitle)</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    width: 100%;
                    height: 100%;
                    background: #000;
                    color: #fff;
                    overflow: hidden;
                    touch-action: none;
                    -webkit-user-select: none;
                    user-select: none;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                }
                #canvas {
                    display: block;
                    width: 100vw;
                    height: 100vh;
                    object-fit: contain;
                    background: #000;
                }
                #canvas:focus { outline: none; }
                #status {
                    position: absolute;
                    top: 0; left: 0; right: 0; bottom: 0;
                    background: radial-gradient(circle at center, #141721 0%, #08090C 100%);
                    display: flex;
                    flex-direction: column;
                    justify-content: center;
                    align-items: center;
                    z-index: 10;
                    padding: 24px;
                    transition: opacity 0.4s ease-out;
                }
                .loader-card {
                    background: rgba(255, 255, 255, 0.05);
                    border: 1px solid rgba(255, 255, 255, 0.12);
                    backdrop-filter: blur(20px);
                    -webkit-backdrop-filter: blur(20px);
                    border-radius: 20px;
                    padding: 32px 28px;
                    max-width: 380px;
                    width: 90%;
                    text-align: center;
                    box-shadow: 0 20px 40px rgba(0,0,0,0.6);
                }
                .engine-badge {
                    display: inline-flex;
                    align-items: center;
                    gap: 6px;
                    background: rgba(0, 229, 255, 0.12);
                    color: #00e5ff;
                    border: 1px solid rgba(0, 229, 255, 0.3);
                    border-radius: 12px;
                    padding: 4px 12px;
                    font-size: 11px;
                    font-weight: 700;
                    letter-spacing: 0.5px;
                    text-transform: uppercase;
                    margin-bottom: 16px;
                }
                .game-title {
                    font-size: 20px;
                    font-weight: 700;
                    color: #ffffff;
                    margin-bottom: 8px;
                    letter-spacing: -0.3px;
                }
                .status-text {
                    font-size: 13px;
                    color: #8E8E93;
                    margin-bottom: 20px;
                    min-height: 20px;
                }
                .progress-bar-container {
                    width: 100%;
                    height: 6px;
                    background: rgba(255, 255, 255, 0.1);
                    border-radius: 3px;
                    overflow: hidden;
                    position: relative;
                    margin-bottom: 10px;
                }
                .progress-bar-fill {
                    height: 100%;
                    width: 0%;
                    background: linear-gradient(90deg, #00B4D8, #00E5FF);
                    border-radius: 3px;
                    transition: width 0.2s ease;
                }
                .progress-label {
                    font-size: 12px;
                    color: #A0A5B5;
                    font-variant-numeric: tabular-nums;
                }
                #status-error {
                    display: none;
                    background: rgba(255, 69, 58, 0.15);
                    border: 1px solid rgba(255, 69, 58, 0.4);
                    color: #ff6b6b;
                    border-radius: 12px;
                    padding: 12px;
                    font-size: 12px;
                    margin-top: 14px;
                    text-align: left;
                    word-break: break-word;
                }
            </style>
        </head>
        <body>
            <canvas id="canvas" tabindex="0">
                Your browser does not support the canvas tag.
            </canvas>

            <div id="status">
                <div class="loader-card">
                    <div class="engine-badge">
                        <span>⚡</span> Godot 4 Web Runtime
                    </div>
                    <div class="game-title">\(escapedTitle)</div>
                    <div id="status-text" class="status-text">Loading game engine...</div>
                    <div class="progress-bar-container">
                        <div id="progress-fill" class="progress-bar-fill"></div>
                    </div>
                    <div id="progress-label" class="progress-label">Preparing...</div>
                    <div id="status-error"></div>
                </div>
            </div>

            <script src="godot.js"></script>
            <script>
                if (typeof Engine !== 'undefined') {
                    Engine.isSecureContext = function() { return true; };
                }

                const statusEl = document.getElementById('status');
                const statusText = document.getElementById('status-text');
                const progressFill = document.getElementById('progress-fill');
                const progressLabel = document.getElementById('progress-label');
                const statusError = document.getElementById('status-error');

                function showError(err) {
                    console.error('[KINW-Godot-Error]', err);
                    statusText.innerText = "Failed to launch game";
                    statusText.style.color = "#ff6b6b";
                    statusError.style.display = "block";
                    statusError.innerText = (err && err.message) ? err.message : String(err);
                }

                const canvasEl = document.getElementById('canvas');

                const GODOT_CONFIG = {
                    args: ["--rendering-driver", "opengl3"],
                    canvas: canvasEl,
                    canvasResizePolicy: 2,
                    executable: "godot",
                    experimentalVK: false,
                    focusCanvas: true,
                    gdextensionLibs: [],
                    mainPack: "\(pckRelativePath)"
                };

                const engine = new Engine(GODOT_CONFIG);

                statusText.innerText = "Mounting game archive...";

                engine.startGame({
                    onProgress: function(current, total) {
                        if (total > 0) {
                            const percent = Math.min(100, Math.round((current / total) * 100));
                            progressFill.style.width = percent + '%';
                            const currentMB = (current / (1024 * 1024)).toFixed(1);
                            const totalMB = (total / (1024 * 1024)).toFixed(1);
                            progressLabel.innerText = currentMB + ' MB / ' + totalMB + ' MB (' + percent + '%)';
                            if (percent >= 100) {
                                statusText.innerText = "Starting engine...";
                            }
                        } else if (current > 0) {
                            const currentMB = (current / (1024 * 1024)).toFixed(1);
                            progressLabel.innerText = currentMB + ' MB loaded';
                        }
                    }
                }).then(function() {
                    statusText.innerText = "Game started!";
                    setTimeout(function() {
                        statusEl.style.opacity = '0';
                        setTimeout(function() {
                            statusEl.remove();
                        }, 400);
                    }, 300);
                }).catch(function(err) {
                    showError(err);
                });
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
            var target = document.getElementById('canvas') || window;
            var evt = new KeyboardEvent('\(type)', {
                key: '\(key)',
                code: '\(code)',
                bubbles: true,
                cancelable: true
            });
            target.dispatchEvent(evt);
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

    // MARK: - WKURLSchemeHandler Task Tracking
    private func isTaskActive(_ task: WKURLSchemeTask) -> Bool {
        let taskId = ObjectIdentifier(task)
        taskLock.lock()
        defer { taskLock.unlock() }
        return activeTasks.contains(taskId)
    }

    private func markTaskStarted(_ task: WKURLSchemeTask) {
        let taskId = ObjectIdentifier(task)
        taskLock.lock()
        activeTasks.insert(taskId)
        taskLock.unlock()
    }

    private func markTaskFinished(_ task: WKURLSchemeTask) {
        let taskId = ObjectIdentifier(task)
        taskLock.lock()
        activeTasks.remove(taskId)
        taskLock.unlock()
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        markTaskFinished(urlSchemeTask)
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        markTaskStarted(urlSchemeTask)

        // Handle OPTIONS CORS preflight
        if urlSchemeTask.request.httpMethod?.uppercased() == "OPTIONS" {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
                    "Access-Control-Allow-Headers": "*"
                ]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data())
            urlSchemeTask.didFinish()
            markTaskFinished(urlSchemeTask)
            return
        }

        let rawPath = (url.path as NSString).removingPercentEncoding ?? url.path
        let cleanPath = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var matchedURL: URL?

        // 1. Check if it is a Godot runtime file
        let runtimeFiles = ["godot.js", "godot.wasm", "godot.audio.worklet.js", "godot.audio.position.worklet.js"]
        if runtimeFiles.contains(cleanPath) || cleanPath.hasSuffix(".wasm") {
            let lookupName = cleanPath.hasSuffix(".wasm") ? "godot.wasm" : cleanPath
            matchedURL = findGodotRuntimeFile(named: lookupName)
        }

        // 2. Fall back to bottle directory
        if matchedURL == nil {
            let bottleDir = BottleManager.shared.bottleDirectory(for: bottle.id)
            let target = bottleDir.appendingPathComponent(cleanPath)
            let resolved = bottleDir.resolvingSymlinksInPath().appendingPathComponent(cleanPath)

            if FileManager.default.fileExists(atPath: target.path) {
                matchedURL = target
            } else if FileManager.default.fileExists(atPath: resolved.path) {
                matchedURL = resolved
            }
        }

        guard let fileURL = matchedURL else {
            addLog("[Godot-404] Missing resource: \(cleanPath)")
            let notFound = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Access-Control-Allow-Origin": "*"]
            )!
            if isTaskActive(urlSchemeTask) {
                urlSchemeTask.didReceive(notFound)
                urlSchemeTask.didReceive(Data())
                urlSchemeTask.didFinish()
            }
            markTaskFinished(urlSchemeTask)
            return
        }

        let ext = fileURL.pathExtension.lowercased()
        let mime = mimeType(for: ext)

        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? NSNumber {
            fileSize = size.int64Value
        } else {
            fileSize = 0
        }

        // Parse Range request if provided
        var rangeStart: Int64 = 0
        var rangeEnd: Int64 = fileSize - 1
        var isRangeRequest = false

        if let rangeHeader = urlSchemeTask.request.allHTTPHeaderFields?["Range"] ?? urlSchemeTask.request.allHTTPHeaderFields?["range"],
           rangeHeader.hasPrefix("bytes=") {
            let spec = String(rangeHeader.dropFirst(6))
            let parts = spec.components(separatedBy: "-")
            if let startVal = Int64(parts[0]) {
                rangeStart = max(0, startVal)
                if parts.count > 1, let endVal = Int64(parts[1]) {
                    rangeEnd = min(fileSize - 1, endVal)
                }
                if rangeEnd >= rangeStart {
                    isRangeRequest = true
                }
            }
        }

        let statusCode = isRangeRequest ? 206 : 200
        var headers: [String: String] = [
            "Content-Type": mime,
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Accept-Ranges": "bytes"
        ]

        let contentLength: Int64
        if isRangeRequest {
            contentLength = rangeEnd - rangeStart + 1
            headers["Content-Range"] = "bytes \(rangeStart)-\(rangeEnd)/\(fileSize)"
            headers["Content-Length"] = "\(contentLength)"
        } else {
            contentLength = fileSize
            headers["Content-Length"] = "\(fileSize)"
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            urlSchemeTask.didFailWithError(URLError(.badServerResponse))
            markTaskFinished(urlSchemeTask)
            return
        }

        urlSchemeTask.didReceive(response)

        if urlSchemeTask.request.httpMethod?.uppercased() == "HEAD" {
            urlSchemeTask.didFinish()
            markTaskFinished(urlSchemeTask)
            return
        }

        // Small files (< 2 MB): read and send synchronously
        if contentLength <= 2 * 1024 * 1024 {
            if let handle = try? FileHandle(forReadingFrom: fileURL) {
                defer { try? handle.close() }
                if rangeStart > 0 {
                    try? handle.seek(toOffset: UInt64(rangeStart))
                }
                let data = handle.readData(ofLength: Int(contentLength))
                if isTaskActive(urlSchemeTask) {
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                }
            } else {
                if isTaskActive(urlSchemeTask) {
                    urlSchemeTask.didFailWithError(URLError(.cannotOpenFile))
                }
            }
            markTaskFinished(urlSchemeTask)
            return
        }

        // Large files (e.g. 35 MB Wasm, 539 MB PCK): stream in 2 MB chunks on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
                if self.isTaskActive(urlSchemeTask) {
                    urlSchemeTask.didFailWithError(URLError(.cannotOpenFile))
                }
                self.markTaskFinished(urlSchemeTask)
                return
            }
            defer { try? handle.close() }

            if rangeStart > 0 {
                do {
                    try handle.seek(toOffset: UInt64(rangeStart))
                } catch {
                    if self.isTaskActive(urlSchemeTask) {
                        urlSchemeTask.didFailWithError(URLError(.cannotOpenFile))
                    }
                    self.markTaskFinished(urlSchemeTask)
                    return
                }
            }

            let chunkSize = 2 * 1024 * 1024
            var remaining = contentLength
            var hasError = false

            while remaining > 0 && self.isTaskActive(urlSchemeTask) {
                let toRead = Int(min(Int64(chunkSize), remaining))
                let chunk: Data
                do {
                    if #available(iOS 13.4, *) {
                        guard let data = try handle.read(upToCount: toRead), !data.isEmpty else {
                            break
                        }
                        chunk = data
                    } else {
                        let data = handle.readData(ofLength: toRead)
                        if data.isEmpty { break }
                        chunk = data
                    }
                } catch {
                    hasError = true
                    break
                }

                guard self.isTaskActive(urlSchemeTask) else { break }
                urlSchemeTask.didReceive(chunk)
                remaining -= Int64(chunk.count)
            }

            guard self.isTaskActive(urlSchemeTask) else { return }

            if hasError {
                urlSchemeTask.didFailWithError(URLError(.cannotDecodeRawData))
            } else {
                urlSchemeTask.didFinish()
            }
            self.markTaskFinished(urlSchemeTask)
        }
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "wasm":
            return "application/wasm"
        case "js", "mjs":
            return "application/javascript; charset=utf-8"
        case "json":
            return "application/json; charset=utf-8"
        case "html", "htm":
            return "text/html; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "pck", "sparsepck":
            return "application/octet-stream"
        default:
            return "application/octet-stream"
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "KINW Godot Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            self?.dismiss(animated: true)
        }))
        present(alert, animated: true)
    }
}
