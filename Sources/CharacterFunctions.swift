// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import Foundation

extension FileHandle.AsyncBytes {
  /// Asynchronously reads lines from the `AsyncBytes` stream.
  public var linesNLX : AsyncLineSequenceX<FileHandle.AsyncBytes> {
    return AsyncLineSequenceX(self)
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
    var encoding : String.Encoding = .utf8
    
    public init(_ base : Base.AsyncIterator, encoding : String.Encoding = .utf8) {
      self._base = base
      self._peek = nil
      
      let k = setlocale(LC_CTYPE, nil)
      let kk = String(cString: k!)
      let kkk = kk.split(separator: ".").last ?? "C"
      
      // FIXME: map other encodings properly
      let ase = String.availableStringEncodings
      switch kkk {
        case "C": self.encoding = .isoLatin1
        case "UTF-8": self.encoding = .utf8
        default: self.encoding = .utf8
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
        return String(bytes: _buffer, encoding: self.encoding)
        //              return _buffer
      } else {
        return nil
      }
    }
    
  }
  
  let base: Base
  let encoding : String.Encoding
  
  public init(_ base: Base, encoding: String.Encoding = .utf8) {
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

public func regerror(_ n : Int32, _ regx : regex_t )  -> String {
  var re = regx
  let s = withUnsafeMutablePointer(to: &re) { rr in
     regerror(n, rr, nil, 0)
  }
  
  var p = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: s) { b in
    withUnsafeMutablePointer(to: &re) {rr in
      let j = regerror(n, rr, b.baseAddress!, s)
      return String(cString: b.baseAddress!)
    }
  }
  return p
}

public func posixRename(from oldPath: String, to newPath: String) throws {
    if rename(oldPath, newPath) != 0 {
        // If an error occurs, capture it using errno
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }
}

/// Calculates the display width of a character.
/// Swift does not have a direct equivalent to C's `wcwidth`, so we provide a basic implementation.
public func wcwidth(_ ch: Character) -> Int {
  // Simplified: Most characters occupy width 1. You can enhance this with more accurate width calculations if needed.
  let scalars = String(ch).unicodeScalars
  for scalar in scalars {
    if scalar.properties.isIdeographic {
      return 2
    }
  }
  return 1
}

/// Determines the display width of a Unicode character.
/// - Parameter wc: The Unicode scalar to measure.
/// - Returns: The width of the character in column positions.
/*
func wcwidth(_ wc: Unicode.Scalar) -> Int {
  // Simplified version: Most characters occupy width 1.
  // You can enhance this function to handle wide characters appropriately.
  if wc.properties.isEmoji {
    return 2
  } else if wc.properties.generalCategory == .control {
    return 0
  } else {
    return 1
  }
}
*/


/// Returns `true` if the given Unicode scalar is considered printable.
/// - Parameter scalar: A UnicodeScalar to test.
/// - Returns: A Boolean value that is `true` if the scalar is printable.
public func iswprint(_ char: Character) -> Bool {
    // For ASCII, only characters between space (0x20) and tilde (0x7E) are printable.
  let scalars = char.unicodeScalars
  if scalars.count > 1 { return true }
  let scalar = scalars.first!
    if scalar.isASCII {
      return scalar.value >= 0x20 && scalar.value <= 0x7E
    } else {
        // For non-ASCII characters, we consider the scalar printable if its Unicode
        // general category is not one of the following:
        //   - Control (.control)
        //   - Format (.format)
        //   - Surrogate (.surrogate)
        //   - Private Use (.privateUse)
        //   - Unassigned (.unassigned)
      if scalar.value < 256 { return false }
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned:
            return false
        default:
            return true
        }
    }
}
