import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenGuardPlugin") {
      ScreenGuardPlugin.register(with: registrar)
    }
  }
}

/// アプリ切り替え時にスナップショットが撮られる直前で画面をぼかす。
///
/// iOS にはスクリーンショットを禁止する公式 API がないため、
/// このアプリで行えるのは「タスク切り替え画面での遮蔽」までである。
/// シーン対応アプリでは UIApplicationDelegate の active/resign が呼ばれないので、
/// シーン側とアプリ側の両方の通知を購読している。
final class ScreenGuardPlugin: NSObject, FlutterPlugin {

  private var obscureOnSwitch = true
  private var overlay: UIView?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "jp.privacyasset/screen_guard",
      binaryMessenger: registrar.messenger()
    )
    let instance = ScreenGuardPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.startObserving()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setObscureOnSwitch":
      obscureOnSwitch = (call.arguments as? Bool) ?? true
      if !obscureOnSwitch { hideOverlay() }
      result(true)
    case "setSecure":
      // iOS ではスクリーンショットそのものを禁止できない。
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startObserving() {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(obscure),
      name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(reveal),
      name: UIScene.didActivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(obscure),
      name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(reveal),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  private var hostWindow: UIWindow? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first(where: { $0.isKeyWindow }) ?? windows.first
  }

  @objc private func obscure() {
    guard obscureOnSwitch, overlay == nil, let window = hostWindow else { return }

    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    blur.frame = window.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(blur)
    overlay = blur
  }

  @objc private func reveal() {
    overlay?.removeFromSuperview()
    overlay = nil
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
