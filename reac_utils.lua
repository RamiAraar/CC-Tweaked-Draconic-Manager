--==============================================================
-- REACTOR UTILITIES
-- Save as: reac_utils.lua
--==============================================================

--[[
README
-------
Manages all Draconic Reactor operations and peripheral handling.

Expected modem labels:
  draconic_reactor_0  → Reactor stabilizer
  flow_gate_0         → Input flux gate (into reactor)
  flow_gate_1         → Output flux gate (to storage/core)
  left                → Status display monitor
]]

------------------------------------------------------------
-- IMPORT CONFIG
------------------------------------------------------------
local cfg = require("config")
local p = cfg.peripherals
local reac_utils = {}

------------------------------------------------------------
-- PERIPHERAL OBJECTS (declared global to module)
------------------------------------------------------------
reac_utils.reactor  = nil
reac_utils.gateIn   = nil
reac_utils.gateOut  = nil
reac_utils.mon      = nil
reac_utils.info     = {}

-- Set these to true from another script or the shell to trigger one-shot actions (e.g. monitor UI).
reac_utils.manualCharge = false
reac_utils.manualStart  = false
reac_utils.manualStop   = false

------------------------------------------------------------
-- INTERNAL LOGGER
------------------------------------------------------------
local function logError(msg)
    local f = fs.open("reactor_error.log", "a")
    if f then
        f.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. msg)
        f.close()
    end
    print("[!] " .. msg)
end

------------------------------------------------------------
-- SAFE WRAPPER FUNCTION
------------------------------------------------------------
local function safeWrap(name)
    if not name or name == "" then return nil end
    if peripheral.isPresent(name) then
        return peripheral.wrap(name)
    end
    return nil
end

------------------------------------------------------------
-- SETUP FUNCTION
------------------------------------------------------------
function reac_utils.setup()
    print("[INFO] Initializing reactor peripherals...")

    -- Attempt to find or wrap peripherals by label
    reac_utils.reactor = safeWrap(p.reactor) or safeWrap("draconic_reactor_0")
    reac_utils.gateIn  = safeWrap(p.fluxIn)  or safeWrap("flow_gate_0")
    reac_utils.gateOut = safeWrap(p.fluxOut) or safeWrap("flow_gate_1")
    reac_utils.mon     = safeWrap(p.monitors and p.monitors[1]) or safeWrap("left")

    -- Validation
    if not reac_utils.reactor then error("Reactor stabilizer not found!") end
    if not reac_utils.gateIn then  error("Input flux gate not found!") end
    if not reac_utils.gateOut then error("Output flux gate not found!") end

    -- Set gates into manual control mode
    if reac_utils.gateIn.setOverrideEnabled then
        reac_utils.gateIn.setOverrideEnabled(true)
        reac_utils.gateIn.setFlowOverride(0)
    end
    if reac_utils.gateOut.setOverrideEnabled then
        reac_utils.gateOut.setOverrideEnabled(true)
        reac_utils.gateOut.setFlowOverride(0)
    end

    print("[SUCCESS] Reactor peripherals initialized successfully.")
end

------------------------------------------------------------
-- REACTOR STATUS
------------------------------------------------------------
function reac_utils.checkReactorStatus()
    if not reac_utils.reactor then
        logError("Reactor not initialized.")
        return
    end

    local ok, data = pcall(function() return reac_utils.reactor:getReactorInfo() end)
    if not ok or not data then
        logError("Failed to read reactor info.")
        return
    end
    reac_utils.info = data
end

------------------------------------------------------------
-- EMERGENCY CHECK
-- Low field / fuel are normal when idle (cold, charging, etc.); only treat them as
-- emergencies while the reactor is supposed to be online. Temperature runaway is always checked.
------------------------------------------------------------
function reac_utils.isEmergency()
    local i = reac_utils.info
    if not i or not i.temperature then return false end

    if i.temperature > cfg.reactor.defaultTemp + cfg.reactor.maxOvershoot then
        return true
    end

    local status = i.status or "unknown"
    if status ~= "running" and status ~= "online" then
        return false
    end

    local maxField = i.maxFieldStrength
    local fieldPct = (maxField and maxField > 0) and (i.fieldStrength / maxField) or 1.0

    local maxFuel = i.maxFuelConversion
    local fuelPct = (maxFuel and maxFuel > 0)
        and (1.0 - (i.fuelConversion / maxFuel))
        or 1.0

    return (fieldPct < cfg.reactor.shutDownField)
        or (fuelPct < cfg.reactor.minFuel)
end

------------------------------------------------------------
-- FAILSAFE SHUTDOWN
------------------------------------------------------------
function reac_utils.failSafeShutdown()
    if reac_utils.reactor and reac_utils.reactor.stopReactor then
        reac_utils.reactor:stopReactor()
    end
    if reac_utils.gateIn then reac_utils.gateIn.setFlowOverride(0) end
    if reac_utils.gateOut then reac_utils.gateOut.setFlowOverride(0) end
    logError("Emergency reactor shutdown executed.")
end

------------------------------------------------------------
-- FUEL AND CHAOS CHECK
------------------------------------------------------------
function reac_utils.checkFuelAndChaos()
    if not reac_utils.reactor then return false end

    local ok, info = pcall(function() return reac_utils.reactor:getReactorInfo() end)
    if not ok or not info then
        logError("Failed to read reactor info during fuel/chaos check.")
        return false
    end

    local maxFuel = info.maxFuelConversion
    if not maxFuel or maxFuel <= 0 then
        logError("Invalid maxFuelConversion from reactor; skipping fuel check.")
        return false
    end

    local fuelLeft = 1.0 - (info.fuelConversion / maxFuel)
    if fuelLeft <= 0 then
        logError("Reactor has no fuel! Insert fuel before startup.")
        reac_utils.failSafeShutdown()
        return false
    end

    local maxChaos = info.maxEnergySaturation
    if maxChaos and maxChaos > 0 then
        if info.energySaturation >= maxChaos then
            logError("Chaos energy buffer full — shutting down to prevent overload.")
            reac_utils.failSafeShutdown()
            return false
        elseif info.energySaturation >= maxChaos * 0.95 then
            logError("Warning: Chaos storage nearing full capacity.")
        end
    end

    return true
end

------------------------------------------------------------
-- TEMPERATURE / FIELD MANAGEMENT
------------------------------------------------------------
function reac_utils.adjustReactorTempAndField()
    local i = reac_utils.info
    if not i or not i.temperature then return end

    local maxField = i.maxFieldStrength
    if not maxField or maxField <= 0 then return end
    local fieldPct = i.fieldStrength / maxField
    local targetField = cfg.reactor.defaultField
    local inflow = 0
    local outflow = 0

    -- Maintain field
    if fieldPct < targetField then
        inflow = cfg.reactor.chargeInflow
    else
        inflow = 0
    end

    -- Manage heat
    if i.temperature > cfg.reactor.defaultTemp then
        outflow = math.min(cfg.reactor.maxOutflow, (i.temperature - cfg.reactor.defaultTemp) * 2000)
    end

    if reac_utils.gateIn then reac_utils.gateIn.setFlowOverride(inflow) end
    if reac_utils.gateOut then reac_utils.gateOut.setFlowOverride(outflow) end
end

------------------------------------------------------------
-- HANDLE STOPPING
------------------------------------------------------------
function reac_utils.handleReactorStopping()
    if reac_utils.gateIn then reac_utils.gateIn.setFlowOverride(0) end
    if reac_utils.gateOut then reac_utils.gateOut.setFlowOverride(0) end
end

return reac_utils
