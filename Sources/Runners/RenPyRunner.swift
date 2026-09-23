import Foundation
import UIKit
import WebKit
import AVFoundation

public final class RenPyRunner: NSObject, GameRunnerProtocol {
    public let bottle: Bottle
    private var viewController: RenPyViewController?

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init()
    }

    public func makeViewController() -> UIViewController {
        let vc = RenPyViewController(bottle: bottle)
        self.viewController = vc
        return vc
    }

    public func pause() {
        viewController?.pause()
    }

    public func resume() {
        viewController?.resume()
    }

    public func stop() {
        viewController?.stop()
    }
}

public final class RenPyViewController: UIViewController, WKScriptMessageHandler, WKURLSchemeHandler {
    private let bottle: Bottle
    private var webView: WKWebView!
    private let customScheme = "kinw-renpy"

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
        return bottle.config.orientation == "portrait" ? .portrait : .landscape
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[KINW-RenPy] Audio session error: \(error)")
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.setURLSchemeHandler(self, forURLScheme: customScheme)

        let userContentController = WKUserContentController()
        let scriptSource = """
        document.addEventListener('contextmenu', e => e.preventDefault());
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
        
        // Find Ren'Py game folder or entry
        let candidates = ["assets/x-game", "assets/game", "base/game", "assets", ""]
        var gameFolder = ""
        for c in candidates {
            let path = c.isEmpty ? bottleDir : bottleDir.appendingPathComponent(c)
            if FileManager.default.fileExists(atPath: path.path) {
                gameFolder = c
                break
            }
        }

        // Generate Ren'Py Web loader page
        let html = generateRenPyLoaderHTML(gameFolder: gameFolder)
        webView.loadHTMLString(html, baseURL: URL(string: "\(customScheme)://localhost/"))
    }

    private func generateRenPyLoaderHTML(gameFolder: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <title>\(bottle.title)</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { background: #08090C; color: #fff; font-family: -apple-system, system-ui, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
                #canvas { width: 100vw; height: 100vh; object-fit: contain; background: #000; }
                .loader-box { text-align: center; max-width: 400px; padding: 24px; }
                .spinner { width: 50px; height: 50px; border: 4px solid rgba(0,255,255,0.2); border-top-color: #00e5ff; border-radius: 50%; animation: spin 1s infinite linear; margin: 0 auto 16px; }
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
                <p>Mounting Ren'Py Visual Novel scripts and media assets from package...</p>
                <div class="badge">Ren'Py Engine Active</div>
            </div>
            <canvas id="canvas" style="display:none;"></canvas>
            <script>
                // Bridge to initialize Ren'Py Web runtime
                console.log("[KINW] Initializing Ren'Py for: \(bottle.packageName)");
                setTimeout(() => {
                    // Try loading existing web export if embedded
                    fetch("/assets/www/index.html").then(res => {
                        if (res.ok) {
                            window.location.href = "/assets/www/index.html";
                        }
                    }).catch(() => {});
                }, 1000);
            </script>
        </body>
        </html>
        """
    }

    public func pause() {}
    public func resume() {}
    public func stop() {
        webView?.stopLoading()
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

        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
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
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
