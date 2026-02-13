// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <r0ml@liberally.net> in 2026

import Darwin

public struct DateTime : Comparable {
  public static func < (lhs: DateTime, rhs: DateTime) -> Bool {
    if lhs.secs < rhs.secs { return true }
    if lhs.secs == rhs.secs {
      if lhs.nanosecs < rhs.nanosecs { return true }
    }
    return false
  }

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

  public init() {
    var ts = Darwin.timespec()
    clock_gettime(CLOCK_REALTIME, &ts) // != 0 { perror("clock_gettime") }
    secs = ts.tv_sec        // time_t
    nanosecs = ts.tv_nsec   // long
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

    // Try full date-time with optional 'Z'
    let formats = [
      "%Y-%m-%dT%H:%M:%SZ",
      "%Y-%m-%dT%H:%M:%S",
      "%Y-%m-%d"
    ]

    var parsed = false
    for fmt in formats {
      if strptime(s, fmt, &tm) != nil {
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


  public static func + (lhs: DateTime, rhs: Int) -> DateTime {
    DateTime(Darwin.timespec(tv_sec: lhs.secs + rhs, tv_nsec: lhs.nanosecs))
  }

  public static func - (lhs: DateTime, rhs: Int) -> DateTime {
    DateTime(Darwin.timespec(tv_sec: lhs.secs - rhs, tv_nsec: lhs.nanosecs))
  }

}



