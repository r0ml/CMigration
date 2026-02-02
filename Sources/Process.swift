// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import SystemPackage
import Darwin

import os

let logger = Logger(subsystem: "CMigration", category: "Process")

func log(_ message: String) {
  logger.info("\(message)")
}

func log(_ message: POSIXErrno) -> POSIXErrno {
  logger.error("\(message.localizedDescription)")
  return message
}

public struct Environment {
  /// Return the value of the environment variable given as argument.  Return `nil` if the environment variable is not set
/*  public static func getenv(_ name: String) -> String? {
    if let a = Darwin.getenv(name) {
      return String(cString: a)
    } else {
      return nil
    }
  }
*/
  
  public static subscript(_ name : String) -> String? {
    get {if let a = Darwin.getenv(name) {
      return String(cString: a)
    } else {
      return nil
    }
    }
    set {
      if let newValue {
        Darwin.setenv(name, newValue, 1)
      } else {
        Darwin.unsetenv(name)
      }
    }
  }

  /// Return  a dictionary mapping environment variable names to values
  public static func getenv() -> [String:String] {
    var env = [String: String]()

    var ptr = environ
    while let current = ptr.pointee {
      if let entry = String(validatingCString: current) {
        if let equalIndex = entry.firstIndex(of: "=") {
          let key = String(entry[..<equalIndex])
          let value = String(entry[entry.index(after: equalIndex)...])
          env[key] = value
        }
      }
      ptr = ptr.advanced(by: 1)
    }
    return env
  }

  /// Set the environment variable specified by @arg name to the value specified by @arg value.`
  /// A subscript `set` specifier cannot throw -- so I need a separate function
  public static func setenv(_ name : String, _ value: String) throws(POSIXErrno) {
    let k = Darwin.setenv(name, value, 1)
    if k == -1 {
      throw POSIXErrno(fn: "setenv")
    }
  }

  /// Unset the environment variable @arg name
  public static func unsetenv(_ name : String) throws(POSIXErrno) {
    let k = Darwin.unsetenv(name)
    if k == -1 {
      throw POSIXErrno(fn: "unsetenv")
    }
  }

  /*
  /// Return the name of the currently executing command
  public static var progname : String {
    let k = String(cString: getprogname())
    return k
  }
   */
}

public protocol Stdinable : Sendable {}
extension String : Stdinable {}
extension Substring : Stdinable {}
extension [UInt8] : Stdinable {}
extension FileDescriptor : Stdinable {}
extension AsyncStream : Stdinable {}
extension FilePath : Stdinable {}

public protocol Arguable : Sendable {
  func asStringArgument() -> String
}
extension Substring : Arguable {
  public func asStringArgument() -> String { return String(self) }
}
extension String : Arguable {
  public func asStringArgument() -> String { return self }
}
extension FilePath : Arguable {
  public func asStringArgument() -> String { return self.string }
}


extension FileDescriptor {
  func setCloexec() {
    let flags = Darwin.fcntl(self.rawValue, F_GETFD)
    _ = fcntl(self.rawValue, F_SETFD, flags | FD_CLOEXEC)
  }
}

public actor DarwinProcess {

  public struct Output : Sendable {
    public let code : Int32
    public let data : [UInt8]
    public let error : String

    public var string : String { String(decoding: data, as: UTF8.self) }
  }


  public var pid : pid_t = 0
  var stdinWriteFDForParent: FileDescriptor? = nil

  var stdoutR : FileDescriptor? = nil
  var stderrR : FileDescriptor? = nil
  var feederTask : Task<Void, Error>? = nil
  var readerTask : Task<[UInt8], Error>? = nil
  var errorTask : Task<String, Error>? = nil

  var actions: posix_spawn_file_actions_t? = nil
  var attr: posix_spawnattr_t? = nil
  var awaitingValue = false
  var launched = false

  public init() {}

  /*
   // An alternative to using Stdinable; make an enum of possible ways to pass stdin
   public enum StandardInput: Sendable {
   case inherit
   case string(String)
   case bytes([UInt8])
   case fileDescriptor(FileDescriptor)
   case filePath(FilePath)
   case byteStream(AsyncStream<[UInt8]>)
   }
   */

  public static func launch(
    _ executablePath: String,
    withStdin: (any Stdinable)? = nil,
    args arguments: any Arguable...,
    env : [String : String] = [:],
    cd : FilePath? = nil,
    captureOutput: Bool = true
  ) async throws(POSIXErrno) -> DarwinProcess {
    let p = DarwinProcess()
    let _ = try await p.launch(executablePath, withStdin: withStdin, args: arguments, env: env, cd: cd, captureOutput: captureOutput)
    return p
  }

  public func launch(
    _ executablePath: String,
    withStdin: (any Stdinable)? = nil,
    args arguments: any Arguable...,
    env : [String : String] = [:],
    cd : FilePath? = nil,
    captureOutput: Bool = true
  ) throws(POSIXErrno) -> pid_t {
    return try launch(executablePath, withStdin: withStdin, args: arguments, env: env, cd: cd, captureOutput: captureOutput)
  }

  /// - Parameters:
  ///   - stdin: If non-nil, bytes are written to the child process stdin and then stdin is closed.
  public func launch(
    _ execu: String,
    withStdin: (any Stdinable)? = nil,
    args arguments: [any Arguable] = [],
    env : [String : String] = [:],
    cd : FilePath? = nil,
    captureOutput: Bool = true
  ) throws(POSIXErrno) -> pid_t {
    // Pipes for stdout/stderr (always captured)
    if launched { fatalError("already launched once") }
    launched = true

    guard let executablePath = searchPath(for: execu) else {
      throw POSIXErrno(2, fn: "launching process")
    }

    // FIXME: as a life-cycle matter, only one "launch" per instance is allowed.
    // also, only "value" per instance is allowed (and it must folow "launch"

    var stdoutW : FileDescriptor? = nil
    var stderrW : FileDescriptor

    if captureOutput {
      do {
        (stdoutR, stdoutW) = try FileDescriptor.pipe()
      } catch(let e as Errno) {
        throw log(POSIXErrno(e.rawValue, fn: "pipe", reason: "creating stdout pipe"))
      } catch(let e) {
        throw log(POSIXErrno(-1, fn: "pipe", reason: "creating stdout pipe: \(e)"))
      }
    }

    do {
      (stderrR, stderrW) = try FileDescriptor.pipe()
    } catch(let e as Errno) {
      throw log(POSIXErrno(e.rawValue, fn: "pipe", reason: "creating stderr pipe"))
    } catch(let e) {
      throw log(POSIXErrno(-1, fn: "pipe", reason: "creating stderr pipe: \(e)"))
    }


    // Not needed on Darwin because of SPAWN_CLOEXEC -- but needed on other platforms
    stderrR?.setCloexec()
    stderrW.setCloexec()
    stdoutR?.setCloexec()
    stdoutW?.setCloexec()





    // posix_spawn file actions are optional-opaque on Darwin in Swift
    let irc = posix_spawn_file_actions_init(&actions)
    if irc != 0 {
      throw log(POSIXErrno(irc, fn: "posix_spawn_file_actions_init"))
    }

    var openedStdinFDToCloseInParent: FileDescriptor? = nil

    switch withStdin {

      case is FilePath:
        let fp = withStdin as! FilePath
        do {
          let fd = try FileDescriptor.open(fp, .readOnly)
          openedStdinFDToCloseInParent = fd
          try addDup2AndClose(&actions, from: fd.rawValue, to: STDIN_FILENO, closeSourceInChild: false)
        } catch(let e as Errno) {
          throw log(POSIXErrno(e.rawValue, fn: "open(\(fp))", reason: "setting stdin to FilePath"))
        } catch(let e) {
          throw log(POSIXErrno(-1, fn: "open(\(fp))", reason: "setting stdin to FilePath: \(e)"))
        }
      case is FileDescriptor:
        do {
          let fd = withStdin as! FileDescriptor
          try addDup2AndClose(&actions, from: fd.rawValue, to: STDIN_FILENO, closeSourceInChild: false)
        } catch(let e as Errno) {
          throw log(POSIXErrno(e.rawValue, reason: "setting stdin to FileDescriptor" ))
        } catch(let e) {
          throw log(POSIXErrno(-1, reason: "setting stdin to FileDescriptor: \(e)"))
        }
      case is Substring, is String, is [UInt8], is AsyncStream<[UInt8]>:
        do {
          (openedStdinFDToCloseInParent, stdinWriteFDForParent) = try FileDescriptor.pipe()

          openedStdinFDToCloseInParent?.setCloexec( )
          stdinWriteFDForParent?.setCloexec()

          // Wire child's stdio
          try addDup2AndClose(&actions, from: openedStdinFDToCloseInParent!.rawValue, to: STDIN_FILENO,  closeSourceInChild: true)

          let rcCloseWrite = posix_spawn_file_actions_addclose(&actions, stdinWriteFDForParent!.rawValue)
          if rcCloseWrite != 0 { throw log(POSIXErrno(rcCloseWrite, fn: "posix_spawn_file_actions_addclose(stdin write)")) }
        } catch(let e as Errno) {
          throw log(POSIXErrno(e.rawValue, reason: "setting stdin to strings"))
        } catch(let e) {
          throw log(POSIXErrno(-1, reason: "setting stdin to strings: \(e)"))
        }

      default:
        break
    }

    do {
      if captureOutput {
        try addDup2AndClose(&actions, from: stdoutW!.rawValue, to: STDOUT_FILENO, closeSourceInChild: true)
      }
      try addDup2AndClose(&actions, from: stderrW.rawValue, to: STDERR_FILENO, closeSourceInChild: true)
    } catch(let e as Errno) {
      throw log(POSIXErrno(e.rawValue, fn: "addDup2AndClose", reason: "redirecting stdio"))
    } catch(let e) {
      throw log(POSIXErrno(-1, fn: "addDup2AndClose", reason: "redirecting stdio: \(e)"))
    }

    if let r = stdoutR {
      let rc = posix_spawn_file_actions_addclose(&actions, r.rawValue)
      if rc != 0 { throw log(POSIXErrno(rc, fn: "posix_spawn_file_actions_addclose(stdout read)")) }
    }
    if let r = stderrR {
      let rc = posix_spawn_file_actions_addclose(&actions, r.rawValue)
      if rc != 0 { throw log(POSIXErrno(rc, fn: "posix_spawn_file_actions_addclose(stderr read)")) }
    }


    // Optional cwd (Darwin extension)
    if let cwd = cd {
#if os(macOS)
      let rc = cwd.withPlatformString { posix_spawn_file_actions_addchdir_np(&actions, $0) }
#else
      let rc = ENOTSUP
#endif
      if rc != 0 { throw log(POSIXErrno(rc, fn: "posix_spawn_file_actions_addchdir_np")) }

    }

    // Spawn
    let argvStrings = [execu] + arguments.map { $0.asStringArgument() }

    let nv = Environment.getenv().merging(env, uniquingKeysWith: { lhs, rhs in rhs} )
    let envpStrings: [String]? = nv.map { "\($0.key)=\($0.value)" }



    // 1️⃣ Initialize
    guard posix_spawnattr_init(&attr) == 0 else {
      throw log(POSIXErrno(fn: "posix_spawnattr_init"))
    }
    defer {
      posix_spawnattr_destroy(&attr)
    }
    var flags: Int16 = 0
    flags |= Int16(POSIX_SPAWN_SETSIGDEF)
    flags |= Int16(POSIX_SPAWN_SETSIGMASK)
    flags |= Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)

    guard posix_spawnattr_setflags(&attr, flags) == 0 else {
      throw log(POSIXErrno(fn: "posix_spawnattr_setflags"))
    }

    var sig = sigset_t()
    sigemptyset(&sig)
    posix_spawnattr_setsigdefault(&attr, &sig)
    posix_spawnattr_setsigmask(&attr, &sig)




    do {
      let spawnRC: Int32 = try withCStringArray(argvStrings) { argv in
        try withUnsafePointer(to: actions) { actionsPtr in
          try withUnsafePointer(to: attr) { attrPtr in
            if let envpStrings {
              return try withCStringArray(envpStrings) { envp in
                posix_spawn(&pid, executablePath, actionsPtr, attrPtr, argv, envp)
              }
            } else {
              return posix_spawn(&pid, executablePath, actionsPtr, attrPtr, argv, environ)
            }
          }
        }
      }
      if spawnRC != 0 {
        throw log(POSIXErrno(spawnRC, fn: "posix_spawn"))
      }
    } catch(let e as Errno) {
      throw log(POSIXErrno(e.rawValue, fn: "posix_spawn") )
    } catch(let e as POSIXErrno) {
      throw e
    } catch(let e) {
      throw log(POSIXErrno(-1, fn: "posix_spawn", reason: "\(e)"))
    }
    // Parent side: close pipe ends we must not keep open.
    // - For stdout/stderr: close the write ends in the parent (child owns those).



    do {
      try stdoutW?.close()
      try stderrW.close()
    } catch(let e as Errno) {
      let p = POSIXErrno(e.rawValue, fn: "close", reason: "closing stderrW or stdoutW" )
    } catch(let e) {
      let p = POSIXErrno(-1, fn: "close", reason: "closing stderrW or stdoutW: \(e)" )
    }

    // Parent closes any stdin file FD it opened (child has its own dup2’d copy).
    if let fd = openedStdinFDToCloseInParent { try? fd.close() }


    if captureOutput {
      let so = stdoutR!
      readerTask = Task.detached {
        let res = try so.readAllBytes()
        return res
      }
    }

    let se = stderrR!
    errorTask = Task.detached {
      let res = try se.readAsString()
      return res
    }


    if let w = stdinWriteFDForParent {
      switch withStdin {
        case is String:
          let s = withStdin as! String
          feederTask = Task.detached {defer { try? w.close() }
            try w.writeAllBytes(Array(s.utf8))
          }

        case is Substring:
          let s = String(withStdin as! Substring)
          feederTask = Task.detached { defer { try? w.close() }; try w.writeAllBytes(Array(s.utf8) ) }
        case is [UInt8]:
          let b = withStdin as! [UInt8]
          feederTask = Task.detached { defer { try? w.close() }; try w.writeAllBytes(b) }
        case is AsyncStream<[UInt8]>:
          let stream = withStdin as! AsyncStream<[UInt8]>
          feederTask = Task.detached {
            defer { try? w.close() }
            for await chunk in stream {
              if Task.isCancelled { throw CancellationError() }
              try w.writeAllBytes(chunk)
            }
          }
        default: break
      }
    }

    return pid

    // Concurrently:
    // - drain stdout/stderr
    // - wait for exit
    // - (optionally) write stdin then close it to deliver EOF

  }

  public func run(
    _ executablePath: String,
    withStdin: (any Stdinable)? = nil,
    args arguments: any Arguable...,
    env : [String : String] = [:],
    cd : FilePath? = nil,
    captureOutput: Bool = true
  ) async throws -> Output {
    return try await run(executablePath, withStdin: withStdin, args: arguments, env: env, cd: cd, captureOutput: captureOutput)
  }

  public func run(
    _ executablePath: String,
    withStdin: (any Stdinable)? = nil,
    args arguments: [any Arguable] = [],
    env : [String : String] = [:],
    cd : FilePath? = nil,
    captureOutput: Bool = true
  ) async throws -> Output {

    let _ = try launch(
      executablePath,
      withStdin: withStdin,
      args: arguments,
      env: env,
      cd: cd,
      captureOutput: captureOutput
    )

    return try await value()
  }



  public func value() async throws -> Output {
    defer { posix_spawn_file_actions_destroy(&actions); actions = nil }

    if awaitingValue { fatalError("DarwinProcess requested value twice") }
    awaitingValue = true


    async let status: Int32 = waitForExit(pid: pid)
    async let _ = feederTask?.value
    async let stderr = errorTask!.value

    async let stdout = readerTask?.value ?? [UInt8]()


    //      let (stdout, stderr, terminationStatus, _) = try await (readerTask == nil ? [UInt8]() : readerTask!.value, errorTask!.value, status, feederTask!.value)


    let res = try await Output(code: status, data: stdout, error: stderr)

    // Close read ends after drain
    try? stdoutR?.close()
    try? stderrR?.close()

    return res
  }

  // MARK: - Helpers




  private func waitForExit(pid: pid_t) async throws -> Int32 {
    try await Task.detached {
      var status: Int32 = 0
      while true {
        let w = Darwin.waitpid(pid, &status, 0)
        if w == -1 {
          if errno == EINTR { continue }
          throw POSIXErrno(fn: "waitpid")
        }
        break
      }

      if WIFEXITED(status) { return WEXITSTATUS(status) }
      if WIFSIGNALED(status) { return 128 + WTERMSIG(status) }
      return status
    }.value
  }


  // MARK: - posix_spawn file actions wiring (Darwin Swift overlay)

  private func addDup2AndClose(
    _ actions: inout posix_spawn_file_actions_t?,
    from: Int32,
    to: Int32,
    closeSourceInChild: Bool
  ) throws {
    let rc = posix_spawn_file_actions_adddup2(&actions, from, to)
    if rc != 0 { throw POSIXErrno(rc, fn: "posix_spawn_file_actions_adddup2") }

    if closeSourceInChild {
      let rc2 = posix_spawn_file_actions_addclose(&actions, from)
      if rc2 != 0 { throw POSIXErrno(rc2, fn: "posix_spawn_file_actions_addclose") }
    }
  }


  private func withCStringArray<R>(
    _ strings: [String],
    _ body: ([UnsafeMutablePointer<CChar>?]) throws -> R
  ) throws -> R {
    var cStrings: [UnsafeMutablePointer<CChar>?] = []
    cStrings.reserveCapacity(strings.count + 1)

    for s in strings {
      cStrings.append(strdup(s))
    }
    cStrings.append(nil)

    defer {
      for p in cStrings where p != nil { free(p) }
    }

    return try body(cStrings)
  }
}

// ===================================================================================================
/**
 Implemented for find.
  */
public func execvp(_ x : String, _ a : [String]) -> POSIXErrno {
  let az = a.map { $0.withCString { strdup($0) } } + [UnsafeMutablePointer<CChar>.init(bitPattern: 0)]
  Darwin.execvp(x, az )
  return POSIXErrno()
}
