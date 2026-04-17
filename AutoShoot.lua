local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer      = Players.LocalPlayer
local CharactersFolder = Workspace:WaitForChild("Characters")

local State = {
    AutoShoot   = false,
    Range       = 200,
    FireRate    = 0.1,
    AutoReload  = false,
}

local SupportedTypes = {
    Zombie  = true,
    Crawler = true,
    Runner  = true,
}

local vector_create   = vector.create
local table_insert    = table.insert
local math_huge       = math.huge
local os_clock        = os.clock

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

local function getClosestTarget(originPos, rangeSq)
    local closestChar, closestHead, closestDistSq = nil, nil, math_huge

    for _, model in ipairs(CharactersFolder:GetChildren()) do
        if SupportedTypes[model.Name] then
            local head = model:FindFirstChild("Head")
            if head then
                local hum = model:FindFirstChildOfClass("Humanoid")
                if not hum or hum.Health > 0 then
                    local diff = head.Position - originPos
                    local dSq = diff.X*diff.X + diff.Y*diff.Y + diff.Z*diff.Z
                    if dSq <= rangeSq and dSq < closestDistSq then
                        closestDistSq = dSq
                        closestChar   = model
                        closestHead   = head
                    end
                end
            end
        end
    end

    return closestChar, closestHead
end

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

local Window = WindUI:CreateWindow({
    Title        = "STA Hub",
    Icon         = "crosshair",
    Author       = "Kaizen",
    Folder       = "STA Hub",
    Size         = UDim2.fromOffset(560, 380),
    Transparent  = true,
    Theme        = "Dark",
    SideBarWidth = 180,
    HasOutline   = true,
})

local TabRanged = Window:Tab({
    Title = "STA Hub",
    Icon  = "crosshair",
})

TabRanged:Toggle({
    Title    = "Ranged Aura",
    Desc     = "Auto shoots the closest supported enemy in range",
    Icon     = "target",
    Value    = false,
    Callback = function(v) State.AutoShoot = v end,
})

TabRanged:Slider({
    Title    = "Range",
    Desc     = "Maximum distance to engage targets",
    Icon     = "radar",
    Value    = { Min = 10, Max = 200, Default = 200 },
    Step     = 1,
    Callback = function(v) State.Range = tonumber(v) or 200 end,
})

TabRanged:Slider({
    Title    = "Fire Rate",
    Desc     = "Seconds between server fires",
    Icon     = "zap",
    Value    = { Min = 0.1, Max = 0.5, Default = 0.1 },
    Step     = 0.01,
    Rounding = 2,
    Callback = function(v) State.FireRate = tonumber(v) or 0.1 end,
})

TabRanged:Paragraph({
    Title = "Note",
    Desc  = "Fire Rate - the rate at which events are sent to the server",
    Icon  = "info",
})

TabRanged:Toggle({
    Title    = "Auto Reload",
    Desc     = "Syncs ammo and reloads instantly when empty",
    Icon     = "refresh-cw",
    Value    = false,
    Callback = function(v) State.AutoReload = v end,
})

WindUI:Notify({
    Title    = "Ranged Hub",
    Content  = "Loaded. Supported targets: Zombie, Crawler, Runner.",
    Icon     = "check",
    Duration = 5,
})
