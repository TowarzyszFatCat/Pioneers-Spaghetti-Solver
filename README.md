<div align="center">

<img width="128" height="128" alt="icon" src="https://github.com/user-attachments/assets/a3f42fa1-eacd-417f-bae5-51a5a7928def" />

# Pioneer's Spaghetti Solver (PSS)

**Advanced Factory Planner, Logistics Calculator & 2D CAD Foundation Grid for Satisfactory (1.0+)**

[![Version](https://img.shields.io/badge/Version-0.1.0-FAB757?style=for-the-badge)](https://github.com/TowarzyszFatCat/Pioneers-Spaghetti-Solver/releases)
[![Godot Engine](https://img.shields.io/badge/Godot_Engine-4.7-478cbf?style=for-the-badge&logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![Languages](https://img.shields.io/badge/Languages-55_Supported-4B8052?style=for-the-badge)](#🌍-localization--language-status)
[![License](https://img.shields.io/badge/License-Modified_MIT_(Non--Commercial)-B04A3E?style=for-the-badge)](LICENSE)

<br>

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/chonkchum)

*Because spaghetti belongs on your plate, not in your factory.*

</div>

---

## Video Showcase

Click the image below to watch **Pioneer's Spaghetti Solver** in action on YouTube:

<div align="center">
  <a href="https://www.youtube.com/watch?v=Vj9e2gJjwfY" target="_blank">
	<img src="https://img.youtube.com/vi/Vj9e2gJjwfY/maxresdefault.jpg" alt="Watch the PSS Trailer on YouTube" width="820" style="border-radius: 8px; border: 2px solid #FAB757;" />
  </a>
</div>


## Key Features

### 1. Node Schematic & Interactive World Map
* **High-Performance Node Graph:** Connect machines, extractors, power plants, splitters, and storage blocks using smooth Bézier curves or **90° Orthogonal Wires** with custom routing waypoints (`Reroute Pins` supported).
* **Live Logistics Badges:** Wires display item flow rates (`/m` or `m³/m`) and required Conveyor Belt (`Mk.1` – `Mk.6`) or Pipeline (`Mk.1` – `Mk.2`) tiers, highlighting overloaded lines.
* **Nested Factories (Outposts):** Group selected nodes (`Ctrl + G`) into modular **Factory** sub-graphs with automatic input (`Receiver`) and output (`Transmitter`) port synchronization.
* **Compact UI Mode:** Hide text descriptions and display only icons and numbers for large megabase schematics.

### 2. 2D Foundation Grid Planner (CAD Mode)
Switch directly from your logical node graph to a **1:1 scale 2D Foundation Grid** (`1 Foundation = 8m × 8m`) to plan the physical layout of your factory:
* **Multi-Floor Architecture (`B5` to `P25`):** Build across 30+ vertical floors with an **Onion Skin (Floor Below)** preview to align upper floors with lower infrastructure.
* **Physical 2m Conveyor Belt Routing:** Route physical belts port-to-port in **90° Straight** mode (authentic 2m turning radius) or **Smooth Curve** mode, with rotatable conveyor poles (`R`).
* **Multi-Floor Conveyor Lifts:** Place 2-step vertical **Conveyor Lifts** (`[8]` / `[V]`) that connect floors and check for shaft collisions across intermediate levels.
* **True Load Balancers:** Automatically expands abstract graph splitters into physical `4m × 4m` Splitters and Mergers on the grid, including loopback lines for non-standard ratios.
* **CAD & Alignment Tools:** Auto-Floor foundation filling, Side Elevation height profile panel (in `4m` wall segments), CAD Ruler (`ΔX`, `ΔY`, diagonal `L`), Row/Column snapping (`G` / `Shift + G`), and real-time footprint collision warnings.

### 3. World Map Radar (Ores, Wells & Collectibles)
* **In-Game Coordinate Database:** View locations for Resource Nodes (`Impure 0.5x`, `Normal 1.0x`, `Pure 2.0x`), Resource Wells, Hard Drives, Power Slugs, Mercer Spheres, and Somersloops.
* **Double-Click to Spawn Miner:** Double-click (`2x LMB`) any deposit on the map to spawn a pre-configured Miner/Extractor with matching purity.
* **Progress Tracking:** Right-click (`RMB`) any deposit or collectible marker to mark it as **Used / Collected**.
* **Custom Map Backgrounds:** Load custom map or blueprint images (`.png`, `.jpg`, `.webp`) with adjustable scale and opacity.

### 4. Auto-Chain Generator (Backwards Planner)
* Select a target item and desired output rate (`/min`) to automatically calculate and spawn the entire upstream production chain, optionally including raw resource extractors and wrapping the chain in a dedicated Factory block.

### 5. Multi-Platform Train & Truck Stations
* **Train Stations (Up to 12 Platforms):** Configure individual freight platforms (`Wagon #1` – `#12`), link stations into routes, and track **Total**, **Taken**, and **Free** capacity across connected stops.
* **Truck Stations:** Dedicated fuel ports with valid fuel filtering and mixed cargo pool balancing.

### 6. Overclocking Assistant (OCA) & Somersloop Support
* **Satisfactory 1.0 Somersloop Amplification:** Configure Somersloop slots per machine for up to `+100%` output amplification and accurate quadratic power scaling `(1 + s/max)²`.
* **4-Decimal Clock Precision:** Supports clock speeds from `0.0001%` to `250.0000%` (`1.321928` exponent) with one-click presets for **Power Saving**, **Precision**, and **Space Saving**.

### 7. Analytics, Shopping List & Bottleneck Inspector
* **Bottleneck & Overload Inspector:** Scans all graphs for input starvation and belt/pipe overloads with one-click camera jump to problematic nodes.
* **Construction Planner & Shopping List:** Aggregates unbuilt machines, foundations, Power Shards, Somersloops, and building materials with an adjustable safety buffer and inventory stack calculator.
* **Global Production & AWESOME Sink Summary:** Tracks items entering Storage Containers, Dimensional Depots, and AWESOME Sinks with live coupon point calculations.
* **Custom Recipe Manager:** Create and save custom recipes (`user://custom_recipes.json`) for modded playthroughs.
---

## Localization & Language Support

PSS uses a two-layer localization system:
1. **In-Game Item & Recipe Names (55 Languages):** Extracted directly from Satisfactory's localization dictionaries so you can search and view items, buildings, and recipes in your native in-game language.
2. **Application UI:** Complete, human-verified interface translations for **English** and **Polish**, plus partial machine-translated UI strings for German, Spanish, Russian, and Chinese.

| Language | Code | Application UI | In-Game Item & Recipe Names |
| :--- | :---: | :---: | :---: |
| **English** | `en-US` / `en-GB` | **100% (Verified)** | **100%** |
| **Polish (Polski)** | `pl` | **100% (Verified)** | **100%** |
| **German / Spanish / Russian / Chinese** | `de`, `es`, `ru`, `zh` | ~25% (Core UI, WIP) | **100%** |
| **All Other Satisfactory Languages (49)** | *Various* | English UI Fallback | **100%** |

### Contributing Translations
To translate or improve the UI for your language:
1. Open **Settings** in PSS and select your target language.
2. Click **Export Full Translation Template** at the bottom of the Settings window.
3. Edit the `"ui"` dictionary in `user://i18n_template_<lang>.json` and submit a Pull Request.

## Controls & Keyboard Shortcuts

### Node Schematic Mode
| Shortcut / Input | Action |
| :--- | :--- |
| **Right Mouse Button (RMB)** | Open Recipe / Node Search Popup (or disconnect wire on port) |
| **Drag Wire to Empty Space** | Open context-filtered recipe search for that specific item |
| **2× LMB / Shift + LMB on Wire** | Add a routing waypoint on a wire (`RMB` on waypoint = remove) |
| **2× LMB on Map Deposit** | Spawn a pre-configured Miner on that resource node |
| **RMB on Map Deposit** | Toggle **Used / Collected** status on map marker |
| **`L`** | Lock / Unlock selected nodes |
| **`Delete` / `Backspace`** | Delete selected unlocked nodes |
| **`Ctrl + G`** | Group selected nodes into a modular **Factory** sub-graph |
| **`Ctrl + F`** | Open **World & Factory Navigator** |
| **`Ctrl + C` / `Ctrl + V`** | Copy / Paste selected nodes and internal connections |
| **`Ctrl + Z` / `Ctrl + Y`** | Undo / Redo (`Ctrl + Shift + Z` supported) |
| **`Ctrl + S` / `Ctrl + O` / `Ctrl + N`** | Save Project (`.pss`) / Load Project / New Project |

### 2D Foundation Grid Mode (CAD)
| Shortcut / Input | Action |
| :--- | :--- |
| **`1` — `8`** | Select Tool: `[1]` Select, `[2]` Foundation, `[3]` Pillar, `[4]` Ruler, `[5/B]` Belt, `[6]` Splitter, `[7]` Merger, `[8/V]` Lift |
| **`R` / `RMB` on Block** | Rotate selected/hovered block, splitter, or conveyor pole by `90°` |
| **`T`** *(in Belt Tool)* | Toggle Conveyor Belt routing mode (`90° Straight` vs `Smooth Curve`) |
| **`PageUp` / `PageDown`** | Move selected/hovered block up or down 1 floor (or switch floor during Lift placement) |
| **`G` / `Shift + G`** | Align selected blocks into a horizontal row (`G`) or vertical column (`Shift + G`) |
| **`L`** | Lock / Unlock position and rotation of selected/hovered blocks |
| **`F`** | Quick-filter grid visibility by the hovered block's item (`RMB` on filter button clears) |
---

## Getting Started & Running from Source

### Pre-built Releases
Download the latest standalone executable for your platform from the [**Releases**](https://github.com/TowarzyszFatCat/Pioneers-Spaghetti-Solver/releases) page. No installation required!

### Running / Building from Source
1. Download and install **Godot Engine 4.7+** (Standard version, GDScript).
2. Clone this repository:
   ```bash
   git clone https://github.com/TowarzyszFatCat/Pioneers-Spaghetti-Solver.git
   ```
3. Open Godot Project Manager, click **Import**, and select the `project.godot` file.
4. Press **`F5`** (Run Project) in the editor.

* **User Data Directory:** Projects (`.pss`), autosaves, custom recipes (`custom_recipes.json`), and settings (`app_settings.json`) are stored in the custom user directory:
  * **Windows:** `%APPDATA%\PioneersSpaghettiSolver\`

---

## Contributing

Community contributions, bug fixes, UI translations, and feature improvements are very welcome!  
Before submitting a Pull Request, please read [**CONTRIBUTING.md**](CONTRIBUTING.md) carefully:

1. **License Agreement:** By submitting a Pull Request, you agree that your contributions are licensed under the project's Modified MIT License and grant the original copyright holder (`TowarzyszFatCat / ChonkChum`) the unrestricted right to use, modify, and distribute your contribution, including in commercial releases (such as a future Steam release).
2. **DCO Sign-off Required:** All commits must be signed off using the `-s` flag:
   ```bash
   git commit -s -m "Your commit message"
   ```

---

## License & Disclaimer

* **License:** This project is licensed under the **Modified MIT License with Non-Commercial Clause** — see the [**LICENSE**](LICENSE) file for full details.
  * You are free to use, copy, modify, fork, and distribute this software for **non-commercial** purposes.
  * Commercial use, monetization, or paid distribution (including Steam, mobile stores, or paid services) by anyone other than the original copyright holder (**TowarzyszFatCat / ChonkChum**) is strictly prohibited.
* **Warranty Disclaimer:** This software is provided *"as is"*, without warranty of any kind, and may contain bugs or calculation inaccuracies.
* **Affiliation Disclaimer:** *Pioneer's Spaghetti Solver* is an independent community-made tool and is not affiliated with, endorsed, or sponsored by **Coffee Stain Studios AB**. *Satisfactory* and all related game trademarks and assets belong to their respective owners.

## Legal Notice & Assets Credit
Pioneer's Spaghetti Solver is an unofficial, community-made fan project and is not affiliated with, endorsed by, or connected to **Coffee Stain Studios** in any way. 
All in-game assets, item icons, and related graphics used within this software are the property and copyright of Coffee Stain Studios. Images were sourced via the [Official Satisfactory Wiki](https://satisfactory.wiki.gg/).
This software is provided for free, non-commercial use by the Satisfactory community.
