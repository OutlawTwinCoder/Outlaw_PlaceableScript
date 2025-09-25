local function rotationToDirection(rotation)
    local adjustedRotation = vector3(
        math.rad(rotation.x),
        math.rad(rotation.y),
        math.rad(rotation.z)
    )

    local direction = vector3(
        -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.sin(adjustedRotation.x)
    )

    return direction
end

local function getCameraRay(maxDistance)
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local direction = rotationToDirection(camRot)
    local destination = camCoords + (direction * maxDistance)
    return camCoords, destination
end

local function performRayTest(from, to, flags, ignore)
    flags = flags or (1 | 2 | 4 | 8 | 16 | 256)
    local handle = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore or 0, 7)
    local result, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(handle)

    if result == 1 then
        return hit == 1, vector3(endCoords.x, endCoords.y, endCoords.z), vector3(surfaceNormal.x, surfaceNormal.y, surfaceNormal.z), entityHit
    end

    return false, to, vector3(0.0, 0.0, 1.0), 0
end

PlaceableRaycast = PlaceableRaycast or {}

function PlaceableRaycast.FromCamera(maxDistance, flags, ignore)
    local from, to = getCameraRay(maxDistance)
    return performRayTest(from, to, flags, ignore)
end

function PlaceableRaycast.FromPedForward(ped, distance, flags)
    ped = ped or PlayerPedId()
    distance = distance or 3.0

    local origin = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local destination = origin + (forward * distance)
    destination = vector3(destination.x, destination.y, origin.z + 0.5)

    return performRayTest(origin + vector3(0.0, 0.0, 0.5), destination, flags, ped)
end

