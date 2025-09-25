PlaceablePhysics = PlaceablePhysics or {}

local function shapeTestDown(position, depth, flags, ignore)
    local to = position - vector3(0.0, 0.0, depth or 5.0)
    local handle = StartShapeTestRay(position.x, position.y, position.z, to.x, to.y, to.z, flags or 1, ignore or 0, 7)
    local result, hit, coords, normal = GetShapeTestResult(handle)

    if result == 1 and hit == 1 then
        return vector3(coords.x, coords.y, coords.z), vector3(normal.x, normal.y, normal.z)
    end

    return nil, nil
end

function PlaceablePhysics.SnapToGround(position, entity, options)
    options = options or {}
    local offset = options.offset or 0.0
    local coords, normal = shapeTestDown(position + vector3(0.0, 0.0, 0.5), options.depth or 4.0, options.flags, entity)

    if coords then
        coords = vector3(coords.x, coords.y, coords.z + offset)
        return coords, normal
    end

    return position, vector3(0.0, 0.0, 1.0)
end

function PlaceablePhysics.ApplyPlacement(entity, coords, heading)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(entity, heading)
    PlaceObjectOnGroundProperly(entity)
end

function PlaceablePhysics.SettleEntity(entity, options)
    options = options or {}
    local lockMs = options.lockMs or Config.Settle.lockMs
    local settleDelay = options.settleDelay or Config.Settle.settleDelay
    local epsilon = options.epsilon or Config.Settle.epsilon
    local attempts = options.maxAttempts or Config.Settle.maxAttempts
    local failZ = options.failZ or Config.Settle.failZ

    if not DoesEntityExist(entity) then return end

    FreezeEntityPosition(entity, true)
    Wait(lockMs)
    FreezeEntityPosition(entity, false)

    local initialCoords = GetEntityCoords(entity)
    local attempt = 0
    local lastValid = initialCoords

    while attempt < attempts do
        attempt = attempt + 1
        Wait(settleDelay)

        if not DoesEntityExist(entity) then
            return
        end

        local coords = GetEntityCoords(entity)
        if coords.z < failZ then
            SetEntityCoordsNoOffset(entity, lastValid.x, lastValid.y, lastValid.z + epsilon, false, false, false)
            FreezeEntityPosition(entity, true)
            Wait(lockMs)
            FreezeEntityPosition(entity, false)
            goto continue
        end

        local drop = lastValid.z - coords.z
        if drop > epsilon then
            SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z + epsilon, false, false, false)
            lastValid = coords
        else
            lastValid = coords
            break
        end

        ::continue::
    end
end

