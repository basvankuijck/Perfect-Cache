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
import PerfectCrypto

open class PerfectCache {
    private(set) var cacheDirectoryURL: URL

    public init(folderName: String=".perfect-caches") {
        let url = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.cacheDirectoryURL = url.appendingPathComponent(folderName)
        LogFile.info("PerfectCache initialized in folder: \(cacheDirectoryURL.absoluteString)")
        _optionallyCreateCacheDirectory()
    }

    fileprivate func _optionallyCreateCacheDirectory() {
        if !FileManager.default.fileExists(atPath: cacheDirectoryURL.path) {
            try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
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
    ///             response.completed()
    ///             cache.write(response: response, for: request)
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
        guard let cacheFileURL = _getCacheFile(for: key) else {
            return false
        }

        return _return(cacheFileURL, with: response, expires: expires)
    }

    fileprivate func _return(_ cacheFileURL: URL, with response: HTTPResponse, expires: TimeInterval) -> Bool {
        _optionallyCreateCacheDirectory()
        if !FileManager.default.fileExists(atPath: cacheFileURL.path) {
            return false
        }

        guard let data = FileManager.default.contents(atPath: cacheFileURL.path) else {
            return false
        }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: cacheFileURL.path)
            guard let fileCreationDate = attrs[.creationDate] as? Date else {
                return false
            }
            let expireTime = Date(timeIntervalSinceNow: -expires)
            if expireTime > fileCreationDate {
                LogFile.warning("PerfectCache: Cache file (\(cacheFileURL.path)) expired...")
                _clear(cacheFileURL)
                return false
            }
        } catch {
            return false
        }

        response.setBody(bytes: [UInt8](data))
        response.completed()
        LogFile.info("PerfectCache: Return from cache (\(cacheFileURL.path))")
        return true
    }

    fileprivate func _getCacheFile(`for` request: HTTPRequest) -> URL? {
        let sortedParams = request.params().sorted { $0.0 < $1.0 }
        return _getCacheFile(for: (request.method.description + "_" + request.uri + "_" + String(describing: sortedParams)))
    }

    fileprivate func _getCacheFile(`for` key: String) -> URL? {
        _optionallyCreateCacheDirectory()

        guard let cacheFilename = key
            .digest(.sha1)?
            .encode(.hex)?
            .reduce("", { $0 + String(format: "%c", $1)}) else {
                return nil
        }
        return self.cacheDirectoryURL.appendingPathComponent(cacheFilename + ".cache")
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

    fileprivate func _clear(_ cacheFileURL: URL) {
        if !FileManager.default.fileExists(atPath: cacheFileURL.path) {
            return
        }

        do {
            try FileManager.default.removeItem(atPath: cacheFileURL.path)
            LogFile.debug("PerfectCache: Cache file (\(cacheFileURL.path)) removed!")
            
        } catch let error {
            LogFile.error("PerfectCache: Error removing cache file (\(cacheFileURL.path)): \(error)")
        }
    }

    /// Clears all the cached files
    public func clearAll() {
        guard let enumerator = FileManager.default.enumerator(at: cacheDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }

        for case let fileURL as URL in enumerator {
            try? FileManager.default.removeItem(atPath: fileURL.path)
        }

        LogFile.debug("PerfectCache: Cache cleared")
    }
}

extension PerfectCache {
    public func write(response: HTTPResponse, `for` key: String) {
        guard let cacheFileURL = _getCacheFile(for: key) else {
            return
        }

        _write(response: response, at: cacheFileURL)
    }


    public func write(response: HTTPResponse, `for` request: HTTPRequest) {
        guard let cacheFileURL = _getCacheFile(for: request) else {
            return
        }
        _write(response: response, at: cacheFileURL)
    }

    private func _write(response: HTTPResponse, `at` cacheFileURL: URL) {
        do {
            let data = Data(bytes: response.bodyBytes)
            try data.write(to: cacheFileURL, options: .atomicWrite)
            LogFile.info("PerfectCache: Cache file (\(cacheFileURL.path)) written!")

        } catch let error {
            LogFile.error("PerfectCache: Error writing cache file (\(cacheFileURL.path)): \(error)")
        }
    }
}
