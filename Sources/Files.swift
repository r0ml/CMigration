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


// FIXME: do the swift-system version of this
/*
extension FileDescriptor.AsyncBytes {
  /// Asynchronously reads lines from the `AsyncBytes` stream.
  public var linesNLX : AsyncLineSequenceX<FileHandle.AsyncBytes> {
    return AsyncLineSequenceX(self)
  }
  
}
*/

import Darwin
@_exported import errno_h

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
    let code: Int32

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

public let MAXPATHLEN = Darwin.MAXPATHLEN

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
