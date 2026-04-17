-- ================================================================
-- Simple RemoteSpy (Enhanced) by fearliam
-- Responsive (mobile + desktop), with advanced features:
--   * Incoming + Outgoing remote hooks (Events & Functions)
--   * Tabs: All / Incoming / Outgoing
--   * Per-remote call counter (auto-merge duplicates)
--   * Auto-generated reproduction script per log
--   * Copy / Generate / Block / Delete per entry
--   * Pause / Resume logging
--   * Export all logs to clipboard
--   * Search filter
--   * Draggable + resizable window (desktop)
--   * Floating toggle button (great for mobile)
--   * Keybind toggle: RightShift (PC) / floating icon (Mobile)
-- ================================================================

-- ---------- SERVICES ----------
local Players       = game:GetService("Players")
local UIS           = game:GetService("UserInputService")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ---------- CLEANUP PREVIOUS ----------
local pg = player:WaitForChild("PlayerGui")
for _, v in ipairs(pg:GetChildren()) do
	if v.Name == "RemoteLoggerGui" or v.Name == "RemoteLoggerToggle" then
		v:Destroy()
	end
end

-- ---------- EXPLOIT SHIMS (safe fallbacks) ----------
local setclipboard = (setclipboard) or (syn and syn.write_clipboard)
	or (writeclipboard) or (toclipboard) or function() end

local hookmetamethod   = hookmetamethod
local getnamecallmethod = getnamecallmethod or (getrawmetatable and function()
	return debug.getinfo(2, "n").name
end)
local checkcaller = checkcaller or function() return false end

-- ---------- RESPONSIVE SIZING ----------
local camera   = workspace.CurrentCamera
local viewport = camera.ViewportSize
local isMobile = UIS.TouchEnabled and not UIS.MouseEnabled
local isSmall  = viewport.X < 700

local UI_SCALE = isSmall and 1.0 or 0.9
local BTN_H    = isMobile and 34 or 26
local FONT_S   = isMobile and 15 or 14

-- ---------- COLORS ----------
local C = {
	bg     = Color3.fromRGB(22, 22, 26),
	panel  = Color3.fromRGB(32, 32, 38),
	panel2 = Color3.fromRGB(42, 42, 50),
	accent = Color3.fromRGB(90, 140, 255),
	good   = Color3.fromRGB(80, 200, 120),
	warn   = Color3.fromRGB(230, 170, 70),
	bad    = Color3.fromRGB(220, 80, 80),
	text   = Color3.fromRGB(235, 235, 240),
	mute   = Color3.fromRGB(160, 160, 170),
}

-- ---------- ROOT GUI ----------
local gui = Instance.new("ScreenGui")
gui.Name = "RemoteLoggerGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = pg

-- Helpers
local function corner(p, r) local c = Instance.new("UICorner", p) c.CornerRadius = UDim.new(0, r or 8) return c end
local function stroke(p, col, t) local s = Instance.new("UIStroke", p) s.Color = col or C.panel2 s.Thickness = t or 1 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border return s end
local function pad(p, n) local u = Instance.new("UIPadding", p) u.PaddingTop = UDim.new(0,n) u.PaddingBottom = UDim.new(0,n) u.PaddingLeft = UDim.new(0,n) u.PaddingRight = UDim.new(0,n) return u end

-- ---------- MAIN FRAME ----------
local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)

if isSmall then
	main.Size = UDim2.new(0.95, 0, 0.8, 0)
else
	main.Size = UDim2.new(0, math.clamp(viewport.X * 0.5, 420, 720), 0, math.clamp(viewport.Y * 0.65, 360, 560))
end

main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.Active = true
main.ClipsDescendants = true
main.Parent = gui
corner(main, 12)
stroke(main, C.panel2, 1)

-- Min window size we won't shrink below when resizing
local MIN_W, MIN_H = 340, 280

-- ---------- HEADER ----------
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = C.panel
header.BorderSizePixel = 0
header.Parent = main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -110, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.Text = "RemoteSpy  •  by fearliam"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = C.text
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local function headerBtn(txt, xOff, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 30, 0, 26)
	b.Position = UDim2.new(1, xOff, 0.5, -13)
	b.Text = txt
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = C.text
	b.BackgroundColor3 = color or C.panel2
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = header
	corner(b, 6)
	return b
end

local btnMin   = headerBtn("–", -76)
local btnClose = headerBtn("X", -40, C.bad)

-- ---------- DRAG (header) ----------
do
	local dragging, dStart, sPos
	local function begin(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dStart = i.Position
			sPos = main.Position
		end
	end
	local function update(i)
		if not dragging then return end
		if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
			local d = i.Position - dStart
			main.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
		end
	end
	local function stop(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end
	header.InputBegan:Connect(begin)
	header.InputChanged:Connect(update)
	UIS.InputEnded:Connect(stop)
end

-- ---------- TAB BAR ----------
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 32)
tabBar.Position = UDim2.new(0, 8, 0, 48)
tabBar.BackgroundColor3 = C.panel
tabBar.BorderSizePixel = 0
tabBar.Parent = main
corner(tabBar, 8)

local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
pad(tabBar, 4)

local currentTab = "All"
local tabButtons = {}

local function setTab(name)
	currentTab = name
	for n, b in pairs(tabButtons) do
		b.BackgroundColor3 = (n == name) and C.accent or C.panel2
		b.TextColor3 = (n == name) and Color3.new(1,1,1) or C.mute
	end
end

local function makeTab(name)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 90, 1, -4)
	b.Text = name
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.BackgroundColor3 = C.panel2
	b.TextColor3 = C.mute
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = tabBar
	corner(b, 6)
	tabButtons[name] = b
	b.MouseButton1Click:Connect(function() setTab(name); applyFilters() end)
	return b
end

makeTab("All"); makeTab("Incoming"); makeTab("Outgoing")
setTab("All")

-- ---------- TOOLBAR (search + actions) ----------
local toolbar = Instance.new("Frame")
toolbar.Size = UDim2.new(1, -16, 0, BTN_H + 4)
toolbar.Position = UDim2.new(0, 8, 0, 88)
toolbar.BackgroundTransparency = 1
toolbar.Parent = main

local search = Instance.new("TextBox")
search.Size = UDim2.new(0.55, -4, 1, 0)
search.Position = UDim2.new(0, 0, 0, 0)
search.PlaceholderText = "Search remotes or args..."
search.Text = ""
search.Font = Enum.Font.Gotham
search.TextSize = FONT_S
search.TextColor3 = C.text
search.PlaceholderColor3 = C.mute
search.BackgroundColor3 = C.panel
search.BorderSizePixel = 0
search.ClearTextOnFocus = false
search.TextXAlignment = Enum.TextXAlignment.Left
search.Parent = toolbar
corner(search, 6)
pad(search, 8)

local function actionBtn(text, color)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = C.text
	b.BackgroundColor3 = color or C.panel2
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = toolbar
	corner(b, 6)
	return b
end

local btnPause  = actionBtn("PAUSE")
local btnExport = actionBtn("EXPORT", C.accent)
local btnClear  = actionBtn("CLEAR", C.bad)

-- layout the right-side action buttons
do
	local count = 3
	local gap = 4
	local areaX = 0.45
	local width = (areaX - (gap * (count - 1)) / main.AbsoluteSize.X) / count
	-- simpler: use scale math
	btnPause.Size  = UDim2.new(0.15, -2, 1, 0)
	btnExport.Size = UDim2.new(0.15, -2, 1, 0)
	btnClear.Size  = UDim2.new(0.15, -2, 1, 0)
	btnPause.Position  = UDim2.new(0.55, 4, 0, 0)
	btnExport.Position = UDim2.new(0.70, 6, 0, 0)
	btnClear.Position  = UDim2.new(0.85, 8, 0, 0)
end

-- ---------- STATUS BAR ----------
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 18)
status.Position = UDim2.new(0, 8, 0, 88 + BTN_H + 8)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = C.mute
status.Text = "0 logs  •  logging active"
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = main

-- ---------- SCROLL (logs) ----------
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -16, 1, -(88 + BTN_H + 34))
scroll.Position = UDim2.new(0, 8, 0, 88 + BTN_H + 30)
scroll.CanvasSize = UDim2.new()
scroll.ScrollBarThickness = 5
scroll.ScrollBarImageColor3 = C.accent
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Parent = main

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end)

-- ---------- RESIZE HANDLE (desktop only) ----------
if not isMobile then
	local grip = Instance.new("TextButton")
	grip.Size = UDim2.new(0, 16, 0, 16)
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.Position = UDim2.new(1, -4, 1, -4)
	grip.BackgroundColor3 = C.panel2
	grip.Text = "◢"
	grip.Font = Enum.Font.GothamBold
	grip.TextSize = 12
	grip.TextColor3 = C.mute
	grip.AutoButtonColor = false
	grip.BorderSizePixel = 0
	grip.Parent = main
	corner(grip, 4)

	local resizing, rStart, sSize
	grip.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = true
			rStart = i.Position
			sSize = main.AbsoluteSize
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if resizing and i.UserInputType == Enum.UserInputType.MouseMovement then
			local d = i.Position - rStart
			local w = math.max(MIN_W, sSize.X + d.X)
			local h = math.max(MIN_H, sSize.Y + d.Y)
			main.Size = UDim2.new(0, w, 0, h)
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then resizing = false end
	end)
end

-- ================================================================
-- STATE & LOGIC
-- ================================================================

local logs          = {}   -- unique key -> {box, data}
local order         = 0
local paused        = false
local blocked       = {}   -- fullName -> true
local minimized     = false
local originalSize  = main.Size

-- Pretty-format a single arg
local function reprArg(v)
	local t = typeof(v)
	if t == "string" then
		return string.format('%q', v)
	elseif t == "number" or t == "boolean" or t == "nil" then
		return tostring(v)
	elseif t == "Instance" then
		return string.format('game:GetService("%s")%s',
			v:FindFirstAncestorOfClass("DataModel") and v:GetFullName():match("^(%w+)") or "Workspace",
			"")
	elseif t == "Vector3" then
		return string.format("Vector3.new(%s,%s,%s)", v.X, v.Y, v.Z)
	elseif t == "Vector2" then
		return string.format("Vector2.new(%s,%s)", v.X, v.Y)
	elseif t == "CFrame" then
		return "CFrame.new(" .. tostring(v) .. ")"
	elseif t == "Color3" then
		return string.format("Color3.fromRGB(%d,%d,%d)", v.R*255, v.G*255, v.B*255)
	elseif t == "table" then
		local parts = {}
		for k, val in pairs(v) do
			parts[#parts+1] = "["..tostring(k).."]="..reprArg(val)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return "<"..t..">"
end

local function formatArgs(args)
	local t = {}
	for i = 1, #args do t[i] = reprArg(args[i]) end
	return table.concat(t, ", ")
end

-- Build reproduction script for a remote call
local function buildCallScript(remote, args, dir)
	local path = remote:GetFullName()
	local argStr = formatArgs(args)
	local method
	if remote:IsA("RemoteEvent") then
		method = (dir == "Outgoing") and "FireServer" or "-- (incoming event, cannot re-fire from client)"
	elseif remote:IsA("RemoteFunction") then
		method = "InvokeServer"
	elseif remote:IsA("BindableEvent") then
		method = "Fire"
	elseif remote:IsA("BindableFunction") then
		method = "Invoke"
	else
		method = "Fire"
	end
	if method:sub(1,2) == "--" then
		return ("-- Source: %s\n-- %s"):format(path, method)
	end
	return ("local r = %s\nr:%s(%s)"):format(path, method, argStr)
end

-- ---------- FILTERS ----------
function applyFilters()
	local q = string.lower(search.Text)
	local visible = 0
	for _, entry in pairs(logs) do
		local d = entry.data
		local matchTab = (currentTab == "All") or (currentTab == d.direction)
		local matchText = (q == "") or string.find(string.lower(d.searchBlob), q, 1, true) ~= nil
		local show = matchTab and matchText
		entry.box.Visible = show
		if show then visible += 1 end
	end
	status.Text = string.format("%d logs%s  •  %s", visible, paused and " (paused)" or "", paused and "paused" or "logging")
end

search:GetPropertyChangedSignal("Text"):Connect(applyFilters)

-- ---------- CREATE / UPDATE LOG ENTRY ----------
local function createOrUpdateLog(remote, args, direction)
	if paused then return end
	if blocked[remote:GetFullName()] then return end

	local key = remote:GetFullName() .. "|" .. direction
	local existing = logs[key]

	local argText = formatArgs(args)
	local fullText = ("[%s] %s\n→ %s"):format(direction, remote:GetFullName(), argText)

	-- If exact same call exists, bump counter
	if existing and existing.data.argText == argText then
		existing.data.count += 1
		existing.countLabel.Text = "x" .. existing.data.count
		existing.countLabel.Visible = true
		return
	end

	-- If same remote/direction but new args, create new entry (so history is preserved)
	order -= 1

	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, -4, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = C.panel
	box.BorderSizePixel = 0
	box.LayoutOrder = order
	box.Parent = scroll
	corner(box, 8)
	stroke(box, C.panel2, 1)

	-- direction badge color
	local badgeColor = (direction == "Outgoing") and C.warn or C.good

	local badge = Instance.new("Frame")
	badge.Size = UDim2.new(0, 4, 1, -12)
	badge.Position = UDim2.new(0, 6, 0, 6)
	badge.BackgroundColor3 = badgeColor
	badge.BorderSizePixel = 0
	badge.Parent = box
	corner(badge, 2)

	local pathLabel = Instance.new("TextLabel")
	pathLabel.Size = UDim2.new(1, -150, 0, 16)
	pathLabel.Position = UDim2.new(0, 18, 0, 8)
	pathLabel.BackgroundTransparency = 1
	pathLabel.Font = Enum.Font.GothamBold
	pathLabel.TextSize = 13
	pathLabel.TextColor3 = badgeColor
	pathLabel.TextXAlignment = Enum.TextXAlignment.Left
	pathLabel.Text = ("[%s] %s"):format(direction:upper(), remote:GetFullName())
	pathLabel.TextTruncate = Enum.TextTruncate.AtEnd
	pathLabel.Parent = box

	local argsLabel = Instance.new("TextLabel")
	argsLabel.Size = UDim2.new(1, -150, 0, 0)
	argsLabel.AutomaticSize = Enum.AutomaticSize.Y
	argsLabel.Position = UDim2.new(0, 18, 0, 26)
	argsLabel.BackgroundTransparency = 1
	argsLabel.Font = Enum.Font.Code
	argsLabel.TextSize = 13
	argsLabel.TextColor3 = C.text
	argsLabel.TextXAlignment = Enum.TextXAlignment.Left
	argsLabel.TextYAlignment = Enum.TextYAlignment.Top
	argsLabel.TextWrapped = true
	argsLabel.Text = "→ " .. argText
	argsLabel.Parent = box

	-- spacer at the bottom
	local spacer = Instance.new("Frame")
	spacer.Size = UDim2.new(1, 0, 0, 10)
	spacer.Position = UDim2.new(0, 0, 1, 0)
	spacer.BackgroundTransparency = 1
	spacer.Parent = box

	-- call count badge
	local countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.new(0, 40, 0, 18)
	countLabel.Position = UDim2.new(1, -134, 0, 8)
	countLabel.BackgroundColor3 = C.panel2
	countLabel.TextColor3 = C.text
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 12
	countLabel.Text = "x1"
	countLabel.Visible = false
	countLabel.Parent = box
	corner(countLabel, 4)

	-- action buttons (stacked for mobile friendliness)
	local function rowBtn(txt, idx, color)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 86, 0, 22)
		b.Position = UDim2.new(1, -92, 0, 8 + (idx - 1) * 26)
		b.Text = txt
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		b.TextColor3 = C.text
		b.BackgroundColor3 = color or C.panel2
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.Parent = box
		corner(b, 5)
		return b
	end

	local copyBtn  = rowBtn("COPY",     1, C.panel2)
	local genBtn   = rowBtn("GEN SCRIPT", 2, C.accent)
	local blockBtn = rowBtn("BLOCK",    3, C.warn)
	local delBtn   = rowBtn("DELETE",   4, C.bad)

	copyBtn.MouseButton1Click:Connect(function()
		setclipboard(fullText)
		copyBtn.Text = "COPIED!"
		task.delay(1, function() if copyBtn.Parent then copyBtn.Text = "COPY" end end)
	end)

	genBtn.MouseButton1Click:Connect(function()
		local s = buildCallScript(remote, args, direction)
		setclipboard(s)
		genBtn.Text = "COPIED!"
		task.delay(1, function() if genBtn.Parent then genBtn.Text = "GEN SCRIPT" end end)
	end)

	blockBtn.MouseButton1Click:Connect(function()
		blocked[remote:GetFullName()] = true
		-- remove all entries for this remote path
		for k, entry in pairs(logs) do
			if entry.data.path == remote:GetFullName() then
				entry.box:Destroy()
				logs[k] = nil
			end
		end
		applyFilters()
	end)

	delBtn.MouseButton1Click:Connect(function()
		logs[key] = nil
		box:Destroy()
		applyFilters()
	end)

	logs[key] = {
		box = box,
		countLabel = countLabel,
		data = {
			path = remote:GetFullName(),
			direction = direction,
			argText = argText,
			searchBlob = fullText,
			count = 1,
		},
	}
	applyFilters()
end

-- ================================================================
-- TOOLBAR ACTIONS
-- ================================================================

btnPause.MouseButton1Click:Connect(function()
	paused = not paused
	btnPause.Text = paused and "RESUME" or "PAUSE"
	btnPause.BackgroundColor3 = paused and C.good or C.panel2
	applyFilters()
end)

btnClear.MouseButton1Click:Connect(function()
	for k, entry in pairs(logs) do entry.box:Destroy() end
	table.clear(logs)
	applyFilters()
end)

btnExport.MouseButton1Click:Connect(function()
	local parts = {}
	for _, entry in pairs(logs) do
		parts[#parts+1] = entry.data.searchBlob
	end
	setclipboard(table.concat(parts, "\n\n"))
	btnExport.Text = "COPIED!"
	task.delay(1, function() btnExport.Text = "EXPORT" end)
end)

-- ================================================================
-- MINIMIZE / CLOSE / TOGGLE
-- ================================================================

local function hideBody(hidden)
	tabBar.Visible   = not hidden
	toolbar.Visible  = not hidden
	status.Visible   = not hidden
	scroll.Visible   = not hidden
end

btnMin.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		originalSize = main.Size
		main.Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, 40)
		btnMin.Text = "+"
		hideBody(true)
	else
		main.Size = originalSize
		btnMin.Text = "–"
		hideBody(false)
	end
end)

-- ---------- FLOATING TOGGLE BUTTON ----------
local toggleGui = Instance.new("ScreenGui")
toggleGui.Name = "RemoteLoggerToggle"
toggleGui.ResetOnSpawn = false
toggleGui.IgnoreGuiInset = true
toggleGui.Parent = pg

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 46, 0, 46)
toggleBtn.AnchorPoint = Vector2.new(0, 0)
toggleBtn.Position = UDim2.new(0, 12, 0, 80)
toggleBtn.Text = "RS"
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 16
toggleBtn.TextColor3 = C.text
toggleBtn.BackgroundColor3 = C.accent
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = true
toggleBtn.Parent = toggleGui
corner(toggleBtn, 23)
stroke(toggleBtn, Color3.fromRGB(255,255,255), 1).Transparency = 0.7

-- Make the floating button draggable too
do
	local dragging, dStart, sPos
	toggleBtn.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; dStart = i.Position; sPos = toggleBtn.Position
		end
	end)
	toggleBtn.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dStart
			toggleBtn.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local function toggleMain()
	main.Visible = not main.Visible
end

toggleBtn.MouseButton1Click:Connect(toggleMain)

btnClose.MouseButton1Click:Connect(function()
	main.Visible = false
end)

-- Keybind (RightShift) on PC
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		toggleMain()
	end
end)

-- ================================================================
-- REMOTE HOOKS
-- ================================================================

-- Incoming hooks (OnClientEvent / OnClientInvoke)
local hooked = setmetatable({}, {__mode = "k"})
local function hookIncoming(obj)
	if hooked[obj] then return end
	hooked[obj] = true
	if obj:IsA("RemoteEvent") then
		obj.OnClientEvent:Connect(function(...)
			createOrUpdateLog(obj, {...}, "Incoming")
		end)
	end
	-- NOTE: OnClientInvoke can only have a single assignment; we don't override it here
	-- to avoid breaking the game. Outgoing Invoke is still captured via namecall hook.
end

for _, d in ipairs(game:GetDescendants()) do hookIncoming(d) end
game.DescendantAdded:Connect(hookIncoming)

-- Outgoing hooks via metatable (FireServer / InvokeServer)
local okHook = pcall(function()
	if not hookmetamethod then error("no hookmetamethod") end
	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
		local method = getnamecallmethod and getnamecallmethod() or ""
		if not checkcaller() and (method == "FireServer" or method == "InvokeServer") then
			if typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
				createOrUpdateLog(self, {...}, "Outgoing")
			end
		end
		return oldNamecall(self, ...)
	end)
end)

if not okHook then
	-- Fallback: wrap FireServer / InvokeServer per-remote (less reliable but works on some executors)
	local function wrapOutgoing(obj)
		if obj:IsA("RemoteEvent") then
			local orig = obj.FireServer
			obj.FireServer = function(self, ...)
				createOrUpdateLog(self, {...}, "Outgoing")
				return orig(self, ...)
			end
		elseif obj:IsA("RemoteFunction") then
			local orig = obj.InvokeServer
			obj.InvokeServer = function(self, ...)
				createOrUpdateLog(self, {...}, "Outgoing")
				return orig(self, ...)
			end
		end
	end
	for _, d in ipairs(game:GetDescendants()) do pcall(wrapOutgoing, d) end
	game.DescendantAdded:Connect(function(d) pcall(wrapOutgoing, d) end)
end

-- ================================================================
-- VIEWPORT CHANGE (rotate / resize)
-- ================================================================
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	local vp = camera.ViewportSize
	if vp.X < 700 then
		main.Size = UDim2.new(0.95, 0, 0.8, 0)
	else
		if not minimized then
			main.Size = UDim2.new(0, math.clamp(vp.X * 0.5, 420, 720), 0, math.clamp(vp.Y * 0.65, 360, 560))
			originalSize = main.Size
		end
	end
end)

applyFilters()
print("[RemoteSpy] loaded  •  RightShift to toggle  •  floating RS button works on mobile")
