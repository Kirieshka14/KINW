import Foundation
import UIKit
import SwiftUI

public protocol GameRunnerProtocol: AnyObject {
    var bottle: Bottle { get }
    func makeViewController() -> UIViewController
    func pause()
    func resume()
    func stop()
    func reload()
    func sendKey(code: String, key: String, down: Bool)
    var consoleLogs: [String] { get }
}

public extension GameRunnerProtocol {
    func reload() {}
    func sendKey(code: String, key: String, down: Bool) {}
    var consoleLogs: [String] { [] }
}

public final class RunnerRegistry {
    public static let shared = RunnerRegistry()

    private init() {}

    public func createRunner(for bottle: Bottle) -> GameRunnerProtocol {
        switch bottle.engine {
        case .webNovel, .rpgMaker:
            return WebNovelRunner(bottle: bottle)
        case .renpy:
            return RenPyRunner(bottle: bottle)
        case .godot:
            return GodotRunner(bottle: bottle)
        case .gameMaker:
            return GameMakerRunner(bottle: bottle)
        case .love2d:
            return Love2DRunner(bottle: bottle)
        case .unity, .genericNative, .unknown:
            return GenericNativeRunner(bottle: bottle)
        }
    }
}
