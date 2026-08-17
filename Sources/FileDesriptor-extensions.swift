// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import System
import Darwin

// FIXME: System has added support for Stat
public extension FileDescriptor {
  /// Returns `true` if this file descriptor refers to a regular file.
  var isRegularFile : Bool {
    var sbp = Darwin.stat()
    if fstat(self.rawValue, &sbp) != 0 {
      return false
    }
    return (sbp.st_mode & S_IFMT) == S_IFREG
  }
  
  /// An `AsyncSequence` that yields one byte at a time from this file descriptor.
  var bytes : AsyncByteStream { get  { AsyncByteStream(fd: self) } }
  /// An `AsyncSequence` that yields one decoded `Character` at a time from this file descriptor.
  var characters : AsyncCharacterReader { get { AsyncCharacterReader(fd: self) } }
  
  /// Opens `forReading` for reading.
  ///
  /// - Parameter forReading: The file path to open.
  /// - Throws: `Errno` if the file cannot be opened.
  init(forReading: String) throws {
    self = try Self.open(forReading, .readOnly)
  }
  
  /// Opens `forWriting` for writing.
  ///
  /// - Parameter forWriting: The file path to open.
  /// - Throws: `Errno` if the file cannot be opened.
  init(forWriting: String) throws {
    self = try Self.open(forWriting, .writeOnly, options: [.create, .truncate], permissions: [.ownerReadWrite])
  }
  
  /// Opens `forUpdating` for both reading and writing.
  ///
  /// - Parameter forUpdating: The file path to open.
  /// - Throws: `Errno` if the file cannot be opened.
  init(forUpdating: String) throws {
    self = try Self.open(forUpdating, .readWrite, options: [.create], permissions: [.ownerReadWrite])
  }
  
  /// Reads up to `count` bytes from this descriptor.
  ///
  /// - Parameter count: Maximum number of bytes to read.
  /// - Returns: The bytes actually read (may be fewer than `count`).
  /// - Throws: `Errno` on I/O error.
  func readUpToCount(_ count: Int) throws -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: count)
    
    let bytesRead = try buffer.withUnsafeMutableBytes {
      try self.read(into: $0)
    }
    
    return Array(buffer.prefix(bytesRead))
  }
  
  /// Writes all elements of `data` to this descriptor.
  ///
  /// - Parameter data: The sequence of bytes to write.
  /// - Returns: The number of bytes written.
  /// - Throws: `Errno` on I/O error.
  @discardableResult func write<S:Sequence>(_ data : S) throws -> Int where S.Element == UInt8  {
    try self.writeAll(data)
  }
  
  /// Reads all bytes from this file descriptor until EOF.
  ///
  /// - Parameter chunkSize: The size of each read operation. Defaults to 4096 bytes.
  /// - Returns: A `[UInt8]` containing the full contents.
  /// - Throws: `Errno` on I/O error.
  func readToEnd(chunkSize: Int = 4096) throws -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: chunkSize)
    var result = [UInt8]()
    
    while true {
      let bytesRead = try buffer.withUnsafeMutableBytes {
        try self.read(into: $0)
      }
      if bytesRead == 0 {
        break // EOF
      }
      result.append(contentsOf: buffer[..<bytesRead])
    }
    
    return result
  }
  
  /// Sets the POSIX permission bits on this file descriptor.
  ///
  /// - Parameter p: The desired permissions.
  /// - Throws: ``POSIXErrno`` if `fchmod(2)` fails.
  func setPermissions(_ p : FilePermissions) throws(POSIXErrno) {
    if 0 != fchmod(self.rawValue, p.rawValue) {
      throw POSIXErrno(fn: "setPermissions")
    }
  }
  
  /// Sets the access and modification timestamps of this file.
  ///
  /// Pass `nil` for either parameter to leave that timestamp unchanged.
  ///
  /// - Parameters:
  ///   - modified: The new modification time, or `nil` to omit.
  ///   - accessed: The new access time, or `nil` to omit.
  /// - Throws: ``POSIXErrno`` if `futimens(2)` fails.
  func setTimes(modified: DateTime? = nil, accessed: DateTime? = nil) throws(POSIXErrno) {
    let omit = timespec(tv_sec: 0, tv_nsec: Int(Darwin.UTIME_OMIT))
    var times : (timespec, timespec) = ( modified?.timespec ?? omit, accessed?.timespec ?? omit)
    if futimens( self.rawValue, &times.0) != 0 {
      throw POSIXErrno(fn: "setTimes")
    }
  }
  
  /// Reads all bytes from this descriptor and decodes them as a UTF-8 string.
  ///
  /// - Returns: The full contents as a `String`.
  /// - Throws: Any error from ``readAllBytes()``.
  func readAsString<C : Unicode.Encoding>(encoding: C.Type = UTF8.self) throws -> String {
    let k = try readAllBytes()
    switch encoding {
      case is ISOLatin1.Type:
        // FIXME: should it be validating?
        return String(decoding: k, as: ISOLatin1.self)
      case is UTF8.Type:
        fallthrough
      default:
        return String.init(decoding: k, as: UTF8.self)
    }
  }
  
  /// Reads all bytes from this already-open descriptor (streaming; mmap does not apply).
  ///
  /// Retries automatically on `EINTR` and respects `Task.isCancelled`.
  ///
  /// - Returns: A `[UInt8]` with the complete contents.
  /// - Throws: `Errno` on I/O error, or `CancellationError` if the task is cancelled.
  func readAllBytes() throws -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(8192)
    
    var buf = [UInt8](repeating: 0, count: 64 * 1024)
    
    while true {
      if Task.isCancelled { throw CancellationError() }
      
      let n: Int
      do {
        n = try buf.withUnsafeMutableBytes { rawBuf in
          try self.read(into: rawBuf)
        }
      } catch let e as Errno {
        if e == .interrupted { continue }   // EINTR
        throw e
      }
      
      if n == 0 { break } // EOF
      out.append(contentsOf: buf[0..<n])
    }
    
    return out
  }
  
  /// Writes all bytes in `bytes` to this descriptor, retrying on `EINTR`.
  ///
  /// - Parameter bytes: The bytes to write.
  /// - Throws: `Errno` on I/O error, or ``POSIXErrno`` if the write returns zero unexpectedly.
  func writeAllBytes(_ bytes: [UInt8]) throws {
    var written = 0
    while written < bytes.count {
      let n: Int
      do {
        n = try bytes.withUnsafeBytes { rawBuf in
          let base = rawBuf.bindMemory(to: UInt8.self).baseAddress!
          let ptr = base.advanced(by: written)
          let remaining = bytes.count - written
          return try write(UnsafeRawBufferPointer(start: ptr, count: remaining))
        }
      } catch let e as Errno {
        if e == .interrupted { continue }
        throw e
      }
      if n == 0 {
        throw POSIXErrno(EPIPE, fn: "write")
      }
      written += n
    }
  }
  
  /// Lists the names of all entries in the directory represented by this descriptor.
  ///
  /// - Returns: An array of entry name strings (including `.` and `..`).
  /// - Throws: ``POSIXErrno`` if `fdopendir(3)` or `readdir(3)` fails.
  func listDirectory() throws(POSIXErrno) -> [String] {
    guard let dp = fdopendir(rawValue) else {
      throw POSIXErrno(fn: "fdopendir")
    }
    defer { closedir(dp) }
    
    var results: [String] = []
    results.reserveCapacity(64)
    
    errno = 0
    while let ent = readdir(dp) {
      let name = withUnsafePointer(to: &ent.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(cString: $0)
        }
      }
      
      results.append(name)
      errno = 0
    }
    
    if errno != 0 {
      throw POSIXErrno(fn: "readdir")
    }
    
    return results
  }
  
  /// Reads whatever bytes are currently available on the file descriptor without blocking.
  ///
  /// Returns an empty array if no bytes are available (`EAGAIN`/`EWOULDBLOCK`), or at
  /// end-of-file.
  ///
  /// - Returns: All bytes currently available.
  /// - Throws: `Errno` for any error other than `EAGAIN`/`EWOULDBLOCK`.
  func readAvailableBytes() throws(Errno) -> [UInt8] {
    var result: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 4096)
    
    while true {
      do {
        let count = try buffer.withUnsafeMutableBytes { rawBuffer in
          try self.read(into: rawBuffer)
        }
        if count == 0 {
          // EOF
          break
        }
        result.append(contentsOf: buffer.prefix(count))
      } catch let error as Errno {
        if error == .wouldBlock {
          // No more data currently available
          break
        }
        throw error
      } catch {
        throw Errno.ioError
      }
    }
    return result
  }
  
  /// Blocks the current thread until at least one byte is available to read on this descriptor.
  ///
  /// Uses `poll(2)` with an infinite timeout and retries on `EINTR`.
  ///
  /// - Throws: `Errno` if `poll` returns an error.
  func waitUntilReadable() throws(Errno) {
    var pfd = pollfd(
      fd: Int32(self.rawValue),
      events: Int16(POLLIN),
      revents: 0
    )
    
    while true {
      let rc = poll(&pfd, 1, -1)   // -1 = wait forever
      if rc > 0 {
        return
      }
      
      if rc == -1 {
        if errno == EINTR {
          continue
        }
        throw Errno(rawValue: errno)
      }
    }
  }
  
  /// Sets the `O_NONBLOCK` flag on this file descriptor.
  ///
  /// - Throws: `Errno` if `fcntl(F_SETFL)` fails.
  func makeNonBlocking() throws(Errno) {
    let flags = fcntl(self.rawValue, F_GETFL)
    guard flags >= 0 else { throw Errno(rawValue: errno) }
    guard fcntl(self.rawValue, F_SETFL, flags | O_NONBLOCK) >= 0 else {
      throw Errno(rawValue: errno)
    }
  }

  /// Sets the close-on-exec flag (`FD_CLOEXEC`) on this file descriptor.
  func setCloexec() {
    let flags = Darwin.fcntl(self.rawValue, F_GETFD)
    _ = fcntl(self.rawValue, F_SETFD, flags | FD_CLOEXEC)
  }
}


extension FileDescriptor: @retroactive TextOutputStream {
  /// Writes `string` encoded as UTF-8 to this file descriptor.
  ///
  /// Errors are silently discarded so this conforms to `TextOutputStream`.
  public func write(_ string: String) {
    let _ = try? self.writeAll( Array(string.utf8) )
  }
}
