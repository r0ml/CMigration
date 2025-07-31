// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import Darwin
import Synchronization

public enum ComparisonResult: Int {
    case orderedAscending = -1
    case orderedSame = 0
    case orderedDescending = 1
}

final class Context {
  var fn : (@Sendable (FtsEntry, FtsEntry) -> ComparisonResult)? = nil
  var fe : FTSWalker? = nil
}

let globalContext = Mutex<Context>(Context())

// Sort FTS results in lexicographical order.
// from `find`
fileprivate func sort_shim(s1: UnsafeMutablePointer<UnsafePointer<FTSENT>?>?, s2: UnsafeMutablePointer<UnsafePointer<FTSENT>?>?) -> Int32 {
  let fe = globalContext.withLock { $0.fe }
  let a = FtsEntry(fe, s1!.pointee!)
  let b = FtsEntry(fe, s2!.pointee!)

  let fn = globalContext.withLock { $0.fn }
  switch fn!(a, b) {
    case .orderedAscending: return -1
    case .orderedDescending: return 1
    case .orderedSame: return 0
  }
}

fileprivate func get_sort_shim(_ fe : FTSWalker?, _ fn : ( @Sendable (FtsEntry, FtsEntry) -> ComparisonResult)?) -> (@convention(c) (UnsafeMutablePointer<UnsafePointer<FTSENT>?>?, UnsafeMutablePointer<UnsafePointer<FTSENT>?>?) -> Int32)? {
//  guard let fn else { return nil }
  globalContext.withLock { @Sendable in
      $0.fn = fn
  }
  return sort_shim
}

public enum FTSInfo : Int {
  case D       //  A directory being visited in pre-order.
  case DC      //  A directory that causes a cycle in the tree. (The fts_cycle field of the FTSENT structure will be filled in as well.)
  case DEFAULT //  Any FTSENT structure that represents a file type not explicitly described by one of the other fts_info values.
  case DNR     // A directory which cannot be read. This is an error return, and the fts_errno field will be set to indicate what caused the error.
  case DOT     // A file named .​ or ..​ which was not specified as a file name to fts_open() or fts_open_b() (see FTS_SEEDOT) .
  case DP      // A directory being visited in post-order. The contents of the FTSENT structure will be unchanged from when it was returned in pre-order, i.e. with the fts_info field set to FTS_D.
  case ERR     // This is an error return, and the fts_errno field will be set to indicate what caused the error.
  case F       // A regular file.
  case NS      // A file for which no stat(2) information was available. The contents of the fts_statp field are undefined. This is an error return, and the fts_errno field will be set to indicate what caused the error.
  case NSOK    // A file for which no stat(2) information was requested. The contents of the fts_statp field are undefined.
  case SL      // A symbolic link.
  case SLNONE  // A symbolic link with a non-existent target. The contents of the fts_statp field reference the file characteristic information for the symbolic link itself.
  case INVALID

  public init(_ x : Int) {
    switch Int32(x) {
      case FTS_D: self = Self.D
      case FTS_DC: self = Self.DC
      case FTS_DEFAULT: self = Self.DEFAULT
      case FTS_DNR: self = Self.DNR
      case FTS_DOT: self = Self.DOT
      case FTS_DP: self = Self.DP
      case FTS_ERR: self = Self.ERR
      case FTS_F: self = Self.F
      case FTS_NS: self = Self.NS
      case FTS_NSOK: self = Self.NSOK
      case FTS_SL: self = Self.SL
      default: self = Self.INVALID
    }
  }
}
public struct FTSFlags: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
  public static let empty = FTSFlags([])
  public static let COMFOLLOW = FTSFlags(rawValue: FTS_COMFOLLOW)
  public static let LOGICAL = FTSFlags(rawValue: FTS_LOGICAL)
  public static let NOCHDIR = FTSFlags(rawValue: FTS_NOCHDIR)
  public static let NOSTAT = FTSFlags(rawValue: FTS_NOSTAT)
  public static let PHYSICAL = FTSFlags(rawValue: FTS_PHYSICAL)
  public static let SEEDOT = FTSFlags(rawValue: FTS_SEEDOT)
  public static let XDEV = FTSFlags(rawValue: FTS_XDEV)
  public static let WHITEOUT = FTSFlags(rawValue: FTS_WHITEOUT)
  public static let COMFOLLOWDIR = FTSFlags(rawValue: FTS_COMFOLLOWDIR)
  public static let NOSTAT_TYPE = FTSFlags(rawValue: FTS_NOSTAT_TYPE)
  public static let OPTIONMASK = FTSFlags(rawValue: FTS_OPTIONMASK)
  public static let NAMEONLY = FTSFlags(rawValue: FTS_NAMEONLY)
  public static let STOP = FTSFlags(rawValue: FTS_STOP)
  public static let THEAD_FCHDIR = FTSFlags(rawValue: FTS_THREAD_FCHDIR)
}

public class FTSWalker: Sequence, IteratorProtocol {
    var fts: UnsafeMutablePointer<FTS>?
    private var finished = false
    private let rootPaths: [String]
    private let cPath: [UnsafeMutablePointer<CChar>?]

  public init(path: [String], options: FTSFlags = [.LOGICAL, .NOCHDIR], sort: (@Sendable (FtsEntry, FtsEntry) -> ComparisonResult)? = nil) throws(POSIXErrno) {
        self.rootPaths = path
    self.cPath = path.compactMap { strdup($0) }
        var paths: [UnsafeMutablePointer<CChar>?] = cPath + [nil]

    let fc = sort == nil ? nil : get_sort_shim(nil, sort!)
    self.fts = fts_open(&paths, options.rawValue, fc)
        if self.fts == nil {
          cPath.forEach { free($0) }
            throw POSIXErrno()
        }
    }

    public func next() -> FtsEntry? {
        guard let fts = self.fts, !finished else { return nil }

        guard let entry = fts_read(fts) else {
            fts_close(fts)
            self.fts = nil
            self.finished = true
            return nil
        }

      return FtsEntry(self, entry)
    }

    deinit {
        if let fts = fts {
            fts_close(fts)
        }
      cPath.forEach {
            free($0)
        }
    }
}

public enum FTSAction {
  case FOLLOW
  case SKIP
  case AGAIN

  var value : Int32 {
    switch self {
      case .FOLLOW: return FTS_FOLLOW
      case .SKIP: return FTS_SKIP
      case .AGAIN: return FTS_AGAIN
    }
  }
}

public struct FtsEntry {
  var fts : FTSWalker?
  var ent : UnsafePointer<FTSENT>
  var accpath : String
//  var cycle : Int32
  var dev : Int32
  var errno : Int32
  var flags : Int32
  var ino : UInt64
  var info : FTSInfo
  var instr : Int
  var level : Int
//  var link : UnsafeMutablePointer<FTSENT>?
  var name : String!
  var nlink : Int
  var number : Int
//  var parent : UnsafeMutablePointer<FTSENT>?
  var path : String
//  var pointer : UnsafeRawPointer?
  var statp : UnsafeMutablePointer<stat>?
  var symfd : Int

  init(_ fts : FTSWalker? = nil, _ ff : UnsafePointer<FTSENT>) {
    self.ent = ff
    self.fts = fts
    let f = ff.pointee
//    var f = fx.pointee
    self.accpath = String(cString: f.fts_accpath)
//    self.cycle = f.fts_cycle
    self.dev = f.fts_dev
    self.errno = f.fts_errno
    self.flags = Int32(f.fts_flags)
    self.ino = f.fts_ino
    self.info = FTSInfo(Int(f.fts_info))
    self.instr = Int(f.fts_instr)
    self.level = Int(f.fts_level)
//    self.link = f.fts_link
    self.nlink = Int(f.fts_nlink)



    self.number = f.fts_number
//    self.parent = f.fts_parent

    self.path = String(cString: f.fts_path)

 //   self.pointer = f.fts_pointer
    self.statp = f.fts_statp
    self.symfd = Int(f.fts_symfd)

    // AAARGH!  The definition of FTSENT (entry) defines the file name as a char[1] -- when in reality,
    // it is a string longer than 1.  passing this struct as an argument will cause the name to get lost.
    // so, before the memory beyond the defined end of the struct is tampered with, grab the fts_name from
    // the struct.

      let jk = UnsafeRawPointer(ff).advanced(by: MemoryLayout.offset(of: \FTSENT.fts_name)!)
      jk.withMemoryRebound(to: UInt8.self, capacity: Int(f.fts_namelen)) {jj in
        let buf = UnsafeBufferPointer(start: jj, count: Int(f.fts_namelen))
        let h = Array(buf)
        self.name = String(decoding: h, as: UTF8.self)
      }

  }

  mutating func setAction(_ action: FTSAction) {
    if let ff = fts?.fts { fts_set(ff, UnsafeMutablePointer(mutating: self.ent), action.value) }
  }
}



func listDirectory(at path: FilePath) throws -> [FilePath.Component] {
    var entries: [FilePath.Component] = []

    let dir = opendir(path.string)
    guard let stream = dir else {
        throw Errno(rawValue: errno)
    }
    defer { closedir(stream) }

    while let entry = readdir(stream) {
        let name = withUnsafePointer(to: entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX)) {
                String(cString: $0)
            }
        }
        if name != "." && name != ".." {
            entries.append(FilePath.Component(name)!)
        }
    }

    return entries
}


