//
//  SessionViewDelegate.swift
//  TangemSdk
//
//  Created by Alexander Osokin on 02/10/2019.
//  Copyright © 2019 Tangem AG. All rights reserved.
//

import Foundation
import UIKit
import CoreHaptics

/// Wrapper for a message that can be shown to user after a start of NFC session.
public struct Message: Codable {
    let header: String?
    let body: String?
    
    var alertMessage: String? {
        if header == nil && body == nil {
            return nil
        }
        
        var alertMessage = ""
        
        if let header = header {
            alertMessage = "\(header)\n"
        }
        
        if let body = body {
            alertMessage += body
        }
        
        return alertMessage
    }
    
    public init(header: String?, body: String?) {
        self.header = header
        self.body = body
    }
}


/// Allows interaction with users and shows visual elements.
/// Its default implementation, `DefaultSessionViewDelegate`, is in our SDK.
public protocol SessionViewDelegate: class {
    func showAlertMessage(_ text: String)
    
    /// It is called when security delay is triggered by the card. A user is expected to hold the card until the security delay is over.
    func showSecurityDelay(remainingMilliseconds: Int) //todo: rename santiseconds
    
    func showPercentLoading(_ percent: Int, hint: String?)
    
    /// It is called when a user is expected to enter pin1 code.
    func requestPin(pinType: PinCode.PinType, cardId: String?, completion: @escaping (_ pin: String?) -> Void)
    
    /// It is called when a user is expected to enter pin1 code.
    func requestPinChange(pinType: PinCode.PinType, cardId: String?, completion: @escaping CompletionResult<(currentPin: String, newPin: String)>)
    
    /// It is called when tag was found
    func tagConnected()
    
    /// It is called when tag was lost
    func tagLost()
    
    func hideUI(_ indicatorMode: IndicatorMode?)
    
    func wrongCard(message: String?)
    
    func sessionStarted()
    
    func sessionStopped()
    
    func sessionInitialized()
    
    @available(iOS 13.0, *)
    func showScanUI(session: CardSession, cancelledHandler: @escaping () -> Void)
}


@available(iOS 13.0, *)
final class DefaultSessionViewDelegate: SessionViewDelegate {
    private let reader: CardReader
    private var engine: CHHapticEngine?
    private var engineNeedsStart = true
    private var indicatorController: CircularIndicatorViewController?
    private var scanController: ScanViewController?
    
    private lazy var delayFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.second, .nanosecond]
        return formatter
    }()
    
    private lazy var supportsHaptics: Bool = {
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }()
    
    init(reader: CardReader) {
        self.reader = reader
        createHapticEngine()
    }
    
    func showAlertMessage(_ text: String) {
        reader.alertMessage = text
    }
    
    func showScanUI(session: CardSession, cancelledHandler: @escaping () -> Void) {
        let storyBoard = UIStoryboard(name: "Scan", bundle: .sdkBundle)
        if scanController == nil {
        scanController = storyBoard.instantiateViewController(identifier: "ScanViewController", creator: { coder in
        return ScanViewController(coder: coder, session: session, cancelledHandler: cancelledHandler)
            })
        scanController?.modalPresentationStyle = .fullScreen
        }
        
        if let topmostViewController = UIApplication.shared.topMostViewController {
            topmostViewController.present(scanController!, animated: true) {
            }
        }
    }
    
    func hideUI(_ indicatorMode: IndicatorMode?) {
        guard let indicatorMode = indicatorMode else {
            DispatchQueue.main.async {
                self.indicatorController?.dismiss(animated: true, completion: nil)
                self.scanController?.dismiss(animated: true, completion: nil)
            }
            return
        }
        
        if let indicatorController = self.indicatorController, indicatorMode == indicatorController.mode {
            DispatchQueue.main.async {
                self.indicatorController?.dismiss(animated: true, completion: nil)
            }
        }
    }
    
    func showSecurityDelay(remainingMilliseconds: Int) {
        //if let timeString = self.delayFormatter.string(from: TimeInterval(remainingMilliseconds/100)) {
        playTick()
        showAlertMessage(Localization.nfcAlertDefault)
        // self.showAlertMessage(Localization.secondsLeft(timeString))
        //}
        DispatchQueue.main.async {
            if self.indicatorController == nil {
                let storyBoard = UIStoryboard(name: "CircularIndicator", bundle: .sdkBundle)
                self.indicatorController = storyBoard.instantiateViewController(identifier: "CircularIndicatorViewController")
                self.indicatorController?.modalPresentationStyle = .fullScreen
            }
            self.indicatorController!.mode = .sd
            
            let remainingSeconds = Float(remainingMilliseconds/100)
            if self.indicatorController!.view.window == nil {
                self.indicatorController!.totalValue = remainingSeconds + 1
                if let topmostViewController = UIApplication.shared.topMostViewController {
                    topmostViewController.present(self.indicatorController!, animated: true) {
                        self.indicatorController!.modalPresentationStyle = .fullScreen
                        
                    }
                }
            }
            
            self.indicatorController!.tickSD(remainingValue: remainingSeconds, message: "\(Int(remainingSeconds))", hint: Localization.nfcAlertDefault)
        }
    }
    
    
    func showPercentLoading(_ percent: Int, hint: String?) {
        playTick()
        showAlertMessage(Localization.nfcAlertDefault)
        
        DispatchQueue.main.async {
            if self.indicatorController == nil {
                let storyBoard = UIStoryboard(name: "CircularIndicator", bundle: .sdkBundle)
                self.indicatorController = storyBoard.instantiateViewController(identifier: "CircularIndicatorViewController")
            }
            self.indicatorController!.mode = .percent
            
            if self.indicatorController!.view.window == nil {
                if let topmostViewController = UIApplication.shared.topMostViewController {
                    topmostViewController.present(self.indicatorController!, animated: true) {
                        self.indicatorController!.modalPresentationStyle = .fullScreen
                    }
                }
            }
            
            self.indicatorController!.tickPercent(percentValue: percent, message: String(format: "%@%%", percent.description), hint: hint)
        }
    }
    
    func requestPin(pinType: PinCode.PinType, cardId: String?, completion: @escaping (_ pin: String?) -> Void) {
        switch pinType {
        case .pin1:
            requestPin(.pin1, cardId: cardId, completion: completion)
        case .pin2:
            requestPin(.pin2, cardId: cardId, completion: completion)
        case .pin3:
            requestPin(.pin3, cardId: cardId, completion: completion)
        }
    }
    
    func requestPinChange(pinType: PinCode.PinType, cardId: String?, completion: @escaping CompletionResult<(currentPin: String, newPin: String)>) {
        switch pinType {
        case .pin1:
            requestChangePin(.pin1, cardId: cardId, completion: completion)
        case .pin2:
            requestChangePin(.pin2, cardId: cardId, completion: completion)
        case .pin3:
            requestChangePin(.pin3, cardId: cardId, completion: completion)
        }
    }
    
    func tagConnected() {
        print("tag did connect")
    }
    
    func tagLost() {
        print("tag lost")
    }
    
    func wrongCard(message: String?) {
        playError()
        
        if let message = message {
            let oldMessage = reader.alertMessage
            showAlertMessage(message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showAlertMessage(oldMessage)
            }
        }
    }
    
    func sessionStarted() {
        startHapticsEngine()
    }
    
    func sessionInitialized() {
        playSuccess()
    }
    
    func sessionStopped() {
        hideUI(nil)
        stopHapticsEngine()
    }
    
    private func requestPin(_ state: PinViewControllerState, cardId: String?, completion: @escaping (String?) -> Void) {
        let storyBoard = UIStoryboard(name: "PinStoryboard", bundle: .sdkBundle)
        let vc = storyBoard.instantiateViewController(identifier: "PinViewController", creator: { coder in
            return PinViewController(coder: coder, state: state, cardId: cardId, completionHandler: completion)
        })
        if let topmostViewController = UIApplication.shared.topMostViewController {
            vc.modalPresentationStyle = .fullScreen
            topmostViewController.present(vc, animated: true, completion: nil)
        } else {
            completion(nil)
        }
    }
    
    private func requestChangePin(_ state: PinViewControllerState, cardId: String?, completion: @escaping CompletionResult<(currentPin: String, newPin: String)>) {
        let storyBoard = UIStoryboard(name: "PinStoryboard", bundle: .sdkBundle)
        let vc = storyBoard.instantiateViewController(identifier: "ChangePinViewController", creator: { coder in
            return  ChangePinViewController(coder: coder, state: state, cardId: cardId, completionHandler: completion)
        })
        if let topmostViewController = UIApplication.shared.topMostViewController {
            vc.modalPresentationStyle = .fullScreen
            topmostViewController.present(vc, animated: true, completion: nil)
        } else {
            completion(.failure(.unknownError))
        }
    }
    
    private func playSuccess() {
        if supportsHaptics {
            do {
                
                guard let path = Bundle.sdkBundle.path(forResource: "Success", ofType: "ahap") else {
                    return
                }
                
                try engine?.playPattern(from: URL(fileURLWithPath: path))
            } catch let error {
                print("Error creating a haptic transient pattern: \(error)")
            }
        }
    }
    
    private func playError() {
        if supportsHaptics {
            do {
                guard let path = Bundle.sdkBundle.path(forResource: "Error", ofType: "ahap") else {
                    return
                }
                
                try engine?.playPattern(from: URL(fileURLWithPath: path))
            } catch let error {
                print("Error creating a haptic transient pattern: \(error)")
            }
        } else {
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.error)
        }
    }
    
    private func playTick() {
        if supportsHaptics {
            do {
                // Create an event (static) parameter to represent the haptic's intensity.
                let intensityParameter = CHHapticEventParameter(parameterID: .hapticIntensity,
                                                                value: 0.75)
                
                // Create an event (static) parameter to represent the haptic's sharpness.
                let sharpnessParameter = CHHapticEventParameter(parameterID: .hapticSharpness,
                                                                value: 0.5)
                
                // Create an event to represent the transient haptic pattern.
                let event = CHHapticEvent(eventType: .hapticTransient,
                                          parameters: [intensityParameter, sharpnessParameter],
                                          relativeTime: 0)
                
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                
                // Create a player to play the haptic pattern.
                let player = try engine?.makePlayer(with: pattern)
                try player?.start(atTime: CHHapticTimeImmediate) // Play now.
            } catch let error {
                print("Error creating a haptic transient pattern: \(error)")
            }
        } else {
            let generator = UIImpactFeedbackGenerator(style: UIImpactFeedbackGenerator.FeedbackStyle.light)
            generator.impactOccurred()
        }
    }
    
    private func stopHapticsEngine() {
        guard supportsHaptics else {
            return
        }
        
        engine?.stop(completionHandler: {[weak self] error in
            if let error = error {
                print("Haptic Engine Shutdown Error: \(error)")
                return
            }
            self?.engineNeedsStart = true
        })
    }
    
    private func startHapticsEngine() {
        guard supportsHaptics && engineNeedsStart else {
            return
        }
        
        engine?.start(completionHandler: {[weak self] error in
            if let error = error {
                print("Haptic Engine Start Error: \(error)")
                return
            }
            self?.engineNeedsStart = false
        })
    }
    
    private func createHapticEngine() {
        guard supportsHaptics else {
            return
        }
        
        do {
            engine = try CHHapticEngine()
            engine!.playsHapticsOnly = true
            engine!.stoppedHandler = {[weak self] reason in
                print("CHHapticEngine stop handler: The engine stopped for reason: \(reason.rawValue)")
                self?.engineNeedsStart = true
            }
            engine!.resetHandler = {[weak self] in
                print("Reset Handler: Restarting the engine.")
                do {
                    // Try restarting the engine.
                    try self?.engine?.start()
                    
                    // Indicate that the next time the app requires a haptic, the app doesn't need to call engine.start().
                    self?.engineNeedsStart = false
                    
                } catch {
                    print("Failed to start the engine")
                }
            }
        } catch {
            print("CHHapticEngine error: \(error)")
        }
    }
}
