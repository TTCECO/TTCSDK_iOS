//
//  TTCBannerDelegate.swift
//  TTCSDK
//
//  Created by chenchao on 2018/12/29.
//  Copyright © 2018 tataufo. All rights reserved.
//

import UIKit

@objc public protocol TTCBannerDelegate: NSObjectProtocol {
 
    //MARK: - Ad Request Lifecycle Notifications
    
    /// Tells the delegate that an ad request successfully received an ad. The delegate may want to add
    /// the banner view to the view hierarchy if it hasn't been added yet.
    func adViewDidReceiveAd(_ banner: TTCBanner)
    
    /// Tells the delegate that an ad request failed. The failure is normally due to network
    /// connectivity or ad availablility (i.e., no fill).
    func adViewDidFailToReceiveAd(banner: TTCBanner, error: Error)
    
    //MARK: - Click-Time Lifecycle Notifications
    
    /// Tells the delegate that a full screen view will be presented in response to the user clicking on
    /// an ad. The delegate may want to pause animations and time sensitive interactions.
    func adViewWillPresentScreen(banner: TTCBanner)
    
    /// Tells the delegate that the full screen view will be dismissed.
    func adViewWillDismissScreen(banner: TTCBanner)
    
    /// Tells the delegate that the full screen view has been dismissed. The delegate should restart
    /// anything paused while handling adViewWillPresentScreen:.
    func adViewDidDismissScreen(banner: TTCBanner)
    
    /// Tells the delegate that the user click will open another app, backgrounding the current
    /// application. The standard UIApplicationDelegate methods, like applicationDidEnterBackground:,
    /// are called immediately before this method is called.
    func adViewWillLeaveApplication(banner: TTCBanner)

}

