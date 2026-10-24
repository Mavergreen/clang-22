# Build ingredients

Everything baked into the shipped `.pkg`s (clang22, clang22-cross and libcxx22), where it is
pinned, and how a change to it reaches a release. An *ingredient* is an input to the product; the
*own upstream* is the thing this repo exists to port. An own-upstream bump cuts
`<upstream>-mavericks.1`; an ingredient bump cuts a `-mavericks.(N+1)` repackage of the same
upstream, via `.github/workflows/repackage-on-ingredient-bump.yml`.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| LLVM/Clang source (own upstream) | `UPSTREAM_VERSION` (repo root) | ✅ customManager → `github-tags` on `llvm/llvm-project`, capped to this repo's line | `release.yml` on push to main cuts `-mavericks.1` |
| Recaulk (prebuilt librecaulk.a + headers) | `components/recaulk/version` | ✅ shipyard preset manager → github-releases on Mavergreen/recaulk | watched path → repackage dispatched |
| LLVM release-signing keys | `keys/llvm-release.asc` | ❌ **untrackable — manual refresh** (see below) | not a watched path; a stale bundle fails the build loudly, never silently |
| MacOSX10.9 SDK | `Mavergreen/shipyard@v1` (`fetch_sdk.sh`) | ✅ github-actions manager tracks the tag | `@v1` is a *moving* tag, so content moves without any path here changing |
| Sparkle framework (embedded in the updater `.app`) | `Mavergreen/shipyard@v1` (`mavericks_fetch_sparkle`; Sparkle 1.x — the last line that runs on 10.9) | ✅ via `@v1` (github-actions manager) | content moves with `@v1` |
| longboat (CI only: `on-mavericks` installs it in the 10.9 guest, because clang22's preinstall requires it, and runs `longboat sdk install 10.9` for sdk109; nothing of it ships) | `components/longboat/version` | ✅ `github-releases` on `Mavergreen/longboat`, `YYYYMMDD.N` versioning | no release: nothing shipped changes |
| Sparkle EdDSA public key | `updater/ed25519_key.pub` | ❌ untrackable (our own key) | baked into the updater's `Info.plist` as `SUPublicEDKey`; paired with the `SPARKLE_PRIVATE_KEY` secret |

Not ingredients: `build/*.sh` and `native-bootstrap/` are this repo's own recipe — a change there is a
repackage you cut deliberately (`workflow_dispatch` with `local_release=true`), not something Renovate
drives.

Patches (`patches/*.patch`, applied to the GPG-verified source by `mav_apply_patches` in
`build/lib.sh`, which both `build/build-cross.sh` and `build/build-native.sh` call: CI's native job
unpacks its own copy of the tarball): upstream LLVM fixes the pinned version lacks, each rebased onto
it and naming its upstream commit in its header, or Mavergreen's own fix where upstream has none yet:
`0001-arm64e-x1-tbd.patch`, so ld64.lld reads macOS 27's SDK stubs (upstream's), and
`0002-lld-weak-bindings-by-name.patch`, so 10.9's dyld coalesces weak symbols across images (ours, to
offer upstream), and `0003-clang-catch-by-value-exn-alignment.patch`, so a caught `__int128` or
16-byte-aligned class does not fault on 10.9 to 10.13 (ours, to offer upstream). They apply with no fuzz, so an `UPSTREAM_VERSION` bump that breaks one fails the
build by name; drop a patch once the new version carries its commit. A change here is a deliberate
repackage.

## Why no source checksum is pinned for LLVM

There is no `LLVM_SHA256` in `build/versions.sh` on purpose. A pinned hash cannot vouch for a tarball
that does not exist yet, so it is exactly the thing that blocks the bot: every LLVM bump would need a
human to fetch and paste one. Instead `build/build-cross.sh` GPG-verifies
`llvm-project-<ver>.src.tar.xz` against `keys/llvm-release.asc` — a signature vouches for bytes nobody
has seen, which is what makes a Renovate bump of `UPSTREAM_VERSION` self-contained.

## Why the LLVM signing keys are untracked

`keys/llvm-release.asc` is LLVM's published release-key bundle, fetched verbatim from
<https://releases.llvm.org/release-keys.asc> — the URL llvm/llvm-project's own release body names
under "Verifying Packages". There is no version or datasource for Renovate to compare against, so
there is nothing to track.

It carries **all six** LLVM release managers rather than only whoever signed the currently pinned
release. LLVM rotates who cuts a release (22.1.1 was Douglas Yung), so a single-key bundle would make
a routine Renovate bump fail on an unrelated-looking GPG error the day the rotation lands — defeating
the point of preferring a signature to a hash. Carrying the set LLVM publishes for this purpose is
their own trust model, not a widening of ours. Refresh the file if LLVM adds a release manager; the
failure mode is a loud build failure at `gpg --verify`, never a silent downgrade.

## Lines, and the two variants a line ships

A **line** is an LLVM major (this repo's root `UPSTREAM_VERSION` = 22.1.1, LINE 22). One repo ships
one LLVM major: a clang-22 user is never carried onto clang-23, because LLVM 23 arrives as a new
repo, not a bump of this one's `UPSTREAM_VERSION`. The Renovate manager uses a `depName`
(`llvm-22`) with `packageName` pointing at the real repo, capped to this line -- an uncapped line
is one Renovate bump away from silently becoming a different product.

Each line ships **two toolchain variants from one release**, plus the libcxx22 runtime. The two
variants are members of the `clang` group, so one box can hold both, and `mavergreen select clang`
picks which one owns the bare names:

| Variant | Runs on | Prefix | Identifier | Install floor |
|---|---|---|---|---|
| native | x86_64 Mavericks (the flagship) | `/usr/local/mavergreen/clang<line>` | `dev.mavergreen.clang.clang<line>` | **10.9.5** |
| cross | modern arm64 macOS | `/usr/local/mavergreen/clang<line>-cross` | `dev.mavergreen.clang.clang<line>-cross` | 11.0 |
| libcxx22 (runtime) | x86_64 Mavericks | `/usr/local/mavergreen/libcxx<line>` | `dev.mavergreen.clang.libcxx<line>` | 10.9.5 |

libcxx22 is relinked from the cross build's `libc++.a` by `build/build-libcxx.sh`; its group is `libcxx`,
and its build-info agrees with the toolchains on `llvm`, `recaulk` and `target`.

**One C++ ABI, the system's.** libc++ is built on `/usr/lib/libc++abi.dylib`, as Apple builds it, and no
libc++abi or libunwind of LLVM's ships. Every C++ program clang22 links statically takes libc++.a and the
system's libc++abi, and libcxx22's `libc++abi.1.dylib` is not LLVM's: it re-exports the system's and
exports Recaulk's libc++abi back-fills, the names 10.9's lacks that Wowfunhappy's `libc++abi.1.dylib`
exported, so programs built against his still load. Before, a libc++abi of our own sat beside the
system's (Foundation's libobjc uses it) in any Cocoa process, and an exception caught by the copy that
did not throw it crashed. Recaulk (from 20261019.1) back-fills what 10.9's libc++abi lacks, so this
repo's Recaulk pin is also its C++ runtime's. The aligned and sized new and delete moved from
`libc++abi.1.dylib` to `libc++.1.dylib`, which defines them; every name the parity references export
stays reachable through `libc++.1.dylib`. `tests/cxxabi-interop-test.sh` is the gate.

One known limit, 10.9's own: its libc++abi places a thrown object 8 bytes past a 16-byte boundary.
clang reads a value caught by value at that alignment since patches/0003, but a 16-byte-aligned type
caught BY REFERENCE binds to the object itself, and code using the reference assumes the type's
alignment, so it can still fault on 10.9 to 10.13. clang warns on the throw side ("underaligned
exception object").

Both target `x86_64-apple-macos10.9`, and both are built on the modern arm64 runner in one run — the
native variant is cross-*hosted* using the cross variant as its compiler, so nothing x86_64 is ever
executed during the build. Their `build-info-*.txt` records must agree on `llvm` and `recaulk`
(conformance compares any key appearing in more than one variant); `variant`, `arch`, `prefix`, `pkg`
and `identifier` are the keys that are supposed to differ.

## Conformance deviations

- shipyard-cmake-only:build/build-linux.sh: the Linux host compiler bootstraps with the exact Ubuntu CMake locked in build/linux/packages.lock; the shipped CMake product currently has only Mac host binaries. Reconsider when a Linux CMake product is available.
- shipyard-cmake-only:build/configure-linux.sh: configures that same locked Linux bootstrap with Ubuntu CMake; no Mac CMake binary can execute in the baseline container. Reconsider with a Linux CMake product.
- rosetta:tests/target/host-run.sh: preserves the existing Mac runtime-test policy when executing saved x86_64 witnesses on Apple Silicon, including profile-test Rosetta setup. Linux never calls this helper. Reconsider when Mac build jobs can execute the witnesses on an Intel host; before macOS 28 removes Rosetta.

- rosetta:tests/smoke-native.sh: the native-toolchain smoke test primes Rosetta (`softwareupdate --install-rosetta`) and runs the staged x86_64/10.9 `clang++` under `arch -x86_64` to compile and execute a hello-world, proving the shipped native toolchain actually works rather than just looking right on disk. This is the check the cross variant cannot run (its host tools are arm64 by design); only the native leg's shipped x86_64 host clang++ needs it. Availability never gates: it SKIPs when `arch -x86_64 clang++ --version` cannot execute at all (no Rosetta), but once Rosetta demonstrably runs the binary, a compile/link/run failure is treated as a real product defect, not skipped. Reconsider when this validation can run on an x86_64 host (the 10.9 box or an Intel runner) instead of via Rosetta on the arm64 release runner; at the latest before macOS 28 removes Rosetta.
- rosetta:tests/libcxx-runtime-test.sh: runs an x86_64/10.9 C++ program against the staged libcxx22 on the arm64 release runner, proving exceptions, iostreams and threads work through the dylibs; it primes Rosetta (`softwareupdate --install-rosetta`) first on a non-x86_64 host. In CI an inability to run x86_64 fails the step (the workflow does not treat its exit 77 as a skip), because this is the only CI proof that an exception thrown in one image is caught in another and that libcxx22 coexists with the system libc++; run locally, the test SKIPs instead. Reconsider when it can run on the 10.9 box or an Intel runner in CI; at the latest before macOS 28 removes Rosetta.
- rosetta:tests/profile-runtime-test.sh: runs `-fprofile-instr-generate` and `--coverage` x86_64/10.9 binaries built by the staged toolchains (cross, then native) on the arm64 release runner, then reads their profiles back with the toolchain's own `llvm-profdata`/`llvm-cov`; it primes Rosetta (`softwareupdate --install-rosetta`) first on a non-x86_64 host. In CI an inability to run x86_64 fails the step, because a profile runtime that links but cannot write a profile is the defect this test exists to catch; run locally, it SKIPs instead. It also passes natively on the 10.9 box (`TC=/usr/local/mavergreen/clang22`). Reconsider when it can run on the 10.9 box or an Intel runner in CI; at the latest before macOS 28 removes Rosetta.
- rosetta:tests/cxxabi-interop-test.sh: runs x86_64/10.9 C++ and Objective-C++ programs, built by the staged toolchains and against the staged libcxx22, on the arm64 release runner, to prove one C++ ABI (the system's /usr/lib/libc++abi.dylib) across our code, the system's C++ and Cocoa; it needs no priming of its own, the earlier Rosetta steps having run. In CI an inability to run x86_64 fails the step, as for libcxx-runtime-test. Under Rosetta the system's libc++abi and dyld are macOS 26's, so this proves the shape only; the on-mavericks job runs it on a 10.9.5 guest, which is the proof of 10.9's own, and publish needs that job. Reconsider when the build jobs can run on an x86_64 host; at the latest before macOS 28 removes Rosetta.
- rosetta:tests/catch-align-test.sh: checks in the IR, on any host, that a value caught by value is read at no more than the exception object's alignment (patches/0003), then runs the program where x86_64 runs, here under Rosetta. macOS 26's libc++abi aligns exception objects to 16, so under Rosetta the run cannot fault for this bug; the IR half and the on-mavericks job's run on a 10.9.5 guest are what catch it. Reconsider with libcxx-runtime-test's.
- rosetta:tests/weak-bind-order-test.sh: checks ld64.lld's weak binding order in the table on any host, then, where x86_64 runs (here under Rosetta), runs the program to see the weak symbols coalesce. macOS 26's dyld does not need the order, so under Rosetta the run half cannot fail for this bug; the table half and the on-mavericks job's run on a 10.9.5 guest are what catch it. Reconsider with libcxx-runtime-test's.
Machine-read by `artifact-facts.sh` as `- <check>:<glob> : <reason>` (one line each, plain glob):

- shipyard-cmake-only:native-bootstrap/*: this tree bootstraps a whole toolchain from nothing on a
  stock 10.9 box, so it cannot presuppose an installed shipyard, and its `cmake` is deliberately not
  whichever one is on `PATH`. `build_tools()` builds cmake 3.19.8 into `toolchains/tools/bin` (the
  newest the 10.9 libc++ can compile — 3.21+ fails) and prepends that to `PATH`; stages A–C then
  configure LLVM 3.9.1/6.0.1/14.0.6 with exactly it, and stage D switches to the `cmake-new` it
  builds later, named through `$CMAKE`. Writing `shipyard-cmake` in stages A–C would substitute a
  different cmake for the one the stage was pinned to and require the pkg on a box that by
  construction has nothing installed. None of these configures a shipyard consumer — no
  `find_package(MavericksShipyard)` is involved — so the runtime refusal never fires here either.
  Revisit if native-bootstrap ever builds this repo's own CMakeLists.txt, or if the shipyard pkg
  becomes a bootstrap prerequisite.
- floor:mavericks-clang-*-cross-*.pkg: the cross toolchain runs on macOS 11 and later (arm64) and only targets 10.9, so its archive's install floor is 11.0, not 10.9.5

## Deferred from family conventions (not artifact-conformance checks)

- **Generic (opt-in) updater icon** — the Sparkle updater ships the standard macOS app icon by
  explicit opt-in (`MAVERICKS_ALLOW_GENERIC_ICON=ON`), embedding no artwork at all, pending a real
  Mavericks-Clang mark. Not the LLVM dragon (trademark, and it would read as official LLVM). See
  `updater/ICON-CREDIT.txt`.
- **SDK not redistributed** — the Apple MacOSX10.9 SDK is not baked into the artifact (Apple's bytes).
  Both toolchains' `SDKs` is a link to `../sdk109/SDKs`, which Longboat's `sdk109` fills
  (`sudo longboat sdk install 10.9`), and both pkgs refuse to install without Longboat. Without `sdk109`
  the first compile fails naming the missing `SDKs/MacOSX10.9.sdk`.
- **No build on 10.9 yet** — the family requires a product's build to run natively on a Mavericks box;
  this repo's does not. `build/build-cross.sh` builds the arm64-hosted cross variant, which needs a
  modern host by nature. `build/build-native.sh` is the one that could run on 10.9 but does not: it
  cross-hosts the native variant on the arm64 runner, using the cross stage it just built as its
  compiler. The capability is proven, not hoped for: on 2026-08-04 the shipped native clang-22 built
  clang+lld 22.1.1 from source on a real 10.9.5 box (about 53 minutes on 12 cores), and on 2026-10-18
  the installed clang22 built this repo's patched 22.1.8 `ld64.lld` there, which passed
  `tests/tbd-arch-test.sh`. What is missing is the recipe: a native mode of `build-native.sh` (the
  installed clang22 as compiler, the 10.9 SDK, shipyard-cmake and ninja from the installed pkgs) that
  produces the same staged, relocatable toolchain and passes the same gates. `native-bootstrap/` is
  not that path: it is Wowfunhappy's original climb from Apple's clang-3.5 seed,
  kept for history. Ends when that native mode exists and is checked against a CI build.

### Linux host variant

The Linux x86_64 tarball serves developers producing Mavericks artifacts on Linux.
It shares this release's LLVM source, patches, Recaulk and target-file export; the SDK
remains separately fetched. Host bootstrap inputs are locked in `build/linux/base-image`
and `build/linux/packages.lock` (Ubuntu 22.04, GCC 12.3). This is an explicit initial
Linux bootstrap exception to clang22 N−1: revisit once the first supported Linux clang22
release is available. No Linux arm64 variant or distro package is shipped.
