local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer      = Players.LocalPlayer
local CharactersFolder = Workspace:WaitForChild("Characters")

local State = {
    AutoShoot       = false,
    Range           = 200,
    FireRate        = 0.1,
    AutoReload      = false,
    WallCheck       = true,   -- ← NEW: skip zombies behind walls
    SmartTarget     = true,   -- ← NEW: prefer visible over closest
}

local SupportedTypes = {
    Zombie  = true,
    Crawler = true,
    Runner  = true,
}

local vector_create   = vector.create
local math_huge       = math.huge
local os_clock        = os.clock

-- ── Weapon cache ──────────────────────────────────────────────────────────────
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

-- ── Line-of-sight check ───────────────────────────────────────────────────────
-- Returns true if there is NO solid wall between originPos and targetPos.
-- We raycast from origin toward target and see if the first thing we hit
-- belongs to the zombie model. If something else (terrain/wall/part) is hit
-- first, the path is blocked → return false.

local function hasLineOfSight(originPos, targetModel, targetHead)
    local targetPos = targetHead.Position

    -- Build a filter that ignores: our own character + the zombie model itself
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local exclude = {}
    -- Exclude player character
    local char = LocalPlayer.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then exclude[#exclude+1] = p end
        end
    end
    -- Exclude the zombie model itself
    for _, p in ipairs(targetModel:GetDescendants()) do
        if p:IsA("BasePart") then exclude[#exclude+1] = p end
    end
    params.FilterDescendantsInstances = exclude

    local direction = targetPos - originPos
    local result    = Workspace:Raycast(originPos, direction, params)

    if result then
        -- Something was hit before the zombie — it's a wall/obstacle
        return false
    end

    -- Nothing blocked → clear shot
    return true
end

-- ── Target finder (wall-aware, smart) ────────────────────────────────────────
-- Priority:
--   1. Alive zombie with clear LOS, sorted by distance (closest first)
--   2. If SmartTarget=false or no visible target exists, falls back
--      to closest regardless of walls (old behaviour) — but WallCheck
--      still hard-blocks if enabled.

local function getClosestTarget(originPos, rangeSq)
    local bestChar, bestHead = nil, nil
    local bestDistSq = math_huge

    -- Collect all candidates with their distance
    local candidates = {}

    for _, model in ipairs(CharactersFolder:GetChildren()) do
        if SupportedTypes[model.Name] then
            local head = model:FindFirstChild("Head")
            if head then
                local hum = model:FindFirstChildOfClass("Humanoid")
                -- Only target alive zombies (health > 0)
                if hum and hum.Health > 0 then
                    local diff  = head.Position - originPos
                    local dSq   = diff.X*diff.X + diff.Y*diff.Y + diff.Z*diff.Z
                    if dSq <= rangeSq then
                        table.insert(candidates, {
                            model = model,
                            head  = head,
                            dSq   = dSq,
                        })
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil, nil end

    -- Sort candidates by distance (closest first)
    table.sort(candidates, function(a, b) return a.dSq < b.dSq end)

    -- If wall check is ON: walk through sorted list, return first with clear LOS
    if State.WallCheck then
        for _, c in ipairs(candidates) do
            if hasLineOfSight(originPos, c.model, c.head) then
                return c.model, c.head
            end
        end
        -- All candidates are wall-blocked → don't fire at all
        return nil, nil
    else
        -- Wall check OFF: just return closest
        local c = candidates[1]
        return c.model, c.head
    end
end

-- ── Fire shot ─────────────────────────────────────────────────────────────────
local function fireShot(shootRemote, originPos, targetChar, targetHead)
    local hitPos = targetHead.Position
    local args = {
        vector_create(originPos.X, originPos.Y, originPos.Z),
        {
            {
                Target  = vector_create(hitPos.X, hitPos.Y, hitPos.Z),
                HitData = {
                    {
                        HitChar = targetChar,
                        HitPos  = vector_create(hitPos.X, hitPos.Y, hitPos.Z),
                        HitPart = targetHead,
                    }
                }
            }
        }
    }
    pcall(function()
        shootRemote:FireServer(unpack(args))
    end)
end

-- ── Ammo helper ───────────────────────────────────────────────────────────────
local function tryGetAmmo(tool)
    if not tool then return nil end
    local a = tool:GetAttribute("Ammo")
            or tool:GetAttribute("Mag")
            or tool:GetAttribute("Magazine")
            or tool:GetAttribute("Bullets")
    if a then return a end
    local v = tool:FindFirstChild("Ammo")
           or tool:FindFirstChild("Mag")
           or tool:FindFirstChild("Bullets")
    if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
        return v.Value
    end
    return nil
end

-- ── Auto reload ───────────────────────────────────────────────────────────────
local Reloading = false
local function doReload(reloadRemote)
    if Reloading or not reloadRemote then return end
    Reloading = true
    task.spawn(function()
        pcall(function()
            reloadRemote:InvokeServer()
        end)
        task.wait(0.15)
        Reloading = false
    end)
end

-- ── Main shoot loop ───────────────────────────────────────────────────────────
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

    local rangeSq = State.Range * State.Range
    local targetChar, targetHead = getClosestTarget(hrp.Position, rangeSq)

    if targetChar and targetHead then
        lastFire = now
        fireShot(shoot, hrp.Position, targetChar, targetHead)
    end
end)

-- ── Auto reload loop ──────────────────────────────────────────────────────────
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

-- ── UI ────────────────────────────────────────────────────────────────────────
local Window = WindUI:CreateWindow({
    Title        = "STA Hub",
    Icon         = "crosshair",
    Author       = "Kaizen",
    Folder       = "STA Hub",
    Size         = UDim2.fromOffset(560, 420),
    Transparent  = true,
    Theme        = "Dark",
    SideBarWidth = 180,
    HasOutline   = true,
})

local Tab = Window:Tab({
    Title = "STA Hub",
    Icon  = "crosshair",
})

Tab:Toggle({
    Title    = "Ranged Aura",
    Desc     = "Auto shoots the closest visible enemy in range",
    Icon     = "target",
    Value    = false,
    Callback = function(v) State.AutoShoot = v end,
})

Tab:Slider({
    Title    = "Range",
    Desc     = "Maximum distance to engage targets (studs)",
    Icon     = "radar",
    Value    = { Min = 10, Max = 200, Default = 200 },
    Step     = 1,
    Callback = function(v) State.Range = tonumber(v) or 200 end,
})

Tab:Slider({
    Title    = "Fire Rate",
    Desc     = "Seconds between server fires (lower = faster)",
    Icon     = "zap",
    Value    = { Min = 0.05, Max = 0.5, Default = 0.1 },
    Step     = 0.01,
    Rounding = 2,
    Callback = function(v) State.FireRate = tonumber(v) or 0.1 end,
})

-- ← NEW toggles
Tab:Toggle({
    Title    = "Wall Check (LOS)",
    Desc     = "Skip zombies blocked by walls — saves ammo",
    Icon     = "shield",
    Value    = true,
    Callback = function(v) State.WallCheck = v end,
})

Tab:Toggle({
    Title    = "Auto Reload",
    Desc     = "Reloads instantly when magazine is empty",
    Icon     = "refresh-cw",
    Value    = false,
    Callback = function(v) State.AutoReload = v end,
})

Tab:Paragraph({
    Title = "How Wall Check works",
    Desc  = "A raycast is fired toward each zombie. If a wall or terrain is hit first, that zombie is skipped and the next closest visible one is targeted instead. No more wasting ammo through walls.",
    Icon  = "info",
})

WindUI:Notify({
    Title    = "STA Hub",
    Content  = "Loaded. Wall Check ON by default — no more shooting through walls!",
    Icon     = "check",
    Duration = 5,
})
