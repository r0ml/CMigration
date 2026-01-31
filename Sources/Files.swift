// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025
// from a files containing the following notices:

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
  public func isRegularFile() throws -> Bool {
    let statBuf = try FileMetadata(for: self.string)
    return statBuf.filetype == .regular
  }
}

extension FileDescriptor {
  public var isRegularFile : Bool {
    var sbp = stat()
    if fstat(self.rawValue, &sbp) != 0 {
      return false
    }
    return (sbp.st_mode & S_IFMT) == S_IFREG
  }
}


extension FileDescriptor {
  public var bytes : AsyncByteStream { get  { AsyncByteStream(fd: self) } }
  public var characters : AsyncCharacterReader { get { AsyncCharacterReader(fd: self) } }

  public init(forReading: String) throws {
    self = try Self.open(forReading, .readOnly)
  }

  public init(forWriting: String) throws {
    self = try Self.open(forWriting, .writeOnly)
  }

  public init(forUpdating: String) throws {
    self = try Self.open(forUpdating, .readWrite)
  }


}

public struct AsyncByteStream: AsyncSequence {
  public typealias Element = UInt8
  let fd: FileDescriptor
  let bufferSize: Int = 4096

  public var lines : AsyncLineReader { get { AsyncLineReader(byteStream: self) } }
  public func lines(_ withEOL : Bool = false, encoding: any Unicode.Encoding.Type = UTF8.self) -> AsyncLineReader {
    return AsyncLineReader(byteStream: self, retEOL:  withEOL, encoding: encoding)
  }
  //  public var linesNLX : AsyncLineSequenceX { get { AsyncLineSequenceX(base: self) } }

  public struct AsyncIterator: AsyncIteratorProtocol {
    let fd: FileDescriptor
    var buffer = [UInt8]()
    var index = 0
    let bufferSize: Int

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

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(fd: fd, bufferSize: bufferSize)
  }
}




/// A reimplementation of Swifts AsyncLineSequence in order to support legacy C command semantics.
/// These include:
///     - including the newline character as part of the result (to distinguish end-of-file-with-no-eol situations
///     - supporting different encodings (other than UTF-8)
///     - supporting different line endings
/*
 public struct AsyncLineSequenceX<Base>: AsyncSequence
 where Base: AsyncSequence, Base.Element == UInt8 {

 /// The type of element produced by this asynchronous sequence.
 public typealias Element = String

 /// The type of asynchronous iterator that produces elements of this
 /// asynchronous sequence.
 public struct AsyncIterator: AsyncIteratorProtocol {
 public typealias Element = String

 var _base: Base.AsyncIterator
 var _peek: UInt8?
 var encoding : any Unicode.Encoding.Type = UTF8.self

 public init(_ base : Base.AsyncIterator, encoding : any Unicode.Encoding.Type = UTF8.self ) {
 self._base = base
 self._peek = nil

 // FIXME: Tahoe gets rid of setlocale?
 // let k = setlocale(LC_CTYPE, nil)
 // let kk = String(cString: k!)
 // let kkk = kk.split(separator: ".").last ?? "C"

 // FIXME: map other encodings properly
 // let ase = String.availableStringEncodings
 // switch kkk {
 //  case "C": self.encoding =   ISOLatin1.self
 //  case "UTF-8": self.encoding = UTF8.self
 //  default: self.encoding = UTF8.self
 // }

 }

 /// Asynchronously advances to the next element and returns it, or ends
 /// the sequence if there is no next element.
 ///
 /// - Returns: The next element, if it exists, or `nil` to signal the
 ///            end of the sequence.
 public mutating func next() async rethrows -> Element? {
 var _buffer = [UInt8]()

 func nextByte() async throws -> UInt8? {
 if let peek = self._peek {
 self._peek = nil
 return peek
 }
 let k = try await self._base.next()
 return k
 }

 loop: while let first = try await nextByte() {
 switch first {
 // FIXME: handle \r\n line endings...
 case 0x0A:
 _buffer.append(first)
 break loop
 default:
 _buffer.append(first)
 }
 }


 // Don't return an empty line when at end of file
 if !_buffer.isEmpty {
 //        return String(bytes: _buffer, encoding: self.encoding)
 var j : String
 if self.encoding == ISOLatin1.self {
 j = String(decoding: _buffer, as: ISOLatin1.self)
 } else if self.encoding == UTF8.self {
 j =  String(decoding: _buffer, as: UTF8.self)
 } else {
 j =  String(decoding: _buffer, as: UTF8.self)
 }
 return j
 //              return _buffer
 } else {
 return nil
 }
 }

 }

 let base: Base
 let encoding : any Unicode.Encoding.Type

 public init(_ base: Base, encoding: any Unicode.Encoding.Type = UTF8.self ) {
 self.base = base
 self.encoding = encoding
 }

 /// Creates the asynchronous iterator that produces elements of this
 /// asynchronous sequence.
 ///
 /// - Returns: An instance of the `AsyncIterator` type used to produce
 ///            elements of the asynchronous sequence.
 public func makeAsyncIterator() -> AsyncIterator {
 return AsyncIterator(self.base.makeAsyncIterator(), encoding: encoding)
 }
 }
 */

public struct AsyncLineReader: AsyncSequence {
  public typealias Element = String
  let byteStream: AsyncByteStream
  var retEOL = false
  var encoding : any Unicode.Encoding.Type = UTF8.self

  public mutating func withEOL() -> Self {
    retEOL = true
    return self
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    var byteIterator: AsyncByteStream.AsyncIterator
    var buffer = [UInt8]()
    var retEOL = false
    var encoding : any Unicode.Encoding.Type = UTF8.self

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

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(byteIterator: byteStream.makeAsyncIterator(), retEOL: retEOL, encoding: encoding)
  }
}

public extension FilePath {
  var exists : Bool {
    var statBuf = stat()
    return self.string.withPlatformString { cPath in
      stat(cPath, &statBuf) == 0
    }
  }

  var isExecutable : Bool {
    return self.string.withPlatformString { cPath in
      access(cPath, X_OK) == 0
    }
  }
}


extension FileDescriptor {
  public func readUpToCount(_ count: Int) throws -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: count)

    let bytesRead = try buffer.withUnsafeMutableBytes {
      try self.read(into: $0)
    }

    return Array(buffer.prefix(bytesRead))
  }

  @discardableResult public func write<S:Sequence>(_ data : S) throws -> Int where S.Element == UInt8  {
    try self.writeAll(data)
  }
}



extension FileDescriptor: @retroactive TextOutputStream {
  public func write(_ string: String) {
    let _ = try? self.writeAll( Array(string.utf8) )
  }
}


public struct AsyncCharacterReader: AsyncSequence {
  public typealias Element = Character
  public let fd: FileDescriptor
  public let bufferSize: Int

  public init(fd: FileDescriptor, bufferSize: Int = 4096) {
    self.fd = fd
    self.bufferSize = bufferSize
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    let fd: FileDescriptor
    let bufferSize: Int

    var byteBuffer = [UInt8]()
    var characterIterator: String.Iterator?

    init(fd: FileDescriptor, bufferSize: Int) {
      self.fd = fd
      self.bufferSize = bufferSize
    }

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

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(fd: fd, bufferSize: bufferSize)
  }
}



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

  // Decode as UTF-8
  return String(decoding: content, as: UTF8.self)
}

public extension FileDescriptor {
  /// Reads all bytes from the file until EOF.
  /// - Parameter chunkSize: The size of each read operation (default: 4096 bytes).
  /// - Returns: A `[UInt8]` array containing the full contents.
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


public struct POSIXErrno: Error {
  public let code: Int32
  public let function : String?
  public let reason : String?

  public init(_ code: Int32 = errno, fn: String? = nil, reason: String? = nil) {
    self.code = code
    self.function = fn
    self.reason = reason
  }

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

  public var localizedDescription : String {
    return description
  }
}

public let MAXPATHLEN : Int = Int(Darwin.MAXPATHLEN)

public func basename(_ path : String) -> String {
  // Empty string gets treated as "."
  if path.isEmpty {
    return "."
  }

  var ppath = Substring(path)

  // Strip any trailing slashes
  while ppath.last == "/" {
    ppath = ppath.dropLast()
  }

  // All slashes becomes "/"
  if ppath.isEmpty {
    return "/"
  }

  // Find the start of the base
  var res = Substring("")
  while !ppath.isEmpty && ppath.last != "/" {
    res.insert(ppath.last!, at: ppath.startIndex)
    ppath = ppath.dropLast()
  }

  /*
  if res.count >= MAXPATHLEN {
    throw POSIXErrno(ENAMETOOLONG)
  }
*/

  return String(res)
}



public enum DeviceType {
}

public struct FileFlags: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public init() { self.rawValue = 0 }

  public var allFlags : [FileFlags] {
    var res = [FileFlags]()
    for i in 0..<31 {
      if (rawValue & (1 << i)) != 0 {
        res.append(FileFlags(rawValue: 1 << i))
      }
    }
    return res
  }

  // Example flag values (if you have real flag values, replace or add)
  public static let none = FileFlags([])
  public static let someFlag = FileFlags(rawValue: 1 << 0)
  // Add more specific flags as needed.


  /*
   * Definitions of flags stored in file flags word.
   *
   * Super-user and owner changeable flags.
   */
//  public static let SETTABLE     0x0000ffff      /* mask of owner changeable flags */
  public static let UF_NODUMP       = Self(rawValue: 1 << 0)      /* do not dump file */
  public static let UF_IMMUTABLE    = Self(rawValue: 1 << 1)      /* file may not be changed */
  public static let UF_APPEND       = Self(rawValue: 1 << 2)      /* writes to file may only append */
  public static let UF_OPAQUE       = Self(rawValue: 1 << 3)      /* directory is opaque wrt. union */
  /*
   * The following bit is reserved for FreeBSD.  It is not implemented
   * in Mac OS X.
   */
  /* #define UF_NOUNLINK  0x00000010 */  /* file may not be removed or renamed */
  public static let UF_COMPRESSED   = Self(rawValue: 1 << 5)      /* file is compressed (some file-systems) */

  /* UF_TRACKED is used for dealing with document IDs.  We no longer issue
   *  notifications for deletes or renames for files which have UF_TRACKED set. */
  public static let UF_TRACKED      = Self(rawValue: 1 << 6)

  public static let UF_DATAVAULT    = Self(rawValue: 1 << 7)     /* entitlement required for reading */
                                          /* and writing */

  /* Bits 0x0100 through 0x4000 are currently undefined. */
  public static let UF_HIDDEN       = Self(rawValue: 1 << 8)     /* hint that this item should not be */
                                          /* displayed in a GUI */
  /*
   * Super-user changeable flags.
   */
//  #define SF_SUPPORTED    0x009f0000      /* mask of superuser supported flags */
//  #define SF_SETTABLE     0x3fff0000      /* mask of superuser changeable flags */
//  public static let SYNTHETIC    0xc0000000      /* mask of system read-only synthetic flags */
  public static let SF_ARCHIVED     = Self(rawValue: 1 << 16)      /* file is archived */
  public static let SF_IMMUTABLE    = Self(rawValue: 1 << 17)      /* file may not be changed */
  public static let SF_APPEND       = Self(rawValue: 1 << 18)      /* writes to file may only append */
  public static let SF_RESTRICTED   = Self(rawValue: 1 << 19)      /* entitlement required for writing */
  public static let SF_NOUNLINK     = Self(rawValue: 1 << 20)      /* Item may not be removed, renamed or mounted on */

  /*
   * The following two bits are reserved for FreeBSD.  They are not
   * implemented in Mac OS X.
   */
  /* #define SF_SNAPSHOT  0x00200000 */  /* snapshot inode */
  /* NOTE: There is no SF_HIDDEN bit. */

  public static let SF_FIRMLINK     = Self(rawValue: 1 << 23)      /* file is a firmlink */

  /*
   * Synthetic flags.
   *
   * These are read-only.  We keep them out of SF_SUPPORTED so that
   * attempts to set them will fail.
   */
  public static let SF_DATALESS     = Self(rawValue: 1 << 30)     /* file is dataless object */

}


public enum FileType {
  case regular
  case symbolicLink
  case socket
  case blockDevice
  case whiteOut
  case directory
  case characterDevice
  case fifo
  case unknown

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

public struct FileMetadata {
  public var device : UInt               // device inode resides on
  public var inode : UInt                // inode's number
  public var permissions: FilePermissions    // inode protection mode
  public var filetype : FileType             // file type
  public var links : UInt                // number of hard links to the file
  public var userId : UInt               // user-id of owner
  public var groupId : UInt              // group-id of owner
  public var rawDevice : UInt            // device for special file inode
  public var created : DateTime          // creation time
  public var lastAccess : DateTime       // time of last access
  public var lastWrite : DateTime        // time of last data modification
  public var lastModification : DateTime // time of last file status change
  public var size : UInt                 // file size, in bytes
  public var blocks : UInt               // blocks allocated for file
  public var blockSize : UInt            // optimal file sys I/O ops blocksize
  public var flags : FileFlags           // user defined flags for file
  public var generation : UInt           // file generation number

  public init(for f: String, followSymlinks: Bool = true) throws(POSIXErrno) {
    var statbuf = Darwin.stat()
    let e = (followSymlinks ? stat : lstat)(f, &statbuf)
    try self.init(e == 0 ? 0 : errno, statbuf)
  }

  public init(for f: FileDescriptor) throws(POSIXErrno) {
    var statbuf = Darwin.stat()
    let e = fstat(f.rawValue, &statbuf)
    try self.init(e == 0 ? 0 : errno, statbuf)
  }

  public init(from: UnsafePointer<stat>) {
    do {
      try self.init(0, from.pointee)
    } catch {
      fatalError("doesn't throw with errno 0")
    }
  }

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
    created  = DateTime.init(statbuf.st_birthtimespec)
    lastAccess = DateTime(statbuf.st_atimespec)
    lastWrite = DateTime(statbuf.st_mtimespec)
    lastModification = DateTime(statbuf.st_ctimespec)
    size = UInt(statbuf.st_size)
    blocks = UInt(statbuf.st_blocks)
    blockSize = UInt(statbuf.st_blksize)
    flags = FileFlags(rawValue: statbuf.st_flags)
    generation = UInt(statbuf.st_gen)
  }
}


public let _PATH_TTY = "/dev/tty"
public let _PATH_DEVNULL = "/dev/null"

public enum AccessType : Int32 {
  case read = 4
  case write = 2
  case execute = 1
  case exist = 0
}

public func haveAccess(_ path: String, _ at : AccessType) throws(POSIXErrno) {
  let j = access(path, at.rawValue )
  if j == 0 { return }
  throw POSIXErrno()
}


// ============================

public func S_ISREG(_ m : mode_t) -> Bool {
  return (m & S_IFMT) == S_IFREG
}
public func S_ISDIR(_ m : mode_t) -> Bool {
  return (m & S_IFMT) == S_IFDIR     /* directory */
}

public func S_ISCHR(_ m : mode_t) -> Bool {
  return (m & S_IFMT) == S_IFCHR     /* char special */
}


public func isThere(candidate: String) -> Bool {
  var fin = stat()

  return access(candidate, X_OK) == 0 && stat(candidate, &fin) == 0 && S_ISREG(fin.st_mode) && (getuid() != 0 || (fin.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0)
}

/// Find the executable in the path
public func searchPath(for filename: String) -> String? {
  var candidate = ""

  let path = Environment["PATH"] ?? _PATH_DEFPATH //   "/usr/bin:/bin"

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

public func readlink(_ s : String) throws(POSIXErrno) -> String {
  var path = Array<UInt8>(repeating: 0, count: MAXPATHLEN+1)
  let lnklen = Darwin.readlink(s, &path, MAXPATHLEN)
  if lnklen == -1 {
    throw POSIXErrno(errno)
  }
  path[lnklen] = 0
  let r = String(decoding: path[..<Int(lnklen)], as: UTF8.self)
  return r
  /*
   name = withUnsafeTemporaryAllocation(byteCount: Int(PATH_MAX), alignment: 1) { p -> String? in
     let pp = p.assumingMemoryBound(to: UInt8.self).baseAddress!
     let len = readlink(entry.accpath, pp , Int(PATH_MAX) - 1)
     if (len == -1) {
       return nil
     } else {
//          let k = Data(bytes: pp, count: len)
       return String(decoding: UnsafeBufferPointer(start: pp, count: len), as: Unicode.ASCII.self)
     }
   }
   */
}

extension UnsafeMutablePointer<stat> {
  public var st_ctime : Int { pointee.st_ctimespec.tv_sec }
  public var st_mtime : Int { pointee.st_mtimespec.tv_sec }
  public var st_atime : Int { pointee.st_atimespec.tv_sec }
  public var st_birthtime : Int { pointee.st_birthtimespec.tv_sec }

  public var st_ctim : timespec { pointee.st_ctimespec }
  public var st_mtim : timespec { pointee.st_mtimespec }
  public var st_atim : timespec { pointee.st_atimespec }
  public var st_birthtim : timespec { pointee.st_birthtimespec }
}

extension stat {
  public var st_ctime : Int { st_ctimespec.tv_sec }
  public var st_mtime : Int { st_mtimespec.tv_sec }
  public var st_atime : Int { st_atimespec.tv_sec }
  public var st_birthtime : Int { st_birthtimespec.tv_sec }

  public var st_ctim : timespec { st_ctimespec }
  public var st_mtim : timespec { st_mtimespec }
  public var st_atim : timespec { st_atimespec }
  public var st_birthtim : timespec { st_birthtimespec }
}

enum StringEncodingError : Error {
  case invalidCharacter
}


// =========================================================

// ============================================


public extension FilePath {
  func listDirectory() throws -> [String] {
    // opendir wants a C string path
    let dirString = self.string

    guard let dp = opendir(dirString) else {
      throw POSIXErrno(fn: "opendir")
    }
    defer { closedir(dp) }

    var results: [String] = []
    results.reserveCapacity(64)

    errno = 0
    while let ent = readdir(dp) {
      // d_name is a fixed-size CChar array; treat it as a C string
      let name = withUnsafePointer(to: &ent.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(cString: $0)
        }
      }

//      if !includeDotEntries, (name == "." || name == "..") {
//        continue
//      }

      // Build a child path: dir/<name>
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
  func listDirectory() throws -> [String] {
    // opendir wants a C string path

    guard let dp = fdopendir(rawValue) else {
      throw POSIXErrno(fn: "fdopendir")
    }
    defer { closedir(dp) }

    var results: [String] = []
    results.reserveCapacity(64)

    errno = 0
    while let ent = readdir(dp) {
      // d_name is a fixed-size CChar array; treat it as a C string
      let name = withUnsafePointer(to: &ent.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(cString: $0)
        }
      }

//      if !includeDotEntries, (name == "." || name == "..") {
//        continue
//      }

      // Build a child path: dir/<name>
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

// FIXME: Need to harmonize  'readUpToCount', 'readToEnd', and 'readAllBytes'
extension FileDescriptor {
  /// Read all bytes from an already-open FD (files/pipes/sockets).
  /// This is always streaming (mmap doesn’t apply).
  public func readAllBytes() throws -> [UInt8] {
      var out: [UInt8] = []
      out.reserveCapacity(8192)

      var buf = [UInt8](repeating: 0, count: 64 * 1024)

      while true {
        // Optional cancellation check (won't interrupt a blocked read in progress,
        // but will stop promptly between reads).
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

  public func writeAllBytes(_ bytes: [UInt8]) throws {
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
                  // Shouldn't happen for a pipe write unless something is very wrong.
                throw POSIXErrno(EPIPE, fn: "write")
              }
              written += n
          }
  }


}

public extension FilePath {
  func readAsString() throws -> String {
    let k = try readAllBytes()
    return String(decoding: k, as: UTF8.self)
  }

  /// Read all bytes from a filesystem path.
  /// Fast path: mmap for regular files.
  /// Fallback: async streaming (works for everything open/read supports).
  func readAllBytes() throws -> [UInt8] {
    // Try mmap first. If it fails for any reason, fallback.
    if let mm = try? mmapRegularFile() {
      return mm
    }

    // Fallback: open + async streaming read.
    let fd = try FileDescriptor.open(self, .readOnly)
    defer { try? fd.close() }
    return try fd.readAllBytes()
  }

    // MARK: - mmap fast-path (regular files only)

    /// Returns bytes via mmap if `path` is a regular file; otherwise throws.
    /// This copies once into `[UInt8]` (still typically faster than read loop for large regular files).
    private func mmapRegularFile() throws -> [UInt8] {
        try self.withPlatformString { cPath in
            let fd = Darwin.open(cPath, O_RDONLY)
          if fd < 0 { throw POSIXErrno(fn: "open") }
            defer { _ = Darwin.close(fd) }

            var st = stat()
          if fstat(fd, &st) != 0 { throw POSIXErrno(fn: "fstat") }

            // Only try mmap for regular files. Pipes/sockets/devices will fail or be meaningless.
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
  func setPermissions(_ p : FilePermissions) throws {
    if 0 != fchmod(self.rawValue, p.rawValue) {
      throw POSIXErrno(fn: "setPermissions")
    }
  }

  func setTimes(modified: DateTime? = nil, accessed: DateTime? = nil) throws {
    let omit = timespec(tv_sec: 0, tv_nsec: Int(Darwin.UTIME_OMIT))
    var times : (timespec, timespec) = ( modified?.timespec ?? omit, accessed?.timespec ?? omit)
    if futimens( self.rawValue, &times.0) != 0 {
      throw POSIXErrno(fn: "setTimes")
    }
  }
}

public extension FilePath {
  func setPermissions(_ p : FilePermissions) throws {
    if 0 != chmod(self.string, p.rawValue) {
      throw POSIXErrno(fn: "setPermissions")
    }
  }

  func createSymbolicLink(to target: FilePath) throws {
    if 0 != symlink(target.string, self.string) {
      throw POSIXErrno(fn: "createSymbolicLink")
    }
  }

  func setTimes(modified: DateTime? = nil, accessed: DateTime? = nil) throws {
    let omit = timespec(tv_sec: 0, tv_nsec: Int(Darwin.UTIME_OMIT))
    var times : (timespec, timespec) = ( modified?.timespec ?? omit, accessed?.timespec ?? omit)
    if utimensat(AT_FDCWD, self.string, &times.0, AT_SYMLINK_NOFOLLOW ) != 0 {
      throw POSIXErrno(fn: "setTimes")
    }
  }

}
