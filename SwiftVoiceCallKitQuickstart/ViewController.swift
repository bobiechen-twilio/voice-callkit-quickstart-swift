//
//  ViewController.swift
//  Twilio Voice with CallKit Quickstart - Swift
//
//  Copyright © 2016 Twilio, Inc. All rights reserved.
//

import UIKit
import AVFoundation
import PushKit
import CallKit
import TwilioVoiceClient

let baseURLString = <#URL TO YOUR ACCESS TOKEN SERVER#>
let accessTokenEndpoint = "/accessToken"

class ViewController: UIViewController, PKPushRegistryDelegate, TVONotificationDelegate, TVOIncomingCallDelegate, TVOOutgoingCallDelegate, CXProviderDelegate {

    @IBOutlet weak var placeCallButton: UIButton!
    @IBOutlet weak var iconView: UIImageView!

    var deviceTokenString:String?

    var voipRegistry:PKPushRegistry

    var isSpinning: Bool
    var incomingAlertController: UIAlertController?

    var incomingCall:TVOIncomingCall?
    var outgoingCall:TVOOutgoingCall?

    let callKitProvider:CXProvider
    let callKitCallController:CXCallController

    required init?(coder aDecoder: NSCoder) {
        isSpinning = false
        voipRegistry = PKPushRegistry.init(queue: DispatchQueue.main)

        let configuration = CXProviderConfiguration(localizedName: "CallKit Quickstart")
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        if let callKitIcon = UIImage(named: "iconMask80") {
            configuration.iconTemplateImageData = UIImagePNGRepresentation(callKitIcon)
        }

        callKitProvider = CXProvider(configuration: configuration)
        callKitCallController = CXCallController()

        super.init(coder: aDecoder)

        callKitProvider.setDelegate(self, queue: nil)

        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = Set([PKPushType.voIP])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        toggleUIState(isEnabled: true)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func fetchAccessToken() -> String? {
        guard let accessTokenURL = URL(string: baseURLString + accessTokenEndpoint) else {
            return nil
        }

        return try? String.init(contentsOf: accessTokenURL, encoding: .utf8)
    }
    
    func toggleUIState(isEnabled: Bool) {
        placeCallButton.isEnabled = isEnabled
    }

    @IBAction func placeCall(_ sender: UIButton) {
        let uuid = UUID()
        let handle = "Voice Bot"

        performStartCallAction(uuid: uuid, handle: handle)
    }


    // MARK: PKPushRegistryDelegate
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, forType type: PKPushType) {
        NSLog("pushRegistry:didUpdatePushCredentials:forType:")
        
        if (type != .voIP) {
            return
        }

        guard let accessToken = fetchAccessToken() else {
            return
        }
        
        let deviceToken = (credentials.token as NSData).description

        VoiceClient.sharedInstance().register(withAccessToken: accessToken, deviceToken: deviceToken) { (error) in
            if (error != nil) {
                NSLog("An error occurred while registering: \(error?.localizedDescription)")
            }
            else {
                NSLog("Successfully registered for VoIP push notifications.")
            }
        }

        self.deviceTokenString = deviceToken
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenForType type: PKPushType) {
        NSLog("pushRegistry:didInvalidatePushTokenForType:")
        
        if (type != .voIP) {
            return
        }
        
        guard let deviceToken = deviceTokenString, let accessToken = fetchAccessToken() else {
            return
        }
        
        VoiceClient.sharedInstance().unregister(withAccessToken: accessToken, deviceToken: deviceToken) { (error) in
            if (error != nil) {
                NSLog("An error occurred while unregistering: \(error?.localizedDescription)")
            }
            else {
                NSLog("Successfully unregistered from VoIP push notifications.")
            }
        }
        
        self.deviceTokenString = nil
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, forType type: PKPushType) {
        NSLog("pushRegistry:didReceiveIncomingPushWithPayload:forType:")

        if (type == PKPushType.voIP) {
            VoiceClient.sharedInstance().handleNotification(payload.dictionaryPayload, delegate: self)
        }
    }


    // MARK: TVONotificaitonDelegate
    func incomingCallReceived(_ incomingCall: TVOIncomingCall) {
        NSLog("incomingCallReceived:")
        
        self.incomingCall = incomingCall
        self.incomingCall?.delegate = self

        reportIncomingCall(from: "Voice Bot", uuid: incomingCall.uuid)
    }
    
    func incomingCallCancelled(_ incomingCall: TVOIncomingCall?) {
        NSLog("incomingCallCancelled:")
        
        if let incomingCall = incomingCall {
            performEndCallAction(uuid: incomingCall.uuid)
        }

        self.incomingCall = nil
    }
    
    func notificationError(_ error: Error) {
        NSLog("notificationError: \(error.localizedDescription)")
    }
    
    
    // MARK: TVOIncomingCallDelegate
    func incomingCallDidConnect(_ incomingCall: TVOIncomingCall) {
        NSLog("incomingCallDidConnect:")
        
        self.incomingCall = incomingCall
        toggleUIState(isEnabled: false)
        stopSpin()
        routeAudioToSpeaker()
    }
    
    func incomingCallDidDisconnect(_ incomingCall: TVOIncomingCall) {
        NSLog("incomingCallDidDisconnect:")

        performEndCallAction(uuid: incomingCall.uuid)

        self.incomingCall = nil
        toggleUIState(isEnabled: true)
    }
    
    func incomingCall(_ incomingCall: TVOIncomingCall, didFailWithError error: Error) {
        NSLog("incomingCall:didFailWithError: \(error.localizedDescription)")

        performEndCallAction(uuid: incomingCall.uuid)

        self.incomingCall = nil
        toggleUIState(isEnabled: true)
        stopSpin()
    }
    
    
    // MARK: TVOOutgoingCallDelegate
    func outgoingCallDidConnect(_ outgoingCall: TVOOutgoingCall) {
        NSLog("outgoingCallDidConnect:")
        
        toggleUIState(isEnabled: false)
        stopSpin()
        routeAudioToSpeaker()
    }
    
    func outgoingCallDidDisconnect(_ outgoingCall: TVOOutgoingCall) {
        NSLog("outgoingCallDidDisconnect:")

        performEndCallAction(uuid: outgoingCall.uuid)
        
        self.outgoingCall = nil
        toggleUIState(isEnabled: true)
    }
    
    func outgoingCall(_ outgoingCall: TVOOutgoingCall, didFailWithError error: Error) {
        NSLog("outgoingCall:didFailWithError: \(error.localizedDescription)")

        performEndCallAction(uuid: outgoingCall.uuid)

        self.outgoingCall = nil
        toggleUIState(isEnabled: true)
        stopSpin()
    }
    
    
    // MARK: AVAudioSession
    func routeAudioToSpeaker() {
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, with: .defaultToSpeaker)
        } catch {
            NSLog(error.localizedDescription)
        }
    }


    // MARK: Icon spinning
    func startSpin() {
        if (isSpinning != true) {
            isSpinning = true
            spin(options: UIViewAnimationOptions.curveEaseIn)
        }
    }
    
    func stopSpin() {
        isSpinning = false
    }
    
    func spin(options: UIViewAnimationOptions) {
        UIView.animate(withDuration: 0.5,
                       delay: 0.0,
                       options: options,
                       animations: { [weak iconView] in
            if let iconView = iconView {
                iconView.transform = iconView.transform.rotated(by: CGFloat(M_PI/2))
            }
        }) { [weak self] (finished: Bool) in
            guard let strongSelf = self else {
                return
            }

            if (finished) {
                if (strongSelf.isSpinning) {
                    strongSelf.spin(options: UIViewAnimationOptions.curveLinear)
                } else if (options != UIViewAnimationOptions.curveEaseOut) {
                    strongSelf.spin(options: UIViewAnimationOptions.curveEaseOut)
                }
            }
        }
    }


    // MARK: CXProviderDelegate
    func providerDidReset(_ provider: CXProvider) {
        NSLog("providerDidReset:")
    }

    func providerDidBegin(_ provider: CXProvider) {
        NSLog("providerDidBegin")
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        NSLog("provider:didActivateAudioSession:")

        VoiceClient.sharedInstance().startAudioDevice()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        NSLog("provider:didDeactivateAudioSession:")
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        NSLog("provider:timedOutPerformingAction:")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        NSLog("provider:performStartCallAction:")

        guard let accessToken = fetchAccessToken() else {
            action.fail()
            return
        }

        VoiceClient.sharedInstance().configureAudioSession()

        outgoingCall = VoiceClient.sharedInstance().call(accessToken, params: [:], delegate: self)

        guard let outgoingCall = outgoingCall else {
            NSLog("Failed to start outgoing call")
            action.fail()
            return
        }

        outgoingCall.uuid = action.callUUID

        toggleUIState(isEnabled: false)
        startSpin()

        action.fulfill(withDateStarted: Date())
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        NSLog("provider:performAnswerCallAction:")

        // RCP: Workaround from https://forums.developer.apple.com/message/169511 suggests configuring audio in the
        //      completion block of the `reportNewIncomingCallWithUUID:update:completion:` method instead of in
        //      `provider:performAnswerCallAction:` per the WWDC examples.
        // VoiceClient.sharedInstance().configureAudioSession()

        incomingCall?.accept(with: self)

        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        NSLog("provider:performEndCallAction:")

        VoiceClient.sharedInstance().stopAudioDevice()

        if let incomingCall = incomingCall {
            if incomingCall.state == .pending {
                incomingCall.reject()
            } else {
                incomingCall.disconnect()
            }
        } else if let outgoingCall = outgoingCall {
            outgoingCall.disconnect()
        }

        action.fulfill()
    }

    // MARK: Call Kit Actions
    func performStartCallAction(uuid: UUID, handle: String) {
        let callHandle = CXHandle(type: .generic, value: handle)
        let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        let transaction = CXTransaction(action: startCallAction)

        callKitCallController.request(transaction)  { error in
            if let error = error {
                NSLog("StartCallAction transaction request failed: \(error.localizedDescription)")
                return
            }

            NSLog("StartCallAction transaction request successful")

            let callUpdate = CXCallUpdate()
            callUpdate.remoteHandle = callHandle
            callUpdate.supportsDTMF = true
            callUpdate.supportsHolding = false
            callUpdate.supportsGrouping = false
            callUpdate.supportsUngrouping = false
            callUpdate.hasVideo = false

            self.callKitProvider.reportCall(with: uuid, updated: callUpdate)
        }
    }

    func reportIncomingCall(from: String, uuid: UUID) {
        let callHandle = CXHandle(type: .generic, value: from)

        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = callHandle
        callUpdate.supportsDTMF = true
        callUpdate.supportsHolding = false
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false

        callKitProvider.reportNewIncomingCall(with: uuid, update: callUpdate) { error in
            if let error = error {
                NSLog("Failed to report incoming call successfully: \(error.localizedDescription).")
                return
            }

            NSLog("Incoming call successfully reported.")

            // RCP: Workaround per https://forums.developer.apple.com/message/169511
            VoiceClient.sharedInstance().configureAudioSession()
        }
    }

    func performEndCallAction(uuid: UUID) {

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callKitCallController.request(transaction) { error in
            if let error = error {
                NSLog("EndCallAction transaction request failed: \(error.localizedDescription).")
                return
            }

            NSLog("EndCallAction transaction request successful")
        }
    }
}
