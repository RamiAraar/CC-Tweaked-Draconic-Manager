--==============================================================
-- STATISTICS UTILITIES
-- Save as: stat_utils.lua
--==============================================================

local stat_utils = {}

local function logError(msg)
    local f = fs.open("stats_error.log", "a")
    if f then
        f.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. msg)
        f.close()
    end
end

function stat_utils.logReactorStats(reactor)
    if not reactor or not reactor.getReactorInfo then
        logError("Reactor unavailable during stats logging.")
        return
    end

    local ok, info = pcall(function() return reactor:getReactorInfo() end)
    if not ok or not info then
        logError("Failed to get reactor info: " .. tostring(info))
        return
    end

    local maxField = info.maxFieldStrength
    local fieldPct = (maxField and maxField > 0) and ((info.fieldStrength or 0) / maxField) or 0
    local maxFuel = info.maxFuelConversion
    local fuelLeft = (maxFuel and maxFuel > 0)
        and (1.0 - (info.fuelConversion or 0) / maxFuel)
        or 0
    local maxSat = info.maxEnergySaturation
    local satFrac = (maxSat and maxSat > 0) and ((info.energySaturation or 0) / maxSat) or 0

    local f = fs.open("reactor_stats.log", "a")
    if not f then return end
    f.writeLine(string.format(
        "%s | Temp=%.1f | Field=%.3f | FuelLeft=%.3f | Sat=%.3f | Status=%s",
        os.date("%Y-%m-%d %H:%M:%S"),
        info.temperature or 0,
        fieldPct,
        fuelLeft,
        satFrac,
        info.status or "unknown"
    ))
    f.close()
end

return stat_utils
