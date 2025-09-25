local Trunk = {}
local Utils = Utils

local trunks = {}

local function getVehicleFromNetId(netId)
    if not netId then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return nil end
    if not DoesEntityExist(entity) then return nil end
    return entity
end

local function getCapacity(vehicle)
    local class = GetVehicleClass(vehicle)
    local capacity = Config.Trunk.capacityByClass[class]
    if capacity == nil then
        capacity = Config.Trunk.fallbackCapacity
    end
    return capacity or 0
end

local function computeCells(vehicle, dims, capacity)
    local cells = {}
    if capacity <= 0 then return cells end
    local columns = math.max(1, math.ceil(math.sqrt(capacity)))
    local rows = math.max(1, math.ceil(capacity / columns))

    local cellX = dims.x + Config.Trunk.cellPadding
    local cellY = dims.y + Config.Trunk.cellPadding
    local cellZ = dims.z + Config.Trunk.cellPadding

    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local baseY = min.y + (cellY / 2.0)
    local baseZ = min.z + math.max(cellZ, (max.z - min.z) * 0.25)
    local heading = GetEntityHeading(vehicle)

    for row = 0, rows - 1 do
        for col = 0, columns - 1 do
            local index = row * columns + col + 1
            if index > capacity then break end
            local offsetX = (col - (columns - 1) / 2) * cellX
            local offsetY = baseY + (row * cellY)
            local offsetZ = baseZ
            local world = GetOffsetFromEntityInWorldCoords(vehicle, offsetX, offsetY, offsetZ)
            cells[index] = { x = world.x, y = world.y, z = world.z, w = heading }
        end
    end

    return cells
end

local function ensureState(netId, dims)
    trunks[netId] = trunks[netId] or { occupants = {} }
    local state = trunks[netId]
    state.dims = dims
    state.hash = dims.hash
    local vehicle = getVehicleFromNetId(netId)
    if not vehicle then
        return nil
    end
    local capacity = getCapacity(vehicle)
    state.capacity = capacity
    state.cells = computeCells(vehicle, dims, capacity)
    return state
end

function Trunk.fetch(netId, dims)
    local state = ensureState(netId, dims)
    if not state then return nil end
    local nextIndex
    for idx = 1, state.capacity do
        if not state.occupants[idx] then
            nextIndex = idx
            break
        end
    end
    return {
        capacity = state.capacity,
        occupied = state.occupants,
        nextCell = nextIndex and state.cells[nextIndex] or nil,
        hash = state.hash
    }
end

function Trunk.reserve(netId, dims, objectId)
    local state = ensureState(netId, dims)
    if not state then return nil end
    for idx = 1, state.capacity do
        if not state.occupants[idx] then
            state.occupants[idx] = objectId or idx
            return idx, state.cells[idx]
        end
    end
    return nil, nil
end

function Trunk.release(netId, key)
    local state = trunks[netId]
    if not state then return end
    if not key then
        for idx in pairs(state.occupants) do
            state.occupants[idx] = nil
        end
        return
    end
    if state.occupants[key] then
        state.occupants[key] = nil
    end
end

_G.Trunk = Trunk
return Trunk
