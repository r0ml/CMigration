// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import Darwin

public func getShell() -> String {
  let tmpShell = Environment["SHELL"]
  return tmpShell ?? _PATH_BSHELL
}

public struct Sysconf {
  public static var scArgMax : Int { return Darwin.sysconf(Darwin._SC_ARG_MAX) } // The maximum bytes of argument to execve(2).

/*
  _SC_CHILD_MAX The maximum number of simultaneous processes per user id.
  _SC_CLK_TCK The frequency of the statistics clock in ticks per second.
  _SC_IOV_MAX The maximum number of elements in the I/O vector used by readv(2), writev(2), recvmsg(2), and sendmsg(2).
 */

  public static var scNroupsMax : Int { return Darwin.sysconf(Darwin._SC_NGROUPS_MAX) } //  The maximum number of supplemental groups.
  public static var scNprocessorsConf : Int { return Darwin.sysconf(Darwin._SC_NPROCESSORS_CONF) } // The number of processors configured.
  public static var scNprocessorsOnln : Int { return Darwin.sysconf(Darwin._SC_NPROCESSORS_ONLN) } // The number of processors currently online.

  /*
  _SC_OPEN_MAX The maximum number of open files per user id.
  _SC_PAGESIZE The size of a system page in bytes.
  _SC_STREAM_MAX The minimum maximum number of streams that a process may have open at any one time.
  _SC_TZNAME_MAX The minimum maximum number of types supported for the name of a timezone.
  _SC_JOB_CONTROL Return 1 if job control is available on this system, otherwise -1.
  _SC_SAVED_IDS Returns 1 if saved set-group and saved set-user ID is available, otherwise -1.
  _SC_VERSION The version of IEEE Std 1003.1 (“POSIX.1”) with which the system attempts to comply.
  _SC_BC_BASE_MAX The maximum ibase/obase values in the bc(1) utility.
  _SC_BC_DIM_MAX The maximum array size in the bc(1) utility.
  _SC_BC_SCALE_MAX The maximum scale value in the bc(1) utility.
  _SC_BC_STRING_MAX The maximum string length in the bc(1) utility.
  _SC_COLL_WEIGHTS_MAX The maximum number of weights that can be assigned to any entry of the LC_COLLATE order keyword in the locale definition file.
  _SC_EXPR_NEST_MAX The maximum number of expressions that can be nested within parenthesis by the expr(1) utility.
  _SC_LINE_MAX The maximum length in bytes of a text-processing utility's input line.
  _SC_RE_DUP_MAX The maximum number of repeated occurrences of a regular expression permitted when using interval notation.
  _SC_2_VERSION The version of IEEE Std 1003.2 (“POSIX.2”) with which the system attempts to comply.
  _SC_2_C_BIND Return 1 if the system's C-language development facilities support the C-Language Bindings Option, otherwise -1.
  _SC_2_C_DEV Return 1 if the system supports the C-Language Development Utilities Option, otherwise -1.
  _SC_2_CHAR_TERM Return 1 if the system supports at least one terminal type capable of all operations described in IEEE Std 1003.2 (“POSIX.2”) otherwise -1.
  _SC_2_FORT_DEV Return 1 if the system supports the FORTRAN Development Utilities Option, otherwise -1.
  _SC_2_FORT_RUN Return 1 if the system supports the FORTRAN Runtime Utilities Option, otherwise -1.
  _SC_2_LOCALEDEF Return 1 if the system supports the creation of locales, otherwise -1.
  _SC_2_SW_DEV Return 1 if the system supports the Software Development Utilities Option, otherwise -1.
  _SC_2_UPE Return 1 if the system supports the User Portability Utilities Option, otherwise -1.

    These values also exist, but may not be standard:

  _SC_PHYS_PAGES The number of pages of physical memory. Note that it is possible that the product of this value and the value of _SC_PAGESIZE will overflow a (long) in some configurations on a 32bit machine.
*/
}

public struct Sysctl {
  public static func getString(_ name : String) throws(POSIXErrno) -> String {
    var s : Int = 0
    let (e , r ) : (POSIXErrno?, String?) = name.withCString { (nm : UnsafePointer<Int8>) -> (POSIXErrno?, String? ) in
      if Darwin.sysctlbyname(nm, nil, &s, nil, 0) == -1 {
        return (POSIXErrno(errno, fn: "sysctl: \(name)"), nil)
      }
      return withUnsafeTemporaryAllocation(byteCount: s, alignment: 1) { b in
        if sysctlbyname(nm, b.baseAddress, &s, nil, 0) == -1 {
          return (POSIXErrno(errno, fn: "sysctl: \(name)"), nil)
        }
        let k = b.baseAddress?.assumingMemoryBound(to: UInt8.self)
        return (nil, String(cString: k!))
      }
    }
    if let e { throw e }
    else { return r! }
  }

  public static func get<T>(_ name : String) throws(POSIXErrno) -> T {
    var s : Int = 0
    let (e , r ) : (POSIXErrno?, T?) = name.withCString { nm in
      return withUnsafeTemporaryAllocation(byteCount: MemoryLayout<T>.size, alignment: 16 ) { b in
        if sysctlbyname(nm, b.baseAddress, &s, nil, 0) == -1 {
          return (POSIXErrno(errno, fn: "sysctl: \(name)"), nil)
        }
        let k = b.load(as: T.self) // b.baseAddress?.assumingMemoryBound(to: T.self)
        return (nil, k)
      }
    }
    if let e { throw e }
    else { return r! }
  }

  public static func getArray<T>(_ name : String) throws(POSIXErrno) -> [T] {
    var s : Int = 0
    let (e , r ) = name.withCString { nm -> (POSIXErrno?, [T]?) in
      if Darwin.sysctlbyname(nm, nil, &s, nil, 0) == -1 {
        return (POSIXErrno(errno, fn: "sysctl: \(name)"), nil)
      }
      return withUnsafeTemporaryAllocation(byteCount: s, alignment: 16) { b in
        if sysctlbyname(nm, b.baseAddress, &s, nil, 0) == -1 {
          return (POSIXErrno(errno, fn: "sysctl: \(name)"), nil)
        }
        let k = b.load(as: [T].self) //  b.baseAddress?.assumingMemoryBound(to: UInt8.self)
        return (nil, k)
      }
    }
    if let e { throw e }
    else { return r! }
  }


}
