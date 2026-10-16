-- NullShight Build the Pyramid // v0.3.0
-- Game: Build the Pyramid! (123720558354386). Haul loop: grab blocks at the
-- quarry, carry them to the pyramid, train speed/strength on the side.
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
--
-- Remotes mapped live 2026-10-16 (SimpleSpy, Knit 1.7.0):
--   BlockService.RF.Pickup(regionInstance)
-- Deliver + train remotes not mapped yet -> prompt fallback for delivery.
-- Map them with NetLens and only CONFIG below changes.

local CONFIG = {
    KnitIndex = "sleitnick_knit@1.7.0",
    BlockService = "BlockService",
    PickupRemote = "Pickup",             -- RF, arg: region Instance
    PickupRegion = "Regions.Region:Quarry", -- path from workspace
    DeliverService = "PyramidService",
    DeliverRemote = "Place",             -- RF, mapped 2026-10-16
    -- Observed args: {5, 4086, 7, {}}. IDs may vary per block: watch
    -- NetLens (merge OFF) while placing twice and update these.
    DeliverArgs = { 5, 4086, 7, {} },
    TrainService = "GymService",
    -- Strength = teleport to bench seat + StartBench(folderName).
    -- Speed has NO remote: training = standing on treadmill hitbox.
    -- Station discovery: Shared.Config.GymConfig (auto, like MarioHub).
    TrainStrengthRemote = "StartBench",  -- RF, mapped 2026-10-16
    StopBenchRemote = "StopBench",       -- RF, mapped 2026-10-16
    BenchStation = nil,   -- nil = auto best; or set gym folder name
    TreadStation = nil,   -- nil = auto best; or set gym folder name
    AFKService = "AFKService",
    AFKRemote = "Activity",              -- RE heartbeat, mapped 2026-10-16
    AFKDelay = 60,
    AutoFarm = false,      -- master loop: travel + pickup + slot place
    FarmDelay = 2,
    UpgradeService = "DataService",
    UpgradeRemote = "PurchaseUpgrade",   -- RF, arg: upgradeId
    AutoUpgrade = false,
    UpgradeDelay = 5,
    GiftService = "FreeGiftService",
    GiftStateRemote = "GetState",        -- RF
    GiftStepRemote = "MarkStep",         -- RF, arg: "liked"/"favorited"
    GiftClaimRemote = "Claim",           -- RF
    AutoGift = true,
    GiftDelay = 60,
    CodesService = "CodesService",
    CodesRemote = "Redeem",              -- RF, arg: code string
    ExtraCodes = { "SUNGOD", "SORRYFORUPDATEBUG", "FREECODE", "WELCOME",
        "DEADBYMELOL", "UPDATE15", "PYRAMID1500" },
    WalkSpeed = 60,
    WalkNormal = 16,
    AutoPickup = true,
    PickupDelay = 1.5,
    AutoDeliver = true,                  -- prompt fallback near the player
    DeliverDelay = 1,
    DeliverDist = 15,
    AutoTrainSpeed = false,              -- needs remote, off until mapped
    AutoTrainStrength = false,           -- needs remote, off until mapped
    TrainDelay = 2,
    AntiAfk = true,
    FpsBoost = false,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

local state = {
    autoPickup = CONFIG.AutoPickup,
    autoDeliver = CONFIG.AutoDeliver,
    autoTrainSpeed = CONFIG.AutoTrainSpeed,
    autoTrainStrength = CONFIG.AutoTrainStrength,
    autoFarm = CONFIG.AutoFarm,
    autoUpgrade = CONFIG.AutoUpgrade,
    autoGift = CONFIG.AutoGift,
    walkSpeed = false,
    noclip = false,
}

-- Generation guard: a fresh run kills the previous run's loops.
local alive = true
_G.NSBP_Gen = ((_G.NSBP_Gen or 0) + 1)
local myGen = _G.NSBP_Gen

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
            for _, n in ipairs({ "NullShightPyramid", "PyramidEmblem" }) do
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
    state.autoPickup = false
    state.autoDeliver = false
    state.autoTrainSpeed = false
    state.autoTrainStrength = false
    pcall(stopBench)
    state.walkSpeed = false
    state.noclip = false
    pcall(setHumanoidSpeed, CONFIG.WalkNormal)
    pcall(function()
        local char = LocalPlayer.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                    p.CanCollide = true
                end
            end
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
            for _, n in ipairs({ "NullShightPyramid", "PyramidEmblem" }) do
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

-- Knit resolver with cache + auto re-resolve.
local knitCache = nil
local function knitServices()
    if knitCache and knitCache.Parent then return knitCache end
    knitCache = nil
    pcall(function()
        local pkgs = ReplicatedStorage:WaitForChild("Packages", 5)
        local idx = pkgs and pkgs:FindFirstChild("_Index")
        local kn = idx and idx:FindFirstChild(CONFIG.KnitIndex)
        local k = kn and kn:FindFirstChild("knit")
        knitCache = k and k:FindFirstChild("Services") or nil
    end)
    return knitCache
end

local function knitRemote(svc, kind, name)
    if not name or name == "" then return nil end
    local svcs = knitServices()
    if not svcs then return nil end
    local s = svcs:FindFirstChild(svc)
    local f = s and s:FindFirstChild(kind)
    local r = f and f:FindFirstChild(name)
    if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then
        return r
    end
    return nil
end

local function fireKnit(svc, kind, name, args)
    local r = knitRemote(svc, kind, name)
    if not r then return false end
    return pcall(function()
        if r:IsA("RemoteEvent") then
            r:FireServer(unpack(args or {}))
        else
            r:InvokeServer(unpack(args or {}))
        end
    end)
end

-- Resolve dotted workspace path ("Regions.Region:Quarry").
-- Gym discovery: require the shared GymConfig (client-readable), then
-- resolve machine parts in the workspace gym folder by station name.
local gymCfgCache = nil
local function gymCfg()
    if gymCfgCache then return gymCfgCache end
    pcall(function()
        local shared = ReplicatedStorage:WaitForChild("Shared", 5)
        local cfg = shared and shared:WaitForChild("Config", 5)
        local mod = cfg and cfg:WaitForChild("GymConfig", 5)
        if mod then gymCfgCache = require(mod) end
    end)
    return gymCfgCache
end

local function attrStr(inst, name)
    if not inst then return nil end
    local ok, v = pcall(inst.GetAttribute, inst, name)
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

local function stationPart(g, folderName, modelKey, partKey)
    if not g or not folderName then return nil end
    local gym = workspace:FindFirstChild(g.GymFolderName)
    local st = gym and gym:FindFirstChild(folderName)
    local m = st and g[modelKey] and st:FindFirstChild(g[modelKey])
    local part = m and g[partKey] and m:FindFirstChild(g[partKey])
    if part and part:IsA("BasePart") then return part end
    return nil
end

local function sortedStations(list, key)
    local out = {}
    for _, st in ipairs(list or {}) do
        if type(st) == "table" and st.GymFolder then
            out[#out + 1] = st
        end
    end
    table.sort(out, function(a, b)
        return (tonumber(a[key]) or 0) > (tonumber(b[key]) or 0)
    end)
    return out
end

local function stopBench()
    local r = knitRemote(CONFIG.TrainService, "RF", CONFIG.StopBenchRemote)
    if r then pcall(function() r:InvokeServer() end) end
end

-- Shared modules (client-readable, like the public hubs require them).
local sharedCache = {}
local function sharedMod(...)
    local steps = { ... }
    local key = table.concat(steps, "/")
    if sharedCache[key] ~= nil then return sharedCache[key] end
    local node = nil
    pcall(function()
        node = ReplicatedStorage:WaitForChild("Shared", 5)
        for _, step in ipairs(steps) do
            node = node and node:WaitForChild(step, 5)
        end
        if node then node = require(node) end
    end)
    if type(node) ~= "table" then node = false end
    sharedCache[key] = node
    return node
end

local function readCarry()
    local mod = sharedMod("Books", "CarryState")
    if not mod then return nil end
    local ok, st = pcall(mod.read, LocalPlayer)
    if ok and type(st) == "table" then return tonumber(st.count) end
    return nil
end

local function readCapacity()
    local cfg = sharedMod("Config", "CarryConfig")
    local base = 20
    if cfg then base = tonumber(cfg.Capacity) or base end
    local ok, lv = pcall(LocalPlayer.GetAttribute, LocalPlayer, "StrengthLevel")
    if ok and tonumber(lv) then base = base + tonumber(lv) end
    return base
end

local function runtimeMod()
    return sharedMod("Placement", "PyramidRuntime")
end

local function resolveSlot(origin)
    local rt = runtimeMod()
    if not rt or type(rt.resolveNearestSlot) ~= "function" then
        return nil
    end
    local ok, slot = pcall(rt.resolveNearestSlot, origin, workspace,
        function() return false end, {})
    if ok and type(slot) == "table" and slot.layer then return slot end
    return nil
end

local function teleportTo(pos)
    local root = getRoot()
    if not root or not pos then return end
    local cf = root.CFrame
    root.CFrame = CFrame.new(pos) * (cf - cf.Position)
end

local function quarryTop()
    local region = findRegion(CONFIG.PickupRegion)
    if region and region:IsA("BasePart") then
        return region.Position + Vector3.new(0, region.Size.Y / 2 + 3, 0)
    end
    return nil
end

local function upgradeIds()
    local cat = sharedMod("Config", "UpgradeCatalog")
    local ids = {}
    if cat and type(cat.Upgrades) == "table" then
        for _, u in ipairs(cat.Upgrades) do
            if type(u) == "table" and u.Id then
                ids[#ids + 1] = u.Id
            end
        end
    end
    return ids
end

local function knownCodes()
    local out, seen = {}, {}
    local cat = sharedMod("Config", "CodesConfig")
    if cat and type(cat.Codes) == "table" then
        for code, _ in pairs(cat.Codes) do
            if type(code) == "string" and not seen[code] then
                seen[code] = true
                out[#out + 1] = code
            end
        end
    end
    for _, code in ipairs(CONFIG.ExtraCodes) do
        if not seen[code] then
            seen[code] = true
            out[#out + 1] = code
        end
    end
    return out
end

local codesRunning = false
local function redeemAll()
    if codesRunning then return end
    codesRunning = true
    task.spawn(function()
        local n = 0
        for _, code in ipairs(knownCodes()) do
            if not alive or _G.NSBP_Gen ~= myGen then break end
            local r = knitRemote(CONFIG.CodesService, "RF", CONFIG.CodesRemote)
            if r then
                local ok, reply = pcall(function()
                    return r:InvokeServer(code)
                end)
                if ok and type(reply) == "table" and reply.ok then
                    n = n + 1
                end
            end
            task.wait(1.1)
        end
        note("Codes redeemed: " .. tostring(n))
        codesRunning = false
    end)
end

local function findRegion(path)
    if not path or path == "" then return nil end
    local node = workspace
    for part in string.gmatch(path, "[^%.]+") do
        node = node:FindFirstChild(part)
        if not node then return nil end
    end
    return node
end

local function getRoot()
    local char = LocalPlayer.Character
    if char then
        return char:FindFirstChild("HumanoidRootPart")
    end
    return nil
end

-- Core loops: each feature runs its own loop, toggles are independent.
task.spawn(function()
    while alive and _G.NSBP_Gen == myGen do
        if state.autoPickup then
            local region = findRegion(CONFIG.PickupRegion)
            if region then
                pcall(fireKnit, CONFIG.BlockService, "RF",
                    CONFIG.PickupRemote, { region })
            end
        end
        task.wait(CONFIG.PickupDelay)
    end
end)

-- Delivery: mapped remote first, prompt fallback near the player.
local function deliverFallback()
    local root = getRoot()
    if not root then return false end
    local did = false
    for _, p in ipairs(workspace:GetDescendants()) do
        if not alive then break end
        if p:IsA("ProximityPrompt") then
            local holder = p.Parent
            local pos = nil
            if holder and holder:IsA("BasePart") then
                pos = holder.Position
            elseif holder then
                local part = holder:FindFirstChildWhichIsA("BasePart", true)
                if part then pos = part.Position end
            end
            if pos and (pos - root.Position).Magnitude <= CONFIG.DeliverDist then
                if pcall(fireproximityprompt, p) then did = true end
            end
        end
    end
    return did
end

task.spawn(function()
    while alive and _G.NSBP_Gen == myGen do
        if state.autoDeliver then
            local fired = false
            if CONFIG.DeliverRemote then
                fired = fireKnit(CONFIG.DeliverService, "RF",
                    CONFIG.DeliverRemote, CONFIG.DeliverArgs)
            end
            if not fired then
                pcall(deliverFallback)
            end
        end
        task.wait(CONFIG.DeliverDelay)
    end
end)

-- Station locks: stick to a working station, re-pick every 2 minutes
-- (covers unlocks) or when its parts vanish.
local benchLock, benchLockAt = nil, 0
local treadLock, treadLockAt = nil, 0

local function pickStation(listKey, multKey, manual, modelKey, partKey, lock, lockAt)
    local g = gymCfg()
    if not g then return nil, nil end
    if manual then
        local part = stationPart(g, manual, modelKey, partKey)
        if part then return manual, part end
    end
    if lock and os.clock() - lockAt < 120 then
        local part = stationPart(g, lock, modelKey, partKey)
        if part then return lock, part end
    end
    for _, st in ipairs(sortedStations(g[listKey], multKey)) do
        local part = stationPart(g, st.GymFolder, modelKey, partKey)
        if part then return st.GymFolder, part end
    end
    return nil, nil
end

-- Master farm loop: haul to quarry while hands free, then travel to
-- the nearest free pyramid slot and place. Slot math comes from the
-- game's own PyramidRuntime module.
task.spawn(function()
    while alive and _G.NSBP_Gen == myGen do
        if state.autoFarm then
            pcall(function()
                local carried = readCarry() or 0
                if carried < readCapacity() then
                    local top = quarryTop()
                    local root = getRoot()
                    if top and root and
                        (root.Position - top).Magnitude > 20 then
                        teleportTo(top)
                        task.wait(0.5)
                    end
                    local region = findRegion(CONFIG.PickupRegion)
                    if region then
                        fireKnit(CONFIG.BlockService, "RF",
                            CONFIG.PickupRemote, { region })
                    end
                else
                    local root = getRoot()
                    local slot = root and resolveSlot(root.Position) or nil
                    if slot then
                        if (root.Position - slot.position).Magnitude > 12 then
                            teleportTo(slot.position)
                            task.wait(0.5)
                        end
                        fireKnit(CONFIG.DeliverService, "RF",
                            CONFIG.DeliverRemote,
                            { slot.layer, slot.slotIndex,
                                slot.generation, {} })
                    elseif CONFIG.DeliverArgs then
                        fireKnit(CONFIG.DeliverService, "RF",
                            CONFIG.DeliverRemote, CONFIG.DeliverArgs)
                    end
                end
            end)
        end
        task.wait(CONFIG.FarmDelay)
    end
end)

task.spawn(function()
    while alive and _G.NSBP_Gen == myGen do
        if state.autoTrainStrength then
            pcall(function()
                local g = gymCfg()
                if not g then return end
                local folder = pickStation("BenchpressStations",
                    "StrengthMultiplier", CONFIG.BenchStation,
                    "BenchpressModelName", "AlignPartName",
                    benchLock, benchLockAt)
                if not folder then return end
                local benching = g.BenchStationAttribute and
                    attrStr(LocalPlayer, g.BenchStationAttribute) or nil
                if benching == folder then
                    benchLock, benchLockAt = folder, os.clock()
                    return
                end
                local _, seat = pickStation("BenchpressStations",
                    "StrengthMultiplier", folder,
                    "BenchpressModelName", "AlignPartName", nil, 0)
                local root = getRoot()
                if root and seat and
                    (root.Position - seat.Position).Magnitude > 12 then
                    local cf = root.CFrame
                    root.CFrame = CFrame.new(
                        seat.Position + Vector3.new(0, 3, 0)) *
                        (cf - cf.Position)
                end
                local r = knitRemote(CONFIG.TrainService, "RF",
                    CONFIG.TrainStrengthRemote)
                if r then
                    local ok, ret = pcall(function()
                        return r:InvokeServer(folder)
                    end)
                    if ok and ret == true then
                        benchLock, benchLockAt = folder, os.clock()
                    end
                end
            end)
        end
        if state.autoTrainSpeed then
            pcall(function()
                local folder, belt = pickStation("TreadmillStations",
                    "SpeedMultiplier", CONFIG.TreadStation,
                    "TreadmillModelName", "HitboxName",
                    treadLock, treadLockAt)
                if not belt then return end
                treadLock, treadLockAt = folder, os.clock()
                local root = getRoot()
                if root and (root.Position - belt.Position).Magnitude > 8 then
                    local cf = root.CFrame
                    root.CFrame = CFrame.new(belt.Position) *
                        (cf - cf.Position)
                end
            end)
        end
        task.wait(CONFIG.TrainDelay)
    end
end)

-- AutoUpgrade: rotate the catalog, buy what the server accepts.
-- Server enforces funds; refused ids rest for 5 minutes.
task.spawn(function()
    local idx = 1
    local banned = {}
    while alive and _G.NSBP_Gen == myGen do
        if state.autoUpgrade then
            pcall(function()
                local ids = upgradeIds()
                if #ids == 0 then return end
                if idx > #ids then idx = 1 end
                local id = ids[idx]
                idx = idx + 1
                if banned[id] and os.clock() - banned[id] < 300 then return end
                local r = knitRemote(CONFIG.UpgradeService, "RF",
                    CONFIG.UpgradeRemote)
                if not r then return end
                local ok, reply = pcall(function()
                    return r:InvokeServer(id)
                end)
                if ok and type(reply) == "table" and reply.ok then
                    note("Upgrade bought: " .. tostring(id))
                else
                    banned[id] = os.clock()
                end
            end)
        end
        task.wait(CONFIG.UpgradeDelay)
    end
end)

-- AutoGift: steps then claim, checked every minute.
task.spawn(function()
    while alive and _G.NSBP_Gen == myGen do
        if state.autoGift then
            pcall(function()
                local st = knitRemote(CONFIG.GiftService, "RF",
                    CONFIG.GiftStateRemote)
                if not st then return end
                local ok, gs = pcall(function() return st:InvokeServer() end)
                if not ok or type(gs) ~= "table" or gs.claimed then return end
                for _, step in ipairs({ "liked", "favorited" }) do
                    if not gs[step] then
                        local ms = knitRemote(CONFIG.GiftService, "RF",
                            CONFIG.GiftStepRemote)
                        if ms then pcall(function()
                            ms:InvokeServer(step)
                        end) end
                    end
                end
                local cl = knitRemote(CONFIG.GiftService, "RF",
                    CONFIG.GiftClaimRemote)
                if cl then
                    local ok2, rep = pcall(function()
                        return cl:InvokeServer()
                    end)
                    if ok2 and (rep == true or
                        (type(rep) == "table" and rep.ok)) then
                        note("Free gift claimed")
                    end
                end
            end)
        end
        task.wait(CONFIG.GiftDelay)
    end
end)

-- WalkSpeed + noclip enforcement.
local function setHumanoidSpeed(v)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.WalkSpeed = v end) end
end

task.spawn(function()
    while alive and _G.NSBP_Gen == myGen do
        if state.walkSpeed then
            pcall(setHumanoidSpeed, CONFIG.WalkSpeed)
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while alive and _G.NSBP_Gen == myGen do
        if state.noclip then
            pcall(function()
                local char = LocalPlayer.Character
                if char then
                    for _, p in ipairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
                    end
                end
            end)
        end
        task.wait(0.3)
    end
end)

-- Native anti-AFK: fire the game's own heartbeat (cleaner than input sim).
task.spawn(function()
    while alive and _G.NSBP_Gen == myGen do
        pcall(fireKnit, CONFIG.AFKService, "RE", CONFIG.AFKRemote, {})
        task.wait(CONFIG.AFKDelay)
    end
end)

note("NullShight Pyramid loaded. AutoPickup " ..
    (state.autoPickup and "ON" or "OFF"))

-- Free codes once per run (server dedupes, costs nothing).
task.spawn(function()
    task.wait(5)
    if alive and _G.NSBP_Gen == myGen then redeemAll() end
end)

task.spawn(function()
    task.wait(2)
    if _G.NSBP_Gen ~= myGen then return end
    local want = {
        { CONFIG.BlockService, "RF", CONFIG.PickupRemote },
        { CONFIG.DeliverService, "RF", CONFIG.DeliverRemote },
        { CONFIG.TrainService, "RF", CONFIG.TrainStrengthRemote },
    }
    local missing = {}
    for _, w in ipairs(want) do
        if not knitRemote(w[1], w[2], w[3]) then
            missing[#missing + 1] = w[3]
        end
    end
    if #missing > 0 then
        note("Remote missing: " .. table.concat(missing, ", "))
    else
        note("Pickup remote OK")
    end
    local g = gymCfg()
    if g then
        local nb = g.BenchpressStations and #g.BenchpressStations or 0
        local nt = g.TreadmillStations and #g.TreadmillStations or 0
        note("Gym: " .. tostring(nb) .. " bench, " ..
            tostring(nt) .. " treadmills")
    else
        note("GymConfig unreadable - train disabled")
        state.autoTrainSpeed = false
        state.autoTrainStrength = false
    end
    if not CONFIG.DeliverRemote then
        note("Deliver uses prompt fallback until mapped")
    end
end)

-- UI v2 (Fluent-style, landscape tabs, grab-anywhere). All English.
local TweenService = game:GetService("TweenService")

local ACCENT = Color3.fromRGB(255, 200, 120)
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
    pad.Name = "PyramidEmblem"
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
    emb.BackgroundColor3 = Color3.fromRGB(30, 26, 18)
    emb.BorderSizePixel = 0
    emb.Font = Enum.Font.Code
    emb.TextSize = 18
    emb.TextColor3 = Color3.fromRGB(245, 245, 250)
    emb.Text = "NS"
    emb.Parent = pad
    round(emb, 28)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(66, 54, 32)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 18, 14)),
    })
    grad.Rotation = 35
    grad.Parent = emb

    local ring = Instance.new("UIStroke")
    ring.Color = Color3.fromRGB(210, 200, 190)
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
    gui.Name = "NullShightPyramid"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local PW = 470
    local main = Instance.new("CanvasGroup")
    main.Name = "Panel"
    main.Position = UDim2.new(0, 16, 0, 60)
    main.BackgroundColor3 = Color3.fromRGB(17, 16, 14)
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.GroupTransparency = 1
    main.Parent = gui
    round(main, 14)
    stroke(main, Color3.fromRGB(110, 92, 70), 0.4)

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
    badge.BackgroundColor3 = Color3.fromRGB(38, 30, 20)
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
    sub.Text = "BUILD THE PYRAMID v0.3.0"
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
        { id = "haul", label = "HAUL" },
        { id = "train", label = "TRAIN" },
        { id = "more", label = "MORE" },
        { id = "sys", label = "SYS" },
    }
    local pages = {}
    local tabBtns = {}
    local curTab = "haul"
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

    -- HAUL: 2x2 grid. TRAIN: placeholders until mapped. SYS: Fix + unload.
    local haul = pages.haul
    toggleCell(haul, 0, 0, "Auto Farm", state.autoFarm,
        function(v) state.autoFarm = v end)
    toggleCell(haul, 1, 0, "Auto Pickup", state.autoPickup,
        function(v)
            state.autoPickup = v
            if v then
                local region = findRegion(CONFIG.PickupRegion)
                if region then
                    pcall(fireKnit, CONFIG.BlockService, "RF",
                        CONFIG.PickupRemote, { region })
                end
            end
        end)
    toggleCell(haul, 0, 1, "Auto Deliver", state.autoDeliver,
        function(v) state.autoDeliver = v end)
    wideBtn(haul, 2, "PICKUP x5 BURST", function()
        local region = findRegion(CONFIG.PickupRegion)
        if not region then
            note("Quarry region not found")
            return
        end
        task.spawn(function()
            for _ = 1, 5 do
                pcall(fireKnit, CONFIG.BlockService, "RF",
                    CONFIG.PickupRemote, { region })
                task.wait(0.2)
            end
        end)
    end)

    local train = pages.train
    toggleCell(train, 0, 0, "Train Speed", state.autoTrainSpeed,
        function(v) state.autoTrainSpeed = v end)
    toggleCell(train, 1, 0, "Train Strength", state.autoTrainStrength,
        function(v)
            state.autoTrainStrength = v
            if not v then stopBench() end
        end)

    local more = pages.more
    toggleCell(more, 0, 0, "Auto Upgrade", state.autoUpgrade,
        function(v) state.autoUpgrade = v end)
    toggleCell(more, 1, 0, "Auto Gift", state.autoGift,
        function(v) state.autoGift = v end)
    toggleCell(more, 0, 1, "Walk Speed", state.walkSpeed,
        function(v)
            state.walkSpeed = v
            if not v then pcall(setHumanoidSpeed, CONFIG.WalkNormal) end
        end)
    toggleCell(more, 1, 1, "Noclip", state.noclip,
        function(v) state.noclip = v end)
    wideBtn(more, 2, "REDEEM CODES", function() redeemAll() end)

    local sys = pages.sys
    wideBtn(sys, 0, "FIX LAG", function()
        pcall(fpsBoost)
        CONFIG.PickupDelay = 3
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
