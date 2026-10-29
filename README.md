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

## 🎬 Video Showcase

Click the image below to watch **Pioneer's Spaghetti Solver** in action on YouTube:

<div align="center">
  <a href="https://www.youtube.com/watch?v=Vj9e2gJjwfY" target="_blank">
	<img src="https://img.youtube.com/vi/Vj9e2gJjwfY/maxresdefault.jpg" alt="Watch the PSS Trailer on YouTube" width="820" style="border-radius: 8px; border: 2px solid #FAB757;" />
  </a>
  <br>
  <sub><b>Click to watch feature overview</b></sub>
</div>

---

## ✨ Key Features

### 🔗 1. Node Schematic & Interactive World Map
* **High-Performance Node Graph:** Connect machines, extractors, power plants, splitters, and storage blocks with smooth drag-and-drop wires.
* **Custom Wire Routing:** Choose between smooth Bézier curves or **90° Orthogonal Wires**. Double-click any wire to insert custom routing waypoints (`Reroute Pins` also supported).
* **Live Logistics Badges:** Wires dynamically display item flow rates (`/m` or `m³/m`) and required Conveyor Belt (`Mk.1` – `Mk.6`) or Pipeline (`Mk.1` – `Mk.2`) tiers, highlighting overloaded lines in red.
* **Nested Factories (Outposts):** Select any group of nodes and press `Ctrl + G` to pack them into a modular **Factory** sub-graph. Inputs and outputs automatically synchronize via `Receiver` and `Transmitter` nodes.
* **Compact UI Mode:** Declutter massive megabase schematics with a single click—hide text descriptions and display only clean icons and numbers.

### 📐 2. 2D Foundation Grid Planner (CAD Mode)
Switch directly from your logical node graph to a **1:1 scale 2D Foundation Grid** (`1 Foundation = 8m × 8m`) to plan the physical layout of your factory:
* **Multi-Floor Architecture (`B5` to `P25`):** Build vertically across 30+ floors. Toggle the **👻 Floor Below (Onion Skin)** blueprint view to align upper floors with lower infrastructure.
* **Physical 2m Conveyor Belt Routing:** Route physical belts port-to-port with two dedicated modes (`T`): **90° Straight** (authentic 2m turning radius) or **Smooth Curve**, complete with rotatable conveyor poles (`R`).
* **Multi-Floor Conveyor Lifts:** Place 2-step vertical **Conveyor Lifts** (`[8]` / `[V]`) that physically connect floors and automatically check for shaft collisions across all intermediate levels.
* **True Load Balancers:** Automatically expands abstract graph splitters into physical `4m × 4m` Splitters and Mergers on the grid, including loopback lines for non-standard ratios.
* **CAD & Alignment Tools:**
  * **🏗 Auto-Floor:** Automatically fill foundations and corner pillars underneath all machines on the active floor.
  * **📏 Side Elevation Panel:** Inspect the vertical profile of the current floor, showing the lowest/highest machine and calculating the optimal ceiling clearance in `4m` wall segments.
  * **📏 CAD Ruler:** Measure exact distances in foundations and meters (`ΔX`, `ΔY`, and diagonal `L`).
  * **↔ Row X / ↕ Col Y Alignment:** Snap selected machines into tight horizontal rows or vertical columns.
  * **⚠ Real-Time Collision Detection:** Instant visual warnings when machine footprints or lift shafts overlap.

### 📍 3. Interactive World Map Radar (Ores, Wells & Collectibles)
* **Complete In-Game Coordinate Database:** View exact locations for all Resource Nodes (`Impure 0.5x`, `Normal 1.0x`, `Pure 2.0x`), Resource Wells, and Collectibles (**Hard Drives**, **Power Slugs**, **Mercer Spheres**, **Somersloops**).
* **Double-Click to Spawn Miner:** Double-click (`2x LMB`) any ore deposit or resource well on the map to immediately spawn a pre-configured Miner/Extractor with the exact purity set.
* **Progress Tracking:** Right-click (`RMB`) any deposit or collectible marker to mark it as **Used / Collected** (with an option to hide used markers).
* **Customizable Map Backgrounds:** Switch between built-in world maps or load your own custom map/blueprint image (`.png`, `.jpg`, `.webp`) with adjustable scale and opacity.

### 🪄 4. Auto-Chain Generator (Backwards Planner)
* Pick any target item and desired output rate (`/min`), and let PSS calculate and spawn the entire upstream production chain automatically.
* Optionally include raw resource Miners/Extractors and encapsulate the generated production line inside a dedicated **Factory** block.

### 🚂 5. Multi-Platform Train & Truck Stations
* **Train Stations (Up to 12 Platforms):** Add individual freight platforms (`Wagon #1` – `#12`) and link stations into multi-stop routes.
* **Global Route Balancing:** Automatically tracks cargo across connected stations, displaying **Total**, **Taken**, and **Free** capacity per platform or mixed truck cargo pool.
* **Fuel Validation:** Dedicated fuel ports for Truck Stations that accept only valid fuel items.

### ⚡ 6. Overclocking Assistant (OCA) & Somersloop Amplification
* **Satisfactory 1.0 Somersloop Support:** Configure Somersloop slots per machine for up to `+100%` output amplification, accurately calculating the quadratic power multiplier `(1 + s/max)²`.
* **4-Decimal Clock Precision:** Supports clock speeds from `0.0001%` to `250.0000%` using the official exponent (`1.321928`).
* **One-Click OCA Presets:** Open the Overclocking Assistant on any machine to copy or apply **Power Saving** (equal clock), **Precision** (full `100%` machines + 1 underclocked), or **Space Saving** (`250%` max clock) configurations.

### 📊 7. Analytics, Shopping List & Bottleneck Inspector
* **⚠ Bottleneck & Overload Inspector:** Automatically scans all graphs for **Input Starvation** (machines receiving less than required) and **Belt/Pipe Overloads**, allowing you to jump the camera directly to the problematic node.
* **🛒 Construction Planner & Shopping List:** Aggregates every unbuilt machine, foundation footprint, Power Shard, Somersloop, and building material (with an adjustable safety buffer slider and inventory stack calculator). Mark nodes as **✓ Built** on the graph to exclude them from the shopping list.
* **📊 Global Production & AWESOME Sink Summary:** Monitors all items entering **Storage Containers**, **Dimensional Depots**, and **AWESOME Sinks**, calculating live **AWESOME Coupon points/min** based on official item point values.
* **➕ Custom Recipe Manager:** Create, edit, and persist custom recipes (up to 4 inputs and 4 outputs, custom cycle time, and positive/negative MW power) for modded playthroughs.

---

## 🌍 Localization & Language Status

**Pioneer's Spaghetti Solver** features a dual-layer localization system supporting **55 languages**:
1. **In-Game Data Layer (`Game`):** Names of items, fluids, buildings, conveyor belts, pipelines, and recipes are loaded directly from localized game data dictionaries across all 55 supported languages.
2. **Application Interface Layer (`UI`):** Menus, tooltips, modals, and CAD tools.

| Language | Code | UI Status | Game Data (Items/Recipes) | Verification Status |
| :--- | :---: | :---: | :---: | :--- |
| **English** | `en-US` / `en-GB` | **100%** | **100%** | ✅ **Human-Verified** |
| **Polish (Polski)** | `pl-PL` | **100%** | **100%** | ✅ **Human-Verified** |
| **German (Deutsch)** | `de` | ~25% (Core UI) | **100%** | 🤖 AI-Translated |
| **Spanish (Español)** | `es` | ~25% (Core UI) | **100%** | 🤖 AI-Translated |
| **Russian (Русский)** | `ru` | ~25% (Core UI) | **100%** | 🤖 AI-Translated |
| **Chinese (简体中文)** | `zh` | ~25% (Core UI) | **100%** | 🤖 AI-Translated |
| **49 Other Languages** | *Various* | Fallback to `EN` | **100%** | No translation yet |

> **🤖 Note on `[AI]` Tagged Languages:**  
> Languages other than English and Polish are marked with an `[AI]` tag in the Settings menu. While all in-game recipe and item names are fully localized, UI translations for those languages are either partial or AI-assisted and may contain inaccuracies.

### 🛠 How to Translate / Improve a Language
Want to complete or fix the UI translation for your language?
1. Open **⚙ Settings** in PSS and select your target language.
2. Click **🌐 Export Full Translation Template** at the bottom of the Settings window.
3. This generates a clean JSON file at `user://i18n_template_<lang>.json` containing all UI keys, buildings, items, and recipes.
4. Edit the `"ui"` dictionary values and submit a Pull Request!

---

## ⌨️ Controls & Keyboard Shortcuts

### 🔗 Node Schematic Mode
| Shortcut / Input | Action |
| :--- | :--- |
| **Right Mouse Button (RMB)** | Open Recipe / Node Search Popup (or disconnect wire on port) |
| **Drag Wire to Empty Space** | Open context-filtered recipe search for that specific item |
| **2× LMB / Shift + LMB on Wire** | Add a routing waypoint on a wire (`RMB` on waypoint = remove) |
| **2× LMB on Map Deposit** | Spawn a pre-configured Miner on that resource node |
| **RMB on Map Deposit** | Toggle **✓ Used / Collected** status on map marker |
| **`L`** | Lock / Unlock selected nodes (prevents edits, deletion & auto-balance) |
| **`Delete` / `Backspace`** | Delete selected unlocked nodes |
| **`Ctrl + G`** | Group selected nodes into a modular **Factory** sub-graph |
| **`Ctrl + F`** | Open **World & Factory Navigator** |
| **`Ctrl + C` / `Ctrl + V`** | Copy / Paste selected nodes and their internal connections |
| **`Ctrl + Z` / `Ctrl + Y`** | Undo / Redo (`Ctrl + Shift + Z` also supported) |
| **`Ctrl + S` / `Ctrl + O` / `Ctrl + N`** | Save Project (`.pss`) / Load Project / New Project |

### 📐 2D Foundation Grid Mode (CAD)
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

## 🚀 Getting Started & Running from Source

### 📥 Pre-built Releases
Download the latest standalone executable for your platform from the [**Releases**](https://github.com/TowarzyszFatCat/Pioneers-Spaghetti-Solver/releases) page. No installation required!

### 🛠 Running / Building from Source
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

## 🤝 Contributing

Community contributions, bug fixes, UI translations, and feature improvements are very welcome!  
Before submitting a Pull Request, please read [**CONTRIBUTING.md**](CONTRIBUTING.md) carefully:

1. **License Agreement:** By submitting a Pull Request, you agree that your contributions are licensed under the project's Modified MIT License and grant the original copyright holder (`TowarzyszFatCat / ChonkChum`) the unrestricted right to use, modify, and distribute your contribution, including in commercial releases (such as a future Steam release).
2. **DCO Sign-off Required:** All commits must be signed off using the `-s` flag:
   ```bash
   git commit -s -m "Your commit message"
   ```

---

## 📜 License & Disclaimer

* **License:** This project is licensed under the **Modified MIT License with Non-Commercial Clause** — see the [**LICENSE**](LICENSE) file for full details.
  * ✅ You are free to use, copy, modify, fork, and distribute this software for **non-commercial** purposes.
  * ❌ Commercial use, monetization, or paid distribution (including Steam, mobile stores, or paid services) by anyone other than the original copyright holder (**TowarzyszFatCat / ChonkChum**) is strictly prohibited.
* **Warranty Disclaimer:** This software is provided *"as is"*, without warranty of any kind, and may contain bugs or calculation inaccuracies.
* **Affiliation Disclaimer:** *Pioneer's Spaghetti Solver* is an independent community-made tool and is not affiliated with, endorsed, or sponsored by **Coffee Stain Studios AB**. *Satisfactory* and all related game trademarks and assets belong to their respective owners.

## ⚖️ Legal Notice & Assets Credit
Pioneer's Spaghetti Solver is an unofficial, community-made fan project and is not affiliated with, endorsed by, or connected to **Coffee Stain Studios** in any way. 
All in-game assets, item icons, and related graphics used within this software are the property and copyright of Coffee Stain Studios. Images were sourced via the [Official Satisfactory Wiki](https://satisfactory.wiki.gg/).
This software is provided for free, non-commercial use by the Satisfactory community.
