# fix-apple-music

One-click PowerShell fix for the
**"An unknown error has occurred"** (also reported as **error 18006** or
**KCCAError 4** in logs) problem that bricks the Microsoft Store version of
Apple Music on Windows.

## Quick start (30 seconds)

1. **Download two files** (click each → download):
   - `fix-apple-music.bat`
   - `fix-apple-music.ps1`
2. **Put them in the same folder** (e.g. your `Downloads\` folder).
3. **Double-click `fix-apple-music.bat`** — click **Yes** on the UAC prompt.
4. **Open Apple Music** from the Start menu when the script finishes.
5. **Play any song** — it should work immediately.

You should see output like:

```
[fix-apple-music] Found Apple Music package: AppleInc.AppleMusicWin ...
[fix-apple-music] Reset OK.
[fix-apple-music] Cache reset looks clean.
```

The window stays open with `Press any key to close...` — press any key when done.

**Why the .bat?** Running the `.ps1` directly via "Run with PowerShell"
fails with *“not digitally signed”* on unsigned scripts. The `.bat`
wrapper invokes PowerShell with `-ExecutionPolicy Bypass`, which fixes that.

If it still doesn't work, the full log is saved to:
`%TEMP%\fix-apple-music-<timestamp>.log` — read it to see what failed.

## What this fixes

When Apple Music for Windows (the Store / MSIX version, package name
`AppleInc.AppleMusicWin_*`) is force-killed mid-playback, hit by an AV
false-positive, or hit by a Store update race, its keychain component
(**kccadp**) gets corrupted and the app refuses to launch with:

> An unknown error has occurred.

The only fixes documented in [Apple Music communities][reddit-thread] and
[Microsoft Q&A][ms-qa] are:
1. **Sign out of Apple ID → sign back in** (annoying, breaks your session)
2. **Reset-AppxPackage** (clears the local cache, **preserves your Apple ID login**)
3. Reinstall from the Store (slow, also breaks your login)

This script automates **option 2** with a single double-click + one UAC prompt.

## What it does NOT touch

- Your Apple ID sign-in
- Your iCloud Music Library
- Your downloaded songs / DRM licenses
- The classic iTunes install (if you have it)
- Any other apps

## Requirements

- Windows 10 21H2+ or Windows 11
- Apple Music installed **from the Microsoft Store** (the classic iTunes
  install is a different package and not affected by this error)
- Administrator privileges (auto-requested via UAC)

## Safe to re-run

The script is idempotent — running it when Apple Music is already healthy
is a no-op. Run it again whenever the error returns.

## Why this happens

Apple Music on Windows uses Microsoft's **AppX/MSIX** packaging. Its
keychain (`kccadp`) is initialized lazily on launch and persists across
launches in the app's `LocalCache`. When the process is killed during
initialization (or the local state is corrupted for any reason), subsequent
launches hit the cached bad state and refuse to start, reporting the
generic "unknown error". `Reset-AppxPackage` is Microsoft's official way
to reset a Store app's local state without requiring re-authentication.

## Tested on

- Windows 10 22H2 + Apple Music 1.1540.23042.0 (Store version)
- Windows 11 23H2 + Apple Music 1.1540.23042.0

## See also

- [Reddit thread][reddit-thread] — original user reports of this error
- [Microsoft Q&A on NPSMSvc][npsmsvc] — same class of issue, different service
  (the Now Playing Session Manager service has a similar runaway loop that
  can cause Apple Music's audio engine to wedge; managed separately by
  [usblcd-display's NPSMSvc watchdog][usblcd-watchdog])

[reddit-thread]: https://www.reddit.com/r/AppleMusic/comments/177h0z4/apple_music_doesnt_work_on_my_pc_and_says_an/
[ms-qa]: https://learn.microsoft.com/en-us/answers/questions/4067371/service-host-npsmsvc_1f1c1b99-using-99-cpu-usage
[npsmsvc]: https://learn.microsoft.com/en-us/answers/questions/4067371/service-host-npsmsvc_1f1c1b99-using-99-cpu-usage
[usblcd-watchdog]: https://github.com/yanyifeng7/thermalright-display
