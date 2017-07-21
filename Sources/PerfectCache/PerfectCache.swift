//
//  Perfect-Cache.swift
//  Perfect-Cache
//
//  Created by Bas van Kuijck on 19/07/2017.
//
//

import Foundation
import PerfectLogger
import PerfectHTTP
import SwiftString
import PerfectCrypto
import PerfectLib

open class PerfectCache {
    private(set) var cacheDirectory: Dir

    public init(folderName: String="./.caches") {
        self.cacheDirectory = Dir(folderName)
        LogFile.info("PerfectCache initialized in folder: \(cacheDirectory.path)")
        _optionallyCreateCacheDirectory()
    }

    fileprivate func _optionallyCreateCacheDirectory() {
        if !cacheDirectory.exists {
            do {
                try cacheDirectory.create()
                LogFile.debug("PerfectCache: Created directory: \(cacheDirectory.path)")

            } catch let error {
                LogFile.debug("PerfectCache: Error creating directory \(cacheDirectory.path): \(error)")
            }
        }
    }
}

extension PerfectCache {

    /// Checks if a specific request has a valid cache and then returns the file contents to the `HTTPResponse`
    ///
    /// ## Example
    ///
    ///     let cache = PerfectCache()
    ///
    ///     func handler(data: [String:Any]) throws -> RequestHandler {
    ///         return { request, response in
    ///             response.setHeader(.contentType, value: "application/json")
    ///             if cache.return(for: request, with: response) {
    ///                 return
    ///             }
    ///
    ///             // ... Do some stuff to build of the HTTPResponse
    ///             cache.write(response: response, for: request)
    ///             response.completed()
    ///         }
    ///     }
    /// - Parameters:
    ///   - request: The `Perfect.HTTPRequest`
    ///   - response: The `HTTPResponse`
    ///   - expires: How long should the cache live? (In seconds)
    /// - Returns: Bool. If a valid cache is found, return true. So the response can be prematurely broken down.
    public func `return`(`for` request: HTTPRequest, with response: HTTPResponse, expires: TimeInterval=3600) -> Bool {
        guard let cacheFileURL = _getCacheFile(for: request) else {
            return false
        }

        return _return(cacheFileURL, with: response, expires: expires)
    }

    /// Searches for a cached file according to a custom key (`String`) and returns the file contents to the `HTTPResponse`
    ///
    /// ## Example
    ///
    ///     let cache = PerfectCache()
    ///
    ///     func handler(data: [String:Any]) throws -> RequestHandler {
    ///         return { request, response in
    ///             response.setHeader(.contentType, value: "application/json")
    ///             if cache.return(for: "user-content", with: response) {
    ///                 return
    ///             }
    ///
    ///             // ... Do some stuff to build of the HTTPResponse
    ///             response.completed()
    ///             cache.write(response: response, for: "user-content")
    ///         }
    ///     }
    /// - Parameters:
    ///   - key: The cache key
    ///   - response: The `HTTPResponse`
    ///   - expires: How long should the cache live? (In seconds)
    /// - Returns: Bool. If a valid cache is found, return true. So the response can be prematurely broken down.
    public func `return`(`for` key: String, with response: HTTPResponse, expires: TimeInterval=3600) -> Bool {
        guard let cacheFile = _getCacheFile(for: key) else {
            return false
        }

        return _return(cacheFile, with: response, expires: expires)
    }

    fileprivate func _return(_ cacheFile: File, with response: HTTPResponse, expires: TimeInterval) -> Bool {
        _optionallyCreateCacheDirectory()

        if !cacheFile.exists {
            return false
        }
        let expireTime = Int(Date(timeIntervalSinceNow: -expires).timeIntervalSince1970)
        let fileModificationTime = cacheFile.modificationTime
        let dif = fileModificationTime - expireTime
        if dif < 0 {
            LogFile.warning("PerfectCache: Cache file (\(cacheFile.path)) expired...")
            _clear(cacheFile)
            return false
        }

        do {
            try cacheFile.open()
            let bytes = try cacheFile.readSomeBytes(count: cacheFile.size)
            cacheFile.close()
            response.setBody(bytes: bytes)
            response.status = .notModified
            response.completed()
            LogFile.info("PerfectCache: Return from cache (\(cacheFile.path)). Exprires in \(Int(dif)) seconds.")
            return true
        } catch let error {
            LogFile.error("PerfectCache: Error reading cache: \(error)")
        }
        return false
    }

    fileprivate func _getCacheFile(`for` request: HTTPRequest) -> File? {
        let sortedParams = request.params().sorted { $0.0 < $1.0 }
        return _getCacheFile(for: "\(request.method.description)_\(request.uri)_\(String(describing: sortedParams))")
    }

    fileprivate func _getCacheFile(`for` key: String) -> File? {
        _optionallyCreateCacheDirectory()

        guard let cacheFilename = key
            .digest(.sha1)?
            .encode(.hex)?
            .reduce("", { $0! + String(format: "%c", $1) }),
            cacheFilename.characters.count > 10 else {
                return nil
        }
        let l1 = cacheFilename[0]
        let l2 = cacheFilename[1]
        let dir = Dir("\(cacheDirectory.path)\(l1)/\(l2)")
        if !dir.exists {
            do {
                try dir.create()
            } catch let error {
                LogFile.error("PerfectCache: Error creating directory: \(error)")
                return nil
            }
        }
        return File(dir.path + cacheFilename + ".cache")
    }
}

extension PerfectCache {

    /// Clears the cache file for a specific `HTTPRequest`
    ///
    /// - Parameter request: `HTTPRequest`
    public func clear(`for` request: HTTPRequest) {
        guard let cacheFileURL = _getCacheFile(for: request) else {
            return
        }
        _clear(cacheFileURL)
    }

    /// Clears the cache file for a custom cache-key
    ///
    /// - Parameter key: `String`
    public func clear(`for` key: String) {
        guard let cacheFileURL = _getCacheFile(for: key) else {
            return
        }
        _clear(cacheFileURL)
    }

    fileprivate func _clear(_ cacheFile: File) {
        if !cacheFile.exists {
            return
        }
        do {
            try cacheFile.open(.truncate)
            cacheFile.delete()
            LogFile.debug("PerfectCache: Cache file (\(cacheFile.path)) removed!")
        } catch let error {
            LogFile.debug("PerfectCache: Error deleting file (\(cacheFile.path)): \(error)")
        }
    }

    /// Clears all the cached files
    public func clearAll() {
        do {
            try cacheDirectory.delete()
            LogFile.debug("PerfectCache: Cache cleared")
        } catch let error {
            LogFile.debug("PerfectCache: Error deleting directory (\(cacheDirectory.path)): \(error)")
        }
    }
}

extension PerfectCache {
    public func write(response: HTTPResponse, `for` key: String) {
        guard let cacheFile = _getCacheFile(for: key) else {
            return
        }

        _write(response: response, at: cacheFile)
    }


    public func write(response: HTTPResponse, `for` request: HTTPRequest) {
        guard let cacheFile = _getCacheFile(for: request) else {
            return
        }
        _write(response: response, at: cacheFile)
    }

    private func _write(response: HTTPResponse, `at` cacheFile: File) {
        do {
            let bodyBytes = response.bodyBytes
            if bodyBytes.count == 0 {
                LogFile.critical("PerfectCache: Error writing cache file (\(cacheFile.path)): 'Empty body, make sure you call write() before response.complete()'")
                return
            }
            try cacheFile.open(.write)
            try cacheFile.write(bytes: response.bodyBytes)
            cacheFile.close()
            LogFile.info("PerfectCache: Cache file (\(cacheFile.path)) written!")

        } catch let error {
            LogFile.error("PerfectCache: Error writing cache file (\(cacheFile.path)): \(error)")
        }
    }
}
