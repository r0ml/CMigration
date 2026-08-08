
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025
// from a file containing the following notices:

/*
 * Copyright (c) 1997 Todd C. Miller <Todd.Miller@courtesan.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Darwin
@_exported import errno_h


extension FilePath {
  /// Returns `true` if the path refers to a regular file (not following symlinks).
  ///
  /// - Throws: ``POSIXErrno`` if `lstat(2)` fails.
  public func isRegularFile() throws(POSIXErrno) -> Bool {
    let statBuf = try FileMetadata(for: self, followSymlinks: false)
    return statBuf.filetype == .regular
  }

  /// Renames this path to `to`.
  ///
  /// - Parameter to: The destination path.
  /// - Throws: ``POSIXErrno`` if `rename(2)` fails.
  public func rename(to: FilePath) throws(POSIXErrno) {
    let k = Darwin.rename(self.string, to.string)
    if k != 0 {
      throw POSIXErrno(k, fn: "rename")
    }
  }
}

extension FileDescriptor {
  /// Returns `true` if this file descriptor refers to a regular file.
  public var isRegularFile : Bool {
    var sbp = Darwin.stat()
    if fstat(self.rawValue, &sbp) != 0 {
      return false
    }
    return (sbp.st_mode & S_IFMT) == S_IFREG
  }
}


extension FileDescriptor {
  /// An `AsyncSequence` that yields one byte at a time from this file descriptor.
  public var bytes : AsyncByteStream { get  { AsyncByteStream(fd: self) } }
  /// An `AsyncSequence` that yields one decoded `Character` at a time from this file descriptor.
  public var characters : AsyncCharacterReader { get { AsyncCharacterReader(fd: self) } }

  /// Opens `forReading` for reading.
  ///
  /// - Parameter forReading: The file path to open.
  /// - Throws: `Errno` if the file cannot be opened.
  public init(forReading: String) throws {
    self = try Self.open(forReading, .readOnly)
  }

  /// Opens `forWriting` for writing.
  ///
  /// - Parameter forWriting: The file path to open.
  /// - Throws: `Errno` if the file cannot be opened.
  public init(forWriting: String) throws {
    self = try Self.open(forWriting, .writeOnly)
  }

  /// Opens `forUpdating` for both reading and writing.
  ///
  /// - Parameter forUpdating: The file path to open.
  /// - Throws: `Errno` if the file cannot be opened.
  public init(forUpdating: String) throws {
    self = try Self.open(forUpdating, .readWrite)
  }


}

/// An `AsyncSequence` that yields raw bytes from an open `FileDescriptor`.
///
/// Use `fd.bytes` to obtain one, or iterate it directly.  Obtain a line-based view
/// via ``lines`` or ``lines(_:encoding:)``.
public struct AsyncByteStream: AsyncSequence {
  /// Each element is a single raw byte.
  public typealias Element = UInt8
  let fd: FileDescriptor
  let bufferSize: Int = 4096

  /// Returns a line-based async sequence (newline-terminated strings, without EOL).
  public var lines : AsyncLineReader { get { AsyncLineReader(byteStream: self) } }

  /// Returns a line-based async sequence with configurable EOL inclusion and encoding.
  ///
  /// - Parameters:
  ///   - withEOL: When `true`, the newline character is included in each line. Defaults to `false`.
  ///   - encoding: The string encoding to apply. Defaults to `UTF8.self`.
  public func lines(_ withEOL : Bool = false, encoding: any Unicode.Encoding.Type = UTF8.self) -> AsyncLineReader {
    return AsyncLineReader(byteStream: self, retEOL:  withEOL, encoding: encoding)
  }

  /// The iterator type for ``AsyncByteStream``.
  public struct AsyncIterator: AsyncIteratorProtocol {
    let fd: FileDescriptor
    var buffer = [UInt8]()
    var index = 0
    let bufferSize: Int

    /// Returns the next byte from the file descriptor, refilling the internal buffer as needed.
    ///
    /// - Returns: The next byte, or `nil` at end-of-file.
    /// - Throws: `Errno` on I/O error.
    public mutating func next() async throws -> UInt8? {
      if index >= buffer.count {
        var temp = [UInt8](repeating: 0, count: bufferSize)
        let bytesRead = try temp.withUnsafeMutableBytes {
          try fd.read(into: $0)
        }

        guard bytesRead > 0 else { return nil }
        buffer = Array(temp.prefix(bytesRead))
        index = 0
      }

      let byte = buffer[index]
      index += 1
      return byte
    }
  }

  /// Creates the async iterator for this byte stream.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(fd: fd, bufferSize: bufferSize)
  }
}


/// An `AsyncSequence` that yields complete lines from a ``AsyncByteStream``.
///
/// This is a Swift-native reimplementation of `AsyncLineSequence` supporting:
/// - Optional inclusion of the newline character in each result.
/// - Selectable string encodings (`UTF8`, `ISOLatin1`, `UTF16`, `UTF32`).
public struct AsyncLineReader: AsyncSequence {
  /// Each element is one text line.
  public typealias Element = String
  let byteStream: AsyncByteStream
  var retEOL = false
  var encoding : any Unicode.Encoding.Type = UTF8.self

  /// Returns a copy of this reader configured to include the trailing newline in each line.
  public mutating func withEOL() -> Self {
    retEOL = true
    return self
  }

  /// The iterator type for ``AsyncLineReader``.
  public struct AsyncIterator: AsyncIteratorProtocol {
    var byteIterator: AsyncByteStream.AsyncIterator
    var buffer = [UInt8]()
    var retEOL = false
    var encoding : any Unicode.Encoding.Type = UTF8.self

    /// Returns the next decoded line, or `nil` at end-of-file.
    ///
    /// - Returns: A line string (possibly including `\n` when `retEOL` is `true`), or `nil`.
    /// - Throws: `Errno` on I/O error.
    public mutating func next() async throws -> String? {
      var go = false
      while let byte = try await byteIterator.next() {
        go = true
        if byte == UInt8(ascii: "\n") {
          if retEOL { buffer.append(byte) }
          break
        } else {
          buffer.append(byte)
        }
      }

      guard go else { return nil }
      var line : String?
      switch encoding {
        case is ISOLatin1.Type:
          line = String(validating: buffer, as: ISOLatin1.self )
        case is UTF16.Type:
          let buff = buffer.withUnsafeBytes { $0.load(as: [UInt16].self) }
          line = String(validating: buff, as: UTF16.self )
        case is UTF32.Type:
          let buff = buffer.withUnsafeBytes { $0.load(as: [UInt32].self) }
          line = String(validating: buff, as: UTF32.self )
        case is UTF8.Type:
          fallthrough
        default:
          line = String(validating: buffer, as: UTF8.self )
      }
      guard let line else {
        line = String(validating: buffer, as: ISOLatin1.self )
        buffer.removeAll()
        return line
      }
      buffer.removeAll()
      return line
    }
  }

  /// Creates the async iterator for this line reader.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(byteIterator: byteStream.makeAsyncIterator(), retEOL: retEOL, encoding: encoding)
  }
}

public extension FilePath {
  /// Returns `true` if the process has execute permission for this path.
  var isExecutable : Bool {
    return self.string.withPlatformString { cPath in
      access(cPath, X_OK) == 0
    }
  }
}


extension FileDescriptor {
  /// Reads up to `count` bytes from this descriptor.
  ///
  /// - Parameter count: Maximum number of bytes to read.
  /// - Returns: The bytes actually read (may be fewer than `count`).
  /// - Throws: `Errno` on I/O error.
  public func readUpToCount(_ count: Int) throws -> [UInt8] {
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
  @discardableResult public func write<S:Sequence>(_ data : S) throws -> Int where S.Element == UInt8  {
    try self.writeAll(data)
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


/// An `AsyncSequence` that yields `Character` values decoded from an open `FileDescriptor`.
///
/// Handles multi-byte UTF-8 sequences by buffering partial bytes until a complete
/// code point is available.
public struct AsyncCharacterReader: AsyncSequence {
  /// Each element is one Swift `Character`.
  public typealias Element = Character
  /// The file descriptor to read from.
  public let fd: FileDescriptor
  /// The number of bytes read from the descriptor in each I/O operation.
  public let bufferSize: Int

  /// Creates an `AsyncCharacterReader` for the given descriptor.
  ///
  /// - Parameters:
  ///   - fd: The descriptor to read from.
  ///   - bufferSize: The read buffer size. Defaults to 4096.
  public init(fd: FileDescriptor, bufferSize: Int = 4096) {
    self.fd = fd
    self.bufferSize = bufferSize
  }

  /// The iterator type for ``AsyncCharacterReader``.
  public struct AsyncIterator: AsyncIteratorProtocol {
    let fd: FileDescriptor
    let bufferSize: Int

    var byteBuffer = [UInt8]()
    var characterIterator: String.Iterator?

    init(fd: FileDescriptor, bufferSize: Int) {
      self.fd = fd
      self.bufferSize = bufferSize
    }

    /// Returns the next decoded `Character`, or `nil` at end-of-file.
    ///
    /// - Returns: The next character, or `nil`.
    /// - Throws: `Errno` on I/O error.
    public mutating func next() async throws -> Character? {
      if var iter = characterIterator, let nextChar = iter.next() {
        characterIterator = iter
        return nextChar
      }

      var tempBuffer = [UInt8](repeating: 0, count: bufferSize)
      let bytesRead = try tempBuffer.withUnsafeMutableBytes {
        try fd.read(into: $0)
      }

      if bytesRead == 0 {
        return nil // EOF
      }

      byteBuffer.append(contentsOf: tempBuffer[..<bytesRead])

      var decodedCount = byteBuffer.count
      while decodedCount > 0 {
        let slice = byteBuffer.prefix(decodedCount)
        let decoded = String(decoding: slice, as: UTF8.self)
        let reencoded = Array(decoded.utf8)

        if reencoded.count == decodedCount {
          characterIterator = decoded.makeIterator()
          byteBuffer.removeFirst(decodedCount)
          return characterIterator?.next()
        }

        decodedCount -= 1
      }

      // Wait for more bytes to complete the UTF-8 sequence
      return try await next()
    }
  }

  /// Creates the async iterator for this character reader.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(fd: fd, bufferSize: bufferSize)
  }
}



/// Reads the entire contents of the file at `path` as a UTF-8 string.
///
/// - Parameter path: The filesystem path to read.
/// - Returns: The file contents decoded as UTF-8.
/// - Throws: `Errno` if the file cannot be opened or read.
public func readFileAsString(at path: String) throws -> String {
  let fd = try FileDescriptor.open(path, .readOnly)
  defer { try? fd.close() }

  var content = [UInt8]()
  var buffer = [UInt8](repeating: 0, count: 4096)

  while true {
    let bytesRead = try buffer.withUnsafeMutableBytes {
      try fd.read(into: $0)
    }
    if bytesRead == 0 { break }
    content.append(contentsOf: buffer[..<bytesRead])
  }

  return String(decoding: content, as: UTF8.self)
}

public extension FileDescriptor {
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
}


/// A typed POSIX error that captures an `errno` code, an optional function name, and an optional reason string.
///
/// `POSIXErrno` conforms to `Error` and provides a human-readable description via `strerror(3)`.
public struct POSIXErrno: Error {
  /// The `errno` code from the failed POSIX call.
  public let code: Int32
  /// The name of the function that failed, if provided.
  public let function : String?
  /// Additional context about why the failure occurred, if provided.
  public let reason : String?

  /// Creates a `POSIXErrno` from the given error code.
  ///
  /// - Parameters:
  ///   - code: The `errno` value. Defaults to the current `errno`.
  ///   - fn: The name of the failing function. Optional.
  ///   - reason: Additional context. Optional.
  public init(_ code: Int32 = errno, fn: String? = nil, reason: String? = nil) {
    self.code = code
    self.function = fn
    self.reason = reason
  }

  /// A human-readable description combining the function name, reason, and `strerror` text.
  public var description : String {
    let z = String(cString: strerror(code))
    if let function {
      if let reason {
        return "\(function) failed (\(reason)): \(z)"
      } else {
        return "\(function) failed: \(z)"
      }
    } else {
      if let reason {
        return "\(reason): \(z)"
      } else {
        return z
      }
    }
  }

  /// Same as ``description``.
  public var localizedDescription : String {
    return description
  }
}

/// The maximum filesystem path length on the current platform, as an `Int`.
public let MAXPATHLEN : Int = Int(Darwin.MAXPATHLEN)



/// Placeholder for device-type enumeration (reserved for future use).
public enum DeviceType {
}

/// BSD file flags (chflags/lchflags) represented as an `OptionSet`.
///
/// Mirrors the `UF_*` and `SF_*` constants from `<sys/stat.h>`.
public struct FileFlags: OptionSet, Sendable, Hashable {
  /// The raw bitmask value.
  public let rawValue: UInt32

  /// Creates a `FileFlags` from a raw bitmask.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// Creates an empty `FileFlags`.
  public init() { self.rawValue = 0 }

  /// Returns an array of individual flag values that are set in this value.
  public var allFlags : [FileFlags] {
    var res = [FileFlags]()
    for i in 0..<31 {
      if (rawValue & (1 << i)) != 0 {
        res.append(FileFlags(rawValue: 1 << i))
      }
    }
    return res
  }

  /// No flags set.
  public static let none = FileFlags([])
  /// Placeholder for a generic single-flag value.
  public static let someFlag = FileFlags(rawValue: 1 << 0)

  // Owner-changeable flags (UF_*)
  /// Do not dump this file.
  public static let UF_NODUMP       = Self(rawValue: 1 << 0)
  /// File may not be changed.
  public static let UF_IMMUTABLE    = Self(rawValue: 1 << 1)
  /// Writes to the file may only append.
  public static let UF_APPEND       = Self(rawValue: 1 << 2)
  /// Directory is opaque with respect to union mounts.
  public static let UF_OPAQUE       = Self(rawValue: 1 << 3)
  /// File is compressed (some file systems).
  public static let UF_COMPRESSED   = Self(rawValue: 1 << 5)
  /// Used for document-ID tracking; suppresses delete/rename notifications.
  public static let UF_TRACKED      = Self(rawValue: 1 << 6)
  /// Entitlement required for reading and writing.
  public static let UF_DATAVAULT    = Self(rawValue: 1 << 7)
  /// Item should not be displayed in a GUI.
  public static let UF_HIDDEN       = Self(rawValue: 1 << 8)

  // Super-user-changeable flags (SF_*)
  /// File is archived.
  public static let SF_ARCHIVED     = Self(rawValue: 1 << 16)
  /// File may not be changed (superuser).
  public static let SF_IMMUTABLE    = Self(rawValue: 1 << 17)
  /// Writes to file may only append (superuser).
  public static let SF_APPEND       = Self(rawValue: 1 << 18)
  /// Entitlement required for writing.
  public static let SF_RESTRICTED   = Self(rawValue: 1 << 19)
  /// Item may not be removed, renamed, or mounted on.
  public static let SF_NOUNLINK     = Self(rawValue: 1 << 20)
  /// File is a firmlink.
  public static let SF_FIRMLINK     = Self(rawValue: 1 << 23)
  /// File is a dataless object (read-only synthetic flag).
  public static let SF_DATALESS     = Self(rawValue: 1 << 30)

}


/// The type of a filesystem entry, derived from the `st_mode` field of `stat(2)`.
public enum FileType {
  /// A regular file.
  case regular
  /// A symbolic link.
  case symbolicLink
  /// A Unix domain socket.
  case socket
  /// A block-special device.
  case blockDevice
  /// A whiteout entry.
  case whiteOut
  /// A directory.
  case directory
  /// A character-special device.
  case characterDevice
  /// A named pipe (FIFO).
  case fifo
  /// An unrecognised or unknown file type.
  case unknown

  /// Creates a `FileType` from the raw `st_mode` value returned by `stat(2)`.
  ///
  /// - Parameter rawValue: The 16-bit mode word from `stat`.
  public init(rawValue: UInt16) {
    switch rawValue & S_IFMT {
      case S_IFREG: self = .regular
      case S_IFLNK: self = .symbolicLink
      case S_IFBLK: self = .blockDevice
      case S_IFSOCK: self = .socket
      case S_IFWHT: self = .whiteOut
      case S_IFDIR : self = .directory
      case S_IFCHR: self = .characterDevice
      case S_IFIFO: self = .fifo
      default: self = .unknown
    }
  }

  /// The raw `st_mode` constant for this type.
  public var rawValue: UInt16 { get {
    switch self {
      case .regular: return S_IFREG
      case .symbolicLink: return S_IFLNK
      case .blockDevice: return S_IFBLK
      case .socket: return S_IFSOCK
      case .whiteOut: return S_IFWHT
      case .directory: return S_IFDIR
      case .characterDevice: return S_IFCHR
      case .fifo: return S_IFIFO
      case .unknown: return 0
    }
  } }

}

/// A Swift value type wrapping the `stat(2)` structure returned by the kernel.
///
/// All timestamps are represented as ``DateTime`` values.
public struct FileMetadata {
  /// Device inode resides on.
  public var device : UInt
  /// Inode number.
  public var inode : UInt
  /// Protection mode bits.
  public var permissions: FilePermissions
  /// File type.
  public var filetype : FileType
  /// Number of hard links.
  public var links : UInt
  /// User ID of the owner.
  public var userId : UInt
  /// Group ID of the owner.
  public var groupId : UInt
  /// Device number for special files.
  public var rawDevice : UInt
  /// Time the file was created.
  public var whenCreated : DateTime
  /// Time of last access.
  public var lastAccessed : DateTime
  /// Time of last data modification.
  public var lastModified : DateTime
  /// Time of last status change.
  public var lastChanged : DateTime
  /// File size in bytes.
  public var size : UInt
  /// Number of blocks allocated.
  public var blocks : UInt
  /// Optimal I/O block size.
  public var blockSize : UInt
  /// User-defined file flags (see ``FileFlags``).
  public var flags : FileFlags
  /// File generation number.
  public var generation : UInt

  /// Initialises by calling `stat(2)` or `lstat(2)` on the given path.
  ///
  /// - Parameters:
  ///   - f: The path to stat.
  ///   - followSymlinks: When `true` (default), symlinks are followed via `stat(2)`;
  ///     when `false`, `lstat(2)` is used.
  /// - Throws: ``POSIXErrno`` on failure.
  public init(for f: FilePath, followSymlinks: Bool = true) throws(POSIXErrno) {
    var statbuf = Darwin.stat()
    let e = (followSymlinks ? stat : lstat)(f.string, &statbuf)
    try self.init(e == 0 ? 0 : errno, statbuf)
  }

  /// Initialises by calling `fstat(2)` on the given file descriptor.
  ///
  /// - Parameter f: An open file descriptor.
  /// - Throws: ``POSIXErrno`` on failure.
  public init(for f: FileDescriptor) throws(POSIXErrno) {
    var statbuf = Darwin.stat()
    let e = fstat(f.rawValue, &statbuf)
    try self.init(e == 0 ? 0 : errno, statbuf)
  }

  /// Initialises from an existing `stat` pointer (used by the FTS API).
  ///
  /// - Parameter from: Pointer to a valid `stat` struct.
  public init(from: UnsafePointer<stat>) {
    do {
      try self.init(0, from.pointee)
    } catch {
      fatalError("doesn't throw with errno 0")
    }
  }

  /// Private designated initialiser: populates all fields from a `stat` struct,
  /// or throws if `e` is non-zero.
  private init(_ e : Int32, _ statbuf : stat) throws(POSIXErrno) {
    if e != 0 {
      throw POSIXErrno(e)
    }
    device = UInt(UInt32(bitPattern: statbuf.st_dev))
    inode = UInt(statbuf.st_ino)
    permissions = FilePermissions(rawValue: statbuf.st_mode)
    filetype = FileType(rawValue: statbuf.st_mode)
    links = UInt(statbuf.st_nlink)
    rawDevice = UInt(UInt32(bitPattern: statbuf.st_rdev))
    userId = UInt(statbuf.st_uid)
    groupId = UInt(statbuf.st_gid)
    whenCreated  = DateTime.init(statbuf.st_birthtimespec)
    lastAccessed = DateTime(statbuf.st_atimespec)
    lastModified = DateTime(statbuf.st_mtimespec)
    lastChanged = DateTime(statbuf.st_ctimespec)
    size = UInt(statbuf.st_size)
    blocks = UInt(statbuf.st_blocks)
    blockSize = UInt(statbuf.st_blksize)
    flags = FileFlags(rawValue: statbuf.st_flags)
    generation = UInt(statbuf.st_gen)
  }
}


/// Path to the controlling terminal device (`/dev/tty`).
public let _PATH_TTY = "/dev/tty"
/// Path to the null device (`/dev/null`).
public let _PATH_DEVNULL = "/dev/null"

/// The type of access to test for with `access(2)`.
public enum AccessType : Int32 {
  /// Read access (`R_OK`).
  case read = 4
  /// Write access (`W_OK`).
  case write = 2
  /// Execute/search access (`X_OK`).
  case execute = 1
  /// Existence check (`F_OK`).
  case exist = 0
}

/// Checks whether the current process has the specified access to `path`.
///
/// - Parameters:
///   - path: The path to check.
///   - at: The type of access required.
/// - Throws: ``POSIXErrno`` if the access check fails.
public func haveAccess(_ path: String, _ at : AccessType) throws(POSIXErrno) {
  let j = access(path, at.rawValue )
  if j == 0 { return }
  throw POSIXErrno()
}


// ============================

/// Returns `true` when `m` represents a regular file.
///
/// - Parameter m: A raw `mode_t` value from `stat(2)`.
public func S_ISREG(_ m : mode_t) -> Bool {
  return (m & S_IFMT) == S_IFREG
}

/// Returns `true` when `m` represents a directory.
///
/// - Parameter m: A raw `mode_t` value from `stat(2)`.
public func S_ISDIR(_ m : mode_t) -> Bool {
  return (m & S_IFMT) == S_IFDIR
}

/// Returns `true` when `m` represents a character-special device.
///
/// - Parameter m: A raw `mode_t` value from `stat(2)`.
public func S_ISCHR(_ m : mode_t) -> Bool {
  return (m & S_IFMT) == S_IFCHR
}


/// Returns `true` if `candidate` is an executable regular file reachable by the current user.
///
/// - Parameter candidate: The absolute or relative path to test.
/// - Returns: `true` when the path is executable, `false` otherwise.
public func isThere(candidate: String) -> Bool {
  var fin = stat()

  return access(candidate, X_OK) == 0 && stat(candidate, &fin) == 0 && S_ISREG(fin.st_mode) && (getuid() != 0 || (fin.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0)
}

/// Searches `PATH` for an executable named `filename`.
///
/// If `filename` contains a `/`, it is returned immediately without searching.
///
/// - Parameter filename: The executable name or absolute path.
/// - Returns: The full path to the executable, or `nil` if not found.
public func searchPath(for filename: String) -> String? {
  var candidate = ""

  let path = Environment["PATH"] ?? _PATH_DEFPATH

  if filename.contains("/") {
    return filename
  }

  for dx in path.split(separator: ":") {
    let d = dx.isEmpty ? "." : dx
    candidate = "\(d)/\(filename)"
    if candidate.count >= PATH_MAX {
      continue
    }
    if isThere(candidate: candidate) {
      return candidate
    }
  }
  return nil
}

/// Reads the target of the symbolic link at `s`.
///
/// - Parameter s: The path to the symbolic link.
/// - Returns: The link target as a string.
/// - Throws: ``POSIXErrno`` if `readlink(2)` fails.
public func readlink(_ s : String) throws(POSIXErrno) -> String {
  var path = Array<UInt8>(repeating: 0, count: MAXPATHLEN+1)
  let lnklen = Darwin.readlink(s, &path, MAXPATHLEN)
  if lnklen == -1 {
    throw POSIXErrno(errno)
  }
  path[lnklen] = 0
  let r = String(decoding: path[..<Int(lnklen)], as: UTF8.self)
  return r
}

extension UnsafeMutablePointer<stat> {
  /// The seconds component of the last-status-change time (POSIX `st_ctime`).
  public var st_ctime : Int { pointee.st_ctimespec.tv_sec }
  /// The seconds component of the last-modification time (POSIX `st_mtime`).
  public var st_mtime : Int { pointee.st_mtimespec.tv_sec }
  /// The seconds component of the last-access time (POSIX `st_atime`).
  public var st_atime : Int { pointee.st_atimespec.tv_sec }
  /// The seconds component of the birth time (POSIX `st_birthtime`).
  public var st_birthtime : Int { pointee.st_birthtimespec.tv_sec }

  /// The last-status-change time as a `timespec`.
  public var st_ctim : timespec { pointee.st_ctimespec }
  /// The last-modification time as a `timespec`.
  public var st_mtim : timespec { pointee.st_mtimespec }
  /// The last-access time as a `timespec`.
  public var st_atim : timespec { pointee.st_atimespec }
  /// The birth time as a `timespec`.
  public var st_birthtim : timespec { pointee.st_birthtimespec }
}

extension stat {
  /// The seconds component of the last-status-change time (POSIX `st_ctime`).
  public var st_ctime : Int { st_ctimespec.tv_sec }
  /// The seconds component of the last-modification time (POSIX `st_mtime`).
  public var st_mtime : Int { st_mtimespec.tv_sec }
  /// The seconds component of the last-access time (POSIX `st_atime`).
  public var st_atime : Int { st_atimespec.tv_sec }
  /// The seconds component of the birth time (POSIX `st_birthtime`).
  public var st_birthtime : Int { st_birthtimespec.tv_sec }

  /// The last-status-change time as a `timespec`.
  public var st_ctim : timespec { st_ctimespec }
  /// The last-modification time as a `timespec`.
  public var st_mtim : timespec { st_mtimespec }
  /// The last-access time as a `timespec`.
  public var st_atim : timespec { st_atimespec }
  /// The birth time as a `timespec`.
  public var st_birthtim : timespec { st_birthtimespec }
}

/// Errors that can be thrown when a string encoding operation fails.
enum StringEncodingError : Error {
  /// The input contained a character that cannot be represented in the target encoding.
  case invalidCharacter
}


// =========================================================

public extension FilePath {
  /// Lists the names of all entries in this directory (excluding `.` and `..`).
  ///
  /// - Returns: An array of entry name strings.
  /// - Throws: ``POSIXErrno`` if `opendir(3)` or `readdir(3)` fails.
  func listDirectory() throws(POSIXErrno) -> [String] {
    let dirString = self.string

    guard let dp = opendir(dirString) else {
      throw POSIXErrno(fn: "opendir")
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

      if name == "." || name == ".." {
        continue
      }

      results.append(name)
      errno = 0
    }

    if errno != 0 {
      throw POSIXErrno(fn: "readdir")
    }

    return results
  }
}


public extension FileDescriptor {
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
}

// =============================================

public extension FileDescriptor {
  /// Reads all bytes from this descriptor and decodes them as a UTF-8 string.
  ///
  /// - Returns: The full contents as a `String`.
  /// - Throws: Any error from ``readAllBytes()``.
  func readAsString() throws -> String {
    let k = try readAllBytes()
    return String(decoding: k, as: UTF8.self)
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


}

public extension FilePath {
  /// Reads all bytes of this file and decodes them as a UTF-8 string.
  ///
  /// - Returns: The file contents as a `String`.
  /// - Throws: Any error from ``readAllBytes()``.
  func readAsString() throws -> String {
    let k = try readAllBytes()
    return String(decoding: k, as: UTF8.self)
  }

  /// Reads all bytes of this file.
  ///
  /// Uses `mmap(2)` for regular files (fast path) and falls back to a streaming
  /// read for pipes, devices, and other non-regular files.
  ///
  /// - Returns: A `[UInt8]` containing the full file contents.
  /// - Throws: Any `Errno` or ``POSIXErrno`` from the underlying calls.
  func readAllBytes() throws -> [UInt8] {
    if let mm = try? mmapRegularFile() {
      return mm
    }

    let fd = try FileDescriptor.open(self, .readOnly)
    defer { try? fd.close() }
    return try fd.readAllBytes()
  }

  // MARK: - mmap fast-path (regular files only)

  /// Returns the file contents via `mmap(2)`, copying them into a `[UInt8]`.
  ///
  /// Throws when the path does not refer to a regular file.
  private func mmapRegularFile() throws -> [UInt8] {
    try self.withPlatformString { cPath in
      let fd = Darwin.open(cPath, O_RDONLY)
      if fd < 0 { throw POSIXErrno(fn: "open") }
      defer { _ = Darwin.close(fd) }

      var st = Darwin.stat()
      if fstat(fd, &st) != 0 { throw POSIXErrno(fn: "fstat") }

      if (st.st_mode & S_IFMT) != S_IFREG {
        throw POSIXErrno(EINVAL, fn: "mmap", reason: "not a regular file")
      }

      if st.st_size == 0 { return [] }

      let length = Int(st.st_size)
      let mapped = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0)
      if mapped == MAP_FAILED { throw POSIXErrno(fn: "mmap") }
      defer { _ = munmap(mapped, length) }

      let ptr = mapped!.assumingMemoryBound(to: UInt8.self)
      return Array(UnsafeBufferPointer(start: ptr, count: length))
    }
  }
}


public extension FileDescriptor {
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
}

public extension FilePath {
  /// Sets the POSIX permission bits on this path.
  ///
  /// - Parameters:
  ///   - p: The desired permissions.
  ///   - followSymlinks: When `false` (default), `lchmod(2)` is used so the symlink
  ///     itself is changed rather than its target.
  /// - Throws: ``POSIXErrno`` if the chmod call fails.
  func setPermissions(_ p : FilePermissions, followSymlinks: Bool = false) throws(POSIXErrno) {
    let f = followSymlinks ? chmod : lchmod
    if 0 != f(self.string, p.rawValue) {
      throw POSIXErrno(fn: "setPermissions")
    }
  }

  /// Creates a symbolic link at this path pointing to `target`.
  ///
  /// - Parameter target: The path the symlink should point to.
  /// - Throws: ``POSIXErrno`` if `symlink(2)` fails.
  func createSymbolicLink(to target: FilePath) throws(POSIXErrno) {
    if 0 != symlink(target.string, self.string) {
      throw POSIXErrno(fn: "createSymbolicLink")
    }
  }

  /// Creates a hard link at this path pointing to `target`.
  ///
  /// Uses `linkat(2)` with `AT_SYMLINK_NOFOLLOW_ANY` so that a symlink as the final
  /// component of `target` is linked directly (not followed).
  ///
  /// - Parameter target: The existing file to link to.
  /// - Throws: ``POSIXErrno`` if `linkat(2)` fails.
  func createHardLink(to target: FilePath) throws(POSIXErrno) {
    do {
      let fds = try FileDescriptor.open(self.removingLastComponent().string, .readOnly, options: .directory)
      let fdt = try FileDescriptor.open(target.removingLastComponent().string, .readOnly, options: .directory)
      let tc = target.lastComponent
      let fc = self.lastComponent
      if 0 != Darwin.linkat(fdt.rawValue, tc?.string ?? "", fds.rawValue, fc?.string ?? "", Darwin.AT_SYMLINK_NOFOLLOW_ANY) {
        throw POSIXErrno(fn: "linkat")
      }
    } catch(let e as Errno) {
      throw POSIXErrno(e.rawValue, fn: "linkat")
    } catch(let e) {
      throw POSIXErrno(errno, fn: "linkat")
    }
  }

  /// Creates this path as a directory, creating intermediate components as needed.
  ///
  /// - Parameter pr: The permissions to apply to each created directory.
  /// - Throws: ``POSIXErrno`` if any `mkdir(2)` call fails.
  func createDirectory(_ pr : FilePermissions) throws(POSIXErrno) {
    var d = FilePath((self.root ?? FilePath.Root(".")).string)
    for p in self.components {
      d.append(p)
      if (try? FileMetadata(for: d))?.filetype == .directory { continue }
      if 0 != mkdir(d.string, pr.rawValue) {
        throw POSIXErrno(fn: "createDirectory")
      }
    }
  }

  /// Sets the access and modification timestamps of the file at this path.
  ///
  /// Passes `nil` for either parameter to leave that timestamp unchanged.  The symlink
  /// itself is updated (`AT_SYMLINK_NOFOLLOW`) rather than its target.
  ///
  /// - Parameters:
  ///   - modified: The new modification time, or `nil` to omit.
  ///   - accessed: The new access time, or `nil` to omit.
  /// - Throws: ``POSIXErrno`` if `utimensat(2)` fails.
  func setTimes(modified: DateTime? = nil, accessed: DateTime? = nil) throws(POSIXErrno) {
    let omit = timespec(tv_sec: 0, tv_nsec: Int(Darwin.UTIME_OMIT))
    var times : (timespec, timespec) = ( modified?.timespec ?? omit, accessed?.timespec ?? omit)
    if utimensat(AT_FDCWD, self.string, &times.0, AT_SYMLINK_NOFOLLOW ) != 0 {
      throw POSIXErrno(fn: "setTimes")
    }
  }

  /// Resolves this path to its canonical absolute path by calling `realpath(3)`.
  ///
  /// - Returns: The resolved canonical ``FilePath``.
  /// - Throws: ``POSIXErrno`` if `realpath(3)` fails.
  func realpath() throws(POSIXErrno) -> FilePath {
    let (r,e) : (String?, POSIXErrno?) = withUnsafeTemporaryAllocation(byteCount: Int(PATH_MAX), alignment: 1) {
      if let x = Darwin.realpath(self.string, $0.baseAddress) {
        return (String(cString: x), nil)
      }
      return (nil, POSIXErrno(fn: "realpath"))
    }
    if let r { return FilePath(r) }
    else { throw e! }
  }

}

public extension FilePath {
  /// Recursively removes this path and all of its contents.
  ///
  /// For regular files, symbolic links, and other non-directory types, calls `unlink(2)`.
  /// For directories, recursively removes children then calls `rmdir(2)`.
  ///
  /// - Throws: ``POSIXErrno`` if any removal step fails.
  func removeTree() throws(POSIXErrno) {
    guard let st = try? FileMetadata(for: self, followSymlinks: false) else {
      return
    }
    if st.filetype == .directory {
      let j = try self.listDirectory()
      for i in j {
        try self.appending(i).removeTree()
      }
      if rmdir(self.string) != 0 {
        throw POSIXErrno(fn: "rmdir")
      }
    } else {
      if unlink(self.string) != 0 {
        throw POSIXErrno(fn: "unlink")
      }
    }
  }
}


public extension FilePath {
  /// The last path component, following the same semantics as POSIX `basename(3)`.
  ///
  /// - An empty path returns `"."`.
  /// - A path of all slashes returns `"/"`.
  /// - Trailing slashes are stripped before extracting the component.
  var basename : String {
    if self.string.isEmpty {
      return "."
    }

    var ppath = Substring(self.string)

    while ppath.last == "/" {
      ppath = ppath.dropLast()
    }

    if ppath.isEmpty {
      return "/"
    }

    var res = Substring("")
    while !ppath.isEmpty && ppath.last != "/" {
      res.insert(ppath.last!, at: ppath.startIndex)
      ppath = ppath.dropLast()
    }

    return String(res)
  }


  /// The directory portion of this path, following the same semantics as POSIX `dirname(3)`.
  ///
  /// Uses `dirname_r(3)` when available; falls back to ``removingLastComponent()``.
  var dirname : FilePath {
    withUnsafeTemporaryAllocation(byteCount: MAXPATHLEN+1, alignment: 8) {
      if let d = Darwin.dirname_r(self.string, $0.baseAddress!) {
        return FilePath(platformString: d )
      } else {
        return self.removingLastComponent()
      }
    }
  }


  /// Returns the path of this file relative to `baseDirectory`.
  ///
  /// Uses `".."` components to ascend out of the common prefix, then descends
  /// into the target.  Returns `"."` when the paths are identical.
  ///
  /// - Parameter baseDirectory: The directory to which the result should be relative.
  /// - Returns: A relative path string.
  func relativeTo(_ baseDirectory: FilePath) -> String {
    func components(_ path: String) -> [Substring] {
      path.split(separator: "/", omittingEmptySubsequences: true)
    }

    let base = components(baseDirectory.string)
    let target = components(self.string)
    var common = 0
    while common < min(base.count, target.count),
          base[common] == target[common] {
      common += 1
    }
    let up = Array(repeating: "..", count: base.count - common)
    let down = target[common...].map(String.init)
    let result = up + down
    return result.isEmpty ? "." : result.joined(separator: "/")
  }

}

/// Renames `oldPath` to `newPath` using `rename(2)`.
///
/// - Parameters:
///   - oldPath: The current path.
///   - newPath: The desired new path.
/// - Throws: `Errno` if `rename(2)` fails.
public func posixRename(from oldPath: String, to newPath: String) throws {
    if rename(oldPath, newPath) != 0 {
      throw Errno(rawValue: errno)
    }
}
