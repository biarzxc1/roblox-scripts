-- ==============================================
--   Advanced RemoteSpy v2  by fearliam
--   Works on PC + Mobile | RemoteEvent + RemoteFunction
--   Features: Script Gen, Blacklist, Pause, Group, Pin, Export
-- ==============================================

local Players        = game:GetService("Players")
local UIS            = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")

local player         = Players.LocalPlayer
local camera         = workspace.CurrentCamera
local isMobile       = UIS.TouchEnabled and not UIS.MouseEnabled

-- ── Screen dimensions ────────────────────────────────────────────────────────
local VP = camera.ViewportSize
local SW, SH = VP.X, VP.Y

-- Responsive dimensions
local PANEL_W = isMobile and math.min(SW - 20, 420) or 460
local PANEL_H = isMobile and math.min(SH - 60, 560) or 540
local START_X = isMobile and (SW - PANEL_W) / 2 or 20
local START_Y = isMobile and (SH - PANEL_H) / 2 or (SH - PANEL_H) / 2

-- ── Colours ──────────────────────────────────────────────────────────────────
local C = {
	bg        = Color3.fromRGB(14,14,20),
	surface   = Color3.fromRGB(22,22,32),
	card      = Color3.fromRGB(28,28,42),
	border    = Color3.fromRGB(45,45,70),
	accent    = Color3.fromRGB(90,130,255),
	green     = Color3.fromRGB(0,210,120),
	blue      = Color3.fromRGB(80,160,255),
	red       = Color3.fromRGB(200,60,60),
	yellow    = Color3.fromRGB(220,180,0),
	text      = Color3.fromRGB(220,220,240),
	muted     = Color3.fromRGB(100,100,140),
	white     = Color3.new(1,1,1),
}

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = p
	return c
end
local function stroke(p, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color or C.border
	s.Thickness = thick or 1
	s.Parent = p
	return s
end
local function pad(p, px)
	local u = Instance.new("UIPadding")
	u.PaddingLeft   = UDim.new(0,px)
	u.PaddingRight  = UDim.new(0,px)
	u.PaddingTop    = UDim.new(0,px)
	u.PaddingBottom = UDim.new(0,px)
	u.Parent = p
end
local function tween(obj, props, t, style, dir)
	TweenService:Create(obj,
		TweenInfo.new(t or .18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props):Play()
end
local function clip(text)
	pcall(function()
		if setclipboard then setclipboard(text)
		elseif syn and syn.write_file then syn.write_file("RemoteSpy_Export.txt", text)
		end
	end)
end

-- ── Serialiser ────────────────────────────────────────────────────────────────
local function serialize(v, depth)
	depth = depth or 0
	if depth > 4 then return "..." end
	local t = typeof(v)
	if t=="string"   then return string.format("%q",v) end
	if t=="number"   then return tostring(v) end
	if t=="boolean"  then return tostring(v) end
	if t=="nil"      then return "nil" end
	if t=="Vector3"  then return ("Vector3.new(%g,%g,%g)"):format(v.X,v.Y,v.Z) end
	if t=="Vector2"  then return ("Vector2.new(%g,%g)"):format(v.X,v.Y) end
	if t=="CFrame"   then local p=v.Position return ("CFrame.new(%g,%g,%g)"):format(p.X,p.Y,p.Z) end
	if t=="Color3"   then return ("Color3.fromRGB(%d,%d,%d)"):format(v.R*255,v.G*255,v.B*255) end
	if t=="UDim2"    then return ("UDim2.new(%g,%g,%g,%g)"):format(v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset) end
	if t=="Enum"     then return tostring(v) end
	if t=="Instance" then
		local ok,n = pcall(function() return v:GetFullName() end)
		return ok and ("game:GetService(\""..v.ClassName.."\")") or "Instance(?)"
	end
	if t=="table" then
		if next(v)==nil then return "{}" end
		local parts,i = {},0
		for k,val in pairs(v) do
			i+=1; if i>8 then parts[#parts+1]="..."; break end
			parts[#parts+1] = ("[%s]=%s"):format(tostring(k), serialize(val,depth+1))
		end
		return "{"..table.concat(parts,", ").."}"
	end
	return t.."("..tostring(v)..")"
end

local function formatArgs(args)
	if #args==0 then return "(no args)" end
	local t={}
	for i,v in ipairs(args) do t[#t+1]=("[%d] %s"):format(i,serialize(v)) end
	return table.concat(t,"\n")
end

-- ── Script generator ─────────────────────────────────────────────────────────
local function genScript(remote, args, rtype)
	local path = remote:GetFullName()
	local parts = {}
	for p in path:gmatch("[^%.]+") do
		if p~="game" then parts[#parts+1]=p end
	end
	local expr = "game"
	for _,p in ipairs(parts) do
		expr = expr..string.format(':WaitForChild("%s")',p)
	end

	local stubs={}
	for _,v in ipairs(args) do stubs[#stubs+1]=serialize(v) end

	local lines = {
		"-- [RemoteSpy] Auto-generated script",
		"-- Remote : "..path,
		"-- Type   : "..(rtype or "RemoteEvent"),
		"-- Args   : "..#args,
		"",
		"local remote = "..expr,
		"",
	}
	if rtype=="RemoteFunction" then
		lines[#lines+1] = "local result = remote:InvokeServer("..table.concat(stubs,", ")..")"
		lines[#lines+1] = 'print("[RemoteSpy] Result:", result)'
	else
		lines[#lines+1] = "remote:FireServer("..table.concat(stubs,", ")..")"
	end
	return table.concat(lines,"\n")
end

-- ── State ─────────────────────────────────────────────────────────────────────
local logs        = {}      -- box → {text,rtype,remote,args,count,pinned}
local blacklist   = {}      -- remote path → true
local logCount    = 0
local order       = 0
local paused      = false
local minimized   = false
local savedH

-- ── ScreenGui ─────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "RSpy2"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 999
gui.Parent         = player:WaitForChild("PlayerGui")

-- Main panel
local main = Instance.new("Frame")
main.Size            = UDim2.new(0, PANEL_W, 0, PANEL_H)
main.Position        = UDim2.new(0, START_X, 0, START_Y)
main.BackgroundColor3= C.bg
main.BorderSizePixel = 0
main.ClipsDescendants= true
main.Active          = true
main.Parent          = gui
corner(main, 14)
stroke(main, C.border, 1)

-- Accent top bar
local accentBar = Instance.new("Frame")
accentBar.Size            = UDim2.new(1,0,0,3)
accentBar.BackgroundColor3= C.accent
accentBar.BorderSizePixel = 0
accentBar.ZIndex          = 5
accentBar.Parent          = main

-- ── Header ────────────────────────────────────────────────────────────────────
local header = Instance.new("Frame")
header.Size            = UDim2.new(1,0,0,42)
header.Position        = UDim2.new(0,0,0,3)
header.BackgroundColor3= C.surface
header.BorderSizePixel = 0
header.ZIndex          = 4
header.Parent          = main

local titleLbl = Instance.new("TextLabel")
titleLbl.Size             = UDim2.new(1,-180,1,0)
titleLbl.Position         = UDim2.new(0,14,0,0)
titleLbl.Text             = "⚡ RemoteSpy"
titleLbl.Font             = Enum.Font.GothamBold
titleLbl.TextSize         = 16
titleLbl.TextColor3       = C.text
titleLbl.BackgroundTransparency=1
titleLbl.TextXAlignment   = Enum.TextXAlignment.Left
titleLbl.ZIndex           = 5
titleLbl.Parent           = header

local countLbl = Instance.new("TextLabel")
countLbl.Size             = UDim2.new(0,70,1,0)
countLbl.Position         = UDim2.new(1,-180,0,0)
countLbl.Text             = "0 logs"
countLbl.Font             = Enum.Font.Gotham
countLbl.TextSize         = 12
countLbl.TextColor3       = C.muted
countLbl.BackgroundTransparency=1
countLbl.TextXAlignment   = Enum.TextXAlignment.Right
countLbl.ZIndex           = 5
countLbl.Parent           = header

-- Header buttons helper
local function hBtn(txt, xOff, bg)
	local b = Instance.new("TextButton")
	b.Size            = UDim2.new(0, 30, 0, 26)
	b.Position        = UDim2.new(1, xOff, 0.5, -13)
	b.Text            = txt
	b.Font            = Enum.Font.GothamBold
	b.TextSize        = 13
	b.BackgroundColor3= bg or C.surface
	b.TextColor3      = C.white
	b.BorderSizePixel = 0
	b.ZIndex          = 6
	b.Parent          = header
	corner(b, 6)
	stroke(b, C.border)
	return b
end
local closeBtn = hBtn("✕", -38, C.red)
local minBtn   = hBtn("–", -74)

-- ── Toolbar ───────────────────────────────────────────────────────────────────
local toolbar = Instance.new("Frame")
toolbar.Size            = UDim2.new(1,-16,0,30)
toolbar.Position        = UDim2.new(0,8,0,50)
toolbar.BackgroundTransparency=1
toolbar.ZIndex          = 4
toolbar.Parent          = main

-- Search box
local searchBox = Instance.new("TextBox")
searchBox.Size            = UDim2.new(1,-100,1,0)
searchBox.BackgroundColor3= C.surface
searchBox.BorderSizePixel = 0
searchBox.PlaceholderText = "🔍 Search remotes..."
searchBox.Text            = ""
searchBox.Font            = Enum.Font.Gotham
searchBox.TextSize        = 13
searchBox.TextColor3      = C.text
searchBox.PlaceholderColor3=C.muted
searchBox.ClearTextOnFocus= false
searchBox.ZIndex          = 5
searchBox.Parent          = toolbar
corner(searchBox, 8)
pad(searchBox, 10)
stroke(searchBox, C.border)

-- Pause button
local pauseBtn = Instance.new("TextButton")
pauseBtn.Size            = UDim2.new(0,46,1,0)
pauseBtn.Position        = UDim2.new(1,-98,0,0)
pauseBtn.Text            = "⏸"
pauseBtn.Font            = Enum.Font.GothamBold
pauseBtn.TextSize        = 14
pauseBtn.BackgroundColor3= C.surface
pauseBtn.TextColor3      = C.yellow
pauseBtn.BorderSizePixel = 0
pauseBtn.ZIndex          = 5
pauseBtn.Parent          = toolbar
corner(pauseBtn, 8)
stroke(pauseBtn, C.border)

-- Clear button
local clearBtn = Instance.new("TextButton")
clearBtn.Size            = UDim2.new(0,46,1,0)
clearBtn.Position        = UDim2.new(1,-48,0,0)
clearBtn.Text            = "🗑"
clearBtn.Font            = Enum.Font.GothamBold
clearBtn.TextSize        = 14
clearBtn.BackgroundColor3= C.red
clearBtn.TextColor3      = C.white
clearBtn.BorderSizePixel = 0
clearBtn.ZIndex          = 5
clearBtn.Parent          = toolbar
corner(clearBtn, 8)

-- ── Filter chips ──────────────────────────────────────────────────────────────
local chipRow = Instance.new("Frame")
chipRow.Size            = UDim2.new(1,-16,0,24)
chipRow.Position        = UDim2.new(0,8,0,86)
chipRow.BackgroundTransparency=1
chipRow.ZIndex          = 4
chipRow.Parent          = main

local chipLayout = Instance.new("UIListLayout")
chipLayout.FillDirection= Enum.FillDirection.Horizontal
chipLayout.Padding      = UDim.new(0,6)
chipLayout.Parent       = chipRow

local filterState = {Event=true, ["Function"]=true}

local function chip(label, key, active_color)
	local b = Instance.new("TextButton")
	b.Size            = UDim2.new(0,0,1,0)
	b.AutomaticSize   = Enum.AutomaticSize.X
	b.Text            = label
	b.Font            = Enum.Font.GothamBold
	b.TextSize        = 11
	b.BackgroundColor3= active_color
	b.TextColor3      = C.white
	b.BorderSizePixel = 0
	b.ZIndex          = 5
	b.Parent          = chipRow
	corner(b,12)
	pad(b,8)
	local on = true
	b.MouseButton1Click:Connect(function()
		on = not on
		filterState[key] = on
		b.BackgroundColor3 = on and active_color or C.surface
		b.TextColor3 = on and C.white or C.muted
		applyFilter()
	end)
	return b
end
chip("🟢 Events",    "Event",    C.green)
chip("🔵 Functions", "Function", C.blue)

-- Export all button
local exportBtn = Instance.new("TextButton")
exportBtn.Size            = UDim2.new(0,0,1,0)
exportBtn.AutomaticSize   = Enum.AutomaticSize.X
exportBtn.Text            = "📤 Export"
exportBtn.Font            = Enum.Font.GothamBold
exportBtn.TextSize        = 11
exportBtn.BackgroundColor3= C.surface
exportBtn.TextColor3      = C.text
exportBtn.BorderSizePixel = 0
exportBtn.ZIndex          = 5
exportBtn.Parent          = chipRow
corner(exportBtn,12)
pad(exportBtn,8)
stroke(exportBtn, C.border)

-- ── Scroll area ───────────────────────────────────────────────────────────────
local scroll = Instance.new("ScrollingFrame")
scroll.Size                = UDim2.new(1,-16,1,-122)
scroll.Position            = UDim2.new(0,8,0,116)
scroll.CanvasSize          = UDim2.new()
scroll.ScrollBarThickness  = 4
scroll.ScrollBarImageColor3= C.accent
scroll.BackgroundTransparency=1
scroll.BorderSizePixel     = 0
scroll.ZIndex              = 3
scroll.ElasticBehavior     = Enum.ElasticBehavior.Always
scroll.Parent              = main

local listLayout = Instance.new("UIListLayout")
listLayout.Padding   = UDim.new(0,6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent    = scroll

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0,0,0, listLayout.AbsoluteContentSize.Y + 12)
end)

-- ── Filter logic ─────────────────────────────────────────────────────────────
function applyFilter()
	local q = searchBox.Text:lower()
	for box, data in pairs(logs) do
		local matchSearch = q=="" or data.text:lower():find(q,1,true)
		local matchType   = filterState[data.rtype]
		box.Visible = (matchSearch and matchType) and true or false
	end
end
searchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)

-- ── Update counter ────────────────────────────────────────────────────────────
local function updateCount()
	countLbl.Text = logCount.." log"..(logCount~=1 and "s" or "")
end

-- ── Log entry builder ─────────────────────────────────────────────────────────
local TYPE_COLOR = {
	Event    = C.green,
	["Function"] = C.blue,
}

local function makeBtn(parent, txt, w, bg, yOff)
	local b = Instance.new("TextButton")
	b.Size            = UDim2.new(0,w,0,22)
	b.Position        = UDim2.new(1,-(w+8),0,yOff)
	b.Text            = txt
	b.Font            = Enum.Font.GothamBold
	b.TextSize        = 10
	b.BackgroundColor3= bg
	b.TextColor3      = C.white
	b.BorderSizePixel = 0
	b.ZIndex          = 6
	b.Parent          = parent
	corner(b,5)
	return b
end

local function createLog(remote, args, rtype)
	order -= 1
	logCount += 1
	updateCount()

	local path      = remote:GetFullName()
	local name      = remote.Name
	local argsText  = formatArgs(args)
	local fullText  = path.."\n"..argsText
	local tc        = TYPE_COLOR[rtype] or C.text
	local timestamp = os.date("%H:%M:%S")

	-- Card
	local card = Instance.new("Frame")
	card.Size            = UDim2.new(1,-4,0,0)
	card.AutomaticSize   = Enum.AutomaticSize.Y
	card.BackgroundColor3= C.card
	card.BorderSizePixel = 0
	card.LayoutOrder     = order
	card.ZIndex          = 4
	card.Parent          = scroll
	corner(card, 10)
	stroke(card, C.border)

	-- Left stripe (type colour)
	local stripe = Instance.new("Frame")
	stripe.Size            = UDim2.new(0,3,1,0)
	stripe.BackgroundColor3= tc
	stripe.BorderSizePixel = 0
	stripe.ZIndex          = 5
	stripe.Parent          = card
	makeCorner and corner(stripe,2)

	-- Top row: badge + name + time
	local topRow = Instance.new("Frame")
	topRow.Size            = UDim2.new(1,-90,0,22)
	topRow.Position        = UDim2.new(0,10,0,6)
	topRow.BackgroundTransparency=1
	topRow.ZIndex          = 5
	topRow.Parent          = card

	local badge = Instance.new("TextLabel")
	badge.Size            = UDim2.new(0,70,1,0)
	badge.Text            = rtype=="Function" and "🔵 Func" or "🟢 Event"
	badge.Font            = Enum.Font.GothamBold
	badge.TextSize        = 10
	badge.TextColor3      = tc
	badge.BackgroundColor3= C.surface
	badge.BorderSizePixel = 0
	badge.ZIndex          = 6
	badge.TextXAlignment  = Enum.TextXAlignment.Center
	badge.Parent          = topRow
	corner(badge,4)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size           = UDim2.new(1,-80,1,0)
	nameLbl.Position       = UDim2.new(0,76,0,0)
	nameLbl.Text           = name
	nameLbl.Font           = Enum.Font.GothamBold
	nameLbl.TextSize       = 13
	nameLbl.TextColor3     = C.text
	nameLbl.BackgroundTransparency=1
	nameLbl.ZIndex         = 6
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate   = Enum.TextTruncate.AtEnd
	nameLbl.Parent         = topRow

	local timeLbl = Instance.new("TextLabel")
	timeLbl.Size           = UDim2.new(0,60,1,0)
	timeLbl.Position       = UDim2.new(1,-62,0,0)
	timeLbl.Text           = timestamp
	timeLbl.Font           = Enum.Font.Code
	timeLbl.TextSize       = 10
	timeLbl.TextColor3     = C.muted
	timeLbl.BackgroundTransparency=1
	timeLbl.ZIndex         = 6
	timeLbl.TextXAlignment = Enum.TextXAlignment.Right
	timeLbl.Parent         = card

	-- Path (collapsed by default, expand on tap)
	local pathLbl = Instance.new("TextLabel")
	pathLbl.Size           = UDim2.new(1,-20,0,0)
	pathLbl.Position       = UDim2.new(0,10,0,32)
	pathLbl.AutomaticSize  = Enum.AutomaticSize.Y
	pathLbl.Text           = "📂 "..path
	pathLbl.Font           = Enum.Font.Code
	pathLbl.TextSize       = 10
	pathLbl.TextColor3     = C.muted
	pathLbl.BackgroundTransparency=1
	pathLbl.ZIndex         = 5
	pathLbl.TextXAlignment = Enum.TextXAlignment.Left
	pathLbl.TextWrapped    = true
	pathLbl.Parent         = card

	-- Args text
	local argsLbl = Instance.new("TextLabel")
	argsLbl.Size           = UDim2.new(1,-20,0,0)
	argsLbl.Position       = UDim2.new(0,10,0,52)
	argsLbl.AutomaticSize  = Enum.AutomaticSize.Y
	argsLbl.Text           = argsText
	argsLbl.Font           = Enum.Font.Code
	argsLbl.TextSize       = 12
	argsLbl.TextColor3     = tc
	argsLbl.BackgroundTransparency=1
	argsLbl.ZIndex         = 5
	argsLbl.TextXAlignment = Enum.TextXAlignment.Left
	argsLbl.TextWrapped    = true
	argsLbl.Parent         = card

	-- Bottom padding
	local bot = Instance.new("Frame")
	bot.Size            = UDim2.new(1,0,0,36)
	bot.Position        = UDim2.new(0,0,1,-36)
	bot.BackgroundTransparency=1
	bot.ZIndex          = 4
	bot.Parent          = card

	-- Action buttons (bottom-right)
	local copyBtn   = makeBtn(card,"📋 Copy",   68, C.surface,  -32)
	local scriptBtn = makeBtn(card,"📄 Script",  68, C.accent,  -32)
	local blBtn     = makeBtn(card,"🚫 Block",   68, C.surface,  -32)
	local delBtn    = makeBtn(card,"🗑",          28, C.red,      -32)

	-- Reposition buttons horizontally
	copyBtn.Position   = UDim2.new(1,-218,1,-30)
	scriptBtn.Position = UDim2.new(1,-144,1,-30)
	blBtn.Position     = UDim2.new(1,-70,1,-30)
	delBtn.Position    = UDim2.new(1,-32,1,-30)
	blBtn.Size         = UDim2.new(0,66,0,22)
	copyBtn.Size       = UDim2.new(0,68,0,22)

	-- ─ Button actions ─────────────────────────────────────
	copyBtn.MouseButton1Click:Connect(function()
		clip(fullText)
		copyBtn.Text = "✓ Copied!"
		task.delay(1.5, function()
			if copyBtn.Parent then copyBtn.Text = "📋 Copy" end
		end)
	end)

	scriptBtn.MouseButton1Click:Connect(function()
		local sc = genScript(remote, args, rtype=="Function" and "RemoteFunction" or "RemoteEvent")
		clip(sc)
		scriptBtn.Text = "✓ Copied!"
		task.delay(1.5, function()
			if scriptBtn.Parent then scriptBtn.Text = "📄 Script" end
		end)
	end)

	-- Block: add to blacklist so future fires from this remote are ignored
	blBtn.MouseButton1Click:Connect(function()
		blacklist[path] = not blacklist[path]
		if blacklist[path] then
			blBtn.Text = "✅ Blocked"
			blBtn.BackgroundColor3 = C.red
			card.BackgroundColor3 = Color3.fromRGB(40,20,20)
		else
			blBtn.Text = "🚫 Block"
			blBtn.BackgroundColor3 = C.surface
			card.BackgroundColor3 = C.card
		end
	end)

	delBtn.MouseButton1Click:Connect(function()
		tween(card, {BackgroundTransparency=1}, .15)
		task.delay(.15, function()
			logs[card] = nil
			logCount = math.max(0,logCount-1)
			updateCount()
			card:Destroy()
		end)
	end)

	logs[card] = {text=fullText, rtype=rtype, remote=remote, args=args}
	applyFilter()

	-- Scroll to bottom
	task.defer(function()
		scroll.CanvasPosition = Vector2.new(0, math.huge)
	end)
end

-- ── Toolbar actions ───────────────────────────────────────────────────────────
pauseBtn.MouseButton1Click:Connect(function()
	paused = not paused
	pauseBtn.Text            = paused and "▶" or "⏸"
	pauseBtn.TextColor3      = paused and C.green or C.yellow
	pauseBtn.BackgroundColor3= paused and C.surface or C.surface
end)

clearBtn.MouseButton1Click:Connect(function()
	for box in pairs(logs) do box:Destroy() end
	table.clear(logs)
	logCount = 0
	updateCount()
end)

exportBtn.MouseButton1Click:Connect(function()
	local lines = {"-- RemoteSpy Export | "..os.date("%Y-%m-%d %H:%M:%S"), ""}
	for _, data in pairs(logs) do
		lines[#lines+1] = "-- ["..data.rtype.."]"
		lines[#lines+1] = data.text
		lines[#lines+1] = ""
	end
	clip(table.concat(lines,"\n"))
	exportBtn.Text = "✓ Exported!"
	task.delay(2, function()
		if exportBtn.Parent then exportBtn.Text = "📤 Export" end
	end)
end)

minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		savedH = main.Size.Y.Offset
		tween(main, {Size=UDim2.new(0,PANEL_W,0,48)}, .2)
		toolbar.Visible   = false
		chipRow.Visible   = false
		scroll.Visible    = false
		minBtn.Text       = "+"
	else
		tween(main, {Size=UDim2.new(0,PANEL_W,0,savedH or PANEL_H)}, .2)
		toolbar.Visible   = true
		chipRow.Visible   = true
		scroll.Visible    = true
		minBtn.Text       = "–"
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	tween(main, {BackgroundTransparency=1}, .2)
	task.delay(.2, function() gui:Destroy() end)
end)

-- ── Drag (mouse + touch) ──────────────────────────────────────────────────────
do
	local dragging, startInput, startPos

	local function startDrag(pos)
		dragging  = true
		startInput= pos
		startPos  = main.Position
	end
	local function doDrag(pos)
		if not dragging then return end
		local d = pos - startInput
		local nx = math.clamp(startPos.X.Offset+d.X, 0, SW-main.AbsoluteSize.X)
		local ny = math.clamp(startPos.Y.Offset+d.Y, 0, SH-main.AbsoluteSize.Y)
		main.Position = UDim2.new(0,nx,0,ny)
	end

	header.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
			startDrag(i.Position)
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then
			doDrag(i.Position)
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
			dragging=false
		end
	end)
end

-- ── Remote hooker ─────────────────────────────────────────────────────────────
local hooked = {}

local function hookRemote(obj)
	if hooked[obj] then return end

	if obj:IsA("RemoteEvent") then
		hooked[obj] = true
		obj.OnClientEvent:Connect(function(...)
			local path = pcall(function() return obj:GetFullName() end) and obj:GetFullName() or "?"
			if paused or blacklist[path] then return end
			createLog(obj, {...}, "Event")
		end)

	elseif obj:IsA("RemoteFunction") then
		hooked[obj] = true
		local orig = obj.OnClientInvoke
		obj.OnClientInvoke = function(...)
			local path = pcall(function() return obj:GetFullName() end) and obj:GetFullName() or "?"
			if not paused and not blacklist[path] then
				createLog(obj, {...}, "Function")
			end
			if orig then return orig(...) end
		end
	end
end

for _, d in ipairs(game:GetDescendants()) do pcall(hookRemote, d) end
game.DescendantAdded:Connect(function(d)
	task.wait()
	pcall(hookRemote, d)
end)

-- Keep viewport responsive when screen rotates (mobile)
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	VP=camera.ViewportSize; SW=VP.X; SH=VP.Y
end)

print("[RemoteSpy v2] Ready. Hooked "..#game:GetDescendants().." descendants.")
print("[RemoteSpy v2] 📄 Script button = paste-ready FireServer/InvokeServer script")
print("[RemoteSpy v2] 🚫 Block button  = ignore that remote from now on")
print("[RemoteSpy v2] 📤 Export button = copy ALL logs to clipboard")
