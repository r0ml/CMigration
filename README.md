CMigration
==========

The CMigration package is a support package to assist in porting POSIX command line tools from C to Swift.

The intent is to insulate the Swift commands from dependencies on lower level C libraries which have not yet
been exposed to Swift.

It is my understanding that building Darwin level commands should not be dependent on Foundation, so this library also provides some re-implementations of certain Foundation capabilities which might be needed for Swift command line tools to remain Foundation-free.

The following capabilities are provided:

1) CharacterFunctions.swift provides wrappers for C multi-byte character functions like `wcwidth` which don't map onto Swift character support.

1) DateTime.swift provides wrappers for C date functions, including functions for `timespec` and `time_t`

1) Files.swift provides Swift-y wrappers for reading and writing files -- including wrappers for `stat` and `fstat`

1) FileStream.swift provides functionality similar to the C stream functions, such as `fputs`, `fgets`, `fputc`, `fgetc`

1) FileSystem.swift wraps access to the C functions `statfs` and `fstatfs`

1) Formatting.swift provides formatting functions to left and right pad numbers and strings, as C-format strings don't work in Swift when resulting strings are large.

1) FTS.swift provides wrappers for the the `fts_` functions in C.  Calling sequences for these are tricky from Swift, and I have not yet undertaken to provide a Swift-y implementation of the `fts_` C functions.  So, for now, these wrappers abstract (a bit) the lower level C implementation.  

1) Getopt.swift implements a replacement for C `getopt`.  Although there is a swift-argument-parser package which provides Swift-y capabilities for command line options, the use of this package adds considerable bulk to a small command-line tool, so we provide a port of the C getopt which is much leaner and compatible with the original C tools.

1) Humanize.swift re-implements `humanize_number` from `libuti`

1) Interact.swift re-implements `rpmatch` (prompting for Yes/No) which is used in some command line tools.

1) LibUtil.swift re-implements a `expand_number` from `libutil` which are needed for some command line tools.

1) MigrationSupport.swift provides the base class for command line tools which use CMigration.  `ShellCommand` is the base class to structure command line tools.  The file also includes functions for error reporting that match the C implementations.

1) Process,swift implements support for process management -- to be used instead of `fork` or `process_spawn` or `exec`.  It also includes support for process-related functions, such as `getenv` and `setenv`

1) Strmode.swift reimplements `atrmode` from LibC

1) Strtofflags.swift reimplements `strtofflags` and `fflagstostr` from LibC 

1) System.swift provides access to sysctl

1) Users.swift provides support for the required functions that manipulated `uid_t` and `gid_t` values.  The includes `getPasswd` and `getGroupEntry`


