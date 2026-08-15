# InnervateTracker

**InnervateTracker** is a clean, lightweight, highly optimized World of Warcraft AddOn for tracking **Innervate (Stymulacja)** cooldowns, active buff durations, and recipient history in **TBC Anniversary** and **Classic Era** (Interface `20504`).

Designed for competitive raid environments, **InnervateTracker** features a squeezed 170px UI footprint, native C++ non-hijacking keybindings (`F9`, `F10`, `F11`), 3-slot multi-highlighting with automatic slot re-allocation, 30-yard range fading, and robust combat-taint protections.

---

## 🌟 Key Features

* **Squeezed & Compact Window (170px)**: Extremely compact UI footprint with bold, crisp, single-line fonts (`OUTLINE`), strict left/right bounds, `SetWordWrap(false)`, and zero text overlap.
* **Class-Specific 30-Yard Range Check**:
  * Queries native 30-yard friendly buff/heal spells for your class (`Innervate` for Druids, `Dampen/Amplify Magic` for Mages, `PW:Shield` for Priests, `Blessing of Might` for Paladins, etc.).
  * Smoothly fades out-of-range Druids (>30yd) to **65% opacity**, keeping names and countdown timers crisp and readable.
* **Raid Role Icons & Name Truncation**:
  * Displays official Blizzard group role icons (🛡️ Tank, 💚 Healer, ⚔️ Damager) to the left of each Druid's name using `"Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"`.
  * Truncates Druid names longer than 7 characters with a `*` suffix (e.g. `Malfurion` ➔ `Malfuri*`) to fit within the 170px frame.
* **2-Phase Visual Cooldown Flow**:
  * **0 – 20s (Active Buff)**: Replaces `Ready` with a cyan bar displaying the target's nick and buff duration (e.g. `PriestA 18s`).
  * **20 – 360s (Cooldown)**: Displays a red/orange bar counting down the Druid's remaining cooldown (e.g. `5m30s`).
  * **360s+ (Ready)**: Displays green `Ready` text.
* **Persistent Data & Marked Druids (`SavedVariables`)**: Session time (`S: 12m`), cast totals `()`, recipient history, active cooldown timers, and marked Druid highlights **persist seamlessly across `/reload` and logouts**.
* **3-Slot Multi-Highlight & Keybindings**:
  * **Slot 1 (Default: `F9`)**: Gold / Yellow Highlight (`#ffd100`, `0.35 Alpha`).
  * **Slot 2 (Default: `F10`)**: Cyan / Blue Highlight (`#1eb3ff`, `0.35 Alpha`).
  * **Slot 3 (Default: `F11`)**: Bright Green Highlight (`#30ff30`, `0.35 Alpha`).
  * **Smart Re-allocation**: Left-clicking to unmark a Druid automatically shifts remaining slots up, ensuring Slot 1 is always Gold (`F9`), Slot 2 is Cyan (`F10`), and Slot 3 is Green (`F11`).
  * **Persistent Highlights**: Highlights stay locked to Druids even if they die, go offline, or leave the group.
* **Absent, Offline & Dead Status Indicators**:
  * **`(Absent)`**: Displayed in **Muted Purple (`#a673a6`)** when a Druid leaves the party/raid group. Whispers are automatically blocked for absent Druids.
  * **`(Off)`**: Displayed in **Gray (`#888888`)** for offline Druids.
  * **`(Dead)`**: Displayed in **Dark Red (`#bf3333`)** for dead or ghost Druids.
* **Dynamic Growth Direction (`[v]` / `[^]`)**: Click `[v]` or `[^]` on the header bar to toggle whether rows grow **Upwards** (header fixed at bottom) or **Downwards** (header fixed at top), saved in `InnervateTrackerDB.growUp`.
* **Mouseover GameTooltip**: Hover over any Druid row to view a detailed breakdown of who received Innervate from them and how many times, formatted with class-colored names.
* **Sound Alerts**: Emits a subtle Ready Check audio alert when an Innervate comes off cooldown (wrapped in `pcall(PlaySound, 5274)`).
* **Safe Native Input & Zero Taint**:
  * **No Keyboard Hijacking**: Uses official `Bindings.xml` registered under `Options > Keybindings > AddOns`. Never captures WASD or chat.
  * **No `SaveBindings` Corruption**: Does not touch player binding files.
  * **Zero Combat Taint**: Uses standard unprotected buttons and direct `SendChatMessage` whispers, allowing instant 100% taint-free whispering and dynamic frame repositioning during combat.

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
| `/it bind` | Assigns default keys (`F9`, `F10`, `F11`) for the current session. |
| `/it lock` | Toggles frame dragging lock/unlock. |
| `/it sound` | Toggles sound alert when Innervate becomes Ready. |

---

## 📚 Developer Architecture Guidelines

For in-depth lessons on WoW TBC AddOn development, combat taint prevention, keybinding safety, and how to avoid freezing user controls or corrupting binding files, see **[`tbc_addon_instructions.md`](./tbc_addon_instructions.md)**.

---

## 📜 License

Released under the **MIT License**. Free to use, modify, and distribute.
