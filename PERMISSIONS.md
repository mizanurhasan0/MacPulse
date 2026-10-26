# Permissions

System readings use Mach, Foundation, sysctl and libproc. The app requests no root access or persistent background helper.

Folder analysis starts with NSOpenPanel. A chosen security-scoped URL remains active only while that folder is in use; bookmarks and file paths are not persisted. Unreadable entries and cloud placeholders are skipped and partial scans are labeled. MacPulse does not request Full Disk Access to broaden scans.

Cleanup requires manual selection, a path preview and explicit confirmation. Approved items go to Trash; MacPulse does not empty it. An app can rebuild or redownload cached data. Protected/active/unknown cache folders cannot be selected.

Application quit and development-server stop have separate confirmations. They warn about unsaved work and interrupted requests/builds. macOS can deny an action; results show observed termination, continued running, rejection, cancellation or failure.

This Swift Package runs as an ordinary unsandboxed desktop app. A future sandboxed/App Store target must disable unsupported cross-process actions and review folder access requirements. Signing and notarization are separate release work.
