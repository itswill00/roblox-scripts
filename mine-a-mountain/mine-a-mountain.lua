-- NullShight Mine A Mountain // v0.2.0
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
    ESPMaxDist = 0,        -- cull jarak ESP (studs, 0 = tanpa batas)
    ESPPerTier = 5,        -- label termahal per tier (0 = semua, rawan lag)
    ESPShowLowest = true,  -- tandai 1 termurah per tier (tag LOW)
    -- Kategori tier: true = tampil, false = disembunyiin. Warna bebas ganti.
    ESPShowTier = {
        Common = false,
        Uncommon = true,
        Rare = true,
        Epic = true,
        Legendary = true,
        Mythic = true,
    },
    TierColors = {
        Common = Color3.fromRGB(170, 170, 170),
        Uncommon = Color3.fromRGB(110, 255, 130),
        Rare = Color3.fromRGB(110, 180, 255),
        Epic = Color3.fromRGB(200, 130, 255),
        Legendary = Color3.fromRGB(255, 190, 90),
        Mythic = Color3.fromRGB(255, 100, 120),
        Unknown = Color3.fromRGB(235, 235, 240),
    },
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
    showLowest = CONFIG.ESPShowLowest,
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
        local e = root:FindFirstChild("NullShightMineESP")
        if e then e:Destroy() end
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

-- ESP per-tier + anti-lag:
--   * Label dikelompokkan per tier (warna beda tiap tier, atur di CONFIG).
--   * Per tier tampil yang termahal (ESPPerTier) + 1 termurah (tag LOW).
--   * Billboard dipakai ulang dari pool (nol create/destroy per refresh).
--   * Cull jarak opsional (ESPMaxDist), scan cuma tiap EspRefresh detik.
local TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local TIER_ORDER = { "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common", "Unknown" }

local function tierOf(inst)
    local ok, name = pcall(inst.GetAttribute, inst, "TierName")
    if ok and type(name) == "string" and name ~= "" then return name end
    local ok2, t = pcall(inst.GetAttribute, inst, "Tier")
    t = tonumber(t) or 0
    if TIER_NAMES[t] then return TIER_NAMES[t] end
    return "Unknown"
end

local function crystalLabel(inst)
    local nm = inst.Name
    pcall(function()
        local cn = inst:GetAttribute("CrystalName")
        if type(cn) == "string" and cn ~= "" then nm = cn end
    end)
    return nm
end

local espFolder = nil
pcall(function()
    local root = (gethui and gethui()) or game:GetService("CoreGui")
    espFolder = Instance.new("Folder")
    espFolder.Name = "NullShightMineESP"
    espFolder.Parent = root
end)

local espPool = {}
local function getBB(i)
    local bb = espPool[i]
    if bb and bb.Parent then
        bb.Visible = true
        return bb
    end
    bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 130, 0, 40)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    local tl = Instance.new("TextLabel")
    tl.Name = "L"
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.BackgroundTransparency = 1
    tl.Font = Enum.Font.Code
    tl.TextSize = 13
    tl.TextStrokeTransparency = 0.3
    tl.Parent = bb
    bb.Parent = espFolder
    espPool[i] = bb
    return bb
end

local function hideESP()
    for _, bb in ipairs(espPool) do
        pcall(function() bb.Visible = false end)
    end
end

local function clearESP()
    hideESP()
end

local function paintESP()
    if not espFolder then return end
    local root = getRoot()
    if not root then hideESP() return end
    local showTier = CONFIG.ESPShowTier or {}
    local perTier = CONFIG.ESPPerTier or 5
    local maxDist = CONFIG.ESPMaxDist or 0

    -- 1x scan: kelompokkan per tier.
    local groups = {}
    for _, cname in ipairs(CONFIG.CrystalContainers) do
        local c = workspace:FindFirstChild(cname)
        if c then
            for _, inst in ipairs(c:GetChildren()) do
                local ok, v = pcall(inst.GetAttribute, inst, "Value")
                v = ok and tonumber(v) or nil
                if v and v >= CONFIG.MinValue then
                    local tier = tierOf(inst)
                    if showTier[tier] ~= false then
                        if maxDist <= 0 then
                            local g = groups[tier]
                            if not g then g = {}; groups[tier] = g end
                            g[#g + 1] = inst
                        else
                            local pos = targetPos(inst)
                            if pos and (pos - root.Position).Magnitude <= maxDist then
                                local g = groups[tier]
                                if not g then g = {}; groups[tier] = g end
                                g[#g + 1] = inst
                            end
                        end
                    end
                end
            end
        end
    end

    -- Termahal dulu per tier + termurah (urutan tier sultan duluan).
    local idx = 0
    for _, tier in ipairs(TIER_ORDER) do
        local g = groups[tier]
        if g and #g > 0 then
            table.sort(g, function(a, b)
                return attrNum(a, "Value") > attrNum(b, "Value")
            end)
            local color = (CONFIG.TierColors or {})[tier]
                or Color3.fromRGB(235, 235, 240)
            local n = perTier <= 0 and #g or math.min(#g, perTier)
            for i = 1, n do
                if idx >= CONFIG.EspMax then break end
                idx = idx + 1
                local inst = g[i]
                local adorn = inst:IsA("BasePart") and inst
                    or inst:FindFirstChildWhichIsA("BasePart", true)
                if adorn then
                    local bb = getBB(idx)
                    bb.Adornee = adorn
                    local tag = (i == 1) and "[TOP] " or ("#" .. tostring(i) .. " ")
                    bb.L.Text = tag .. tier .. "\n" .. crystalLabel(inst)
                        .. " $" .. shortNum(attrNum(inst, "Value"))
                    bb.L.TextColor3 = color
                end
            end
            if state.showLowest and #g > n and idx < CONFIG.EspMax then
                local inst = g[#g]
                local adorn = inst:IsA("BasePart") and inst
                    or inst:FindFirstChildWhichIsA("BasePart", true)
                if adorn then
                    idx = idx + 1
                    local bb = getBB(idx)
                    bb.Adornee = adorn
                    bb.L.Text = "[LOW] " .. tier .. "\n" .. crystalLabel(inst)
                        .. " $" .. shortNum(attrNum(inst, "Value"))
                    bb.L.TextColor3 = Color3.fromRGB(140, 140, 150)
                end
            end
        end
        if idx >= CONFIG.EspMax then break end
    end
    for i = idx + 1, #espPool do
        pcall(function() espPool[i].Visible = false end)
    end
end

task.spawn(function()
    while alive do
        if state.oreESP then
            pcall(paintESP)
        else
            hideESP()
        end
        task.wait(CONFIG.EspRefresh)
    end
end)

-- UI v2: bahasa desain Fluent/WindUI — kartu gelap rounded, satu aksen,
-- toggle geser beranimasi, buka/tutup + collapse pakai tween, drag halus.
-- Murni Instance API (tanpa lib eksternal) biar loadstring tetap ringan.
local TweenService = game:GetService("TweenService")

local ACCENT = Color3.fromRGB(124, 140, 255)
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

-- Emblem NS melayang: pad sentuh 96px + visual gradien + pop saat ditekan.
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
    emb.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    emb.BorderSizePixel = 0
    emb.Font = Enum.Font.Code
    emb.TextSize = 18
    emb.TextColor3 = Color3.fromRGB(245, 245, 250)
    emb.Text = "NS"
    emb.Parent = pad
    round(emb, 28)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 45, 66)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 18, 26)),
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

    -- CanvasGroup = panel bisa fade utuh + collapse ter-clip rapi.
    local main = Instance.new("CanvasGroup")
    main.Name = "Panel"
    main.Position = UDim2.new(0, 16, 0, 110)
    main.BackgroundColor3 = Color3.fromRGB(16, 18, 25)
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.GroupTransparency = 1
    main.Parent = gui
    round(main, 14)
    stroke(main, Color3.fromRGB(72, 78, 100), 0.35)

    local y = 0
    -- Header: badge NS + judul + tombol minimize.
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
    badge.BackgroundColor3 = Color3.fromRGB(30, 34, 50)
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
    sub.Text = "MINE A MOUNTAIN v0.2.0"
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
    body.Size = UDim2.new(1, 0, 0, 500)
    body.Position = UDim2.new(0, 0, 0, y)
    body.BackgroundTransparency = 1
    body.Parent = main

    -- Drag header dengan lerp biar meluncur, bukan patah-patah.
    -- lastPos diupdate dari semua input biar akurat di touch maupun mouse.
    local dragging, grabOff, lastPos = false, nil, nil
    track(game:GetService("UserInputService").InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            lastPos = input.Position
        end
    end))
    track(head.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            lastPos = input.Position
            grabOff = input.Position - main.AbsolutePosition
        end
    end))
    track(head.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(game:GetService("RunService").RenderStepped:Connect(function()
        if not alive then return end
        if dragging and grabOff and lastPos then
            local guiOff = gui.AbsolutePosition
            local want = UDim2.new(0,
                lastPos.X - guiOff.X - grabOff.X, 0,
                lastPos.Y - guiOff.Y - grabOff.Y)
            local cur = main.Position
            main.Position = UDim2.new(cur.X.Scale,
                cur.X.Offset + (want.X.Offset - cur.X.Offset) * 0.45,
                cur.Y.Scale,
                cur.Y.Offset + (want.Y.Offset - cur.Y.Offset) * 0.45)
        end
    end))

    local by = 0
    local function section(text)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -32, 0, 18)
        t.Position = UDim2.new(0, 16, 0, by)
        t.BackgroundTransparency = 1
        t.Font = Enum.Font.Code
        t.TextSize = 10
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.TextColor3 = DIM
        t.Text = text
        t.Parent = body
        by = by + 22
    end

    local function toggleRow(labelText, initial, cb)
        local card = Instance.new("TextButton")
        card.Size = UDim2.new(1, -24, 0, 42)
        card.Position = UDim2.new(0, 12, 0, by)
        card.BackgroundColor3 = CARD
        card.BorderSizePixel = 0
        card.Text = ""
        card.AutoButtonColor = false
        card.Parent = body
        round(card, 10)
        stroke(card, Color3.fromRGB(55, 60, 78), 0.55)

        local lb = Instance.new("TextLabel")
        lb.Size = UDim2.new(1, -72, 1, 0)
        lb.Position = UDim2.new(0, 12, 0, 0)
        lb.BackgroundTransparency = 1
        lb.Font = Enum.Font.Code
        lb.TextSize = 12
        lb.TextXAlignment = Enum.TextXAlignment.Left
        lb.TextColor3 = INK
        lb.Text = labelText
        lb.Parent = card

        local sw = Instance.new("Frame")
        sw.Size = UDim2.new(0, 46, 0, 26)
        sw.AnchorPoint = Vector2.new(1, 0.5)
        sw.Position = UDim2.new(1, -12, 0.5, 0)
        sw.BorderSizePixel = 0
        sw.Parent = card
        round(sw, 13)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 20, 0, 20)
        knob.AnchorPoint = Vector2.new(0, 0.5)
        knob.Position = UDim2.new(0, 3, 0.5, 0)
        knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
        knob.BorderSizePixel = 0
        knob.Parent = sw
        round(knob, 10)

        local on = initial
        local function paint(animate)
            local swC = on and ACCENT or Color3.fromRGB(48, 52, 68)
            local kx = on and UDim2.new(1, -23, 0.5, 0)
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
        track(card.MouseButton1Click:Connect(function()
            on = not on
            paint(true)
            cb(on)
        end))
        by = by + 48
    end

    local function actionBtn(labelText, cb, danger)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -24, 0, 38)
        btn.Position = UDim2.new(0, 12, 0, by)
        btn.BackgroundColor3 = danger and Color3.fromRGB(52, 24, 26)
            or CARD2
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.Code
        btn.TextSize = 12
        btn.TextColor3 = danger and Color3.fromRGB(255, 175, 175) or INK
        btn.Text = labelText
        btn.AutoButtonColor = false
        btn.Parent = body
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
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                tw(btn, { BackgroundColor3 = dark }, 0.1)
            end
        end))
        track(btn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                tw(btn, { BackgroundColor3 = base }, 0.15)
            end
        end))
        track(btn.MouseButton1Click:Connect(function() cb() end))
        by = by + 44
    end

    section("  FARM")
    toggleRow("Auto Mine", state.autoMine, function(v) state.autoMine = v end)
    toggleRow("Auto Collect", state.autoCollect,
        function(v) state.autoCollect = v end)
    toggleRow("Auto Sell", state.autoSell, function(v) state.autoSell = v end)

    section("  TAMPILAN")
    toggleRow("Ore ESP", state.oreESP, function(v)
        state.oreESP = v
        if not v then clearESP() end
    end)
    toggleRow("ESP Termurah", state.showLowest,
        function(v) state.showLowest = v end)

    section("  SISTEM")
    actionBtn("FIX LAG", function()
        pcall(fpsBoost)
        CONFIG.EspMax = 15
        CONFIG.EspRefresh = 4
        CONFIG.ESPPerTier = 2
        CONFIG.ESPMaxDist = 1500
        CONFIG.Burst = 2
        clearESP()
        note("Lag fix applied")
    end)
    actionBtn("SELL NOW", function()
        doSell()
        note("Selling...")
    end)
    actionBtn("UNLOAD SCRIPT", function() unload() end, true)

    local fullH = y + by + 12
    body.Size = UDim2.new(1, 0, 0, by)
    main.Size = UDim2.new(0, 252, 0, fullH)

    local collapsed = false
    track(mini.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        mini.Text = collapsed and "+" or "-"
        tw(main, { Size = collapsed and UDim2.new(0, 252, 0, 52)
            or UDim2.new(0, 252, 0, fullH) }, 0.3,
            Enum.EasingStyle.Quart)
    end))

    buildEmblem(gui, main)

    -- Intro: panel melayang naik + fade in.
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
