import Foundation
import UIKit
import WebKit
import AVFoundation

public final class WebNovelRunner: NSObject, GameRunnerProtocol {
    public let bottle: Bottle
    private var webView: WKWebView?
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
        webView?.evaluateJavaScript("if (window.onPause) window.onPause();", completionHandler: nil)
    }

    public func resume() {
        webView?.evaluateJavaScript("if (window.onResume) window.onResume();", completionHandler: nil)
    }

    public func stop() {
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
    }
}

public final class WebNovelViewController: UIViewController, WKScriptMessageHandler, WKURLSchemeHandler {
    private let bottle: Bottle
    private var webView: WKWebView!
    private let customScheme = "kinw-app"

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupAudioSession()
        setupWebView()
        loadGame()
    }

    override public var prefersStatusBarHidden: Bool {
        return true
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if bottle.config.orientation == "portrait" {
            return .portrait
        } else {
            return .landscape
        }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[KINW] Failed to configure AVAudioSession: \(error)")
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Hook custom scheme to serve bottle files
        config.setURLSchemeHandler(self, forURLScheme: customScheme)

        // User script to sync saves and disable context menu/selection
        let userContentController = WKUserContentController()
        let scriptSource = """
        document.addEventListener('contextmenu', e => e.preventDefault());
        document.addEventListener('selectstart', e => e.preventDefault());

        // Sync localStorage into KINW saves
        window.kinwSaveStorage = function() {
            try {
                let data = JSON.stringify(window.localStorage);
                window.webkit.messageHandlers.saveSync.postMessage(data);
            } catch(e) {}
        };
        setInterval(window.kinwSaveStorage, 5000);
        """
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)
        userContentController.add(self, name: "saveSync")

        config.userContentController = userContentController

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        view.addSubview(webView)
    }

    private func loadGame() {
        let bottleDir = BottleManager.shared.bottleDirectory(for: bottle.id)
        let entryRelative = bottle.entryPoint.isEmpty ? "assets/www/index.html" : bottle.entryPoint
        let fullPath = bottleDir.appendingPathComponent(entryRelative).path

        if FileManager.default.fileExists(atPath: fullPath) {
            // Restore saves if exists
            restoreSaves()

            // Load via custom scheme
            if let url = URL(string: "\(customScheme)://localhost/\(entryRelative)") {
                webView.load(URLRequest(url: url))
            }
        } else {
            showError("Entry file not found: \(entryRelative)")
        }
    }

    private func restoreSaves() {
        let savesFile = BottleManager.shared.savesDirectory(for: bottle.id).appendingPathComponent("localstorage.json")
        guard let data = try? Data(contentsOf: savesFile),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        let escaped = jsonString.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "'", with: "\\'")
        let restoreScript = """
        try {
            let saved = JSON.parse('\(escaped)');
            for (let k in saved) {
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
        }
    }

    // MARK: - WKURLSchemeHandler

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let relativePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bottleDir = BottleManager.shared.bottleDirectory(for: bottle.id)
        let fileURL = bottleDir.appendingPathComponent(relativePath)

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mimeType = mimeType(for: fileURL.pathExtension)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
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
