//
//  ActionManager.swift
//  ACN_SDK
//
//  Created by Zhang Yufei on 2018/7/9  下午12:15.
//  Copyright © 2018年 tataufo. All rights reserved.
//

import Foundation
import RealmSwift
import BigInt
import Alamofire
import JSONRPCKit
import ACN_SDK_NET

class ACNActionInfo: Object {
    
    /// actionType > 100
    @objc dynamic var actionType: Int32 = 0
    /// Transaction number
    @objc dynamic var actionHash: String = String()
    /// nonce
    @objc dynamic var nonce: Int64 = -1
    /// from user id
    @objc dynamic var fromUserID: String = String()
    /// Ancillary information
    @objc dynamic var extra: String = String()
    /// Have you uploaded the behavior to the server? 0 = no  1 = yes
    @objc dynamic var isUpload: Int = 0
    /// Have you checked? 0 = no  1 = yes, Waiting for a block  2 = yes, Block failure  3 = yes, Block success
    @objc dynamic var isCheck: Int = 0
    /// time
    @objc dynamic var timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    /// Database primary key
    override class func primaryKey() -> String? { return "timestamp" }
    
    func hashData() -> Data {
        var hashString = "actionType=\(self.actionType)&extra=\(self.extra)&fromUserId=\(self.fromUserID)&timestamp=\(self.timestamp)".md5()
        hashString = "ufo:1:oplog:md5:\(hashString):\(ACNManager.shared.appId.description)"
        return hashString.data(using: .utf8) ?? Data()
    }
    
    func transitionProto() -> ACNNETActionInfo {
        
        let pbActionInfo = ACNNETActionInfo()
        pbActionInfo.actionType = self.actionType
        pbActionInfo.fromUserID = self.fromUserID
        pbActionInfo.actionHash = self.actionHash
        pbActionInfo.timestamp = self.timestamp
        pbActionInfo.extra = self.extra
        
        return pbActionInfo
    }
    
    /// Ignored attributes are not stored in the database
    override static func ignoredProperties() -> [String] {
        return ["description"]
    }
    
    override var description: String {
        get {
            return "actionType=\(self.actionType)\nextra=\(self.extra)\nfromUserId=\(self.fromUserID)\ntimestamp=\(self.timestamp)\nactionHash=\(self.actionHash)"
        }
    }
}

class ACNActionManager {
    
    let realmQueue = DispatchQueue(label: "realmQueue")
    let cfg: Realm.Configuration
    var realm: Realm {
        get {
            return try! Realm(configuration: cfg)
        }
    }
    var timer: Timer?
    
    /// gas limit
    var gasLimit: BigInt = BigInt(210000)
    /// gas price
    var gasPrice: BigInt = BigInt("500000000000") // 500 gwei
    
    /// nonce
    var nonce: BigInt = BigInt(-1)
    
    /// chainID
    var chainID: BigInt?
    
    /// Maximum upload behavior
    let uploadCountLimit = 1
    /// is uploading behavior?
    var isUploadAction: Bool = false
    /// is transaction?
    var isTransaction: Bool = false
    /// is checking transaction?, Ensure this is changed in main queue
    var isChecking: Bool = false
    /// error count for 'requestPrivateKeyAndAddress'
    var transactionErrorCount: Int {
        didSet {
            if transactionErrorCount > 5 {
                transactionErrorCount = 0
                ACNManager.shared.requestPrivateKeyAndAddress { (_, _) -> Void in }
            }
        }
    }
    
    /// creat queue of checking transaction
    let checkQueue: DispatchQueue = DispatchQueue(label: "com.ttc.eco.checkQueue")
    
    var timeInterval: TimeInterval = 15
    
    static let shared = ACNActionManager()
    
    init() {
        
        var realmPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        realmPath += "/action.realm"
        var bid = Bundle.main.bundleIdentifier ?? ""
        bid = bid.md5()
        var ACN = "ttc-" + bid
        ACN = ACN.md5()
        var key = ACN + bid
        let i = key.index(key.startIndex, offsetBy: 64)
        key = String(key.prefix(upTo: i))
        let data = key.data(using: .utf8) ?? Data()
        cfg = Realm.Configuration.init(fileURL: URL(string: realmPath), encryptionKey: data, readOnly: false, schemaVersion: 2, migrationBlock: { migration, oldSchemaVersion in
            if oldSchemaVersion < 2{
                
            }
        }, deleteRealmIfMigrationNeeded: false, shouldCompactOnLaunch: nil, objectTypes: nil)
        
        transactionErrorCount = 0
    }
    
    func runScheduledTimer() {
        self.timer = Timer.scheduledTimer(timeInterval: timeInterval, target: self, selector: #selector(checkAndupload), userInfo: nil, repeats: true)
        self.timer?.fire()
    }
    
    
    func setDefaultManager() {
        
        self.gasLimit = BigInt(210000)
        self.gasPrice = BigInt("500000000000") // 500 gwei
        self.nonce = BigInt(-1)
        
        self.transactionErrorCount = 0
        
        self.timer?.invalidate()
        self.timer = nil
        self.timeInterval = 30
        runScheduledTimer()
        
    }
    
    /// Behavior write to database
    func insertAction(actionInfo: ACNActionInfo) {
        realmQueue.async {
            let realm = self.realm
            try? realm.write {
                realm.add(actionInfo, update: true)
            }
            //            ACNPrint(actionInfo)
            self.actionWriteBlockChain(actionInfo: actionInfo)
        }
    }
    
    /// remove behavior from database
    func deleteAction() {
        
        realmQueue.async {
            
            guard let userinfo = ACNManager.shared.userInfo else { return }
            
            let realm = self.realm
            let actionInfos = realm.objects(ACNActionInfo.self).filter("fromUserID = '\(userinfo.userId)' AND actionHash != '' AND isUpload = 1 AND isCheck = 3")
            try? realm.write {
                realm.delete(actionInfos)
            }
        }
    }
    
    /// query and upload
    func queriesActionAndUpload() {
        realmQueue.async {
            if self.isUploadAction { return }
            guard let userinfo = ACNManager.shared.userInfo else { return }
            
            let results = self.realm.objects(ACNActionInfo.self).filter("fromUserID = '\(userinfo.userId)' AND actionHash != '' AND isUpload = 0")
            if results.count >= self.uploadCountLimit {
                self.isUploadAction = true
                
                var ecoActions: [ACNNETActionInfo] = []
                for action in results {
                    ecoActions.append(action.transitionProto())
                }
                
                ACNPrint("start upload behavior....")
                self.uploadAction(ecoActions: ecoActions)
            }
        }
    }
    
    /// Update upload status to uploaded
    func updateAction(actionInfos: [ACNNETActionInfo]) {
        realmQueue.async {
            let realm = self.realm
            for action in actionInfos {
                guard let act = realm.objects(ACNActionInfo.self).filter("timestamp = \(action.timestamp)").first else { return }
                try? realm.write {
                    act.isUpload = 1
                }
            }
        }
    }
    
    /// query and transaction
    func queriesActionAndTransaction() {
        realmQueue.async {
            if self.isTransaction { return }
            guard let userinfo = ACNManager.shared.userInfo else { return }
            
            guard let actionInfo = self.realm.objects(ACNActionInfo.self).filter("fromUserID = '\(userinfo.userId)' AND actionHash = ''").first else { return }
            self.actionWriteBlockChain(actionInfo: actionInfo)
        }
    }
    
    /// upload block chain
    func actionWriteBlockChain(actionInfo: ACNActionInfo) {
        
        if self.isTransaction {
            ACNPrint("Trading. . .")
            return
        }
        
        /// get chainid
        guard let chainId = self.chainID else {
            getChainID()
            return
        }
        
        /// fetch nonce
        if self.nonce == BigInt(-1) {
            getTransactionCount()
            return
        }
        
        /// start transaction
        self.isTransaction = true
        
        let nonce: BigInt
        let data: Data
        let timestamp: Int64
        let gasLimit: BigInt
        let gasPrice: BigInt
        
        nonce = self.nonce
        data = actionInfo.hashData()
        timestamp = actionInfo.timestamp
        gasLimit = self.gasLimit
        gasPrice = self.gasPrice
        
        if actionInfo.fromUserID != ACNManager.shared.userInfo?.userId {
            self.isTransaction = false
            return
        }
        
        guard let userinfo = ACNManager.shared.userInfo else {
            self.isTransaction = false
            return
        }
        
        let trans = Transaction(
            from: ACNManager.shared.actionAddress?.to0x ?? "",
            to: userinfo.address?.to0x ?? "",
            gasLimit: gasLimit,
            gasPrice: gasPrice,
            value: EtherNumberFormatter.full.number(from: String(Int(0)), units: EthereumUnit.wei) ?? BigInt(0),
            nonce: nonce,
            data: data,
            chainID: chainId)
        
        ACNRPCManager.sendTransaction(transaction: trans) { (result) in
            switch result {
            case .success(let hex):
                ACNPrint("Transaction success -> hash: \(hex)")
                self.realmQueue.async {
                    
                    /// update database
                    let realm = self.realm
                    let action = realm.objects(ACNActionInfo.self).filter("timestamp = \(timestamp)").first
                    try? realm.write {
                        action?.actionHash = hex
                        action?.nonce = Int64(nonce.description) ?? 0
                        action?.isUpload = 0 // 有可能被上传服务器后设为1了
                    }
                }
                
                //                ACNRPCManager.getTransaction(hash: hex) { (result) in
                //                    switch result {
                //                    case .success(let transaction):
                //                        ACNPrint("Transaction hash: \(hex), info: \(transaction)")
                //                    case .failure(_): break
                //                    }
                //                }
                
                self.nonce += 1
                ACNPrint("current nonce: \(self.nonce)")
                self.isTransaction = false
                /// Inquire whether there is no transaction, initiate a transaction
                self.queriesActionAndTransaction()
                self.queriesActionAndUpload()
            case .failure(let error):
                
                ACNPrint("Transaction failed: \(error)")
                /// end transation
                self.isTransaction = false
                self.transactionErrorCount += 1
                
                self.doError(error: error)
            }
        }
    }
    
    /// Upload user behavior to the server
    func uploadAction(ecoActions: [ACNNETActionInfo]) {
        
        ACNPrint("behavior count :\(ecoActions.count)")
        
        if ecoActions.first?.fromUserID != ACNManager.shared.userInfo?.userId {
            self.isUploadAction = false
            return
        }
        
        ACNNetworkManager.uploadAction(actionInfoList: ecoActions, result: { (success, error) in
            
            if success {
                ACNPrint("Upload behavior succeeded")
                self.updateAction(actionInfos: ecoActions)
                self.queriesActionAndUpload()
            } else {
                ACNPrint("Upload behavior failed: \(String(describing: error?.errorDescription))")
            }
            
            self.isUploadAction = false
        })
    }
    
    // query transaction count
    func getTransactionCount() {
        
        guard let address = ACNManager.shared.actionAddress, !address.isEmpty else {
            return
        }
        
        let userid = ACNManager.shared.userInfo?.userId
        
        ACNRPCManager.getTransactionPendingCount(address: address, completion: { (result) in
            switch result {
            case .success(let nonce):
                ACNPrint("fetch nonce success, nonce: \(nonce.description)")
                
                //                guard let userinfo = ACNManager.shared.userInfo else { return }
                
                //                if let action = self.realm.objects(ACNActionInfo.self).filter("fromUserID = '\(userinfo.userId)' AND nonce > -1").sorted(byKeyPath: "nonce").last {
                //                    ACNPrint("Database nonce: \(action.nonce)")
                //                    self.nonce = BigInt(action.nonce) + 1
                //                }
                
                self.nonce = nonce
                
                if userid != ACNManager.shared.userInfo?.userId {
                    self.nonce = BigInt(-1)
                }
                
                ACNPrint("Used nonce: \(self.nonce.description)")
                
                self.queriesActionAndTransaction()
                self.deleteAction()
                
            case .failure(let error):
                ACNPrint("Get nonce failed: \(error)")
            }
        })
    }
    
    // version
    func getChainID() {
        ACNRPCManager.fetchVersion { (result) in
            switch result {
            case .success(let version):
                ACNPrint("Get chainid success: \(version)")
                self.chainID = BigInt(version)
            case .failure(let error):
                ACNPrint("Get chainid failed: \(error)")
            }
        }
    }
    
    func afterCheck(afterTime: Int = 2) {
        
        let time = DispatchTime.now() + DispatchTimeInterval.seconds(afterTime)
        
        self.checkQueue.asyncAfter(deadline: time) {
            ACNPrint("start checking time >>>>>>>>> : \(Date().timeIntervalSince1970.description)")
            self.checkTransaction()
        }
    }
    
    // check transaction and upload action
    @objc func checkAndupload() {
        afterCheck()
        getTransactionCount()
    }
    
    // check transaction
    func checkTransaction() {
        
        if !ACNManager.shared.SDKEnabled { return }
        if !ACNManager.shared.isRegister { return }
        guard let userinfo = ACNManager.shared.userInfo else { return }
        if isChecking { return }
        
        let userid = ACNManager.shared.userInfo?.userId
        
        if let actionInfo = self.realm.objects(ACNActionInfo.self).filter("fromUserID = '\(userinfo.userId)' AND actionHash != '' AND isCheck < 3").sorted(byKeyPath: "nonce").first {
            
            if userid != userinfo.userId { return }
            isChecking = true
            
            let timestamp = actionInfo.timestamp
            let hash = actionInfo.actionHash
            
            ACNRPCManager.getTransaction(hash: hash) { (result) in
                switch result {
                case .success(let transaction):
                    //                    ACNPrint("Transaction hash: \(hash), info: \(transaction)")
                    
                    if userid != userinfo.userId { self.isChecking = false; return }
                    
                    let blockNumberStr = transaction["blockNumber"] as? String ?? ""
                    let blockNumber = BigInt(blockNumberStr.drop0x, radix: 16) ?? BigInt(0)
                    let nonceString = transaction["nonce"] as? String ?? ""
                    let nonce = BigInt(nonceString.drop0x, radix: 16) ?? BigInt(0)
                    
                    if blockNumber > BigInt(0) {
                        
                        /// update database
                        self.realmQueue.async {
                            let tmpRealm = self.realm
                            if let info = tmpRealm.objects(ACNActionInfo.self).filter("timestamp = \(timestamp)").first {
                                try? tmpRealm.write {
                                    info.isCheck = 3 // Check successful
                                }
                            }
                            
                            DispatchQueue.main.async {
                                self.isChecking = false
                                
                                /// Continue to check
                                self.afterCheck()
                            }
                        }
                        
                        ACNPrint("Transaction hash: \(hash), blockNumber = \(blockNumber), nonce : \(nonce.description)")
                        
                    } else {
                        
                        /// wait block
                        self.realmQueue.async {
                            let tmpRealm = self.realm
                            if let info = tmpRealm.objects(ACNActionInfo.self).filter("timestamp = \(timestamp)").first {
                                try? tmpRealm.write {
                                    info.isCheck = 1 // Not yet successful
                                }
                            }
                            
                            DispatchQueue.main.async {
                                self.isChecking = false
                                /// Continue to check
                                self.afterCheck(afterTime: 5)
                            }
                        }
                        
                        ACNPrint("Transaction hash: \(hash), no blockNumber, nonce : \(nonce.description)")
                    }
                    
                case .failure(let error):
                    
                    ACNPrint("Get transaction failed, hash:\(hash), failed: \(error)")
                    
                    guard let RPCError: ACNRPCError = error as? ACNRPCError else { self.isChecking = false; return }
                    
                    switch RPCError {
                    case .RPCSuccessError(let code, _):
                        if code == RPCErrorType.null.rawValue {
                            /// 一般情况是nonce过大，为了追求实时性，重新上传
                            /// The general situation is that the nonce is too large, in order to pursue real-time, re-upload
                            ACNPrint("is null ------- \(hash)")
                            self.realmQueue.async {
                                let tmpRealm = self.realm
                                if let info = tmpRealm.objects(ACNActionInfo.self).filter("timestamp = \(timestamp)").first {
                                    try? tmpRealm.write {
                                        info.actionHash = ""  // Hash restore
                                        info.isCheck = 2      // Block failure
                                        info.nonce = 0
                                        info.isUpload = 0     // may be 1
                                    }
                                }
                                
                                DispatchQueue.main.async {
                                    self.isChecking = false
                                    /// Continue to check
                                    self.afterCheck()
                                    /// re-upload
                                    self.getTransactionCount()
                                }
                            }
                        } else {
                            self.isChecking = false
                        }
                    default:
                        self.isChecking = false
                    }
                }
            }
        }
    }
    
    
    /// MARK: - json rpc error
    func dealwithRPCError(error: ACNRPCError) {
        switch error {
        case .RPCSuccessError(_, let message):
            // nonce, Have problems re-query "replacement transaction underpriced"？？？
            if message == "nonce too low" {
                self.getTransactionCount()
            }
        default:
            break
        }
    }
    
    /// return SessionTaskError and jsonrpc
    func doError(error: Error) {
        guard let RPCError: ACNRPCError = error as? ACNRPCError else {
            return
        }
        
        self.dealwithRPCError(error: RPCError)
    }
    
}