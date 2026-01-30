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
}

