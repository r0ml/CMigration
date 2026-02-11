// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


import SystemPackage
import Darwin

/// A tiny stdio-like wrapper around a FileDescriptor.
/// - Provides buffered reads (delimiter-based) and buffered writes.
/// - No Foundation required.
/// - Encoding is the caller's choice (bytes in / bytes out).
public struct FileStream {
    enum Ownership { case borrowed, owned }
    enum Mode { case read, write, readWrite }

    var fd: FileDescriptor
    let ownership: Ownership
//  let mode: FileDescriptor.AccessMode

    // Read buffering
    private var rbuf: [UInt8] = []
    private var eof = false

    // Write buffering
    private var wbuf: [UInt8] = []
    var writeBufferLimit: Int = 64 * 1024   // auto-flush threshold

  public init(_ fp : FilePath, mode: FileDescriptor.AccessMode = .readWrite) throws(POSIXErrno) {
    do {
      self.fd = try FileDescriptor.open(fp, mode)
  //    self.mode = mode
      self.ownership = .owned
    } catch(let e as Errno) {
      throw POSIXErrno(e.rawValue, fn: "open")
    } catch(let e) {
      throw POSIXErrno(errno == 0 ? EBADF : errno, fn: "open")
    }
  }

  public init(_ fd: FileDescriptor) {
    self.fd = fd
//        self.mode = mode
      self.ownership = .borrowed
    }

    mutating func close() throws {
        try flush()
        if ownership == .owned {
            try fd.close()
        }
    }

    // MARK: - Reading

    /// Read some bytes from the FD into the read buffer.
    /// Returns number of bytes read (0 = EOF).
    private mutating func fill(minimum: Int = 1) throws(POSIXErrno) -> Int {
        guard !eof else { return 0 }
      let (n, e) : (Int?, POSIXErrno?) = withUnsafeTemporaryAllocation(byteCount: 4096, alignment: 8) { tmp  in
        do {
          let n = try fd.read(into: tmp)
          if n == 0 { eof = true; return (0, nil) }
          rbuf.append(contentsOf: tmp[..<n])
          return (n, nil)
        } catch(let e as Errno) {
          return (nil, POSIXErrno(e.rawValue, fn: "read") )
        } catch(let e) {
          return (nil, POSIXErrno(EBADF, fn: "read", reason: "\(e)"))
        }
      }
      if let n {
        return n
      } else {
        throw e!
      }
    }

    /// Reads until `delimiter` is encountered.
    /// - Parameters:
    ///   - delimiter: byte delimiter (e.g. `0x0A` for '\n')
    ///   - includeDelimiter: whether returned data includes delimiter
    ///   - maxBytes: safety cap to prevent unbounded growth
    /// - Returns: bytes read, or nil on EOF with no pending data.
    public mutating func readUntil(
        _ delimiter: UInt8,
        includeDelimiter: Bool = false,
        maxBytes: Int = 8 * 1024 * 1024
    ) throws(POSIXErrno) -> [UInt8]? {
        while true {
            if let i = rbuf.firstIndex(of: delimiter) {
                let end = includeDelimiter ? rbuf.index(after: i) : i
                let out = Array(rbuf[..<end])
                rbuf.removeFirst(includeDelimiter ? (i + 1) : (i + 1)) // always consume delimiter
                return out
            }

            if eof {
                if rbuf.isEmpty { return nil }
                let out = rbuf
                rbuf.removeAll(keepingCapacity: true)
                return out
            }

            if rbuf.count >= maxBytes {
                // Similar to a "line too long" protection; tune for your use.
              throw POSIXErrno( E2BIG, fn: "readUntil" )
            }

            _ = try fill()
        }
    }

  // ==========================================================================

    /// `FILE*`-like `fgets`: reads a line terminated by '\n' (newline not included).
    public mutating func readLine(maxBytes: Int = 8 * 1024 * 1024) throws(POSIXErrno) -> [UInt8]? {
        return try readUntil(0x0A, includeDelimiter: false, maxBytes: maxBytes)
    }

    /// Read exactly `count` bytes unless EOF.
    mutating func readBytes(_ count: Int) throws(POSIXErrno) -> [UInt8]? {
      guard count >= 0 else { throw POSIXErrno(EINVAL, fn: "readBytes" ) }
        while rbuf.count < count && !eof {
            _ = try fill(minimum: count - rbuf.count)
        }
        if rbuf.isEmpty && eof { return nil }
        let n = min(count, rbuf.count)
        let out = Array(rbuf[..<n])
        rbuf.removeFirst(n)
        return out
    }

    // MARK: - Writing

    /// Buffer bytes for output (auto-flush at `writeBufferLimit`).
    public mutating func write(_ bytes: [UInt8]) throws(POSIXErrno) {
        wbuf.append(contentsOf: bytes)
        if wbuf.count >= writeBufferLimit {
            try flush()
        }
    }

    /// Convenience: write a single byte.
    public mutating func putc(_ byte: UInt8) throws(POSIXErrno) {
        wbuf.append(byte)
        if wbuf.count >= writeBufferLimit {
            try flush()
        }
    }

    /// Write bytes + '\n' (like `fputs` + newline).
    public mutating func writeLine(_ bytes: [UInt8]) throws(POSIXErrno) {
        try write(bytes)
        try putc(0x0A)
    }

    /// Flush buffered output (like `fflush`).
    public mutating func flush() throws(POSIXErrno) {
        guard !wbuf.isEmpty else { return }
        var total = 0
        while total < wbuf.count {
            let (n, e) = wbuf.withUnsafeBytes { raw -> (Int?, POSIXErrno?) in
                let base = raw.baseAddress!.advanced(by: total)
              do {
                  let n = try fd.write(UnsafeRawBufferPointer(start: base, count: wbuf.count - total))
                return (n, nil)
              } catch(let e as Errno) {
                return (nil, POSIXErrno(e.rawValue, fn: "write flush"))
              } catch(let e) {
                return (nil, POSIXErrno(EIO, fn: "write flush"))
              }
            }
          if let e {
            throw e
          }
          if n == 0 { throw POSIXErrno(EIO, fn: "write flush") } // should not happen for regular fds
          total += n!
        }
        wbuf.removeAll(keepingCapacity: true)
    }
}

// MARK: - Tiny helpers (no Foundation)

public extension FileStream {
    /// UTF-8 decode without Foundation.
    mutating func readLineUTF8(maxBytes: Int = 8 * 1024 * 1024) throws -> String? {
        guard let b = try readLine(maxBytes: maxBytes) else { return nil }
        return String(decoding: b, as: UTF8.self)
    }

    mutating func writeUTF8(_ s: String) throws {
        try write(Array(s.utf8))
    }

    mutating func writeLineUTF8(_ s: String) throws {
        try write(Array(s.utf8))
        try putc(0x0A)
    }
}
