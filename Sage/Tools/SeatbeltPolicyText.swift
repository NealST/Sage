//
//  SeatbeltPolicyText.swift
//  Sage
//
//  Static Seatbelt (SBPL) policy text shared by all sandboxed shell runs.
//

/// Base Seatbelt policy applied to every sandboxed process.
///
/// deny-default with an allowlist ported from OpenAI Codex's sandboxing crate
/// (codex-rs/sandboxing/src/*.sbpl, Apache-2.0), which itself borrows from
/// Chrome's macOS sandbox policy. Dynamic per-run rules (readable/writable
/// roots, home-read denial) are appended by `SeatbeltSandbox`.
nonisolated enum SeatbeltPolicyText {
    static let base = """
    (version 1)

    ; deny-by-default base; every section below adds an allowlist.
    (deny default)

    ; ------------------------------------------------------------------
    ; Process (codex seatbelt_base_policy.sbpl)
    ; ------------------------------------------------------------------

    ; child processes inherit the policy of their parent
    (allow process-exec)
    (allow process-fork)
    (allow signal (target same-sandbox))
    (allow process-info* (target same-sandbox))

    (allow file-write-data
      (require-all
        (path "/dev/null")
        (vnode-type CHARACTER-DEVICE)))

    ; sysctls permitted.
    (allow sysctl-read
      (sysctl-name "hw.activecpu") (sysctl-name "hw.busfrequency_compat")
      (sysctl-name "hw.byteorder") (sysctl-name "hw.cacheconfig")
      (sysctl-name "hw.cachelinesize_compat") (sysctl-name "hw.cpufamily")
      (sysctl-name "hw.cpufrequency_compat") (sysctl-name "hw.cputype")
      (sysctl-name "hw.l1dcachesize_compat") (sysctl-name "hw.l1icachesize_compat")
      (sysctl-name "hw.l2cachesize_compat") (sysctl-name "hw.l3cachesize_compat")
      (sysctl-name "hw.logicalcpu_max") (sysctl-name "hw.logicalcpu")
      (sysctl-name "hw.machine") (sysctl-name "hw.model")
      (sysctl-name "hw.memsize") (sysctl-name "hw.ncpu")
      (sysctl-name "hw.nperflevels") (sysctl-name "hw.packages")
      (sysctl-name "hw.pagesize_compat") (sysctl-name "hw.pagesize")
      (sysctl-name "hw.physicalcpu") (sysctl-name "hw.physicalcpu_max")
      (sysctl-name "hw.cpufrequency") (sysctl-name "hw.tbfrequency_compat")
      (sysctl-name "hw.vectorunit") (sysctl-name "machdep.cpu.brand_string")
      (sysctl-name "kern.argmax") (sysctl-name "kern.hostname")
      (sysctl-name "kern.maxfilesperproc") (sysctl-name "kern.maxproc")
      (sysctl-name "kern.osproductversion") (sysctl-name "kern.osrelease")
      (sysctl-name "kern.ostype") (sysctl-name "kern.osvariant_status")
      (sysctl-name "kern.osversion") (sysctl-name "kern.secure_kernel")
      ; Python's ProcessPoolExecutor queries this through sysconf(_SC_SEM_NSEMS_MAX).
      (sysctl-name "kern.sysv.semmns") (sysctl-name "kern.usrstack64")
      (sysctl-name "kern.version") (sysctl-name "sysctl.proc_cputype")
      (sysctl-name "vm.loadavg")
      (sysctl-name-prefix "hw.optional.arm.") (sysctl-name-prefix "hw.optional.armv8_")
      (sysctl-name-prefix "hw.perflevel") (sysctl-name-prefix "kern.proc.pgrp.")
      (sysctl-name-prefix "kern.proc.pid.") (sysctl-name-prefix "net.routetable."))

    ; Allow Java to read some CPU info. This is misclassified as a "write" because
    ; userspace passes a memory buffer to the sysctl, but conceptually it is a read.
    (allow sysctl-write
      (sysctl-name "kern.grade_cputype"))

    ; IOKit
    (allow iokit-open
      (iokit-registry-entry-class "RootDomainUserClient"))

    ; needed to look up user info, see https://crbug.com/792228
    (allow mach-lookup
      (global-name "com.apple.system.opendirectoryd.libinfo"))

    ; Needed for python multiprocessing on macOS for the SemLock
    (allow ipc-posix-sem)

    ; Needed for PyTorch/libomp on macOS to register OpenMP runtimes.
    (allow ipc-posix-shm-read-data
      ipc-posix-shm-write-create
      ipc-posix-shm-write-unlink
      (ipc-posix-name-regex #"^/__KMP_REGISTERED_LIB_[0-9]+$"))

    (allow mach-lookup
      (global-name "com.apple.PowerManagement.control"))

    ; allow openpty()
    (allow pseudo-tty)
    (allow file-read* file-write* file-ioctl (literal "/dev/ptmx"))
    (allow file-read* file-write*
      (require-all
        (regex #"^/dev/ttys[0-9]+")
        (extension "com.apple.sandbox.pty")))
    ; PTYs created before entering seatbelt may lack the extension; allow ioctl
    ; on those slave ttys so interactive shells detect a TTY and remain functional.
    (allow file-ioctl (regex #"^/dev/ttys[0-9]+"))

    ; ------------------------------------------------------------------
    ; Network helpers (codex seatbelt_network_policy.sbpl). Sage leaves
    ; network access itself unrestricted, matching the pre-sandbox shell.
    ; ------------------------------------------------------------------

    ; allow only safe AF_SYSTEM sockets used for local platform services.
    (allow system-socket
      (require-all
        (socket-domain AF_SYSTEM)
        (socket-protocol 2)))

    (allow mach-lookup
      ; Used by platform helpers that resolve user directory locations.
      (global-name "com.apple.bsd.dirhelper")
      (global-name "com.apple.system.opendirectoryd.membership")
      ; Communicate with the security server for TLS certificate information.
      (global-name "com.apple.SecurityServer")
      (global-name "com.apple.networkd")
      (global-name "com.apple.ocspd")
      (global-name "com.apple.trustd.agent")
      ; Read network configuration.
      (global-name "com.apple.SystemConfiguration.DNSConfiguration")
      (global-name "com.apple.SystemConfiguration.configd"))

    (allow sysctl-read
      (sysctl-name-regex #"^net.routetable"))

    (allow network-outbound)
    (allow network-inbound)
    """
}
