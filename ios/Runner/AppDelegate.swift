import Flutter
import UIKit
import StoreKit
import FirebaseCore
import FirebaseAnalytics
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var channels: [FlutterMethodChannel] = []
  private var pdfResult: FlutterResult?
  private var pdfFolder: URL?
  private var preparedReviewAt: Date?
  private var reviewAttempted = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let documents = FlutterMethodChannel(name: "com.warrantycave.app/document_saver", binaryMessenger: messenger)
    documents.setMethodCallHandler { [weak self] call, result in
      guard call.method == "savePdf" else { result(FlutterMethodNotImplemented); return }
      self?.savePdf(call.arguments, result: result)
    }
    let reviews = FlutterMethodChannel(name: "com.warrantycave.app/play_review", binaryMessenger: messenger)
    reviews.setMethodCallHandler { [weak self] call, result in
      self?.handleReview(call, result: result)
    }
    let measurement = FlutterMethodChannel(name: "com.warrantycave.app/usage_analytics", binaryMessenger: messenger)
    measurement.setMethodCallHandler { [weak self] call, result in
      self?.handleMeasurement(call, result: result)
    }
    channels = [documents, reviews, measurement]
  }

  private var activeScene: UIWindowScene? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }

  private var presenter: UIViewController? {
    var controller = activeScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let next = controller?.presentedViewController { controller = next }
    return controller
  }

  private func savePdf(_ arguments: Any?, result: @escaping FlutterResult) {
    guard pdfResult == nil else {
      result(FlutterError(code: "busy", message: "A PDF is already being saved.", details: nil)); return
    }
    guard let args = arguments as? [String: Any], let bytes = args["bytes"] as? FlutterStandardTypedData,
          let proposedName = args["fileName"] as? String,
          !bytes.data.isEmpty, proposedName.lowercased().hasSuffix(".pdf"), let presenter = presenter else {
      result(FlutterError(code: "invalid_pdf", message: "Could not open the PDF export.", details: nil)); return
    }
    do {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      pdfFolder = folder
      let name = (proposedName as NSString).lastPathComponent
      let url = folder.appendingPathComponent(name)
      try bytes.data.write(to: url, options: .atomic)
      let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
      picker.delegate = self
      pdfResult = result
      presenter.present(picker, animated: true)
    } catch {
      cleanPdf()
      result(FlutterError(code: "save_failed", message: "The PDF could not be saved.", details: nil))
    }
  }

  private func cleanPdf() {
    if let folder = pdfFolder { try? FileManager.default.removeItem(at: folder) }
    pdfFolder = nil
  }
  private func finishPdf(_ saved: Bool) {
    let result = pdfResult
    pdfResult = nil
    cleanPdf()
    result?(saved)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finishPdf(false) }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishPdf(!urls.isEmpty)
  }

  private func handleReview(_ call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let count = args["count"] as? Int ?? 0
    let defaults = UserDefaults.standard
    switch call.method {
    case "observe":
      if defaults.object(forKey: "review.existing") == nil {
        defaults.set(count > 0 || args["existingAccount"] as? Bool == true, forKey: "review.existing")
      }
      result(nil)
    case "prepare":
      let last = defaults.double(forKey: "review.lastAttempt")
      let now = Date().timeIntervalSince1970
      let eligible = count > 0 && (defaults.bool(forKey: "review.existing") || count >= 2)
      guard !reviewAttempted, eligible, activeScene != nil,
            last == 0 || now - last >= 30 * 24 * 60 * 60 else { result(false); return }
      reviewAttempted = true
      defaults.set(now, forKey: "review.lastAttempt")
      preparedReviewAt = Date()
      result(true)
    case "launch":
      guard let prepared = preparedReviewAt, Date().timeIntervalSince(prepared) < 10,
            let scene = activeScene else { result(false); return }
      preparedReviewAt = nil
      SKStoreReviewController.requestReview(in: scene)
      result(true) // An attempt, never evidence that Apple showed UI or a rating was submitted.
    default: result(FlutterMethodNotImplemented)
    }
  }

  // Installation-local, excluded from backup. A restored phone asks again.
  private func consentFile() throws -> URL {
    var folder = try FileManager.default.url(for: .applicationSupportDirectory,
      in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("installation-consent", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    return folder.appendingPathComponent("usage-v1")
  }
  private func measurementChoice() throws -> Bool? {
    guard let data = try? Data(contentsOf: consentFile()) else { return nil }
    return String(data: data, encoding: .utf8) == "true"
  }
  private func applyMeasurement(_ enabled: Bool) {
    Analytics.setConsent([
      .analyticsStorage: enabled ? .granted : .denied,
      .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied,
    ])
    Analytics.setAnalyticsCollectionEnabled(enabled)
    if !enabled { Analytics.resetAnalyticsData() }
  }
  private func handleMeasurement(_ call: FlutterMethodCall, result: FlutterResult) {
    guard FirebaseApp.app() != nil else { result(FlutterMethodNotImplemented); return }
    do {
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "choice":
        let choice = try measurementChoice()
        applyMeasurement(choice == true)
        result(choice)
      case "setConsent":
        guard let enabled = args["enabled"] as? Bool else {
          result(FlutterError(code: "invalid_choice", message: "Missing consent choice.", details: nil)); return
        }
        if !enabled { applyMeasurement(false) }
        try Data((enabled ? "true" : "false").utf8).write(to: consentFile(), options: .atomic)
        applyMeasurement(enabled)
        result(nil)
      case "event":
        if try measurementChoice() == true, let name = args["name"] as? String {
          if name == "warranty_created" { Analytics.logEvent(name, parameters: nil) }
          else if name == "sign_up", let method = args["method"] as? String,
                  ["password", "google", "apple"].contains(method) {
            Analytics.logEvent(name, parameters: ["method": method])
          }
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "measurement_unavailable", message: "Please try again.", details: nil))
    }
  }
}
