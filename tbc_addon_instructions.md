# World of Warcraft (TBC / Classic) AddOn Development Guidelines & Pitfalls Guide

This document outlines critical engineering rules, dangerous Lua/XML practices, and technical pitfalls discovered during the development of **InnervateTracker** for World of Warcraft TBC Anniversary & Classic Era (Interface `20504`).

Follow these guidelines strictly to prevent freezing player controls, wiping keybinding files, causing combat taint, or producing console errors.

---

## 🚫 DANGER ZONE #1: Low-Level Keyboard Event Interception & Control Freezing

### The Problem
Calling `frame:EnableKeyboard(true)` and attaching an `OnKeyDown` handler on global or top-level UI frames causes **the entire physical keyboard to stop responding in World of Warcraft**. Movement keys (WASD), jumping (Spacebar), opening chat (Enter), spell action bars (1–=), and the Escape menu freeze instantly.

```lua
-- ❌ DO NOT DO THIS IN ANY ADDON!
local f = CreateFrame("Frame", "MyAddonFrame", UIParent)
f:EnableKeyboard(true) -- 💀 CRITICAL ERROR: Intercepts all raw OS keystrokes
f:SetScript("OnKeyDown", function(self, key)
    if key == "F9" then
        MyAddon_DoSomething()
    end
end)
```

### Why It Breaks the Game
1. **Prioritized Input Pipeline**: The WoW C++ engine routes raw physical keyboard events to UI frames that have `EnableKeyboard(true)` **before** passing input to the character movement or combat engines.
2. **Default Event Consumption**: In WoW's UI architecture, UI frames swallow keystrokes by default. Unless `self:SetPropagateKeyboardInput(true)` is explicitly called on every key event, the keypress stops at the frame and is discarded.
3. **Lua Error Traps**: If a Lua error occurs anywhere inside the `OnKeyDown` callback *before* propagation runs, script execution halts. The frame stays permanently stuck in keyboard capture mode, locking out WASD movement and chat until `/reload` or Alt+F4.

### The Proper Solution
**NEVER use `EnableKeyboard(true)` or `OnKeyDown` for global hotkeys.** Declare keybindings natively using `Bindings.xml` and let WoW's C++ input manager route key events safely:

```xml
<!-- ✅ SAFE & CORRECT: Bindings.xml in root folder -->
<Bindings>
    <Binding category="ADDONS" name="MYADDON_ACTION1" header="MYADDON_HEADER">
        MyAddon_Action1();
    </Binding>
</Bindings>
```

---

## 🚫 DANGER ZONE #2: Programmatic Binding Overwrites & Keybinding File Corruption

### The Problem
Calling `SaveBindings()` or automatically executing `SetBinding()` in Lua startup routines can **wipe out and corrupt player keybindings across multiple characters**.

```lua
-- ❌ DO NOT DO THIS ON ADDON LOAD / LOGIN!
function MyAddon_OnLoad()
    SetBinding("F9", "MYADDON_ACTION1")
    SaveBindings(GetCurrentBindingSet()) -- 💀 CRITICAL ERROR: Erases bindings-cache.wtf!
end
```

### Why It Breaks the Game
`SaveBindings(setID)` instructs the WoW engine to immediately flush the current in-memory keybinding table to disk at `WTF/Account/<AccountName>/<Server>/<Character>/bindings-cache.wtf`.

If `SaveBindings()` is invoked during loading screens, before keybindings finish synchronizing, or while binding tables are partially initialized, **WoW writes an empty keybinding structure to disk**, overwriting and permanently erasing all character hotkeys.

### The Proper Solution
1. **Never call `SaveBindings()` programmatically.**
2. Register bindings via `Bindings.xml` and register localized strings in Lua:
   ```lua
   _G["BINDING_HEADER_MYADDON_HEADER"] = "My AddOn"
   _G["BINDING_NAME_MYADDON_ACTION1"] = "Perform Action 1"
   ```
3. Allow players to bind keys through the official interface menu: `Main Menu ➔ Options ➔ Keybindings ➔ AddOns`. WoW will save the binding safely when the user accepts the menu changes.

---

## 🚫 DANGER ZONE #3: XML Manifests & Console Warnings

### The Problem
Including `Bindings.xml` inside `AddOnName.toc` or repeating binding headers causes severe client console warnings and parsing errors.

```ini
## ❌ DO NOT LIST Bindings.xml IN YOUR TOC FILE!
## Interface: 20504
## Title: MyAddon
Bindings.xml  <-- 💀 CRITICAL ERROR: Triggers "LUA_WARNING: Unrecognized XML: Binding"
MyAddon.lua
```

```xml
<!-- ❌ DO NOT REPEAT header="..." ON EVERY BINDING! -->
<Bindings>
    <Binding name="ACTION1" header="MY_HEADER"> ... </Binding>
    <Binding name="ACTION2" header="MY_HEADER"> ... </Binding> <!-- 💀 Triggers duplicate header warning -->
</Bindings>
```

### Why It Breaks
* Listing `Bindings.xml` in `.toc` sends the file to WoW's **FrameXML layout parser** rather than the **Keybinding parser**.
* The WoW engine automatically auto-detects `Bindings.xml` located in the root directory of any AddOn.

### The Proper Solution
1. **Omit `Bindings.xml` from `AddOnName.toc`**.
2. Put `header="HEADER_KEY"` **only on the first `<Binding>` entry** in `Bindings.xml`:
   ```xml
   <Bindings>
       <Binding category="ADDONS" name="MYADDON_ACT1" header="MYADDON_HEADER">
           MyAddon_Act1();
       </Binding>
       <Binding category="ADDONS" name="MYADDON_ACT2">
           MyAddon_Act2();
       </Binding>
   </Bindings>
   ```

---

## 🚫 DANGER ZONE #4: Combat Taint & Secure Execution (`ADDON_ACTION_BLOCKED`)

### The Problem
Calling `row:ClearAllPoints()` or `row:SetPoint()` during combat on a frame that inherits `"SecureActionButtonTemplate"` throws a severe combat taint block:

```
1x [ADDON_ACTION_BLOCKED] AddOn 'InnervateTracker' tried to call the protected function 'Button:ClearAllPoints()'.
```

### Why It Breaks
In World of Warcraft's C++ security engine, inheriting `SecureActionButtonTemplate` marks the frame as a **Secure / Protected Frame**. 
When in combat (`InCombatLockdown() == true`):
1. AddOns are **strictly forbidden** from calling layout or positioning methods (`ClearAllPoints()`, `SetPoint()`, `SetWidth()`, `SetHeight()`, `Show()`, `Hide()`, `SetParent()`, `SetAttribute()`) on any Secure Frame.
2. If an AddOn attempts to dynamically reposition or rebuild secure rows during combat (e.g. inside an `OnUpdate` or `GROUP_ROSTER_UPDATE` event handler), WoW blocks the call immediately with an `ADDON_ACTION_BLOCKED` error.

### The Proper Solution
1. **Do NOT use `SecureActionButtonTemplate` unless casting spells or targeting units.**
   If your frame only handles UI selection, toggling highlights, or sending whispers (`SendChatMessage`), **create a standard unprotected button**:
   ```lua
   -- ✅ SAFE: Standard unprotected Button (Can be re-anchored anytime in combat!)
   local row = CreateFrame("Button", nil, parentFrame)
   ```
2. **`SendChatMessage` for Whispers is NOT a Protected Function**:
   Whispering (`SendChatMessage("msg", "WHISPER", nil, "Name")`) is an unprotected Lua API in World of Warcraft that works anywhere—inside or outside of combat. Standard buttons can handle right-click whispers in `OnClick` directly without needing secure macro templates:
   ```lua
   row:SetScript("OnClick", function(self, button)
       if button == "RightButton" then
           SendChatMessage("Innervate please!", "WHISPER", nil, self.druidName)
       end
   end)
   ```
3. **If a Frame MUST be Secure**: Never call `ClearAllPoints()` or `SetPoint()` on it while `InCombatLockdown()` is true. Anchor secure frames once outside of combat or defer layout updates until `PLAYER_REGEN_ENABLED`.

---

## 🚫 DANGER ZONE #5: UI Layout Constraints & Text Wrapping in Compact Frames

### The Problem
In squeezed / compact AddOn frames (e.g., 170px width), standard `FontString` elements containing space-separated words will automatically wrap to a second line, breaking row alignment and overlapping adjacent UI elements.

```lua
-- ❌ Default FontString wraps on spaces!
local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetText("Malfurion (Absent)") -- Wraps to 2 lines, pushing UI out of bounds
```

### The Proper Solution
1. Explicitly disable word wrapping:
   ```lua
   text:SetWordWrap(false)
   ```
2. Set strict left and right anchor points to bound horizontal text expansion:
   ```lua
   text:SetPoint("LEFT", row.roleIcon, "RIGHT", 2)
   text:SetPoint("RIGHT", row.bar, "LEFT", -2)
   ```
3. Implement string truncation with a visual indicator (e.g., `*` suffix):
   ```lua
   local function FormatShortName(name)
       if #name > 7 then
           return string.sub(name, 1, 7) .. "*"
       end
       return name
   end
   ```

---

## 🚫 DANGER ZONE #6: Double Whispers & Input Debouncing

### The Problem
Triggering an action through multiple input pathways (e.g., keybind press + right-click macro + rapid key tapping) can cause dual executions, sending duplicate whispers or chat spam.

### The Proper Solution
Implement timestamp debouncing **at the very top** of execution entry points:

```lua
local lastWhisperTimes = {}

function MyAddon_WhisperSlot(slotIndex)
    local now = GetTime and GetTime() or time()
    
    -- 🛡️ Debounce Guard: Block duplicate calls within 0.5 seconds
    if lastWhisperTimes[slotIndex] and (now - lastWhisperTimes[slotIndex]) < 0.5 then
        return
    end
    
    lastWhisperTimes[slotIndex] = now -- Update timestamp BEFORE performing action
    
    -- Perform whisper logic...
end
```

---

## 🚫 DANGER ZONE #7: Texture Path Typos & API Backwards Compatibility

### The Problem
* **Texture Path Errors**: A single missing letter in a Blizzard texture string (e.g., `UI-LFG-ICON-PORTRAITOLES` missing the 'R' in `PORTRAIT`) causes textures to render as missing green boxes without generating Lua runtime errors.
* **API Incompatibilities**: Calling modern Retail APIs (such as `C_Spell.GetSpellInfo`) on older Classic/TBC builds without fallbacks causes nil function exceptions.

### The Proper Solution
1. **Verify Official Texture Paths**: Always verify exact texture paths against Blizzard's FrameXML source code:
   ```lua
   -- ✅ Official Blizzard Role Icon Texture
   row.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
   ```
2. **Use API Fallback Wrappers**:
   ```lua
   local function GetSpellName(id)
       if C_Spell and C_Spell.GetSpellInfo then
           local info = C_Spell.GetSpellInfo(id)
           return info and info.name
       elseif GetSpellInfo then
           return (GetSpellInfo(id))
       end
       return nil
   end
   ```

---

## 📋 AddOn Developer Quick Reference Checklist

| Feature | ❌ Dangerous Practice | ✅ Safe Best Practice |
| :--- | :--- | :--- |
| **Hotkeys** | `EnableKeyboard(true)` + `OnKeyDown` | Native `Bindings.xml` registration |
| **Saving Keys** | Calling `SaveBindings()` in Lua | Let WoW client handle key saving |
| **TOC File** | Listing `Bindings.xml` in `.toc` | Omit `Bindings.xml` from `.toc` |
| **Binding Headers** | Repeating `header="..."` per binding | Set `header="..."` on 1st entry only |
| **Combat Whispers** | Using `SecureActionButtonTemplate` on UI rows | Standard `Button` + direct `SendChatMessage` |
| **Text Layout** | Default `SetWordWrap(true)` | `SetWordWrap(false)` + strict anchors |
| **Spam Guard** | Instant execution on click/key | Time-based debouncing guard (`0.5s`) |
| **Spell API** | Calling modern API directly | Fallback check (`C_Spell` vs `GetSpellInfo`) |

---

*This guide was generated for World of Warcraft AddOn developers targeting TBC Anniversary / Classic Era (Interface `20504`).*
