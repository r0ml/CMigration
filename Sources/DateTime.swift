// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <r0ml@liberally.net> in 2026

import Darwin

public struct DateTime {
  public var secs : Int
  public var nanosecs : Int

  public init(_ t : Darwin.timespec) {
    secs = t.tv_sec
    nanosecs = t.tv_nsec
  }

  public init(_ t : any BinaryInteger) {
    secs = Int(t)
    nanosecs = 0
  }

  public init(_ t : Darwin.time_t) {
    secs = t
    nanosecs = 0
  }

  public var timeInterval : Double {
    Double(secs) + Double(nanosecs) / 1_000_000_000
  }

  public var timespec : Darwin.timespec {
    return Darwin.timespec(tv_sec: secs, tv_nsec: nanosecs)
  }

  public init(fromISO8601 s: String) throws {
    var tm = tm()
    memset(&tm, 0, MemoryLayout<tm>.size)

    let cstr = s.cString(using: .utf8)!

    // Try full date-time with optional 'Z'
    let formats = [
      "%Y-%m-%dT%H:%M:%SZ",
      "%Y-%m-%dT%H:%M:%S",
      "%Y-%m-%d"
    ]

    var parsed = false
    for fmt in formats {
      if strptime(cstr, fmt, &tm) != nil {
        parsed = true
        break
      }
    }

    guard parsed else {
      throw POSIXErrno(EINVAL, fn: "parsing ISO8601 date string")
    }

    // Force UTC
    tm.tm_isdst = 0

    let seconds = timegm(&tm)
    guard seconds >= 0 else {
      throw POSIXErrno(EINVAL, fn: "parsing ISO8601 date string")
    }

    self.init(seconds)
  }



}



