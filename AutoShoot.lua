local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer      = Players.LocalPlayer
local CharactersFolder = Workspace:WaitForChild("Characters")

-- ══════════════════════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════════════════════
local State = {
    AutoShoot    = false,
    Range        = 250,
    FireRate     = 0.1,
    AutoReload   = false,
    WallCheck    = true,
    TargetMode   = "Smartest",

    -- RA shares AutoShoot / Range / WallCheck / FireRate from above
    RAAutoReload = false,
    RAMagSize    = 7,
}

-- ══════════════════════════════════════════════════════════════════════════════
-- THREAT TIERS
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- LOS RAYCAST
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- HEAD FINDER — robust, all zombie types
-- ══════════════════════════════════════════════════════════════════════════════
local function findHead(model)
    local h = model:FindFirstChild("Head")
    if h and h:IsA("BasePart") then return h end
    for _, p in ipairs(model:GetChildren()) do
        if p:IsA("BasePart") and p.Name:lower():find("head") then return p end
    end
    return model:FindFirstChild("HumanoidRootPart")
end

-- ══════════════════════════════════════════════════════════════════════════════
-- REMOTE ARSENAL FINDER
-- *** FIX: Only checks Character (equipped). Backpack = not equipped = skip. ***
-- ══════════════════════════════════════════════════════════════════════════════
local function findRA()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil, nil end

    -- MUST be equipped in character, NOT in backpack
    local ra = char:FindFirstChild("Remote Arsenal")
    if not ra then return nil, nil, nil, nil end

    local shoot    = ra:FindFirstChild("Shoot",    true)
    local reload   = ra:FindFirstChild("Reload",   true)
    local syncAmmo = ra:FindFirstChild("SyncAmmo", true)

    return ra, shoot, reload, syncAmmo
end

-- ══════════════════════════════════════════════════════════════════════════════
-- RA SLOT TOOL TRACKING
-- ══════════════════════════════════════════════════════════════════════════════
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

-- Hook immediately if RA is already equipped, else wait for equip
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

-- ══════════════════════════════════════════════════════════════════════════════
-- RA AMMO READER
-- ══════════════════════════════════════════════════════════════════════════════
local function readRAAmmo()
    if #raSlotTools == 0 then return nil end
    local total = 0
    for _, tool in pairs(raSlotTools) do
        local a = tool:GetAttribute("Ammo")
        if a then total = total + a end
    end
    return total
end

-- ══════════════════════════════════════════════════════════════════════════════
-- RA RELOAD
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- REGULAR WEAPON FINDER
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- TARGET FINDER
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- MAIN WEAPON FIRE
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- REMOTE ARSENAL FIRE
-- ══════════════════════════════════════════════════════════════════════════════
local function fireRemoteArsenal(originPos, tChar, tHead)
    local _, shoot = findRA()
    if not shoot then return end   -- RA not equipped → skip silently

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

-- ══════════════════════════════════════════════════════════════════════════════
-- RA AUTO-RELOAD: REAL AMMO DETECTION LOOP
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- RA AUTO-RELOAD: TIMED FALLBACK LOOP
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- MAIN WEAPON AUTO-RELOAD
-- ══════════════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════════════
-- COMBINED SHOOT LOOP
-- Ranged Aura fires main weapon + RA (if equipped) at the same target.
-- RA only fires if findRA() returns a shoot remote (i.e. equipped in character).
-- ══════════════════════════════════════════════════════════════════════════════
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

    -- Fire main weapon (if equipped)
    local tool, shoot = resolveWeapon()
    if tool and shoot then
        fireMainWeapon(shoot, hrp.Position, tChar, tHead)
    end

    -- Fire Remote Arsenal (only if equipped in character)
    fireRemoteArsenal(hrp.Position, tChar, tHead)
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- UI — single Main tab, no separate Remote Arsenal tab
-- ══════════════════════════════════════════════════════════════════════════════
local Window = WindUI:CreateWindow({
    Title        = "STA Hub",
    Icon         = "crosshair",
    Author       = "Kaizen",
    Folder       = "STA Hub",
    Size         = UDim2.fromOffset(560, 500),
    Transparent  = true,
    Theme        = "Dark",
    SideBarWidth = 180,
    HasOutline   = true,
})

local Main = Window:Tab({ Title = "Main", Icon = "crosshair" })

Main:Toggle({
    Title = "Ranged Aura", Icon = "target",
    Desc  = "Auto-shoots enemies with your equipped weapon (+ Remote Arsenal if equipped)",
    Value = false,
    Callback = function(v)
        State.AutoShoot = v
        if not v then raShotCount = 0 end
    end,
})
Main:Toggle({
    Title = "Smart Target", Icon = "cpu",
    Desc  = "ON = Threat tier + HP first  |  OFF = Closest first",
    Value = true,
    Callback = function(v) State.TargetMode = v and "Smartest" or "Closest" end,
})
Main:Slider({
    Title = "Range", Icon = "radar",
    Desc  = "Max engagement distance in studs (applies to both main weapon and Remote Arsenal)",
    Value = { Min = 10, Max = 500, Default = 250 }, Step = 1,
    Callback = function(v) State.Range = tonumber(v) or 250 end,
})
Main:Toggle({
    Title = "Wall Check (LOS)", Icon = "shield",
    Desc  = "Skip enemies blocked by walls (applies to both main weapon and Remote Arsenal)",
    Value = true,
    Callback = function(v) State.WallCheck = v end,
})
Main:Slider({
    Title = "Fire Rate", Icon = "zap",
    Desc  = "Seconds between shots (applies to both main weapon and Remote Arsenal)",
    Value = { Min = 0.05, Max = 1.0, Default = 0.1 }, Step = 0.05,
    Callback = function(v) State.FireRate = tonumber(v) or 0.1 end,
})
Main:Toggle({
    Title = "Auto Reload (Main)", Icon = "refresh-cw",
    Desc  = "Reloads main weapon instantly when ammo hits 0",
    Value = false,
    Callback = function(v) State.AutoReload = v end,
})
Main:Toggle({
    Title = "RA Auto Reload", Icon = "refresh-cw",
    Desc  = "Auto-reloads Remote Arsenal when ammo is depleted (only works if RA is equipped)",
    Value = false,
    Callback = function(v)
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
Main:Slider({
    Title = "RA Mag Size", Icon = "layers",
    Desc  = "Remote Arsenal pistol mag size — used for shot-count reload trigger (default: 7)",
    Value = { Min = 1, Max = 30, Default = 7 }, Step = 1,
    Callback = function(v)
        State.RAMagSize = tonumber(v) or 7
        raShotCount     = 0
    end,
})
Main:Paragraph({
    Title = "Remote Arsenal Note", Icon = "info",
    Desc  = "RA fires automatically with Ranged Aura — no separate toggle needed.\n"
         .. "RA only fires when the Remote Arsenal tool is EQUIPPED (in your character).\n"
         .. "If RA is in your backpack (not equipped), it will NOT fire.",
})
Main:Paragraph({
    Title = "Priority Tiers", Icon = "info",
    Desc  = "T5 Boss: Brute · Experiment · Exterminator\n"
         .. "T4: Muscle · Screamer · Night Hunter · Elemental\n"
         .. "T3 Mutations: Armored Zombie · Enforcer Riot · Bloater Acidic · Blitzer Runner\n"
         .. "T3 Raiders: Bandit · Rebel · Gunner · Sniper · Heavy Rebel · Butcher\n"
         .. "T3 Mid: Riot · Spitter · Phaser · Hazmat · Bloater\n"
         .. "T2: Runner · Crawler  |  T1: Zombie · Emerald Zombie",
})

WindUI:Notify({
    Title    = "STA Hub v12",
    Content  = "RA merged into Ranged Aura — equip check fixed!",
    Icon     = "zap",
    Duration = 6,
})
