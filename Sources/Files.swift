// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025


// FIXME: do the swift-system version of this
/*
extension FileDescriptor.AsyncBytes {
  /// Asynchronously reads lines from the `AsyncBytes` stream.
  public var linesNLX : AsyncLineSequenceX<FileHandle.AsyncBytes> {
    return AsyncLineSequenceX(self)
  }
  
}
*/

extension FileDescriptor {
  public var bytes : AsyncByteStream { get  { AsyncByteStream(fd: self) } }
  
  public init?(forReadingAtPath: String) {
    if let z = try? Self.open(forReadingAtPath, .readOnly) {
      self = z
    } else {
      return nil
    }
  }
  
  public init?(forWritingAtPath: String) {
    if let z = try? Self.open(forWritingAtPath, .writeOnly) {
      self = z
    } else {
      return nil
    }
  }
  
  public init?(forUpdatingAtPath: String) {
    if let z = try? Self.open(forUpdatingAtPath, .readWrite) {
      self = z
    } else {
      return nil
    }
  }

  
}

public struct AsyncByteStream: AsyncSequence {
    public typealias Element = UInt8
    let fd: FileDescriptor
    let bufferSize: Int = 4096

  public var lines : AsyncLineReader { get { AsyncLineReader(byteStream: self) } }
  
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
      
      let k = setlocale(LC_CTYPE, nil)
      let kk = String(cString: k!)
      let kkk = kk.split(separator: ".").last ?? "C"
      
      // FIXME: map other encodings properly
      // let ase = String.availableStringEncodings
      switch kkk {
        case "C": self.encoding =   ISOLatin1.self
        case "UTF-8": self.encoding = UTF8.self
        default: self.encoding = UTF8.self
      }

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

public struct AsyncLineReader: AsyncSequence {
    public typealias Element = String
    let byteStream: AsyncByteStream

    public struct AsyncIterator: AsyncIteratorProtocol {
        var byteIterator: AsyncByteStream.AsyncIterator
        var buffer = [UInt8]()

        public mutating func next() async throws -> String? {
            while let byte = try await byteIterator.next() {
                if byte == UInt8(ascii: "\n") {
                    let line = String(decoding: buffer, as: UTF8.self)
                    buffer.removeAll()
                    return line
                } else {
                    buffer.append(byte)
                }
            }

            if !buffer.isEmpty {
                let line = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll()
                return line
            }

            return nil
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(byteIterator: byteStream.makeAsyncIterator())
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
  
  public func write(_ data : [UInt8]) throws -> Int {
    try withUnsafeBytes(of: data) {
      try self.write($0)
    }
  }
}
