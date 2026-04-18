local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer      = Players.LocalPlayer
local CharactersFolder = Workspace:WaitForChild("Characters")

local State = {
    AutoShoot    = false,
    Range        = 250,
    FireRate     = 0.1,
    AutoReload   = false,
    WallCheck    = true,
    TargetMode   = "Smartest",

    RAAutoReload = false,
    RAMagSize    = 7,
}

local ThreatTier = {
    Brute = 5, Experiment = 5, Exterminator = 5,
    Muscle = 4, Screamer = 4, ["Night Hunter"] = 4, Elemental = 4,
    ["Armored Zombie"] = 3, ["Enforcer Riot"] = 3,
    ["Bloater Acidic"] = 3, ["Blitzer Runner"] = 3,
    Riot = 3, Spitter = 3, Phaser = 3, Hazmat = 3, Bloater = 3,
    Bandit = 3, Rebel = 3, Gunner = 3, Sniper = 3,
    ["Heavy Rebel"] = 3, Butcher = 3,
    Runner = 2, Crawler = 2,
    Zombie = 1, ["Emerald Zombie"] = 1,
}

local SupportedTypes = {}
for name in pairs(ThreatTier) do SupportedTypes[name] = true end

local math_sqrt = math.sqrt
local os_clock  = os.clock

local charParams = RaycastParams.new()
charParams.FilterType = Enum.RaycastFilterType.Exclude

local function rebuildCharParams()
    local excl = {}
    local char = LocalPlayer.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then excl[#excl + 1] = p end
        end
    end
    charParams.FilterDescendantsInstances = excl
end
rebuildCharParams()

local function hasLOS(originPos, model, head)
    local result = Workspace:Raycast(originPos, head.Position - originPos, charParams)
    if not result then return true end
    return result.Instance and result.Instance:IsDescendantOf(model)
end

local function findHead(model)
    local h = model:FindFirstChild("Head")
    if h and h:IsA("BasePart") then return h end
    for _, p in ipairs(model:GetChildren()) do
        if p:IsA("BasePart") and p.Name:lower():find("head") then return p end
    end
    return model:FindFirstChild("HumanoidRootPart")
end

local function findRA()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil, nil end

    local ra = char:FindFirstChild("Remote Arsenal")
    if not ra then return nil, nil, nil, nil end

    local shoot    = ra:FindFirstChild("Shoot",    true)
    local reload   = ra:FindFirstChild("Reload",   true)
    local syncAmmo = ra:FindFirstChild("SyncAmmo", true)

    return ra, shoot, reload, syncAmmo
end

local raSlotTools = {}
local raSlotCount = 0

local function hookSetWeaponsClient(ra)
    if not ra then return end
    local swc = ra:FindFirstChild("SetWeaponsClient", true)
    if not swc then return end
    swc.OnClientEvent:Connect(function(weapons)
        raSlotTools = {}
        raSlotCount = #weapons
        for i, w in ipairs(weapons) do
            if w and w.Tool then
                raSlotTools[i] = w.Tool
            end
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(1)
        local ra = findRA()
        if ra then hookSetWeaponsClient(ra) break end
    end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(2)
    local ra = findRA()
    if ra then hookSetWeaponsClient(ra) end
end)

local function readRAAmmo()
    if #raSlotTools == 0 then return nil end
    local total = 0
    for _, tool in pairs(raSlotTools) do
        local a = tool:GetAttribute("Ammo")
        if a then total = total + a end
    end
    return total
end

local lastRAReloadAt = -999
local raShotCount    = 0

local function doRAReload()
    local now = os_clock()
    if now - lastRAReloadAt < 0.4 then return end
    lastRAReloadAt = now
    raShotCount    = 0

    task.spawn(function()
        local _, _, reload, syncAmmo = findRA()
        local slots = math.max(raSlotCount, 4)

        if syncAmmo then
            for slot = 1, slots do
                pcall(function() syncAmmo:FireServer(slot) end)
            end
            task.wait(0.05)
        end

        if reload then
            for slot = 1, slots do
                pcall(function()
                    local newAmmo = reload:InvokeServer(nil, slot)
                    if newAmmo and raSlotTools[slot] then
                        raSlotTools[slot]:SetAttribute("Ammo", newAmmo)
                    end
                end)
            end
        end
    end)
end

local CachedTool, CachedShoot, CachedReload = nil, nil, nil

local function invalidateWeapon()
    CachedTool, CachedShoot, CachedReload = nil, nil, nil
end

local function resolveWeapon()
    if CachedTool and CachedTool.Parent == LocalPlayer.Character then
        return CachedTool, CachedShoot, CachedReload
    end
    invalidateWeapon()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool.Name ~= "Remote Arsenal" then
            local s = tool:FindFirstChild("Shoot")
            local r = tool:FindFirstChild("Reload")
            if s or r then
                CachedTool, CachedShoot, CachedReload = tool, s, r
                return tool, s, r
            end
        end
    end
    return nil
end

local function onCharAdded(char)
    invalidateWeapon()
    task.defer(rebuildCharParams)
    char.ChildAdded:Connect(function(c)
        if c:IsA("Tool")     then invalidateWeapon() end
        if c:IsA("BasePart") then task.defer(rebuildCharParams) end
    end)
    char.ChildRemoved:Connect(function(c)
        if c == CachedTool   then invalidateWeapon() end
        if c:IsA("BasePart") then task.defer(rebuildCharParams) end
    end)
end
if LocalPlayer.Character then onCharAdded(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(onCharAdded)
LocalPlayer.CharacterRemoving:Connect(invalidateWeapon)

local function getTarget(originPos, rangeSq, wallCheck)
    local best, bestScore = nil, -math.huge
    local smart = State.TargetMode == "Smartest"

    for _, model in ipairs(CharactersFolder:GetChildren()) do
        if SupportedTypes[model.Name] then
            local head = findHead(model)
            if head then
                local hum = model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local d   = head.Position - originPos
                    local dSq = d.X*d.X + d.Y*d.Y + d.Z*d.Z
                    if dSq <= rangeSq then
                        if (not wallCheck) or hasLOS(originPos, model, head) then
                            local score
                            if smart then
                                score = ((ThreatTier[model.Name] or 1) * 1e6)
                                      + hum.Health
                                      - (math_sqrt(dSq) * 2)
                            else
                                score = -dSq
                            end
                            if score > bestScore then
                                best      = { model = model, head = head }
                                bestScore = score
                            end
                        end
                    end
                end
            end
        end
    end

    if best then return best.model, best.head end
    return nil, nil
end

local function fireMainWeapon(shoot, originPos, tChar, tHead)
    local hp = tHead.Position
    pcall(function()
        shoot:FireServer(
            vector.create(originPos.X, originPos.Y, originPos.Z),
            {{
                Target  = vector.create(hp.X, hp.Y, hp.Z),
                HitData = {{
                    HitChar = tChar,
                    HitPos  = vector.create(hp.X, hp.Y, hp.Z),
                    HitPart = tHead,
                }}
            }}
        )
    end)
end

local function fireRemoteArsenal(originPos, tChar, tHead)
    local _, shoot = findRA()
    if not shoot then return end

    local origin = vector.create(originPos.X, originPos.Y, originPos.Z)
    local hp     = tHead.Position
    local hpVec  = vector.create(hp.X, hp.Y, hp.Z)

    for slot = 1, 4 do
        pcall(function()
            shoot:FireServer(
                origin,
                {{
                    Target  = hpVec,
                    HitData = {{
                        HitChar = tChar,
                        HitPos  = hpVec,
                        HitPart = tHead,
                    }}
                }},
                slot
            )
        end)
    end

    raShotCount = raShotCount + 1

    if State.RAAutoReload and raShotCount >= State.RAMagSize then
        doRAReload()
    end
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if not State.RAAutoReload then continue end
        local ammo = readRAAmmo()
        if ammo ~= nil and ammo <= 0 then
            doRAReload()
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.2)
        if not State.RAAutoReload then continue end
        local interval = math.max(0.5, State.RAMagSize * State.FireRate)
        if os_clock() - lastRAReloadAt >= interval then
            doRAReload()
        end
    end
end)

local regReloading  = false
local lastRegReload = 0

local function tryGetAmmo(tool)
    if not tool then return nil end
    local a = tool:GetAttribute("Ammo") or tool:GetAttribute("Mag")
           or tool:GetAttribute("Magazine") or tool:GetAttribute("Bullets")
    if a then return a end
    local v = tool:FindFirstChild("Ammo") or tool:FindFirstChild("Mag") or tool:FindFirstChild("Bullets")
    if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return v.Value end
    return nil
end

local function reloadMainWeapon(reload)
    if regReloading or not reload then return end
    if os_clock() - lastRegReload < 0.25 then return end
    lastRegReload = os_clock()
    regReloading  = true
    task.spawn(function()
        pcall(function() reload:InvokeServer() end)
        task.wait(0.1)
        regReloading = false
    end)
end

task.spawn(function()
    while true do
        task.wait(0.08)
        if not State.AutoReload then continue end
        local tool, _, reload = resolveWeapon()
        if not (tool and reload) then continue end
        local ammo = tryGetAmmo(tool)
        if ammo == nil or ammo <= 0 then reloadMainWeapon(reload) end
    end
end)

local lastMainFire = 0
RunService.Heartbeat:Connect(function()
    if not State.AutoShoot then return end
    local now = os_clock()
    if now - lastMainFire < State.FireRate then return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local tChar, tHead = getTarget(hrp.Position, State.Range ^ 2, State.WallCheck)
    if not (tChar and tHead) then return end

    lastMainFire = now

    local tool, shoot = resolveWeapon()
    if tool and shoot then
        fireMainWeapon(shoot, hrp.Position, tChar, tHead)
    end

    fireRemoteArsenal(hrp.Position, tChar, tHead)
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- FLUENT UI — MOBILE RESPONSIVE
-- ══════════════════════════════════════════════════════════════════════════════
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")

local isMobile   = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local viewport   = workspace.CurrentCamera.ViewportSize
local screenW    = viewport.X
local screenH    = viewport.Y

local winW, winH, tabW
if isMobile then
    winW = math.min(screenW - 20, 360)
    winH = math.min(screenH - 80, 500)
    tabW = 110
else
    winW = 560
    winH = 460
    tabW = 160
end

local Window = Fluent:CreateWindow({
    Title       = "STA Hub",
    SubTitle    = "by Kaizen",
    TabWidth    = tabW,
    Size        = UDim2.fromOffset(winW, winH),
    Acrylic     = not isMobile,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "crosshair" }),
}

local Main = Tabs.Main

Main:AddToggle("RangedAura", {
    Title   = "Ranged Aura",
    Description = "Auto-shoots enemies with your equipped weapon (+ Remote Arsenal if equipped)",
    Default = false,
    Callback = function(v)
        State.AutoShoot = v
        if not v then raShotCount = 0 end
    end,
})

Main:AddToggle("SmartTarget", {
    Title   = "Smart Target",
    Description = "ON = Threat tier + HP first  |  OFF = Closest first",
    Default = true,
    Callback = function(v)
        State.TargetMode = v and "Smartest" or "Closest"
    end,
})

Main:AddSlider("Range", {
    Title       = "Range",
    Description = "Max engagement distance in studs",
    Default     = 250,
    Min         = 10,
    Max         = 500,
    Rounding    = 0,
    Callback    = function(v) State.Range = v end,
})

Main:AddToggle("WallCheck", {
    Title       = "Wall Check (LOS)",
    Description = "Skip enemies blocked by walls",
    Default     = true,
    Callback    = function(v) State.WallCheck = v end,
})

Main:AddSlider("FireRate", {
    Title       = "Fire Rate",
    Description = "Seconds between shots (lower = faster)",
    Default     = 0.1,
    Min         = 0.05,
    Max         = 1.0,
    Rounding    = 2,
    Callback    = function(v) State.FireRate = v end,
})

Main:AddToggle("AutoReload", {
    Title       = "Auto Reload (Main)",
    Description = "Reloads main weapon instantly when ammo hits 0",
    Default     = false,
    Callback    = function(v) State.AutoReload = v end,
})

Main:AddToggle("RAAutoReload", {
    Title       = "RA Auto Reload",
    Description = "Auto-reloads Remote Arsenal when ammo is depleted (only works if RA is equipped)",
    Default     = false,
    Callback    = function(v)
        State.RAAutoReload = v
        if v then
            raShotCount    = 0
            lastRAReloadAt = 0
            task.spawn(function()
                local ra = findRA()
                if ra then hookSetWeaponsClient(ra) end
                doRAReload()
            end)
        end
    end,
})

Main:AddParagraph({
    Title   = "Remote Arsenal Note",
    Content = "RA fires automatically with Ranged Aura — no separate toggle needed.\n"
           .. "RA only fires when the Remote Arsenal tool is EQUIPPED (in your character).\n"
           .. "If RA is in your backpack (not equipped), it will NOT fire.",
})

Main:AddParagraph({
    Title   = "Priority Tiers",
    Content = "T5 Boss: Brute · Experiment · Exterminator\n"
           .. "T4: Muscle · Screamer · Night Hunter · Elemental\n"
           .. "T3 Mutations: Armored Zombie · Enforcer Riot · Bloater Acidic · Blitzer Runner\n"
           .. "T3 Raiders: Bandit · Rebel · Gunner · Sniper · Heavy Rebel · Butcher\n"
           .. "T3 Mid: Riot · Spitter · Phaser · Hazmat · Bloater\n"
           .. "T2: Runner · Crawler  |  T1: Zombie · Emerald Zombie",
})

Window:SelectTab(1)

Fluent:Notify({
    Title    = "STA Hub v12",
    Content  = isMobile and "Mobile mode enabled! Tap the button to toggle UI." or "Loaded! Press Left Ctrl to hide/show.",
    Duration = 6,
})

if isMobile then
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name             = "STAMobileToggle"
    screenGui.ResetOnSpawn     = false
    screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder     = 999
    screenGui.Parent           = game:GetService("CoreGui")

    local btn = Instance.new("TextButton")
    btn.Size            = UDim2.fromOffset(52, 52)
    btn.Position        = UDim2.new(0, 12, 1, -72)
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
    btn.TextColor3      = Color3.fromRGB(255, 255, 255)
    btn.Text            = "STA"
    btn.Font            = Enum.Font.GothamBold
    btn.TextSize        = 13
    btn.BorderSizePixel = 0
    btn.Parent          = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent       = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color     = Color3.fromRGB(100, 100, 220)
    stroke.Thickness = 1.5
    stroke.Parent    = btn

    local isVisible = true
    btn.MouseButton1Click:Connect(function()
        isVisible = not isVisible
        Window:SetVisible(isVisible)
        btn.Text             = isVisible and "STA" or "▶"
        btn.BackgroundColor3 = isVisible
            and Color3.fromRGB(30, 30, 36)
            or  Color3.fromRGB(20, 20, 60)
    end)

    local dragging, dragStart, startPos = false, nil, nil
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = btn.Position
        end
    end)
    btn.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            btn.Position = UDim2.new(
                startPos.X.Scale,
                math.clamp(startPos.X.Offset + delta.X, 0, screenW - 52),
                startPos.Y.Scale,
                math.clamp(startPos.Y.Offset + delta.Y, -screenH + 52, 0)
            )
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end
