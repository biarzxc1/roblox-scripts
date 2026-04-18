local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer      = Players.LocalPlayer
local CharactersFolder = Workspace:WaitForChild("Characters")

-- ── State ─────────────────────────────────────────────────────────────────────
local State = {
    AutoShoot   = false,
    Range       = 200,
    FireRate    = 0.1,
    AutoReload  = false,
    WallCheck   = true,
    -- ESP
    ESP         = false,
    ESP_Health  = true,
    ESP_LOS     = true,   -- tint red when wall-blocked
    ESP_MaxDist = 500,    -- only show ESP within this distance
}

local SupportedTypes = {
    Zombie  = true,
    Crawler = true,
    Runner  = true,
}

-- ── Type colours (ESP tint per zombie type) ───────────────────────────────────
local TypeColor = {
    Zombie  = Color3.fromRGB(255, 80,  80),
    Crawler = Color3.fromRGB(255, 170, 50),
    Runner  = Color3.fromRGB(120, 80,  255),
}

local vector_create = vector.create
local math_huge     = math.huge
local os_clock      = os.clock
local sqrt          = math.sqrt
local floor         = math.floor
local clamp         = math.clamp

-- ══════════════════════════════════════════════════════════════════════════════
--   WEAPON CACHE
-- ══════════════════════════════════════════════════════════════════════════════
local CachedTool, CachedShoot, CachedReload = nil, nil, nil

local function invalidateWeapon()
    CachedTool, CachedShoot, CachedReload = nil, nil, nil
end

local function resolveWeapon()
    if CachedTool and CachedTool.Parent and CachedTool.Parent == LocalPlayer.Character then
        return CachedTool, CachedShoot, CachedReload
    end
    invalidateWeapon()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") then
            local shoot  = tool:FindFirstChild("Shoot")
            local reload = tool:FindFirstChild("Reload")
            if shoot or reload then
                CachedTool, CachedShoot, CachedReload = tool, shoot, reload
                return tool, shoot, reload
            end
        end
    end
    return nil
end

local function hookCharacter(char)
    invalidateWeapon()
    if not char then return end
    char.ChildAdded:Connect(function(c)
        if c:IsA("Tool") then invalidateWeapon() end
    end)
    char.ChildRemoved:Connect(function(c)
        if c == CachedTool then invalidateWeapon() end
    end)
end

hookCharacter(LocalPlayer.Character)
LocalPlayer.CharacterAdded:Connect(hookCharacter)
LocalPlayer.CharacterRemoving:Connect(invalidateWeapon)

-- ══════════════════════════════════════════════════════════════════════════════
--   LINE-OF-SIGHT RAYCAST
-- ══════════════════════════════════════════════════════════════════════════════
local function hasLineOfSight(originPos, targetModel, targetHead)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local exclude = {}
    local char = LocalPlayer.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then exclude[#exclude+1] = p end
        end
    end
    for _, p in ipairs(targetModel:GetDescendants()) do
        if p:IsA("BasePart") then exclude[#exclude+1] = p end
    end
    params.FilterDescendantsInstances = exclude

    local direction = targetHead.Position - originPos
    return not Workspace:Raycast(originPos, direction, params)
end

-- ══════════════════════════════════════════════════════════════════════════════
--   TARGET FINDER
-- ══════════════════════════════════════════════════════════════════════════════
local function getClosestTarget(originPos, rangeSq)
    local candidates = {}
    for _, model in ipairs(CharactersFolder:GetChildren()) do
        if SupportedTypes[model.Name] then
            local head = model:FindFirstChild("Head")
            if head then
                local hum = model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local diff = head.Position - originPos
                    local dSq  = diff.X*diff.X + diff.Y*diff.Y + diff.Z*diff.Z
                    if dSq <= rangeSq then
                        table.insert(candidates, { model=model, head=head, dSq=dSq })
                    end
                end
            end
        end
    end
    if #candidates == 0 then return nil, nil end
    table.sort(candidates, function(a,b) return a.dSq < b.dSq end)
    if State.WallCheck then
        for _, c in ipairs(candidates) do
            if hasLineOfSight(originPos, c.model, c.head) then
                return c.model, c.head
            end
        end
        return nil, nil
    else
        return candidates[1].model, candidates[1].head
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
--   FIRE SHOT
-- ══════════════════════════════════════════════════════════════════════════════
local function fireShot(shootRemote, originPos, targetChar, targetHead)
    local hitPos = targetHead.Position
    pcall(function()
        shootRemote:FireServer(
            vector_create(originPos.X, originPos.Y, originPos.Z),
            {{
                Target  = vector_create(hitPos.X, hitPos.Y, hitPos.Z),
                HitData = {{
                    HitChar = targetChar,
                    HitPos  = vector_create(hitPos.X, hitPos.Y, hitPos.Z),
                    HitPart = targetHead,
                }}
            }}
        )
    end)
end

-- ══════════════════════════════════════════════════════════════════════════════
--   AMMO / RELOAD
-- ══════════════════════════════════════════════════════════════════════════════
local function tryGetAmmo(tool)
    if not tool then return nil end
    local a = tool:GetAttribute("Ammo") or tool:GetAttribute("Mag")
           or tool:GetAttribute("Magazine") or tool:GetAttribute("Bullets")
    if a then return a end
    local v = tool:FindFirstChild("Ammo") or tool:FindFirstChild("Mag") or tool:FindFirstChild("Bullets")
    if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return v.Value end
    return nil
end

local Reloading = false
local function doReload(reloadRemote)
    if Reloading or not reloadRemote then return end
    Reloading = true
    task.spawn(function()
        pcall(function() reloadRemote:InvokeServer() end)
        task.wait(0.15)
        Reloading = false
    end)
end

-- ══════════════════════════════════════════════════════════════════════════════
--   ESP SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

local ESPObjects = {}   -- model → { billboard, distLabel, hpBar, hpFill, hpLabel, losLabel }

-- Distance → colour gradient
-- Green (close) → Yellow (mid) → Red (far)
local function distColor(dist, maxDist)
    local t = clamp(dist / maxDist, 0, 1)
    if t < 0.5 then
        -- green → yellow
        local s = t * 2
        return Color3.fromRGB(floor(50 + 205*s), 230, 50)
    else
        -- yellow → red
        local s = (t - 0.5) * 2
        return Color3.fromRGB(255, floor(230 - 180*s), 50)
    end
end

-- Health → colour gradient
local function hpColor(frac)
    if frac > 0.5 then
        local s = (frac - 0.5) * 2
        return Color3.fromRGB(floor(255 - 205*s), 220, 30)
    else
        return Color3.fromRGB(255, floor(220 * frac * 2), 30)
    end
end

local function makeLabel(parent, size, pos, textSize, bold, zindex)
    local l = Instance.new("TextLabel")
    l.Size               = size
    l.Position           = pos
    l.BackgroundTransparency = 1
    l.TextScaled         = false
    l.TextSize           = textSize
    l.Font               = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextColor3         = Color3.new(1,1,1)
    l.TextStrokeColor3   = Color3.new(0,0,0)
    l.TextStrokeTransparency = 0.4
    l.ZIndex             = zindex or 1
    l.Parent             = parent
    return l
end

local function createESPFor(model)
    if ESPObjects[model] then return end
    local head = model:FindFirstChild("Head")
    if not head then return end

    -- BillboardGui attached to the head
    local bb = Instance.new("BillboardGui")
    bb.Name             = "ZombieESP"
    bb.Adornee          = head
    bb.Size             = UDim2.new(0, 130, 0, 68)
    bb.StudsOffset      = Vector3.new(0, 2.8, 0)
    bb.AlwaysOnTop      = true   -- shows through walls
    bb.LightInfluence   = 0
    bb.MaxDistance      = State.ESP_MaxDist
    bb.Parent           = Workspace  -- parent to Workspace so it persists

    -- Background frame (semi-transparent pill)
    local bg = Instance.new("Frame")
    bg.Size                 = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3     = Color3.fromRGB(0, 0, 0)
    bg.BackgroundTransparency = 0.55
    bg.BorderSizePixel      = 0
    bg.Parent               = bb
    local corner = Instance.new("UICorner")
    corner.CornerRadius     = UDim.new(0, 8)
    corner.Parent           = bg

    -- Type colour stripe on left edge
    local stripe = Instance.new("Frame")
    stripe.Size             = UDim2.new(0, 3, 1, 0)
    stripe.BackgroundColor3 = TypeColor[model.Name] or Color3.fromRGB(255,255,255)
    stripe.BorderSizePixel  = 0
    stripe.Parent           = bg
    local sc = Instance.new("UICorner")
    sc.CornerRadius         = UDim.new(0, 4)
    sc.Parent               = stripe

    -- Zombie type name
    local typeLbl = makeLabel(bg,
        UDim2.new(1, -10, 0, 18),
        UDim2.new(0, 8, 0, 4),
        12, true, 2)
    typeLbl.Text            = model.Name
    typeLbl.TextColor3      = TypeColor[model.Name] or Color3.new(1,1,1)
    typeLbl.TextXAlignment  = Enum.TextXAlignment.Left

    -- Distance label (updates each frame)
    local distLbl = makeLabel(bg,
        UDim2.new(1, -10, 0, 16),
        UDim2.new(0, 8, 0, 20),
        11, false, 2)
    distLbl.Text            = "? studs"
    distLbl.TextXAlignment  = Enum.TextXAlignment.Left

    -- LOS indicator dot (🟢 visible / 🔴 blocked)
    local losLbl = makeLabel(bg,
        UDim2.new(0, 20, 0, 16),
        UDim2.new(1, -22, 0, 20),
        11, false, 2)
    losLbl.Text             = "●"
    losLbl.TextColor3       = Color3.fromRGB(0, 220, 80)

    -- Health bar background
    local hpBg = Instance.new("Frame")
    hpBg.Size               = UDim2.new(1, -10, 0, 6)
    hpBg.Position           = UDim2.new(0, 5, 1, -14)
    hpBg.BackgroundColor3   = Color3.fromRGB(40, 40, 40)
    hpBg.BorderSizePixel    = 0
    hpBg.Parent             = bg
    local hbc = Instance.new("UICorner")
    hbc.CornerRadius        = UDim.new(0, 3)
    hbc.Parent              = hpBg

    -- Health bar fill
    local hpFill = Instance.new("Frame")
    hpFill.Size             = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
    hpFill.BorderSizePixel  = 0
    hpFill.Parent           = hpBg
    local hfc = Instance.new("UICorner")
    hfc.CornerRadius        = UDim.new(0, 3)
    hfc.Parent              = hpFill

    -- HP text label (e.g. "85 / 100")
    local hpLbl = makeLabel(bg,
        UDim2.new(1, -10, 0, 12),
        UDim2.new(0, 8, 1, -26),
        9, false, 2)
    hpLbl.Text              = ""
    hpLbl.TextColor3        = Color3.fromRGB(180, 180, 180)
    hpLbl.TextXAlignment    = Enum.TextXAlignment.Left

    ESPObjects[model] = {
        billboard = bb,
        distLbl   = distLbl,
        losLbl    = losLbl,
        hpFill    = hpFill,
        hpLbl     = hpLbl,
        hpBg      = hpBg,
    }

    -- Auto-cleanup when the zombie is removed from game
    model.AncestryChanged:Connect(function()
        if not model:IsDescendantOf(Workspace) then
            pcall(function() bb:Destroy() end)
            ESPObjects[model] = nil
        end
    end)
end

local function removeESPFor(model)
    local esp = ESPObjects[model]
    if esp then
        pcall(function() esp.billboard:Destroy() end)
        ESPObjects[model] = nil
    end
end

local function clearAllESP()
    for model, esp in pairs(ESPObjects) do
        pcall(function() esp.billboard:Destroy() end)
    end
    table.clear(ESPObjects)
end

local function buildAllESP()
    for _, model in ipairs(CharactersFolder:GetChildren()) do
        if SupportedTypes[model.Name] then
            createESPFor(model)
        end
    end
end

-- Watch for new zombies spawning
CharactersFolder.ChildAdded:Connect(function(model)
    if State.ESP and SupportedTypes[model.Name] then
        task.wait()   -- let model fully replicate
        createESPFor(model)
    end
end)

CharactersFolder.ChildRemoved:Connect(function(model)
    removeESPFor(model)
end)

-- ── ESP update loop (RenderStepped = before camera renders, smooth) ───────────
RunService.RenderStepped:Connect(function()
    if not State.ESP then return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local originPos = hrp.Position

    for model, esp in pairs(ESPObjects) do
        -- Safety: model might have been cleaned up
        if not model.Parent then
            pcall(function() esp.billboard:Destroy() end)
            ESPObjects[model] = nil
            continue
        end

        local head = model:FindFirstChild("Head")
        local hum  = model:FindFirstChildOfClass("Humanoid")
        if not head or not hum then continue end

        -- Distance
        local diff = head.Position - originPos
        local dist = sqrt(diff.X*diff.X + diff.Y*diff.Y + diff.Z*diff.Z)
        local distRounded = floor(dist + 0.5)

        esp.distLbl.Text       = distRounded .. " studs"
        esp.distLbl.TextColor3 = distColor(dist, State.ESP_MaxDist)

        -- Visibility / max distance
        esp.billboard.Enabled = (dist <= State.ESP_MaxDist)

        -- Health bar
        if State.ESP_Health then
            esp.hpBg.Visible = true
            local maxHp  = hum.MaxHealth
            local curHp  = hum.Health
            local frac   = (maxHp > 0) and clamp(curHp / maxHp, 0, 1) or 0
            esp.hpFill.Size          = UDim2.new(frac, 0, 1, 0)
            esp.hpFill.BackgroundColor3 = hpColor(frac)
            esp.hpLbl.Text           = floor(curHp) .. " / " .. floor(maxHp)
        else
            esp.hpBg.Visible = false
            esp.hpLbl.Text   = ""
        end

        -- LOS dot (only do raycast if LOS option is on — it costs perf)
        if State.ESP_LOS then
            local visible = hasLineOfSight(originPos, model, head)
            esp.losLbl.Text      = "●"
            esp.losLbl.TextColor3 = visible
                and Color3.fromRGB(0, 230, 90)    -- green = clear shot
                or  Color3.fromRGB(230, 60, 60)   -- red   = wall blocked
        else
            esp.losLbl.Text = ""
        end
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--   MAIN SHOOT LOOP
-- ══════════════════════════════════════════════════════════════════════════════
local lastFire = 0

RunService.Heartbeat:Connect(function()
    if not State.AutoShoot then return end

    local now = os_clock()
    if now - lastFire < State.FireRate then return end

    local tool, shoot, _ = resolveWeapon()
    if not tool or not shoot then return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local targetChar, targetHead = getClosestTarget(hrp.Position, State.Range * State.Range)
    if targetChar and targetHead then
        lastFire = now
        fireShot(shoot, hrp.Position, targetChar, targetHead)
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--   AUTO RELOAD LOOP
-- ══════════════════════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(0.25)
        if State.AutoReload and not Reloading then
            local tool, _, reload = resolveWeapon()
            if tool and reload then
                local ammo = tryGetAmmo(tool)
                if ammo == nil then
                    doReload(reload)
                    task.wait(1.25)
                elseif ammo <= 0 then
                    doReload(reload)
                end
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--   WINDUI
-- ══════════════════════════════════════════════════════════════════════════════
local Window = WindUI:CreateWindow({
    Title        = "STA Hub",
    Icon         = "crosshair",
    Author       = "Kaizen",
    Folder       = "STA Hub",
    Size         = UDim2.fromOffset(560, 480),
    Transparent  = true,
    Theme        = "Dark",
    SideBarWidth = 180,
    HasOutline   = true,
})

-- ── Tab 1: Combat ─────────────────────────────────────────────────────────────
local TabCombat = Window:Tab({ Title = "Combat", Icon = "crosshair" })

TabCombat:Toggle({
    Title    = "Ranged Aura",
    Desc     = "Auto shoots the closest visible enemy in range",
    Icon     = "target",
    Value    = false,
    Callback = function(v) State.AutoShoot = v end,
})

TabCombat:Slider({
    Title    = "Range",
    Desc     = "Maximum distance to engage targets (studs)",
    Icon     = "radar",
    Value    = { Min = 10, Max = 300, Default = 200 },
    Step     = 1,
    Callback = function(v) State.Range = tonumber(v) or 200 end,
})

TabCombat:Slider({
    Title    = "Fire Rate",
    Desc     = "Seconds between shots (lower = faster)",
    Icon     = "zap",
    Value    = { Min = 0.05, Max = 0.5, Default = 0.1 },
    Step     = 0.01,
    Rounding = 2,
    Callback = function(v) State.FireRate = tonumber(v) or 0.1 end,
})

TabCombat:Toggle({
    Title    = "Wall Check (LOS)",
    Desc     = "Skip zombies blocked by walls — saves ammo",
    Icon     = "shield",
    Value    = true,
    Callback = function(v) State.WallCheck = v end,
})

TabCombat:Toggle({
    Title    = "Auto Reload",
    Desc     = "Reloads instantly when magazine hits 0",
    Icon     = "refresh-cw",
    Value    = false,
    Callback = function(v) State.AutoReload = v end,
})

-- ── Tab 2: ESP ────────────────────────────────────────────────────────────────
local TabESP = Window:Tab({ Title = "ESP", Icon = "eye" })

TabESP:Toggle({
    Title    = "Enable ESP",
    Desc     = "Show zombie overlays with distance & health",
    Icon     = "eye",
    Value    = false,
    Callback = function(v)
        State.ESP = v
        if v then
            buildAllESP()
        else
            clearAllESP()
        end
    end,
})

TabESP:Toggle({
    Title    = "Health Bar",
    Desc     = "Show HP bar and current / max health",
    Icon     = "heart",
    Value    = true,
    Callback = function(v) State.ESP_Health = v end,
})

TabESP:Toggle({
    Title    = "LOS Indicator",
    Desc     = "🟢 = clear shot  🔴 = wall blocked",
    Icon     = "radio",
    Value    = true,
    Callback = function(v) State.ESP_LOS = v end,
})

TabESP:Slider({
    Title    = "Max Render Distance",
    Desc     = "Hide ESP labels beyond this distance (studs)",
    Icon     = "maximize",
    Value    = { Min = 50, Max = 1000, Default = 500 },
    Step     = 10,
    Callback = function(v)
        State.ESP_MaxDist = tonumber(v) or 500
        -- Update all existing billboard max distances
        for _, esp in pairs(ESPObjects) do
            esp.billboard.MaxDistance = State.ESP_MaxDist
        end
    end,
})

TabESP:Paragraph({
    Title = "ESP Colour Guide",
    Desc  = "Distance label: Green = close  |  Yellow = medium  |  Red = far\n"
          .."Type stripe:  Red = Zombie  |  Orange = Crawler  |  Purple = Runner\n"
          .."LOS dot:  🟢 clear line of sight  |  🔴 blocked by wall",
    Icon  = "info",
})

-- ── Notification ──────────────────────────────────────────────────────────────
WindUI:Notify({
    Title    = "STA Hub",
    Content  = "Loaded! Enable ESP in the ESP tab to see zombie distances.",
    Icon     = "check",
    Duration = 5,
})
