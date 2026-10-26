# Benchmarks

No general idle CPU, memory or package-size benchmark has been executed.

## Parallel scanner (2026-10-26)

Release build, Apple Swift 6.4, arm64, macOS 26.6.2 (25G83), 10 active CPU cores. Generated temporary regular files only; no personal directories. Each 1/2/4-worker comparison used three runs with rotated order. Application fingerprint caches started empty for every measured comparison; OS filesystem caches were warm and were not flushed. Files contain repeated bytes, so these timings do not represent uncached physical-disk throughput. No compiler or UI render ran concurrently with the recorded samples.

| Fixture | 1 worker median (range), ms | 2 workers median (range), ms | 4 workers median (range), ms |
| --- | --- | --- | --- |
| 256 × 64 KiB, four copies/group | 178.5 (177.7–182.1) | 129.7 (127.7–133.2) | 99.3 (99.2–100.8) |
| 64 × 4 MiB, four copies/group | 174.2 (168.7–177.0) | 103.3 (97.0–109.1) | 68.5 (66.8–72.6) |
| 8 × 32 MiB, two copies/group | 119.9 (117.3–124.9) | 65.3 (64.1–65.8) | 39.2 (39.2–41.6) |
| 128 × 1 MiB, unique content | 43.4 (42.1–66.0) | 31.9 (31.7–32.0) | 26.1 (26.1–26.4) |

Two workers improved these fixture medians by approximately 1.36–1.84× relative to the new scanner constrained to one worker. The default remains two to limit simultaneous I/O and CPU use; four is the tested hard ceiling, not the default. Low Power Mode, serious/critical heat, fewer than four active CPU cores, and unknown/external/removable/nonlocal volumes reduce scheduling to one worker. Already running file reads drain before the lower limit takes effect. Moderate heat caps scheduling at two. Enumeration remains serial.

Repeat scans with two workers took 112.7 / 43.1 / 15.0 / 29.2 ms for the fixtures above. Full hashing read zero bytes on these cache-hit runs, while exact comparison still read 24 / 384 / 256 / 0 MiB respectively. Cached fingerprints never replace full byte comparison. Repeat timings are single observations, not medians. Hash reuse bytes and actual reads are reported separately in the app.

These are bounded, warm-filesystem synthetic measurements, not a promise for Downloads, network disks, huge directory trees or every Mac. The comparison is with the same new pipeline using one worker, not a historical app version. Metadata enumeration, filesystem latency, unrelated activity and the amount of matching content affect end-to-end times.

Reproduce from the project directory:

```sh
MACPULSE_SCAN_BENCHMARK=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/macpulse-module-cache \
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test \
  -c release --filter ScanBenchmarkTests
```

## Scan bug verification (2026-10-26)

For the user's reported Downloads scan, the fixed metadata-only large-file mode listed 23,315 regular files, found one file above the default 100 MiB threshold, skipped 121 entries, and returned in 2.32 seconds. It performed no duplicate hashing and did not reach the file-count cap. Only metadata in the explicitly reported folder was read; no files were modified and no file names were logged.

This is an observed support check on the current dataset, not a universal scan-time guarantee. Filesystem caching, disk speed, permissions and folder contents affect timing. Duplicate verification reads content separately, uses a quick-sample prefilter followed by full SHA-256 and byte comparison, and displays bytes processed. Large-file listings do not wait for it.

Nine new regression cases cover metadata-only mode, early listing publication, quick-sample rejection, matching-sample/full-content verification, byte progress, explicit cap reporting, dependency exclusions and cancellation retaining useful results.

## Reproducible methodology

1. Build the signed Release configuration on a recorded Mac model, macOS version, and Xcode version.
2. Record app bundle size and compressed archive size separately.
3. Measure idle CPU and resident memory after a five-minute warm-up with the dashboard open, then closed, using Activity Monitor or Instruments. Repeat at least five times and report the median and range.
4. Measure cache scan duration against a dedicated fixture tree with known file counts and allocated sizes. Do not scan or clean personal directories for benchmark development.
5. Record toolchain versions, sample interval, fixture characteristics, and measurement commands with any future results.
