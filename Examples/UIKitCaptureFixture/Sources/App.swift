import UIKit
import ScreenerKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = MaterialsController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

final class MaterialsController: UIViewController {
    private var captureTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        // High-frequency content makes missing backdrop blur unambiguous.
        for index in 0..<30 {
            let stripe = UIView(frame: CGRect(x: 0, y: 100 + index * 22, width: 1000, height: 11))
            stripe.backgroundColor = index.isMultiple(of: 2) ? .systemBlue : .systemOrange
            view.addSubview(stripe)
        }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        addMaterial(blur, title: "UIBlurEffect.systemMaterial", y: 180)
        if #available(iOS 26, *) {
            let glass = UIVisualEffectView(effect: UIGlassEffect())
            addMaterial(glass, title: "UIGlassEffect", y: 340)
        }
        let button = UIButton(type: .system)
        button.configuration = .borderedProminent()
        button.setTitle("Save", for: .normal)
        button.accessibilityIdentifier = "fixture.save"
        button.menu = UIMenu(children: ["Files", "Photos", "Share"].map { title in
            UIAction(title: title) { _ in }
        })
        button.showsMenuAsPrimaryAction = true
        button.frame = CGRect(x: 260, y: 540, width: 110, height: 48)
        view.addSubview(button)
    }

    private func addMaterial(_ material: UIVisualEffectView, title: String, y: CGFloat) {
        material.frame = CGRect(x: 24, y: y, width: 340, height: 120)
        material.layer.cornerRadius = 24
        material.clipsToBounds = true
        let label = UILabel(frame: material.bounds.insetBy(dx: 16, dy: 16))
        label.text = title
        label.font = .systemFont(ofSize: 19, weight: .semibold)
        label.textAlignment = .center
        material.contentView.addSubview(label)
        view.addSubview(material)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard captureTask == nil, let window = view.window else { return }
        captureTask = Task { @MainActor in
            let root = URL.documentsDirectory.appending(path: "Captures", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let recorder = Screener()
                _ = try await recorder.startSession(
                    name: "uikit-materials", appBundleID: "dev.screener.UIKitFixture", tracesDirectory: root
                )
                // Bounded fixture recording; gives time to inspect and open the menu.
                for index in 0..<60 {
                    try await Task.sleep(for: .seconds(2))
                    let image = try UIKitCaptureSource(view: window).capture()
                    try await recorder.recordFrame(image, reason: "sample.\(index)")
                    try UIImage(cgImage: image.cgImage).pngData()?.write(to: root.appending(path: "latest.png"), options: .atomic)
                    let info = "width=\(image.cgImage.width) height=\(image.cgImage.height) scale=\(image.scale) window.window=\(String(describing: window.window)) traits=\(window.traitCollection.displayScale) sample=\(index)"
                    try info.write(to: root.appending(path: "latest.txt"), atomically: true, encoding: .utf8)
                }
                try await recorder.stopSession()
            } catch {
                try? String(describing: error).write(to: root.appending(path: "error.txt"), atomically: true, encoding: .utf8)
            }
        }
    }
}
