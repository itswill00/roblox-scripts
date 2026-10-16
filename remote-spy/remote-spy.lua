-- NullShight NetLens // v1.0.0 -- RemoteSpy
-- A precise, low-footprint network lens: logs RemoteEvent/RemoteFunction
-- traffic, coalesces duplicates, and generates paste-ready call snippets.
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
--
-- Stealth notes (honest): single __namecallmethod hook, restored on unload.
-- No polling loops, no getconnections tampering, no globals except one
-- generation counter, discreet GUI names. Nothing is 100% undetectable
-- against a determined server-side anti-cheat -- use on alt accounts.
--
-- Workflow: run, play the game manually, tap a row to copy its snippet,
-- paste the snippet form into the game script CONFIG.

local CONFIG = {
    MaxRows = 120,         -- cap on-screen rows (oldest pruned first)
    MergeDupes = true,     -- coalesce identical calls into xN counters
    ArgsOnly = false,      -- ignore calls with zero arguments
    SnipDepth = 3,         -- table depth in generated snippets
    SnipKeys = 8,          -- max table keys in generated snippets
    StrLen = 120,          -- truncate long strings in previews
    AntiAfk = true,
}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local VirtualUser = game:GetService("VirtualUser")

local state = {
    paused = false,
    merge = CONFIG.MergeDupes,
    argsOnly = CONFIG.ArgsOnly,
}

-- Generation guard: a fresh run kills the previous run's hook + handle.
local alive = true
_G.NSNL_Gen = ((_G.NSNL_Gen or 0) + 1)
local myGen = _G.NSNL_Gen
local function mine() return alive and _G.NSNL_Gen == myGen end

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
            for _, n in ipairs({ "NetLens", "NetLensEmblem" }) do
                local o = r:FindFirstChild(n)
                if o then pcall(function() o:Destroy() end) end
            end
        end
    end)
end

local function note(msg)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "NetLens",
            Text = msg,
            Duration = 4,
        })
    end)
end

local oldNC = nil
local function unload(quiet)
    if not alive then return end
    alive = false
    pcall(function()
        if type(hookmetamethod) == "function" and oldNC then
            hookmetamethod(game, "__namecallmethod", oldNC)
        end
    end)
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function()
        local roots = {}
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then roots[#roots + 1] = h end
        roots[#roots + 1] = game:GetService("CoreGui")
        for _, r in ipairs(roots) do
            for _, n in ipairs({ "NetLens", "NetLensEmblem" }) do
                local g = r:FindFirstChild(n)
                if g then pcall(function() g:Destroy() end) end
            end
        end
    end)
    if not quiet then note("NetLens unloaded, hook restored") end
end

if CONFIG.AntiAfk then
    track(LocalPlayer.Idled:Connect(function()
        if not mine() then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end))
end

-- Value formatting: short preview for rows.
local function preview(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        if #v > CONFIG.StrLen then v = string.sub(v, 1, CONFIG.StrLen) .. ".." end
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Vector3" then
        return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("V2(%.1f,%.1f)", v.X, v.Y)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CF(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return string.format("C3(%d,%d,%d)",
            math.floor(v.R * 255), math.floor(v.G * 255), math.floor(v.B * 255))
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "Instance" then
        return "<" .. v.ClassName .. " " .. v.Name .. ">"
    elseif t == "table" then
        if depth >= 2 then return "{..}" end
        local parts = {}
        local n = 0
        for k, vv in pairs(v) do
            n = n + 1
            if n > 4 then
                parts[#parts + 1] = ".."
                break
            end
            parts[#parts + 1] = tostring(k) .. "=" .. preview(vv, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return t .. "(" .. tostring(v) .. ")"
    end
end

-- Serializer: real Lua source for the snippet.
local function serialize(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Vector3" then
        return string.format("Vector3.new(%s,%s,%s)",
            tostring(v.X), tostring(v.Y), tostring(v.Z))
    elseif t == "Vector2" then
        return string.format("Vector2.new(%s,%s)", tostring(v.X), tostring(v.Y))
    elseif t == "CFrame" then
        local c = { v:GetComponents() }
        local p = {}
        for i = 1, 12 do p[#p + 1] = tostring(c[i]) end
        return "CFrame.new(" .. table.concat(p, ",") .. ")"
    elseif t == "Color3" then
        return string.format("Color3.fromRGB(%d,%d,%d)",
            math.floor(v.R * 255), math.floor(v.G * 255), math.floor(v.B * 255))
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "Instance" then
        return "nil --[[Instance:" .. v:GetFullName() .. "]]"
    elseif t == "table" then
        if depth >= CONFIG.SnipDepth then return "{--[[depth]]}" end
        local parts = {}
        local n = 0
        for k, vv in pairs(v) do
            n = n + 1
            if n > CONFIG.SnipKeys then
                parts[#parts + 1] = "--[[truncated]]"
                break
            end
            local key
            if type(k) == "string" and string.match(k, "^[%a_][%w_]*$") then
                key = k .. " = "
            elseif type(k) == "string" then
                key = "['" .. k .. "'] = "
            else
                key = "[" .. tostring(k) .. "] = "
            end
            parts[#parts + 1] = key .. serialize(vv, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return "nil --[[" .. t .. "]]"
    end
end
-- Instance -> service-rooted path expression.
local function instPath(inst)
    local chain = {}
    local cur = inst
    while cur and cur ~= game do
        chain[#chain + 1] = cur
        cur = cur.Parent
    end
    local svc = chain[#chain]
    local expr = "game"
    if svc then
        local ok, sname = pcall(function() return svc.ClassName end)
        if ok and (svc.ClassName == "Workspace" or svc == workspace) then
            expr = "workspace"
        else
            local cls = svc.ClassName
            if cls == "ReplicatedStorage" or cls == "Players"
                or cls == "Lighting" or cls == "StarterGui"
                or cls == "StarterPack" or cls == "StarterPlayer"
                or cls == "ServerStorage" or cls == "ServerScriptService"
                or cls == "ReplicatedFirst" then
                expr = "game:GetService(\"" .. cls .. "\")"
            else
                expr = "game." .. svc.Name
            end
        end
    end
    for i = #chain - 1, 1, -1 do
        local nm = chain[i].Name
        if string.match(nm, "^[%a_][%w_]*$") then
            expr = expr .. "." .. nm
        else
            expr = expr .. "[\"" .. nm .. "\"]"
        end
    end
    return expr
end

-- Log store.
local entries = {}     -- ordered entry list
local byKey = {}        -- signature -> entry (merge mode)
local blacklist = {}    -- remote path -> true
local totalCalls = 0
local remoteSet = {}
local rows = {}         -- entry -> row frame
local listFrame = nil
local subLabel = nil

local function statsText()
    local n = 0
    for _ in pairs(remoteSet) do n = n + 1 end
    return "NETLENS v1.0.0  |  " .. tostring(n) .. " remotes  |  " ..
        tostring(totalCalls) .. " calls"
end

local function refreshStats()
    if subLabel then
        pcall(function() subLabel.Text = statsText() end)
    end
end

local function pruneRows()
    while #entries > CONFIG.MaxRows do
        local e = table.remove(entries, 1)
        byKey[e.key] = nil
        local r = rows[e]
        rows[e] = nil
        if r then pcall(function() r:Destroy() end) end
    end
end

local function rowText(e)
    local clock = os.date("%X")
    return clock .. "  " .. e.method .. "  " .. e.name ..
        (e.count > 1 and ("  x" .. tostring(e.count)) or "")
end

local function mountRow(e)
    if not listFrame then return end
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 48)
    row.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    row.BorderSizePixel = 0
    row.Parent = listFrame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = row

    local tap = Instance.new("TextButton")
    tap.Size = UDim2.new(1, -52, 1, 0)
    tap.Position = UDim2.new(0, 0, 0, 0)
    tap.BackgroundTransparency = 1
    tap.Text = ""
    tap.AutoButtonColor = false
    tap.Parent = row

    local l1 = Instance.new("TextLabel")
    l1.Size = UDim2.new(1, -8, 0, 20)
    l1.Position = UDim2.new(0, 8, 0, 4)
    l1.BackgroundTransparency = 1
    l1.Font = Enum.Font.Code
    l1.TextSize = 11
    l1.TextXAlignment = Enum.TextXAlignment.Left
    l1.TextColor3 = Color3.fromRGB(235, 235, 242)
    l1.TextTruncate = Enum.TextTruncate.AtEnd
    l1.Text = rowText(e)
    l1.Parent = tap

    local l2 = Instance.new("TextLabel")
    l2.Size = UDim2.new(1, -8, 0, 16)
    l2.Position = UDim2.new(0, 8, 0, 26)
    l2.BackgroundTransparency = 1
    l2.Font = Enum.Font.Code
    l2.TextSize = 10
    l2.TextXAlignment = Enum.TextXAlignment.Left
    l2.TextColor3 = Color3.fromRGB(150, 155, 175)
    l2.TextTruncate = Enum.TextTruncate.AtEnd
    l2.Text = e.preview
    l2.Parent = tap

    local bl = Instance.new("TextButton")
    bl.Size = UDim2.new(0, 40, 0, 28)
    bl.AnchorPoint = Vector2.new(1, 0.5)
    bl.Position = UDim2.new(1, -6, 0.5, 0)
    bl.BackgroundColor3 = Color3.fromRGB(46, 24, 26)
    bl.BorderSizePixel = 0
    bl.Font = Enum.Font.Code
    bl.TextSize = 10
    bl.TextColor3 = Color3.fromRGB(255, 170, 170)
    bl.Text = "BL"
    bl.AutoButtonColor = true
    bl.Parent = row
    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 7)
    bc.Parent = bl

    e.row1 = l1
    e.row2 = l2
    rows[e] = row
    return row, tap, bl
end

local pressBegan, pressEnded -- forward decls (UI section assigns)

local function wireRow(e, row, tap, bl, dispName)
    if not (tap and bl and pressBegan and pressEnded) then return end
    track(tap.InputBegan:Connect(pressBegan))
    track(tap.InputEnded:Connect(function(input)
        if pressEnded(input) then
            local ok = pcall(function()
                if type(setclipboard) == "function" then
                    setclipboard(e.snippet)
                else
                    error("no clipboard")
                end
            end)
            note(ok and "Snippet copied" or "Copy failed on this executor")
            pcall(function()
                row.BackgroundColor3 = Color3.fromRGB(34, 48, 40)
                task.delay(0.25, function()
                    if row.Parent then
                        row.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
                    end
                end)
            end)
        end
    end))
    track(bl.MouseButton1Click:Connect(function()
        blacklist[e.path] = true
        for i = #entries, 1, -1 do
            if entries[i].path == e.path then
                local dead = table.remove(entries, i)
                byKey[dead.key] = nil
                local r = rows[dead]
                rows[dead] = nil
                if r then pcall(function() r:Destroy() end) end
            end
        end
        refreshStats()
        note("Blacklisted " .. dispName)
    end))
end

local function logCall(inst, method, args)
    if not mine() or state.paused then return end
    local path = instPath(inst)
    if blacklist[path] then return end
    local n = #args
    if state.argsOnly and n == 0 then return end
    totalCalls = totalCalls + 1
    remoteSet[path] = true

    local parts = {}
    for i = 1, math.min(n, 6) do
        parts[#parts + 1] = preview(args[i])
    end
    local argsPrev = table.concat(parts, ", ")
    if n > 6 then argsPrev = argsPrev .. ", ..+" .. tostring(n - 6) end
    local caller = "?"
    pcall(function()
        local cs = getcallingscript and getcallingscript()
        if cs then caller = cs:GetFullName() end
    end)

    local key
    if state.merge then
        key = method .. "|" .. path .. "|" .. argsPrev
    else
        key = method .. "|" .. path .. "|" .. tostring(totalCalls)
    end
    local e = byKey[key]
    if e then
        e.count = e.count + 1
        if e.row1 then
            pcall(function()
                e.row1.Text = rowText(e)
                e.row2.Text = e.preview
            end)
        end
        refreshStats()
        return
    end

    -- Build paste-ready snippet.
    local sargs = {}
    for i = 1, n do sargs[#sargs + 1] = serialize(args[i]) end
    local call = method == "FireServer" and ":FireServer(unpack(args))"
        or ":InvokeServer(unpack(args))"
    local snippet = "local args = { " .. table.concat(sargs, ", ") .. " }\n" ..
        path .. call

    e = {
        key = key, method = method, path = path, name = inst.Name,
        count = 1, preview = argsPrev .. "   <- " .. caller,
        snippet = snippet, row1 = nil, row2 = nil,
    }
    byKey[key] = e
    entries[#entries + 1] = e
    pruneRows()
    local row, tap, bl = mountRow(e)
    wireRow(e, row, tap, bl, inst.Name)
    refreshStats()
end

-- The hook: single interception point, everything else passes through.
pcall(function()
    if type(hookmetamethod) ~= "function" then return end
    local wrap = newcclosure or function(f) return f end
    oldNC = hookmetamethod(game, "__namecallmethod", wrap(function(self, ...)
        local method = ""
        pcall(function()
            if type(getnamecallmethod) == "function" then
                method = getnamecallmethod()
            end
        end)
        if method == "FireServer" or method == "InvokeServer" then
            local okClass = false
            pcall(function()
                okClass = self:IsA("RemoteEvent") or self:IsA("RemoteFunction")
            end)
            if okClass then
                pcall(logCall, self, method, { ... })
            end
        end
        return oldNC(self, ...)
    end))
    if oldNC == nil then oldNC = nil end
end)

-- UI (Fluent-style, landscape, grab-anywhere).
local TweenService = game:GetService("TweenService")

local ACCENT = Color3.fromRGB(124, 200, 255)
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

local dragging, dragStart, startPos, moved = false, nil, nil, false
local mainRef = nil
local function isTouch(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement
end
pressBegan = function(input)
    if not isTouch(input) or dragging or not mainRef then return end
    dragging = true
    moved = false
    dragStart = input.Position
    startPos = mainRef.Position
end
pressEnded = function(input)
    if not isTouch(input) then return false end
    if not dragging then return false end
    dragging = false
    pcall(function()
        local cam = workspace.CurrentCamera
        local vs = (cam and cam.ViewportSize) or Vector2.new(800, 600)
        local p = mainRef.Position
        local w = mainRef.AbsoluteSize.X
        local h = mainRef.AbsoluteSize.Y
        mainRef.Position = UDim2.new(0,
            math.max(-w + 80, math.min(p.X.Offset, vs.X - 80)), 0,
            math.max(-h + 60, math.min(p.Y.Offset, vs.Y - 60)))
    end)
    return not moved
end

local function buildEmblem(parent, panel)
    local pad = Instance.new("TextButton")
    pad.Name = "NetLensEmblem"
    pad.Size = UDim2.new(0, 96, 0, 96)
    pad.Position = UDim2.new(1, -112, 1, -180)
    pad.BackgroundTransparency = 1
    pad.Text = ""
    pad.AutoButtonColor = false
    pad.Active = true
    pad.Selectable = false
    pad.Parent = parent

    local emb = Instance.new("TextLabel")
    emb.Size = UDim2.new(0, 56, 0, 56)
    emb.Position = UDim2.new(0.5, -28, 0.5, -28)
    emb.BackgroundColor3 = Color3.fromRGB(20, 26, 34)
    emb.BorderSizePixel = 0
    emb.Font = Enum.Font.Code
    emb.TextSize = 16
    emb.TextColor3 = Color3.fromRGB(245, 245, 250)
    emb.Text = "NL"
    emb.Parent = pad
    round(emb, 28)

    local ring = Instance.new("UIStroke")
    ring.Color = Color3.fromRGB(200, 200, 210)
    ring.Thickness = 2
    ring.Parent = emb

    local visible = true
    local downPos, startPos2, moved2 = nil, nil, false
    track(pad.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            downPos = input.Position
            startPos2 = pad.Position
            moved2 = false
            tw(emb, { Size = UDim2.new(0, 48, 0, 48),
                Position = UDim2.new(0.5, -24, 0.5, -24) }, 0.12)
        end
    end))
    track(pad.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            tw(emb, { Size = UDim2.new(0, 56, 0, 56),
                Position = UDim2.new(0.5, -28, 0.5, -28) }, 0.18,
                Enum.EasingStyle.Back)
            if not moved2 and downPos then
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
    end))
    track(game:GetService("UserInputService").InputChanged:Connect(function(input)
        if downPos
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - downPos
            if d.Magnitude > 8 then moved2 = true end
            if moved2 then
                pad.Position = UDim2.new(startPos2.X.Scale,
                    startPos2.X.Offset + d.X, startPos2.Y.Scale,
                    startPos2.Y.Offset + d.Y)
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
    gui.Name = "NetLens"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local PW, fullH = 560, 330
    local main = Instance.new("CanvasGroup")
    main.Name = "Panel"
    main.Position = UDim2.new(0, 16, 0, 60)
    main.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.GroupTransparency = 1
    main.Parent = gui
    round(main, 14)
    stroke(main, Color3.fromRGB(80, 100, 130), 0.4)
    mainRef = main

    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, 46)
    head.BackgroundTransparency = 1
    head.Text = ""
    head.AutoButtonColor = false
    head.Parent = main

    local badge = Instance.new("TextLabel")
    badge.Size = UDim2.new(0, 30, 0, 30)
    badge.Position = UDim2.new(0, 12, 0.5, -15)
    badge.BackgroundColor3 = Color3.fromRGB(24, 32, 46)
    badge.BorderSizePixel = 0
    badge.Font = Enum.Font.Code
    badge.TextSize = 12
    badge.TextColor3 = ACCENT
    badge.Text = "NL"
    badge.Parent = head
    round(badge, 9)
    stroke(badge, ACCENT, 0.45)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -92, 0, 20)
    title.Position = UDim2.new(0, 50, 0, 5)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = INK
    title.Text = "NETLENS"
    title.Parent = head

    subLabel = Instance.new("TextLabel")
    subLabel.Size = UDim2.new(1, -92, 0, 14)
    subLabel.Position = UDim2.new(0, 50, 0, 26)
    subLabel.BackgroundTransparency = 1
    subLabel.Font = Enum.Font.Code
    subLabel.TextSize = 10
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.TextColor3 = DIM
    subLabel.Text = statsText()
    subLabel.Parent = head

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

    local toolbar = Instance.new("Frame")
    toolbar.Size = UDim2.new(1, -24, 0, 76)
    toolbar.Position = UDim2.new(0, 12, 0, 50)
    toolbar.BackgroundTransparency = 1
    toolbar.Parent = main

    local function toolBtn(x, w, label, cb)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, w, 0, 30)
        btn.Position = UDim2.new(0, x, 0, 0)
        btn.BackgroundColor3 = CARD2
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.Code
        btn.TextSize = 11
        btn.TextColor3 = INK
        btn.Text = label
        btn.AutoButtonColor = false
        btn.Parent = toolbar
        round(btn, 8)
        stroke(btn, Color3.fromRGB(70, 76, 100), 0.5)
        track(btn.InputBegan:Connect(pressBegan))
        track(btn.InputEnded:Connect(function(input)
            if pressEnded(input) then cb(btn) end
        end))
        return btn
    end

    local bw = (PW - 24 - 16) / 3
    toolBtn(0, bw, "PAUSE", function(btn)
        state.paused = not state.paused
        btn.Text = state.paused and "RESUME" or "PAUSE"
        note(state.paused and "Capture paused" or "Capture resumed")
    end)
    toolBtn(bw + 8, bw, "CLEAR", function()
        entries = {}
        byKey = {}
        rows = {}
        totalCalls = 0
        remoteSet = {}
        if listFrame then
            for _, ch in ipairs(listFrame:GetChildren()) do
                if ch:IsA("Frame") then
                    pcall(function() ch:Destroy() end)
                end
            end
        end
        refreshStats()
    end)
    toolBtn(2 * (bw + 8), bw, "COPY ALL", function()
        local lines = {}
        for _, e in ipairs(entries) do
            lines[#lines + 1] = "-- " .. rowText(e) .. "\n" .. e.snippet
        end
        local ok = pcall(function()
            if type(setclipboard) == "function" then
                setclipboard(table.concat(lines, "\n\n"))
            else
                error("no clipboard")
            end
        end)
        note(ok and (#entries .. " snippets copied") or "Copy failed")
    end)

    local function miniToggle(x, w, label, initial, cb)
        local card = Instance.new("TextButton")
        card.Size = UDim2.new(0, w, 0, 32)
        card.Position = UDim2.new(0, x, 0, 38)
        card.BackgroundColor3 = CARD
        card.BorderSizePixel = 0
        card.Text = ""
        card.AutoButtonColor = false
        card.Parent = toolbar
        round(card, 8)
        stroke(card, Color3.fromRGB(55, 60, 78), 0.55)
        local lb = Instance.new("TextLabel")
        lb.Size = UDim2.new(1, -58, 1, 0)
        lb.Position = UDim2.new(0, 10, 0, 0)
        lb.BackgroundTransparency = 1
        lb.Font = Enum.Font.Code
        lb.TextSize = 11
        lb.TextXAlignment = Enum.TextXAlignment.Left
        lb.TextColor3 = INK
        lb.Text = label
        lb.Parent = card
        local sw = Instance.new("Frame")
        sw.Size = UDim2.new(0, 40, 0, 22)
        sw.AnchorPoint = Vector2.new(1, 0.5)
        sw.Position = UDim2.new(1, -8, 0.5, 0)
        sw.BorderSizePixel = 0
        sw.Parent = card
        round(sw, 11)
        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 16, 0, 16)
        knob.AnchorPoint = Vector2.new(0, 0.5)
        knob.Position = UDim2.new(0, 3, 0.5, 0)
        knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
        knob.BorderSizePixel = 0
        knob.Parent = sw
        round(knob, 8)
        local on = initial
        local function paint(animate)
            local swC = on and ACCENT or Color3.fromRGB(48, 52, 68)
            local kx = on and UDim2.new(1, -19, 0.5, 0)
                or UDim2.new(0, 3, 0.5, 0)
            if animate then
                tw(sw, { BackgroundColor3 = swC }, 0.2)
                tw(knob, { Position = kx }, 0.22, Enum.EasingStyle.Back)
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
    local cw = (PW - 24 - 8) / 2
    miniToggle(0, cw, "Merge dupes", state.merge,
        function(v) state.merge = v end)
    miniToggle(cw + 8, cw, "Args only", state.argsOnly,
        function(v) state.argsOnly = v end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -24, 0, 178)
    scroll.Position = UDim2.new(0, 12, 0, 134)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = main
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll
    listFrame = scroll

    track(game:GetService("UserInputService").InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local d = input.Position - dragStart
        if d.Magnitude > 10 then moved = true end
        if moved and mainRef then
            mainRef.Position = UDim2.new(startPos.X.Scale,
                startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(game:GetService("UserInputService").InputEnded:Connect(function(input)
        pressEnded(input)
    end))
    track(head.InputBegan:Connect(pressBegan))
    track(head.InputEnded:Connect(pressEnded))

    main.Size = UDim2.new(0, PW, 0, fullH)
    local collapsed = false
    track(mini.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        mini.Text = collapsed and "+" or "-"
        tw(main, { Size = collapsed and UDim2.new(0, PW, 0, 46)
            or UDim2.new(0, PW, 0, fullH) }, 0.3,
            Enum.EasingStyle.Quart)
    end))

    buildEmblem(gui, main)

    for _, e in ipairs(entries) do
        if not rows[e] then
            local erow, etap, ebl = mountRow(e)
            wireRow(e, erow, etap, ebl, e.name)
        end
    end
    refreshStats()

    local endPos = main.Position
    main.Position = UDim2.new(endPos.X.Scale, endPos.X.Offset,
        endPos.Y.Scale, endPos.Y.Offset + 24)
    main.Visible = true
    tw(main, { GroupTransparency = 0 }, 0.3)
    tw(main, { Position = endPos }, 0.35, Enum.EasingStyle.Back)
    return true
end

if not buildUI() then
    note("UI failed to mount, hook still active")
end

if oldNC == nil then
    note("Hook failed on this executor")
else
    note("NetLens armed. Do an action in-game.")
end

return true
