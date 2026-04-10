<div align="center">
    <img src="Resources/Icon.svg" width=200 height=200>
    <h1>Thaw</h1>
</div>

Thaw is an autonomous launcher and organizer for third-party menu extras. It discovers supported extras, presents them in its own UI, activates them cleanly when possible, and manages groups, order, profiles, search, and display-aware surfaces without physically rearranging the macOS menu bar.

![thaw-banner](https://github.com/user-attachments/assets/9584065d-f840-4545-9a42-cfc5534b5ac3)

[![Download](https://img.shields.io/badge/download-latest-brightgreen?style=flat-square)](https://github.com/stonerl/Thaw/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/stonerl/Thaw/ci.yml?style=flat-square)](https://github.com/stonerl/Thaw/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=flat-square)
[![Sponsor](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=flat-square)](https://github.com/sponsors/stonerl)
[![Discord](https://img.shields.io/badge/Discord-7289DA?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/5cnKkKbMFd)
[![License](https://img.shields.io/github/license/stonerl/Thaw?style=flat-square)](LICENSE)

> [!NOTE]
> **Thaw** is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird.
> Thaw now follows its own product contract focused on a public-API-first launcher/runtime for menu extras rather than physical menu bar manipulation.

## Install

### Manual Installation

Download the `Thaw_1.x.x.zip` file from the [latest release](https://github.com/stonerl/Thaw/releases/latest) and move the unzipped app into your `Applications` folder.

### Homebrew

Install the latest stable release:

```sh
brew install thaw
```

To get the latest beta (or stable, whichever is newer):

```sh
brew install thaw@beta
```

## Translations

Thaw is currently available in the following languages:

<table frame="void" rules="none">
    <tr>
        <th align="left">Language</th>
        <th align="left">Status</th>
        <th align="center">Flag</th>
        <th align="left">Completion</th>
        <th width="30"></th>
        <th align="left">Language</th>
        <th align="left">Status</th>
        <th align="center">Flag</th>
        <th align="left">Completion</th>
    </tr>
    <tr>
        <td><b>Bahasa Indonesia</b></td>
        <td>Complete</td>
        <td align="center">🇮🇩</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td><b>Čeština(*)</b></td>
        <td>Complete</td>
        <td align="center">🇨🇿</td>
        <td><img src="https://geps.dev/progress/100" /></td>
    </tr>
    <tr>
        <td><b>Deutsch</b></td>
        <td>Complete</td>
        <td align="center">🇩🇪/🇦🇹</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td><b>English</b></td>
        <td>Complete</td>
        <td align="center">🇬🇧/🇺🇸</td>
        <td><img src="https://geps.dev/progress/100" /></td>
    </tr>
    <tr>
        <td><b>Español</b></td>
        <td>Complete</td>
        <td align="center">🇪🇸/🇲🇽</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td><b>Français</b></td>
        <td>Complete</td>
        <td align="center">🇫🇷</td>
        <td><img src="https://geps.dev/progress/100" /></td>
    </tr>
    <tr>
        <td><b>Italiano</b></td>
        <td>Complete</td>
        <td align="center">🇮🇹</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td><b>日本語(*)</b></td>
        <td>Complete</td>
        <td align="center">🇯🇵</td>
        <td><img src="https://geps.dev/progress/100" /></td>
    </tr>
    <tr>
        <td><b>한국어</b></td>
        <td>Complete</td>
        <td align="center">🇰🇷</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td><b>Magyar</b></td>
        <td>Complete</td>
        <td align="center">🇭🇺</td>
        <td><img src="https://geps.dev/progress/100" /></td>
    </tr>
    <tr>
        <td><b>Nederlands</b></td>
        <td>Complete</td>
        <td align="center">🇳🇱/🇧🇪</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td><b>Português (Brasil)(*)</b></td>
        <td>Complete</td>
        <td align="center">🇧🇷</td>
        <td><img src="https://geps.dev/progress/100" /></td>
    </tr>
    <tr>
        <td><b>Русский(*)</b></td>
        <td>Complete</td>
        <td align="center">🇷🇺</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td><b>简体中文</b></td>
        <td>Complete</td>
        <td align="center">🇨🇳</td>
        <td><img src="https://geps.dev/progress/100" /></td>
    </tr>
    <tr>
        <td><b>正體中文</b></td>
        <td>Complete</td>
        <td align="center">🇹🇼</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td><b>ภาษาไทย</b></td>
        <td>Complete</td>
        <td align="center">🇹🇭</td>
        <td><img src="https://geps.dev/progress/100" /></td>
    </tr>
    <tr>
        <td><b>Türkçe(*)</b></td>
        <td>Complete</td>
        <td align="center">🇹🇷</td>
        <td><img src="https://geps.dev/progress/100" /></td>
        <td></td>
        <td></td>
        <td></td>
        <td align="center"></td>
        <td></td>
    </tr>
</table>

_Note: languages marked with (\*) are currently only available in the development branch._

## Features/Roadmap

<details>
<summary>Click to view the full Features & Roadmap list</summary>

### Menu bar item management

- [x] Hide menu bar items
- [x] Archive surface
- [x] Discover supported third-party menu extras
- [x] Activate menu extras from Thaw's own UI
- [x] Search menu extras
- [x] Manage Quick Access / Panel / Archive virtual groups
- [x] Maintain virtual order and naming without touching the physical macOS menu bar
- [x] Display-aware primary surface behavior
- [x] Profiles for launcher/layout state
- [x] Menu extra organization from a dedicated layout UI

### Menu bar appearance

- [x] Menu bar tint (solid and gradient)
- [x] Menu bar shadow
- [x] Menu bar border
- [x] Custom menu bar shapes (rounded and/or split)
- [ ] Remove background behind menu bar
- [ ] Rounded screen corners
- [ ] Different settings for light/dark mode

### Hotkeys

- [x] Toggle panel and archive surfaces
- [x] Show the search panel
- [x] Toggle the primary Thaw surface
- [x] Apply profiles

### Other

- [x] Launch at login
- [x] Automatic updates
- [ ] Menu bar widgets

</details>

## Why does Thaw only support macOS 26 and later?

Thaw’s current V3 architecture targets macOS 26+ only. The runtime, permissions flow, Focus integration, and panel/discovery contracts are built around that baseline, and there are no plans to support earlier versions of macOS.

## Gallery

### Item layout

<img width="1760" height="956" alt="thaw-items-fs8" src="https://github.com/user-attachments/assets/f2f6b9a6-55c5-40b3-910f-b27b114577dd" />

### Open the Panel below the menu bar

<img width="1760" height="400" alt="thaw-hidden-fs8" src="https://github.com/user-attachments/assets/c6ac6364-30f8-4c92-8f6f-9efe15f99573" />

### Drag-and-drop interface to arrange menu bar items

<img width="1760" height="800" alt="thaw-layout-fs8" src="https://github.com/user-attachments/assets/54273d41-fcf3-4c9a-834b-e62a162a6b0c" />

### Customize the menu bar's appearance

<img width="1760" height="956" alt="thaw-appearance-fs8" src="https://github.com/user-attachments/assets/d95302df-26b0-4608-896e-4966c822fb5e" />

### Menu bar item search

<img width="1760" height="956" alt="thaw-search-fs8" src="https://github.com/user-attachments/assets/ebafc745-7220-46c9-9297-f7a00ef6c15d" />

## License

Thaw is available under the [GPL-3.0 license](LICENSE).

## Project Stats

<a href="https://star-history.com/#stonerl/Thaw&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date" width="100%" />
  </picture>
</a>
