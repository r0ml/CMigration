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
    return statBuf.fileType == .regular
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

public func fileExists(atPath: String) -> Bool {
  var statBuf = stat()
  return atPath.withCString { cPath in
    stat(cPath, &statBuf) == 0
  }
}

public func isExecutableFile(atPath: String) -> Bool {
  return atPath.withCString { cPath in
    access(cPath, X_OK) == 0
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

  @discardableResult public func write(_ data : [UInt8]) throws -> Int {
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

  public init(_ code: Int32 = errno) {
    self.code = code
  }

  public var description : String {
    return String(cString: strerror(code))
  }

  public var localizedDescription : String {
    return description
  }
}

public let MAXPATHLEN : Int = Int(Darwin.MAXPATHLEN)

public func basename(_ path : String) throws(POSIXErrno) -> String {
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

  if res.count >= MAXPATHLEN {
    throw POSIXErrno(ENAMETOOLONG)
  }

  return String(res)
}


public struct Passwd {
  public var name : String
  public var userId : Int
  public var groupId : Int
  public var home : String
  public var shell : String
  public var fullname : String
}
/**
 Retrieve passwd data for provided username.  Generated by ChatGPT
 */
public func getPasswd(for username: String) -> Passwd? {
  // Convert Swift string to C string
  return username.withPlatformString { cUsername -> Passwd? in
    var pwd = passwd()
    var result: UnsafeMutablePointer<passwd>? = nil
    let bufSize = sysconf(_SC_GETPW_R_SIZE_MAX)
    let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(bufSize))
    defer { buffer.deallocate() }

    let error = getpwnam_r(cUsername, &pwd, buffer, bufSize, &result)
    guard error == 0, result != nil else {
      return nil // user not found
    }

    let p = Passwd(name: String(cString: pwd.pw_name),
                   userId: Int(pwd.pw_uid),
                   groupId: Int(pwd.pw_gid),
                   home: String(cString: pwd.pw_dir),
                   shell: String(cString: pwd.pw_shell),
                   fullname: String(cString: pwd.pw_gecos),
    )
    return p
  }
}

/**
 Retrieve passwd data for provided userid.  Generated by ChatGPT
 */
public func getPasswd(of userid: Int) -> Passwd? {
  // Convert Swift string to C string
  var pwd = passwd()
  var result: UnsafeMutablePointer<passwd>? = nil
  let bufSize = sysconf(_SC_GETPW_R_SIZE_MAX)
  let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(bufSize))
  defer { buffer.deallocate() }

  let error = getpwuid_r(uid_t(userid), &pwd, buffer, bufSize, &result)
  guard error == 0, result != nil else {
    return nil // user not found
  }

  let p = Passwd(name: String(cString: pwd.pw_name),
                 userId: Int(pwd.pw_uid),
                 groupId: Int(pwd.pw_gid),
                 home: String(cString: pwd.pw_dir),
                 shell: String(cString: pwd.pw_shell),
                 fullname: String(cString: pwd.pw_gecos),
  )
  return p
}

public var userId : Int { Int(getuid()) }
public var userName : String { String(cString: getlogin()) }
public var groupId : Int { Int(getgid()) }
public var effectiveUserId : Int { Int(geteuid()) }
public var effectiveGroupId : Int { Int(getegid()) }

public struct GroupEntry {
  public var name : String
  public var groupId : Int
  public var members : [String]
}

public func getGroupEntry(of groupId: Int) -> GroupEntry? {
  // Convert Swift string to C string
  var gr = group()
  var result: UnsafeMutablePointer<group>? = nil
  let bufSize = sysconf(_SC_GETGR_R_SIZE_MAX)
  let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(bufSize))
  defer { buffer.deallocate() }

  let error = getgrgid_r(gid_t(groupId), &gr, buffer, bufSize, &result)
  guard error == 0, result != nil else {
    return nil // user not found
  }

  var members: [String] = []
  var memberPtr = gr.gr_mem

  while let ptr = memberPtr?.pointee {
    members.append(String(cString: ptr))
    memberPtr = memberPtr?.advanced(by: 1)
  }

  let p = GroupEntry(name: String(cString: gr.gr_name),
                     groupId: Int(gr.gr_gid),
                     members: members
  )
  return p
}

public func getGroupEntry(for groupname: String) -> GroupEntry? {
  // Convert Swift string to C string
  return groupname.withPlatformString { cGroupname -> GroupEntry? in
    var gr = group()
    var result: UnsafeMutablePointer<group>? = nil
    let bufSize = sysconf(_SC_GETGR_R_SIZE_MAX)
    let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(bufSize))
    defer { buffer.deallocate() }

    let error = getgrnam_r(cGroupname, &gr, buffer, bufSize, &result)
    guard error == 0, result != nil else {
      return nil // group not found
    }

    var members: [String] = []
    var memberPtr = gr.gr_mem

    while let ptr = memberPtr?.pointee {
      members.append(String(cString: ptr))
      memberPtr = memberPtr?.advanced(by: 1)
    }

    let p = GroupEntry(name: String(cString: gr.gr_name),
                       groupId: Int(gr.gr_gid),
                       members: members
    )
    return p
  }
}


public enum DeviceType {
}

public struct FileFlags: OptionSet, Sendable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public init() { self.rawValue = 0 }

  // Example flag values (if you have real flag values, replace or add)
  public static let none = FileFlags([])
  public static let someFlag = FileFlags(rawValue: 1 << 0)
  // Add more specific flags as needed.
}

public struct DateTime {
  public var secs : Int
  public var nanosecs : Int

  init(_ t : timespec) {
    secs = t.tv_sec
    nanosecs = t.tv_nsec
  }

  public var timeInterval : Double {
    Double(secs) + Double(nanosecs) / 1_000_000_000
  }

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

}

public struct FileMetadata {
  public var device : UInt               // device inode resides on
  public var inode : UInt                // inode's number
  public var mode : FilePermissions      // inode protection mode
  public var fileType : FileType             // file type
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
    try self.init(e, statbuf)
  }

  public init(for f: FileDescriptor) throws(POSIXErrno) {
    var statbuf = Darwin.stat()
    let e = fstat(f.rawValue, &statbuf)
    try self.init(e, statbuf)
  }

  public init?(from: UnsafePointer<stat>?) {
    guard from != nil else { return nil }
    do {
      try self.init(0, from!.pointee)
    } catch {
      fatalError("doesn't throw with errno 0")
    }
  }

  private init(_ e : Int32, _ statbuf : stat) throws(POSIXErrno) {
    if e != 0 {
      throw POSIXErrno(e)
    }
    device = UInt(statbuf.st_dev)
    inode = UInt(statbuf.st_ino)
    mode = FilePermissions(rawValue: statbuf.st_mode)
    fileType = FileType(rawValue: statbuf.st_mode)
    links = UInt(statbuf.st_nlink)
    rawDevice = UInt(statbuf.st_rdev)
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

