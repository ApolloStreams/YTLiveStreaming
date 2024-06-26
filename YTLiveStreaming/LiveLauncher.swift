//
//  LiveLauncher.swift
//  YTLiveStreaming
//
//  Created by Serhii Krotkykh on 11/13/16.
//

import Foundation

@objc public protocol LiveStreamTransitioning: AnyObject {
   @objc optional func didTransitionToLiveStatus()
   @objc optional func didTransitionTo(broadcastStatus: String?, streamStatus: String?, healthStatus: String?)
   @objc optional func returnAnError(error: String?)
}

class LiveLauncher: NSObject {
   let askStatusStreamFrequencyInSeconds = 5.0
   fileprivate var liveBroadcast: LiveBroadcastStreamModel?
   fileprivate var liveStream: LiveStreamModel?
   fileprivate var _isLiveStreaming: Bool = false

   weak var delegate: LiveStreamTransitioning?
   var youTubeWorker: YTLiveStreaming?

   fileprivate var timer: Timer?

    var isLiveStreaming: Bool {
        get {
            return _isLiveStreaming
        }
        set {
            if newValue != _isLiveStreaming {
                _isLiveStreaming = newValue
                if _isLiveStreaming {
                    self.delegate?.didTransitionToLiveStatus?()
                }
            }
        }
    }

   private override init() {

   }

   class var sharedInstance: LiveLauncher {
      struct Singleton {
         static let instance = LiveLauncher()
      }
      return Singleton.instance
   }

   func launchBroadcast(broadcast: LiveBroadcastStreamModel?, stream: LiveStreamModel?) {
      liveBroadcast = broadcast
      liveStream = stream
      isLiveStreaming = false
      startTimerForChekingStatusStream()
   }

   func stopBroadcast() {
      timer?.invalidate()
      timer = nil
   }

   fileprivate func startTimerForChekingStatusStream() {
      timer?.invalidate()
      timer = Timer(timeInterval: askStatusStreamFrequencyInSeconds,
                    target: self,
                    selector: #selector(liveVideoStatusRequestTickTimer),
                    userInfo: nil,
                    repeats: true)
    RunLoop.main.add(timer!, forMode: RunLoop.Mode.common)
      liveVideoStatusRequestTickTimer()
   }

   @objc func liveVideoStatusRequestTickTimer() {
      statusRequest { liveStatus, error in
         if liveStatus {
            self.isLiveStreaming = true
         } else {
            self.transitionToLive { success, err in
               if success {
                  self.isLiveStreaming = true
               } else if let err = err {
                 self.delegate?.returnAnError?(error: err.message())
               }
            }
         }
        if let error = error {
          self.delegate?.returnAnError?(error: error.message())
        }
      }
   }

   fileprivate func statusRequest(completion: @escaping (Bool, YTError?) -> Void) {
      guard !self.isLiveStreaming else {
         return
      }
      guard let liveBroadcast = self.liveBroadcast else {
         return
      }
      guard let liveStream = self.liveStream else {
         return
      }
      self.youTubeWorker?.getStatusBroadcast(liveBroadcast,
                                             stream: liveStream,
                                             completion: { (broadcastStatus, streamStatus, healthStatus, error) in
         if let broadcastStatus = broadcastStatus, let streamStatus = streamStatus, let healthStatus = healthStatus {
            if broadcastStatus == "live" || broadcastStatus == "liveStarting" {
               completion(true, nil)
            } else {
               self.delegate?.didTransitionTo?(
                broadcastStatus: broadcastStatus,
                streamStatus: streamStatus,
                healthStatus: healthStatus
               )
               completion(false, nil)
            }
         } else if let error = error {
           completion(false, error)
         }
      })
   }

   fileprivate func transitionToLive(completion: @escaping (Bool, YTError?) -> Void) {
      guard let liveBroadcast = self.liveBroadcast else {
         return
      }
      self.youTubeWorker?.transitionBroadcastToLiveState(liveBroadcast: liveBroadcast, liveState: completion)
   }
}
