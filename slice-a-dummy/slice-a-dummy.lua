-- NullShight Slice A Dummy! // v0.4.0
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
-- Land every hit for the user: tap the big slice button is never needed.
--
-- Mapped live 2026-10-16 (profit RemoteSpy):
--   SlashRemotes.SwingCompleted:FireServer(1)   -- damage lands here
-- Remote names live in CONFIG; only CONFIG changes on a game update.

local CONFIG = {
    SwingRemote = "SlashRemotes.SlashRequest",   -- swing request
    SwingCompletedRemote = "SlashRemotes.SwingCompleted", -- damage call
    SwingCompletedArgs = { 1 },
    RebirthRemote = nil,   -- fill after mapping
    EggRemote = nil,       -- fill after mapping
    AutoSwing = true,
    SwingDelay = 0.15,     -- seconds between attempts
    Turbo = false,         -- 0 delay between attempts
    Burst = 50,            -- TAP x50 burst count
    AntiAfk = true,
    FpsBoost = false,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

-- Generation guard: a fresh run kills the previous run's loops, so
-- re-running the loadstring never stacks duplicate swing loops.
local alive = true
_G.NSSD_Gen = ((_G.NSSD_Gen or 0) + 1)
local myGen = _G.NSSD_Gen

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
            for _, n in ipairs({ "NullShightSlice", "SliceEmblem" }) do
                local o = r:FindFirstChild(n)
                if o then pcall(function() o:Destroy() end) end
            end
        end
    end)
end

local function unload(quiet)
    if not alive then return end
    alive = false
    pcall(function() state.autoSwing = false end)
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function()
        local roots = {}
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then roots[#roots + 1] = h end
        roots[#roots + 1] = game:GetService("CoreGui")
        for _, r in ipairs(roots) do
            for _, n in ipairs({ "NullShightSlice", "SliceEmblem" }) do
                local g = r:FindFirstChild(n)
                if g then pcall(function() g:Destroy() end) end
            end
        end
    end)
    if not quiet then note("NullShight unloaded") end
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

-- Anti-AFK: generic, works everywhere.
if CONFIG.AntiAfk then
    track(LocalPlayer.Idled:Connect(function()
        if not alive then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end))
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

-- Observed 2026-10-16: damage lands via SwingCompleted:FireServer(1).
-- SlashRequest exists but the completed call is what counts, so the loop
-- fires exactly the observed call and nothing fancier.
local doneRemote = findRemote(CONFIG.SwingCompletedRemote)
local doneArgs = CONFIG.SwingCompletedArgs or { 1 }
if CONFIG.SwingCompletedRemote and not doneRemote then
    note("SwingCompleted remote not found, using tool/click fallback")
end
local function fireSlash()
    if doneRemote then
        local ok = pcall(function()
            if doneRemote:IsA("RemoteEvent") then
                doneRemote:FireServer(unpack(doneArgs))
            else
                doneRemote:InvokeServer(unpack(doneArgs))
            end
        end)
        if ok then countHit() return true end
    end
    return false
end

local state = {
    autoSwing = CONFIG.AutoSwing,
    turbo = CONFIG.Turbo,
}

local hits = 0
local function countHit() hits = hits + 1 end

local function doBurst()
    task.spawn(function()
        for _ = 1, CONFIG.Burst do
            if not alive or _G.NSSD_Gen ~= myGen then break end
            if not fireSlash() then
                local ok = swingTool()
                if not ok then clickDummy() end
            end
            task.wait()
        end
    end)
end

note("NullShight Slice loaded. AutoSwing " ..
    (state.autoSwing and "ON" or "OFF"))

task.spawn(function()
    while alive and _G.NSSD_Gen == myGen do
        if state.autoSwing then
            local fired = fireSlash()
            if not fired then
                fired = swingTool() or clickDummy()
            end
        end
        if state.turbo then
            task.wait()
        else
            task.wait(CONFIG.SwingDelay)
        end
    end
end)

-- NS Console UI.
-- References actually read (not guessed):
--   WindUI src/themes/Init.lua + window/Init.lua -- neutral token set,
--     pill CornerRadius(1,0) on small controls, 16px icons, translucent
--     panels.
--   Rayfield docs/themes -- every theme is flat neutral plus ONE state
--     color; color means "selected", never branding.
--   Mobile layout rules -- tabs for 2-6 peer sections, >=44px touch
--     targets, stable content height, progressive disclosure.
-- Departures from those libraries, on purpose:
--   * Left icon rail instead of a top tab bar. These scripts run on a
--     phone in landscape where vertical space is the scarce axis.
--   * Hairline rows instead of one card per option: ~2x density.
-- Palette consequence: ONE functional accent (green = ON). No per-game
-- hue, because then the accent could not double as "enabled".
local TweenService = game:GetService("TweenService")

-- Palette: WindUI Dark tokens (verified from the library source) and
-- Rayfield's neutral rule -- grayscale surface plus exactly one
-- functional color for ON states. No per-game hues: the accent must
-- mean "enabled", so it cannot double as branding.
local ACCENT = Color3.fromRGB(51, 199, 89)     -- #33C759 functional ON
local PRIMARY = Color3.fromRGB(0, 145, 255)   -- #0091FF focus/primary
local BASE = Color3.fromRGB(16, 16, 16)       -- #101010
local DIALOG = Color3.fromRGB(26, 26, 26)     -- #1a1a1a
local ELEMENT = Color3.fromRGB(42, 42, 44)    -- #2A2A2C
local HAIR = Color3.fromRGB(54, 54, 58)
local INK = Color3.fromRGB(255, 255, 255)
local PLACE = Color3.fromRGB(161, 161, 161)   -- #a1a1a1
local ICON = Color3.fromRGB(161, 161, 170)    -- #a1a1aa
local DIM = PLACE

local function tw(obj, props, dur, style, dir)
    local t = TweenService:Create(obj,
        TweenInfo.new(dur or 0.2, style or Enum.EasingStyle.Quart,
            dir or Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function round(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = obj
end

local function hairline(parent, yPos, w)
    local l = Instance.new("Frame")
    l.Size = UDim2.new(0, w or 200, 0, 1)
    l.Position = UDim2.new(0, 12, 0, yPos)
    l.BackgroundColor3 = HAIR
    l.BorderSizePixel = 0
    l.Parent = parent
    return l
end

-- Geometric rail icons built from Frames: always renders, no assets,
-- no emoji. kind: "bolt" | "gauge" | "list" | "cube"
local function railIcon(parent, kind, cy)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(0, 20, 0, 20)
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Position = UDim2.new(0.5, 0, 0, cy)
    holder.BackgroundTransparency = 1
    holder.Parent = parent

    local function bar(w, h, x, y, rot, col)
        local b = Instance.new("Frame")
        b.Size = UDim2.new(0, w, 0, h)
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = UDim2.new(0.5, x, 0.5, y)
        b.BackgroundColor3 = col or ICON
        b.BorderSizePixel = 0
        b.Rotation = rot or 0
        b.Parent = holder
        round(b, math.max(math.min(w, h) / 2, 1))
        return b
    end

    if kind == "bolt" then
        bar(3, 11, -3, -2, 22)
        bar(3, 8, 3, 3, 22)
    elseif kind == "gauge" then
        local ring = Instance.new("Frame")
        ring.Size = UDim2.new(0, 15, 0, 15)
        ring.BackgroundTransparency = 1
        ring.Parent = holder
        round(ring, 8)
        local s = Instance.new("UIStroke")
        s.Color = ICON
        s.Thickness = 2
        s.Parent = ring
        bar(2, 6, 2, -2, 35)
    elseif kind == "cube" then
        local o = Instance.new("Frame")
        o.Size = UDim2.new(0, 13, 0, 13)
        o.BackgroundTransparency = 1
        o.Parent = holder
        round(o, 3)
        local s = Instance.new("UIStroke")
        s.Color = ICON
        s.Thickness = 1.5
        s.Parent = o
        bar(5, 2, 0, 0, 0)
    else -- list
        bar(13, 2, 0, -5)
        bar(13, 2, 0, 0)
        bar(9, 2, -2, 5)
    end
    return holder
end

local function buildEmblem(parent, panel)
    local pad = Instance.new("TextButton")
    pad.Name = "SliceEmblem"
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
    emb.Size = UDim2.new(0, 54, 0, 54)
    emb.Position = UDim2.new(0.5, -27, 0.5, -27)
    emb.BackgroundColor3 = DIALOG
    emb.BorderSizePixel = 0
    emb.Font = Enum.Font.Code
    emb.TextSize = 19
    emb.TextColor3 = Color3.fromRGB(255, 255, 255)
    emb.TextStrokeTransparency = 0.45
    emb.Text = "NS"
    emb.Parent = pad
    round(emb, 27)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, ELEMENT),
        ColorSequenceKeypoint.new(1, BASE),
    })
    grad.Rotation = 40
    grad.Parent = emb

    -- Double thin ring: outer accent hairline + inner gap ring.
    local ring = Instance.new("UIStroke")
    ring.Color = PLACE
    ring.Thickness = 1.5
    ring.Parent = emb

    local ring2 = Instance.new("Frame")
    ring2.Size = UDim2.new(1, -9, 1, -9)
    ring2.AnchorPoint = Vector2.new(0.5, 0.5)
    ring2.Position = UDim2.new(0.5, 0, 0.5, 0)
    ring2.BackgroundTransparency = 1
    ring2.Parent = emb
    round(ring2, 23)
    local ring2s = Instance.new("UIStroke")
    ring2s.Color = Color3.fromRGB(226, 226, 232)
    ring2s.Thickness = 1
    ring2s.Transparency = 0.55
    ring2s.Parent = ring2

    local visible = true
    local downPos, startPos, moved = nil, nil, false
    track(pad.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            downPos = input.Position
            startPos = pad.Position
            moved = false
            tw(emb, { Size = UDim2.new(0, 46, 0, 46),
                Position = UDim2.new(0.5, -23, 0.5, -23) }, 0.12)
        end
    end))
    local function release(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            tw(emb, { Size = UDim2.new(0, 54, 0, 54),
                Position = UDim2.new(0.5, -27, 0.5, -27) }, 0.18,
                Enum.EasingStyle.Back)
            if not moved and downPos then
                visible = not visible
                if visible then
                    panel.Visible = true
                    tw(panel, { GroupTransparency = 0 }, 0.2)
                else
                    local f = tw(panel, { GroupTransparency = 1 }, 0.18)
                    pcall(function()
                        f.Completed:Wait()
                        if not visible then panel.Visible = false end
                    end)
                end
                ring.Color = visible and PLACE or ICON
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

    -- Idle breathing: subtle, cheap, gives the emblem a pulse of life.
    task.spawn(function()
        local t = 0
        while alive and _G.NSSD_Gen == myGen do
            t = t + 0.05
            local k = 1 + math.sin(t) * 0.035
            pcall(function()
                if emb.Parent then
                    emb.Size = UDim2.new(0, 54 * k, 0, 54 * k)
                    emb.Position = UDim2.new(0.5, -27 * k, 0.5, -27 * k)
                end
            end)
            task.wait(0.05)
        end
    end)
end

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

    local PW, PH = 470, 288
    local RAIL = 46
    local main = Instance.new("CanvasGroup")
    main.Name = "Panel"
    main.Position = UDim2.new(0, 14, 0, 56)
    main.BackgroundColor3 = BASE
    main.BackgroundTransparency = 0.04
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.GroupTransparency = 1
    main.Size = UDim2.new(0, PW, 0, PH)
    main.Parent = gui
    round(main, 16)

    -- Header: 42px, accent underline is the only "decoration" we allow.
    local head = Instance.new("TextButton")
    head.Name = "Head"
    head.Size = UDim2.new(1, 0, 0, 42)
    head.BackgroundTransparency = 1
    head.Text = ""
    head.AutoButtonColor = false
    head.Parent = main

    local badge = Instance.new("TextLabel")
    badge.Size = UDim2.new(0, 22, 0, 22)
    badge.Position = UDim2.new(0, 12, 0.5, -11)
    badge.BackgroundColor3 = ELEMENT
    badge.BorderSizePixel = 0
    badge.Font = Enum.Font.Code
    badge.TextSize = 11
    badge.TextColor3 = ACCENT
    badge.Text = "NS"
    badge.Parent = head
    round(badge, 7)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0, 150, 0, 16)
    title.Position = UDim2.new(0, 42, 0, 6)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = INK
    title.Text = "SLICE A DUMMY"
    title.Parent = head

    local readout = Instance.new("TextLabel")
    readout.Size = UDim2.new(0, 120, 0, 14)
    readout.Position = UDim2.new(0, 42, 0, 23)
    readout.BackgroundTransparency = 1
    readout.Font = Enum.Font.Code
    readout.TextSize = 9
    readout.TextXAlignment = Enum.TextXAlignment.Left
    readout.TextColor3 = DIM
    readout.Text = "hits 0"
    readout.Parent = head

    local mini = Instance.new("TextButton")
    mini.Size = UDim2.new(0, 26, 0, 26)
    mini.Position = UDim2.new(1, -34, 0.5, -13)
    mini.BackgroundTransparency = 1
    mini.Font = Enum.Font.Code
    mini.TextSize = 14
    mini.TextColor3 = DIM
    mini.Text = "-"
    mini.AutoButtonColor = false
    mini.Parent = head

    hairline(main, 41, PW)
    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(0, 64, 0, 2)
    accentLine.Position = UDim2.new(0, 12, 0, 41)
    accentLine.BackgroundColor3 = ACCENT
    accentLine.BorderSizePixel = 0
    accentLine.Parent = main
    round(accentLine, 1)

    -- Left rail.
    local rail = Instance.new("Frame")
    rail.Name = "Rail"
    rail.Size = UDim2.new(0, RAIL, 1, -42)
    rail.Position = UDim2.new(0, 0, 0, 42)
    rail.BackgroundColor3 = DIALOG
    rail.BorderSizePixel = 0
    rail.Parent = main

    local railEdge = Instance.new("Frame")
    railEdge.Size = UDim2.new(0, 1, 1, 0)
    railEdge.BackgroundColor3 = HAIR
    railEdge.BorderSizePixel = 0
    railEdge.Parent = rail

    local pages, tabSlots, rowHighlights = {}, {}, {}
    local curTab = "slice"
    local CONTENT_X = RAIL
    local CONTENT_W = PW - RAIL

    local function makeRow(parent, yPos, h)
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, -24, 0, h or 34)
        row.Position = UDim2.new(0, CONTENT_X + 12, 0, yPos)
        row.BackgroundTransparency = 1
        row.Text = ""
        row.AutoButtonColor = false
        row.Parent = parent
        local hl = Instance.new("Frame")
        hl.Size = UDim2.new(1, -24, 1, 0)
        hl.BackgroundColor3 = ACCENT
        hl.BackgroundTransparency = 1
        hl.BorderSizePixel = 0
        hl.Parent = row
        rowHighlights[row] = hl
        return row
    end

    local function micro(parent, yPos, text)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -48, 0, 14)
        t.Position = UDim2.new(0, 24, 0, yPos)
        t.BackgroundTransparency = 1
        t.Font = Enum.Font.Code
        t.TextSize = 9
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.TextColor3 = DIM
        t.Text = text
        t.Parent = parent
        return t
    end

    local function toggleRow(parent, yPos, labelText, initial, cb)
        local row = makeRow(parent, yPos, 34)
        local lb = Instance.new("TextLabel")
        lb.Size = UDim2.new(1, -60, 1, 0)
        lb.Position = UDim2.new(0, 10, 0, 0)
        lb.BackgroundTransparency = 1
        lb.Font = Enum.Font.Code
        lb.TextSize = 11
        lb.TextXAlignment = Enum.TextXAlignment.Left
        lb.TextColor3 = INK
        lb.Text = labelText
        lb.Parent = row

        local sw = Instance.new("Frame")
        sw.Size = UDim2.new(0, 34, 0, 19)
        sw.AnchorPoint = Vector2.new(1, 0.5)
        sw.Position = UDim2.new(1, -12, 0.5, 0)
        sw.BackgroundColor3 = ELEMENT
        sw.BorderSizePixel = 0
        sw.Parent = row
        local swc = Instance.new("UICorner")
        swc.CornerRadius = UDim.new(1, 0)
        swc.Parent = sw

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 13, 0, 13)
        knob.AnchorPoint = Vector2.new(0, 0.5)
        knob.Position = UDim2.new(0, 3, 0.5, 0)
        knob.BackgroundColor3 = INK
        knob.BorderSizePixel = 0
        knob.Parent = sw
        local kc = Instance.new("UICorner")
        kc.CornerRadius = UDim.new(1, 0)
        kc.Parent = knob

        local on = initial
        local function paint(animate)
            local target = on and ACCENT or ELEMENT
            local kx = on and UDim2.new(1, -16, 0.5, 0)
                or UDim2.new(0, 3, 0.5, 0)
            if animate then
                tw(sw, { BackgroundColor3 = target }, 0.18)
                tw(knob, { Position = kx }, 0.2, Enum.EasingStyle.Back)
            else
                sw.BackgroundColor3 = target
                knob.Position = kx
            end
        end
        paint(false)
        track(row.InputBegan:Connect(function(input)
            if not isTouch(input) then return end
            pressBegan(input)
            tw(rowHighlights[row], { BackgroundTransparency = 0.88 }, 0.1)
        end))
        track(row.InputEnded:Connect(function(input)
            if not isTouch(input) then return end
            tw(rowHighlights[row], { BackgroundTransparency = 1 }, 0.2)
            if pressEnded(input) then
                on = not on
                paint(true)
                cb(on)
            end
        end))
        return row
    end

    local function actionBtn(parent, yPos, labelText, cb, danger)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -48, 0, 30)
        btn.Position = UDim2.new(0, 24, 0, yPos)
        btn.BackgroundColor3 = danger and Color3.fromRGB(52, 24, 26)
            or ELEMENT
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.Code
        btn.TextSize = 11
        btn.TextColor3 = danger and Color3.fromRGB(255, 170, 170) or INK
        btn.Text = labelText
        btn.AutoButtonColor = false
        btn.Parent = parent
        round(btn, 8)
        local edge = Instance.new("UIStroke")
        edge.Color = danger and Color3.fromRGB(150, 70, 76)
            or HAIR
        edge.Thickness = 1
        edge.Transparency = danger and 0.4 or 0.3
        edge.Parent = btn
        local base = btn.BackgroundColor3
        local dark = Color3.new(
            math.max(base.R - 0.05, 0),
            math.max(base.G - 0.05, 0),
            math.max(base.B - 0.05, 0))
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
        return btn
    end

    -- Grab-anywhere drag + shared tap/drag helper.
    local dragging, dragStart, startPos, moved = false, nil, nil, false
    local function clampPanel()
        local cam = workspace.CurrentCamera
        local vs = (cam and cam.ViewportSize) or Vector2.new(800, 600)
        local p = main.Position
        local w = main.AbsoluteSize.X
        local h = main.AbsoluteSize.Y
        main.Position = UDim2.new(0,
            math.max(-w + 80, math.min(p.X.Offset, vs.X - 80)), 0,
            math.max(-h + 60, math.min(p.Y.Offset, vs.Y - 60)))
    end
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
    head.Active = true
    rail.Active = true
    track(head.InputBegan:Connect(pressBegan))
    track(head.InputEnded:Connect(pressEnded))

    -- Build pages, then slots in the rail.
    local defs = {
        { id = "slice", icon = "bolt", build = function(pg)
            micro(pg, 12, "AUTOMATION")
            toggleRow(pg, 30, "Auto Slice", state.autoSwing,
                function(v)
                    state.autoSwing = v
                    if v then fireSlash() end
                end)
            hairline(pg, 64, CONTENT_W - 24)
            toggleRow(pg, 65, "Turbo", state.turbo,
                function(v) state.turbo = v end)
            hairline(pg, 99, CONTENT_W - 24)
            micro(pg, 110, "ACTIONS")
            actionBtn(pg, 128, "SLICE x50 BURST", function() doBurst() end)
            actionBtn(pg, 164, "RELOAD UI", function()
                unload(true)
                pcall(function()
                    if gui.Parent then gui:Destroy() end
                end)
                task.wait(0.2)
                buildUI()
            end)
        end },
        { id = "boost", icon = "gauge", build = function(pg)
            micro(pg, 12, "PERFORMANCE")
            toggleRow(pg, 30, "FPS Boost", CONFIG.FpsBoost, function(v)
                CONFIG.FpsBoost = v
                if v then pcall(fpsBoost) end
            end)
            hairline(pg, 64, CONTENT_W - 24)
            toggleRow(pg, 65, "Anti AFK", CONFIG.AntiAfk, function(v)
                CONFIG.AntiAfk = v
            end)
            hairline(pg, 99, CONTENT_W - 24)
            micro(pg, 110, "DANGER")
            actionBtn(pg, 128, "APPLY FIX LAG", function()
                pcall(fpsBoost)
                CONFIG.SwingDelay = 0.35
                CONFIG.FpsBoost = true
                note("Lag fix applied")
            end)
            actionBtn(pg, 164, "UNLOAD SCRIPT",
                function() unload() end, true)
        end },
    }

    local PAGE_H = PH - 42
    for i, d in ipairs(defs) do
        local pg = Instance.new("CanvasGroup")
        pg.Name = "Page_" .. d.id
        pg.Size = UDim2.new(0, CONTENT_W, 0, PAGE_H)
        pg.Position = UDim2.new(0, CONTENT_X, 0, 42)
        pg.BackgroundTransparency = 1
        pg.Visible = d.id == curTab
        pg.GroupTransparency = d.id == curTab and 0 or 1
        pg.Parent = main
        pages[d.id] = pg
        d.build(pg)

        local slot = Instance.new("TextButton")
        slot.Size = UDim2.new(1, 0, 0, 46)
        slot.Position = UDim2.new(0, 0, 0, 6 + (i - 1) * 52)
        slot.BackgroundTransparency = 1
        slot.Text = ""
        slot.AutoButtonColor = false
        slot.Parent = rail
        local tint = Instance.new("Frame")
        tint.Size = UDim2.new(1, 0, 1, 0)
        tint.BackgroundColor3 = Color3.fromRGB(58, 58, 64)
        tint.BackgroundTransparency = 1
        tint.BorderSizePixel = 0
        tint.Parent = slot
        local marker = Instance.new("Frame")
        marker.Size = UDim2.new(0, 2, 0, 20)
        marker.AnchorPoint = Vector2.new(0, 0.5)
        marker.Position = UDim2.new(0, 0, 0.5, 0)
        marker.BackgroundColor3 = ACCENT
        marker.BackgroundTransparency = 1
        marker.BorderSizePixel = 0
        marker.Parent = slot
        round(marker, 1)
        local icon = railIcon(slot, d.icon, 0)
        local tip = Instance.new("TextLabel")
        tip.Size = UDim2.new(0, 40, 0, 12)
        tip.AnchorPoint = Vector2.new(0, 0)
        tip.Position = UDim2.new(0.5, -20, 1, 3)
        tip.BackgroundTransparency = 1
        tip.Font = Enum.Font.Code
        tip.TextSize = 8
        tip.TextColor3 = DIM
        tip.Text = d.id:upper()
        tip.Parent = slot
        tabSlots[d.id] = { slot = slot, tint = tint,
            marker = marker, icon = icon, tip = tip }
    end

    local function paintRail()
        for _, d in ipairs(defs) do
            local s = tabSlots[d.id]
            local active = d.id == curTab
            tw(s.tint, { BackgroundTransparency =
                active and 0 or 1 }, 0.18)
            tw(s.marker, { BackgroundTransparency =
                active and 0 or 1 }, 0.18)
            s.tip.TextColor3 = active and INK or DIM
            s.icon.Position = UDim2.new(0.5, 0, 0, active and -4 or 0)
        end
    end

    local function switchTab(id)
        if id == curTab then return end
        local old = pages[curTab]
        curTab = id
        paintRail()
        local new = pages[curTab]
        if old then
            local f = tw(old, { GroupTransparency = 1 }, 0.1)
            pcall(function()
                f.Completed:Wait()
                if pages[curTab] ~= old then old.Visible = false end
            end)
        end
        if new then
            new.Visible = true
            tw(new, { GroupTransparency = 0 }, 0.16)
        end
    end
    paintRail()

    for _, d in ipairs(defs) do
        local s = tabSlots[d.id]
        track(s.slot.InputBegan:Connect(function(input)
            if not isTouch(input) then return end
            pressBegan(input)
        end))
        track(s.slot.InputEnded:Connect(function(input)
            if not isTouch(input) then return end
            if pressEnded(input) then switchTab(d.id) end
        end))
    end

    -- Live hit readout.
    task.spawn(function()
        while alive and _G.NSSD_Gen == myGen do
            pcall(function() readout.Text = "hits " .. tostring(hits) end)
            task.wait(0.5)
        end
    end)

    local collapsed = false
    track(mini.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        mini.Text = collapsed and "+" or "-"
        tw(main, { Size = collapsed and UDim2.new(0, PW, 0, 42)
            or UDim2.new(0, PW, 0, PH) }, 0.28,
            Enum.EasingStyle.Quart)
    end))

    buildEmblem(gui, main)

    local endPos = main.Position
    main.Position = UDim2.new(endPos.X.Scale, endPos.X.Offset,
        endPos.Y.Scale, endPos.Y.Offset + 18)
    main.Visible = true
    tw(main, { GroupTransparency = 0 }, 0.28)
    tw(main, { Position = endPos }, 0.34, Enum.EasingStyle.Back)
    return true
end

if not buildUI() then
    note("UI failed to mount, core still running")
end

return true
