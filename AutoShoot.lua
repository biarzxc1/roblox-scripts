-- ================================================================
-- Auto Shoot Zombie Script (WindUI)
-- Based on RemoteSpy captured remotes:
--   * Character.Torso.AimRotate.ReplicateAim:FireServer(aimValue)
--   * Character[Weapon].Shoot:FireServer(originPos, hitDataTable)
--
-- Features:
--   * Auto Shoot Zombies (workspace.Characters)
--   * Range/Aura slider (studs)
--   * Fire Rate slider (shots per second)
--   * Target Part selector (Head / Torso / HumanoidRootPart)
--   * Wallbang toggle (ignore line-of-sight)
--   * Prioritize closest / lowest HP
--   * Auto detect equipped weapon
--   * Visual range circle (optional)
-- ================================================================

-- ---------- LOAD WINDUI ----------
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- ---------- SERVICES ----------
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")

local LocalPlayer  = Players.LocalPlayer

-- ---------- STATE ----------
local State = {
    AutoShoot      = false,
    Range          = 500,
    FireRate       = 15,       -- shots per second
    TargetPart     = "Head",   -- Head / Torso / HumanoidRootPart
    Priority       = "Closest",-- Closest / LowestHP
    Wallbang       = true,
    ShowRange      = false,
    SilentAim      = true,     -- fires ReplicateAim for minimal aim value
}

-- ---------- HELPERS ----------
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getRoot()
    local char = getCharacter()
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end

local function getEquippedWeapon()
    local char = getCharacter()
    if not char then return nil end
    -- Scan character for a child with a "Shoot" RemoteEvent
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Model") or child:IsA("Tool") or child:IsA("Folder") then
            local shoot = child:FindFirstChild("Shoot")
            if shoot and shoot:IsA("RemoteEvent") then
                return child, shoot
            end
        end
    end
    return nil, nil
end

local function getAimRemote()
    local char = getCharacter()
    if not char then return nil end
    local torso = char:FindFirstChild("Torso")
    if not torso then return nil end
    local aimRotate = torso:FindFirstChild("AimRotate")
    if not aimRotate then return nil end
    return aimRotate:FindFirstChild("ReplicateAim")
end

local function getZombiesFolder()
    return Workspace:FindFirstChild("Characters")
end

local function isAlive(zombie)
    if not zombie or not zombie.Parent then return false end
    local hum = zombie:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return false end
    -- Some zombie models may not have Humanoid, fallback to Head existence
    return zombie:FindFirstChild("Head") ~= nil
end

local function hasLineOfSight(fromPos, targetPart)
    if State.Wallbang then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { getCharacter() }
    local dir = (targetPart.Position - fromPos)
    local result = Workspace:Raycast(fromPos, dir, params)
    if not result then return true end
    -- Make sure the hit is within the target model
    return result.Instance and result.Instance:IsDescendantOf(targetPart.Parent)
end

local function getTargetPart(zombie)
    local part = zombie:FindFirstChild(State.TargetPart)
    if part then return part end
    -- Fallback chain
    return zombie:FindFirstChild("Head")
        or zombie:FindFirstChild("Torso")
        or zombie:FindFirstChild("HumanoidRootPart")
        or zombie.PrimaryPart
end

local function findBestTarget()
    local folder = getZombiesFolder()
    if not folder then return nil end
    local root = getRoot()
    if not root then return nil end
    local originPos = root.Position

    local best, bestScore
    for _, zombie in ipairs(folder:GetChildren()) do
        if isAlive(zombie) then
            local part = getTargetPart(zombie)
            if part then
                local dist = (part.Position - originPos).Magnitude
                if dist <= State.Range and hasLineOfSight(originPos, part) then
                    local score
                    if State.Priority == "LowestHP" then
                        local hum = zombie:FindFirstChildOfClass("Humanoid")
                        score = hum and hum.Health or dist
                    else
                        score = dist
                    end
                    if not bestScore or score < bestScore then
                        best, bestScore = zombie, score
                    end
                end
            end
        end
    end
    return best
end

-- ---------- SHOOT LOGIC ----------
local function fireAim()
    if not State.SilentAim then return end
    local aimRemote = getAimRemote()
    if aimRemote then
        pcall(function()
            aimRemote:FireServer(0.02490769699215889)
        end)
    end
end

local function fireShot(zombie)
    local weapon, shootRemote = getEquippedWeapon()
    if not weapon or not shootRemote then return false end
    local root = getRoot()
    if not root then return false end
    local targetPart = getTargetPart(zombie)
    if not targetPart then return false end

    local originPos = root.Position
    local hitPos    = targetPart.Position

    local args = {
        originPos,
        {
            {
                Target = hitPos,
                HitData = {
                    {
                        HitChar = zombie,
                        HitPos  = hitPos,
                        HitPart = targetPart,
                    },
                },
            },
        },
    }

    local ok = pcall(function()
        shootRemote:FireServer(unpack(args))
    end)
    return ok
end

-- ---------- LOOP ----------
local lastShot = 0
RunService.Heartbeat:Connect(function()
    if not State.AutoShoot then return end
    local now = tick()
    local interval = 1 / math.max(State.FireRate, 0.1)
    if now - lastShot < interval then return end

    local target = findBestTarget()
    if target then
        fireAim()
        if fireShot(target) then
            lastShot = now
        end
    end
end)

-- ---------- RANGE VISUAL ----------
local rangePart
local function updateRangeVisual()
    if State.ShowRange then
        if not rangePart then
            rangePart = Instance.new("Part")
            rangePart.Name = "AutoShootRange"
            rangePart.Shape = Enum.PartType.Ball
            rangePart.Material = Enum.Material.ForceField
            rangePart.Color = Color3.fromRGB(0, 170, 255)
            rangePart.Transparency = 0.85
            rangePart.CanCollide = false
            rangePart.CanQuery = false
            rangePart.CanTouch = false
            rangePart.Anchored = true
            rangePart.Parent = Workspace
        end
        rangePart.Size = Vector3.new(State.Range * 2, State.Range * 2, State.Range * 2)
    else
        if rangePart then
            rangePart:Destroy()
            rangePart = nil
        end
    end
end

RunService.RenderStepped:Connect(function()
    if rangePart then
        local root = getRoot()
        if root then
            rangePart.CFrame = CFrame.new(root.Position)
        end
    end
end)

-- ================================================================
-- WINDUI INTERFACE
-- ================================================================

local Window = WindUI:CreateWindow({
    Title  = "Zombie Hub",
    Icon   = "crosshair",
    Author = "Auto Shoot v1.0",
    Folder = "ZombieHub",
    Size   = UDim2.fromOffset(560, 420),
    Theme  = "Dark",
    Resizable  = true,
    ToggleKey  = Enum.KeyCode.RightShift,
    SideBarWidth = 180,
})

-- ---------- MAIN TAB ----------
local MainTab = Window:Tab({
    Title = "Combat",
    Icon  = "target",
})

local CombatSection = MainTab:Section({
    Title = "Auto Shoot",
    TextSize = 17,
})

MainTab:Toggle({
    Title = "Auto Shoot Zombies",
    Desc  = "Automatically shoots zombies within range",
    Value = false,
    Callback = function(state)
        State.AutoShoot = state
    end,
})

MainTab:Toggle({
    Title = "Silent Aim",
    Desc  = "Fires ReplicateAim to bypass aim checks",
    Value = true,
    Callback = function(state)
        State.SilentAim = state
    end,
})

MainTab:Toggle({
    Title = "Wallbang",
    Desc  = "Ignore walls / line-of-sight",
    Value = true,
    Callback = function(state)
        State.Wallbang = state
    end,
})

MainTab:Slider({
    Title = "Range (Aura)",
    Desc  = "Maximum distance in studs",
    Step  = 5,
    Value = { Min = 20, Max = 2000, Default = 500 },
    Callback = function(value)
        State.Range = value
        if rangePart then
            rangePart.Size = Vector3.new(value * 2, value * 2, value * 2)
        end
    end,
})

MainTab:Slider({
    Title = "Fire Rate",
    Desc  = "Shots per second",
    Step  = 1,
    Value = { Min = 1, Max = 60, Default = 15 },
    Callback = function(value)
        State.FireRate = value
    end,
})

MainTab:Dropdown({
    Title = "Target Part",
    Desc  = "Preferred body part to hit",
    Values = { "Head", "Torso", "HumanoidRootPart" },
    Value  = "Head",
    Callback = function(value)
        State.TargetPart = value
    end,
})

MainTab:Dropdown({
    Title = "Target Priority",
    Desc  = "How to choose among zombies in range",
    Values = { "Closest", "LowestHP" },
    Value  = "Closest",
    Callback = function(value)
        State.Priority = value
    end,
})

-- ---------- VISUALS TAB ----------
local VisualTab = Window:Tab({
    Title = "Visuals",
    Icon  = "eye",
})

VisualTab:Toggle({
    Title = "Show Range Sphere",
    Desc  = "Displays a sphere showing aura range",
    Value = false,
    Callback = function(state)
        State.ShowRange = state
        updateRangeVisual()
    end,
})

VisualTab:Button({
    Title = "Highlight Zombies",
    Desc  = "Add highlight to all zombies in workspace.Characters",
    Callback = function()
        local folder = getZombiesFolder()
        if not folder then return end
        for _, zombie in ipairs(folder:GetChildren()) do
            if zombie:IsA("Model") and not zombie:FindFirstChild("AutoShootHL") then
                local hl = Instance.new("Highlight")
                hl.Name = "AutoShootHL"
                hl.FillColor = Color3.fromRGB(255, 60, 60)
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl.FillTransparency = 0.6
                hl.Parent = zombie
            end
        end
    end,
})

VisualTab:Button({
    Title = "Remove Highlights",
    Callback = function()
        local folder = getZombiesFolder()
        if not folder then return end
        for _, zombie in ipairs(folder:GetChildren()) do
            local hl = zombie:FindFirstChild("AutoShootHL")
            if hl then hl:Destroy() end
        end
    end,
})

-- ---------- INFO TAB ----------
local InfoTab = Window:Tab({
    Title = "Info",
    Icon  = "info",
})

InfoTab:Paragraph({
    Title = "How it works",
    Desc  = "Fires the same remotes captured by RemoteSpy:\n"
         .. "1) Character.Torso.AimRotate.ReplicateAim\n"
         .. "2) Character[Weapon].Shoot\n\n"
         .. "Make sure a weapon (e.g. AK-47) is equipped.",
})

InfoTab:Paragraph({
    Title = "Toggle UI",
    Desc  = "Press RightShift to show/hide this window.",
})

InfoTab:Button({
    Title = "Debug: Print Equipped Weapon",
    Callback = function()
        local weapon = getEquippedWeapon()
        if weapon then
            WindUI:Notify({
                Title = "Weapon Found",
                Content = weapon.Name,
                Duration = 4,
            })
        else
            WindUI:Notify({
                Title = "No Weapon",
                Content = "Equip a weapon first.",
                Duration = 4,
            })
        end
    end,
})

InfoTab:Button({
    Title = "Debug: Count Zombies",
    Callback = function()
        local folder = getZombiesFolder()
        local count = 0
        if folder then
            for _, z in ipairs(folder:GetChildren()) do
                if isAlive(z) then count = count + 1 end
            end
        end
        WindUI:Notify({
            Title = "Zombies Alive",
            Content = tostring(count),
            Duration = 4,
        })
    end,
})

MainTab:Select()

WindUI:Notify({
    Title = "Zombie Hub Loaded",
    Content = "Press RightShift to toggle UI",
    Duration = 5,
})
