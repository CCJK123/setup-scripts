# setup-scripts

This repository contains a collection of opinionated scripts to automate the setup of fresh installs of various operating systems according to my personal preferences. Specifically, these scripts help install and configure desired software and/or configure system settings as desired.

## Windows

Generally the preferred method of installation of software on Windows is [WinGet][] ([`winget`][]) and [mise][] (`mise`). WinGet is preferred for system-wide/per-user software installs where you only need one version of the software installed (usually the latest version, and sometimes it can auto self-update), while mise is preferred for per-user global installs where it might be useful to have multiple versions of the same software installed. If something is available on both, mise is preferred, for greater ease of portability of the config across different operating systems (via simply using the same `~/.config/mise/config.toml`).

[WinGet]: https://learn.microsoft.com/en-gb/windows/package-manager/
[`winget`]: https://github.com/microsoft/winget-cli
[mise]: https://mise.jdx.dev/
