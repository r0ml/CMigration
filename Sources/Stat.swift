// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import Darwin
import System

// #if compiler(<6.4)
// #if !canImport(FoundationModels)
// #if !canImport(Foundation, _version: "27.0")
  

public extension FilePath {
  func stat(followTargetSymlink: Bool = false) throws(Errno) -> Stat {
    do {
      return try Stat(for: self, followTargetSymlink: followTargetSymlink)
    } catch let e {
      throw Errno(rawValue: e.code)
    }
  }
}

// #if !canImport(Foundation, _version: "27.0")
public struct DeviceID : Equatable {
  public var rawValue: dev_t
  public init(_ d : dev_t) { self.rawValue = d }
}

public struct Inode : Equatable{
  public var rawValue: ino_t
  public init(_ d : ino_t) { self.rawValue = d }
}

public struct UserID : Equatable {
  public var rawValue: uid_t
  public init(_ d : uid_t) { self.rawValue = d }
}

public struct GroupID : Equatable {
  public var rawValue: gid_t
  public init(_ d : gid_t) { self.rawValue = d }
}

public struct FileMode : Equatable {
  public var rawValue: mode_t
  public init(_ d : mode_t) { self.rawValue = d }
}


/// A Swift value type wrapping the `stat(2)` structure returned by the kernel.
/// Obsolete in macOS 27.0 when Swift System added Stat
///
/// All timestamps are represented as ``DateTime`` values.
// @available(anyAppleOS, obsoleted: 27.0)
  public struct Stat {
    /// Device inode resides on.
    public var deviceID : DeviceID
    /// Inode number.
    public var inode : Inode
    /// Protection mode bits.
    public var permissions: FilePermissions
    /// File type.
    public var type : FileType
    /// Number of hard links.
    public var linkCount : Int
    /// User ID of the owner.
    public var userID : UserID
    /// Group ID of the owner.
    public var groupID : GroupID
    /// Device number for special files.
    public var specialDeviceID : DeviceID
    /// Time the file was created.
    public var st_birthtim : timespec
    /// Time of last access.
    public var st_atim : timespec
    /// Time of last data modification.
    public var st_mtim : timespec
    /// Time of last status change.
    public var st_ctim : timespec
    /// File size in bytes.
    public var size : UInt
    /// Number of blocks allocated.
    public var blocksAllocated : Int64
    /// Optimal I/O block size.
    public var blockSize : UInt
    /// User-defined file flags (see ``FileFlags``).
    public var flags : FileFlags
    /// File generation number.
    public var generationNumber : UInt64
    
    /// Initialises by calling `stat(2)` or `lstat(2)` on the given path.
    ///
    /// - Parameters:
    ///   - f: The path to stat.
    ///   - followTargetSymlink: When `true` (default), symlinks are followed via `stat(2)`;
    ///     when `false`, `lstat(2)` is used.
    /// - Throws: ``POSIXErrno`` on failure.
    public init(for f: FilePath, followTargetSymlink: Bool = true) throws(POSIXErrno) {
      var statbuf = Darwin.stat()
      let e = (followTargetSymlink ? stat : lstat)(f.string, &statbuf)
      try self.init(e == 0 ? 0 : errno, statbuf)
    }
    
    /// Initialises by calling `fstat(2)` on the given file descriptor.
    ///
    /// - Parameter f: An open file descriptor.
    /// - Throws: ``POSIXErrno`` on failure.
    public init(for f: FileDescriptor) throws(POSIXErrno) {
      var statbuf = Darwin.stat()
      let e = fstat(f.rawValue, &statbuf)
      try self.init(e == 0 ? 0 : errno, statbuf)
    }
    
    /// Initialises from an existing `stat` pointer (used by the FTS API).
    ///
    /// - Parameter from: Pointer to a valid `stat` struct.
    public init(rawValue: stat) {
      do {
        try self.init(0, rawValue)
      } catch {
        fatalError("doesn't throw with errno 0")
      }
    }
    
    /// Private designated initialiser: populates all fields from a `stat` struct,
    /// or throws if `e` is non-zero.
    private init(_ e : Int32, _ statbuf : stat) throws(POSIXErrno) {
      if e != 0 {
        throw POSIXErrno(e)
      }
      deviceID = DeviceID(statbuf.st_dev)
      inode = Inode(statbuf.st_ino)
      permissions = FilePermissions(rawValue: statbuf.st_mode)
      type = FileType(rawValue: statbuf.st_mode)
      linkCount = Int(statbuf.st_nlink)
      specialDeviceID = DeviceID(statbuf.st_rdev)
      userID = UserID(statbuf.st_uid)
      groupID = GroupID(statbuf.st_gid)
      st_birthtim  = statbuf.st_birthtimespec
      st_atim = statbuf.st_atimespec
      st_mtim = statbuf.st_mtimespec
      st_ctim = statbuf.st_ctimespec
      size = UInt(statbuf.st_size)
      blocksAllocated = Int64(statbuf.st_blocks)
      blockSize = UInt(statbuf.st_blksize)
      flags = FileFlags(rawValue: statbuf.st_flags)
      generationNumber = UInt64(statbuf.st_gen)
    }
  }

/// BSD file flags (chflags/lchflags) represented as an `OptionSet`.
///
/// Mirrors the `UF_*` and `SF_*` constants from `<sys/stat.h>`.
// @available(anyAppleOS, obsoleted: 27.0)
public struct FileFlags: OptionSet, Sendable, Hashable {
  /// The raw bitmask value.
  public let rawValue: UInt32

  /// Creates a `FileFlags` from a raw bitmask.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// Creates an empty `FileFlags`.
  public init() { self.rawValue = 0 }

   /// No flags set.
  public static let none = FileFlags([])
  /// Placeholder for a generic single-flag value.
  public static let someFlag = FileFlags(rawValue: 1 << 0)

  // Owner-changeable flags (UF_*)
  /// Do not dump this file.
  public static let noDump       = Self(rawValue: 1 << 0)
  /// File may not be changed.
  public static let userImmutable    = Self(rawValue: 1 << 1)
  /// Writes to the file may only append.
  public static let userAppend       = Self(rawValue: 1 << 2)
  /// Directory is opaque with respect to union mounts.
  public static let opaque       = Self(rawValue: 1 << 3)
  /// File is compressed (some file systems).
  public static let compressed   = Self(rawValue: 1 << 5)
  /// Used for document-ID tracking; suppresses delete/rename notifications.
  public static let UF_TRACKED      = Self(rawValue: 1 << 6)
  /// Entitlement required for reading and writing.
  public static let dataVault    = Self(rawValue: 1 << 7)
  /// Item should not be displayed in a GUI.
  public static let hidden       = Self(rawValue: 1 << 8)

  // Super-user-changeable flags (SF_*)
  /// File is archived.
  public static let archived     = Self(rawValue: 1 << 16)
  /// File may not be changed (superuser).
  public static let systemImmutable    = Self(rawValue: 1 << 17)
  /// Writes to file may only append (superuser).
  public static let systemAppend       = Self(rawValue: 1 << 18)
  /// Entitlement required for writing.
  public static let restricted   = Self(rawValue: 1 << 19)
  /// Item may not be removed, renamed, or mounted on.
  public static let systemNoUnlink     = Self(rawValue: 1 << 20)
  /// File is a firmlink.
  public static let SF_FIRMLINK     = Self(rawValue: 1 << 23)
  /// File is a dataless object (read-only synthetic flag).
  public static let dataless     = Self(rawValue: 1 << 30)

}


/// The type of a filesystem entry, derived from the `st_mode` field of `stat(2)`.
// @available(anyAppleOS, obsoleted: 27.0)
public enum FileType {
  /// A regular file.
  case regular
  /// A symbolic link.
  case symbolicLink
  /// A Unix domain socket.
  case socket
  /// A block-special device.
  case blockSpecial
  /// A whiteout entry.
  case whiteout
  /// A directory.
  case directory
  /// A character-special device.
  case characterSpecial
  /// A named pipe (FIFO).
  case fifo
  /// An unrecognised or unknown file type.
  case unknown

  /// Creates a `FileType` from the raw `st_mode` value returned by `stat(2)`.
  ///
  /// - Parameter rawValue: The 16-bit mode word from `stat`.
  public init(rawValue: UInt16) {
    switch rawValue & S_IFMT {
      case S_IFREG: self = .regular
      case S_IFLNK: self = .symbolicLink
      case S_IFBLK: self = .blockSpecial
      case S_IFSOCK: self = .socket
      case S_IFWHT: self = .whiteout
      case S_IFDIR : self = .directory
      case S_IFCHR: self = .characterSpecial
      case S_IFIFO: self = .fifo
      default: self = .unknown
    }
  }

  /// The raw `st_mode` constant for this type.
  public var rawValue: UInt16 { get {
    switch self {
      case .regular: return S_IFREG
      case .symbolicLink: return S_IFLNK
      case .blockSpecial: return S_IFBLK
      case .socket: return S_IFSOCK
      case .whiteout: return S_IFWHT
      case .directory: return S_IFDIR
      case .characterSpecial: return S_IFCHR
      case .fifo: return S_IFIFO
      case .unknown: return 0
    }
  } }

}


// #endif // compiler(<6.4)

public extension FileFlags {
  /// Returns an array of individual flag values that are set in this value.
  var allFlags : [FileFlags] {
    var res = [FileFlags]()
    for i in 0..<31 {
      if (rawValue & (1 << i)) != 0 {
        res.append(FileFlags(rawValue: 1 << i))
      }
    }
    return res
  }
}
