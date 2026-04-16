--==============================================================
-- ENERGY CORE UTILITIES
-- Save as: energy_core_utils.lua
-- Flux gate flow display/logging (refreshed in setup()).
--==============================================================

local cfg = require("config")
local p = cfg.peripherals
local energy_core_utils = {}

local inputGate, outputGate, monitor = nil, nil, nil

local function safeWrap(name)
    if name and peripheral.isPresent(name) then
        return peripheral.wrap(name)
    end
    return nil
end

local function refreshPeripherals()
    inputGate  = safeWrap(p.fluxIn)  or safeWrap("flow_gate_0")
    outputGate = safeWrap(p.fluxOut) or safeWrap("flow_gate_1")
    monitor    = safeWrap(p.monitors and p.monitors[1]) or safeWrap("left")
end

local function logError(msg)
    local f = fs.open(cfg.energyCore.logsFile or "energy_core.log", "a")
    if f then
        f.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. msg)
        f.close()
    end
end

function energy_core_utils.setup()
    refreshPeripherals()
    if not monitor then
        logError("Monitor not found, running headless.")
        return
    end
    monitor.setTextScale(cfg.energyCore.monitorScale)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Energy Flow Monitor Initialized")
end

function energy_core_utils.updateMonitor()
    if not monitor then return end
    local inFlow = 0
    local outFlow = 0

    if inputGate and inputGate.getFlow then
        local ok, val = pcall(inputGate.getFlow)
        if ok then inFlow = val end
    end
    if outputGate and outputGate.getFlow then
        local ok, val = pcall(outputGate.getFlow)
        if ok then outFlow = val end
    end

    monitor.clear()
    monitor.setCursorPos(2, 2)
    monitor.write("Energy Flow Monitor")
    monitor.setCursorPos(2, 4)
    monitor.write(string.format("Input:  %.0f RF/t", inFlow))
    monitor.setCursorPos(2, 5)
    monitor.write(string.format("Output: %.0f RF/t", outFlow))
end

function energy_core_utils.logEnergyCoreStats()
    local f = fs.open("energy_core_stats.log", "a")
    if not f then return end
    local inFlow, outFlow = 0, 0

    if inputGate and inputGate.getFlow then
        local ok, val = pcall(inputGate.getFlow)
        if ok then inFlow = val end
    end
    if outputGate and outputGate.getFlow then
        local ok, val = pcall(outputGate.getFlow)
        if ok then outFlow = val end
    end

    f.writeLine(string.format(
        "%s | In: %.0f RF/t | Out: %.0f RF/t",
        os.date("%Y-%m-%d %H:%M:%S"),
        inFlow, outFlow
    ))
    f.close()
end

return energy_core_utils
