// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import System
import Darwin

public extension FilePath {
  

  /// Returns `true` if the path refers to a regular file (not following symlinks).
  ///
  /// - Throws: ``POSIXErrno`` if `lstat(2)` fails.
  func isRegularFile() throws(POSIXErrno) -> Bool {
    if #available(anyAppleOS 27.0, *) {
      do {
        let statBuf = try self.stat(followTargetSymlink: false)
        return statBuf.type == .regular
      } catch(let e) {
        throw POSIXErrno(e.rawValue, fn: "stat", reason: string)
      }
    } else {
      let statBuf = try FileMetadata(for: self, followSymlinks: false)
      return statBuf.type == .regular
    }
  }

  /// Renames this path to `to`.
  ///
  /// - Parameter to: The destination path.
  /// - Throws: ``POSIXErrno`` if `rename(2)` fails.
  func rename(to: FilePath) throws(POSIXErrno) {
    let k = Darwin.rename(self.string, to.string)
    if k != 0 {
      throw POSIXErrno(k, fn: "rename")
    }
  }

  /// Returns `true` if the process has execute permission for this path.
  var isExecutable : Bool {
    return self.string.withPlatformString { cPath in
      access(cPath, X_OK) == 0
    }
  }

  /// Lists the names of all entries in this directory (excluding `.` and `..`).
  ///
  /// - Returns: An array of entry name strings.
  /// - Throws: ``POSIXErrno`` if `opendir(3)` or `readdir(3)` fails.
  func listDirectory() throws(POSIXErrno) -> [String] {
    let dirString = self.string

    guard let dp = opendir(dirString) else {
      throw POSIXErrno(fn: "opendir")
    }
    defer { closedir(dp) }

    var results: [String] = []
    results.reserveCapacity(64)

    errno = 0
    while let ent = readdir(dp) {
      let name = withUnsafePointer(to: &ent.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(cString: $0)
        }
      }

      if name == "." || name == ".." {
        continue
      }

      results.append(name)
      errno = 0
    }

    if errno != 0 {
      throw POSIXErrno(fn: "readdir")
    }

    return results
  }

  /// Reads all bytes of this file and decodes them as a UTF-8 string.
  ///
  /// - Returns: The file contents as a `String`.
  /// - Throws: Any error from ``readAllBytes()``.
  func readAsString(encoding: IEncoding = .utf8) throws -> String {
    let k = try readAllBytes()
    return try encoding.toString(k)
  }

  /// Reads all bytes of this file.
  ///
  /// Uses `mmap(2)` for regular files (fast path) and falls back to a streaming
  /// read for pipes, devices, and other non-regular files.
  ///
  /// - Returns: A `[UInt8]` containing the full file contents.
  /// - Throws: Any `Errno` or ``POSIXErrno`` from the underlying calls.
  func readAllBytes() throws -> [UInt8] {
    if let mm = try? mmapRegularFile() {
      return mm
    }

    let fd = try FileDescriptor.open(self, .readOnly)
    defer { try? fd.close() }
    return try fd.readAllBytes()
  }

  // MARK: - mmap fast-path (regular files only)

  /// Returns the file contents via `mmap(2)`, copying them into a `[UInt8]`.
  ///
  /// Throws when the path does not refer to a regular file.
  private func mmapRegularFile() throws -> [UInt8] {
    try self.withPlatformString { cPath in
      let fd = Darwin.open(cPath, O_RDONLY)
      if fd < 0 { throw POSIXErrno(fn: "open") }
      defer { _ = Darwin.close(fd) }

      var st = Darwin.stat()
      if fstat(fd, &st) != 0 { throw POSIXErrno(fn: "fstat") }

      if (st.st_mode & S_IFMT) != S_IFREG {
        throw POSIXErrno(EINVAL, fn: "mmap", reason: "not a regular file")
      }

      if st.st_size == 0 { return [] }

      let length = Int(st.st_size)
      let mapped = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0)
      if mapped == MAP_FAILED { throw POSIXErrno(fn: "mmap") }
      defer { _ = munmap(mapped, length) }

      let ptr = mapped!.assumingMemoryBound(to: UInt8.self)
      return Array(UnsafeBufferPointer(start: ptr, count: length))
    }
  }

  /// Sets the POSIX permission bits on this path.
  ///
  /// - Parameters:
  ///   - p: The desired permissions.
  ///   - followSymlinks: When `false` (default), `lchmod(2)` is used so the symlink
  ///     itself is changed rather than its target.
  /// - Throws: ``POSIXErrno`` if the chmod call fails.
  func setPermissions(_ p : FilePermissions, followSymlinks: Bool = false) throws(POSIXErrno) {
    let f = followSymlinks ? chmod : lchmod
    if 0 != f(self.string, p.rawValue) {
      throw POSIXErrno(fn: "setPermissions", reason: self.string)
    }
  }

  /// Creates a symbolic link at this path pointing to `target`.
  ///
  /// - Parameter target: The path the symlink should point to.
  /// - Throws: ``POSIXErrno`` if `symlink(2)` fails.
  func createSymbolicLink(to target: FilePath) throws(POSIXErrno) {
    if 0 != symlink(target.string, self.string) {
      throw POSIXErrno(fn: "createSymbolicLink", reason: self.string)
    }
  }

  /// Creates a hard link at this path pointing to `target`.
  ///
  /// Uses `linkat(2)` with `AT_SYMLINK_NOFOLLOW_ANY` so that a symlink as the final
  /// component of `target` is linked directly (not followed).
  ///
  /// - Parameter target: The existing file to link to.
  /// - Throws: ``POSIXErrno`` if `linkat(2)` fails.
  func createHardLink(to target: FilePath) throws(POSIXErrno) {
    do {
      let fds = try FileDescriptor.open(self.removingLastComponent().string, .readOnly, options: .directory)
      let fdt = try FileDescriptor.open(target.removingLastComponent().string, .readOnly, options: .directory)
      let tc = target.lastComponent
      let fc = self.lastComponent
      if 0 != Darwin.linkat(fdt.rawValue, tc?.string ?? "", fds.rawValue, fc?.string ?? "", Darwin.AT_SYMLINK_NOFOLLOW_ANY) {
        throw POSIXErrno(fn: "linkat")
      }
    } catch(let e as Errno) {
      throw POSIXErrno(e.rawValue, fn: "linkat")
    } catch(let e) {
      throw POSIXErrno(errno, fn: "linkat")
    }
  }

  /// Creates this path as a directory, creating intermediate components as needed.
  ///
  /// - Parameter pr: The permissions to apply to each created directory.
  /// - Throws: ``POSIXErrno`` if any `mkdir(2)` call fails.
  func createDirectory(_ pr : FilePermissions) throws(POSIXErrno) {
    var d = FilePath((self.root ?? FilePath.Root(".")).string)
    for p in self.components {
      d.append(p)
      if #available(anyAppleOS 27.0, *) {
        if (try? d.stat().type) == .directory { continue }
      } else {
        if (try? FileMetadata(for: d))?.type == .directory { continue }
      }
      if 0 != mkdir(d.string, pr.rawValue) {
        throw POSIXErrno(fn: "createDirectory")
      }
    }
  }

  /// Sets the access and modification timestamps of the file at this path.
  ///
  /// Passes `nil` for either parameter to leave that timestamp unchanged.  The symlink
  /// itself is updated (`AT_SYMLINK_NOFOLLOW`) rather than its target.
  ///
  /// - Parameters:
  ///   - modified: The new modification time, or `nil` to omit.
  ///   - accessed: The new access time, or `nil` to omit.
  /// - Throws: ``POSIXErrno`` if `utimensat(2)` fails.
  func setTimes(modified: DateTime? = nil, accessed: DateTime? = nil) throws(POSIXErrno) {
    let omit = timespec(tv_sec: 0, tv_nsec: Int(Darwin.UTIME_OMIT))
    var times : (timespec, timespec) = ( modified?.timespec ?? omit, accessed?.timespec ?? omit)
    if utimensat(AT_FDCWD, self.string, &times.0, AT_SYMLINK_NOFOLLOW ) != 0 {
      throw POSIXErrno(fn: "setTimes")
    }
  }

  /// Resolves this path to its canonical absolute path by calling `realpath(3)`.
  ///
  /// - Returns: The resolved canonical ``FilePath``.
  /// - Throws: ``POSIXErrno`` if `realpath(3)` fails.
  func realpath() throws(POSIXErrno) -> FilePath {
    let (r,e) : (String?, POSIXErrno?) = withUnsafeTemporaryAllocation(byteCount: Int(PATH_MAX), alignment: 1) {
      if let x = Darwin.realpath(self.string, $0.baseAddress) {
        return (String(cString: x), nil)
      }
      return (nil, POSIXErrno(fn: "realpath"))
    }
    if let r { return FilePath(r) }
    else { throw e! }
  }

  /// Recursively removes this path and all of its contents.
  ///
  /// For regular files, symbolic links, and other non-directory types, calls `unlink(2)`.
  /// For directories, recursively removes children then calls `rmdir(2)`.
  ///
  /// - Throws: ``POSIXErrno`` if any removal step fails.
  func removeTree() throws(POSIXErrno) {
    let isdir : Bool
    if #available(anyAppleOS 27.0, *) {
      guard let st = try? self.stat(followTargetSymlink: false) else {
        return
      }
      isdir = st.type == .directory
    } else {
      guard let st = try? FileMetadata(for: self, followSymlinks: false) else {
        return
      }
      isdir = st.type == .directory
    }
    if isdir {
      let j = try self.listDirectory()
      for i in j {
        try self.appending(i).removeTree()
      }
      if rmdir(self.string) != 0 {
        throw POSIXErrno(fn: "rmdir")
      }
    } else {
      if unlink(self.string) != 0 {
        throw POSIXErrno(fn: "unlink")
      }
    }
  }

  /// The last path component, following the same semantics as POSIX `basename(3)`.
  ///
  /// - An empty path returns `"."`.
  /// - A path of all slashes returns `"/"`.
  /// - Trailing slashes are stripped before extracting the component.
  var basename : String {
    if self.string.isEmpty {
      return "."
    }

    var ppath = Substring(self.string)

    while ppath.last == "/" {
      ppath = ppath.dropLast()
    }

    if ppath.isEmpty {
      return "/"
    }

    var res = Substring("")
    while !ppath.isEmpty && ppath.last != "/" {
      res.insert(ppath.last!, at: ppath.startIndex)
      ppath = ppath.dropLast()
    }

    return String(res)
  }


  /// The directory portion of this path, following the same semantics as POSIX `dirname(3)`.
  ///
  /// Uses `dirname_r(3)` when available; falls back to ``removingLastComponent()``.
  var dirname : FilePath {
    withUnsafeTemporaryAllocation(byteCount: MAXPATHLEN+1, alignment: 8) {
      if let d = Darwin.dirname_r(self.string, $0.baseAddress!) {
        return FilePath(platformString: d )
      } else {
        return self.removingLastComponent()
      }
    }
  }


  /// Returns the path of this file relative to `baseDirectory`.
  ///
  /// Uses `".."` components to ascend out of the common prefix, then descends
  /// into the target.  Returns `"."` when the paths are identical.
  ///
  /// - Parameter baseDirectory: The directory to which the result should be relative.
  /// - Returns: A relative path string.
  func relativeTo(_ baseDirectory: FilePath) -> String {
    func components(_ path: String) -> [Substring] {
      path.split(separator: "/", omittingEmptySubsequences: true)
    }

    let base = components(baseDirectory.string)
    let target = components(self.string)
    var common = 0
    while common < min(base.count, target.count),
          base[common] == target[common] {
      common += 1
    }
    let up = Array(repeating: "..", count: base.count - common)
    let down = target[common...].map(String.init)
    let result = up + down
    return result.isEmpty ? "." : result.joined(separator: "/")
  }

}

