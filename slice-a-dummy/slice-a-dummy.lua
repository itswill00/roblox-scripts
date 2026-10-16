-- NullShight Slice A Dummy! // v0.1.0
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
-- Game-specific remote names live in CONFIG below: fill them from a live
-- mapping run (see README), everything else already works generically.

local CONFIG = {
    -- RemoteEvent/RemoteFunction names, mapped per game update. Find them
    -- with Dex/SimpleSpy while swinging once, then paste here.
    SwingRemote = nil,      -- e.g. "SwingEvent", path from ReplicatedStorage
    RebirthRemote = nil,    -- e.g. "RebirthEvent"
    EggRemote = nil,        -- e.g. "HatchEgg"
    AutoSwing = true,
    SwingDelay = 0.15,      -- seconds between attempts
    AntiAfk = true,
    FpsBoost = false,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

local function note(msg)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "NullShight",
            Text = msg,
            Duration = 4,
        })
    end)
end

-- Anti-AFK: generic, works everywhere.
if CONFIG.AntiAfk then
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- Optional FPS boost for weak phones: kills shadows, water, postfx.
local function fpsBoost()
    local Lighting = game:GetService("Lighting")
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Part") or v:IsA("UnionOperation") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
        elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
            pcall(function() v.Enabled = false end)
        end
    end
end
if CONFIG.FpsBoost then
    pcall(fpsBoost)
end

-- Resolve a remote by dotted path ("Folder.SwingEvent") or bare name.
local function findRemote(path)
    if not path or path == "" then return nil end
    local node = ReplicatedStorage
    for part in string.gmatch(path, "[^%.]+") do
        node = node:FindFirstChild(part)
        if not node then return nil end
    end
    if node:IsA("RemoteEvent") or node:IsA("RemoteFunction") then
        return node
    end
    return nil
end

-- Fallback one: swing by activating the equipped tool. Works in most
-- simulator games even before remotes are mapped.
local function swingTool()
    local char = LocalPlayer.Character
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
        return true
    end
    return false
end

-- Fallback two: click the dummy's ClickDetector if it has one.
local function clickDummy()
    local ok = false
    pcall(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ClickDetector") and d.MaxActivationDistance > 0 then
                local root = LocalPlayer.Character and
                    LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if root and d.Parent and d.Parent:IsA("BasePart") and
                    (d.Parent.Position - root.Position).Magnitude <=
                    math.max(d.MaxActivationDistance, 12) then
                    fireclickdetector(d)
                    ok = true
                end
            end
        end
    end)
    return ok
end

local swingRemote = findRemote(CONFIG.SwingRemote)
if CONFIG.SwingRemote and not swingRemote then
    note("Swing remote not found, using tool/click fallback")
end

note("NullShight Slice loaded. AutoSwing " ..
    (CONFIG.AutoSwing and "ON" or "OFF"))

task.spawn(function()
    while CONFIG.AutoSwing do
        local fired = false
        if swingRemote then
            fired = pcall(function()
                if swingRemote:IsA("RemoteEvent") then
                    swingRemote:FireServer()
                else
                    swingRemote:InvokeServer()
                end
            end)
        end
        if not fired then
            fired = swingTool() or clickDummy()
        end
        task.wait(CONFIG.SwingDelay)
    end
end)

return true
