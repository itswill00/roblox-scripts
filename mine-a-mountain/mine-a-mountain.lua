-- NullShight Mine A Mountain // v0.1.0
-- Game: Mine a Mountain (125927821145949). Nambah batu/diamond otomatis:
-- auto-mine crystal terdekat + auto-sell berkala + ESP.
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
--
-- Remote teramati 2026-10-16 dari skrip publik (DonnieAzoff dkk):
--   Remotes.DigRequest:FireServer(pickName, Vector3)
--   Remotes.SellRequest:FireServer("all")   (sesudah GoHome "sell")
--   Remotes.GoHome:FireServer("sell" | "home")
--   Remotes.CrystalHoldComplete:FireServer(crystalModel)
-- Kalau game update dan ada yang mati, mapping ulang via SimpleSpy/Dex,
-- yang diganti cuma CONFIG di bawah.

local CONFIG = {
    DigRemote = "Remotes.DigRequest",
    SellRemote = "Remotes.SellRequest",
    SellArgs = { "all" },
    GoRemote = "Remotes.GoHome",
    GoSellArgs = { "sell" },
    HoldRemote = "Remotes.CrystalHoldComplete",
    CrystalContainers = { "DroppedCrystals", "Crystals" },
    AutoMine = true,
    MineDelay = 0.25,      -- jeda antar burst
    Burst = 3,             -- FireServer per burst (hemat, tetap tembus)
    AutoCollect = true,    -- fire prompt + hold-complete di target
    AutoSell = true,
    SellInterval = 120,    -- detik antar auto-sell
    OreESP = true,
    MinValue = 0,          -- filter ESP + target (0 = semua)
    EspMax = 40,           -- cap billboard biar HP kentang aman
    EspRefresh = 2,        -- detik antar refresh ESP
    AntiAfk = true,
    FpsBoost = false,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

local state = {
    autoMine = CONFIG.AutoMine,
    autoCollect = CONFIG.AutoCollect,
    autoSell = CONFIG.AutoSell,
    oreESP = CONFIG.OreESP,
}

-- Unload registry: semua koneksi + loop cek ini. Reload dua kali aman.
local alive = true
local conns = {}
local function track(c)
    conns[#conns + 1] = c
    return c
end
do
    pcall(function()
        local root = (gethui and gethui()) or game:GetService("CoreGui")
        local old = root:FindFirstChild("NullShightMine")
        if old then old:Destroy() end
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
    state.autoMine = false
    state.autoSell = false
    state.autoCollect = false
    state.oreESP = false
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function()
        local root = (gethui and gethui()) or game:GetService("CoreGui")
        local g = root:FindFirstChild("NullShightMine")
        if g then g:Destroy() end
    end)
    if not quiet then note("NullShight unloaded") end
end

-- Anti-AFK generik.
if CONFIG.AntiAfk then
    track(LocalPlayer.Idled:Connect(function()
        if not alive then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end))
end

-- FPS boost opsional buat HP kentang.
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

-- Resolve remote via dotted path ("Remotes.DigRequest") dari ReplicatedStorage.
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

local digRemote = findRemote(CONFIG.DigRemote)
local sellRemote = findRemote(CONFIG.SellRemote)
local goRemote = findRemote(CONFIG.GoRemote)
local holdRemote = findRemote(CONFIG.HoldRemote)
if not digRemote then
    note("Dig remote not found, fallback tool/prompt only")
end

local function fireRemote(remote, args)
    if not remote then return false end
    return pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(unpack(args or {}))
        else
            remote:InvokeServer(unpack(args or {}))
        end
    end)
end

-- Pickaxe yang lagi dipegang: Tool ber-atribut IsPickaxe/DigPower, else Tool apa aja.
local function heldPick()
    local char = LocalPlayer.Character
    if not char then return nil end
    local best = nil
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then
            local ok1, isPick = pcall(t.GetAttribute, t, "IsPickaxe")
            local ok2, power = pcall(t.GetAttribute, t, "DigPower")
            if (ok1 and isPick) or (ok2 and power ~= nil) then
                return t
            end
            if not best then best = t end
        end
    end
    return best
end

local function getRoot()
    local char = LocalPlayer.Character
    if char then
        return char:FindFirstChild("HumanoidRootPart")
    end
    return nil
end

local function attrNum(inst, name)
    local ok, v = pcall(inst.GetAttribute, inst, name)
    if ok and tonumber(v) then return tonumber(v) end
    return 0
end

local function shortNum(n)
    n = tonumber(n) or 0
    if n < 1000 then return tostring(math.floor(n + 0.5)) end
    local suf = { "k", "M", "B", "T", "Qa" }
    local i = 0
    while n >= 1000 and i < #suf do
        n = n / 1000
        i = i + 1
    end
    return string.format("%.2f%s", n, suf[i])
end

-- Satu crystal = Model/part yang punya atribut Value. Posisi = pivot/part.
local function targetPos(inst)
    if inst:IsA("Model") then
        local ok, cf = pcall(inst.GetPivot, inst)
        if ok then return cf.Position end
    end
    if inst:IsA("BasePart") then
        return inst.Position
    end
    local part = inst:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.Position end
    return nil
end

-- Scan target termurah: container game dulu, fallback seluruh workspace.
-- Di-cache 1 detik biar HP nggak ngos-ngosan.
local cachedTarget, cachedAt = nil, 0
local function findTarget()
    local now = os.clock()
    local root = getRoot()
    if not root then return nil end
    if cachedTarget and cachedTarget.Parent and now - cachedAt < 1 then
        return cachedTarget
    end
    cachedTarget, cachedAt = nil, now
    local best, bestDist = nil, math.huge
    local function consider(inst)
        local v = attrNum(inst, "Value")
        if v < CONFIG.MinValue then return end
        local pos = targetPos(inst)
        if not pos then return end
        local d = (pos - root.Position).Magnitude
        if d < bestDist then
            best, bestDist = inst, d
        end
    end
    for _, cname in ipairs(CONFIG.CrystalContainers) do
        local c = workspace:FindFirstChild(cname)
        if c then
            for _, inst in ipairs(c:GetDescendants()) do
                if inst:IsA("Model") or inst:IsA("BasePart") then
                    local ok, v = pcall(inst.GetAttribute, inst, "Value")
                    if ok and tonumber(v) then consider(inst) end
                end
            end
        end
    end
    if not best then
        -- Fallback: apa pun ber-Value di workspace (boulder, dsb).
        for _, inst in ipairs(workspace:GetDescendants()) do
            if inst:IsA("Model") then
                local ok, v = pcall(inst.GetAttribute, inst, "Value")
                if ok and tonumber(v) then consider(inst) end
            end
        end
    end
    cachedTarget = best
    return best
end

-- Burst DigRequest ke posisi target.
local function fireDig(pos)
    if not digRemote or not pos then return false end
    local pick = heldPick()
    if not pick then return false end
    local okAll = false
    for _ = 1, CONFIG.Burst do
        local ok = fireRemote(digRemote, { pick.Name, pos })
        if ok then okAll = true end
    end
    return okAll
end

-- Fallback: ayun tool + sentuh prompt di target.
local function swingFallback(target)
    local did = false
    local pick = heldPick()
    if pick then
        did = pcall(function() pick:Activate() end) or did
    end
    if target and state.autoCollect then
        pcall(function()
            local prompt = target:FindFirstChildOfClass("ProximityPrompt")
            if not prompt then
                prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
            end
            if prompt then
                fireproximityprompt(prompt)
                did = true
            end
        end)
        if holdRemote and target:IsA("Model") then
            if fireRemote(holdRemote, { target }) then did = true end
        end
    end
    return did
end

-- Sell: teleport ke zona sell, jual semua, balik ke posisi semula.
local sellBusy = false
local function doSell()
    if sellBusy then return end
    sellBusy = true
    task.spawn(function()
        local root = getRoot()
        local back = root and root.CFrame or nil
        fireRemote(goRemote, CONFIG.GoSellArgs)
        task.wait(0.8)
        fireRemote(sellRemote, CONFIG.SellArgs)
        task.wait(0.5)
        if back then
            local r = getRoot()
            if r then pcall(function() r.CFrame = back end) end
        end
        sellBusy = false
    end)
end

note("NullShight Mine loaded. AutoMine " ..
    (state.autoMine and "ON" or "OFF"))

task.spawn(function()
    while alive do
        if state.autoMine then
            local target = findTarget()
            local pos = target and targetPos(target) or nil
            local fired = pos and fireDig(pos) or false
            if not fired then
                swingFallback(target)
            elseif target and state.autoCollect then
                swingFallback(target)
            end
        end
        task.wait(CONFIG.MineDelay)
    end
end)

task.spawn(function()
    while alive do
        task.wait(CONFIG.SellInterval)
        if alive and state.autoSell then
            doSell()
        end
    end
end)

-- ESP: billboard nama + value di crystal, di-cap biar enteng.
local espFolder = nil
pcall(function()
    local root = (gethui and gethui()) or game:GetService("CoreGui")
    espFolder = Instance.new("Folder")
    espFolder.Name = "NullShightMineESP"
    espFolder.Parent = root
end)

local function clearESP()
    if espFolder then
        for _, c in ipairs(espFolder:GetChildren()) do
            pcall(function() c:Destroy() end)
        end
    end
end

local function paintESP()
    clearESP()
    if not espFolder then return end
    local root = getRoot()
    if not root then return end
    local list = {}
    for _, cname in ipairs(CONFIG.CrystalContainers) do
        local c = workspace:FindFirstChild(cname)
        if c then
            for _, inst in ipairs(c:GetChildren()) do
                local ok, v = pcall(inst.GetAttribute, inst, "Value")
                if ok and tonumber(v) and tonumber(v) >= CONFIG.MinValue then
                    list[#list + 1] = inst
                end
            end
        end
    end
    table.sort(list, function(a, b)
        local ra = getRoot()
        if not ra then return false end
        local pa, pb = targetPos(a), targetPos(b)
        if not pa then return false end
        if not pb then return true end
        return (pa - ra.Position).Magnitude < (pb - ra.Position).Magnitude
    end)
    for i = 1, math.min(#list, CONFIG.EspMax) do
        local inst = list[i]
        local adorn = inst:IsA("BasePart") and inst
            or inst:FindFirstChildWhichIsA("BasePart", true)
        if adorn then
            pcall(function()
                local bb = Instance.new("BillboardGui")
                bb.Size = UDim2.new(0, 120, 0, 36)
                bb.StudsOffset = Vector3.new(0, 3, 0)
                bb.AlwaysOnTop = true
                local tl = Instance.new("TextLabel")
                tl.Size = UDim2.new(1, 0, 1, 0)
                tl.BackgroundTransparency = 1
                tl.Font = Enum.Font.Code
                tl.TextSize = 13
                tl.TextColor3 = Color3.fromRGB(120, 255, 140)
                tl.TextStrokeTransparency = 0.3
                local nm = inst.Name
                pcall(function()
                    local cn = inst:GetAttribute("CrystalName")
                    if type(cn) == "string" and cn ~= "" then nm = cn end
                end)
                tl.Text = nm .. "\n$" .. shortNum(attrNum(inst, "Value"))
                tl.Parent = bb
                bb.Parent = espFolder
                bb.Adornee = adorn
            end)
        end
    end
end

task.spawn(function()
    while alive do
        if state.oreESP then
            pcall(paintESP)
        elseif espFolder and #espFolder:GetChildren() > 0 then
            clearESP()
        end
        task.wait(CONFIG.EspRefresh)
    end
end)

-- Panel monokrom + emblem NS. Touch-first kayak skrip Slice.
local function buildEmblem(parent, panel)
    local pad = Instance.new("TextButton")
    pad.Name = "EmblemPad"
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
    emb.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
    emb.BorderSizePixel = 0
    emb.Font = Enum.Font.Code
    emb.TextSize = 18
    emb.TextColor3 = Color3.fromRGB(245, 245, 250)
    emb.Text = "NS"
    emb.Parent = pad

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = emb

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
        end
    end))
    track(pad.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            if not moved then
                visible = not visible
                panel.Visible = visible
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
            if d.Magnitude > 10 then moved = true end
            if moved then
                pad.Position = UDim2.new(startPos.X.Scale,
                    startPos.X.Offset + d.X, startPos.Y.Scale,
                    startPos.Y.Offset + d.Y)
            end
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
    gui.Name = "NullShightMine"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local main = Instance.new("Frame")
    main.Name = "Panel"
    main.Size = UDim2.new(0, 230, 0, 268)
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
    title.Text = "  NULLSHIGHT // MINE"
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
    track(mini.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        body.Visible = not collapsed
        main.Size = collapsed and UDim2.new(0, 230, 0, 30)
            or UDim2.new(0, 230, 0, 268)
        mini.Text = collapsed and "+" or "_"
    end))

    local dragging, dragStart, startPos = false, nil, nil
    track(title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end))
    track(title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))

    local y = 6
    local function row(labelText, initial, cb)
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
            btn.Text = (on and "[ ON ]  " or "[ OFF ] ") .. labelText
        end
        paint()
        track(btn.MouseButton1Click:Connect(function()
            on = not on
            paint()
            cb(on)
        end))
        btn.Parent = body
        y = y + 36
    end

    row("Auto Mine", state.autoMine, function(v) state.autoMine = v end)
    row("Auto Collect", state.autoCollect, function(v) state.autoCollect = v end)
    row("Auto Sell", state.autoSell, function(v) state.autoSell = v end)
    row("Ore ESP", state.oreESP, function(v)
        state.oreESP = v
        if not v then clearESP() end
    end)

    local sellBtn = Instance.new("TextButton")
    sellBtn.Size = UDim2.new(1, -16, 0, 30)
    sellBtn.Position = UDim2.new(0, 8, 0, y)
    sellBtn.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
    sellBtn.BorderColor3 = Color3.fromRGB(90, 90, 100)
    sellBtn.BorderSizePixel = 1
    sellBtn.Font = Enum.Font.Code
    sellBtn.TextSize = 12
    sellBtn.TextColor3 = Color3.fromRGB(235, 235, 240)
    sellBtn.Text = "SELL NOW"
    sellBtn.Parent = body
    y = y + 36
    track(sellBtn.MouseButton1Click:Connect(function()
        doSell()
        note("Selling...")
    end))

    local killBtn = Instance.new("TextButton")
    killBtn.Size = UDim2.new(1, -16, 0, 30)
    killBtn.Position = UDim2.new(0, 8, 0, y)
    killBtn.BackgroundColor3 = Color3.fromRGB(64, 20, 20)
    killBtn.BorderColor3 = Color3.fromRGB(200, 90, 90)
    killBtn.BorderSizePixel = 1
    killBtn.Font = Enum.Font.Code
    killBtn.TextSize = 12
    killBtn.TextColor3 = Color3.fromRGB(255, 180, 180)
    killBtn.Text = "UNLOAD SCRIPT"
    killBtn.Parent = body
    killBtn.MouseButton1Click:Connect(function()
        unload()
    end)

    buildEmblem(gui, main)
    return true
end

if not buildUI() then
    note("UI failed to mount, core still running")
end

return true
