--[[
	EXAMPLE LOCALSCRIPT
	Place this in StarterPlayer > StarterPlayerScripts as a LocalScript.
	Put GenericMinecraftClientUILib.lua in ReplicatedStorage as a ModuleScript named
	"GenericMinecraftClientUILib".

	Press RightShift to open or close the GUI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local camera = workspace.CurrentCamera

local Lib = require(ReplicatedStorage:WaitForChild("GenericMinecraftClientUILib"))

--------------------------------------------------------------------------------
-- 1. Create the window
--------------------------------------------------------------------------------
local Window = Lib:CreateWindow({
	Title = "Halcyon",
	Subtitle = "v1.0",
	Style = "Window", -- "Window" (tabs) or "Panels" (floating panels). Switch any time with Window:SetStyle().
	Theme = "Ice", -- Ice, Ember, Orchid, Lime, Mono, Light, or your own theme table
	Plan = "Pro", -- shown as a badge on the player card. Use nil to show "No plan".
	ToggleKey = Enum.KeyCode.RightShift,
	Blur = true, -- blur the game behind the GUI while it is open
})

-- Optional: let the Config buttons save to files if your environment has writefile/readfile.
-- FileAdapter returns nil when those functions do not exist, so this line is always safe.
Window.ConfigAdapter = Lib.FileAdapter("Halcyon")

--------------------------------------------------------------------------------
-- 2. A category with modules that do real things
--------------------------------------------------------------------------------
local Visuals = Window:CreateCategory("Visuals")

local original = { Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd }

-- Fullbright: a module (switch) with one setting.
local fullbright, brightness
local function applyFullbright()
	Lighting.Brightness = fullbright.Enabled and brightness.Value or original.Brightness
end
fullbright = Visuals:AddModule({
	Name = "Fullbright",
	Description = "Raises scene brightness so dark places are readable.",
	Keybind = Enum.KeyCode.B, -- the player can rebind it in the module's settings
	Suffix = function()
		return "x" .. brightness.Value -- shown dimmed after the name in the HUD module list
	end,
	Callback = applyFullbright, -- called with true / false
})
brightness = fullbright:AddSlider({
	Name = "Brightness",
	Min = 1,
	Max = 5,
	Step = 0.5,
	Default = 3,
	Callback = function()
		if fullbright.Enabled then
			applyFullbright()
		end
	end,
})

-- Zoom: Hold mode means it is only on while the key is held down.
local zoomFov
local zoom = Visuals:AddModule({
	Name = "Zoom",
	Description = "Narrow the field of view while the key is held.",
	Keybind = Enum.KeyCode.C,
	KeybindMode = "Hold",
	Callback = function(on)
		camera.FieldOfView = on and zoomFov.Value or 70
	end,
})
zoomFov = zoom:AddSlider({ Name = "FOV", Min = 10, Max = 60, Default = 25, Suffix = " deg" })

-- Time Changer: change the time of day for yourself.
local timeSlider
local timeChanger = Visuals:AddModule({
	Name = "Time Changer",
	Description = "Pick the time of day.",
	Callback = function(on)
		Lighting.ClockTime = on and timeSlider.Value or original.ClockTime
	end,
})
timeSlider = timeChanger:AddSlider({
	Name = "Clock time",
	Min = 0,
	Max = 24,
	Step = 0.5,
	Default = 18,
	Callback = function(v)
		if timeChanger.Enabled then
			Lighting.ClockTime = v
		end
	end,
})

-- Fog Distance
local fogSlider
local fog = Visuals:AddModule({
	Name = "Fog Distance",
	Description = "Push the fog further away.",
	Callback = function(on)
		Lighting.FogEnd = on and fogSlider.Value or original.FogEnd
	end,
})
fogSlider = fog:AddSlider({
	Name = "Distance",
	Min = 200,
	Max = 5000,
	Step = 100,
	Default = 2500,
	Callback = function(v)
		if fog.Enabled then
			Lighting.FogEnd = v
		end
	end,
})

--------------------------------------------------------------------------------
-- 3. A category that shows every control type
--------------------------------------------------------------------------------
local Controls = Window:CreateCategory("Controls")

local everything = Controls:AddModule({
	Name = "Every control",
	Description = "A tour of the settings controls.",
	Default = false,
})
everything:AddLabel({ Text = "Labels explain things. Keep them short." })
everything:AddToggle({
	Name = "Toggle",
	Default = true,
	Callback = function(v)
		print("Toggle ->", v)
	end,
})
everything:AddSlider({
	Name = "Slider",
	Min = 0,
	Max = 1,
	Step = 0.05,
	Default = 0.5,
	Callback = function(v)
		print("Slider ->", v)
	end,
})
everything:AddDropdown({
	Name = "Dropdown",
	Options = { "Alpha", "Beta", "Gamma" },
	Default = "Beta",
	Callback = function(v)
		print("Dropdown ->", v)
	end,
})
everything:AddDropdown({
	Name = "Multi dropdown",
	Options = { "Red", "Green", "Blue", "Yellow" },
	Multi = true,
	Default = { "Red", "Blue" },
	Callback = function(list)
		print("Multi ->", table.concat(list, ", "))
	end,
})
everything:AddSeparator()
everything:AddColorPicker({
	Name = "Color",
	Default = Color3.fromRGB(86, 214, 244),
	Callback = function(c)
		print("Color ->", c)
	end,
})
everything:AddTextbox({
	Name = "Text",
	Default = "hello",
	Placeholder = "type here",
	Callback = function(t)
		print("Text ->", t)
	end,
})
everything:AddTextbox({ Name = "Number", Numeric = true, Min = 0, Max = 100, Default = 10 })
local hotkey = everything:AddKeybind({ Name = "Hotkey", Default = Enum.KeyCode.G })
hotkey:OnPressed(function()
	Window:Notify({ Title = "Hotkey", Content = "You pressed the hotkey.", Type = "Info", Duration = 2 })
end)
everything:AddButton({
	Name = "Show notification",
	Callback = function()
		Window:Notify({ Title = "Hello", Content = "Notifications stack in the corner.", Type = "Success" })
	end,
})

--------------------------------------------------------------------------------
-- 4. HUD extras
--------------------------------------------------------------------------------
Window.HUD:AddInfo("Time", function()
	return os.date("%H:%M")
end)

--------------------------------------------------------------------------------
-- 5. Ready-made Interface category (theme, layout, HUD toggles, config)
--------------------------------------------------------------------------------
Window:AddInterfaceSettings()

Window:Notify({
	Title = "Halcyon loaded",
	Content = "Press RightShift to open the GUI.",
	Type = "Success",
})
