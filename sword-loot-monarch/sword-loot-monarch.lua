-- NullShight Sword Loot Monarch // v0.1.2
-- Game: +1 Sword Loot Monarch (93239606899307). Clicker loop: click for
-- power, train, clear stages, loot, forge swords, rebirth.
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
--
-- Mapped live 2026-10-16 (profit RemoteSpy):
--   Remotes.MainEvent:FireServer(220)   -- click (arg 220)
-- Train / stage / rebirth / collect remotes not mapped yet.
-- Map them and only CONFIG below changes.

local CONFIG = {
    ClickRemote = "Remotes.MainEvent",   -- dotted from ReplicatedStorage
    ClickArgs = { 220 },
    AutoClick = true,
    ClickDelay = 0,          -- 0 = every frame (~60/s), max speed
    Burst = 50,                          -- CLICK x50 burst count
    TrainRemote = nil,                   -- fill after mapping
    TrainArgs = {},
    StageRemote = nil,                   -- fill after mapping (farm/attack)
    StageArgs = {},
    RebirthRemote = "Remotes.MainFunction", -- InvokeServer, mapped 2026-10-16
    RebirthArgs = { 173 },
    CollectRemote = nil,                 -- fill after mapping
    CollectArgs = {},
    AutoTrain = false,                   -- on once TrainRemote mapped
    TrainDelay = 2,
    AutoStage = false,                   -- on once StageRemote mapped
    StageDelay = 2,
    AutoRebirth = false,                 -- on once RebirthRemote mapped
    RebirthDelay = 30,
    AutoCollect = false,                 -- on once CollectRemote mapped
    CollectDelay = 3,
    AntiAfk = true,
    FpsBoost = false,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

local state = {
    autoClick = CONFIG.AutoClick,
    autoTrain = CONFIG.AutoTrain,
    autoStage = CONFIG.AutoStage,
    autoRebirth = CONFIG.AutoRebirth,
    autoCollect = CONFIG.AutoCollect,
}

-- Generation guard: a fresh run kills the previous run's loops.
local alive = true
_G.NSSLM_Gen = ((_G.NSSLM_Gen or 0) + 1)
local myGen = _G.NSSLM_Gen

local conns = {}
local function track(c)
    conns[#conns + 1] = c
    return c
end
do
    pcall(function()
        local roots = {}
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then roots[#roots + 1] = h end
        roots[#roots + 1] = game:GetService("CoreGui")
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then roots[#roots + 1] = pg end
        for _, r in ipairs(roots) do
            for _, n in ipairs({ "NullShightSword", "SwordEmblem" }) do
                local o = r:FindFirstChild(n)
                if o then pcall(function() o:Destroy() end) end
            end
        end
    end)
end

local function note(msg)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "NullShight",
            Text = msg,
            Duration = 4,
        })
    end)
end

local function unload(quiet)
    if not alive then return end
    alive = false
    state.autoClick = false
    state.autoTrain = false
    state.autoStage = false
    state.autoRebirth = false
    state.autoCollect = false
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function()
        local roots = {}
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then roots[#roots + 1] = h end
        roots[#roots + 1] = game:GetService("CoreGui")
        for _, r in ipairs(roots) do
            for _, n in ipairs({ "NullShightSword", "SwordEmblem" }) do
                local g = r:FindFirstChild(n)
                if g then pcall(function() g:Destroy() end) end
            end
        end
    end)
    if not quiet then note("NullShight unloaded") end
end

if CONFIG.AntiAfk then
    track(LocalPlayer.Idled:Connect(function()
        if not alive then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end))
end

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

local function fireMapped(path, args)
    local r = findRemote(path)
    if not r then return false end
    return pcall(function()
        if r:IsA("RemoteEvent") then
            r:FireServer(unpack(args or {}))
        else
            r:InvokeServer(unpack(args or {}))
        end
    end)
end

-- One independent loop per feature. Toggles never depend on each other.
task.spawn(function()
    while alive and _G.NSSLM_Gen == myGen do
        if state.autoClick and CONFIG.ClickRemote then
            pcall(fireMapped, CONFIG.ClickRemote, CONFIG.ClickArgs)
        end
        if CONFIG.ClickDelay > 0 then
            task.wait(CONFIG.ClickDelay)
        else
            task.wait() -- next frame: fastest stable rate
        end
    end
end)

task.spawn(function()
    while alive and _G.NSSLM_Gen == myGen do
        if state.autoTrain and CONFIG.TrainRemote then
            pcall(fireMapped, CONFIG.TrainRemote, CONFIG.TrainArgs)
        end
        task.wait(CONFIG.TrainDelay)
    end
end)

task.spawn(function()
    while alive and _G.NSSLM_Gen == myGen do
        if state.autoStage and CONFIG.StageRemote then
            pcall(fireMapped, CONFIG.StageRemote, CONFIG.StageArgs)
        end
        task.wait(CONFIG.StageDelay)
    end
end)

task.spawn(function()
    while alive and _G.NSSLM_Gen == myGen do
        if state.autoRebirth and CONFIG.RebirthRemote then
            pcall(fireMapped, CONFIG.RebirthRemote, CONFIG.RebirthArgs)
        end
        task.wait(CONFIG.RebirthDelay)
    end
end)

task.spawn(function()
    while alive and _G.NSSLM_Gen == myGen do
        if state.autoCollect and CONFIG.CollectRemote then
            pcall(fireMapped, CONFIG.CollectRemote, CONFIG.CollectArgs)
        end
        task.wait(CONFIG.CollectDelay)
    end
end)

note("NullShight Sword loaded. AutoClick " ..
    (state.autoClick and "ON" or "OFF"))

task.spawn(function()
    task.wait(2)
    if _G.NSSLM_Gen ~= myGen then return end
    if findRemote(CONFIG.ClickRemote) then
        note("Click remote OK")
    else
        note("Click remote missing - game updated?")
    end
end)

-- UI (Fluent-style, landscape tabs, grab-anywhere). All English.
local TweenService = game:GetService("TweenService")

local ACCENT = Color3.fromRGB(150, 190, 255)
local CARD = Color3.fromRGB(24, 27, 36)
local CARD2 = Color3.fromRGB(30, 34, 46)
local INK = Color3.fromRGB(235, 235, 242)
local DIM = Color3.fromRGB(150, 155, 175)

local function tw(obj, props, dur, style, dir)
    local t = TweenService:Create(obj,
        TweenInfo.new(dur or 0.22, style or Enum.EasingStyle.Quart,
            dir or Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function round(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = obj
end

local function stroke(obj, color, transp)
    local st = Instance.new("UIStroke")
    st.Color = color
    st.Transparency = transp or 0.5
    st.Thickness = 1
    st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    st.Parent = obj
end

local function buildEmblem(parent, panel)
    local pad = Instance.new("TextButton")
    pad.Name = "SwordEmblem"
    pad.Size = UDim2.new(0, 96, 0, 96)
    pad.Position = UDim2.new(1, -112, 1, -180)
    pad.BackgroundTransparency = 1
    pad.Text = ""
    pad.AutoButtonColor = false
    pad.Active = true
    pad.Selectable = false
    pad.Parent = parent

    local emb = Instance.new("TextLabel")
    emb.Name = "Emblem"
    emb.Size = UDim2.new(0, 56, 0, 56)
    emb.Position = UDim2.new(0.5, -28, 0.5, -28)
    emb.BackgroundColor3 = Color3.fromRGB(22, 26, 34)
    emb.BorderSizePixel = 0
    emb.Font = Enum.Font.Code
    emb.TextSize = 18
    emb.TextColor3 = Color3.fromRGB(245, 245, 250)
    emb.Text = "NS"
    emb.Parent = pad
    round(emb, 28)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(44, 54, 78)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 17, 26)),
    })
    grad.Rotation = 35
    grad.Parent = emb

    local ring = Instance.new("UIStroke")
    ring.Color = Color3.fromRGB(200, 200, 210)
    ring.Thickness = 2
    ring.Parent = emb

    local visible = true
    local downPos, startPos, moved = nil, nil, false
    track(pad.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            downPos = input.Position
            startPos = pad.Position
            moved = false
            tw(emb, { Size = UDim2.new(0, 48, 0, 48),
                Position = UDim2.new(0.5, -24, 0.5, -24) }, 0.12)
        end
    end))
    local function release(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            tw(emb, { Size = UDim2.new(0, 56, 0, 56),
                Position = UDim2.new(0.5, -28, 0.5, -28) }, 0.18,
                Enum.EasingStyle.Back)
            if not moved and downPos then
                visible = not visible
                if visible then
                    panel.Visible = true
                    tw(panel, { GroupTransparency = 0 }, 0.22)
                else
                    local f = tw(panel, { GroupTransparency = 1 }, 0.18)
                    pcall(function()
                        f.Completed:Wait()
                        if not visible then panel.Visible = false end
                    end)
                end
                ring.Color = visible and Color3.fromRGB(245, 245, 250)
                    or Color3.fromRGB(110, 115, 130)
            end
            downPos = nil
        end
    end
    track(pad.InputEnded:Connect(release))
    track(game:GetService("UserInputService").InputChanged:Connect(function(input)
        if downPos
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - downPos
            if d.Magnitude > 8 then moved = true end
            if moved then
                pad.Position = UDim2.new(startPos.X.Scale,
                    startPos.X.Offset + d.X, startPos.Y.Scale,
                    startPos.Y.Offset + d.Y)
            end
        end
    end))
    track(game:GetService("UserInputService").InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            downPos = nil
        end
    end))
end

local function buildUI()
    local parent = nil
    pcall(function()
        parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not parent then return false end

    local gui = Instance.new("ScreenGui")
    gui.Name = "NullShightSword"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local PW = 470
    local main = Instance.new("CanvasGroup")
    main.Name = "Panel"
    main.Position = UDim2.new(0, 16, 0, 60)
    main.BackgroundColor3 = Color3.fromRGB(15, 17, 25)
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.GroupTransparency = 1
    main.Parent = gui
    round(main, 14)
    stroke(main, Color3.fromRGB(80, 95, 130), 0.4)

    local y = 0
    local head = Instance.new("TextButton")
    head.Name = "Head"
    head.Size = UDim2.new(1, 0, 0, 52)
    head.Position = UDim2.new(0, 0, 0, 0)
    head.BackgroundTransparency = 1
    head.Text = ""
    head.AutoButtonColor = false
    head.Parent = main
    y = 52

    local badge = Instance.new("TextLabel")
    badge.Size = UDim2.new(0, 30, 0, 30)
    badge.Position = UDim2.new(0, 12, 0.5, -15)
    badge.BackgroundColor3 = Color3.fromRGB(26, 32, 48)
    badge.BorderSizePixel = 0
    badge.Font = Enum.Font.Code
    badge.TextSize = 12
    badge.TextColor3 = ACCENT
    badge.Text = "NS"
    badge.Parent = head
    round(badge, 9)
    stroke(badge, ACCENT, 0.45)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -92, 0, 20)
    title.Position = UDim2.new(0, 50, 0, 7)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = INK
    title.Text = "NULLSHIGHT"
    title.Parent = head

    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(1, -92, 0, 14)
    sub.Position = UDim2.new(0, 50, 0, 28)
    sub.BackgroundTransparency = 1
    sub.Font = Enum.Font.Code
    sub.TextSize = 10
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextColor3 = DIM
    sub.Text = "SWORD LOOT MONARCH v0.1.2"
    sub.Parent = head

    local mini = Instance.new("TextButton")
    mini.Size = UDim2.new(0, 30, 0, 30)
    mini.Position = UDim2.new(1, -40, 0.5, -15)
    mini.BackgroundColor3 = CARD
    mini.BorderSizePixel = 0
    mini.Font = Enum.Font.Code
    mini.TextSize = 16
    mini.TextColor3 = DIM
    mini.Text = "-"
    mini.AutoButtonColor = false
    mini.Parent = head
    round(mini, 9)
    stroke(mini, Color3.fromRGB(55, 60, 78), 0.55)

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Size = UDim2.new(1, 0, 0, 224)
    body.Position = UDim2.new(0, 0, 0, y)
    body.BackgroundTransparency = 1
    body.ClipsDescendants = true
    body.Parent = main

    -- Grab-anywhere drag with tap threshold.
    local function clampPanel()
        local cam = workspace.CurrentCamera
        local vs = (cam and cam.ViewportSize) or Vector2.new(800, 600)
        local p = main.Position
        local w = main.AbsoluteSize.X
        local h = main.AbsoluteSize.Y
        local x = math.max(-w + 80, math.min(p.X.Offset, vs.X - 80))
        local yy = math.max(-h + 60, math.min(p.Y.Offset, vs.Y - 60))
        main.Position = UDim2.new(0, x, 0, yy)
    end
    local dragging, dragStart, startPos, moved = false, nil, nil, false
    local function isTouch(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement
    end
    local function pressBegan(input)
        if not isTouch(input) or dragging then return end
        dragging = true
        moved = false
        dragStart = input.Position
        startPos = main.Position
    end
    local function pressEnded(input)
        if not isTouch(input) then return false end
        if not dragging then return false end
        dragging = false
        pcall(clampPanel)
        return not moved
    end
    track(game:GetService("UserInputService").InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local d = input.Position - dragStart
        if d.Magnitude > 10 then moved = true end
        if moved then
            main.Position = UDim2.new(startPos.X.Scale,
                startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(game:GetService("UserInputService").InputEnded:Connect(function(input)
        pressEnded(input)
    end))
    body.Active = true
    track(head.InputBegan:Connect(pressBegan))
    track(head.InputEnded:Connect(pressEnded))
    track(body.InputBegan:Connect(pressBegan))
    track(body.InputEnded:Connect(pressEnded))

    -- Horizontal tabs: one page visible, fixed content height.
    local tabDefs = {
        { id = "click", label = "CLICK" },
        { id = "farm", label = "FARM" },
        { id = "sys", label = "SYS" },
    }
    local pages = {}
    local tabBtns = {}
    local curTab = "click"
    local function paintTabs()
        for _, d in ipairs(tabDefs) do
            local b = tabBtns[d.id]
            if b then
                local active = d.id == curTab
                tw(b, { BackgroundColor3 = active and CARD2
                    or Color3.fromRGB(19, 22, 29) }, 0.15)
                b.TextColor3 = active and ACCENT or DIM
            end
        end
    end
    local function switchTab(id)
        if id == curTab then return end
        local old = pages[curTab]
        curTab = id
        paintTabs()
        local new = pages[curTab]
        if old then
            local f = tw(old, { GroupTransparency = 1 }, 0.12)
            pcall(function()
                f.Completed:Wait()
                if pages[curTab] ~= old then old.Visible = false end
            end)
        end
        if new then
            new.Visible = true
            tw(new, { GroupTransparency = 0 }, 0.18)
        end
    end
    local TW = (PW - 24 - 16) / 3
    for i, d in ipairs(tabDefs) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, TW, 0, 30)
        b.Position = UDim2.new(0, 12 + (i - 1) * (TW + 8), 0, 6)
        b.BackgroundColor3 = Color3.fromRGB(19, 22, 29)
        b.BorderSizePixel = 0
        b.Font = Enum.Font.Code
        b.TextSize = 11
        b.TextColor3 = DIM
        b.Text = d.label
        b.AutoButtonColor = false
        b.Parent = body
        round(b, 8)
        stroke(b, Color3.fromRGB(55, 60, 78), 0.55)
        tabBtns[d.id] = b
        track(b.InputBegan:Connect(function(input)
            if not isTouch(input) then return end
            pressBegan(input)
        end))
        track(b.InputEnded:Connect(function(input)
            if not isTouch(input) then return end
            if pressEnded(input) then switchTab(d.id) end
        end))
        local pg = Instance.new("CanvasGroup")
        pg.Name = "Page_" .. d.id
        pg.Size = UDim2.new(1, -24, 0, 172)
        pg.Position = UDim2.new(0, 12, 0, 44)
        pg.BackgroundTransparency = 1
        pg.Visible = d.id == curTab
        pg.GroupTransparency = d.id == curTab and 0 or 1
        pg.Parent = body
        pages[d.id] = pg
    end
    paintTabs()

    local COLW = (PW - 24 - 8) / 2
    local function toggleCell(parent, col, row, labelText, initial, cb)
        local card = Instance.new("TextButton")
        card.Size = UDim2.new(0, COLW, 0, 40)
        card.Position = UDim2.new(0, col * (COLW + 8), 0, row * 48)
        card.BackgroundColor3 = CARD
        card.BorderSizePixel = 0
        card.Text = ""
        card.AutoButtonColor = false
        card.Parent = parent
        round(card, 10)
        stroke(card, Color3.fromRGB(55, 60, 78), 0.55)

        local lb = Instance.new("TextLabel")
        lb.Size = UDim2.new(1, -70, 1, 0)
        lb.Position = UDim2.new(0, 10, 0, 0)
        lb.BackgroundTransparency = 1
        lb.Font = Enum.Font.Code
        lb.TextSize = 11
        lb.TextXAlignment = Enum.TextXAlignment.Left
        lb.TextColor3 = INK
        lb.Text = labelText
        lb.Parent = card

        local sw = Instance.new("Frame")
        sw.Size = UDim2.new(0, 44, 0, 24)
        sw.AnchorPoint = Vector2.new(1, 0.5)
        sw.Position = UDim2.new(1, -10, 0.5, 0)
        sw.BorderSizePixel = 0
        sw.Parent = card
        round(sw, 12)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 18, 0, 18)
        knob.AnchorPoint = Vector2.new(0, 0.5)
        knob.Position = UDim2.new(0, 3, 0.5, 0)
        knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
        knob.BorderSizePixel = 0
        knob.Parent = sw
        round(knob, 9)

        local on = initial
        local function paint(animate)
            local swC = on and ACCENT or Color3.fromRGB(48, 52, 68)
            local kx = on and UDim2.new(1, -21, 0.5, 0)
                or UDim2.new(0, 3, 0.5, 0)
            if animate then
                tw(sw, { BackgroundColor3 = swC }, 0.2)
                tw(knob, { Position = kx }, 0.22,
                    Enum.EasingStyle.Back)
            else
                sw.BackgroundColor3 = swC
                knob.Position = kx
            end
        end
        paint(false)
        track(card.InputBegan:Connect(pressBegan))
        track(card.InputEnded:Connect(function(input)
            if pressEnded(input) then
                on = not on
                paint(true)
                cb(on)
            end
        end))
    end

    local function wideBtn(parent, row, labelText, cb, danger)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 38)
        btn.Position = UDim2.new(0, 0, 0, row * 46)
        btn.BackgroundColor3 = danger and Color3.fromRGB(52, 24, 26)
            or CARD2
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.Code
        btn.TextSize = 12
        btn.TextColor3 = danger and Color3.fromRGB(255, 175, 175) or INK
        btn.Text = labelText
        btn.AutoButtonColor = false
        btn.Parent = parent
        round(btn, 10)
        if danger then
            stroke(btn, Color3.fromRGB(170, 80, 85), 0.4)
        else
            stroke(btn, Color3.fromRGB(70, 76, 100), 0.5)
        end
        local base = btn.BackgroundColor3
        local dark = Color3.new(
            math.max(base.R - 0.06, 0),
            math.max(base.G - 0.06, 0),
            math.max(base.B - 0.06, 0))
        track(btn.InputBegan:Connect(function(input)
            if not isTouch(input) then return end
            pressBegan(input)
            tw(btn, { BackgroundColor3 = dark }, 0.1)
        end))
        track(btn.InputEnded:Connect(function(input)
            if not isTouch(input) then return end
            tw(btn, { BackgroundColor3 = base }, 0.15)
            if pressEnded(input) then cb() end
        end))
    end

    -- CLICK: core loop + burst. FARM: unlocks as remotes get mapped.
    local click = pages.click
    toggleCell(click, 0, 0, "Auto Click", state.autoClick,
        function(v)
            state.autoClick = v
            if v then pcall(fireMapped, CONFIG.ClickRemote, CONFIG.ClickArgs) end
        end)
    wideBtn(click, 1, "CLICK x50 BURST", function()
        task.spawn(function()
            for _ = 1, CONFIG.Burst do
                if not alive then break end
                pcall(fireMapped, CONFIG.ClickRemote, CONFIG.ClickArgs)
                task.wait()
            end
        end)
    end)

    local farm = pages.farm
    local function farmToggle(label, key, path, args)
        return function(v)
            state[key] = v
            if v then
                if findRemote(path) then
                    pcall(fireMapped, path, args)
                else
                    note(label .. " remote not mapped yet")
                end
            end
        end
    end
    toggleCell(farm, 0, 0, "Auto Train", state.autoTrain,
        farmToggle("Train", "autoTrain",
            CONFIG.TrainRemote, CONFIG.TrainArgs))
    toggleCell(farm, 1, 0, "Auto Stage", state.autoStage,
        farmToggle("Stage", "autoStage",
            CONFIG.StageRemote, CONFIG.StageArgs))
    toggleCell(farm, 0, 1, "Auto Rebirth", state.autoRebirth,
        farmToggle("Rebirth", "autoRebirth",
            CONFIG.RebirthRemote, CONFIG.RebirthArgs))
    toggleCell(farm, 1, 1, "Auto Collect", state.autoCollect,
        farmToggle("Collect", "autoCollect",
            CONFIG.CollectRemote, CONFIG.CollectArgs))

    local sys = pages.sys
    wideBtn(sys, 0, "FIX LAG", function()
        pcall(fpsBoost)
        CONFIG.ClickDelay = 0.5
        note("Lag fix applied")
    end)
    wideBtn(sys, 1, "UNLOAD SCRIPT", function() unload() end, true)

    local fullH = y + 224 + 12
    body.Size = UDim2.new(1, 0, 0, 224)
    main.Size = UDim2.new(0, PW, 0, fullH)

    local collapsed = false
    track(mini.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        mini.Text = collapsed and "+" or "-"
        tw(main, { Size = collapsed and UDim2.new(0, PW, 0, 52)
            or UDim2.new(0, PW, 0, fullH) }, 0.3,
            Enum.EasingStyle.Quart)
    end))

    buildEmblem(gui, main)

    local endPos = main.Position
    main.Position = UDim2.new(endPos.X.Scale, endPos.X.Offset,
        endPos.Y.Scale, endPos.Y.Offset + 24)
    main.Visible = true
    tw(main, { GroupTransparency = 0 }, 0.3)
    tw(main, { Position = endPos }, 0.35, Enum.EasingStyle.Back)
    return true
end

if not buildUI() then
    note("UI failed to mount, core still running")
end

return true
