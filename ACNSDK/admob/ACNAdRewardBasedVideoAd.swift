//
//  ACNAdRewardBasedVideoAd.swift
//  ACNSDK
//
//  Created by chenchao on 2019/1/3.
//  Copyright © 2019 tataufo. All rights reserved.
//

import GoogleMobileAds

@objc public class ACNAdRewardBasedVideoAd: NSObject {

    /// Returns the shared ACNAdRewardBasedVideoAd instance.
    @objc public static let sharedInstance: ACNAdRewardBasedVideoAd = ACNAdRewardBasedVideoAd()
    
    var rewardBasedVideo: GADRewardBasedVideoAd = GADRewardBasedVideoAd.sharedInstance()
    var adUnitID: String?
    
    override init() {
        super.init()
        rewardBasedVideo.delegate = self
    }
    
    /// Delegate for receiving video notifications.
    @objc public weak var delegate: ACNAdRewardBasedVideoAdDelegate?
    
    /// Indicates if the receiver is ready to be presented full screen.
    @objc public var isReady: Bool {
        get {
            return rewardBasedVideo.isReady
        }
    }
    
    /// A unique identifier used to identify the user when making server-to-server reward callbacks.
    /// This value is used at both request time and during ad display. New values must only be set
    /// before ad requests.
    @objc public var userIdentifier: String? {
        didSet {
            rewardBasedVideo.userIdentifier = userIdentifier
        }
    }
    
    /// Optional custom reward string to include in the server-to-server callback.
    @objc public var customRewardString: String? {
        didSet {
            rewardBasedVideo.customRewardString = customRewardString
        }
    }
    
}

extension ACNAdRewardBasedVideoAd {
    
    /// Initiates the request to fetch the reward based video ad. The |request| object supplies ad
    /// targeting information and must not be nil. The adUnitID is the ad unit id used for fetching an
    /// ad and must not be nil.
    @objc public func loadRequest(request: ACNAdRequest, adUnitID: String) {
        self.adUnitID = adUnitID
        rewardBasedVideo.load(request.gadRequest, withAdUnitID: adUnitID)
    }
}

extension ACNAdRewardBasedVideoAd {
    
    /// Presents the reward based video ad with the provided view controller.
    @objc public func present(rootViewController: UIViewController) {
        rewardBasedVideo.present(fromRootViewController: rootViewController)
    }
}

extension ACNAdRewardBasedVideoAd: GADRewardBasedVideoAdDelegate {
    
    public func rewardBasedVideoAd(_ rewardBasedVideoAd: GADRewardBasedVideoAd, didRewardUserWith reward: GADAdReward) {
        ACNAdupload.shared.upload(adUnitID: adUnitID ?? "", handleType: 3)
        self.delegate?.rewardBasedVideoAd(rewardBasedVideoAd: self, didRewardUserWithReward: ACNAdReward(reward: reward))
    }
    
    public func rewardBasedVideoAd(_ rewardBasedVideoAd: GADRewardBasedVideoAd, didFailToLoadWithError error: Error) {
        self.delegate?.rewardBasedVideoAd?(rewardBasedVideoAd: self, didFailToLoadWithError: error)
    }
    
    public func rewardBasedVideoAdDidReceive(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        self.delegate?.rewardBasedVideoAdDidReceiveAd?(rewardBasedVideoAd: self)
    }
    
    public func rewardBasedVideoAdDidOpen(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        ACNAdupload.shared.upload(adUnitID: adUnitID ?? "", handleType: 1)
        self.delegate?.rewardBasedVideoAdDidOpen?(rewardBasedVideoAd: self)
    }
    
    public func rewardBasedVideoAdDidStartPlaying(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        self.delegate?.rewardBasedVideoAdDidStartPlaying?(rewardBasedVideoAd: self)
    }
    
    public func rewardBasedVideoAdDidCompletePlaying(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        self.delegate?.rewardBasedVideoAdDidCompletePlaying?(rewardBasedVideoAd: self)
    }
    
    public func rewardBasedVideoAdDidClose(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        self.delegate?.rewardBasedVideoAdDidClose?(rewardBasedVideoAd: self)
    }
    
    public func rewardBasedVideoAdWillLeaveApplication(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        self.delegate?.rewardBasedVideoAdWillLeaveApplication?(rewardBasedVideoAd: self)
    }
}
