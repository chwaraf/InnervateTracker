# InnervateTracker

**InnervateTracker** is a clean, lightweight, highly optimized World of Warcraft AddOn for tracking **Innervate (Stymulacja)** cooldowns, active buff durations, and recipient history in **TBC Anniversary** and **Classic Era**.

---

## 🌟 Key Features

* **Squeezed & Compact Window (170px)**: Extremely compact UI footprint with bold, crisp, readable fonts (`OUTLINE`).
* **2-Phase Visual Cooldown Flow**:
  * **0 – 20s (Active Buff)**: Replaces `Ready` with a cyan bar displaying the target's nick and buff duration (e.g. `PriestA 18s`).
  * **20 – 360s (Cooldown)**: Displays a red/orange bar counting down the Druid's remaining cooldown (e.g. `5m30s`).
  * **360s+ (Ready)**: Shows green `Ready` text.
* **Persistent Data (`SavedVariables`)**: Session time (`S: 12m`), cast totals `()`, recipient history, and active cooldown timers **persist seamlessly across `/reload` and logouts**.
* **Left Group Indicator & Rejoin Logic**:
  * If a Druid leaves the party/raid (or if you leave), their row remains accessible as `DruidNick (Left)` in gray text with 50% opacity.
  * When they or you rejoin the group, it automatically updates back to active status `DruidNick (2)`.
* **Dynamic Growth Direction (`[v]` / `[^]`)**: Click `[v]` or `[^]` on the header bar to toggle whether rows grow **Upwards** (header fixed at bottom) or **Downwards** (header fixed at top).
* **Click-to-Highlight & Whisper Keybind (`F9`)**:
  * **Left-click** any Druid row/bar to toggle a **gold highlight** mark on/off.
  * **Right-click** or press **`F9`** (configurable under `Options > Keybindings > AddOns > Innervate Tracker`) while highlighted to whisper: `"Innervate please!"`.
* **Range Fading & Status Indicators**:
  * Automatically fades out-of-range Druids (>40yd) to **35% opacity**.
  * Shows `(Dead)` or `(Off)` status indicators for dead or disconnected Druids.
* **Mouseover GameTooltip**: Hover over any Druid row to view a detailed breakdown of who received Innervate from them and how many times, formatted with class-colored names.
* **Sound Alerts**: Emits a subtle Ready Check audio alert when an Innervate comes off cooldown.

---

## 📁 Installation

1. Download or clone this repository into a folder named **`InnervateTracker`**.
2. Move the `InnervateTracker` folder into your World of Warcraft AddOns directory:
   ```
   World of Warcraft\_classic_\Interface\AddOns\InnervateTracker\
   ```
3. Ensure the folder structure contains:
   * `InnervateTracker.toc`
   * `Bindings.xml`
   * `InnervateTracker.lua`
4. **Restart World of Warcraft completely** for the client to register the `.toc` SavedVariables and Keybindings XML.

---

## 💻 Slash Commands

| Command | Description |
| :--- | :--- |
| `/it reset` | Resets all cast statistics, recipient history, and session time. |
| `/it lock` | Toggles frame dragging lock/unlock. |
| `/it sound` | Toggles sound alert when Innervate becomes Ready. |

---

## ⌨️ Keybinding Configuration

1. Open `Main Menu` ➔ `Options` ➔ `Keybindings` ➔ `AddOns`.
2. Scroll to **Innervate Tracker**.
3. Bind **Whisper Highlighted Druid** to your preferred key (Default: **`F9`**).

---

## 📜 License

Released under the **MIT License**. Free to use, modify, and distribute.
