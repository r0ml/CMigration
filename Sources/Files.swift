
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
  public func lines(_ withEOL : Bool = false, encoding: IEncoding = .utf8) -> AsyncLineReader {
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
  var encoding : IEncoding = .utf8 //  any Unicode.Encoding.Type = UTF8.self

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
    var encoding : IEncoding = .utf8

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
      var line = try encoding.toString(buffer)
      /*
      
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
       */
      /*
      guard let line else {
        line = String(validating: buffer, as: ISOLatin1.self )
        buffer.removeAll()
        return line
      }
       */
      buffer.removeAll()
      return line
    }
  }

  /// Creates the async iterator for this line reader.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(byteIterator: byteStream.makeAsyncIterator(), retEOL: retEOL, encoding: encoding)
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
  public init(fd: FileDescriptor, bufferSize: Int = 4096, encoding: any Unicode.Encoding.Type = UTF8.self) {
    self.fd = fd
    self.bufferSize = bufferSize
  }

  /// The iterator type for ``AsyncCharacterReader``.
  public struct AsyncIterator: AsyncIteratorProtocol {
    let fd: FileDescriptor
    let bufferSize: Int
    let encoding : IEncoding // any Unicode.Encoding.Type
    
    var byteBuffer = [UInt8]()
    var characterIterator: String.Iterator?

    init(fd: FileDescriptor, bufferSize: Int, encoding: IEncoding = .utf8) {
      self.fd = fd
      self.bufferSize = bufferSize
      self.encoding = encoding
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
        var decoded : String
        do {
          decoded = try encoding.toString(Array(slice) )
        } catch let e as IconvError {
          if e == .incomplete {
            decodedCount -= 1
            continue
          } else {
            fatalError("string conversion error: \(e)")
          }
        } catch {
          fatalError("string conversion error: \(error)")
        }
        
        
        /*
        var decoded : String
        var reencoded : [UInt8]
        
        
        switch encoding {
          case is ISOLatin1.Type:
            decoded = String(decoding: slice, as: ISOLatin1.self)
            reencoded = Array(slice)
          case is UTF8.Type:
            fallthrough
          default:
            decoded = String(decoding: slice, as: UTF8.self)
            reencoded = Array(decoded.utf8)
        }
        
        if reencoded.count == decodedCount {
         */
          characterIterator = decoded.makeIterator()
          byteBuffer.removeFirst(decodedCount)
          return characterIterator?.next()
//        }

      }

      // Wait for more bytes to complete the encoding sequence
      return try await next()
    }
  }

  /// Creates the async iterator for this character reader.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(fd: fd, bufferSize: bufferSize)
  }
}


/*
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
*/


/// A typed POSIX error that captures an `errno` code, an optional function name, and an optional reason string.
///
/// `POSIXErrno` conforms to `Error` and provides a human-readable description via `strerror(3)`.
public struct POSIXErrno: Error, CustomStringConvertible, CustomDebugStringConvertible {
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
  
  public var debugDescription : String {
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
  case blockSpecial
  /// A whiteout entry.
  case whiteout
  /// A directory.
  case directory
  /// A character-special device.
  case characterSpecial
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
      case S_IFBLK: self = .blockSpecial
      case S_IFSOCK: self = .socket
      case S_IFWHT: self = .whiteout
      case S_IFDIR : self = .directory
      case S_IFCHR: self = .characterSpecial
      case S_IFIFO: self = .fifo
      default: self = .unknown
    }
  }

  /// The raw `st_mode` constant for this type.
  public var rawValue: UInt16 { get {
    switch self {
      case .regular: return S_IFREG
      case .symbolicLink: return S_IFLNK
      case .blockSpecial: return S_IFBLK
      case .socket: return S_IFSOCK
      case .whiteout: return S_IFWHT
      case .directory: return S_IFDIR
      case .characterSpecial: return S_IFCHR
      case .fifo: return S_IFIFO
      case .unknown: return 0
    }
  } }

}

/// A Swift value type wrapping the `stat(2)` structure returned by the kernel.
/// Obsolete in macOS 27.0 when Swift System added Stat
///
/// All timestamps are represented as ``DateTime`` values.
@available(anyAppleOS, obsoleted: 27.0)
  public struct FileMetadata {
    /// Device inode resides on.
    public var device : UInt
    /// Inode number.
    public var inode : UInt
    /// Protection mode bits.
    public var permissions: FilePermissions
    /// File type.
    public var type : FileType
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
      type = FileType(rawValue: statbuf.st_mode)
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
  var path = Array<Int8>(repeating: 0, count: MAXPATHLEN+1)
  let lnklen = Darwin.readlink(s, &path, MAXPATHLEN)
  if lnklen == -1 {
    throw POSIXErrno(errno)
  }
  path[lnklen] = 0
  let r = String(platformString: Array(path[...Int(lnklen)]))
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
