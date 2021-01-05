//
//  WebDAVStorage.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/11/22.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import os.log
import CoreData

class ViewControllerWebDAV: UIViewController, UITextFieldDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    var textURI: UITextField!
    var textUser: UITextField!
    var textPass: UITextField!
    var stackView: UIStackView!

    var onCancel: (()->Void)!
    var onFinish: ((String, String, String)->Void)!
    var done: Bool = false
    
    let activityIndicatorView = UIActivityIndicatorView()
    var uri = ""
    var user = ""
    var pass = ""
    var testState = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "WebDAV"
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }

        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        let stackView1 = UIStackView()
        stackView1.axis = .horizontal
        stackView1.alignment = .center
        stackView1.spacing = 20
        stackView.addArrangedSubview(stackView1)
        
        let label1 = UILabel()
        label1.text = "URL"
        stackView1.addArrangedSubview(label1)
        
        textURI = UITextField()
        textURI.borderStyle = .roundedRect
        textURI.keyboardType = .URL
        textURI.textContentType = .URL
        textURI.enablesReturnKeyAutomatically = true
        textURI.delegate = self
        textURI.clearButtonMode = .whileEditing
        textURI.returnKeyType = .done
        textURI.placeholder = "https://localhost/webdav/"
        stackView1.addArrangedSubview(textURI)
        let widthConstraint = textURI.widthAnchor.constraint(equalToConstant: 300)
        widthConstraint.priority = .defaultHigh
        widthConstraint.isActive = true
        
        let stackView2 = UIStackView()
        stackView2.axis = .horizontal
        stackView2.alignment = .center
        stackView2.spacing = 20
        stackView.addArrangedSubview(stackView2)
        
        let label2 = UILabel()
        label2.text = "Username"
        stackView2.addArrangedSubview(label2)
        
        textUser = UITextField()
        textUser.borderStyle = .roundedRect
        textUser.delegate = self
        textUser.clearButtonMode = .whileEditing
        textUser.textContentType = .username
        textUser.placeholder = "(option)"
        stackView2.addArrangedSubview(textUser)
        let widthConstraint2 = textUser.widthAnchor.constraint(equalToConstant: 200)
        widthConstraint2.priority = .defaultHigh
        widthConstraint2.isActive = true
        
        let stackView3 = UIStackView()
        stackView3.axis = .horizontal
        stackView3.alignment = .center
        stackView3.spacing = 20
        stackView.addArrangedSubview(stackView3)
        
        let label3 = UILabel()
        label3.text = "Password"
        stackView3.addArrangedSubview(label3)
        
        textPass = UITextField()
        textPass.borderStyle = .roundedRect
        textPass.delegate = self
        textPass.clearButtonMode = .whileEditing
        textPass.isSecureTextEntry = true
        textPass.textContentType = .password
        textPass.placeholder = "(option)"
        stackView3.addArrangedSubview(textPass)
        let widthConstraint3 = textPass.widthAnchor.constraint(equalToConstant: 200)
        widthConstraint3.priority = .defaultHigh
        widthConstraint3.isActive = true
        

        let stackView4 = UIStackView()
        stackView4.axis = .horizontal
        stackView4.alignment = .center
        stackView4.spacing = 20
        stackView.addArrangedSubview(stackView4)
        
        let button1 = UIButton(type: .system)
        button1.setTitle("Done", for: .normal)
        button1.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView4.addArrangedSubview(button1)
        
        let button2 = UIButton(type: .system)
        button2.setTitle("Cancel", for: .normal)
        button2.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView4.addArrangedSubview(button2)
        
        activityIndicatorView.center = view.center
        if #available(iOS 13.0, *) {
            activityIndicatorView.style = .large
        } else {
            // Fallback on earlier versions
            activityIndicatorView.style = .whiteLarge
        }
        activityIndicatorView.hidesWhenStopped = true
        view.addSubview(activityIndicatorView)
    }
    
    @objc func buttonEvent(_ sender: UIButton) {
        if sender.currentTitle == "Done" {
            textURI.resignFirstResponder()
            if textURI.text == "" {
                return
            }
            if activityIndicatorView.isAnimating {
                return
            }
            activityIndicatorView.startAnimating()
            uri = textURI.text ?? ""
            user = textUser.text ?? ""
            pass = textPass.text ?? ""
            checkServer()
        }
        else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    override func willMove(toParent parent: UIViewController?) {
        if parent == nil && !done {
            onCancel()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        if textField == textURI {
            if activityIndicatorView.isAnimating {
                return true
            }
            activityIndicatorView.startAnimating()
            uri = textURI.text ?? ""
            user = textUser.text ?? ""
            pass = textPass.text ?? ""
            checkServer()
        }
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if textURI.isFirstResponder {
            textURI.resignFirstResponder()
        }
        if textUser.isFirstResponder {
            textUser.resignFirstResponder()
        }
        if textPass.isFirstResponder {
            textPass.resignFirstResponder()
        }
    }
    
    func checkServer() {
        guard let url = URL(string: uri) else {
            activityIndicatorView.stopAnimating()
            return
        }
        testState = 0
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        let task = dataSession.dataTask(with: request)
        
        task.resume()
    }
    
    lazy var dataSession: URLSession = {
      let configuration = URLSessionConfiguration.default
      
      return URLSession(configuration: configuration,
                        delegate: self,
                        delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {

        guard let response = response as? HTTPURLResponse else {
            DispatchQueue.main.async {
                self.activityIndicatorView.stopAnimating()
            }
            return
        }
        guard response.statusCode == 200 else {
            print(response)
            DispatchQueue.main.async {
                self.activityIndicatorView.stopAnimating()
            }
            return
        }
        if testState == 0 {
            guard let allow = response.allHeaderFields["Allow"] as? String ?? response.allHeaderFields["allow"] as? String else {
                print(response)
                DispatchQueue.main.async {
                    self.activityIndicatorView.stopAnimating()
                }
                return
            }
            guard allow.lowercased().contains("propfind") else {
                print(allow)
                DispatchQueue.main.async {
                    self.activityIndicatorView.stopAnimating()
                }
                return
            }
            guard let dav = response.allHeaderFields["Dav"] as? String ?? response.allHeaderFields["dav"] as? String ??
                response.allHeaderFields["DAV"] as? String else {
                print(response)
                DispatchQueue.main.async {
                    self.activityIndicatorView.stopAnimating()
                }
                return
            }
            guard dav.contains("1") else {
                print(dav)
                DispatchQueue.main.async {
                    self.activityIndicatorView.stopAnimating()
                }
                return
            }
            
            guard let url = URL(string: uri) else {
                DispatchQueue.main.async {
                    self.activityIndicatorView.stopAnimating()
                }
                return
            }
            
            if let server = response.allHeaderFields["Server"] as? String {
                /* Only check HEAD for non-Caddy webdav servers */
                if server.contains("Caddy") {
                    done = true
                    onFinish(uri, user, pass)
                }
            }
            var request: URLRequest = URLRequest(url: url)
            request.httpMethod = "HEAD"
            let task = dataSession.dataTask(with: request)
            testState = 1
            task.resume()

        }
        else if testState == 1 {
            done = true
            onFinish(uri, user, pass)
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print(error)
            DispatchQueue.main.async {
                self.activityIndicatorView.stopAnimating()
            }
            return
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let authMethod = challenge.protectionSpace.authenticationMethod
        guard authMethod == NSURLAuthenticationMethodHTTPBasic || authMethod == NSURLAuthenticationMethodHTTPDigest else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        guard challenge.previousFailureCount < 3 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let credential = URLCredential(user: user, password: pass, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
}

public class WebDAVStorage: NetworkStorage, URLSessionTaskDelegate, URLSessionDataDelegate {
    
    public override func getStorageType() -> CloudStorages {
        return .WebDAV
    }

    var cache_accessUsername = ""
    var accessUsername: String {
        if let name = storageName {
            if let user = getKeyChain(key: "\(name)_accessUsername") {
                cache_accessUsername = user
            }
            return cache_accessUsername
        }
        else {
            return ""
        }
    }

    var cache_accessPassword = ""
    var accessPassword: String {
        if let name = storageName {
            if let pass = getKeyChain(key: "\(name)_accessPassword") {
                cache_accessPassword = pass
            }
            return cache_accessPassword
        }
        else {
            return ""
        }
    }

    var cache_aaccessURI = ""
    var accessURI: String {
        if let name = storageName {
            if let uri = getKeyChain(key: "\(name)_accessURI") {
                cache_aaccessURI = uri
            }
            return cache_aaccessURI
        }
        else {
            return ""
        }
    }
    
    var acceptRange: Bool?
    let checkSemaphore = DispatchSemaphore(value: 1)
    let uploadSemaphore = DispatchSemaphore(value: 5)

    lazy var dataSession: URLSession = {
      let configuration = URLSessionConfiguration.default
      
      return URLSession(configuration: configuration,
                        delegate: self,
                        delegateQueue: nil)
    }()
    
    var dataTasks: [Int: (Data?, Error?)->Void] = [:]
    var recvData: [Int: Data] = [:]
    var headerHandler: [Int: (URLResponse)->URLSession.ResponseDisposition] = [:]
    
    let wholeQueue = DispatchQueue(label: "WholeReading")
    var wholeReading: [URL] = []
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let authMethod = challenge.protectionSpace.authenticationMethod
        guard authMethod == NSURLAuthenticationMethodHTTPBasic || authMethod == NSURLAuthenticationMethodHTTPDigest else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        guard challenge.previousFailureCount < 3 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let credential = URLCredential(user: accessUsername, password: accessPassword, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        let taskid = (session.configuration.identifier ?? "") + ".\(task.taskIdentifier)"
        if let taskdata = taskQueue.sync(execute: {
            self.task_upload.removeValue(forKey: taskid)
        }) {
            // upload is done
            guard let onFinish = taskQueue.sync(execute: {
                self.onFinsh_upload.removeValue(forKey: taskid)
            }) else {
                print("onFinish not found")
                return
            }
            if let target = taskdata["target"] as? URL {
                try? FileManager.default.removeItem(at: target)
            }
            do {
                guard let url = taskdata["url"] as? String else {
                    print(task.response ?? "")
                    throw RetryError.Failed
                }
                if let error = error {
                    print(error)
                    throw RetryError.Failed
                }
                guard let httpResponse = task.response as? HTTPURLResponse else {
                    print(task.response ?? "")
                    throw RetryError.Failed
                }
                guard httpResponse.statusCode == 201 else {
                    print(httpResponse)
                    throw RetryError.Failed
                }
                //print(httpResponse)
                onFinish?(url)
            }
            catch {
                onFinish?(nil)
            }
        }
        else {
            //print(task.taskIdentifier, "didCompleteWithError")
            if let error = error {
                print(error)
                let process = dataTasks[task.taskIdentifier]
                process?(nil, error)
            }
            else if let data = recvData[task.taskIdentifier] {
                let process = dataTasks[task.taskIdentifier]
                process?(data, nil)
            }
            dataTasks.removeValue(forKey: task.taskIdentifier)
            recvData.removeValue(forKey: task.taskIdentifier)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        //print(dataTask.taskIdentifier, "didReceive response")
        if let handler = headerHandler[dataTask.taskIdentifier] {
            completionHandler(handler(response))
        }
        else {
            completionHandler(.allow)
        }
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        //print(dataTask.taskIdentifier, "didReceive data")
        let taskid = (session.configuration.identifier ?? "") + ".\(dataTask.taskIdentifier)"
        if var taskdata = taskQueue.sync(execute: { self.task_upload[taskid] }) {
            guard var recvData = taskdata["data"] as? Data else {
                return
            }
            recvData.append(data)
            taskdata["data"] = recvData
            taskQueue.async {
                self.task_upload[taskid] = taskdata
            }
        }
        else {
            if var prev = recvData[dataTask.taskIdentifier] {
                prev.append(data)
                recvData[dataTask.taskIdentifier] = prev
            }
            else {
                recvData[dataTask.taskIdentifier] = data
            }
        }
    }
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .WebDAV)
        storageName = name
    }

    public override func auth(onFinish: ((Bool) -> Void)?) -> Void {
        DispatchQueue.main.async {
            self.authorize(onFinish: onFinish)
        }
    }
    
    override func authorize(onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "authorize(WebDAV:\(storageName ?? ""))")
        
        DispatchQueue.main.async {
            if let controller = UIApplication.topViewController() {
                let inputView = ViewControllerWebDAV()
                inputView.onCancel = {
                    onFinish?(false)
                }
                inputView.onFinish = { uri, user, pass in
                    let _ = self.setKeyChain(key: "\(self.storageName ?? "")_accessURI", value: uri)
                    let _ = self.setKeyChain(key: "\(self.storageName ?? "")_accessUsername", value: user)
                    let _ = self.setKeyChain(key: "\(self.storageName ?? "")_accessPassword", value: pass)

                    DispatchQueue.global().async {
                        onFinish?(true)
                    }
                }
                controller.navigationController?.pushViewController(inputView, animated: true)
            }
            else {
                onFinish?(false)
            }

        }
    }
    
    public override func logout() {
        if let name = storageName {
            let _ = delKeyChain(key: "\(name)_accessURI")
            let _ = delKeyChain(key: "\(name)_accessUsername")
            let _ = delKeyChain(key: "\(name)_accessPassword")
        }
        super.logout()
    }

    /* Generate RemoteData item from WebDAV records */
    func storeItem(item: [String: Any], parentFileId: String? = nil, parentPath: String? = nil, context: NSManagedObjectContext) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let formatter2 = ISO8601DateFormatter()

        guard let id = item["href"] as? String else {
            return
        }
        if id.removingPercentEncoding == parentFileId?.removingPercentEncoding {
            return
        }
        if let idURL = URL(string: id), let aurl = URL(string: accessURI), idURL.path == aurl.path {
            return
        }
        guard let propstat = item["propstat"] as? [String: Any] else {
            return
        }
        guard let prop = propstat["prop"] as? [String: String] else {
            return
        }
        let name: String
        if let dispname = prop["displayname"] {
            name = dispname
        }
        else {
            guard let idURL = URL(string: id) else {
                return
            }
            guard let orgname = idURL.lastPathComponent.removingPercentEncoding else {
                return
            }
            name = orgname
        }
        let ctime = prop["creationdate"] ?? prop["Win32CreationTime"]
        let mtime = prop["lastmodified"] ?? prop["getlastmodified"] ?? prop["Win32LastModifiedTime"]
        let size = Int64(prop["getcontentlength"] ?? "0")
        let folder = prop["resourcetype"] == "collection"
        
        context.perform {
            var prevParent: String?
            var prevPath: String?
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")

            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    if let item = object as? RemoteData {
                        prevPath = item.path
                        let component = prevPath?.components(separatedBy: "/")
                        prevPath = component?.dropLast().joined(separator: "/")
                        prevParent = item.parent
                    }
                    context.delete(object as! NSManagedObject)
                }
            }

            let newitem = RemoteData(context: context)
            newitem.storage = self.storageName
            newitem.id = id
            newitem.name = name
            let comp = name.components(separatedBy: ".")
            if comp.count >= 1 {
                newitem.ext = comp.last!.lowercased()
            }
            newitem.cdate = formatter.date(from: ctime ?? "") ?? formatter2.date(from: ctime ?? "")
            newitem.mdate = formatter.date(from: mtime ?? "") ?? formatter2.date(from: mtime ?? "")
            newitem.folder = folder
            newitem.size = size ?? 0
            newitem.hashstr = ""
            newitem.parent = (parentFileId == nil) ? prevParent : parentFileId
            if parentFileId == "" {
                newitem.path = "\(self.storageName ?? ""):/\(name)"
            }
            else {
                if let path = (parentPath == nil) ? prevPath : parentPath {
                    newitem.path = "\(path)/\(name)"
                }
            }
        }
    }
    
    class DAVcollectionParser: NSObject, XMLParserDelegate {
        var onFinish: (([[String:Any]]?)->Void)?
        
        var response: [[String: Any]] = []
        var curElement: [String] = []
        var curProp: [String: Any] = [:]
        var prop: [String: String] = [:]
        
        func parserDidStartDocument(_ parser: XMLParser) {
            //os_log("%{public}@", log: OSLog.default, type: .debug, "parser Start")
        }
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            switch elementName {
//            case let str where str.hasSuffix(":multistatus"):
                //os_log("%{public}@", log: OSLog.default, type: .debug, "start")
            case let str where str.hasSuffix(":response"):
                response.append([:])
            case let str where str.hasSuffix(":propstat"):
                curProp = [:]
            case let str where str.hasSuffix(":prop"):
                prop = [:]
            case let str where str.hasSuffix(":resourcetype"):
                prop["resourcetype"] = ""
            case let str where str.hasSuffix(":collection"):
                prop["resourcetype"] = "collection"
            default:
                break
            }
            curElement.append(elementName)
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            //print(string)
            switch curElement.last {
            case let str where str?.hasSuffix(":href") ?? false:
                response[response.count-1]["href"] = (response[response.count-1]["href"] as? String ?? "") + string
            case let str where str?.hasSuffix(":status") ?? false:
                curProp["status"] = string
            case let str where str?.hasSuffix(":getlastmodified") ?? false:
                prop["getlastmodified"] = string
            case let str where str?.hasSuffix(":lastmodified") ?? false:
                prop["lastmodified"] = string
            case let str where str?.hasSuffix(":displayname") ?? false:
                prop["displayname"] = (prop["displayname"] ?? "") + string
            case let str where str?.hasSuffix(":getcontentlength") ?? false:
                prop["getcontentlength"] = string
            case let str where str?.hasSuffix(":creationdate") ?? false:
                prop["creationdate"] = string
            case let str where str?.hasSuffix(":Win32CreationTime") ?? false:
                prop["Win32CreationTime"] = string
            case let str where str?.hasSuffix(":Win32LastModifiedTime") ?? false:
                prop["Win32LastModifiedTime"] = string
            default:
                break
            }
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
//            case let str where str.hasSuffix(":multistatus"):
  //              os_log("%{public}@", log: OSLog.default, type: .debug, "end")
            case let str where str.hasSuffix(":propstat"):
                response[response.count-1]["propstat"] = curProp
            case let str where str.hasSuffix(":prop"):
                curProp["prop"] = prop
            default:
                break
            }
            curElement = curElement.dropLast()
        }
        
        func parserDidEndDocument(_ parser: XMLParser) {
            //os_log("%{public}@", log: OSLog.default, type: .debug, "parser End")
            onFinish?(response)
        }
        
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            print(parseError.localizedDescription)
            onFinish?(nil)
        }
    }
    
    func listFolder(path: String, callCount: Int = 0, onFinish: (([[String:Any]]?)->Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                self.listFolder(path: path, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "listFolder(WebDAV:\(storageName ?? ""))")
        lastCall = Date()
        var request: URLRequest
        guard var url = URL(string: accessURI) else {
            self.callSemaphore.signal()
            onFinish?(nil)
            return
        }
        if path != "" {
            guard let pathURL = URL(string: path) else {
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    return
                }
                url = u
            }
        }
        //print(url)
        request = URLRequest(url: url)

        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let reqStr = [
            "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
            "<D:propfind xmlns:D=\"DAV:\">",
            "<D:allprop/>",
            "</D:propfind>",
        ].joined(separator: "\r\n")+"\r\n"
        request.httpBody = reqStr.data(using: .utf8)
        
        let task = dataSession.dataTask(with: request)
        dataTasks[task.taskIdentifier] = { data, error in
            self.callSemaphore.signal()
            do {
                guard let data = data else {
                   throw RetryError.Retry
                }
                let parser: XMLParser? = XMLParser(data: data)
                let dav = DAVcollectionParser()
                dav.onFinish = onFinish
                parser?.delegate = dav
                parser?.parse()
                //print(String(data: data, encoding: .utf8)!)
            }
            catch RetryError.Retry {
                if callCount < 10 {
                    DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                        self.listFolder(path: path, callCount: callCount+1, onFinish: onFinish)
                    }
                    return
                }
                onFinish?(nil)
                return
            } catch let e {
                print(e)
                onFinish?(nil)
                return
            }
        }
        task.resume()
    }

    override func ListChildren(fileId: String, path: String, onFinish: (() -> Void)?) {
        listFolder(path: fileId) { result in
            if let items = result {
                let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                let itemcount = items.count
                os_log("%{public}@", log: self.log, type: .debug, "store \(itemcount) items(WebDAV:\(self.storageName ?? "") \(fileId)")
                for item in items {
                    self.storeItem(item: item, parentFileId: fileId, parentPath: path, context: backgroundContext)
                }
                backgroundContext.perform {
                    try? backgroundContext.save()
                    DispatchQueue.global().async {
                        onFinish?()
                    }
                }
            }
            else {
                DispatchQueue.global().async {
                    onFinish?()
                }
            }
        }
    }

    func checkAcceptRange(fileId: String, onFinish: @escaping ()->Void) {

        if acceptRange != nil {
            onFinish()
            return
        }
        
        if checkSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait+Double.random(in: 0..<0.5)) {
                self.checkAcceptRange(fileId: fileId, onFinish: onFinish)
            }
            return
        }

        os_log("%{public}@", log: log, type: .debug, "checkAcceptRange(WebDAV:\(storageName ?? "") \(fileId)")

        var request: URLRequest
        guard var url = URL(string: accessURI) else {
            self.checkSemaphore.signal()
            onFinish()
            return
        }
        if fileId != "" {
            guard let pathURL = URL(string: fileId) else {
                self.checkSemaphore.signal()
                onFinish()
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.checkSemaphore.signal()
                    onFinish()
                    return
                }
                url = u
            }
        }
        //print(url)
        request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let task = dataSession.dataTask(with: request)
        headerHandler[task.taskIdentifier] = { response in
            defer {
                DispatchQueue.global().async {
                    onFinish()
                }
            }
            
            guard let response = response as? HTTPURLResponse else {
                return .allow
            }
            guard response.statusCode == 200 else {
                print(response)
                return .allow
            }
            
            guard let accept = response.allHeaderFields["Accept-Ranges"] as? String ?? response.allHeaderFields["accept-ranges"] as? String else {
                print(response)
                return .allow
            }
            if accept.lowercased().contains("bytes") {
                self.acceptRange = true
            }
            else {
                self.acceptRange = false
            }
            return .allow
        }
        dataTasks[task.taskIdentifier] = { data, error in
            self.checkSemaphore.signal()
        }
        task.resume()
    }
    
    func readRangeRead(fileId: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {

        if let cache = CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(WebDAV:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                onFinish?(data)
                return
            }
        }

        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait+Double.random(in: 0..<0.5)) {
                self.readRangeRead(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        lastCall = Date()
        os_log("%{public}@", log: log, type: .debug, "readFile(WebDAV:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")

        var request: URLRequest
        guard var url = URL(string: accessURI) else {
            self.callSemaphore.signal()
            onFinish?(nil)
            return
        }
        if fileId != "" {
            guard let pathURL = URL(string: fileId) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                url = u
            }
        }
        //print(url)
        request = URLRequest(url: url)
        if start != nil || length != nil {
            let s = start ?? 0
            if length == nil {
                request.setValue("bytes=\(s)-", forHTTPHeaderField: "Range")
            }
            else {
                request.setValue("bytes=\(s)-\(s+length!-1)", forHTTPHeaderField: "Range")
            }
        }

        let task = dataSession.dataTask(with: request)
        dataTasks[task.taskIdentifier] = { data, error in
            self.callSemaphore.signal()
            var waittime = self.callWait
            if let error = error {
                print(error)
                if (error as NSError).code == -1009 {
                    waittime += 30
                }
            }
            if let l = length {
                if data?.count ?? 0 != l {
                    if callCount > 50 {
                        onFinish?(data)
                        return
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait+Double.random(in: 0..<waittime)) {
                        self.readRangeRead(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
                    }
                    return
                }
            }
            if let d = data {
                CloudFactory.shared.cache.saveCache(storage: self.storageName!, id: fileId, offset: start ?? 0, data: d)
            }
            onFinish?(data)
        }
        task.resume()
    }

    func readWholeRead(fileId: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {

        if let data = CloudFactory.shared.cache.getPartialFile(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(WebDAV:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                onFinish?(data)
            return
        }

        guard var url = URL(string: accessURI) else {
            self.callSemaphore.signal()
            onFinish?(nil)
            return
        }
        if fileId != "" {
            guard let pathURL = URL(string: fileId) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                url = u
            }
        }
        //print(url)
        if wholeQueue.sync(execute: { wholeReading.contains(url) }) {
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<1)) {
                if self.cancelTime.timeIntervalSinceNow > 0 {
                    self.cancelTime = Date(timeIntervalSinceNow: 0.5)
                    onFinish?(nil)
                    return
                }
                self.readWholeRead(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }

        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait+Double.random(in: 0..<0.5)) {
                self.readWholeRead(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        lastCall = Date()
        wholeQueue.async {
            self.wholeReading += [url]
        }

        var request: URLRequest
        request = URLRequest(url: url)
        
        os_log("%{public}@", log: log, type: .debug, "readFile(WebDAV:\(storageName ?? "") \(fileId) whole read \(start ?? 0) \(length ?? -1)")

        let task = dataSession.dataTask(with: request)
        var timer1: Timer?
        DispatchQueue.main.async {
            timer1 = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
                if self.cancelTime.timeIntervalSinceNow > 0 {
                    print("cancel")
                    task.cancel()
                    self.cancelTime = Date(timeIntervalSinceNow: 0.5)
                    onFinish?(nil)
                    return
                }
            }
        }
        dataTasks[task.taskIdentifier] = { data, error in
            if let error = error {
                print(error)
            }
            self.callSemaphore.signal()
            timer1?.invalidate()
            if let d = data {
                CloudFactory.shared.cache.saveFile(storage: self.storageName!, id: fileId, data: d)
                let s = Int(start ?? 0)
                if let len = length, s+Int(len) < d.count {
                    onFinish?(d.subdata(in: s..<(s+Int(len))))
                }
                else {
                    onFinish?(d.subdata(in: s..<d.count))
                }
            }
            else {
                onFinish?(nil)
            }
            self.wholeReading.removeAll(where: { $0 == url })
        }
        task.resume()
    }

    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {

        if let acceptRange = acceptRange {
            if acceptRange {
                readRangeRead(fileId: fileId, start: start, length: length, callCount: callCount, onFinish: onFinish)
            }
            else {
                readWholeRead(fileId: fileId, start: start, length: length, callCount: callCount, onFinish: onFinish)
            }
        }
        else {
            checkAcceptRange(fileId: fileId) {
                self.readFile(fileId: fileId, start: start, length: length, callCount: callCount, onFinish: onFinish)
            }
        }
    }

    public override func getRaw(fileId: String) -> RemoteItem? {
        return NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return NetworkRemoteItem(path: path)
    }
 
    public override func makeFolder(parentId: String, parentPath: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.makeFolder(parentId: parentId, parentPath: parentPath, newname: newname, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "makeFolder(WebDAV:\(storageName ?? "") \(parentId) \(newname)")
        lastCall = Date()
        
        guard var url = URL(string: accessURI) else {
            self.callSemaphore.signal()
            onFinish?(nil)
            return
        }
        if parentId != "" {
            guard let pathURL = URL(string: parentId) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                url = u
            }
        }
        url.appendPathComponent(newname, isDirectory: true)
        //print(url)

        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        
        var request2 = URLRequest(url: url)
        request2.httpMethod = "PROPFIND"
        request2.setValue("0", forHTTPHeaderField: "Depth")
        request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let reqStr = [
            "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
            "<D:propfind xmlns:D=\"DAV:\">",
            "<D:allprop/>",
            "</D:propfind>",
        ].joined(separator: "\r\n")+"\r\n"
        request2.httpBody = reqStr.data(using: .utf8)

        let task = dataSession.dataTask(with: request)
        let task2 = dataSession.dataTask(with: request2)
        headerHandler[task.taskIdentifier] = { response in
            guard let response = response as? HTTPURLResponse else {
                return .cancel
            }
            guard response.statusCode == 201 else {
                print(response)
                return .cancel
            }
            task2.resume()
            return .allow
        }
        dataTasks[task.taskIdentifier] = { data, error in
            self.callSemaphore.signal()
            do {
                if let error = error {
                    print(error)
                    throw RetryError.Retry
                }
            }
            catch RetryError.Retry {
                if callCount < 10 {
                    DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                        self.makeFolder(parentId: parentId, parentPath: parentPath, newname: newname, callCount: callCount+1, onFinish: onFinish)
                    }
                    return
                }
                onFinish?(nil)
                return
            } catch let e {
                print(e)
                onFinish?(nil)
                return
            }
        }
        dataTasks[task2.taskIdentifier] = { data, error in
            do {
                guard let data = data else {
                   throw RetryError.Retry
                }
                let parser: XMLParser? = XMLParser(data: data)
                let dav = DAVcollectionParser()
                dav.onFinish = { result in
                    guard let result = result else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                        return
                    }
                    if let item = result.first, let id = item["href"] as? String {
                        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                        self.storeItem(item: item, parentFileId: parentId, parentPath: parentPath, context: backgroundContext)
                        backgroundContext.perform {
                            try? backgroundContext.save()
                            DispatchQueue.global().async {
                                onFinish?(id)
                            }
                        }
                    }
                    else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                    }
                }
                parser?.delegate = dav
                parser?.parse()
                //print(String(data: data, encoding: .utf8)!)
            }
            catch RetryError.Retry {
                onFinish?(nil)
                return
            } catch let e {
                print(e)
                onFinish?(nil)
                return
            }
        }
        task.resume()
    }

    override func deleteItem(fileId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.deleteItem(fileId: fileId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "deleteItem(WebDAV:\(storageName ?? "") \(fileId)")
        lastCall = Date()

        guard var url = URL(string: accessURI) else {
            self.callSemaphore.signal()
            onFinish?(false)
            return
        }
        if fileId != "" {
            guard let pathURL = URL(string: fileId) else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.callSemaphore.signal()
                    onFinish?(false)
                    return
                }
                url = u
            }
        }
        //print(url)
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let task = dataSession.dataTask(with: request)
        headerHandler[task.taskIdentifier] = { response in
            self.callSemaphore.signal()
            guard let response = response as? HTTPURLResponse else {
                return .cancel
            }
            guard response.statusCode == 204 || response.statusCode == 404 else {
                print(response)
                return .cancel
            }
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                if let result = try? backgroundContext.fetch(fetchRequest) {
                    for object in result {
                        backgroundContext.delete(object as! NSManagedObject)
                    }
                }
            }
            self.deleteChildRecursive(parent: fileId, context: backgroundContext)
            backgroundContext.perform {
                try? backgroundContext.save()
                DispatchQueue.global().async {
                    onFinish?(true)
                }
            }
            return .allow
        }
        dataTasks[task.taskIdentifier] = { data, error in
            do {
                if let error = error {
                    print(error)
                    throw RetryError.Retry
                }
            }
            catch RetryError.Retry {
                if callCount < 10 {
                    DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                        self.deleteItem(fileId: fileId, callCount: callCount+1, onFinish: onFinish)
                    }
                    return
                }
                onFinish?(false)
            }
            catch let e {
                print(e)
                onFinish?(false)
            }
        }
        task.resume()
    }

    
    override func renameItem(fileId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.renameItem(fileId: fileId, newname: newname, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "renameItem(dropbox:\(storageName ?? "") \(fileId) \(newname)")
        lastCall = Date()

        guard var url = URL(string: accessURI) else {
            self.callSemaphore.signal()
            onFinish?(nil)
            return
        }
        if fileId != "" {
            guard let pathURL = URL(string: fileId) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                url = u
            }
        }
        var destURL = url
        destURL.deleteLastPathComponent()
        destURL.appendPathComponent(newname)
        //print(url)
        //print(destURL)

        var request = URLRequest(url: url)
        request.httpMethod = "MOVE"
        request.setValue(destURL.absoluteString, forHTTPHeaderField: "Destination")

        var request2 = URLRequest(url: destURL)
        request2.httpMethod = "PROPFIND"
        request2.setValue("0", forHTTPHeaderField: "Depth")
        request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let reqStr = [
            "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
            "<D:propfind xmlns:D=\"DAV:\">",
            "<D:allprop/>",
            "</D:propfind>",
        ].joined(separator: "\r\n")+"\r\n"
        request2.httpBody = reqStr.data(using: .utf8)

        let task = dataSession.dataTask(with: request)
        let task2 = dataSession.dataTask(with: request2)
        headerHandler[task.taskIdentifier] = { response in
            self.callSemaphore.signal()
            guard let response = response as? HTTPURLResponse else {
                return .cancel
            }
            guard response.statusCode == 201 else {
                print(response)
                return .cancel
            }
            task2.resume()
            return .allow
        }
        dataTasks[task.taskIdentifier] = { data, error in
            do {
                if let error = error {
                    print(error)
                    throw RetryError.Retry
                }
            }
            catch RetryError.Retry {
                if callCount < 10 {
                    DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                        self.renameItem(fileId: fileId, newname: newname, callCount: callCount+1, onFinish: onFinish)
                    }
                    return
                }
                onFinish?(nil)
            }
            catch let e {
                print(e)
                onFinish?(nil)
            }
        }
        dataTasks[task2.taskIdentifier] = { data, error in
            do {
                guard let data = data else {
                   throw RetryError.Retry
                }
                let parser: XMLParser? = XMLParser(data: data)
                let dav = DAVcollectionParser()
                dav.onFinish = { result in
                    guard let result = result else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                        return
                    }
                    if let item = result.first, let id = item["href"] as? String {
                        var prevParent: String?
                        var prevPath: String?

                        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                        let group = DispatchGroup()
                        group.enter()
                        backgroundContext.perform {
                            defer {
                                group.leave()
                            }
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                            if let result = try? backgroundContext.fetch(fetchRequest) {
                                for object in result {
                                    if let item = object as? RemoteData {
                                        prevPath = item.path
                                        let component = prevPath?.components(separatedBy: "/")
                                        prevPath = component?.dropLast().joined(separator: "/")
                                        prevParent = item.parent
                                    }
                                    backgroundContext.delete(object as! NSManagedObject)
                                }
                            }
                        }
                        self.deleteChildRecursive(parent: fileId, context: backgroundContext)
                        group.notify(queue: .global()) {
                            self.storeItem(item: item, parentFileId: prevParent, parentPath: prevPath, context: backgroundContext)
                            backgroundContext.perform {
                                try? backgroundContext.save()
                                DispatchQueue.global().async {
                                    onFinish?(id)
                                }
                            }
                        }
                    }
                    else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                    }
                }
                parser?.delegate = dav
                parser?.parse()
                //print(String(data: data, encoding: .utf8)!)
            }
            catch RetryError.Retry {
                onFinish?(nil)
                return
            } catch let e {
                print(e)
                onFinish?(nil)
                return
            }
        }
        task.resume()
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.moveItem(fileId: fileId, fromParentId: fromParentId, toParentId: toParentId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        if toParentId == fromParentId {
            callSemaphore.signal()
            onFinish?(nil)
            return
        }
        var toParentPath: String?
        if toParentId != "" {
            if Thread.isMainThread {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        toParentPath = items.first?.path ?? ""
                    }
                }
            }
            else {
                DispatchQueue.main.sync {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, self.storageName ?? "")
                    if let result = try? viewContext.fetch(fetchRequest) {
                        if let items = result as? [RemoteData] {
                            toParentPath = items.first?.path ?? ""
                        }
                    }
                }
            }
        }

        os_log("%{public}@", log: self.log, type: .debug, "moveItem(WebDAV:\(self.storageName ?? "") \(fromParentId)->\(toParentId)")
        self.lastCall = Date()

        guard var url = URL(string: accessURI) else {
            self.callSemaphore.signal()
            onFinish?(nil)
            return
        }
        var destURL = url
        if fileId != "" {
            guard let pathURL = URL(string: fileId) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                url = u
            }
        }
        if toParentId != "" {
            guard let pathURL = URL(string: toParentId) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            if pathURL.host != nil {
                destURL = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: destURL) else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                destURL = u
            }
        }
        let name = url.lastPathComponent
        destURL.appendPathComponent(name)
        //print(url)
        //print(destURL)
        
        var request = URLRequest(url: url)
        request.httpMethod = "MOVE"
        request.setValue(destURL.absoluteString, forHTTPHeaderField: "Destination")

        var request2 = URLRequest(url: destURL)
        request2.httpMethod = "PROPFIND"
        request2.setValue("0", forHTTPHeaderField: "Depth")
        request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let reqStr = [
            "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
            "<D:propfind xmlns:D=\"DAV:\">",
            "<D:allprop/>",
            "</D:propfind>",
        ].joined(separator: "\r\n")+"\r\n"
        request2.httpBody = reqStr.data(using: .utf8)

        let task = dataSession.dataTask(with: request)
        let task2 = dataSession.dataTask(with: request2)
        headerHandler[task.taskIdentifier] = { response in
            self.callSemaphore.signal()
            guard let response = response as? HTTPURLResponse else {
                return .cancel
            }
            guard response.statusCode == 201 else {
                print(response)
                return .cancel
            }
            task2.resume()
            return .allow
        }
        dataTasks[task.taskIdentifier] = { data, error in
            do {
                if let error = error {
                    print(error)
                    throw RetryError.Retry
                }
            }
            catch RetryError.Retry {
                if callCount < 10 {
                    DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                        self.moveItem(fileId: fileId, fromParentId: fromParentId, toParentId: toParentId, callCount: callCount+1, onFinish: onFinish)
                    }
                    return
                }
                onFinish?(nil)
            }
            catch let e {
                print(e)
                onFinish?(nil)
            }
        }
        dataTasks[task2.taskIdentifier] = { data, error in
            do {
                guard let data = data else {
                   throw RetryError.Retry
                }
                let parser: XMLParser? = XMLParser(data: data)
                let dav = DAVcollectionParser()
                dav.onFinish = { result in
                    guard let result = result else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                        return
                    }
                    if let item = result.first, let id = item["href"] as? String {
                        var prevParent: String?
                        var prevPath: String?

                        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                        let group = DispatchGroup()
                        group.enter()
                        backgroundContext.perform {
                            defer {
                                group.leave()
                            }
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                            if let result = try? backgroundContext.fetch(fetchRequest) {
                                for object in result {
                                    if let item = object as? RemoteData {
                                        prevPath = item.path
                                        let component = prevPath?.components(separatedBy: "/")
                                        prevPath = component?.dropLast().joined(separator: "/")
                                        prevParent = item.parent
                                    }
                                    backgroundContext.delete(object as! NSManagedObject)
                                }
                            }
                        }
                        self.deleteChildRecursive(parent: fileId, context: backgroundContext)
                        group.notify(queue: .global()) {
                            self.storeItem(item: item, parentFileId: toParentId, parentPath: toParentPath, context: backgroundContext)
                            backgroundContext.perform {
                                try? backgroundContext.save()
                                DispatchQueue.global().async {
                                    onFinish?(id)
                                }
                            }
                        }
                    }
                    else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                    }
                }
                parser?.delegate = dav
                parser?.parse()
                //print(String(data: data, encoding: .utf8)!)
            }
            catch RetryError.Retry {
                onFinish?(nil)
                return
            } catch let e {
                print(e)
                onFinish?(nil)
                return
            }
        }
        task.resume()
    }
    
    override func changeTime(fileId: String, newdate: Date, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.changeTime(fileId: fileId, newdate: newdate, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: self.log, type: .debug, "changeTime(WebDAV:\(self.storageName ?? "") \(fileId) \(newdate)")
        self.lastCall = Date()

        guard var url = URL(string: accessURI) else {
            self.callSemaphore.signal()
            onFinish?(nil)
            return
        }
        if fileId != "" {
            guard let pathURL = URL(string: fileId) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                url = u
            }
        }
        //print(url)
        
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let reqStr = [
            "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
            "<D:propfind xmlns:D=\"DAV:\">",
            "<D:allprop/>",
            "</D:propfind>",
        ].joined(separator: "\r\n")+"\r\n"
        request.httpBody = reqStr.data(using: .utf8)

        let task = dataSession.dataTask(with: request)
        let task3 = dataSession.dataTask(with: request)
        dataTasks[task.taskIdentifier] = { data, error in
            do {
                guard let data = data else {
                   throw RetryError.Retry
                }
                let lastmodified: (String)->String = { date in
                    [
                        "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                        "<D:propertyupdate xmlns:D=\"DAV:\">",
                        "<D:set>",
                        "<D:prop>",
                        "<D:lastmodified>\(date)</D:lastmodified>",
                        "</D:prop>",
                        "</D:set>",
                        "</D:propertyupdate>",
                    ].joined(separator: "\r\n")+"\r\n"
                }
                let win32lastmodified: (String)->String = { date in
                    [
                        "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                        "<D:propertyupdate xmlns:D=\"DAV:\" xmlns:Z=\"urn:schemas-microsoft-com:\">",
                        "<D:set>",
                        "<D:prop>",
                        "<Z:Win32LastModifiedTime>\(date)</Z:Win32LastModifiedTime>",
                        "</D:prop>",
                        "</D:set>",
                        "</D:propertyupdate>",
                    ].joined(separator: "\r\n")+"\r\n"
                }
                let parser: XMLParser? = XMLParser(data: data)
                let dav = DAVcollectionParser()
                dav.onFinish = { result in
                    guard let result = result else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                        return
                    }
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    formatter.timeZone = TimeZone(identifier: "GMT")
                    let formatter2 = ISO8601DateFormatter()
                    var reqStr2: String?
                    if let item = result.first, let propstat = item["propstat"] as? [String: Any], let prop = propstat["prop"] as? [String: String] {
                        if let mtime = prop["getlastmodified"] {
                            if formatter.date(from: mtime) != nil {
                                reqStr2 = lastmodified(formatter.string(from: newdate))
                            }
                            else if formatter2.date(from: mtime) != nil {
                                reqStr2 = lastmodified(formatter2.string(from: newdate))
                            }
                            else {
                                reqStr2 = lastmodified(formatter.string(from: newdate))
                            }
                        }
                        else if let mtime = prop["Win32LastModifiedTime"] {
                            if formatter.date(from: mtime) != nil {
                                reqStr2 = win32lastmodified(formatter.string(from: newdate))
                            }
                            else if formatter2.date(from: mtime) != nil {
                                reqStr2 = win32lastmodified(formatter2.string(from: newdate))
                            }
                            else {
                                reqStr2 = win32lastmodified(formatter.string(from: newdate))
                            }
                        }
                        else {
                            reqStr2 = lastmodified(formatter.string(from: newdate))
                        }
                    }
                    guard let reqStr3 = reqStr2 else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                        return
                    }
                    
                    var request2 = URLRequest(url: url)
                    request2.httpMethod = "PROPPATCH"
                    request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                    
                    request2.httpBody = reqStr3.data(using: .utf8)
                    let task2 = self.dataSession.dataTask(with: request2)
                    self.dataTasks[task2.taskIdentifier] = { data, error in
                        if let error = error {
                            print(error)
                            onFinish?(nil)
                            return
                        }
                        guard let data = data else {
                            onFinish?(nil)
                            return
                        }
                        //print(String(data: data, encoding: .utf8)!)
                        let parser: XMLParser? = XMLParser(data: data)
                        let dav = DAVcollectionParser()
                        dav.onFinish = { result in
                            guard let result = result else {
                                DispatchQueue.global().async {
                                    onFinish?(nil)
                                }
                                return
                            }
                            guard let item = result.first else {
                                DispatchQueue.global().async {
                                    onFinish?(nil)
                                }
                                return
                            }
                            guard let propstat = item["propstat"] as? [String: Any] else {
                                DispatchQueue.global().async {
                                    onFinish?(nil)
                                }
                                return
                            }
                            guard let status = propstat["status"] as? String else {
                                DispatchQueue.global().async {
                                    onFinish?(nil)
                                }
                                return
                            }
                            if status.contains("200") {
                                task3.resume()
                            }
                            else {
                                task3.cancel()
                            }
                        }
                        parser?.delegate = dav
                        parser?.parse()
                    }
                    
                    task2.resume()
                }
                parser?.delegate = dav
                parser?.parse()
                //print(String(data: data, encoding: .utf8)!)
            }
            catch RetryError.Retry {
                onFinish?(nil)
                return
            } catch let e {
                print(e)
                onFinish?(nil)
                return
            }
        }
        dataTasks[task3.taskIdentifier] = { data, error in
            do {
                guard let data = data else {
                   throw RetryError.Retry
                }
                let parser: XMLParser? = XMLParser(data: data)
                let dav = DAVcollectionParser()
                dav.onFinish = { result in
                    guard let result = result else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                        return
                    }
                    if let item = result.first, let id = item["href"] as? String {
                        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                        self.storeItem(item: item, parentFileId: nil, parentPath: nil, context: backgroundContext)
                        backgroundContext.perform {
                            try? backgroundContext.save()
                            DispatchQueue.global().async {
                                onFinish?(id)
                            }
                        }
                    }
                    else {
                        DispatchQueue.global().async {
                            onFinish?(nil)
                        }
                    }
                }
                parser?.delegate = dav
                parser?.parse()
                print(String(data: data, encoding: .utf8)!)
            }
            catch RetryError.Retry {
                onFinish?(nil)
                return
            } catch let e {
                print(e)
                onFinish?(nil)
                return
            }
        }
        task.resume()
    }
    
    override func uploadFile(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: target.path)
            let fileSize = attr[.size] as! UInt64
            
            UploadManeger.shared.UploadFixSize(identifier: sessionId, size: Int(fileSize))
        }
        catch {
            print(error)
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
            return
        }

        guard var url = URL(string: accessURI) else {
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
            return
        }
        if parentId != "" {
            guard let pathURL = URL(string: parentId) else {
                try? FileManager.default.removeItem(at: target)
                onFinish?(nil)
                return
            }
            if pathURL.host != nil {
                url = pathURL
            }
            else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String
                if p.first == "/" {
                    p2 = String(p.joined(separator: "/").dropFirst())
                }
                else {
                    p2 = p.joined(separator: "/")
                }
                guard let u = URL(string: p2, relativeTo: url) else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                url = u
            }
        }
        url.appendPathComponent(uploadname)
        
        os_log("%{public}@", log: log, type: .debug, "uploadFile(google:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")

        var parentPath = "\(storageName ?? ""):/"
        if parentId != "" {
            if Thread.isMainThread {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        parentPath = items.first?.path ?? ""
                    }
                }
            }
            else {
                DispatchQueue.main.sync {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                    if let result = try? viewContext.fetch(fetchRequest) {
                        if let items = result as? [RemoteData] {
                            parentPath = items.first?.path ?? ""
                        }
                    }
                }
            }
        }
        uploadSemaphore.wait()
        let onFinish2: (String?)->Void = { id in
            self.uploadSemaphore.signal()
            onFinish?(id)
        }

        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "PUT"

        let config = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).\(self.storageName ?? "").\(Int.random(in: 0..<0xffffffff))")
        //config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.sessions += [session]

        let task = session.uploadTask(with: request, fromFile: target)
        let taskid = (session.configuration.identifier ?? "") + ".\(task.taskIdentifier)"
        self.taskQueue.async {
            self.task_upload[taskid] = ["data": Data(), "target": target, "url": url.absoluteString, "session": sessionId]
            self.onFinsh_upload[taskid] = { urlstr in
                guard let urlstr = urlstr, let url = URL(string: urlstr) else {
                    print("failed")
                    onFinish2(nil)
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "PROPFIND"
                request.setValue("0", forHTTPHeaderField: "Depth")
                request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                
                let reqStr = [
                    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                    "<D:propfind xmlns:D=\"DAV:\">",
                    "<D:allprop/>",
                    "</D:propfind>",
                ].joined(separator: "\r\n")+"\r\n"
                request.httpBody = reqStr.data(using: .utf8)

                let task2 = self.dataSession.dataTask(with: request)
                self.dataTasks[task2.taskIdentifier] = { data, error in
                    do {
                        guard let data = data else {
                           throw RetryError.Retry
                        }
                        let parser: XMLParser? = XMLParser(data: data)
                        let dav = DAVcollectionParser()
                        dav.onFinish = { result in
                            guard let result = result else {
                                DispatchQueue.global().async {
                                    onFinish2(nil)
                                }
                                return
                            }
                            if let item = result.first, let id = item["href"] as? String {
                                let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                                self.storeItem(item: item, parentFileId: parentId, parentPath: parentPath, context: backgroundContext)
                                backgroundContext.perform {
                                    try? backgroundContext.save()
                                    DispatchQueue.global().async {
                                        onFinish2(id)
                                    }
                                }
                            }
                            else {
                                DispatchQueue.global().async {
                                    onFinish2(nil)
                                }
                            }
                        }
                        parser?.delegate = dav
                        parser?.parse()
                        //print(String(data: data, encoding: .utf8)!)
                    }
                    catch RetryError.Retry {
                        onFinish2(nil)
                        return
                    } catch let e {
                        print(e)
                        onFinish2(nil)
                        return
                    }
                }
                task2.resume()
            }
            task.resume()
        }
    }
    
    var task_upload = [String: [String: Any]]()
    var onFinsh_upload = [String: ((String?)->Void)?]()
    var sessions = [URLSession]()
    let taskQueue = DispatchQueue(label: "taskDict")

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        CloudFactory.shared.urlSessionDidFinishCallback?(session)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        print("\(bytesSent) / \(totalBytesSent) / \(totalBytesExpectedToSend)")

        let taskid = (session.configuration.identifier ?? "") + ".\(task.taskIdentifier)"
        if let taskdata = taskQueue.sync(execute: { self.task_upload[taskid] }) {
            guard let sessionId = taskdata["session"] as? String else {
                return
            }
            UploadManeger.shared.UploadProgress(identifier: sessionId, possition: Int(totalBytesSent))
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        print("d \(bytesWritten) / \(totalBytesWritten) / \(totalBytesExpectedToWrite)")
    }
    
}
