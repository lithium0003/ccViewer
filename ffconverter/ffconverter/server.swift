//
//  server.swift
//  ffconverter
//
//  Created by rei8 on 2019/09/07.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import BackgroundTasks

class HTTPserver {
    let baseUrl: URL
    let port: UInt16
    let sockfd: Int32
    var isRunning = true
    actor Connections {
        var connfds = [Int32]()
        
        func add(_ fd: Int32) {
            connfds.append(fd)
        }
        
        func remove(_ fd: Int32) {
            connfds.removeAll { $0 == fd }
        }
    }
    var connections = Connections()
    
    init?(baseUrl: URL, port: UInt16) {
        let bundleId = Bundle.main.bundleIdentifier!
        let taskName = UUID().uuidString
        let taskIdentifier = "\(bundleId).server.\(taskName)"

        signal(SIGPIPE) { s in print("signal SIGPIPE") }
        
        var hints = addrinfo()
        memset(&hints, 0, MemoryLayout.size(ofValue: hints))
        hints.ai_family = AF_INET6
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_PASSIVE

        var ai: addrinfo
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let err = getaddrinfo(nil, "\(port)", &hints, &res)
        guard err == 0 else {
            perror("getaddrinfo() failed: \(err)")
            return nil
        }
        guard let resp = res else {
            perror("getaddrinfo() failed: nullpointer")
            return nil
        }
        ai = resp.pointee
        
        self.baseUrl = baseUrl
        self.port = port
        
        sockfd = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
        guard sockfd >= 0 else {
            perror("ERROR opening socket")
            return nil
        }
        
        var reuse = 1
        guard setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, withUnsafePointer(to: &reuse) { $0 }, socklen_t(MemoryLayout.size(ofValue: reuse))) >= 0 else {
            perror("setsockopt(SO_REUSEADDR) failed");
            return nil
        }
        
        guard bind(sockfd, ai.ai_addr, ai.ai_addrlen) >= 0 else {
            perror("ERROR on binding")
            return nil
        }
        
        listen(sockfd,5)

        if !ProcessInfo.processInfo.isiOSAppOnMac || !UserDefaults.standard.bool(forKey: "castInBackground") {
            let request = BGContinuedProcessingTaskRequest(
                identifier: taskIdentifier,
                title: "Local server for cast",
                subtitle: "wait fot start...",
            )
            if BGTaskScheduler.supportedResources.contains(.gpu) {
                request.requiredResources = .gpu
            }
            request.strategy = .fail
            
            let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
                guard let task = task as? BGContinuedProcessingTask else { return }
                var wasExpired = false
                // Check the expiration handler to confirm job completion.
                task.expirationHandler = {
                    wasExpired = true
                }
                
                Task { @MainActor in
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                defer {
                    Task { @MainActor in
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                }
                
                let progress = task.progress
                progress.totalUnitCount = 600
                
                Thread.detachNewThread { [self] in
                    while isRunning, !progress.isFinished, !wasExpired {
                        var cli_addr = sockaddr()
                        var clilen = socklen_t()
                        let newsockfd = accept(sockfd, &cli_addr, &clilen)
                        
                        guard newsockfd >= 0 else {
                            perror("ERROR on accept")
                            return
                        }
                        
                        Task {
                            await connections.add(newsockfd)
                        }
                        
                        Thread.detachNewThread { [self] in
                            Task {
                                await processConnection(connSockfd: newsockfd)
                            }
                        }
                    }
                    progress.completedUnitCount = progress.totalUnitCount
                }
                
                // Update progress.
                while self.isRunning, !progress.isFinished, !wasExpired {
                    progress.completedUnitCount += 1
                    
                    // Update task for displayed progress.
                    task.updateTitle(task.title, subtitle: "Casting \(progress.completedUnitCount / 10)sec")
                    Thread.sleep(forTimeInterval: 0.1)
                    
                    if progress.completedUnitCount > progress.totalUnitCount / 2 {
                        progress.totalUnitCount += 600
                    }
                }
                
                task.setTaskCompleted(success: true)
                Task {
                    await Converter.Stop()
                }
            }
            
            guard success else {
                fatalError("Failed to register task with identifier: \(taskIdentifier)")
            }
            
            // Submit the task request.
            do {
                try BGTaskScheduler.shared.submit(request)
                return
            } catch {
                print("Failed to submit request: \(error)")
            }
        }
        
        Thread.detachNewThread { [self] in
            Task { @MainActor in
                UIApplication.shared.isIdleTimerDisabled = true
            }
            defer {
                Task { @MainActor in
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
            while isRunning {
                var cli_addr = sockaddr()
                var clilen = socklen_t()
                let newsockfd = accept(sockfd, &cli_addr, &clilen)
                
                guard newsockfd >= 0 else {
                    perror("ERROR on accept")
                    return
                }
                
                Task {
                    await connections.add(newsockfd)
                }
                
                Thread.detachNewThread { [self] in
                    Task {
                        await processConnection(connSockfd: newsockfd)
                    }
                }
            }
        }
    }
    
    func processConnection(connSockfd: Int32) async {
        var request = [String]()
        var tmpBuffer = [UInt8]()
        var requestDone = false
        while self.isRunning {
            let buflen = 256*1024
            var buffer = [UInt8](repeating: 0, count: buflen)
            let n = buffer.withUnsafeMutableBytes { read(connSockfd, $0.baseAddress, buflen) }
            
            guard n > 0 else {
                perror("ERROR reading from socket");
                break
            }
            
            tmpBuffer.append(contentsOf: buffer[0..<n])
            
            while tmpBuffer.count > 0, let ind1 = tmpBuffer.firstIndex(of: 13) {
                if ind1 + 1 < tmpBuffer.count && tmpBuffer[ind1+1] == 10 {
                    if let line = String(bytes: tmpBuffer[0..<ind1], encoding: .utf8) {
                        request += [line]
                        if line == "" {
                            requestDone = true
                        }
                    }
                    if ind1 + 2 < tmpBuffer.count {
                        tmpBuffer = Array(tmpBuffer[(ind1+2)...])
                    }
                    else {
                        tmpBuffer.removeAll()
                    }
                }
            }
            
            if requestDone && request.count > 0 {
                let ok = await parseRequest(request: request) { response in
                    //print(String(bytes: response, encoding: .utf8) ?? "")
                    let reslen = response.count
                    //print("reslen ", reslen)
                    let n = response.withUnsafeBytes { write(connSockfd, $0.baseAddress, reslen) }
                    //print("write ", n)
                    guard n >= 0 else {
                        perror("ERROR writing to socket");
                        return false
                    }
                    return true
                }
                request.removeAll()
                guard ok else {
                    break
                }
            }
        }
        close(connSockfd)
        await connections.remove(connSockfd)
    }
    
    func parseRequest(request: [String], writer: ([UInt8])->Bool) async -> Bool {
        print(request)
        let errorRes = Array("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: Close\r\n\r\n".utf8)
        let notImpl = Array("HTTP/1.1 501 Not Implemented\r\nContent-Length: 0\r\nConnection: Close\r\n\r\n".utf8)
        let notFound = Array("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: Close\r\n\r\n".utf8)
        guard let methodLine = request.first else {
            let _ = writer(errorRes)
            return false
        }
        let methodComp = methodLine.components(separatedBy: " ")
        if methodComp[0] == "GET", methodComp.count == 3 {
            let reqpath = methodComp[1]
            guard reqpath.starts(with: "/") else {
                let _ = writer(notFound)
                return false
            }
            guard let reqfile = reqpath.dropFirst().removingPercentEncoding else {
                let _ = writer(notFound)
                return false
            }
            let target = baseUrl.appendingPathComponent(reqfile == "" ? "index.html" : reqfile)
            let contentType: String
            var appendHeader: String? = nil
            switch target.pathExtension {
            case "html":
                contentType = "text/html"
            case "m3u8":
                contentType = "application/vnd.apple.mpegurl"
                appendHeader = ["Access-Control-Allow-Origin: *",
                                "Access-Control-Allow-Method: GET",
                                "Access-Control-Allow-Headers: *",
                                "Access-Control-Expose-Headers: *"]
                    .joined(separator: "\r\n") + "\r\n"
            case "ts":
                contentType = "video/MP2T"
                appendHeader = ["Access-Control-Allow-Origin: *",
                                "Access-Control-Allow-Method: GET",
                                "Access-Control-Allow-Headers: *",
                                "Access-Control-Expose-Headers: *"]
                    .joined(separator: "\r\n") + "\r\n"
            case "vtt":
                contentType = "text/vtt"
                appendHeader = ["Access-Control-Allow-Origin: *",
                                "Access-Control-Allow-Method: GET",
                                "Access-Control-Allow-Headers: *",
                                "Access-Control-Expose-Headers: *"]
                    .joined(separator: "\r\n") + "\r\n"
            case "m4s":
                contentType = "video/iso.segment"
                appendHeader = ["Access-Control-Allow-Origin: *",
                                "Access-Control-Allow-Method: GET",
                                "Access-Control-Allow-Headers: *",
                                "Access-Control-Expose-Headers: *"]
                    .joined(separator: "\r\n") + "\r\n"
            case "mp4":
                contentType = "video/mp4"
                appendHeader = ["Access-Control-Allow-Origin: *",
                                "Access-Control-Allow-Method: GET",
                                "Access-Control-Allow-Headers: *",
                                "Access-Control-Expose-Headers: *"]
                    .joined(separator: "\r\n") + "\r\n"
            default:
                contentType = "text/plain"
            }

            if let segment = Int(reqfile.suffix(11).prefix(8)) {
                let randID = String(reqfile.prefix(36))
                print(randID, segment)
                await Converter.touch(randID: randID, segment: segment)
            }

            guard let attr = try? FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false)) else {
                let _ = writer(notFound)
                return false
            }
            let fileDate: Date
            if let filedate = attr[.modificationDate] as? Date {
                fileDate = filedate
            }
            else {
                fileDate = Date()
            }
            
            let dateFormat = DateFormatter()
            dateFormat.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            dateFormat.timeZone = TimeZone.init(identifier: "GMT")
            dateFormat.locale = Locale(identifier: "en_US_POSIX")
            var header = [
                "HTTP/1.1 200 OK",
                "Content-Type: \(contentType)",
                "Transfer-Encoding: chunked",
                "Date: \(dateFormat.string(from: fileDate))"
                ].joined(separator: "\r\n") + "\r\n"
            if let appendHeader = appendHeader {
                header += appendHeader
            }
            header += "\r\n"

            // actual file
            guard let input = InputStream(url: target) else {
                let _ = writer(notFound)
                return false
            }
            input.open()
            defer {
                input.close()
            }
            
            var res = [UInt8]()
            res.append(contentsOf: Array(header.utf8))
            guard writer(res) else {
                return false
            }
            res.removeAll()
            
            let bufferSize = 32*1024*1024
            var len = 0
            var count = 0
            repeat {
                var buffer = [UInt8](repeating: 0, count: bufferSize)
                len = input.read(&buffer, maxLength: buffer.count)
                if len < 0 {
                    print(input.streamError ?? "")
                    if count == 0 {
                        return writer(notFound)
                    }
                    else {
                        res.append(contentsOf: Array("\(0)\r\n".utf8))
                        res.append(contentsOf: Array("\r\n".utf8))
                        return writer(res)
                    }
                }
                if len == 0 {
                    break
                }
                count += len
                res.append(contentsOf: Array("\(String(format: "%x", len))\r\n".utf8))
                res.append(contentsOf: buffer[0..<len])
                res.append(contentsOf: Array("\r\n".utf8))
                guard writer(res) else {
                    return false
                }
                res.removeAll()
            } while len == bufferSize
            res.append(contentsOf: Array("\(0)\r\n".utf8))
            res.append(contentsOf: Array("\r\n".utf8))
            guard writer(res) else {
                return false
            }
            return true
        }
        else {
            let _ = writer(notImpl)
            return false
        }
    }
    
    func Stop() {
        if isRunning {
            isRunning = false
            close(sockfd)
            Task {
                for fd in await connections.connfds {
                    close(fd)
                    await connections.remove(fd)
                }
            }
        }
    }
    
    // Return IP address of WiFi interface (en0) as a String, or `nil`
    class func getWiFiAddress() -> String? {
        var address : String?
        
        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            
            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                
                // Check interface name:
                let name = String(cString: interface.ifa_name)
                if  name == "en0" {
                    
                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    if let address, !address.hasPrefix("fe80") {
                        break
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        
        return address
    }
}
