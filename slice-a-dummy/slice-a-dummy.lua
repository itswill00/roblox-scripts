-- NullShight Slice A Dummy! // v0.2.0
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
-- Game-specific remote names live in CONFIG below: fill them from a live
-- mapping run (see README), everything else already works generically.

local CONFIG = {
    -- RemoteEvent/RemoteFunction names, mapped per game update. Find them
    -- with Dex/SimpleSpy while swinging once, then paste here.
    SwingRemote = "SlashRemotes.SlashRequest", -- mapped 2026-10-16
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

-- SlashRequest mapped 2026-10-16: FireServer(dummyModel, 2).
-- SlashFinished mapped 2026-10-16: FireServer(true, 2).
-- The dummy model is resolved live; trailing args sent as observed.
local slashPower = 2
local swingRemote = findRemote(CONFIG.SwingRemote)
local finishRemote = findRemote("SlashRemotes.SlashFinished")
if CONFIG.SwingRemote and not swingRemote then
    note("Swing remote not found, using tool/click fallback")
end
local function fireSlash()
    if not swingRemote then return false end
    local folder = workspace:FindFirstChild("DummyFolder")
    if not folder then return false end
    local dummy = folder:FindFirstChild("DummyModel") or
        folder:FindFirstChildOfClass("Model")
    if not dummy then return false end
    local ok = pcall(function()
        if swingRemote:IsA("RemoteEvent") then
            swingRemote:FireServer(dummy, slashPower)
        else
            swingRemote:InvokeServer(dummy, slashPower)
        end
    end)
    if ok and finishRemote then
        pcall(function()
            if finishRemote:IsA("RemoteEvent") then
                finishRemote:FireServer(true, slashPower)
            else
                finishRemote:InvokeServer(true, slashPower)
            end
        end)
    end
    return ok
end

local state = {
    autoSwing = CONFIG.AutoSwing,
}

note("NullShight Slice loaded. AutoSwing " ..
    (state.autoSwing and "ON" or "OFF"))

task.spawn(function()
    while true do
        if state.autoSwing then
            local fired = fireSlash()
            if not fired then
                fired = swingTool() or clickDummy()
            end
        end
        task.wait(CONFIG.SwingDelay)
    end
end)

-- Monochrome compact panel. Touch-first: big tap targets, draggable
-- title bar, collapsible to a pill. No external UI libs needed.
local function buildUI()
    local parent = nil
    pcall(function()
        parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not parent then return false end

    local gui = Instance.new("ScreenGui")
    gui.Name = "NullShightSlice"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local main = Instance.new("Frame")
    main.Name = "Panel"
    main.Size = UDim2.new(0, 230, 0, 196)
    main.Position = UDim2.new(0, 16, 0, 120)
    main.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
    main.BorderColor3 = Color3.fromRGB(120, 120, 128)
    main.BorderSizePixel = 1
    main.Active = true
    main.Parent = gui

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -34, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(235, 235, 240)
    title.Text = "  NULLSHIGHT // SLICE"
    title.Parent = main

    local mini = Instance.new("TextButton")
    mini.Size = UDim2.new(0, 30, 0, 30)
    mini.Position = UDim2.new(1, -30, 0, 0)
    mini.BackgroundTransparency = 1
    mini.Font = Enum.Font.Code
    mini.TextSize = 14
    mini.TextColor3 = Color3.fromRGB(160, 160, 170)
    mini.Text = "_"
    mini.Parent = main

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Size = UDim2.new(1, 0, 1, -30)
    body.Position = UDim2.new(0, 0, 0, 30)
    body.BackgroundTransparency = 1
    body.Parent = main

    local collapsed = false
    mini.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        body.Visible = not collapsed
        main.Size = collapsed and UDim2.new(0, 230, 0, 30)
            or UDim2.new(0, 230, 0, 196)
        mini.Text = collapsed and "+" or "_"
    end)

    -- drag by the title bar, mouse or touch
    local dragging, dragStart, startPos = false, nil, nil
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    local y = 6
    local function row(label, initial, cb)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 30)
        btn.Position = UDim2.new(0, 8, 0, y)
        btn.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
        btn.BorderColor3 = Color3.fromRGB(90, 90, 100)
        btn.BorderSizePixel = 1
        btn.Font = Enum.Font.Code
        btn.TextSize = 12
        btn.TextColor3 = Color3.fromRGB(235, 235, 240)
        btn.AutoButtonColor = true
        local on = initial
        local function paint()
            btn.Text = (on and "[ ON ]  " or "[ OFF ] ") .. label
        end
        paint()
        btn.MouseButton1Click:Connect(function()
            on = not on
            paint()
            cb(on)
        end)
        btn.Parent = body
        y = y + 36
        return function(v)
            on = v
            paint()
        end
    end

    local function label(text, grayed)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -16, 0, 20)
        t.Position = UDim2.new(0, 8, 0, y)
        t.BackgroundTransparency = 1
        t.Font = Enum.Font.Code
        t.TextSize = 12
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.TextColor3 = grayed and Color3.fromRGB(110, 110, 120)
            or Color3.fromRGB(200, 200, 208)
        t.Text = text
        t.Parent = body
        y = y + 24
    end

    row("Auto Slice", state.autoSwing, function(v) state.autoSwing = v end)

    local boostBtn = Instance.new("TextButton")
    boostBtn.Size = UDim2.new(1, -16, 0, 30)
    boostBtn.Position = UDim2.new(0, 8, 0, y)
    boostBtn.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
    boostBtn.BorderColor3 = Color3.fromRGB(90, 90, 100)
    boostBtn.BorderSizePixel = 1
    boostBtn.Font = Enum.Font.Code
    boostBtn.TextSize = 12
    boostBtn.TextColor3 = Color3.fromRGB(235, 235, 240)
    boostBtn.Text = "FPS Boost"
    boostBtn.Parent = body
    y = y + 36
    boostBtn.MouseButton1Click:Connect(function()
        pcall(fpsBoost)
        note("FPS boost applied")
    end)

    label("Auto Train  (next update)", true)
    return true
end

if not buildUI() then
    note("UI failed to mount, core still running")
end

return true
