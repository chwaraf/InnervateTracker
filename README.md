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
* **3-Slot Multi-Highlight & Dynamic Keybindings**:
  * **Slot 1 (Default: `F9`)**: Gold / Yellow Highlight (`#ffd100`).
  * **Slot 2 (Default: `F10`)**: Cyan / Blue Highlight (`#1eb3ff`).
  * **Slot 3 (Default: `F11`)**: Bright Green Highlight (`#30ff30`).
  * **Smart Re-allocation**: Left-clicking to unmark a Druid automatically shifts remaining slots up, ensuring Slot 1 is always Gold (`F9`), Slot 2 is Cyan (`F10`), and Slot 3 is Green (`F11`).
* **Absent, Offline & Dead Status Indicators**:
  * **`(Absent)`**: Displayed in **Muted Purple (`#a673a6`)** when a Druid has left the party/raid group. Whispers are automatically blocked for absent Druids.
  * **`(Off)`**: Displayed in **Gray** for offline Druids.
  * **`(Dead)`**: Displayed in **Dark Red** for dead or ghost Druids.
* **Range Fading (40yd Range Check)**: Automatically fades out-of-range Druids (>40yd) to **35% opacity**.
* **Dynamic Growth Direction (`[v]` / `[^]`)**: Click `[v]` or `[^]` on the header bar to toggle whether rows grow **Upwards** (header fixed at bottom) or **Downwards** (header fixed at top).
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

## ⌨️ Keybinding Configuration

1. Open `Main Menu` ➔ `Options` ➔ `Keybindings` ➔ `AddOns`.
2. Scroll to **Innervate Tracker**.
3. Customize keybindings for:
   * **Whisper Highlighted Druid #1** (Default: **`F9`**)
   * **Whisper Highlighted Druid #2** (Default: **`F10`**)
   * **Whisper Highlighted Druid #3** (Default: **`F11`**)

---

## 💻 Slash Commands

| Command | Description |
| :--- | :--- |
| `/it reset` | Resets all cast statistics, recipient history, and session time. |
| `/it bind` | Force-binds default keys (`F9`, `F10`, `F11`) to both Account and Character settings. |
| `/it lock` | Toggles frame dragging lock/unlock. |
| `/it sound` | Toggles sound alert when Innervate becomes Ready. |

---

## 📜 License

Released under the **MIT License**. Free to use, modify, and distribute.
