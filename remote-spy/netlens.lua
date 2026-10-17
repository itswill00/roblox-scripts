-- NullShight NetLens // v1.2.6 -- RemoteSpy
-- A precise, low-footprint network lens: logs RemoteEvent/RemoteFunction
-- traffic, coalesces duplicates, and generates paste-ready call snippets.
-- Executor-agnostic Luau (Delta / Fluxus / Wave mobile friendly).
--
-- Stealth notes (honest): hookfunction on the FireServer/InvokeServer
-- closures (primary) or a single __namecall hook (fallback), restored
-- on unload.
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
    LogOwn = true,           -- false = hide this executor's own calls
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

-- Declared up here, not in the hook section: unload() below reads them, and a
-- local declared further down is not in scope inside an earlier closure.
local hasHookFn = type(hookfunction) == "function"
local hasHookMM = type(hookmetamethod) == "function"
local hasRawMT = type(getrawmetatable) == "function"
local hasGNM = type(getnamecallmethod) == "function"

local oldNC, oldEvent, oldFunc, oldRaw, rawMT = nil, nil, nil, nil, nil
-- Why a fallback path was skipped, surfaced verbatim in the verdict.
local hookSkip = ""
-- Probe instances are module-scoped so unload can re-fetch the live method
-- for restoration, and so they stay parentless-but-alive for the whole
-- session. Destroying them can silently unhook the game on executors that
-- hand back a per-instance bound closure.
local probeE, probeF
local hookMode = "none"
local function unload(quiet)
    if not alive then return end
    alive = false
    pcall(function()
        if hookMode == "hookfunction" then
            -- Restore targets the CURRENT occupant of the slot, not the
            -- original we saved: hookfunction replaced the slot contents,
            -- so the saved original is what we put back.
            if probeE and type(oldEvent) == "function" and hasHookFn then
                local live = probeE.FireServer
                if type(live) == "function" then hookfunction(live, oldEvent) end
            end
            if probeF and type(oldFunc) == "function" and hasHookFn then
                local live = probeF.InvokeServer
                if type(live) == "function" then hookfunction(live, oldFunc) end
            end
        elseif hookMode == "rawnamecall" then
            if rawMT and type(oldRaw) == "function" and hasHookFn then
                local live = rawMT.__namecall
                if type(live) == "function" then hookfunction(live, oldRaw) end
            end
        elseif hookMode == "namecall" then
            if hasHookMM and type(oldNC) == "function" then
                hookmetamethod(game, "__namecall", oldNC)
            end
        end
    end)
    hookMode = "restored"
    oldEvent, oldFunc, oldNC, oldRaw = nil, nil, nil, nil
    pcall(function()
        probeE:Destroy()
        probeF:Destroy()
    end)
    probeE, probeF = nil, nil
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
local ncTotal = 0
local hookInfo = "installing.."
local rows = {}         -- entry -> row frame
local listFrame = nil
local subLabel = nil
local detLine1, detLine2 = nil, nil
local selected = nil
local filterText = ""
local seqNum = 0

local function statsText()
    local n = 0
    for _ in pairs(remoteSet) do n = n + 1 end
    return "NETLENS v1.2.6  |  " .. tostring(n) .. " remotes  |  " ..
        tostring(totalCalls) .. " calls  |  " .. hookInfo
end

local function refreshStats()
    if subLabel then
        pcall(function() subLabel.Text = statsText() end)
    end
end

local function paintSel()
    for e, r in pairs(rows) do
        pcall(function()
            r.BackgroundColor3 = (e == selected)
                and Color3.fromRGB(34, 44, 62)
                or Color3.fromRGB(24, 27, 36)
        end)
    end
end

local function selectEntry(e)
    selected = e
    paintSel()
    if detLine1 then
        pcall(function()
            if e then
                detLine1.Text = e.snippetPreview
                detLine1.TextColor3 = Color3.fromRGB(235, 235, 242)
            else
                detLine1.Text = "Tap a row: copy, re-fire, blacklist."
                detLine1.TextColor3 = Color3.fromRGB(150, 155, 175)
            end
        end)
    end
    if detLine2 then
        pcall(function()
            detLine2.Text = e and e.preview or ""
        end)
    end
end

local function copySelected()
    local e = selected
    if not e then
        note("Nothing selected")
        return
    end
    local ok = pcall(function()
        if type(setclipboard) == "function" then
            setclipboard(e.snippet)
        else
            error("no clipboard")
        end
    end)
    note(ok and "Snippet copied" or "Copy failed on this executor")
end

local function fireSelected()
    local e = selected
    if not e or not e.ref then
        note("Nothing to fire")
        return
    end
    local ok, err = pcall(function()
        -- Explicit bounds: plain unpack() stops at the first nil and would
        -- replay the call with the wrong argument count.
        if e.method == "FireServer" then
            e.ref:FireServer(table.unpack(e.callArgs, 1, e.argCount))
        else
            e.ref:InvokeServer(table.unpack(e.callArgs, 1, e.argCount))
        end
    end)
    note(ok and ("Fired " .. e.name) or ("Fire failed: " .. tostring(err)))
end

local function blacklistSelected()
    local e = selected
    if not e then
        note("Nothing selected")
        return
    end
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
    selectEntry(nil)
    refreshStats()
    note("Blacklisted " .. e.name)
end

local function pruneRows()
    while #entries > CONFIG.MaxRows do
        local e = table.remove(entries, 1)
        byKey[e.key] = nil
        local r = rows[e]
        rows[e] = nil
        if r then pcall(function() r:Destroy() end) end
        if selected == e then selectEntry(nil) end
    end
end

local function rowText(e)
    local clock = os.date("%X")
    return clock .. " " .. e.method .. " " .. e.name ..
        (e.count > 1 and (" x" .. tostring(e.count)) or "")
end

local function mountRow(e)
    if not listFrame then return nil end
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 28)
    row.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    row.BorderSizePixel = 0
    row.LayoutOrder = -e.seq
    row.Visible = filterText == "" or
        string.find(string.lower(e.name), filterText, 1, true) ~= nil
    row.Parent = listFrame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = row

    local tap = Instance.new("TextButton")
    tap.Size = UDim2.new(1, 0, 1, 0)
    tap.BackgroundTransparency = 1
    tap.Text = ""
    tap.AutoButtonColor = false
    tap.Parent = row

    local l1 = Instance.new("TextLabel")
    l1.Size = UDim2.new(1, -10, 1, 0)
    l1.Position = UDim2.new(0, 6, 0, 0)
    l1.BackgroundTransparency = 1
    l1.Font = Enum.Font.Code
    l1.TextSize = 11
    l1.TextXAlignment = Enum.TextXAlignment.Left
    l1.TextColor3 = Color3.fromRGB(235, 235, 242)
    l1.TextTruncate = Enum.TextTruncate.AtEnd
    l1.Text = rowText(e)
    l1.Parent = tap

    e.row1 = l1
    rows[e] = row
    return row, tap
end

local pressBegan, pressEnded -- forward decls (UI section assigns)

local function wireRow(e, row, tap)
    if not (tap and pressBegan and pressEnded) then return end
    track(tap.InputBegan:Connect(pressBegan))
    track(tap.InputEnded:Connect(function(input)
        if pressEnded(input) then
            selectEntry(e)
        end
    end))
end

local function logCall(inst, method, args, argCount)
    if not mine() or state.paused then return end
    local path = instPath(inst)
    if blacklist[path] then return end
    local n = argCount or #args
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
            pcall(function() e.row1.Text = rowText(e) end)
        end
        refreshStats()
        return
    end

    -- Build paste-ready snippet.
    local sargs = {}
    for i = 1, n do sargs[#sargs + 1] = serialize(args[i]) end
    local call = method == "FireServer" and ":FireServer(table.unpack(args, 1, n))"
        or ":InvokeServer(table.unpack(args, 1, n))"
    local snippet = "local args = { " .. table.concat(sargs, ", ") .. " }\n" ..
        path .. call

    seqNum = seqNum + 1
    local callArgs = {}
    for i = 1, n do callArgs[i] = args[i] end
    local oneLine = (snippet:gsub("\n", " | "))
    e = {
        key = key, method = method, path = path, name = inst.Name,
        count = 1, preview = argsPrev .. "   <- " .. caller,
        snippet = snippet,
        snippetPreview = string.sub(oneLine, 1, 120),
        callArgs = callArgs, argCount = n, ref = inst, seq = seqNum,
        row1 = nil,
    }
    byKey[key] = e
    entries[#entries + 1] = e
    pruneRows()
    local row, tap = mountRow(e)
    wireRow(e, row, tap)
    refreshStats()
end

-- Hooks (v1.2.5 -- self-checked install).
--
-- v1.2.4 was dead on every mobile executor. It used hookfunction's RETURN
-- VALUE as two things at once: the "did it install?" flag, and the original
-- to call through. Several executors return nothing on success, so the hook
-- went live with a nil passthrough: every :FireServer() in the whole game
-- threw "attempt to call a nil value", zero rows were ever logged, and the
-- status line still cheerfully said "armed". Same trap in both namecall
-- fallbacks, and there it breaks EVERY namecall, not just remotes.
--
-- Fix, three rules:
--   1. Capture the original BEFORE hooking. Never read hookfunction's return.
--   2. A probe instance is never destroyed: if the executor hands back a
--      per-instance bound closure, Destroy silently unhooks the game.
--   3. Name resolution must never be the only gate. If getnamecallmethod is
--      missing, fall back to debug.info and still log what the class is.
--
-- Order of preference:
--   1. hookfunction on the real FireServer/InvokeServer C closures.
--   2. hookfunction on the raw __namecall metamethod.
--   3. hookmetamethod(game, "__namecall", ...).
-- Only one path installs, so nothing is logged twice.
-- (hasHookFn / hasHookMM / hasRawMT / hasGNM are declared above unload().)

-- Packs varargs with an explicit count. A plain { ... } table constructor
-- truncates at the first nil, which silently changes InvokeServer(x, nil, nil)
-- into a one-argument call when the snippet is replayed.
local function packArgs(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do t[i] = (select(i, ...)) end
    return t, n
end

-- Resolves the called method name inside a namecall hook. Returns "" when the
-- executor exposes no way to know it; callers must not treat that as fatal.
local function calledMethod()
    if hasGNM then
        local ok, m = pcall(getnamecallmethod)
        if ok and type(m) == "string" and m ~= "" then return m end
    end
    local ok2, m2 = pcall(function()
        return debug.info(2, "name")
    end)
    if ok2 and type(m2) == "string" and m2 ~= "" then return m2 end
    return ""
end

pcall(function()
    local wrap = newcclosure or function(f) return f end

    -- Re-entrancy guard, and the single most important line in this file.
    -- The executor's __namecall is shared by every Instance, not just `game`,
    -- so anything the hook touches that is ITSELF a namecall on an Instance
    -- re-enters the hook. v1.2.4 called self:IsA() as its very first step:
    -- hook -> IsA -> hook -> IsA -> ... stack overflow, hook dead, nothing
    -- ever logged. Any method call in here needs this guard.
    local inHook = false

    -- typeof() is a plain global call, never a namecall, so it cannot recurse.
    -- ClassName is a property read, also recursion-safe. IsA() is BOTH unsafe
    -- and unnecessary here.
    local function remoteClassOf(self)
        local t = typeof(self)
        if t == "RemoteEvent" or t == "RemoteFunction" then return true end
        local ok, cn = pcall(function() return self.ClassName end)
        return ok and (cn == "RemoteEvent" or cn == "RemoteFunction")
    end

    local function handle(method, self, args, n)
        if inHook then return end
        inHook = true
        -- Wrapped whole: a throw inside must not leave inHook stuck true,
        -- which would silently deafen every later call.
        pcall(function()
            if not remoteClassOf(self) then return end
            ncTotal = ncTotal + 1
            local m = string.lower(tostring(method or ""))
            if m ~= "fireserver" and m ~= "invokeserver" then
                if m == "" then
                    -- No name available, but we know the target is a remote
                    -- and that it was reached through :Method(). FireServer
                    -- cannot return a value, so a call with no return
                    -- expectation is the safe classification.
                    m = "fireserver"
                else
                    return
                end
            end
            local resolved = (m == "fireserver") and "FireServer"
                or "InvokeServer"
            if not CONFIG.LogOwn and type(checkcaller) == "function" then
                local okC, isOurs = pcall(checkcaller)
                if okC and isOurs then return end
            end
            pcall(logCall, self, resolved, args, n)
        end)
        inHook = false
    end

-- Synchronous proof that a hook is actually live.
    -- :FireServer() dispatches through the hook inline, so ncTotal moves
    -- before this returns -- no task.wait, no guessing.
    local function canaryCaught()
        local before = ncTotal
        local c = Instance.new("RemoteEvent")
        c.Name = "NetLensCanary"
        c.Parent = workspace
        pcall(function() c:FireServer("ping") end)
        pcall(function() c:Destroy() end)
        return ncTotal > before
    end

    -- Install a path, then demand proof. A path that cannot catch its own
    -- canary is unhooked and reported dead.
    --
    -- Second v1.2.4-level bug: the old install accepted the FIRST path whose
    -- pcall merely did not throw, then stopped. hookfunction on a Roblox C
    -- closure is frequently a silent no-op, so path 1 "succeeded" while
    -- catching nothing -- and since hookMode was already set, the working
    -- __namecall fallbacks were never attempted at all. A hook being
    -- installed is not evidence that it runs; the canary is the evidence.
    local function tryPath(mode, install, uninstall)
        if not pcall(install) then return false end
        if canaryCaught() then
            hookMode = mode
            return true
        end
        pcall(uninstall)
        hookSkip = mode .. ":silent"
        return false
    end

    -- 1. Direct C-closure hooks. Originals captured before hooking and
    -- assigned to oldEvent/oldFunc first, so the passthrough can never see
    -- nil even when the hook installs synchronously.
    if hasHookFn then
        tryPath("hookfunction", function()
            probeE = Instance.new("RemoteEvent")
            probeF = Instance.new("RemoteFunction")
            local origE = probeE.FireServer
            local origF = probeF.InvokeServer
            if type(origE) ~= "function" then
                error("no FireServer")
            end
            oldEvent = origE
            pcall(hookfunction, origE, wrap(function(self, ...)
                local a, n = packArgs(...)
                handle("FireServer", self, a, n)
                return oldEvent(self, ...)
            end))
            -- RemoteFunction is a separate closure. Install it when reachable,
            -- but never let it decide the whole path.
            if type(origF) == "function" then
                oldFunc = origF
                pcall(hookfunction, origF, wrap(function(self, ...)
                    local a, n = packArgs(...)
                    handle("InvokeServer", self, a, n)
                    return oldFunc(self, ...)
                end))
            end
        end, function()
            if probeE and type(oldEvent) == "function" then
                local live = probeE.FireServer
                if type(live) == "function" then
                    pcall(hookfunction, live, oldEvent)
                end
            end
            if probeF and type(oldFunc) == "function" then
                local live = probeF.InvokeServer
                if type(live) == "function" then
                    pcall(hookfunction, live, oldFunc)
                end
            end
        end)
    end

    -- 2. Raw __namecall. Save the original, hook, ignore the return value.
    if hookMode == "none" and hasHookFn and hasRawMT then
        tryPath("rawnamecall", function()
            local mt = getrawmetatable(game)
            if type(mt) ~= "table" or type(mt.__namecall) ~= "function" then
                error("no raw __namecall")
            end
            rawMT = mt
            oldRaw = mt.__namecall
            pcall(hookfunction, oldRaw, wrap(function(self, ...)
                local a, n = packArgs(...)
                handle(calledMethod(), self, a, n)
                return oldRaw(self, ...)
            end))
        end, function()
            if rawMT and type(oldRaw) == "function" then
                local live = rawMT.__namecall
                if type(live) == "function" then
                    pcall(hookfunction, live, oldRaw)
                end
            end
        end)
    end

    -- 3. hookmetamethod. The name is __namecall, NOT __namecallmethod; the
    -- wrong name installs a hook that never fires.
    --
    -- hookmetamethod does not hand back the original on every executor, so
    -- decide BEFORE installing: with no independent copy of __namecall there
    -- is no safe passthrough, and a live hook whose replacement calls nil
    -- breaks every :Method() call in the game.
    if hookMode == "none" and hasHookMM then
        local known = nil
        if hasRawMT then
            pcall(function()
                local mt = getrawmetatable(game)
                if type(mt) == "table" and type(mt.__namecall) == "function" then
                    known = mt.__namecall
                end
            end)
        end
        if type(known) ~= "function" then
            hookSkip = "namecall:no-original"
        else
            tryPath("namecall", function()
                oldNC = known
                local captured
                pcall(function()
                    captured = hookmetamethod(game, "__namecall",
                        wrap(function(self, ...)
                            local a, n = packArgs(...)
                            handle(calledMethod(), self, a, n)
                            return oldNC(self, ...)
                        end))
                end)
                if type(captured) == "function" then oldNC = captured end
            end, function()
                pcall(hookmetamethod, game, "__namecall", oldNC)
            end)
        end
    end
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
    -- Parent resolution, most-reliable first. A single pcall around the
    -- whole expression was a silent killer: if gethui() errored, parent
    -- stayed nil and the script mounted no UI at all, with the hook running
    -- invisibly in the background. Each candidate is tried on its own.
    local parent = nil
    if type(gethui) == "function" then
        pcall(function() parent = gethui() end)
    end
    if type(parent) ~= "Instance" then parent = nil end
    if not parent then
        pcall(function() parent = game:GetService("CoreGui") end)
    end
    if type(parent) ~= "Instance" then
        pcall(function() parent = LocalPlayer:WaitForChild("PlayerGui") end)
    end
    if not parent then
        note("UI failed to mount: no usable ScreenGui parent")
        return false
    end

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

    local bw = (PW - 24 - 32) / 5
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
        selectEntry(nil)
        refreshStats()
    end)
    toolBtn(2 * (bw + 8), bw, "TEST", function()
        -- Diagnostics only: reports what each layer actually did, so a dead
        -- install is identifiable instead of mysterious. Never claims more
        -- than it measured.
        local hf = type(hookfunction)
        local mm = type(hookmetamethod)
        local gn = type(getnamecallmethod)
        local mtOK = false
        if type(getrawmetatable) == "function" then
            pcall(function()
                local mt = getrawmetatable(game)
                mtOK = (type(mt) == "table")
            end)
        end

        local before = ncTotal
        pcall(function()
            local t = Instance.new("RemoteEvent")
            t.Name = "NetLensSelfTest"
            t.Parent = workspace
            t:FireServer("ping", 123, nil)
            pcall(function() t:Destroy() end)
        end)
        task.delay(0.5, function()
            local caught = ncTotal - before
            note(string.format(
                "hook=%s hf=%s mm=%s gnm=%s rawmt=%s seen=%d",
                hookMode, hf, mm, gn, tostring(mtOK), caught))
            if caught == 0 then
                note("Hook caught nothing. If hf=function the executor "
                    .. "stubs it; remote logging cannot work here.")
            end
        end)
    end)
    toolBtn(3 * (bw + 8), bw, "COPY", function()
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
    toolBtn(4 * (bw + 8), bw, "EXPORT", function()
        -- Writes the full log to a .txt via the executor filesystem
        -- (Delta: /Delta/Workspace or the executor's workspace folder).
        if type(writefile) ~= "function" then
            note("Export not supported on this executor")
            return
        end
        local lines = {}
        lines[#lines + 1] = "-- NetLens export " .. os.date("%Y-%m-%d %X")
        lines[#lines + 1] = "-- " .. statsText()
        lines[#lines + 1] = ""
        for _, e in ipairs(entries) do
            lines[#lines + 1] = "-- " .. rowText(e)
            lines[#lines + 1] = "-- caller: " .. e.preview
            lines[#lines + 1] = e.snippet
            lines[#lines + 1] = ""
        end
        local fname = "NetLens_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
        local ok, err = pcall(writefile, fname, table.concat(lines, "\n"))
        note(ok and ("Saved " .. fname .. " (" ..
            tostring(#entries) .. " rows)") or
            ("Export failed: " .. tostring(err)))
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
    local filterBox = Instance.new("TextBox")
    filterBox.Size = UDim2.new(0, 232, 0, 32)
    filterBox.Position = UDim2.new(0, 0, 0, 38)
    filterBox.BackgroundColor3 = CARD
    filterBox.BorderSizePixel = 0
    filterBox.Font = Enum.Font.Code
    filterBox.TextSize = 11
    filterBox.TextColor3 = INK
    filterBox.PlaceholderColor3 = DIM
    filterBox.PlaceholderText = "  filter name.."
    filterBox.Text = ""
    filterBox.TextXAlignment = Enum.TextXAlignment.Left
    filterBox.ClearTextOnFocus = false
    filterBox.Parent = toolbar
    round(filterBox, 8)
    stroke(filterBox, Color3.fromRGB(55, 60, 78), 0.55)
    track(filterBox:GetPropertyChangedSignal("Text"):Connect(function()
        filterText = string.lower(filterBox.Text)
        for e, r in pairs(rows) do
            pcall(function()
                r.Visible = filterText == "" or
                    string.find(string.lower(e.name), filterText, 1, true)
                        ~= nil
            end)
        end
    end))
    miniToggle(240, 120, "Merge", state.merge,
        function(v) state.merge = v end)
    miniToggle(368, 120, "Args", state.argsOnly,
        function(v) state.argsOnly = v end)
    miniToggle(496, 120, "Own", CONFIG.LogOwn,
        function(v) CONFIG.LogOwn = v end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -24, 0, 140)
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

    -- Detail pane: selected entry. COPY / FIRE (re-fire it) / BL.
    local detail = Instance.new("Frame")
    detail.Size = UDim2.new(1, -24, 0, 48)
    detail.Position = UDim2.new(0, 12, 0, 280)
    detail.BackgroundColor3 = CARD
    detail.BorderSizePixel = 0
    detail.Parent = main
    round(detail, 8)
    stroke(detail, Color3.fromRGB(55, 60, 78), 0.55)

    detLine1 = Instance.new("TextLabel")
    detLine1.Size = UDim2.new(1, -216, 0, 20)
    detLine1.Position = UDim2.new(0, 8, 0, 4)
    detLine1.BackgroundTransparency = 1
    detLine1.Font = Enum.Font.Code
    detLine1.TextSize = 11
    detLine1.TextXAlignment = Enum.TextXAlignment.Left
    detLine1.TextColor3 = DIM
    detLine1.TextTruncate = Enum.TextTruncate.AtEnd
    detLine1.Text = "Tap a row: copy, re-fire, blacklist."
    detLine1.Parent = detail

    detLine2 = Instance.new("TextLabel")
    detLine2.Size = UDim2.new(1, -216, 0, 16)
    detLine2.Position = UDim2.new(0, 8, 0, 26)
    detLine2.BackgroundTransparency = 1
    detLine2.Font = Enum.Font.Code
    detLine2.TextSize = 10
    detLine2.TextXAlignment = Enum.TextXAlignment.Left
    detLine2.TextColor3 = DIM
    detLine2.TextTruncate = Enum.TextTruncate.AtEnd
    detLine2.Text = ""
    detLine2.Parent = detail

    local function detBtn(x, w, label, cb, danger)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, w, 0, 28)
        btn.Position = UDim2.new(0, x, 0, 10)
        btn.BackgroundColor3 = danger and Color3.fromRGB(52, 24, 26)
            or CARD2
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.Code
        btn.TextSize = 11
        btn.TextColor3 = danger and Color3.fromRGB(255, 175, 175) or INK
        btn.Text = label
        btn.AutoButtonColor = false
        btn.Parent = detail
        round(btn, 7)
        stroke(btn, danger and Color3.fromRGB(170, 80, 85)
            or Color3.fromRGB(70, 76, 100), 0.5)
        track(btn.InputBegan:Connect(pressBegan))
        track(btn.InputEnded:Connect(function(input)
            if pressEnded(input) then cb() end
        end))
    end
    local dw = PW - 24
    detBtn(dw - 204, 70, "COPY", function() copySelected() end)
    detBtn(dw - 126, 70, "FIRE", function() fireSelected() end)
    detBtn(dw - 48, 48, "BL", function() blacklistSelected() end, true)

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
            local erow, etap = mountRow(e)
            wireRow(e, erow, etap)
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

task.spawn(function()
    while mine() do
        refreshStats()
        task.wait(1)
    end
end)

-- Honest verdict. "Hook installed" is not evidence of anything: the v1.2.4
-- release reported "armed" on executors where every remote call was throwing.
-- So prove it end to end instead of claiming it -- fire a sacrificial
-- RemoteEvent and check whether our own hook actually saw it.
task.spawn(function()
    if hookMode == "none" then
        hookInfo = "DEAD: no hook API" .. (hookSkip ~= "" and (" (" .. hookSkip .. ")") or "")
        note("NetLens DEAD - executor exposes no usable hookfunction/hookmetamethod")
        return
    end

    local before = ncTotal
    local canary = Instance.new("RemoteEvent")
    canary.Name = "NetLensCanary"
    canary.Parent = workspace
    local fired = pcall(function() canary:FireServer("ping", 123, nil) end)
    pcall(function() canary:Destroy() end)

    task.wait(0.4)
    if not mine() then return end

    local gnm = hasGNM and "gnm:OK" or "gnm:MISSING"
    if fired and ncTotal > before then
        hookInfo = "LIVE " .. hookMode .. " " .. gnm
        note("NetLens LIVE (" .. hookMode .. "). Do an action in-game.")
    else
        hookInfo = "DEAD " .. hookMode .. " (hook saw nothing)"
        note("NetLens DEAD - hook installed but caught 0 of its own "
            .. "canary FireServer. Try another executor; remote logging "
            .. "cannot work here.")
    end
end)

return true
