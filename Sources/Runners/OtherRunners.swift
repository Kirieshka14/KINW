import Foundation
import UIKit
import SwiftUI

// MARK: - Godot Runner
public final class GodotRunner: NSObject, GameRunnerProtocol {
    public let bottle: Bottle

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init()
    }

    public func makeViewController() -> UIViewController {
        return RunnerPlaceholderViewController(
            title: "Godot Engine",
            engineName: "Godot",
            bottle: bottle,
            instructions: "Godot PCK archive detected at: \(bottle.entryPoint).\n\nMounts into Godot iOS runner using Metal rendering."
        )
    }

    public func pause() {}
    public func resume() {}
    public func stop() {}
}

// MARK: - GameMaker Runner
public final class GameMakerRunner: NSObject, GameRunnerProtocol {
    public let bottle: Bottle

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init()
    }

    public func makeViewController() -> UIViewController {
        return RunnerPlaceholderViewController(
            title: "GameMaker Studio",
            engineName: "GameMaker",
            bottle: bottle,
            instructions: "GameMaker byte-data (game.droid) detected at: \(bottle.entryPoint).\n\nLoads directly via GameMaker Yoyo runner."
        )
    }

    public func pause() {}
    public func resume() {}
    public func stop() {}
}

// MARK: - LÖVE2D Runner
public final class Love2DRunner: NSObject, GameRunnerProtocol {
    public let bottle: Bottle

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init()
    }

    public func makeViewController() -> UIViewController {
        return RunnerPlaceholderViewController(
            title: "LÖVE2D Game",
            engineName: "LÖVE2D",
            bottle: bottle,
            instructions: "LÖVE archive (game.love) detected at: \(bottle.entryPoint).\n\nLoads via embedded Love for iOS runner."
        )
    }

    public func pause() {}
    public func resume() {}
    public func stop() {}
}

// MARK: - Generic Native C++ Runner (FalsoJNI + ANGLE)
public final class GenericNativeRunner: NSObject, GameRunnerProtocol {
    public let bottle: Bottle

    public init(bottle: Bottle) {
        self.bottle = bottle
        super.init()
    }

    public func makeViewController() -> UIViewController {
        return RunnerPlaceholderViewController(
            title: "Native C++ Engine",
            engineName: "Native C++ / ANGLE",
            bottle: bottle,
            instructions: "Native .so library detected at: \(bottle.entryPoint).\n\nUses FalsoJNI and Google ANGLE to translate graphics to Apple Metal."
        )
    }

    public func pause() {}
    public func resume() {}
    public func stop() {}
}

// MARK: - Placeholder View Controller with Sleek UI
public final class RunnerPlaceholderViewController: UIViewController {
    private let titleText: String
    private let engineName: String
    private let bottle: Bottle
    private let instructions: String

    public init(title: String, engineName: String, bottle: Bottle, instructions: String) {
        self.titleText = title
        self.engineName = engineName
        self.bottle = bottle
        self.instructions = instructions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconLabel = UILabel()
        iconLabel.text = "🎮"
        iconLabel.font = .systemFont(ofSize: 64)

        let titleLabel = UILabel()
        titleLabel.text = bottle.title
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        let badgeLabel = UILabel()
        badgeLabel.text = "  \(engineName) Engine  "
        badgeLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        badgeLabel.textColor = .cyan
        badgeLabel.backgroundColor = UIColor.cyan.withAlphaComponent(0.15)
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.layer.masksToBounds = true

        let descLabel = UILabel()
        descLabel.text = instructions
        descLabel.font = .systemFont(ofSize: 15, weight: .regular)
        descLabel.textColor = .lightGray
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0

        var btnConfig = UIButton.Configuration.filled()
        btnConfig.title = "Back to KINW Library"
        btnConfig.baseBackgroundColor = .systemBlue
        btnConfig.baseForegroundColor = .white
        btnConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        btnConfig.cornerStyle = .medium
        let closeBtn = UIButton(configuration: btnConfig)
        closeBtn.addTarget(self, action: #selector(handleClose), for: .touchUpInside)

        stack.addArrangedSubview(iconLabel)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(badgeLabel)
        stack.addArrangedSubview(descLabel)
        stack.addArrangedSubview(closeBtn)

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30)
        ])
    }

    @objc private func handleClose() {
        dismiss(animated: true)
    }
}
