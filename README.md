# The Generic Minecraft Client UI Lib

A themeable click-GUI library for **Roblox (Luau)**, styled after a Minecraft client menu. You describe
your categories, modules and settings in a few lines of code; the library builds the whole interface,
the HUD, notifications and config handling for you.

**Version 1.0.0**  |  one file: `GenericMinecraftClientUILib.lua`

## What you get

- **Two layouts you can switch at runtime**
  - `Window`: one draggable window with a tab sidebar, module cards and a search bar.
  - `Panels`: one floating, draggable, collapsible panel per category.
- **Modules**: cards with an enable switch, a keybind (Toggle or Hold), a description and expandable settings.
- **Settings controls**: Toggle, Slider, Dropdown (single or multi select), Keybind, Textbox, ColorPicker, Button, Label, Separator.
- **HUD**: watermark, a live module list sorted by width, info lines (FPS and ping built in, add your own).
- **Notifications** that stack in the corner, and a **player card** with avatar, name and plan badge.
- **Full theming**: seven presets, your own themes, per-token overrides at runtime, a rainbow accent.
- **Config system**: every setting has a flag; export/import as JSON, optional save/load adapter.
- **Search** across all modules, **mobile open button**, optional **background blur**, **UI scale**.

---

## 1. Quick start (5 minutes)

### Step 1: add the library

1. In Roblox Studio, open **ReplicatedStorage**.
2. Insert a **ModuleScript** and name it exactly `GenericMinecraftClientUILib`.
3. Delete the default code and paste the entire contents of `GenericMinecraftClientUILib.lua`.

### Step 2: make a LocalScript

Insert a **LocalScript** into **StarterPlayer > StarterPlayerScripts** and paste this:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage:WaitForChild("GenericMinecraftClientUILib"))

-- 1. A window
local Window = Lib:CreateWindow({
	Title = "My Client",
	Subtitle = "v1.0",
	Theme = "Ice",
	Plan = "Pro",
})

-- 2. A category (a tab in Window style, a panel in Panels style)
local Visuals = Window:CreateCategory("Visuals")

-- 3. A module: a card with an on/off switch
local Fullbright = Visuals:AddModule({
	Name = "Fullbright",
	Description = "Makes dark places brighter.",
	Callback = function(enabled)
		game:GetService("Lighting").Brightness = enabled and 3 or 1
	end,
})

-- 4. Settings inside the module (open them with the arrow on the card)
Fullbright:AddSlider({
	Name = "Brightness",
	Min = 1, Max = 5, Step = 0.5, Default = 3,
	Callback = function(value)
		if Fullbright.Enabled then
			game:GetService("Lighting").Brightness = value
		end
	end,
})

-- 5. Settings for the GUI itself (theme, layout, HUD, config)
Window:AddInterfaceSettings()
```

### Step 3: press Play

Press **RightShift** to open or close the GUI. Click a card to switch the module on. Click the small
arrow on a card (or right-click it) to open its settings.

`Example.lua` in this folder is a larger LocalScript that uses every feature.

---

## 2. How it fits together

```
Lib
 └─ Window            Lib:CreateWindow({...})
     ├─ Category      Window:CreateCategory("Name")
     │   └─ Module    Category:AddModule({...})
     │       └─ Element   Module:AddToggle / AddSlider / AddDropdown / ...
     ├─ HUD           Window.HUD
     └─ Flags         Window.Flags["Category.Module"] = current value
```

- A **Module** is one card. It can be switched on and off (a *toggleable* module) or it can just hold
  settings (`Toggleable = false`).
- **Elements** are the controls inside a module's settings area. Each one holds a `Value`.
- **Callbacks** are plain functions you pass in. The library calls them with the new value whenever the
  value changes, and once at creation with the default value (turn that off with `CallOnInit = false`).
  An error inside a callback is caught and printed as a warning, it never breaks the GUI.
- Every value is stored under a **flag** (a unique string). Flags make config saving and loading work
  without any extra code from you. See [Flags and config](#flags-and-config).

---

## 3. Library reference

### `Lib:CreateWindow(options) -> Window`

Creates a window and returns it. Every option is optional.

| Option | Type | Default | What it does |
|---|---|---|---|
| `Title` | string | `"Client"` | Name shown in the sidebar, panel bar and HUD watermark. |
| `Subtitle` | string | `""` | Small text next to the watermark (a version, for example). |
| `Style` | `"Window"` or `"Panels"` | `"Window"` | Starting layout. Change later with `Window:SetStyle()`. |
| `Theme` | string or table | `"Ice"` | Preset name or a theme table. See [Theming](#theming). |
| `Accent` | Color3 | from theme | Quick accent color override. |
| `Accent2` | Color3 | derived | Second gradient color. Derived from `Accent` if left out. |
| `Rainbow` | boolean | `false` | Cycle the accent through the rainbow. |
| `RainbowSpeed` | number | `4` | Rainbow speed, 1 to 10. |
| `ToggleKey` | Enum.KeyCode | `RightShift` | Key that opens and closes the GUI. |
| `StartVisible` | boolean | `true` | Open the GUI right away. |
| `Size` | Vector2 | `700 x 460` | Size of the window (Window style). |
| `Position` | UDim2 | centered | Starting position of the window. |
| `Columns` | number | `2` | Columns of module cards per page, 1 to 4 (Window style). |
| `ShowDescriptions` | boolean | `true` | Show module descriptions on cards (Window style). |
| `PanelWidth` | number | `220` | Width of each panel (Panels style). |
| `PanelMaxHeight` | number | `360` | Tallest a panel's module list gets before it scrolls (Panels style). |
| `Scale` | number | `1` | UI scale, 0.5 to 2. |
| `Blur` | boolean or number | `false` | Blur the game behind the GUI. A number sets the blur size (default 14). |
| `Dim` | boolean | `true` | Darken the game behind the GUI. |
| `DimTransparency` | number | `0.55` | 0 is black, 1 is invisible. |
| `Plan` | string | `nil` | Plan badge on the player card. Leave it out and no badge is shown at all. |
| `NoPlanText` | string | `nil` | Optional text to show when there is no plan, for example `"Free"`. Leave it out to show nothing. |
| `PlanColors` | table | built in | `{ PlanName = Color3 }`. Merged over the defaults (Plus, Pro, Premium, Lifetime). |
| `PlayerCard` | boolean | `true` | Show the player card. |
| `Watermark` | boolean | `true` | Show the HUD watermark. |
| `ModuleList` | boolean | `true` | Show the HUD list of enabled modules. |
| `InfoLines` | boolean | `true` | Show the HUD info box (FPS, ping, yours). |
| `Notifications` | boolean | `true` | Allow `Window:Notify()`. `false` silences all notifications. |
| `NotifyOnToggle` | boolean | `true` | Show a toast whenever a module is switched. |
| `ConfigAdapter` | table | `nil` | Where configs are saved. See [Flags and config](#flags-and-config). |
| `MobileButton` | boolean | `true` | Floating open button on touch devices while the GUI is hidden. |
| `Parent` | Instance | `PlayerGui` | Where the ScreenGui is placed. |
| `Name` | string | `"GenericMCUI"` | Name of the ScreenGui. |
| `DisplayOrder` | number | `1000` | DisplayOrder of the ScreenGui. |

### Other `Lib` members

| Member | Description |
|---|---|
| `Lib.Version`, `Lib.Name` | Version string and library name. |
| `Lib.Themes` | Table of theme presets: `Ice`, `Ember`, `Orchid`, `Lime`, `Mono`, `Crimson`, `Light`. |
| `Lib.DefaultTheme` | Name of the preset used when `Theme` is not given. Defaults to `"Ice"`. |
| `Lib:RegisterTheme(name, tokens)` | Adds a theme to `Lib.Themes`. Missing tokens are filled from the default theme. |
| `Lib:GetThemeNames()` | Sorted list of theme names. |
| `Lib.FileAdapter(folder)` | Returns a config adapter that uses `writefile` and `readfile`, or `nil` when your environment has no such functions. |
| `Lib.Windows` | List of all live windows. |
| `Lib:Unload()` | Destroys every window. |
| `Lib.Util` | Helpers for power users: `Create(class, props)`, `Tween(inst, time, props)`, `Signal`. |

---

## 4. Window reference

### Methods

| Method | Description |
|---|---|
| `Window:CreateCategory(name, opts?)` | Adds a category and returns it. `opts.Icon` is an optional `rbxassetid://` image for the sidebar tab. Aliases: `AddCategory`, `CreateTab`. |
| `Window:AddInterfaceSettings(name?)` | Adds a ready-made category (default name `"Interface"`) with theme, layout, HUD and config controls. |
| `Window:GetCategory(name)` | Returns a category or `nil`. |
| `Window:GetModule(nameOrFlag)` | Finds a module by its name or its flag. |
| `Window:SelectCategory(categoryOrName)` | Opens a category tab (Window style). |
| `Window:SetStyle("Window" or "Panels")` | Switches the layout. Everything is kept. |
| `Window:SetVisible(boolean)` / `Window:Toggle()` | Opens or closes the GUI. |
| `Window:SetToggleKey(keyCode)` | Changes the open/close key. |
| `Window:SetScale(number)` | UI scale, 0.5 to 2. |
| `Window:SetSize(Vector2)` | Window size (Window style). |
| `Window:SetTitle(title, subtitle?)` | Renames the window everywhere. |
| `Window:SetTheme(nameOrTable)` | Applies a preset or a theme table. |
| `Window:SetThemeToken(token, value)` | Changes one theme token, for example `("Corner", 8)`. |
| `Window:SetAccent(color, color2?)` | Changes the accent color. |
| `Window:SetRainbow(enabled, speed?)` | Turns the rainbow accent on or off. |
| `Window:SetPlayerCard(info)` | `info = { Name = "Steve", Plan = "Pro", Avatar = userId or "rbxassetid://..." }`. Use `Plan = false` to remove the plan. `NoPlanText = "Free"` shows text when there is no plan. |
| `Window:Notify(options)` | Shows a toast. See [Notifications](#notifications). |
| `Window:GetFlag(flag)` / `Window:SetFlag(flag, value)` | Read or write any value by its flag. |
| `Window:ExportConfig()` | Returns all values as a JSON string. |
| `Window:ImportConfig(json)` | Applies a JSON string. Returns `true`, or `false, reason`. |
| `Window:SaveConfig(name)` / `Window:LoadConfig(name)` / `Window:ListConfigs()` | Use `ConfigAdapter`. |
| `Window:Destroy()` | Removes the window and disconnects everything. |

### Properties and signals

| Member | Description |
|---|---|
| `Window.Flags` | Table of `flag -> current value`. |
| `Window.HUD` | HUD object. See [HUD](#hud). |
| `Window.Style`, `Window.Visible`, `Window.Theme` | Current state. `Theme` is the live token table. |
| `Window.Categories`, `Window.Modules` | Lists you can loop over. |
| `Window.ShowDescriptions`, `Window.NotifyOnToggle`, `Window.ConfigAdapter` | Settings you can change at any time. |
| `Window.Toggled` | Signal. Fires `(visible)` when the GUI opens or closes. |
| `Window.StyleChanged` | Signal. Fires `(style)`. |
| `Window.FlagChanged` | Signal. Fires `(flag, value)` for every change. |
| `Window.Gui`, `Window.Root`, `Window.Main`, `Window.PanelsHost` | The raw Instances, for advanced customisation. |

Signals work like Roblox events: `local conn = Window.Toggled:Connect(function(visible) ... end)` and
`conn:Disconnect()`.

---

## 5. Categories

```lua
local Combat = Window:CreateCategory("Combat")
```

| Member | Description |
|---|---|
| `Category:AddModule(options)` | Adds a module card. Aliases: `Add`, `CreateModule`. |
| `Category:GetModule(name)` | Finds a module in this category. |
| `Category:Select()` | Opens this tab. |
| `Category:SetCollapsed(boolean)` | Collapses or expands the panel (Panels style). |
| `Category.Name`, `Category.Modules` | The name and the module list. |

---

## 6. Modules

```lua
local Zoom = Visuals:AddModule({
	Name = "Zoom",
	Description = "Narrows the field of view while the key is held.",
	Keybind = Enum.KeyCode.C,
	KeybindMode = "Hold",
	Callback = function(enabled) ... end,
})
```

### Options

| Option | Type | Default | What it does |
|---|---|---|---|
| `Name` | string | `"Module"` | Title of the card. |
| `Description` / `Desc` | string | `""` | Text under the title (Window style). |
| `Toggleable` | boolean | `true` | `false` makes a settings-only card with no switch. |
| `Default` | boolean | `false` | Start switched on. |
| `Keybind` | Enum.KeyCode | `nil` | Starting key. The player can rebind it in the card's settings. |
| `KeybindMode` | `"Toggle"` or `"Hold"` | `"Toggle"` | Hold means on only while the key is down. |
| `Callback` | function(enabled) | `nil` | Called on every change. |
| `Suffix` | string or function | `nil` | Dim text after the name in the HUD module list. A function is re-read when the list rebuilds. |
| `HideFromList` | boolean | `false` | Keep this module out of the HUD module list. |
| `NoKeybind` | boolean | `false` | Do not add the keybind and bind-mode settings. |
| `Flag` | string | `"Category.Name"` | Custom flag. Must be unique (the library adds `#2` if it is not). |

### Methods and members

| Member | Description |
|---|---|
| `Module:SetEnabled(boolean, silent?)` | Switch on or off. `silent = true` skips callbacks and signals. |
| `Module:Toggle()` | Flip the state. |
| `Module:Get()` / `Module.Enabled` | Current state. |
| `Module:OnChanged(fn)` / `Module.Changed` | Signal, fires `(enabled)`. |
| `Module:SetKeybind(keyCode or nil)` | Change or clear the key. |
| `Module:SetSuffix(textOrFunction)` | Change the HUD list suffix, for example to show a mode. |
| `Module:SetVisible(boolean)` | Hide or show the card. |
| `Module:SetName(name)` | Rename the card. |
| `Module:SetOpen(boolean)` | Open or close the settings area. |
| `Module:Destroy()` | Remove the card and all its settings. |
| `Module.Elements`, `Module.Card`, `Module.Flag` | The setting list, the card Instance and the flag. |

On every toggleable module the library adds two settings at the top: **Keybind** and **Bind mode**.

---

## 7. Elements (settings controls)

Add them to a module with the methods below. Each returns the element.

```lua
local slider = Module:AddSlider({ Name = "Range", Min = 1, Max = 10, Default = 4 })
print(slider.Value)      -- read
slider:Set(7)            -- write (fires callbacks)
slider:Set(7, true)      -- write silently
```

### Options shared by all value controls

| Option | Default | What it does |
|---|---|---|
| `Name` | the kind name | Label shown next to the control. |
| `Default` | depends on control | Starting value. |
| `Callback` | `nil` | `function(value)`. Called on change. |
| `Flag` | `Module.Flag .. "/" .. Name` | Unique id for config saving. |
| `CallOnInit` | `true` | Call the callback once with the starting value. |
| `NoSave` | `false` | Leave this control out of exported configs. |
| `Visible` | `true` | Start hidden with `false`. |

### Methods shared by all value controls

| Member | Description |
|---|---|
| `el:Get()` / `el.Value` | Current value. |
| `el:Set(value, silent?)` | Change the value. |
| `el:OnChanged(fn)` / `el.Changed` | Signal, fires `(value)`. |
| `el:SetVisible(boolean)` | Hide or show the row. |
| `el:Destroy()` | Remove the control. |

### Control types

| Method | Value | Extra options and members |
|---|---|---|
| `AddToggle` | boolean | `Default` (false). |
| `AddSlider` | number | `Min` (0), `Max` (100), `Step` (1), `Suffix` (`" px"`), `Default` (Min). `el:SetRange(min, max)`. Decimal steps like `0.05` work. |
| `AddDropdown` | string (or list when `Multi`) | `Options` (list of strings), `Multi` (false), `Default`. `el:SetOptions(list, keepValue?)` replaces the options at runtime. A multi dropdown's value is a list in option order. |
| `AddKeybind` | Enum.KeyCode or nil | `Default`. `el.Pressed` signal and `el:OnPressed(fn)` fire when the key is pressed. Esc, Backspace or Delete clears the key while rebinding. |
| `AddTextbox` | string (or number) | `Placeholder`, `ClearOnFocus` (false), `Numeric` (false), `Min`, `Max` (for numeric). Value is committed when the box loses focus. |
| `AddColorPicker` | Color3 | `Default`. Click the swatch to open the picker. |
| `AddButton` | none | `Name` or `Text`, `Callback` (no arguments). `el:OnClick(fn)`, `el:SetText(text)`. |
| `AddLabel` | none | `Text`, `Dim` (true). `el:SetText(text)`. Alias `AddParagraph`. |
| `AddSeparator` | none | A thin divider line. |

`Module:Add(kind, options)` is the generic form: `Module:Add("Slider", {...})`.

---

## 8. HUD

The HUD stays on screen when the GUI is closed.

```lua
Window.HUD:SetVisible("ModuleList", false)           -- "Watermark", "ModuleList" or "Info"
Window.HUD:SetWatermark("Halcyon", "build 42")
Window.HUD:AddInfo("Position", function()            -- refreshed 4 times a second
	local root = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	return root and string.format("%d, %d, %d", root.Position.X, root.Position.Y, root.Position.Z) or "-"
end)
Window.HUD:RemoveInfo("Position")
```

- **Watermark**: logo, title and subtitle at the top left.
- **Module list**: top right, every enabled module (except `HideFromList`), widest first, with an accent gradient dot.
- **Info box**: bottom left. FPS and Ping are built in.

---

## 9. Notifications

```lua
Window:Notify({
	Title = "Saved",
	Content = "Your config was saved.",
	Type = "Success",   -- "Info" (default), "Success", "Warning" or "Error"
	Duration = 3,       -- seconds
})
Window:Notify("A plain string works too.")
```

Notifications appear at the bottom right. `NotifyOnToggle = false` turns off the automatic toast when
modules are switched.

---

## 10. Theming

A theme is a table of **tokens**. Every colour and size in the GUI reads from these tokens, so changing one
token restyles everything instantly.

| Token | Type | Used for |
|---|---|---|
| `Background` | Color3 | Sidebar tint, deepest layer. |
| `Surface` | Color3 | Window, panels, HUD boxes, toasts. |
| `SurfaceAlt` | Color3 | Module cards, inputs. |
| `Stroke` | Color3 | Borders and divider lines. |
| `Text` | Color3 | Main text. |
| `TextDim` | Color3 | Secondary text. |
| `Accent`, `Accent2` | Color3 | Switches, sliders, highlights and gradients. |
| `Success`, `Warning`, `Danger` | Color3 | Notification colors, the online dot. |
| `Corner` | number | Base corner radius in pixels. |
| `Transparency` | number | Window and panel background transparency, 0 to 1. |
| `StrokeTransparency` | number | Border transparency, 0 to 1. |
| `Font`, `FontBold`, `FontMono` | Enum.Font | Normal, bold and number/code fonts. |

### Use a preset

```lua
Lib:CreateWindow({ Theme = "Ember" })   -- Ice, Ember, Orchid, Lime, Mono, Crimson, Light
Window:SetTheme("Orchid")
```

### Make your own

```lua
-- Start from a preset ("Base") and change only what you want:
local Window = Lib:CreateWindow({
	Theme = {
		Base = "Mono",
		Accent = Color3.fromRGB(255, 170, 0),
		Corner = 6,
		Transparency = 0.15,
		Font = Enum.Font.Ubuntu,
		FontBold = Enum.Font.Ubuntu,
	},
})

-- Or register it once and reuse it by name:
Lib:RegisterTheme("Sunset", { Base = "Ember", Accent = Color3.fromRGB(255, 120, 50) })
Window:SetTheme("Sunset")
```

When a theme table has no `Accent2`, one is derived from `Accent`. Tokens you leave out come from the `Base`
preset (or the default theme).

### Change things while running

```lua
Window:SetThemeToken("Corner", 4)              -- one token
Window:SetAccent(Color3.fromRGB(255, 80, 120)) -- accent
Window:SetRainbow(true, 6)                     -- rainbow accent, speed 6
Window:SetRainbow(false)                       -- back to the chosen accent
Window:SetScale(1.2)
```

`Window:AddInterfaceSettings()` gives your players all of this as controls: preset, accent picker, rainbow,
corner radius, opacity, GUI scale, layout switch, descriptions toggle, toggle key and HUD switches.

---

## 11. Flags and config

Every value control, every module switch, every module keybind and bind mode has a **flag**.

| What | Flag |
|---|---|
| Module switch | `"Category.Module"` |
| Module keybind | `"Category.Module.Bind"` |
| Module bind mode | `"Category.Module.Mode"` |
| Setting | `"Category.Module/Setting name"` |

```lua
print(Window.Flags["Visuals.Fullbright"])               -- true / false
Window:SetFlag("Visuals.Fullbright/Brightness", 4)      -- set a value by flag
Window.FlagChanged:Connect(function(flag, value)
	print(flag, "=", value)
end)
```

### Export and import

```lua
local json = Window:ExportConfig()      -- {"version":1,"flags":{...}}
Window:ImportConfig(json)               -- true, or false + reason
```

Importing applies every value and fires the normal callbacks. Colors, keys and multi-selects are handled for you.

### Saving to files

`Window.ConfigAdapter` is any table with these functions:

```lua
Window.ConfigAdapter = {
	Write = function(name, text) ... end,   -- store text under a name
	Read  = function(name) ... end,         -- return the text, or nil
	List  = function() ... end,             -- return a list of names (optional)
}
```

If your environment provides `writefile` and `readfile`, one line is enough:

```lua
Window.ConfigAdapter = Lib.FileAdapter("MyClient")   -- nil if those functions do not exist
```

Then use `Window:SaveConfig("default")`, `Window:LoadConfig("default")` and `Window:ListConfigs()`, or the
buttons in the Interface category. Roblox itself has no file access, so on a plain Roblox client you can
write an adapter around DataStores through a RemoteFunction, or just copy the JSON from `ExportConfig()`.

---

## 12. Cookbook

**A module that only holds settings (no switch)**
```lua
local Tools = Window:CreateCategory("Tools")
local Info = Tools:AddModule({ Name = "Server", Toggleable = false })
Info:AddButton({ Name = "Print player count", Callback = function()
	print(#game.Players:GetPlayers())
end })
```

**Hold to activate**
```lua
Visuals:AddModule({ Name = "Zoom", Keybind = Enum.KeyCode.C, KeybindMode = "Hold",
	Callback = function(on) workspace.CurrentCamera.FieldOfView = on and 30 or 70 end })
```

**Show a mode next to the name in the HUD list**
```lua
local Mode = Mod:AddDropdown({ Name = "Mode", Options = { "Fast", "Safe" }, Default = "Fast",
	Callback = function(v) Mod:SetSuffix(v) end })
```

**Dropdown whose options change**
```lua
local Players = game:GetService("Players")
local Target = Mod:AddDropdown({ Name = "Player", Options = {} })
local function refresh()
	local names = {}
	for _, p in ipairs(Players:GetPlayers()) do names[#names + 1] = p.Name end
	Target:SetOptions(names, true)   -- true keeps the current value if it still exists
end
Players.PlayerAdded:Connect(refresh)
Players.PlayerRemoving:Connect(refresh)
refresh()
```

**React to a module without using its Callback**
```lua
Fullbright:OnChanged(function(on) print("Fullbright", on) end)
```

**Start in Panels style, let the player switch**
```lua
local Window = Lib:CreateWindow({ Title = "My Client", Style = "Panels" })
Window:AddInterfaceSettings()   -- adds Layout > Style dropdown
```

**Several controls hidden until a toggle is on**
```lua
local advanced = Mod:AddToggle({ Name = "Advanced" })
local extra = Mod:AddSlider({ Name = "Extra", Min = 0, Max = 10, Visible = false })
advanced:OnChanged(function(on) extra:SetVisible(on) end)
```

**Your own toggle key and a quick "panic" button**
```lua
Window:SetToggleKey(Enum.KeyCode.Insert)
local panic = Window:CreateCategory("Safety"):AddModule({ Name = "Panic", Toggleable = false })
panic:AddButton({ Name = "Disable everything", Callback = function()
	for _, m in ipairs(Window.Modules) do m:SetEnabled(false) end
end })
```

**Restyle a piece directly**
```lua
-- Every part is a normal Instance. Modules expose their card:
Fullbright.Card.BackgroundColor3 = Color3.fromRGB(40, 20, 60)
-- Window.Main, Window.Root and Window.Gui are available too.
```

---

## 13. Troubleshooting

| Problem | Fix |
|---|---|
| Nothing shows up | The code must run in a **LocalScript**. Check `Window.Visible`, and that `ToggleKey` is not already used by something else. |
| `require` fails | The ModuleScript must be named `GenericMinecraftClientUILib` and sit where your `WaitForChild` looks. |
| A keybind does nothing | Keybinds are ignored while typing in a text box (including the chat). Check that no other module uses the same key. |
| A callback errors | The error is printed as `[GenericMCUI] callback error: ...` and the GUI keeps working. |
| Two flags clash | The second gets `#2` appended. Set `Flag = "Your.Unique.Name"` yourself to keep configs stable. |
| Config values do not load | Flags must match. Renaming a module or a setting changes its flag. |
| GUI blocks your own `ScreenGui` | Raise or lower `DisplayOrder` in `CreateWindow`. |
| Want it in a protected container | Pass `Parent = yourContainer` to `CreateWindow`. |
| Looks too big or small | Use `Scale`, or `Window:SetScale(0.8)`. |

### Good to know

- Library code uses only standard Roblox APIs. File saving is optional and only works where `writefile` and
  `readfile` exist.
- Modules and settings can be added at any time, even after the GUI is open.
- Creating several windows is supported. Give each its own `Name`.
- The library was checked by running the full example and 85 assertions against a mock of the Roblox API
  (module toggles, keybinds, hold mode, slider and colour dragging, search, style switching, themes, config
  round trips, notifications, destroy). It has not been run inside Roblox Studio, so if something looks
  off in the engine, check the Output window for warnings and report the line.
