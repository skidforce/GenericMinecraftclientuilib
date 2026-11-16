--!nonstrict
--[[
	THE GENERIC MINECRAFT CLIENT UI LIB            v1.0.0

	A themeable click-GUI library for Roblox (Luau) in the style of a Minecraft client:
	  * two layouts you can switch at runtime: "Window" (sidebar tabs) and "Panels" (floating category panels)
	  * modules with enable switches, keybinds (Toggle / Hold) and expandable settings
	  * settings controls: Toggle, Slider, Dropdown (single/multi), Keybind, Textbox, ColorPicker, Button, Label
	  * HUD (watermark, live module list, info lines), notifications, player card with plan badge
	  * full theme system, rainbow accent, config export/import, optional save/load adapter

	Read README.md for the quick start and the complete API reference.
	Put this file in a ModuleScript (for example ReplicatedStorage.GenericMinecraftClientUILib)
	and require it from a LocalScript.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

local Lib = {
	Name = "The Generic Minecraft Client UI Lib",
	Version = "1.0.0",
	Windows = {},
}

local Window, Category, Module, Element = {}, {}, {}, {}
Window.__index = Window
Category.__index = Category
Module.__index = Module
Element.__index = Element
local Elements = {}
local Hud = {}
Hud.__index = Hud

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function safeCall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[GenericMCUI] callback error: " .. tostring(err))
	end
	return ok
end

local function merge(base, extra)
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	if extra then
		for k, v in pairs(extra) do
			out[k] = v
		end
	end
	return out
end

local function clamp(n, lo, hi)
	if n < lo then
		return lo
	elseif n > hi then
		return hi
	end
	return n
end

local function decimals(step)
	local d = string.match(tostring(step), "%.(%d+)")
	return d and #d or 0
end

local function fmtNum(n, step)
	return string.format("%." .. decimals(step or 1) .. "f", n)
end

local function snap(v, min, max, step)
	step = step or 1
	v = math.floor((v - min) / step + 0.5) * step + min
	v = clamp(v, min, max)
	return tonumber(fmtNum(v, step))
end

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

local function shiftHue(c, d)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV((h + d) % 1, s, v)
end

local function new(class, props, children)
	local inst = Instance.new(class)
	local parent
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function tween(inst, time, props, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local KEY_SHORT = {
	LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
	LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", Backspace = "Bksp",
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	Backquote = "`", Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]", Semicolon = ";",
	Quote = "'", Comma = ",", Period = ".", Slash = "/", BackSlash = "\\",
}

local function keyName(key)
	if not key then
		return "None"
	end
	return KEY_SHORT[key.Name] or key.Name
end

local function toKeyCode(v)
	if v == nil then
		return nil
	end
	if type(v) == "string" then
		local ok, kc = pcall(function()
			return Enum.KeyCode[v]
		end)
		return ok and kc or nil
	end
	return v
end

-- Pointer position in the same coordinate space as GuiObject.AbsolutePosition.
-- The ScreenGui ignores the top bar inset, so raw screen coordinates line up with it.
local function pointerPos(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseMovement then
		return UserInputService:GetMouseLocation()
	end
	return Vector2.new(input.Position.X, input.Position.Y)
end

-- Signal -----------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _list = {} }, Signal)
end

function Signal:Connect(fn)
	local list = self._list
	local conn = { Connected = true, _fn = fn }
	list[#list + 1] = conn
	function conn.Disconnect()
		conn.Connected = false
		for i, c in ipairs(list) do
			if c == conn then
				table.remove(list, i)
				break
			end
		end
	end
	return conn
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	local snapshot = {}
	for i, c in ipairs(self._list) do
		snapshot[i] = c
	end
	for _, c in ipairs(snapshot) do
		if c.Connected then
			safeCall(c._fn, ...)
		end
	end
end

-- Serialization (config) -------------------------------------------------------

local function serialize(v)
	local t = typeof(v)
	if v == nil then
		return { t = "None" }
	elseif t == "Color3" then
		return { t = "Color3", r = v.R, g = v.G, b = v.B }
	elseif t == "EnumItem" then
		return { t = "KeyCode", n = v.Name }
	elseif t == "table" then
		local out = {}
		for i, item in ipairs(v) do
			out[i] = item
		end
		return { t = "List", v = out }
	end
	return v
end

local function deserialize(v)
	if type(v) ~= "table" then
		return v
	end
	if v.t == "None" then
		return nil
	elseif v.t == "Color3" then
		return Color3.new(v.r or 0, v.g or 0, v.b or 0)
	elseif v.t == "KeyCode" then
		return toKeyCode(v.n)
	elseif v.t == "List" then
		return v.v or {}
	end
	return v
end

--------------------------------------------------------------------------------
-- Themes
--------------------------------------------------------------------------------

local function makeTheme(accent, accent2, extra)
	local t = {
		Background = Color3.fromRGB(9, 11, 17),
		Surface = Color3.fromRGB(19, 21, 31),
		SurfaceAlt = Color3.fromRGB(29, 32, 45),
		Stroke = Color3.fromRGB(255, 255, 255),
		Text = Color3.fromRGB(243, 245, 251),
		TextDim = Color3.fromRGB(143, 151, 172),
		Accent = accent,
		Accent2 = accent2,
		Success = Color3.fromRGB(61, 220, 132),
		Warning = Color3.fromRGB(255, 193, 77),
		Danger = Color3.fromRGB(255, 94, 94),
		Corner = 14,
		Transparency = 0.04,
		StrokeTransparency = 0.9,
		Font = Enum.Font.GothamMedium,
		FontBold = Enum.Font.GothamBold,
		FontMono = Enum.Font.Code,
	}
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return t
end

Lib.Themes = {
	Ice = makeTheme(Color3.fromRGB(86, 214, 244), Color3.fromRGB(104, 112, 246)),
	Ember = makeTheme(Color3.fromRGB(255, 122, 76), Color3.fromRGB(255, 76, 130)),
	Orchid = makeTheme(Color3.fromRGB(196, 112, 255), Color3.fromRGB(110, 120, 255)),
	Lime = makeTheme(Color3.fromRGB(150, 240, 90), Color3.fromRGB(60, 210, 150)),
	Mono = makeTheme(Color3.fromRGB(235, 235, 240), Color3.fromRGB(150, 150, 165)),
	Light = makeTheme(Color3.fromRGB(34, 120, 255), Color3.fromRGB(120, 80, 255), {
		Background = Color3.fromRGB(226, 229, 238),
		Surface = Color3.fromRGB(246, 247, 251),
		SurfaceAlt = Color3.fromRGB(233, 236, 244),
		Stroke = Color3.fromRGB(0, 0, 0),
		StrokeTransparency = 0.88,
		Text = Color3.fromRGB(20, 23, 34),
		TextDim = Color3.fromRGB(99, 108, 130),
	}),
}
Lib.DefaultTheme = "Ice"

local function resolveTheme(x)
	local base = Lib.Themes[Lib.DefaultTheme]
	if type(x) == "string" then
		return merge(Lib.Themes[x] or base)
	elseif type(x) == "table" then
		local b = (x.Base and Lib.Themes[x.Base]) or base
		local t = merge(b, x)
		t.Base = nil
		if x.Accent and not x.Accent2 then
			t.Accent2 = shiftHue(x.Accent, 0.12)
		end
		return t
	end
	return merge(base)
end

function Lib:RegisterTheme(name, tokens)
	Lib.Themes[name] = resolveTheme(tokens)
	return Lib.Themes[name]
end

function Lib:GetThemeNames()
	local names = {}
	for name in pairs(Lib.Themes) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

--------------------------------------------------------------------------------
-- Window: theming + small widget helpers
--------------------------------------------------------------------------------

-- Binds an instance property to a theme token. `mod(value, theme)` can transform it.
function Window:_bind(inst, prop, token, mod)
	local group = self._binds[token]
	if not group then
		group = setmetatable({}, { __mode = "k" })
		self._binds[token] = group
	end
	local list = group[inst]
	if not list then
		list = {}
		group[inst] = list
	end
	list[#list + 1] = { prop, mod }
	local value = self.Theme[token]
	if mod then
		value = mod(value, self.Theme)
	end
	inst[prop] = value
end

-- Registers a function that re-applies state based styling after the theme changed.
function Window:_refreshable(key, fn)
	self._refreshers[key] = fn
	fn()
end

function Window:_refreshTokens(tokens)
	for token, group in pairs(self._binds) do
		if not tokens or tokens[token] then
			local value = self.Theme[token]
			for inst, list in pairs(group) do
				for _, e in ipairs(list) do
					local v = value
					if e[2] then
						v = e[2](value, self.Theme)
					end
					inst[e[1]] = v
				end
			end
		end
	end
	for _, fn in pairs(self._refreshers) do
		fn()
	end
end

function Window:_conn(connection)
	self._conns[#self._conns + 1] = connection
	return connection
end

function Window:_corner(inst, factor)
	local c = new("UICorner", { Parent = inst })
	factor = factor or 1
	self:_bind(c, "CornerRadius", "Corner", function(v)
		return UDim.new(0, math.floor(v * factor))
	end)
	return c
end

function Window:_pill(inst)
	return new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = inst })
end

function Window:_stroke(inst)
	local s = new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Parent = inst })
	self:_bind(s, "Color", "Stroke")
	self:_bind(s, "Transparency", "StrokeTransparency")
	return s
end

-- Slightly lighter (or darker for Light theme) fill used by inputs inside cards.
function Window:_field(inst, prop, amount)
	amount = amount or 0.09
	self:_bind(inst, prop or "BackgroundColor3", "SurfaceAlt", function(c, T)
		return c:Lerp(T.Text, amount)
	end)
end

function Window:_label(props, kind)
	local l = new("TextLabel", merge({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, props))
	self:_bind(l, "TextColor3", kind == "dim" and "TextDim" or "Text")
	self:_bind(l, "Font", (kind == "bold" or kind == "title") and "FontBold" or (kind == "mono" and "FontMono" or "Font"))
	return l
end

function Window:_gradient(inst)
	local g = new("UIGradient", { Rotation = 45, Parent = inst })
	self:_bind(g, "Color", "Accent", function(c, T)
		return ColorSequence.new(c, T.Accent2)
	end)
	return g
end

function Window:_button(props)
	return new("TextButton", merge({
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, props))
end

function Window:_trackDrag(target, onMove, onEnd)
	local dragging = false
	target.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			onMove(pointerPos(input))
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					c:Disconnect()
					if onEnd then
						onEnd()
					end
				end
			end)
		end
	end)
	self:_conn(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			onMove(pointerPos(input))
		end
	end))
end

function Window:_makeDraggable(handle, target, keepOnScreen)
	local dragging, startPos, startMouse = false, nil, nil
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = target.Position
			startMouse = input.Position
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					c:Disconnect()
				end
			end)
		end
	end)
	self:_conn(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local s = self._scaler.Scale
			local x = startPos.X.Offset + (input.Position.X - startMouse.X) / s
			local y = startPos.Y.Offset + (input.Position.Y - startMouse.Y) / s
			if keepOnScreen then
				local rs = self.Root.AbsoluteSize
				local ts = target.AbsoluteSize
				x = clamp(x, 0, math.max(0, rs.X / s - ts.X / s))
				y = clamp(y, 0, math.max(0, rs.Y / s - 40))
			end
			target.Position = UDim2.new(startPos.X.Scale, x, startPos.Y.Scale, y)
		end
	end))
end

--------------------------------------------------------------------------------
-- Elements (settings controls)
--------------------------------------------------------------------------------

function Element:Get()
	return self.Value
end

function Element:Set(value, silent)
	self:_commit(value, silent)
end

function Element:OnChanged(fn)
	return self.Changed:Connect(fn)
end

function Element:SetVisible(visible)
	self.Row.Visible = visible and true or false
end

function Element:Destroy()
	local W = self.Window
	if self.Flag then
		W._elements[self.Flag] = nil
		W._flagObjs[self.Flag] = nil
		W.Flags[self.Flag] = nil
	end
	W._refreshers[self] = nil
	local i = indexOf(self.Owner.Elements, self)
	if i then
		table.remove(self.Owner.Elements, i)
	end
	local k = indexOf(W._keyElements, self)
	if k then
		table.remove(W._keyElements, k)
	end
	self.Row:Destroy()
end

function Element:_commit(value, silent)
	self:_apply(value)
	if self.Flag then
		self.Window.Flags[self.Flag] = self.Value
	end
	if not silent then
		self.Changed:Fire(self.Value)
		if self.Flag then
			self.Window.FlagChanged:Fire(self.Flag, self.Value)
		end
		if self.Callback then
			safeCall(self.Callback, self.Value)
		end
	end
end

-- Toggle -----------------------------------------------------------------------

Elements.Toggle = function(el, W, row, opts)
	el.Default = false
	row.Size = UDim2.new(1, 0, 0, 24)
	W:_label({ Parent = row, Text = el.Name, Size = UDim2.new(1, -48, 1, 0) })
	local sw = W:_button({
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(34, 18),
	})
	W:_pill(sw)
	local knob = new("Frame", {
		Parent = sw,
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	})
	W:_pill(knob)
	local function paint(instant)
		local T = W.Theme
		local on = el.Value
		local color = on and T.Accent or T.SurfaceAlt:Lerp(T.Text, 0.2)
		local pos = on and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		if instant then
			sw.BackgroundColor3 = color
			knob.Position = pos
		else
			tween(sw, 0.15, { BackgroundColor3 = color })
			tween(knob, 0.15, { Position = pos })
		end
	end
	function el:_apply(v)
		self.Value = v and true or false
		paint(false)
	end
	W._refreshers[el] = function()
		paint(true)
	end
	sw.Activated:Connect(function()
		el:_commit(not el.Value)
	end)
end

-- Slider -----------------------------------------------------------------------

Elements.Slider = function(el, W, row, opts)
	local min, max, step = opts.Min or 0, opts.Max or 100, opts.Step or 1
	local suffix = opts.Suffix or ""
	el.Default = min
	el.Min, el.Max, el.Step = min, max, step
	row.Size = UDim2.new(1, 0, 0, 40)
	W:_label({ Parent = row, Text = el.Name, Size = UDim2.new(1, -80, 0, 18) })
	local valueLabel = W:_label({
		Parent = row,
		Size = UDim2.new(0, 80, 0, 18),
		Position = UDim2.new(1, -80, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 12,
	}, "mono")
	local track = W:_button({
		Parent = row,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 16),
	})
	local bar = new("Frame", {
		Parent = track,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 6),
		BorderSizePixel = 0,
	})
	W:_field(bar, "BackgroundColor3", 0.16)
	W:_pill(bar)
	local fill = new("Frame", { Parent = bar, Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 })
	W:_bind(fill, "BackgroundColor3", "Accent")
	W:_pill(fill)
	local knob = new("Frame", {
		Parent = bar,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(13, 13),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	})
	W:_pill(knob)
	function el:_apply(v)
		v = snap(tonumber(v) or self.Min, self.Min, self.Max, self.Step)
		self.Value = v
		local a = (self.Max == self.Min) and 0 or (v - self.Min) / (self.Max - self.Min)
		fill.Size = UDim2.new(a, 0, 1, 0)
		knob.Position = UDim2.new(a, 0, 0.5, 0)
		valueLabel.Text = fmtNum(v, self.Step) .. suffix
	end
	function el:SetRange(newMin, newMax)
		self.Min, self.Max = newMin, newMax
		self:_commit(self.Value, true)
	end
	W:_trackDrag(track, function(pos)
		local width = math.max(bar.AbsoluteSize.X, 1)
		local a = clamp((pos.X - bar.AbsolutePosition.X) / width, 0, 1)
		local v = snap(el.Min + a * (el.Max - el.Min), el.Min, el.Max, el.Step)
		if v ~= el.Value then
			el:_commit(v)
		end
	end)
end

-- Dropdown ---------------------------------------------------------------------

Elements.Dropdown = function(el, W, row, opts)
	local options = opts.Options or {}
	local multi = opts.Multi == true
	el.Options = options
	el.Multi = multi
	el.Default = multi and {} or options[1]
	el.Value = el.Default
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Size = UDim2.new(1, 0, 0, 0)
	new("UIListLayout", { Parent = row, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
	local head = new("Frame", { Parent = row, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1 })
	W:_label({ Parent = head, Text = el.Name, Size = UDim2.new(0.42, 0, 1, 0) })
	local btn = W:_button({
		Parent = head,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0.58, 0, 0, 24),
	})
	W:_field(btn, "BackgroundColor3")
	W:_corner(btn, 0.55)
	local btnText = W:_label({
		Parent = btn,
		Position = UDim2.new(0, 9, 0, 0),
		Size = UDim2.new(1, -28, 1, 0),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local arrow = W:_label({
		Parent = btn,
		Text = "v",
		Position = UDim2.new(1, -20, 0, 0),
		Size = UDim2.new(0, 14, 1, 0),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, "dim")
	local list = new("Frame", {
		Parent = row,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 2,
	})
	new("UIListLayout", { Parent = list, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
	local optionButtons = {}

	local function selected(opt)
		if multi then
			return indexOf(el.Value, opt) ~= nil
		end
		return el.Value == opt
	end

	local function paint()
		local T = W.Theme
		for opt, b in pairs(optionButtons) do
			local on = selected(opt)
			b.TextColor3 = on and T.Accent or T.TextDim
			b.BackgroundTransparency = on and 0.82 or 1
			b.BackgroundColor3 = T.Accent
		end
		if multi then
			local n = #el.Value
			if n == 0 then
				btnText.Text = "None"
			elseif n <= 2 then
				btnText.Text = table.concat(el.Value, ", ")
			else
				btnText.Text = el.Value[1] .. " +" .. (n - 1)
			end
		else
			btnText.Text = tostring(el.Value)
		end
	end

	local function rebuild()
		for _, b in pairs(optionButtons) do
			b:Destroy()
		end
		optionButtons = {}
		for i, opt in ipairs(el.Options) do
			local b = W:_button({
				Parent = list,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = i,
				Text = tostring(opt),
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundTransparency = 1,
			})
			W:_bind(b, "Font", "Font")
			new("UIPadding", { PaddingLeft = UDim.new(0, 9), Parent = b })
			W:_corner(b, 0.5)
			optionButtons[opt] = b
			b.Activated:Connect(function()
				if multi then
					local nextValue = {}
					for _, o in ipairs(el.Options) do
						if (o == opt) ~= selected(o) then
							nextValue[#nextValue + 1] = o
						end
					end
					el:_commit(nextValue)
				else
					el:_commit(opt)
					list.Visible = false
					arrow.Text = "v"
				end
			end)
		end
		paint()
	end

	function el:_apply(v)
		if multi then
			local want = {}
			if type(v) == "table" then
				for _, o in ipairs(v) do
					want[o] = true
				end
			end
			local out = {}
			for _, o in ipairs(self.Options) do
				if want[o] then
					out[#out + 1] = o
				end
			end
			self.Value = out
		else
			if indexOf(self.Options, v) == nil then
				v = self.Options[1]
			end
			self.Value = v
		end
		paint()
	end

	function el:SetOptions(newOptions, keep)
		self.Options = newOptions
		self.Default = multi and {} or newOptions[1]
		rebuild()
		self:_commit(keep and self.Value or self.Default, true)
	end

	W._refreshers[el] = paint
	btn.Activated:Connect(function()
		list.Visible = not list.Visible
		arrow.Text = list.Visible and "^" or "v"
	end)
	rebuild()
end

-- Keybind ----------------------------------------------------------------------

Elements.Keybind = function(el, W, row, opts)
	el.Default = nil
	el.Pressed = Signal.new()
	row.Size = UDim2.new(1, 0, 0, 26)
	W:_label({ Parent = row, Text = el.Name, Size = UDim2.new(1, -100, 1, 0) })
	local btn = W:_button({
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(92, 24),
		TextSize = 12,
	})
	W:_bind(btn, "Font", "FontMono")
	W:_field(btn, "BackgroundColor3")
	W:_corner(btn, 0.55)
	local listening = false
	local function paint()
		local T = W.Theme
		btn.TextColor3 = listening and T.Accent or T.Text
		btn.Text = listening and "press a key" or keyName(el.Value)
	end
	function el:_apply(v)
		self.Value = toKeyCode(v)
		listening = false
		paint()
	end
	function el:OnPressed(fn)
		return self.Pressed:Connect(fn)
	end
	W._refreshers[el] = paint
	btn.Activated:Connect(function()
		if W._captureCancel then
			W._captureCancel()
		end
		listening = true
		paint()
		W._captureCancel = function()
			listening = false
			W._capture, W._captureCancel = nil, nil
			paint()
		end
		W._capture = function(key)
			W._captureCancel = nil
			listening = false
			el:_commit(key)
		end
	end)
	W._keyElements[#W._keyElements + 1] = el
end

-- Textbox ----------------------------------------------------------------------

Elements.Textbox = function(el, W, row, opts)
	local numeric = opts.Numeric == true
	el.Default = numeric and 0 or ""
	row.Size = UDim2.new(1, 0, 0, 26)
	W:_label({ Parent = row, Text = el.Name, Size = UDim2.new(0.4, 0, 1, 0) })
	local box = new("TextBox", {
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0.6, 0, 0, 24),
		Text = "",
		PlaceholderText = opts.Placeholder or "",
		ClearTextOnFocus = opts.ClearOnFocus == true,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BorderSizePixel = 0,
	})
	W:_bind(box, "TextColor3", "Text")
	W:_bind(box, "PlaceholderColor3", "TextDim")
	W:_bind(box, "Font", "FontMono")
	W:_field(box, "BackgroundColor3")
	W:_corner(box, 0.55)
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = box })
	function el:_apply(v)
		if numeric then
			v = tonumber(v) or 0
			if opts.Min then
				v = math.max(v, opts.Min)
			end
			if opts.Max then
				v = math.min(v, opts.Max)
			end
		elseif v == nil then
			v = ""
		end
		self.Value = v
		box.Text = tostring(v)
	end
	box.FocusLost:Connect(function()
		if numeric and tonumber(box.Text) == nil then
			box.Text = tostring(el.Value)
			return
		end
		el:_commit(numeric and tonumber(box.Text) or box.Text)
	end)
end

-- ColorPicker ------------------------------------------------------------------

Elements.ColorPicker = function(el, W, row, opts)
	el.Default = Color3.fromRGB(255, 255, 255)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Size = UDim2.new(1, 0, 0, 0)
	new("UIListLayout", { Parent = row, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	local head = new("Frame", { Parent = row, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 })
	W:_label({ Parent = head, Text = el.Name, Size = UDim2.new(1, -50, 1, 0) })
	local swatch = W:_button({
		Parent = head,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(38, 20),
	})
	W:_corner(swatch, 0.5)
	W:_stroke(swatch)
	local panel = new("Frame", {
		Parent = row,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 2,
	})
	local sv = W:_button({ Parent = panel, Size = UDim2.new(1, -28, 0, 100) })
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = sv })
	local white = new("Frame", { Parent = sv, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = white })
	new("UIGradient", { Parent = white, Transparency = NumberSequence.new(0, 1) })
	local black = new("Frame", { Parent = sv, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 })
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = black })
	new("UIGradient", { Parent = black, Rotation = 90, Transparency = NumberSequence.new(1, 0) })
	local cursor = new("Frame", {
		Parent = sv,
		Size = UDim2.fromOffset(11, 11),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = cursor })
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = cursor })
	local hue = W:_button({ Parent = panel, Position = UDim2.new(1, -18, 0, 0), Size = UDim2.new(0, 18, 0, 100) })
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = hue })
	local keys = {}
	for i = 0, 6 do
		keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))
	end
	new("UIGradient", { Parent = hue, Rotation = 90, Color = ColorSequence.new(keys) })
	local hueCursor = new("Frame", {
		Parent = hue,
		Size = UDim2.new(1, 4, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hueCursor })
	new("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.5, Parent = hueCursor })

	local hh, ss, vv = 0, 0, 1
	local fromPicker = false
	function el:_apply(c)
		if typeof(c) ~= "Color3" then
			c = self.Default
		end
		if fromPicker then
			c = Color3.fromHSV(hh, ss, vv)
		else
			hh, ss, vv = c:ToHSV()
		end
		self.Value = c
		swatch.BackgroundColor3 = c
		sv.BackgroundColor3 = Color3.fromHSV(hh, 1, 1)
		cursor.Position = UDim2.new(ss, 0, 1 - vv, 0)
		hueCursor.Position = UDim2.new(0.5, 0, hh, 0)
	end
	local function pick(h2, s2, v2)
		hh, ss, vv = h2, s2, v2
		fromPicker = true
		el:_commit(Color3.fromHSV(hh, ss, vv))
		fromPicker = false
	end
	W:_trackDrag(sv, function(pos)
		local s2 = clamp((pos.X - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
		local v2 = 1 - clamp((pos.Y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
		pick(hh, s2, v2)
	end)
	W:_trackDrag(hue, function(pos)
		pick(clamp((pos.Y - hue.AbsolutePosition.Y) / math.max(hue.AbsoluteSize.Y, 1), 0, 0.999), ss, vv)
	end)
	local open = false
	swatch.Activated:Connect(function()
		open = not open
		tween(panel, 0.2, { Size = UDim2.new(1, 0, 0, open and 104 or 0) })
	end)
end

-- Button -----------------------------------------------------------------------

Elements.Button = function(el, W, row, opts)
	row.Size = UDim2.new(1, 0, 0, 30)
	local btn = W:_button({ Parent = row, Size = UDim2.fromScale(1, 1), Text = opts.Text or el.Name, TextSize = 13 })
	W:_bind(btn, "Font", "Font")
	W:_bind(btn, "TextColor3", "Text")
	W:_field(btn, "BackgroundColor3", 0.1)
	W:_corner(btn, 0.6)
	W:_stroke(btn)
	btn.MouseEnter:Connect(function()
		tween(btn, 0.12, { BackgroundColor3 = W.Theme.SurfaceAlt:Lerp(W.Theme.Accent, 0.25) })
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, 0.12, { BackgroundColor3 = W.Theme.SurfaceAlt:Lerp(W.Theme.Text, 0.1) })
	end)
	btn.Activated:Connect(function()
		el.Clicked:Fire()
		if el.Callback then
			safeCall(el.Callback)
		end
	end)
	el.Clicked = Signal.new()
	function el:SetText(t)
		btn.Text = t
	end
	function el:OnClick(fn)
		return self.Clicked:Connect(fn)
	end
end

-- Label ------------------------------------------------------------------------

Elements.Label = function(el, W, row, opts)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Size = UDim2.new(1, 0, 0, 0)
	local l = W:_label({
		Parent = row,
		Text = opts.Text or el.Name,
		TextWrapped = true,
		TextSize = 12,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	}, (opts.Dim ~= false) and "dim" or nil)
	function el:SetText(t)
		l.Text = t
	end
end

-- Separator --------------------------------------------------------------------

Elements.Separator = function(el, W, row, opts)
	row.Size = UDim2.new(1, 0, 0, 1)
	local line = new("Frame", { Parent = row, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 })
	W:_bind(line, "BackgroundColor3", "Stroke")
	W:_bind(line, "BackgroundTransparency", "StrokeTransparency", function(t)
		return math.max(0, t - 0.04)
	end)
end

local VALUELESS = { Button = true, Label = true, Separator = true }

local function uniqueFlag(W, base)
	local flag, n = base, 1
	while W._usedFlags[flag] do
		n = n + 1
		flag = base .. "#" .. n
	end
	W._usedFlags[flag] = true
	return flag
end

local function addElement(owner, kind, opts)
	local W = owner.Window
	opts = opts or {}
	local builder = Elements[kind]
	local el = setmetatable({
		Kind = kind,
		Owner = owner,
		Window = W,
		Name = opts.Name or kind,
		Changed = Signal.new(),
		Callback = opts.Callback,
	}, Element)
	owner:_ensureSettings()
	local row = new("Frame", {
		Name = el.Name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = #owner.Elements + 1,
		Parent = owner.Inner,
	})
	el.Row = row
	local hasValue = not VALUELESS[kind]
	if hasValue then
		el.Flag = uniqueFlag(W, opts.Flag or (owner.Flag .. "/" .. el.Name))
	end
	builder(el, W, row, opts)
	owner.Elements[#owner.Elements + 1] = el
	if hasValue then
		W._elements[el.Flag] = el
		if not opts.NoSave then
			W._flagObjs[el.Flag] = {
				get = function()
					return el.Value
				end,
				set = function(v)
					el:Set(v)
				end,
			}
		end
		local default = opts.Default
		if default == nil then
			default = el.Default
		end
		el:_commit(default, opts.CallOnInit == false)
	end
	if opts.Visible == false then
		row.Visible = false
	end
	return el
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

function Module:_ensureSettings()
	if self.Inner then
		return
	end
	local W = self.Window
	local clip = new("Frame", {
		Name = "Settings",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 3,
		Parent = self.Card,
	})
	local inner = new("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = clip,
	})
	new("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
	new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 13),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = inner,
	})
	self.SettingsClip, self.Inner = clip, inner
	self.Chevron.Visible = true
	inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self.Open then
			clip.Size = UDim2.new(1, 0, 0, inner.AbsoluteSize.Y)
		end
	end)
end

function Module:_visual(instant)
	local W = self.Window
	local T = W.Theme
	local on = self.Toggleable and self.Enabled
	local cardColor = on and T.SurfaceAlt:Lerp(T.Accent, 0.14) or T.SurfaceAlt
	local textColor = (on or not self.Toggleable) and T.Text or T.TextDim
	if instant then
		self.Card.BackgroundColor3 = cardColor
		self.NameLabel.TextColor3 = textColor
	else
		tween(self.Card, 0.15, { BackgroundColor3 = cardColor })
		tween(self.NameLabel, 0.15, { TextColor3 = textColor })
	end
	if self.Switch then
		local swColor = on and T.Accent or T.SurfaceAlt:Lerp(T.Text, 0.2)
		local knobPos = on and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		if instant then
			self.Switch.BackgroundColor3 = swColor
			self.Knob.Position = knobPos
		else
			tween(self.Switch, 0.15, { BackgroundColor3 = swColor })
			tween(self.Knob, 0.15, { Position = knobPos })
		end
	end
end

function Module:_build()
	local W = self.Window
	local card = new("Frame", {
		Name = self.Name,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = self.Order,
	})
	W:_corner(card, 0.85)
	W:_stroke(card)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
	local head = W:_button({
		Name = "Header",
		Parent = card,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 1,
	})
	local right = 12
	if self.Toggleable then
		local sw = new("Frame", {
			Name = "Switch",
			Parent = head,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -right, 0.5, 0),
			Size = UDim2.fromOffset(34, 18),
			BorderSizePixel = 0,
		})
		W:_pill(sw)
		local knob = new("Frame", {
			Parent = sw,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		})
		W:_pill(knob)
		self.Switch, self.Knob = sw, knob
		right = right + 34 + 8
	end
	local chevron = W:_button({
		Name = "Chevron",
		Parent = head,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -right, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		Text = ">",
		TextSize = 14,
		Visible = false,
	})
	W:_bind(chevron, "Font", "FontBold")
	W:_bind(chevron, "TextColor3", "TextDim")
	right = right + 24
	local tag = W:_label({
		Name = "BindTag",
		Parent = head,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -right, 0.5, 0),
		Size = UDim2.fromOffset(46, 16),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, "mono")
	tag.TextTransparency = 0.25
	local nameLabel = W:_label({
		Name = "Name",
		Parent = head,
		Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -(right + 56), 1, 0),
		Text = self.Name,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local desc = W:_label({
		Name = "Description",
		Parent = card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextSize = 12,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = self.Description,
		LayoutOrder = 2,
		Visible = false,
	}, "dim")
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 10),
		Parent = desc,
	})
	self.Card, self.Header, self.Chevron, self.BindTag, self.NameLabel, self.Desc = card, head, chevron, tag, nameLabel, desc

	head.Activated:Connect(function()
		if self.Toggleable then
			self:Toggle()
		else
			self:SetOpen(not self.Open)
		end
	end)
	head.MouseButton2Click:Connect(function()
		self:SetOpen(not self.Open)
	end)
	chevron.Activated:Connect(function()
		self:SetOpen(not self.Open)
	end)
	W._refreshers[self] = function()
		self:_visual(true)
	end
	self:_visual(true)
end

function Module:_place()
	local W = self.Window
	if W._searching then
		return
	end
	local cat = self.Category
	if W.Style == "Window" then
		self.Card.Parent = cat.Cols[((self.Order - 1) % #cat.Cols) + 1]
		self.Desc.Visible = W.ShowDescriptions and self.Description ~= ""
	else
		self.Card.Parent = cat.PanelList
		self.Desc.Visible = false
	end
	self.Card.LayoutOrder = self.Order
end

function Module:_matches(q)
	return string.find(string.lower(self.Name), q, 1, true) ~= nil
		or string.find(string.lower(self.Description), q, 1, true) ~= nil
end

function Module:SetOpen(open)
	if not self.Inner then
		return
	end
	self.Open = open and true or false
	local h = self.Open and self.Inner.AbsoluteSize.Y or 0
	tween(self.SettingsClip, 0.2, { Size = UDim2.new(1, 0, 0, h) })
	tween(self.Chevron, 0.2, { Rotation = self.Open and 90 or 0 })
end

function Module:SetEnabled(value, silent, noNotify)
	if not self.Toggleable then
		return
	end
	value = value and true or false
	if value == self.Enabled then
		return
	end
	local W = self.Window
	self.Enabled = value
	W.Flags[self.Flag] = value
	self:_visual(false)
	W:_rebuildHud()
	W:_updateCounts()
	if not silent then
		self.Changed:Fire(value)
		W.FlagChanged:Fire(self.Flag, value)
		if self.Callback then
			safeCall(self.Callback, value)
		end
		if W.NotifyOnToggle and not noNotify and not W._importing then
			W:Notify({ Title = self.Name, Content = value and "Enabled" or "Disabled", Duration = 1.6, Type = value and "Success" or "Info" })
		end
	end
end

function Module:Toggle()
	self:SetEnabled(not self.Enabled)
end

function Module:Get()
	return self.Enabled
end

function Module:OnChanged(fn)
	return self.Changed:Connect(fn)
end

function Module:SetKeybind(key, silent)
	key = toKeyCode(key)
	self.Keybind = key
	self.BindTag.Text = key and ("[" .. keyName(key) .. "]") or ""
	if self.KeybindElement and self.KeybindElement.Value ~= key then
		self.KeybindElement:Set(key, true)
	end
end

function Module:SetSuffix(text)
	self.Suffix = text
	self.Window:_rebuildHud()
end

function Module:SetVisible(visible)
	self.Card.Visible = visible and true or false
end

function Module:SetName(name)
	self.Name = name
	self.NameLabel.Text = name
	self.Window:_rebuildHud()
end

function Module:Destroy()
	local W = self.Window
	local cat = self.Category
	local i = indexOf(cat.Modules, self)
	if i then
		table.remove(cat.Modules, i)
	end
	local j = indexOf(W.Modules, self)
	if j then
		table.remove(W.Modules, j)
	end
	for n, m in ipairs(cat.Modules) do
		m.Order = n
	end
	local elements = {}
	for i, el in ipairs(self.Elements) do
		elements[i] = el
	end
	for _, el in ipairs(elements) do
		el:Destroy()
	end
	W._flagObjs[self.Flag] = nil
	W._flagObjs[self.Flag .. ".Bind"] = nil
	W._flagObjs[self.Flag .. ".Mode"] = nil
	W.Flags[self.Flag] = nil
	W._refreshers[self] = nil
	self.Card:Destroy()
	W:_rebuildHud()
	W:_updateCounts()
end

local ADDERS = {
	AddToggle = "Toggle",
	AddSlider = "Slider",
	AddDropdown = "Dropdown",
	AddKeybind = "Keybind",
	AddTextbox = "Textbox",
	AddColorPicker = "ColorPicker",
	AddButton = "Button",
	AddLabel = "Label",
	AddParagraph = "Label",
	AddSeparator = "Separator",
}
for method, kind in pairs(ADDERS) do
	Module[method] = function(self, opts)
		if type(opts) == "string" then
			opts = { Name = opts }
		end
		return addElement(self, kind, opts)
	end
end

function Module:Add(kind, opts)
	assert(Elements[kind], "Unknown element kind: " .. tostring(kind))
	return addElement(self, kind, opts)
end

--------------------------------------------------------------------------------
-- Category
--------------------------------------------------------------------------------

function Category:AddModule(opts)
	if type(opts) == "string" then
		opts = { Name = opts }
	end
	opts = opts or {}
	local W = self.Window
	local m = setmetatable({}, Module)
	m.Window, m.Category = W, self
	m.Name = opts.Name or "Module"
	m.Description = opts.Description or opts.Desc or ""
	m.Toggleable = opts.Toggleable ~= false
	m.Enabled = false
	m.Callback = opts.Callback
	m.Changed = Signal.new()
	m.KeybindMode = opts.KeybindMode == "Hold" and "Hold" or "Toggle"
	m.Suffix = opts.Suffix
	m.HideFromList = opts.HideFromList == true
	m.Flag = uniqueFlag(W, opts.Flag or (self.Name .. "." .. m.Name))
	m.Elements = {}
	m.Open = false
	m.Order = #self.Modules + 1
	self.Modules[#self.Modules + 1] = m
	W.Modules[#W.Modules + 1] = m
	m:_build()
	m:_place()

	if m.Toggleable then
		W.Flags[m.Flag] = false
		W._flagObjs[m.Flag] = {
			get = function()
				return m.Enabled
			end,
			set = function(v)
				m:SetEnabled(v)
			end,
		}
		if opts.NoKeybind ~= true then
			m.KeybindElement = addElement(m, "Keybind", {
				Name = "Keybind",
				Flag = m.Flag .. ".Bind",
				Default = toKeyCode(opts.Keybind),
				CallOnInit = false,
				Callback = function(key)
					m:SetKeybind(key)
				end,
			})
			m.ModeElement = addElement(m, "Dropdown", {
				Name = "Bind mode",
				Flag = m.Flag .. ".Mode",
				Options = { "Toggle", "Hold" },
				Default = m.KeybindMode,
				CallOnInit = false,
				Callback = function(mode)
					m.KeybindMode = mode
				end,
			})
			m:SetKeybind(opts.Keybind)
		end
	end
	if opts.Default and m.Toggleable then
		m:SetEnabled(true, false, true)
	end
	if W._searching then
		W:_applySearch(W._searchBox.Text)
	end
	W:_updateCounts()
	return m
end

Category.Add = Category.AddModule
Category.CreateModule = Category.AddModule

function Category:GetModule(name)
	for _, m in ipairs(self.Modules) do
		if m.Name == name then
			return m
		end
	end
	return nil
end

function Category:Select()
	self.Window:SelectCategory(self)
end

function Category:SetCollapsed(collapsed)
	self.Collapsed = collapsed and true or false
	self.PanelList.Visible = not self.Collapsed
	self.PanelChevron.Rotation = self.Collapsed and -90 or 0
end

--------------------------------------------------------------------------------
-- Window: categories, selection, search
--------------------------------------------------------------------------------

local function buildColumns(W, parent, count)
	local holder = new("Frame", {
		Name = "Columns",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = holder,
	})
	local cols = {}
	for i = 1, count do
		local col = new("Frame", {
			Name = "Column" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.new(1 / count, -math.ceil(10 * (count - 1) / count), 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = i,
			Parent = holder,
		})
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = col })
		cols[i] = col
	end
	return cols
end

local function buildPage(W, parent, name)
	local page = new("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		Parent = parent,
	})
	W:_bind(page, "ScrollBarImageColor3", "TextDim")
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 18),
		PaddingLeft = UDim.new(0, 24),
		PaddingRight = UDim.new(0, 18),
		Parent = page,
	})
	return page, buildColumns(W, page, W.Columns)
end

function Window:CreateCategory(name, opts)
	opts = opts or {}
	local cat = setmetatable({}, Category)
	cat.Window, cat.Name, cat.Modules = self, name, {}
	cat.Index = #self.Categories + 1
	self.Categories[cat.Index] = cat

	-- sidebar tab ------------------------------------------------------------
	local tab = self:_button({
		Name = name,
		Parent = self._tabList,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = cat.Index,
	})
	self:_corner(tab, 0.75)
	local icon = new("Frame", {
		Parent = tab,
		Position = UDim2.new(0, 9, 0.5, -11),
		Size = UDim2.fromOffset(22, 22),
		BorderSizePixel = 0,
	})
	self:_corner(icon, 0.5)
	local iconText
	if opts.Icon then
		new("ImageLabel", {
			Parent = icon,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -6, 1, -6),
			Position = UDim2.fromOffset(3, 3),
			Image = opts.Icon,
		})
	else
		iconText = self:_label({
			Parent = icon,
			Size = UDim2.fromScale(1, 1),
			Text = string.upper(string.sub(name, 1, 1)),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, "bold")
	end
	local tabName = self:_label({
		Parent = tab,
		Position = UDim2.new(0, 40, 0, 0),
		Size = UDim2.new(1, -78, 1, 0),
		Text = name,
	})
	local tabCount = self:_label({
		Parent = tab,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(34, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 11,
	}, "mono")
	cat.Tab, cat.TabName, cat.TabCount = tab, tabName, tabCount
	tab.Activated:Connect(function()
		self._searchBox.Text = ""
		self:SelectCategory(cat)
	end)
	self._refreshers[cat] = function()
		local T = self.Theme
		local sel = self._current == cat and not self._searching
		tab.BackgroundColor3 = T.Accent
		tab.BackgroundTransparency = sel and 0.84 or 1
		icon.BackgroundColor3 = sel and T.Accent or T.SurfaceAlt:Lerp(T.Text, 0.12)
		if iconText then
			iconText.TextColor3 = sel and Color3.fromRGB(10, 12, 17) or T.TextDim
		end
		tabName.TextColor3 = sel and T.Text or T.TextDim
		tabCount.TextColor3 = T.TextDim
	end

	-- page (Window layout) ---------------------------------------------------
	cat.Page, cat.Cols = buildPage(self, self._pages, name)

	-- panel (Panels layout) --------------------------------------------------
	local vw = 1280
	pcall(function()
		local v = workspace.CurrentCamera.ViewportSize.X
		if type(v) == "number" then
			vw = v
		end
	end)
	local perRow = math.max(1, math.floor((vw - 20) / (self.PanelWidth + 14)))
	local i0 = cat.Index - 1
	local panel = new("Frame", {
		Name = name,
		Parent = self.PanelsHost,
		Position = UDim2.fromOffset(20 + (i0 % perRow) * (self.PanelWidth + 14), 76 + math.floor(i0 / perRow) * 370),
		Size = UDim2.fromOffset(self.PanelWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
	})
	self:_bind(panel, "BackgroundColor3", "Surface")
	self:_bind(panel, "BackgroundTransparency", "Transparency")
	self:_corner(panel, 1.2)
	self:_stroke(panel)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })
	local phead = self:_button({
		Name = "Header",
		Parent = panel,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 1,
	})
	local dot = new("Frame", {
		Parent = phead,
		Position = UDim2.new(0, 16, 0.5, -4),
		Size = UDim2.fromOffset(8, 8),
		BorderSizePixel = 0,
	})
	self:_pill(dot)
	self:_gradient(dot)
	self:_label({ Parent = phead, Text = name, Position = UDim2.new(0, 32, 0, 0), Size = UDim2.new(1, -110, 1, 0) }, "bold")
	cat.PanelCount = self:_label({
		Parent = phead,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -38, 0.5, 0),
		Size = UDim2.fromOffset(36, 16),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, "mono")
	cat.PanelChevron = self:_button({
		Parent = phead,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		Text = "v",
		TextSize = 12,
	})
	self:_bind(cat.PanelChevron, "TextColor3", "TextDim")
	self:_bind(cat.PanelChevron, "Font", "FontBold")
	cat.PanelChevron.Activated:Connect(function()
		cat:SetCollapsed(not cat.Collapsed)
	end)
	phead.MouseButton2Click:Connect(function()
		cat:SetCollapsed(not cat.Collapsed)
	end)
	local plist = new("ScrollingFrame", {
		Name = "Modules",
		Parent = panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		LayoutOrder = 2,
	})
	self:_bind(plist, "ScrollBarImageColor3", "TextDim")
	new("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 330), Parent = plist })
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = plist })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 10),
		Parent = plist,
	})
	cat.Panel, cat.PanelList = panel, plist
	self:_makeDraggable(phead, panel, true)
	panel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._z = self._z + 1
			panel.ZIndex = self._z
		end
	end)
	panel.Visible = true

	if self.Style == "Window" then
		panel.Parent = self.PanelsHost
	end
	if not self._current then
		self:SelectCategory(cat)
	end
	self._refreshers[cat]()
	self:_updateCounts()
	return cat
end

Window.AddCategory = Window.CreateCategory
Window.CreateTab = Window.CreateCategory

function Window:GetCategory(name)
	for _, c in ipairs(self.Categories) do
		if c.Name == name then
			return c
		end
	end
	return nil
end

function Window:GetModule(name)
	for _, m in ipairs(self.Modules) do
		if m.Name == name or m.Flag == name then
			return m
		end
	end
	return nil
end

function Window:SelectCategory(cat)
	if type(cat) == "string" then
		cat = self:GetCategory(cat)
	end
	if not cat then
		return
	end
	self._current = cat
	self._searching = false
	self._searchBox.Text = ""
	for _, c in ipairs(self.Categories) do
		c.Page.Visible = (c == cat)
	end
	self.Results.Page.Visible = false
	self:_updateHeader()
	for _, c in ipairs(self.Categories) do
		self._refreshers[c]()
	end
end

function Window:_updateCounts()
	for _, c in ipairs(self.Categories) do
		local total, on = #c.Modules, 0
		for _, m in ipairs(c.Modules) do
			if m.Enabled then
				on = on + 1
			end
		end
		local hasToggle = false
		for _, m in ipairs(c.Modules) do
			if m.Toggleable then
				hasToggle = true
			end
		end
		local text = hasToggle and (on .. "/" .. total) or tostring(total)
		c.TabCount.Text = text
		c.PanelCount.Text = text
	end
	self:_updateHeader()
end

function Window:_updateHeader()
	if not self._headTitle then
		return
	end
	local shown, on = 0, 0
	if self._searching then
		for _, c in ipairs(self.Categories) do
			for _, m in ipairs(c.Modules) do
				if m.Card.Visible then
					shown = shown + 1
					if m.Enabled then
						on = on + 1
					end
				end
			end
		end
		self._headTitle.Text = 'Results for "' .. self._searchBox.Text .. '"'
	elseif self._current then
		for _, m in ipairs(self._current.Modules) do
			shown = shown + 1
			if m.Enabled then
				on = on + 1
			end
		end
		self._headTitle.Text = self._current.Name
	end
	self._headSub.Text = shown .. (shown == 1 and " module, " or " modules, ") .. on .. " enabled"
end

function Window:_applySearch(q)
	q = string.lower(q or "")
	local active = q ~= ""
	self._searching = active
	if self.Style == "Window" then
		self.Results.Page.Visible = active
		for _, c in ipairs(self.Categories) do
			c.Page.Visible = (not active) and c == self._current
		end
		local n = 0
		for _, c in ipairs(self.Categories) do
			for _, m in ipairs(c.Modules) do
				if active then
					local hit = m:_matches(q)
					m.Card.Visible = hit
					if hit then
						n = n + 1
						m.Card.Parent = self.Results.Cols[((n - 1) % #self.Results.Cols) + 1]
						m.Card.LayoutOrder = n
						m.Desc.Visible = self.ShowDescriptions and m.Description ~= ""
					end
				else
					m.Card.Visible = true
					m:_place()
				end
			end
		end
	else
		self.Results.Page.Visible = false
		for _, c in ipairs(self.Categories) do
			local any = false
			for _, m in ipairs(c.Modules) do
				local hit = (not active) or m:_matches(q)
				m.Card.Visible = hit
				if hit then
					any = true
				end
				if not active then
					m:_place()
				end
			end
			c.Panel.Visible = (not active) or any
			if active and any then
				c:SetCollapsed(false)
			end
		end
	end
	self:_updateHeader()
	for _, c in ipairs(self.Categories) do
		self._refreshers[c]()
	end
end

function Window:SetStyle(style)
	style = (style == "Panels") and "Panels" or "Window"
	self.Style = style
	self.Main.Visible = style == "Window"
	self.PanelsHost.Visible = style == "Panels"
	self._searchPill.Parent = (style == "Window") and self._searchSlotWindow or self._searchSlotPanels
	self._searching = false
	for _, c in ipairs(self.Categories) do
		for _, m in ipairs(c.Modules) do
			m.Card.Visible = true
			m:_place()
		end
		c.Page.Visible = (c == self._current)
	end
	self.Results.Page.Visible = false
	self:_applySearch(self._searchBox.Text)
	self.StyleChanged:Fire(style)
end

--------------------------------------------------------------------------------
-- Window: visibility, theme, accent, scale
--------------------------------------------------------------------------------

function Window:SetVisible(visible)
	visible = visible and true or false
	if visible == self.Visible then
		return
	end
	self.Visible = visible
	self._visToken = (self._visToken or 0) + 1
	local token = self._visToken
	if visible then
		self.Root.Visible = true
		self.Dim.BackgroundTransparency = 1
		tween(self.Dim, 0.2, { BackgroundTransparency = self._dimTarget })
		if self._blur then
			tween(self._blur, 0.25, { Size = self._blurSize })
		end
	else
		tween(self.Dim, 0.15, { BackgroundTransparency = 1 })
		if self._blur then
			tween(self._blur, 0.2, { Size = 0 })
		end
		task.delay(0.16, function()
			if self._visToken == token and not self.Visible then
				self.Root.Visible = false
			end
		end)
	end
	if self._mobileButton then
		self._mobileButton.Visible = not visible
	end
	self.Toggled:Fire(visible)
end

function Window:Toggle()
	self:SetVisible(not self.Visible)
end

function Window:SetToggleKey(key)
	self.ToggleKey = toKeyCode(key) or Enum.KeyCode.RightShift
	self._hint.Text = keyName(self.ToggleKey) .. " to hide the GUI"
end

function Window:SetScale(scale)
	scale = clamp(tonumber(scale) or 1, 0.5, 2)
	self._scaler.Scale = scale
	self.Root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

function Window:SetSize(size)
	self.Main.Size = UDim2.fromOffset(size.X, size.Y)
end

function Window:SetTitle(title, subtitle)
	self.Title = title
	self._brandLabel.Text = title
	self._panelsBrand.Text = title
	self._wmTitle.Text = title
	if subtitle ~= nil then
		self.Subtitle = subtitle
		self._wmVersion.Text = subtitle
	end
end

function Window:SetTheme(theme)
	if type(theme) == "string" and Lib.Themes[theme] then
		self.ThemeName = theme
	end
	local t = resolveTheme(theme)
	for k, v in pairs(t) do
		self.Theme[k] = v
	end
	self._baseAccent, self._baseAccent2 = self.Theme.Accent, self.Theme.Accent2
	if self._rainbow then
		self.Theme.Accent = self._lastRainbow or self.Theme.Accent
	end
	self:_refreshTokens(nil)
end

function Window:GetTheme()
	return self.Theme
end

function Window:SetThemeToken(token, value)
	self.Theme[token] = value
	self:_refreshTokens({ [token] = true })
end

function Window:SetAccent(color, color2)
	self._baseAccent = color
	self._baseAccent2 = color2 or shiftHue(color, 0.12)
	if not self._rainbow then
		self.Theme.Accent, self.Theme.Accent2 = self._baseAccent, self._baseAccent2
		self:_refreshTokens({ Accent = true, Accent2 = true })
	end
end

function Window:SetRainbow(enabled, speed)
	self._rainbow = enabled and true or false
	self._rainbowSpeed = speed or self._rainbowSpeed or 4
	if not self._rainbow then
		self.Theme.Accent, self.Theme.Accent2 = self._baseAccent, self._baseAccent2
		self:_refreshTokens({ Accent = true, Accent2 = true })
	end
end

--------------------------------------------------------------------------------
-- Window: player card
--------------------------------------------------------------------------------

function Window:_buildCard(parent, compact)
	local ui = {}
	local frame
	if compact then
		frame = new("Frame", {
			Name = "PlayerCard",
			Parent = parent,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BorderSizePixel = 0,
		})
		self:_bind(frame, "BackgroundColor3", "Surface")
		frame.BackgroundTransparency = 0.08
		self:_pill(frame)
		self:_stroke(frame)
		new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 14), Parent = frame })
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
	else
		frame = new("Frame", {
			Name = "PlayerCard",
			Parent = parent,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 0, 58),
			BorderSizePixel = 0,
		})
		self:_bind(frame, "BackgroundColor3", "SurfaceAlt")
		self:_corner(frame, 0.85)
		self:_stroke(frame)
	end
	local size = compact and 30 or 38
	local avatar = new("Frame", {
		Name = "Avatar",
		Parent = frame,
		Size = UDim2.fromOffset(size, size),
		Position = compact and UDim2.new() or UDim2.fromOffset(10, 10),
		LayoutOrder = 1,
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
	})
	if compact then
		self:_pill(avatar)
	else
		self:_corner(avatar, 0.8)
	end
	self:_gradient(avatar)
	ui.Initial = new("TextLabel", {
		Parent = avatar,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = compact and 13 or 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(10, 12, 17),
	})
	self:_bind(ui.Initial, "Font", "FontBold")
	ui.Image = new("ImageLabel", {
		Parent = avatar,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ScaleType = Enum.ScaleType.Crop,
	})
	new("UICorner", { CornerRadius = compact and UDim.new(1, 0) or UDim.new(0, 10), Parent = ui.Image })
	local status = new("Frame", {
		Parent = avatar,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 3, 1, 3),
		Size = UDim2.fromOffset(11, 11),
		BorderSizePixel = 0,
		ZIndex = 3,
	})
	self:_bind(status, "BackgroundColor3", "Success")
	self:_pill(status)
	local ring = new("UIStroke", { Thickness = 2, Parent = status })
	self:_bind(ring, "Color", "SurfaceAlt")

	local info = frame
	if compact then
		info = new("Frame", {
			Parent = frame,
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
		})
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = info,
		})
	end
	ui.Name = self:_label({
		Parent = info,
		Position = compact and UDim2.new() or UDim2.fromOffset(58, 10),
		Size = compact and UDim2.new(0, 0, 0, 16) or UDim2.new(1, -66, 0, 16),
		AutomaticSize = compact and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
	}, "bold")
	ui.Plan = self:_label({
		Parent = info,
		Position = compact and UDim2.new() or UDim2.fromOffset(58, 29),
		Size = UDim2.new(0, 0, 0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
	}, "bold")
	self:_pill(ui.Plan)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = ui.Plan })
	ui.Frame = frame
	self._cards[#self._cards + 1] = ui
	self:_updateCards()
	return ui
end

function Window:_updateCards()
	local info = self.PlayerInfo
	local name = tostring(info.Name or "Player")
	local plan = info.Plan
	for _, ui in ipairs(self._cards) do
		ui.Name.Text = name
		ui.Initial.Text = string.upper(string.sub(name, 1, 1))
		if self._avatarImage then
			ui.Image.Image = self._avatarImage
			ui.Image.Visible = true
		else
			ui.Image.Visible = false
		end
		if plan and plan ~= "" then
			ui.Plan.Text = tostring(plan)
			ui.Plan.BackgroundTransparency = 0
			ui.Plan.BackgroundColor3 = self.PlanColors[plan] or self.Theme.Accent
			ui.Plan.TextColor3 = Color3.fromRGB(10, 12, 17)
		else
			ui.Plan.Text = "No plan"
			ui.Plan.BackgroundTransparency = 1
			ui.Plan.TextColor3 = self.Theme.TextDim
		end
	end
end

-- info = { Name = "Steve", Plan = "Pro" | nil, Avatar = userId (number) | "rbxassetid://..." | nil }
function Window:SetPlayerCard(info)
	info = info or {}
	self.PlayerInfo = merge(self.PlayerInfo or {}, info)
	if info.Plan == false then
		self.PlayerInfo.Plan = nil
	end
	local avatar = info.Avatar
	if type(avatar) == "string" then
		self._avatarImage = avatar
	elseif type(avatar) == "number" or (avatar == nil and info.Avatar == nil and not self._avatarRequested) then
		local userId = (type(avatar) == "number") and avatar or (LocalPlayer and LocalPlayer.UserId)
		self._avatarRequested = true
		if userId then
			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
				end)
				if ok and content then
					self._avatarImage = content
					self:_updateCards()
				end
			end)
		end
	end
	self:_updateCards()
end

--------------------------------------------------------------------------------
-- Window: HUD
--------------------------------------------------------------------------------

function Hud:SetVisible(part, visible)
	local W = self.Window
	local frame = ({ Watermark = W.HudWatermark, ModuleList = W.HudList, Info = W.HudInfo })[part]
	if frame then
		frame.Visible = visible and true or false
	end
end

function Hud:SetWatermark(text, version)
	local W = self.Window
	W._wmTitle.Text = text or W.Title
	if version ~= nil then
		W._wmVersion.Text = version
	end
end

function Hud:AddInfo(name, fn)
	local W = self.Window
	self:RemoveInfo(name)
	local line = new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = #W._infoLines + 1,
		Parent = W.HudInfo,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = line,
	})
	local nameLabel = W:_label({
		Parent = line, Text = name, TextSize = 12, Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1,
	}, "dim")
	local valueLabel = W:_label({
		Parent = line, Text = "-", TextSize = 12, Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2,
	}, "mono")
	W._infoLines[#W._infoLines + 1] = { name = name, fn = fn, frame = line, value = valueLabel, nameLabel = nameLabel }
end

function Hud:RemoveInfo(name)
	local W = self.Window
	for i, l in ipairs(W._infoLines) do
		if l.name == name then
			l.frame:Destroy()
			table.remove(W._infoLines, i)
			return
		end
	end
end

function Window:_textWidth(text, size)
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.GothamMedium, Vector2.new(1000, 100)).X
	end)
	if ok and type(v) == "number" then
		return v
	end
	return #text * 7
end

function Window:_rebuildHud()
	if not self.HudList then
		return
	end
	for _, e in ipairs(self._hudEntries) do
		e.frame:Destroy()
	end
	self._hudEntries = {}
	local items = {}
	for _, m in ipairs(self.Modules) do
		if m.Enabled and m.Toggleable and not m.HideFromList then
			items[#items + 1] = m
		end
	end
	for i, m in ipairs(items) do
		local suffix = m.Suffix
		if type(suffix) == "function" then
			local ok, s = pcall(suffix)
			suffix = ok and s or ""
		end
		suffix = suffix and tostring(suffix) or ""
		local frame = new("Frame", {
			Name = m.Name,
			Parent = self.HudList,
			Size = UDim2.new(0, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			BorderSizePixel = 0,
			BackgroundTransparency = 0.12,
			LayoutOrder = -math.floor(self:_textWidth(m.Name .. " " .. suffix, 13)),
		})
		self:_bind(frame, "BackgroundColor3", "Surface")
		self:_corner(frame, 0.6)
		new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 10), Parent = frame })
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 7),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		local dot = new("Frame", { Parent = frame, Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, LayoutOrder = 1 })
		self:_pill(dot)
		self:_label({
			Parent = frame, Text = m.Name, TextSize = 13, LayoutOrder = 2,
			Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
		})
		if suffix ~= "" then
			self:_label({
				Parent = frame, Text = suffix, TextSize = 12, LayoutOrder = 3,
				Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
			}, "dim")
		end
		self._hudEntries[#self._hudEntries + 1] = { frame = frame, dot = dot, index = i, total = #items }
	end
	self._refreshers.hudlist()
end

--------------------------------------------------------------------------------
-- Window: notifications
--------------------------------------------------------------------------------

-- opts = { Title, Content, Duration = 3, Type = "Info" | "Success" | "Warning" | "Error" }
function Window:Notify(opts)
	if self.Options.Notifications == false then
		return
	end
	if type(opts) == "string" then
		opts = { Content = opts }
	end
	opts = opts or {}
	local T = self.Theme
	local colors = { Info = T.Accent, Success = T.Success, Warning = T.Warning, Error = T.Danger }
	local color = colors[opts.Type or "Info"] or T.Accent
	self._notifCount = self._notifCount + 1
	local wrap = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._notifCount,
		Parent = self.NotifFrame,
	})
	local toast = new("Frame", {
		Parent = wrap,
		Position = UDim2.new(0, 330, 0, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
	})
	self:_bind(toast, "BackgroundColor3", "Surface")
	toast.BackgroundTransparency = 0.04
	self:_corner(toast, 0.8)
	self:_stroke(toast)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 11), Parent = toast,
	})
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = toast })
	local bar = new("Frame", {
		Parent = toast,
		Position = UDim2.new(0, -16, 0, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	})
	bar.LayoutOrder = -1
	if opts.Title then
		self:_label({
			Parent = toast, Text = opts.Title, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 16),
		}, "bold")
	end
	if opts.Content then
		self:_label({
			Parent = toast, Text = opts.Content, TextSize = 12, TextWrapped = true, LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, "dim")
	end
	tween(toast, 0.3, { Position = UDim2.new(0, 0, 0, 0) }, Enum.EasingStyle.Back)
	task.delay(opts.Duration or 3, function()
		tween(toast, 0.25, { Position = UDim2.new(0, 330, 0, 0) })
		task.delay(0.3, function()
			wrap:Destroy()
		end)
	end)
end

--------------------------------------------------------------------------------
-- Window: flags and config
--------------------------------------------------------------------------------

function Window:GetFlag(flag)
	return self.Flags[flag]
end

function Window:SetFlag(flag, value)
	local obj = self._flagObjs[flag]
	if obj then
		obj.set(value)
		return true
	end
	return false
end

function Window:ExportConfig()
	local flags = {}
	for flag, obj in pairs(self._flagObjs) do
		flags[flag] = serialize(obj.get())
	end
	return HttpService:JSONEncode({ version = 1, flags = flags })
end

function Window:ImportConfig(json)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(data) ~= "table" or type(data.flags) ~= "table" then
		return false, "invalid config"
	end
	self._importing = true
	for flag, value in pairs(data.flags) do
		local obj = self._flagObjs[flag]
		if obj then
			pcall(obj.set, deserialize(value))
		end
	end
	self._importing = false
	return true
end

function Window:SaveConfig(name)
	local a = self.ConfigAdapter
	if not a or not a.Write then
		return false, "no ConfigAdapter"
	end
	local ok, err = pcall(a.Write, name, self:ExportConfig())
	return ok, err
end

function Window:LoadConfig(name)
	local a = self.ConfigAdapter
	if not a or not a.Read then
		return false, "no ConfigAdapter"
	end
	local ok, data = pcall(a.Read, name)
	if not ok or not data then
		return false, "config not found"
	end
	return self:ImportConfig(data)
end

function Window:ListConfigs()
	local a = self.ConfigAdapter
	if a and a.List then
		local ok, list = pcall(a.List)
		if ok and type(list) == "table" then
			return list
		end
	end
	return {}
end

-- Adapter backed by writefile/readfile when the environment provides them.
function Lib.FileAdapter(folder)
	local fns = { writefile = writefile, readfile = readfile, isfile = isfile, listfiles = listfiles, makefolder = makefolder, isfolder = isfolder }
	if not (fns.writefile and fns.readfile) then
		return nil
	end
	folder = folder or "GenericMCUI"
	if fns.isfolder and fns.makefolder and not fns.isfolder(folder) then
		pcall(fns.makefolder, folder)
	end
	return {
		Write = function(name, text)
			fns.writefile(folder .. "/" .. name .. ".json", text)
		end,
		Read = function(name)
			local path = folder .. "/" .. name .. ".json"
			if fns.isfile and not fns.isfile(path) then
				return nil
			end
			return fns.readfile(path)
		end,
		List = function()
			local out = {}
			if fns.listfiles then
				for _, path in ipairs(fns.listfiles(folder)) do
					local n = string.match(path, "([^/\\]+)%.json$")
					if n then
						out[#out + 1] = n
					end
				end
			end
			return out
		end,
	}
end

--------------------------------------------------------------------------------
-- Window: ready-made Interface settings category
--------------------------------------------------------------------------------

function Window:AddInterfaceSettings(name)
	local W = self
	local cat = W:CreateCategory(name or "Interface")

	local theme = cat:AddModule({ Name = "Theme", Description = "Colors and look of the whole GUI.", Toggleable = false })
	local names = Lib:GetThemeNames()
	theme:AddDropdown({
		Name = "Preset", Options = names, Default = W.ThemeName, CallOnInit = false,
		Callback = function(v)
			W:SetTheme(v)
		end,
	})
	theme:AddColorPicker({
		Name = "Accent", Default = W._baseAccent, CallOnInit = false,
		Callback = function(c)
			W:SetAccent(c)
		end,
	})
	theme:AddToggle({
		Name = "Rainbow accent", Default = W._rainbow == true, CallOnInit = false,
		Callback = function(v)
			W:SetRainbow(v)
		end,
	})
	theme:AddSlider({
		Name = "Rainbow speed", Min = 1, Max = 10, Default = W._rainbowSpeed or 4, CallOnInit = false,
		Callback = function(v)
			W._rainbowSpeed = v
		end,
	})
	theme:AddSlider({
		Name = "Corner radius", Min = 0, Max = 24, Default = W.Theme.Corner, Suffix = " px", CallOnInit = false,
		Callback = function(v)
			W:SetThemeToken("Corner", v)
		end,
	})
	theme:AddSlider({
		Name = "Window opacity", Min = 0, Max = 100, Step = 5, Default = math.floor((1 - W.Theme.Transparency) * 100), Suffix = "%", CallOnInit = false,
		Callback = function(v)
			W:SetThemeToken("Transparency", 1 - v / 100)
		end,
	})

	local layout = cat:AddModule({ Name = "Layout", Description = "Window or floating panels.", Toggleable = false })
	layout:AddDropdown({
		Name = "Style", Options = { "Window", "Panels" }, Default = W.Style, CallOnInit = false,
		Callback = function(v)
			W:SetStyle(v)
		end,
	})
	layout:AddToggle({
		Name = "Show descriptions", Default = W.ShowDescriptions, CallOnInit = false,
		Callback = function(v)
			W.ShowDescriptions = v
			W:_applySearch(W._searchBox.Text)
		end,
	})
	layout:AddKeybind({
		Name = "Toggle GUI key", Default = W.ToggleKey, CallOnInit = false,
		Callback = function(k)
			if k then
				W:SetToggleKey(k)
			end
		end,
	})
	layout:AddSlider({
		Name = "GUI scale", Min = 0.6, Max = 1.6, Step = 0.1, Default = W._scaler.Scale, Suffix = "x", CallOnInit = false,
		Callback = function(v)
			W:SetScale(v)
		end,
	})

	local hud = cat:AddModule({ Name = "HUD", Description = "Choose what shows on screen.", Toggleable = false })
	hud:AddToggle({ Name = "Watermark", Default = true, Callback = function(v) W.HUD:SetVisible("Watermark", v) end })
	hud:AddToggle({ Name = "Module list", Default = true, Callback = function(v) W.HUD:SetVisible("ModuleList", v) end })
	hud:AddToggle({ Name = "Info lines", Default = true, Callback = function(v) W.HUD:SetVisible("Info", v) end })
	hud:AddToggle({
		Name = "Toggle notifications", Default = W.NotifyOnToggle,
		Callback = function(v)
			W.NotifyOnToggle = v
		end,
	})

	local config = cat:AddModule({ Name = "Config", Description = "Save and share your settings.", Toggleable = false })
	local nameBox = config:AddTextbox({ Name = "Config name", Default = "default", Flag = "Interface/ConfigName", CallOnInit = false })
	config:AddButton({
		Name = "Save config",
		Callback = function()
			local ok, err = W:SaveConfig(nameBox.Value)
			W:Notify({
				Title = "Config", Content = ok and ("Saved " .. nameBox.Value) or ("Could not save: " .. tostring(err)),
				Type = ok and "Success" or "Warning",
			})
		end,
	})
	config:AddButton({
		Name = "Load config",
		Callback = function()
			local ok, err = W:LoadConfig(nameBox.Value)
			W:Notify({
				Title = "Config", Content = ok and ("Loaded " .. nameBox.Value) or ("Could not load: " .. tostring(err)),
				Type = ok and "Success" or "Warning",
			})
		end,
	})
	config:AddButton({
		Name = "Print config to Output",
		Callback = function()
			print(W:ExportConfig())
			W:Notify({ Title = "Config", Content = "Printed to the Output window.", Type = "Info" })
		end,
	})
	local importBox = config:AddTextbox({ Name = "Import JSON", Placeholder = "paste config", Flag = "Interface/ImportBox", CallOnInit = false, NoSave = true })
	importBox.Changed:Connect(function(text)
		if text ~= "" then
			local ok, err = W:ImportConfig(text)
			W:Notify({
				Title = "Config", Content = ok and "Imported." or tostring(err), Type = ok and "Success" or "Error",
			})
			importBox:Set("", true)
		end
	end)
	return cat
end

--------------------------------------------------------------------------------
-- Window: construction
--------------------------------------------------------------------------------

function Window:Destroy()
	for _, c in ipairs(self._conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	self._conns = {}
	if self._blur then
		self._blur:Destroy()
	end
	self.Gui:Destroy()
	local i = indexOf(Lib.Windows, self)
	if i then
		table.remove(Lib.Windows, i)
	end
end

function Lib:Unload()
	local list = {}
	for i, w in ipairs(Lib.Windows) do
		list[i] = w
	end
	for _, w in ipairs(list) do
		w:Destroy()
	end
end

function Lib:CreateWindow(opts)
	opts = opts or {}
	local W = setmetatable({}, Window)
	W.Options = opts
	W.Title = opts.Title or "Client"
	W.Subtitle = opts.Subtitle or ""
	W.Style = (opts.Style == "Panels") and "Panels" or "Window"
	W.Theme = resolveTheme(opts.Theme)
	W.ThemeName = (type(opts.Theme) == "string" and Lib.Themes[opts.Theme]) and opts.Theme or Lib.DefaultTheme
	if opts.Accent then
		W.Theme.Accent = opts.Accent
		W.Theme.Accent2 = opts.Accent2 or shiftHue(opts.Accent, 0.12)
	end
	W._baseAccent, W._baseAccent2 = W.Theme.Accent, W.Theme.Accent2
	W._rainbow = opts.Rainbow == true
	W._rainbowSpeed = opts.RainbowSpeed or 4
	W.ToggleKey = toKeyCode(opts.ToggleKey) or Enum.KeyCode.RightShift
	W.Columns = clamp(opts.Columns or 2, 1, 4)
	W.ShowDescriptions = opts.ShowDescriptions ~= false
	W.PanelWidth = opts.PanelWidth or 220
	W.NotifyOnToggle = opts.NotifyOnToggle ~= false
	W.ConfigAdapter = opts.ConfigAdapter
	W.PlanColors = merge({
		Plus = Color3.fromRGB(120, 200, 255),
		Pro = Color3.fromRGB(150, 130, 255),
		Premium = Color3.fromRGB(150, 130, 255),
		Lifetime = Color3.fromRGB(247, 205, 120),
	}, opts.PlanColors)
	W.PlayerInfo = { Name = (LocalPlayer and (LocalPlayer.DisplayName or LocalPlayer.Name)) or "Player", Plan = opts.Plan }
	W.Flags, W.Categories, W.Modules = {}, {}, {}
	W.Visible = false
	W.Toggled = Signal.new()
	W.StyleChanged = Signal.new()
	W.FlagChanged = Signal.new()
	W._binds, W._refreshers, W._conns = {}, {}, {}
	W._elements, W._flagObjs, W._usedFlags = {}, {}, {}
	W._keyElements, W._cards, W._infoLines, W._hudEntries = {}, {}, {}, {}
	W._z, W._notifCount = 10, 0
	W._dimTarget = (opts.Dim == false) and 1 or (opts.DimTransparency or 0.55)

	-- root gui -----------------------------------------------------------------
	local parent = opts.Parent
	if not parent and LocalPlayer then
		local ok, pg = pcall(function()
			return LocalPlayer:WaitForChild("PlayerGui", 10)
		end)
		parent = ok and pg or nil
	end
	local gui = new("ScreenGui", {
		Name = opts.Name or "GenericMCUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = opts.DisplayOrder or 1000,
		IgnoreGuiInset = true,
		Parent = parent,
	})
	W.Gui = gui
	local inset = 0
	pcall(function()
		local topLeft = GuiService:GetGuiInset()
		if type(topLeft.Y) == "number" then
			inset = topLeft.Y
		end
	end)
	-- HUD sits below the Roblox top bar; the GUI itself uses the full screen.
	W.HudFrame = new("Frame", {
		Name = "HUD", BackgroundTransparency = 1, Parent = gui,
		Position = UDim2.fromOffset(0, inset), Size = UDim2.new(1, 0, 1, -inset),
	})
	W.Root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	W._scaler = new("UIScale", { Scale = 1, Parent = W.Root })
	W.Dim = new("Frame", {
		Name = "Dim",
		Parent = W.Root,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
	})
	if opts.Blur then
		W._blurSize = type(opts.Blur) == "number" and opts.Blur or 14
		W._blur = new("BlurEffect", { Name = "GenericMCUIBlur", Size = 0, Parent = Lighting })
	end

	-- search pill (shared by both layouts) -------------------------------------
	W._searchPill = new("Frame", { Name = "Search", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 })
	W:_bind(W._searchPill, "BackgroundColor3", "SurfaceAlt")
	W:_pill(W._searchPill)
	W:_stroke(W._searchPill)
	W._searchBox = new("TextBox", {
		Parent = W._searchPill,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 0),
		Size = UDim2.new(1, -30, 1, 0),
		PlaceholderText = "Search modules",
		Text = "",
		ClearTextOnFocus = false,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	W:_bind(W._searchBox, "TextColor3", "Text")
	W:_bind(W._searchBox, "PlaceholderColor3", "TextDim")
	W:_bind(W._searchBox, "Font", "Font")
	W._searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		W:_applySearch(W._searchBox.Text)
	end)

	-- Window layout --------------------------------------------------------------
	local size = opts.Size or Vector2.new(700, 460)
	W.Main = new("Frame", {
		Name = "Main",
		Parent = W.Root,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = opts.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		ClipsDescendants = true,
		BorderSizePixel = 0,
	})
	W:_bind(W.Main, "BackgroundColor3", "Surface")
	W:_bind(W.Main, "BackgroundTransparency", "Transparency")
	W:_corner(W.Main, 1.35)
	W:_stroke(W.Main)

	local side = new("Frame", { Name = "Sidebar", Parent = W.Main, Size = UDim2.new(0, 196, 1, 0), BorderSizePixel = 0 })
	W:_bind(side, "BackgroundColor3", "Background")
	side.BackgroundTransparency = 0.35
	local sideLine = new("Frame", {
		Parent = side, Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0), BorderSizePixel = 0,
	})
	W:_bind(sideLine, "BackgroundColor3", "Stroke")
	W:_bind(sideLine, "BackgroundTransparency", "StrokeTransparency")

	local brand = new("Frame", { Parent = side, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58) })
	local logo = new("Frame", { Parent = brand, Position = UDim2.new(0, 18, 0.5, -10), Size = UDim2.fromOffset(20, 20), BorderSizePixel = 0 })
	W:_corner(logo, 0.45)
	W:_gradient(logo)
	logo.BackgroundColor3 = Color3.new(1, 1, 1)
	W._brandLabel = W:_label({
		Parent = brand, Text = W.Title, Position = UDim2.new(0, 48, 0, 0), Size = UDim2.new(1, -56, 1, 0),
		TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd,
	}, "bold")

	W._tabList = new("ScrollingFrame", {
		Name = "Tabs",
		Parent = side,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(1, 0, 1, -58 - 120),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 0,
	})
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = W._tabList })
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), Parent = W._tabList })

	local footer = new("Frame", {
		Name = "Footer", Parent = side, BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -120), Size = UDim2.new(1, 0, 0, 120),
	})
	if opts.PlayerCard ~= false then
		W:_buildCard(footer, false)
	end
	W._hint = W:_label({
		Parent = footer, Position = UDim2.new(0, 16, 0, 80), Size = UDim2.new(1, -28, 0, 28),
		Text = "", TextSize = 11,
	}, "dim")

	local content = new("Frame", {
		Name = "Content", Parent = W.Main, BackgroundTransparency = 1,
		Position = UDim2.new(0, 196, 0, 0), Size = UDim2.new(1, -196, 1, 0),
	})
	local header = W:_button({
		Name = "Header", Parent = content, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 68),
	})
	W._headTitle = W:_label({
		Parent = header, Position = UDim2.new(0, 24, 0, 13), Size = UDim2.new(1, -290, 0, 24),
		TextSize = 20, TextTruncate = Enum.TextTruncate.AtEnd,
	}, "bold")
	W._headSub = W:_label({
		Parent = header, Position = UDim2.new(0, 24, 0, 38), Size = UDim2.new(1, -290, 0, 16), TextSize = 12,
	}, "dim")
	W._searchSlotWindow = new("Frame", {
		Parent = header, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, 0), Size = UDim2.fromOffset(180, 34),
	})
	local closeBtn = W:_button({
		Parent = header, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(30, 30), Text = "X", TextSize = 12,
	})
	W:_bind(closeBtn, "Font", "FontBold")
	W:_bind(closeBtn, "TextColor3", "TextDim")
	W:_field(closeBtn, "BackgroundColor3", 0.06)
	W:_pill(closeBtn)
	closeBtn.Activated:Connect(function()
		W:SetVisible(false)
	end)
	local headLine = new("Frame", {
		Parent = header, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0,
	})
	W:_bind(headLine, "BackgroundColor3", "Stroke")
	W:_bind(headLine, "BackgroundTransparency", "StrokeTransparency")
	W:_makeDraggable(header, W.Main, false)
	W._pages = new("Frame", {
		Name = "Pages", Parent = content, BackgroundTransparency = 1, ClipsDescendants = true,
		Position = UDim2.new(0, 0, 0, 68), Size = UDim2.new(1, 0, 1, -68),
	})
	local resultsPage, resultsCols = buildPage(W, W._pages, "Results")
	W.Results = { Page = resultsPage, Cols = resultsCols }

	-- Panels layout --------------------------------------------------------------
	W.PanelsHost = new("Frame", {
		Name = "Panels", Parent = W.Root, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false,
	})
	local bar = new("Frame", {
		Name = "Bar", Parent = W.PanelsHost, BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.new(0, 0, 0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar,
	})
	local brandPill = new("Frame", {
		Parent = bar, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, LayoutOrder = 1,
	})
	W:_bind(brandPill, "BackgroundColor3", "Surface")
	brandPill.BackgroundTransparency = 0.08
	W:_pill(brandPill)
	W:_stroke(brandPill)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 16), Parent = brandPill })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder, Parent = brandPill,
	})
	local logo2 = new("Frame", { Parent = brandPill, Size = UDim2.fromOffset(18, 18), BorderSizePixel = 0, LayoutOrder = 1 })
	W:_corner(logo2, 0.4)
	W:_gradient(logo2)
	logo2.BackgroundColor3 = Color3.new(1, 1, 1)
	W._panelsBrand = W:_label({
		Parent = brandPill, Text = W.Title, TextSize = 14, LayoutOrder = 2,
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
	}, "bold")
	W._searchSlotPanels = new("Frame", { Parent = bar, BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 40), LayoutOrder = 2 })
	if opts.PlayerCard ~= false then
		local cardHolder = new("Frame", {
			Parent = bar, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3,
		})
		W:_buildCard(cardHolder, true)
	end
	local closeP = W:_button({ Parent = bar, Size = UDim2.fromOffset(40, 40), LayoutOrder = 4, Text = "X", TextSize = 12 })
	W:_bind(closeP, "Font", "FontBold")
	W:_bind(closeP, "TextColor3", "TextDim")
	W:_bind(closeP, "BackgroundColor3", "Surface")
	closeP.BackgroundTransparency = 0.08
	W:_pill(closeP)
	W:_stroke(closeP)
	closeP.Activated:Connect(function()
		W:SetVisible(false)
	end)

	-- HUD --------------------------------------------------------------------------
	W.HUD = setmetatable({ Window = W }, Hud)
	local wm = new("Frame", {
		Name = "Watermark", Parent = W.HudFrame, Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(0, 0, 0, 34), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0,
		Visible = opts.Watermark ~= false,
	})
	W.HudWatermark = wm
	W:_bind(wm, "BackgroundColor3", "Surface")
	wm.BackgroundTransparency = 0.12
	W:_corner(wm, 0.75)
	W:_stroke(wm)
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 14), Parent = wm })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wm,
	})
	local wlogo = new("Frame", { Parent = wm, Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0, LayoutOrder = 1 })
	W:_corner(wlogo, 0.4)
	W:_gradient(wlogo)
	wlogo.BackgroundColor3 = Color3.new(1, 1, 1)
	W._wmTitle = W:_label({
		Parent = wm, Text = W.Title, TextSize = 14, LayoutOrder = 2,
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
	}, "bold")
	W._wmVersion = W:_label({
		Parent = wm, Text = W.Subtitle, TextSize = 11, LayoutOrder = 3,
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
	}, "dim")

	W.HudList = new("Frame", {
		Name = "ModuleList", Parent = W.HudFrame, BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		Visible = opts.ModuleList ~= false,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = W.HudList,
	})
	W._refreshers.hudlist = function()
		local T = W.Theme
		for _, e in ipairs(W._hudEntries) do
			local a = (e.total <= 1) and 0 or (e.index - 1) / (e.total - 1)
			e.dot.BackgroundColor3 = T.Accent:Lerp(T.Accent2, a)
		end
	end

	W.HudInfo = new("Frame", {
		Name = "Info", Parent = W.HudFrame, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY, BorderSizePixel = 0,
		Visible = opts.InfoLines ~= false,
	})
	W:_bind(W.HudInfo, "BackgroundColor3", "Surface")
	W.HudInfo.BackgroundTransparency = 0.15
	W:_corner(W.HudInfo, 0.75)
	W:_stroke(W.HudInfo)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		Parent = W.HudInfo,
	})
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = W.HudInfo })
	W._fps = 60
	W.HUD:AddInfo("FPS", function()
		return string.format("%d", math.floor(W._fps + 0.5))
	end)
	W.HUD:AddInfo("Ping", function()
		local ok, p = pcall(function()
			return LocalPlayer:GetNetworkPing() * 1000
		end)
		return string.format("%d ms", ok and type(p) == "number" and math.floor(p + 0.5) or 0)
	end)

	W.NotifFrame = new("Frame", {
		Name = "Notifications", Parent = gui, BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.new(0, 300, 1, -28),
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom, Parent = W.NotifFrame,
	})

	if opts.MobileButton ~= false and UserInputService.TouchEnabled then
		W._mobileButton = W:_button({
			Name = "OpenButton", Parent = gui, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(46, 46), Text = "",
		})
		W:_bind(W._mobileButton, "BackgroundColor3", "Surface")
		W:_pill(W._mobileButton)
		W:_stroke(W._mobileButton)
		local mlogo = new("Frame", {
			Parent = W._mobileButton, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1),
		})
		W:_corner(mlogo, 0.4)
		W:_gradient(mlogo)
		W._mobileButton.Activated:Connect(function()
			W:SetVisible(true)
		end)
	end

	-- theme-dependent refreshers that are not simple bindings ----------------------
	W._refreshers.cards = function()
		W:_updateCards()
	end

	-- input ----------------------------------------------------------------------
	W:_conn(UserInputService.InputBegan:Connect(function(input, processed)
		if W._capture then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				local fn = W._capture
				W._capture, W._captureCancel = nil, nil
				local key = input.KeyCode
				if key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Delete then
					key = nil
				end
				fn(key)
			end
			return
		end
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if input.KeyCode == W.ToggleKey then
			W:Toggle()
			return
		end
		for _, m in ipairs(W.Modules) do
			if m.Toggleable and m.Keybind and m.Keybind == input.KeyCode then
				if m.KeybindMode == "Hold" then
					m:SetEnabled(true)
				else
					m:Toggle()
				end
			end
		end
		for _, el in ipairs(W._keyElements) do
			if el.Value and el.Value == input.KeyCode then
				el.Pressed:Fire(input.KeyCode)
			end
		end
	end))
	W:_conn(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		for _, m in ipairs(W.Modules) do
			if m.Toggleable and m.Keybind == input.KeyCode and m.KeybindMode == "Hold" then
				m:SetEnabled(false)
			end
		end
	end))

	local infoClock, rainbowClock, hue = 0, 0, 0
	W:_conn(RunService.Heartbeat:Connect(function(dt)
		if dt > 0 then
			W._fps = W._fps * 0.92 + (1 / dt) * 0.08
		end
		infoClock = infoClock + dt
		if infoClock >= 0.25 then
			infoClock = 0
			for _, l in ipairs(W._infoLines) do
				local ok, v = pcall(l.fn)
				l.value.Text = ok and tostring(v) or "?"
			end
		end
		if W._rainbow then
			rainbowClock = rainbowClock + dt
			hue = (hue + dt * 0.05 * W._rainbowSpeed) % 1
			if rainbowClock >= 1 / 24 then
				rainbowClock = 0
				W._lastRainbow = Color3.fromHSV(hue, 0.62, 1)
				W.Theme.Accent = W._lastRainbow
				W.Theme.Accent2 = Color3.fromHSV((hue + 0.12) % 1, 0.62, 1)
				W:_refreshTokens({ Accent = true, Accent2 = true })
			end
		end
	end))

	-- finish -----------------------------------------------------------------------
	W:SetToggleKey(W.ToggleKey)
	W:SetScale(opts.Scale or 1)
	W:SetPlayerCard({ Plan = opts.Plan })
	W:SetStyle(W.Style)
	W:SetTitle(W.Title, W.Subtitle)
	W:_rebuildHud()
	Lib.Windows[#Lib.Windows + 1] = W
	if opts.StartVisible ~= false then
		W:SetVisible(true)
	end
	return W
end

Lib.Util = { Create = new, Tween = tween, Signal = Signal }

return Lib
