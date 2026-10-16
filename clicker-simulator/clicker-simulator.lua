-- NullShight Clicker Tap // v0.1.1
-- Universal tap-based auto clicker: injects synthetic screen taps through
-- VirtualInputManager, so it works even when remotes are unnamed/hidden.
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
--
-- Setup: run, enable Auto Tap. If clicks don't register, the tap point is
-- wrong -- adjust CONFIG.TapX/TapY (0-1 screen scale) toward the big
-- click button, or tell me the game link and I will wire its remotes.

local CONFIG = {
    AutoTap = true,
    TapDelay = 0.1,          -- seconds between taps
    TapX = 0.5,              -- 0-1 horizontal (0.5 = center)
    TapY = 0.5,              -- 0-1 vertical (0.5 = center)
    TapPause = 3,            -- yield seconds after a REAL finger touch
    Burst = 50,              -- TAP x50 burst count
    ClickRemote = nil,       -- optional remote mode: dotted path
    ClickArgs = {},
    AutoRemote = false,
    RemoteDelay = 0.2,
    AntiAfk = true,
    FpsBoost = false,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

local state = {
    autoTap = CONFIG.AutoTap,
    autoRemote = CONFIG.AutoRemote,
}

-- Generation guard: a fresh run kills the previous run's loops.
local alive = true
_G.NSCT_Gen = ((_G.NSCT_Gen or 0) + 1)
local myGen = _G.NSCT_Gen

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
            for _, n in ipairs({ "NullShightTap", "TapEmblem" }) do
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
    state.autoTap = false
    state.autoRemote = false
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function()
        local roots = {}
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then roots[#roots + 1] = h end
        roots[#roots + 1] = game:GetService("CoreGui")
        for _, r in ipairs(roots) do
            for _, n in ipairs({ "NullShightTap", "TapEmblem" }) do
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

local function tapPoint()
    local cam = workspace.CurrentCamera
    local vs = (cam and cam.ViewportSize) or Vector2.new(800, 600)
    return vs.X * CONFIG.TapX, vs.Y * CONFIG.TapY
end

local function sendTap()
    local vim = nil
    pcall(function()
        vim = game:GetService("VirtualInputManager")
    end)
    if not vim then return false end
    local x, y = tapPoint()
    return pcall(function()
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
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

-- Tap loop yields to real fingers: any genuine Touch input pauses
-- synthetic taps for TapPause seconds, so you can always move around
-- and reach the toggle. (Synthetic taps are MouseButton1, never Touch,
-- so the tapper can never pause itself.)
local lastTouch = 0
track(game:GetService("UserInputService").InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        lastTouch = os.clock()
    end
end))

task.spawn(function()
    while alive and _G.NSCT_Gen == myGen do
        if state.autoTap and os.clock() - lastTouch > CONFIG.TapPause then
            pcall(sendTap)
        end
        if CONFIG.TapDelay > 0 then
            task.wait(CONFIG.TapDelay)
        else
            task.wait()
        end
    end
end)

-- Optional remote loop (activates once ClickRemote is mapped).
task.spawn(function()
    while alive and _G.NSCT_Gen == myGen do
        if state.autoRemote and CONFIG.ClickRemote then
            pcall(fireMapped, CONFIG.ClickRemote, CONFIG.ClickArgs)
        end
        task.wait(CONFIG.RemoteDelay)
    end
end)

note("NullShight Tap loaded. AutoTap " ..
    (state.autoTap and "ON" or "OFF"))

-- UI (Fluent-style, landscape tabs, grab-anywhere). All English.
local TweenService = game:GetService("TweenService")

local ACCENT = Color3.fromRGB(150, 255, 190)
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
    pad.Name = "TapEmblem"
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
    emb.BackgroundColor3 = Color3.fromRGB(44, 50, 68)
    emb.BorderSizePixel = 0
    emb.Font = Enum.Font.Code
    emb.TextSize = 20
    emb.TextColor3 = Color3.fromRGB(255, 255, 255)
    emb.TextStrokeTransparency = 0.5
    emb.Text = "NS"
    emb.Parent = pad
    round(emb, 28)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(64, 74, 100)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 34, 50)),
    })
    grad.Rotation = 35
    grad.Parent = emb

    local ring = Instance.new("UIStroke")
    ring.Color = Color3.fromRGB(235, 235, 245)
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
    gui.Name = "NullShightTap"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local PW = 470
    local main = Instance.new("CanvasGroup")
    main.Name = "Panel"
    main.Position = UDim2.new(0, 16, 0, 60)
    main.BackgroundColor3 = Color3.fromRGB(14, 18, 15)
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.GroupTransparency = 1
    main.Parent = gui
    round(main, 14)
    stroke(main, Color3.fromRGB(80, 115, 90), 0.4)

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
    badge.BackgroundColor3 = Color3.fromRGB(24, 38, 28)
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
    sub.Text = "CLICKER TAP v0.1.1"
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

    -- Tabs: TAP + REMOTE (unlocks when mapped) + SYS.
    local tabDefs = {
        { id = "tap", label = "TAP" },
        { id = "remote", label = "REMOTE" },
        { id = "sys", label = "SYS" },
    }
    local pages = {}
    local tabBtns = {}
    local curTab = "tap"
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

    local tap = pages.tap
    toggleCell(tap, 0, 0, "Auto Tap", state.autoTap,
        function(v)
            state.autoTap = v
            if v then pcall(sendTap) end
        end)
    toggleCell(tap, 1, 0, "Turbo (0 delay)", CONFIG.TapDelay <= 0,
        function(v)
            CONFIG.TapDelay = v and 0 or 0.1
        end)
    wideBtn(tap, 1, "TAP x50 BURST", function()
        task.spawn(function()
            for _ = 1, CONFIG.Burst do
                if not alive then break end
                pcall(sendTap)
                task.wait()
            end
        end)
    end)

    local remote = pages.remote
    toggleCell(remote, 0, 0, "Auto Remote", state.autoRemote,
        function(v)
            state.autoRemote = v
            if v then
                if findRemote(CONFIG.ClickRemote) then
                    pcall(fireMapped, CONFIG.ClickRemote, CONFIG.ClickArgs)
                else
                    note("Remote not mapped yet")
                end
            end
        end)

    local sys = pages.sys
    wideBtn(sys, 0, "FIX LAG", function()
        pcall(fpsBoost)
        CONFIG.TapDelay = 0.2
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
