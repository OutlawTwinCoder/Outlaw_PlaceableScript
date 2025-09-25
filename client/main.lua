-- client/main.lua (v1.2.2)
-- Camera-centered preview with pure camera-ray scrolling (no ped clamp in camera mode)

local placing = false
local previewEntity
local previewRotation = 0.0
local activeItem
local placementThread
local previewValid = false
local previewBaseOffset = 0.0
local previewSurfaceOffset
local previewHitCoords
local previewCoords
local previewModelMin
local previewHitEntity
local previewHitNormal
local previewHitType

local trackedObjects = {}
local trackedByNetId = {}
local trackingThread

local DEFAULT_RAY_FLAGS = 1 | 2 | 4 | 8

local function cloneTable(source)
    if not source then return nil end
    local target = {}
    for k, v in pairs(source) do
        target[k] = v
    end
    return target
end

local function resolveAttachmentBreak(itemName)
    local base = cloneTable(Config.AttachmentBreak)
    local override
    if itemName and Config.Placeables and Config.Placeables[itemName] then
        override = Config.Placeables[itemName].attachmentBreak
    end

    if override then
        if not base then base = {} end
        for k, v in pairs(override) do
            base[k] = v
        end
    end

    if not base or base.enabled == false then
        return nil
    end

    local cfg = {
        checkInterval = tonumber(base.checkInterval) or 300,
        minCollisionSpeed = tonumber(base.minCollisionSpeed or base.collisionSpeed),
        minSpeedDelta = tonumber(base.minSpeedDelta or base.speedDelta),
        minVectorSpeedDelta = tonumber(base.minVectorSpeedDelta or base.vectorSpeedDelta),
        requireCollision = base.requireCollision ~= false,
        pitchLimit = base.pitchLimit and tonumber(base.pitchLimit) or nil,
        rollLimit = base.rollLimit and tonumber(base.rollLimit) or nil,
        upsideDownTime = base.upsideDownTime and tonumber(base.upsideDownTime) or nil,
    }

    if cfg.minCollisionSpeed and cfg.minCollisionSpeed < 0.0 then cfg.minCollisionSpeed = 0.0 end
    if cfg.minSpeedDelta and cfg.minSpeedDelta < 0.0 then cfg.minSpeedDelta = 0.0 end
    if cfg.minVectorSpeedDelta and cfg.minVectorSpeedDelta < 0.0 then cfg.minVectorSpeedDelta = 0.0 end
    if cfg.upsideDownTime and cfg.upsideDownTime < 0 then cfg.upsideDownTime = 0 end

    return cfg
end

local function velocityMagnitude(entity)
    local vx, vy, vz = table.unpack(GetEntityVelocity(entity))
    return math.sqrt(vx * vx + vy * vy + vz * vz)
end

local maxDistance = Config.MaxPlacementDistance or 8.0
local minDistance = Config.MinPlacementDistance or 0.8
local minFromPed  = Config.MinDistanceFromPed or 1.0
local forwardBias = Config.ForwardBiasMeters or 0.0
local controls = Config.Controls or {}
local rotateStep = Config.RotateStep or 5.0
local freezePlaced = Config.FreezePlacedObjects ~= false
local pickupControl = controls.pickup or 38

local pickupPromptText = 'Press ~INPUT_PICKUP~ to collect'
local isPickingUp = false

---------------------------------------------------------------------
-- Utils
---------------------------------------------------------------------
local function notify(text, type)
    if lib and lib.notify then
        lib.notify({ title = 'Placeable Items', description = text, type = type or 'inform' })
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function showHelpNotification(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function wasControlJustPressed(control)
    return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control)
end

local function draw3DText(x, y, z, text)
    local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)
    if not onScreen then return end

    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextCentre(true)
    SetTextOutline()

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(screenX, screenY)
end

local function playPickupAnimation(ped)
    local dict = 'anim@mp_snowball'
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end

    TaskPlayAnim(ped, dict, 'pickup_snowball', 8.0, -8.0, 700, 48, 0.0, false, false, false)
    Wait(550)
    ClearPedTasks(ped)
    RemoveAnimDict(dict)
end

local function attemptPickup(info, data, object, coords)
    if isPickingUp then return end
    if not info or not data or not object or not DoesEntityExist(object) then return end
    if not info.item then return end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    if IsPedInAnyVehicle(ped, false) then return end

    local pedCoords = GetEntityCoords(ped)
    local px, py, pz = pedCoords.x, pedCoords.y, pedCoords.z
    local ox, oy, oz = coords.x, coords.y, coords.z
    local dist = math.sqrt((px - ox) * (px - ox) + (py - oy) * (py - oy) + (pz - oz) * (pz - oz))
    local interactDist = data.interactDistance or 2.0
    if dist > interactDist + 0.25 then return end

    local netId = info.netId
    if not netId or netId == 0 then
        netId = NetworkGetNetworkIdFromEntity(object)
    end

    if not netId or netId == 0 then
        notify('Impossible de récupérer cet objet pour le moment.', 'error')
        return
    end

    info.netId = netId

    isPickingUp = true

    TaskTurnPedToFaceCoord(ped, ox, oy, oz, 500)
    Wait(150)
    playPickupAnimation(ped)

    TriggerServerEvent('outlaw_placeables:pickup', netId, info.item)

    Wait(200)
    isPickingUp = false
end

local function requestModel(model)
    if type(model) == 'string' then model = joaat(model) end
    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(0) end
    end
    return model
end

---------------------------------------------------------------------
-- Raycasts + ground
---------------------------------------------------------------------
local function raycast(from, to, flags, ignoreEnt)
    local handle = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, flags or DEFAULT_RAY_FLAGS, ignoreEnt or 0, 7)
    local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(handle)
    return hit == 1, endCoords, surfaceNormal, entityHit
end

local function getGroundZ(x, y, zStart)
    local ok, gz = GetGroundZFor_3dCoord(x, y, zStart or 1000.0, false)
    if ok then return gz end
    local hit, pos = raycast(vector3(x, y, (zStart or 50.0)), vector3(x, y, (zStart or 50.0) - 60.0), DEFAULT_RAY_FLAGS, PlayerPedId())
    if hit then return pos.z end
    return nil
end

local function raycastGroundZ(x, y, zStart, ignoreEntity)
    local handle = StartShapeTestRay(x, y, zStart + 5.0, x, y, zStart - 100.0, DEFAULT_RAY_FLAGS, ignoreEntity or 0, 7)
    local _, hit, hitCoords = GetShapeTestResult(handle)
    if hit == 1 then return hitCoords.z end
    local ok, gz = GetGroundZFor_3dCoord(x, y, zStart + 5.0, false)
    if ok then return gz end
    return nil
end

---------------------------------------------------------------------
-- Tracking des objets placés
---------------------------------------------------------------------

local function cleanupTracked(id)
    local info = trackedObjects[id]
    if not info then return end
    if info.netId and trackedByNetId[info.netId] == id then
        trackedByNetId[info.netId] = nil
    end
    trackedObjects[id] = nil
end

local function tryAttachToEntity(info)
    local attach = info.attachment
    if not attach or not attach.netId or attach.netId == 0 then return false end
    if not NetworkDoesEntityExistWithNetworkId(attach.netId) then return false end

    local target = NetworkGetEntityFromNetworkId(attach.netId)
    if not target or target == 0 or not DoesEntityExist(target) then return false end

    local offset = attach.offset or {}
    local rot    = attach.rot or {}
    local ox = offset.x or 0.0
    local oy = offset.y or 0.0
    local oz = offset.z or 0.0
    local rx = rot.x or 0.0
    local ry = rot.y or 0.0
    local rz = rot.z or 0.0

    local disableCollision = attach.disableCollision ~= false

    FreezeEntityPosition(info.entity, false)
    SetEntityHasGravity(info.entity, false)
    if disableCollision then
        SetEntityCollision(info.entity, false, false)
        SetEntityNoCollisionEntity(info.entity, target, true)
    end

    AttachEntityToEntity(info.entity, target, attach.bone or 0, ox, oy, oz, rx, ry, rz, false, attach.useSoftPinning ~= false, not disableCollision, IsEntityAPed(target), 2, true)

    info.attached = true
    info.attachedTo = attach.netId
    info.attachFailTime = nil
    info.lastTargetSpeed = velocityMagnitude(target)
    local vx, vy, vz = table.unpack(GetEntityVelocity(target))
    info.lastTargetVelocity = vector3(vx, vy, vz)
    info.lastBreakCheck = GetGameTimer()
    info.upsideDownStart = nil
    maybeClearRecovery(info, true)
    return true
end

local function dropObjectToGround(info)
    local object = info.entity
    if not object or not DoesEntityExist(object) then return end

    DetachEntity(object, true, true)
    SetEntityHasGravity(object, true)
    SetEntityCollision(object, true, true)

    local base = info.base or GetEntityCoords(object)
    local offset = info.offset or 0.0
    local gz = info.groundZ or raycastGroundZ(base.x, base.y, base.z + 1.0, object)
    if not gz then gz = base.z end

    local freezeAfter = info.shouldFreeze or freezePlaced
    if freezeAfter then FreezeEntityPosition(object, false) end
    SetEntityCoords(object, base.x, base.y, gz + offset, false, false, false)
    SetEntityVelocity(object, 0.0, 0.0, 0.0)
    PlaceObjectOnGroundProperly(object); Wait(0)
    PlaceObjectOnGroundProperly(object)
    if freezeAfter then FreezeEntityPosition(object, true) end

    info.base = vector3(base.x, base.y, gz)
    info.groundZ = gz
    info.surfaceType = 'world'
    info.attachment = nil
    info.attached = false
    info.attachedTo = nil
    info.shouldFreeze = freezeAfter
    info.attachFailTime = nil
    info.lastTargetSpeed = nil
    info.lastTargetVelocity = nil
    info.lastBreakCheck = nil
    info.upsideDownStart = nil
    maybeClearRecovery(info, true)
end

local function checkAttachmentBreak(info, target)
    local cfg = info.attachmentBreak
    if not cfg then return end

    local now = GetGameTimer()
    local interval = cfg.checkInterval or 0
    if interval > 0 and info.lastBreakCheck and (now - info.lastBreakCheck) < interval then
        return
    end

    local detach = false
    local collided = false
    local shouldCheckCollision = cfg.requireCollision or (cfg.minCollisionSpeed and cfg.minCollisionSpeed > 0.0) or (cfg.minSpeedDelta and cfg.minSpeedDelta > 0.0)

    if shouldCheckCollision then
        collided = HasEntityCollidedWithAnything(target)
    end

    if cfg.upsideDownTime and cfg.upsideDownTime > 0 then
        if IsEntityUpsidedown(target) then
            if not info.upsideDownStart then
                info.upsideDownStart = now
            elseif now - info.upsideDownStart >= cfg.upsideDownTime then
                detach = true
            end
        else
            info.upsideDownStart = nil
        end
    end

    if not detach and (cfg.pitchLimit or cfg.rollLimit) then
        local rot = GetEntityRotation(target, 2)
        if cfg.pitchLimit and math.abs(rot.x) >= cfg.pitchLimit then
            detach = true
        elseif cfg.rollLimit then
            local roll = GetEntityRoll and GetEntityRoll(target) or rot.y
            if math.abs(roll) >= cfg.rollLimit then
                detach = true
            end
        end
    end

    local speed = velocityMagnitude(target)
    local lastSpeed = info.lastTargetSpeed or speed
    local vx, vy, vz = table.unpack(GetEntityVelocity(target))
    local lastVelocity = info.lastTargetVelocity
    local speedDelta = math.abs(speed - lastSpeed)
    local minCollisionSpeed = cfg.minCollisionSpeed or 0.0

    if not detach and cfg.minSpeedDelta and cfg.minSpeedDelta > 0.0 then
        if speedDelta >= cfg.minSpeedDelta and (lastSpeed >= minCollisionSpeed or speed >= minCollisionSpeed) then
            if not cfg.requireCollision or collided then
                detach = true
            end
        end
    end

    if not detach and minCollisionSpeed > 0.0 then
        if (lastSpeed >= minCollisionSpeed or speed >= minCollisionSpeed) and collided then
            detach = true
        end
    end

    if not detach and cfg.minVectorSpeedDelta and cfg.minVectorSpeedDelta > 0.0 and lastVelocity then
        local dvx = vx - lastVelocity.x
        local dvy = vy - lastVelocity.y
        local dvz = vz - lastVelocity.z
        local vectorDelta = math.sqrt(dvx * dvx + dvy * dvy + dvz * dvz)
        if vectorDelta >= cfg.minVectorSpeedDelta then
            if not cfg.requireCollision or collided or speed >= minCollisionSpeed or lastSpeed >= minCollisionSpeed then
                detach = true
            end
        end
    end

    if not detach and cfg.requireCollision and collided then
        detach = true
    end

    info.lastTargetSpeed = speed
    info.lastTargetVelocity = vector3(vx, vy, vz)
    info.lastBreakCheck = now

    if detach then
        dropObjectToGround(info)
    end
end

local function snapObjectToSurface(info, baseCoords, surfaceType)
    local object = info.entity
    if not object or not DoesEntityExist(object) then return end

    local offset = info.offset or 0.0
    local freeze = info.shouldFreeze

    if freeze then FreezeEntityPosition(object, false) end

    SetEntityVelocity(object, 0.0, 0.0, 0.0)
    SetEntityCoords(object, baseCoords.x, baseCoords.y, baseCoords.z + offset, false, false, false)

    if surfaceType == 'world' then
        PlaceObjectOnGroundProperly(object); Wait(0)
        PlaceObjectOnGroundProperly(object)
        local finalCoords = GetEntityCoords(object)
        baseCoords = vector3(finalCoords.x, finalCoords.y, finalCoords.z - offset)
    end

    if freeze then FreezeEntityPosition(object, true) end

    info.base = baseCoords
    info.groundZ = baseCoords.z
    info.surfaceType = surfaceType or 'world'
    info.lastSnapTime = GetGameTimer()
end

local function isSurfaceFloorLike(surface)
    if not surface then return true end

    local normal = surface.normal
    if normal and normal.z then
        return normal.z >= 0.45
    end

    if surface.entityType == 2 then
        return true
    end

    return normal == nil
end

local function markRecoveryAttempt(info)
    local now = GetGameTimer()
    local stats = info.recoveryStats
    if not stats then
        stats = { count = 0, last = 0 }
        info.recoveryStats = stats
    elseif now - (stats.last or 0) > 6000 then
        stats.count = 0
    end

    stats.count = stats.count + 1
    stats.last = now
    return stats.count
end

local function maybeClearRecovery(info, force)
    local stats = info.recoveryStats
    if not stats then return end

    local now = GetGameTimer()
    if force or now - (stats.last or 0) > 8000 then
        info.recoveryStats = nil
    end
end

local function ensureTrackingThread()
    if trackingThread then return end

    trackingThread = CreateThread(function()
        while true do
            if next(trackedObjects) then
                for id, info in pairs(trackedObjects) do
                    local object = info.entity
                    if not object or not DoesEntityExist(object) then
                        cleanupTracked(id)
                    elseif info.attachment then
                        if info.attached then
                            local target = info.attachedTo and NetworkGetEntityFromNetworkId(info.attachedTo)
                            if not target or target == 0 or not DoesEntityExist(target) then
                                dropObjectToGround(info)
                            else
                                local coords = GetEntityCoords(object)
                                local offset = info.offset or 0.0
                                info.base = vector3(coords.x, coords.y, coords.z - offset)
                                info.groundZ = raycastGroundZ(coords.x, coords.y, coords.z, object) or (coords.z - offset)
                                if info.attachmentBreak then
                                    checkAttachmentBreak(info, target)
                                end
                            end
                        else
                            if not tryAttachToEntity(info) then
                                local now = GetGameTimer()
                                if info.attachFailTime then
                                    if now - info.attachFailTime > 5000 then
                                        dropObjectToGround(info)
                                    end
                                else
                                    info.attachFailTime = now
                                end
                            end
                        end
                    else
                        local coords = GetEntityCoords(object)
                        local base = info.base or coords
                        local offset = info.offset or 0.0
                        local threshold = offset + (info.shouldFreeze and 0.6 or 1.2)
                        local surfaceType = info.surfaceType or 'world'
                        local groundZ = info.groundZ or base.z
                        local fellBelowBase = coords.z + 0.01 < (base.z + offset - threshold)
                        local fellBelowGround = coords.z < (groundZ - 1.0)
                        local underMap = coords.z < -20.0

                        if fellBelowBase or fellBelowGround or underMap then
                            local targetSurface = surfaceType
                            local targetX, targetY = base.x, base.y
                            local targetBaseZ

                            if targetSurface ~= 'world' and not underMap and not fellBelowGround then
                                targetBaseZ = base.z
                            else
                                targetX, targetY = coords.x, coords.y
                                local hint = math.max(coords.z + offset, base.z + offset) + 2.0
                                targetBaseZ = raycastGroundZ(targetX, targetY, hint, object)
                                if not targetBaseZ then
                                    targetBaseZ = raycastGroundZ(base.x, base.y, base.z + offset + 2.0, object)
                                end
                                if not targetBaseZ then
                                    targetBaseZ = groundZ
                                end
                                targetSurface = 'world'
                            end

                            if not info.shouldFreeze and (fellBelowGround or underMap or targetSurface == 'world') then
                                local recoverCount = markRecoveryAttempt(info)
                                if recoverCount >= 3 then
                                    info.shouldFreeze = true
                                    maybeClearRecovery(info, true)
                                end
                            end

                            if targetBaseZ then
                                snapObjectToSurface(info, vector3(targetX, targetY, targetBaseZ), targetSurface)
                            end
                        else
                            maybeClearRecovery(info, false)
                        end
                    end
                end
                Wait(500)
            else
                Wait(1000)
            end
        end
    end)
end

local function registerTrackedObject(data, object, targetCoords, shouldFreeze)
    if not data or not data.id or not object or not DoesEntityExist(object) then return end

    local existing = trackedObjects[data.id]
    if existing and existing.entity and DoesEntityExist(existing.entity) then
        DeleteEntity(existing.entity)
    end
    cleanupTracked(data.id)

    local base = data.base and vector3(data.base.x, data.base.y, data.base.z) or targetCoords
    local info = {
        id = data.id,
        entity = object,
        item = data.item,
        base = base,
        offset = data.offset or 0.0,
        shouldFreeze = shouldFreeze and true or false,
        surfaceType = data.surface and data.surface.type or 'world',
        attachment = data.surface and data.surface.attachment or nil,
        surfaceEntityType = data.surface and data.surface.entityType or nil,
    }

    if info.attachment and (not info.attachment.netId or info.attachment.netId == 0) then
        info.attachment = nil
        info.surfaceType = 'world'
    elseif info.attachment then
        info.surfaceType = 'entity'
        local att = info.attachment
        info.attachment = {
            netId = att.netId,
            bone = att.bone,
            disableCollision = att.disableCollision,
            useSoftPinning = att.useSoftPinning,
        }
        if att.offset then
            info.attachment.offset = {
                x = att.offset.x or 0.0,
                y = att.offset.y or 0.0,
                z = att.offset.z or 0.0
            }
        end
        if att.rot then
            info.attachment.rot = {
                x = att.rot.x or 0.0,
                y = att.rot.y or 0.0,
                z = att.rot.z or 0.0
            }
        end
        if info.attachment.disableCollision == nil then
            info.attachment.disableCollision = true
        end
        if info.attachment.useSoftPinning == nil then
            info.attachment.useSoftPinning = true
        end
        info.attachment.entityType = info.surfaceEntityType
        if info.surfaceEntityType == 2 then
            info.attachmentBreak = resolveAttachmentBreak(data.item)
        end
    end

    info.groundZ = raycastGroundZ(base.x, base.y, base.z + 1.0, object) or base.z
    info.netId = NetworkGetNetworkIdFromEntity(object)
    if info.netId and info.netId ~= 0 then
        trackedByNetId[info.netId] = data.id
    end
    info.attachFailTime = nil

    trackedObjects[data.id] = info
    ensureTrackingThread()

    if info.attachment then
        tryAttachToEntity(info)
    end
end

---------------------------------------------------------------------
-- Forwards
---------------------------------------------------------------------
local function rotationToDirection(rot)
    local rx = math.rad(rot.x)
    local rz = math.rad(rot.z)
    return vector3(
        -math.sin(rz) * math.abs(math.cos(rx)),
         math.cos(rz) * math.abs(math.cos(rx)),
         math.sin(rx)
    )
end

local function getPedForward(ped)
    local h = math.rad(GetEntityHeading(ped))
    return vector3(-math.sin(h), math.cos(h), 0.0)
end

---------------------------------------------------------------------
-- Preview appearance
---------------------------------------------------------------------
local function updatePreviewAppearance(isValid)
    if not previewEntity or not DoesEntityExist(previewEntity) then return end
    local alpha = isValid and 160 or 110
    SetEntityAlpha(previewEntity, alpha, false)
    if SetEntityDrawOutline and SetEntityDrawOutlineColor then
        if isValid then SetEntityDrawOutlineColor(60,200,60,200) else SetEntityDrawOutlineColor(200,80,60,200) end
        SetEntityDrawOutline(previewEntity, true)
    end
end

---------------------------------------------------------------------
-- Preview position
---------------------------------------------------------------------
local function updatePreviewPosition(modelHash, aimDist)
    if not previewEntity or not DoesEntityExist(previewEntity) then return nil, 0.0 end

    local ped = PlayerPedId()
    local pedPos = GetEntityCoords(ped)
    local camRot = GetGameplayCamRot(2)
    local camPos = GetGameplayCamCoord()

    previewHitEntity = nil
    previewHitNormal = nil
    previewHitType = nil

    local forward = (Config.PreviewForward == 'ped') and getPedForward(ped) or rotationToDirection(camRot)

    local base
    if Config.PreviewForward == 'ped' then
        local guess = pedPos + (forward * math.min(aimDist, maxDistance))
        local gz = getGroundZ(guess.x, guess.y, pedPos.z + 1.5) or pedPos.z
        base = vector3(guess.x, guess.y, gz)

        -- Clamp uniquement en mode ped
        local delta = base - pedPos
        local planar = vector3(delta.x, delta.y, 0.0)
        local planarDist = #(planar)
        if planarDist < minFromPed then
            local dir = planarDist > 0.001 and (planar / planarDist) or getPedForward(ped)
            local newXY = pedPos + (dir * minFromPed)
            local gz2 = getGroundZ(newXY.x, newXY.y, base.z + 1.0) or base.z
            base = vector3(newXY.x, newXY.y, gz2)
        end
    else
        -- CAMERA MODE: distance pure le long du rayon de la caméra (aucun clamp au ped)
        local dist = math.min(math.max(aimDist + forwardBias, minDistance), maxDistance)
        local to = camPos + (forward * dist)
        local hit, hitPos, hitNormal, hitEntity = raycast(camPos, to, DEFAULT_RAY_FLAGS, ped)

        if hit then
            -- IMPORTANT: NE PAS remapper sur le sol si on a touché une entité (voiture, objet, map)
            -- On garde la Z exacte du point d'impact, puis on pousse légèrement dans la normale pour éviter le z-fight.
            local lift = 0.0025
            local n = hitNormal or vec3(0,0,1)
            local refinedFrom = hitPos + (n * 0.15)
            local refinedTo   = hitPos - (n * 0.30)
            local h2, h2Pos, _, h2Ent = raycast(refinedFrom, refinedTo, DEFAULT_RAY_FLAGS, ped)
            if h2 and h2Ent == hitEntity then
                hitPos = h2Pos + (n * lift)
            else
                hitPos = hitPos + (n * lift)
            end
            base = vector3(hitPos.x, hitPos.y, hitPos.z)
            previewHitEntity = hitEntity
            previewHitNormal = n
            previewHitType = hitEntity and GetEntityType(hitEntity) or nil
        else
            -- Pas d'impact: on retombe sur l'estimation au sol
            local guess = camPos + (forward * dist)
            local gz = getGroundZ(guess.x, guess.y, pedPos.z + 1.5) or pedPos.z
            base = vector3(guess.x, guess.y, gz)
            previewHitEntity = nil
            previewHitNormal = nil
            previewHitType = nil
        end
    end

    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        while not HasModelLoaded(modelHash) do Wait(0) end
    end
    local min, max = GetModelDimensions(modelHash)
    previewModelMin = min
    local heightOffset = (min and min.z) and -min.z or 0.0

    local heading = previewRotation % 360.0
    SetEntityCollision(previewEntity, false, false)
    SetEntityCoords(previewEntity, base.x, base.y, base.z + heightOffset, false, false, false)
    SetEntityHeading(previewEntity, heading)

    local epos = GetEntityCoords(previewEntity)
    local downHit, downPos, _, downEntity = raycast(epos + vec3(0,0,0.8), epos - vec3(0,0,2.5), DEFAULT_RAY_FLAGS, ped)
    if downHit and downEntity and IsEntityAPed(downEntity) then
        downHit = false
    end

    if downHit then
        SetEntityCoords(previewEntity, downPos.x, downPos.y, downPos.z + heightOffset, false, false, false)
        base = vector3(downPos.x, downPos.y, downPos.z)
    end

    local placement = {
        position = { x = base.x, y = base.y, z = base.z + heightOffset },
        base = { x = base.x, y = base.y, z = base.z },
        offset = heightOffset
    }
    return placement, heading
end

---------------------------------------------------------------------
-- Cleanup preview
---------------------------------------------------------------------
local function destroyPreview()
    if previewEntity and DoesEntityExist(previewEntity) then
        if SetEntityDrawOutline then SetEntityDrawOutline(previewEntity, false) end
        if ResetEntityAlpha then ResetEntityAlpha(previewEntity) else SetEntityAlpha(previewEntity, 255, false) end
        DeleteEntity(previewEntity)
    end
    previewEntity, activeItem, previewModelMin = nil, nil, nil
    previewRotation, previewValid = 0.0, false
    previewBaseOffset, previewSurfaceOffset = 0.0, nil
    previewHitCoords, previewCoords = nil, nil
    previewHitType = nil
    placementThread, placing = nil, false
    ClearAllHelpMessages()
end

---------------------------------------------------------------------
-- Final settle
---------------------------------------------------------------------
local function settleObjectOnSurface(obj, x, y, z, heading, freeze)
    RequestCollisionAtCoord(x, y, z)
    while not HasCollisionLoadedAroundEntity(obj) do Wait(0) end
    if heading then SetEntityHeading(obj, heading + 0.0) end

    SetEntityCoords(obj, x, y, z + 0.05, false, false, false)
    local gz = raycastGroundZ(x, y, z, obj) or z
    SetEntityCoords(obj, x, y, gz + 0.02, false, false, false)
    PlaceObjectOnGroundProperly(obj); Wait(0)
    PlaceObjectOnGroundProperly(obj)

    if freeze then FreezeEntityPosition(obj, true) end
end

---------------------------------------------------------------------
-- Placement loop
---------------------------------------------------------------------
local function handlePlacementLoop(modelHash)
    placementThread = CreateThread(function()
        local confirmControl = controls.confirm or 24
        local cancelControl  = controls.cancel  or 25
        local rotateLeftControl  = controls.rotateLeft  or 44
        local rotateRightControl = controls.rotateRight or 38
        local incDist = controls.distIncrease or 241
        local decDist = controls.distDecrease or 242

        local aimDist = math.min(maxDistance, math.max(minDistance, maxDistance * 0.6))

        while placing do
            Wait(0)

            DisableControlAction(0, confirmControl, true)
            DisableControlAction(0, cancelControl, true)
            DisableControlAction(0, rotateLeftControl, true)
            DisableControlAction(0, rotateRightControl, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 38, true)
            DisablePlayerFiring(PlayerId(), true)

            if Config.DistanceScroll then
                if wasControlJustPressed(incDist) then
                    aimDist = math.min(maxDistance, aimDist + 0.5)
                elseif wasControlJustPressed(decDist) then
                    aimDist = math.max(minDistance, aimDist - 0.5)
                end
            end

            local placement, heading = updatePreviewPosition(modelHash, aimDist)
            local ped = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)

            previewValid = false
            if placement and placement.base then
                local surfaceBase = vector3(placement.base.x, placement.base.y, placement.base.z)
                local dist = #(pedCoords - surfaceBase)
                previewValid = (dist <= (maxDistance + 0.05))
                previewCoords = vector3(placement.position.x, placement.position.y, placement.position.z)
                previewHitCoords = surfaceBase
                previewSurfaceOffset = placement.offset
                SetEntityHeading(previewEntity, heading)
            end

            updatePreviewAppearance(previewValid)
            showHelpNotification('~INPUT_ATTACK~ Placer  ~INPUT_AIM~ Annuler  ~INPUT_COVER~/~INPUT_PICKUP~ Tourner  Molette: Distance')

            if wasControlJustPressed(rotateLeftControl) then
                previewRotation = (previewRotation - rotateStep) % 360.0
                if previewEntity and DoesEntityExist(previewEntity) then
                    SetEntityHeading(previewEntity, previewRotation)
                end

            elseif wasControlJustPressed(rotateRightControl) then
                previewRotation = (previewRotation + rotateStep) % 360.0
                if previewEntity and DoesEntityExist(previewEntity) then
                    SetEntityHeading(previewEntity, previewRotation)
                end

            elseif wasControlJustPressed(confirmControl) then
                if not previewValid or not previewCoords or not previewHitCoords then
                    notify("Impossible de placer l'objet ici.", 'error')
                    goto continue
                end

                ClearHelp(true)

                local itemName     = activeItem
                local finalCoords  = vector3(previewCoords.x, previewCoords.y, previewCoords.z)
                local hitBase      = vector3(previewHitCoords.x, previewHitCoords.y, previewHitCoords.z)
                local finalHeading = previewRotation
                local finalOffset  = previewSurfaceOffset or 0.0

                local attachmentData
                local surfaceType = 'world'
                local entityType = previewHitType

                if previewHitEntity and DoesEntityExist(previewHitEntity) then
                    if previewHitType == 1 or previewHitType == 2 then
                        local targetNetId = NetworkGetNetworkIdFromEntity(previewHitEntity)
                        if targetNetId and targetNetId ~= 0 then
                            local relative = GetOffsetFromEntityGivenWorldCoords(previewHitEntity, finalCoords.x, finalCoords.y, finalCoords.z)
                            local objectRot = GetEntityRotation(previewEntity, 2)
                            local targetRot = GetEntityRotation(previewHitEntity, 2)
                            local relRot = vector3(objectRot.x - targetRot.x, objectRot.y - targetRot.y, objectRot.z - targetRot.z)
                            attachmentData = {
                                netId = targetNetId,
                                offset = { x = relative.x, y = relative.y, z = relative.z },
                                rot = { x = relRot.x, y = relRot.y, z = relRot.z },
                                entityType = previewHitType,
                                disableCollision = true,
                                useSoftPinning = true,
                            }
                            surfaceType = 'entity'
                        end
                    elseif previewHitType == 3 then
                        surfaceType = 'object'
                    end
                end

                local surfaceInfo = {
                    type = surfaceType,
                    entityType = entityType,
                    attachment = attachmentData,
                }
                if previewHitNormal then
                    surfaceInfo.normal = { x = previewHitNormal.x, y = previewHitNormal.y, z = previewHitNormal.z }
                end

                destroyPreview()

                TriggerServerEvent('outlaw_placeables:placeObject', itemName, {
                    position = { x = finalCoords.x, y = finalCoords.y, z = finalCoords.z },
                    base     = { x = hitBase.x,    y = hitBase.y,    z = hitBase.z    },
                    offset   = finalOffset,
                    surface  = surfaceInfo,
                }, finalHeading)
                break

            elseif wasControlJustPressed(cancelControl) then
                ClearHelp(true)
                local itemName = activeItem
                TriggerServerEvent('outlaw_placeables:cancelPlacement', itemName)
                destroyPreview()
                break
            end

            ::continue::
        end
    end)
end

---------------------------------------------------------------------
-- Start preview
---------------------------------------------------------------------
RegisterNetEvent('outlaw_placeables:startPlacement', function(itemName, modelName)
    if placing then
        notify('Vous placez déjà un objet.', 'error')
        return
    end

    local itemConfig = Config.Placeables[itemName]
    if not itemConfig then
        notify('Objet non configuré pour le placement.', 'error')
        return
    end

    if exports.ox_inventory and exports.ox_inventory.closeInventory then
        exports.ox_inventory:closeInventory()
    else
        TriggerEvent('ox_inventory:closeInventory')
    end

    placing = true
    activeItem = itemName
    previewRotation = GetEntityHeading(PlayerPedId())

    local modelHash = requestModel(modelName)

    local ok, minDim = pcall(GetModelDimensions, modelHash)
    if ok and minDim then
        previewBaseOffset = -(minDim.z or 0.0)
        previewModelMin = minDim
    else
        previewBaseOffset = 0.0
        previewModelMin = nil
    end

    local pedCoords = GetEntityCoords(PlayerPedId())
    previewEntity = CreateObject(modelHash, pedCoords.x, pedCoords.y, pedCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)

    updatePreviewAppearance(false)
    SetEntityCollision(previewEntity, false, false)
    FreezeEntityPosition(previewEntity, true)

    handlePlacementLoop(modelHash)
end)

---------------------------------------------------------------------
-- Final spawn
---------------------------------------------------------------------
RegisterNetEvent('outlaw_placeables:spawnObject', function(data)
    local model = requestModel(data.model)
    local baseCoords = vector3(data.coords.x, data.coords.y, data.coords.z)
    local object = CreateObject(model, baseCoords.x, baseCoords.y, baseCoords.z, true, true, true)
    SetModelAsNoLongerNeeded(model)

    SetEntityDynamic(object, true)
    if ActivatePhysics then ActivatePhysics(object) end
    if SetEntityLoadCollisionFlag then SetEntityLoadCollisionFlag(object, true, true) end

    local offset = (type(data.offset) == 'number') and data.offset or 0.0
    local hasSurface = data.base and data.base.x and data.base.y and data.base.z
    local targetCoords
    if hasSurface then
        targetCoords = vector3(data.base.x, data.base.y, data.base.z + offset)
    else
        local surfaceZ = raycastGroundZ(baseCoords.x, baseCoords.y, baseCoords.z, object) or baseCoords.z
        targetCoords = vector3(baseCoords.x, baseCoords.y, surfaceZ + offset)
    end

    local surfaceInfo = data.surface
    if not surfaceInfo then
        surfaceInfo = {}
        data.surface = surfaceInfo
    end

    local attachmentInfo = surfaceInfo.attachment
    if attachmentInfo and not freezePlaced and isSurfaceFloorLike(surfaceInfo) then
        surfaceInfo.attachment = nil
        attachmentInfo = nil
        surfaceInfo.type = 'world'
    end

    if not surfaceInfo.attachment and surfaceInfo.type == 'entity' then
        surfaceInfo.type = 'world'
    end

    local hasAttachment = attachmentInfo ~= nil

    SetEntityCollision(object, true, true)
    SetEntityHasGravity(object, not hasAttachment)
    FreezeEntityPosition(object, false)

    local heading = data.heading or 0.0
    local shouldFreeze = freezePlaced and not hasAttachment
    -- settle
    RequestCollisionAtCoord(targetCoords.x, targetCoords.y, targetCoords.z)
    while not HasCollisionLoadedAroundEntity(object) do Wait(0) end
    if hasSurface then
        SetEntityCoords(object, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false)
    else
        SetEntityCoordsNoOffset(object, targetCoords.x, targetCoords.y, targetCoords.z + 0.05, false, false, false)
        local gz = raycastGroundZ(targetCoords.x, targetCoords.y, targetCoords.z, object) or targetCoords.z
        SetEntityCoords(object, targetCoords.x, targetCoords.y, gz + 0.02, false, false, false)
        PlaceObjectOnGroundProperly(object); Wait(0)
        PlaceObjectOnGroundProperly(object)
    end
    SetEntityHeading(object, heading)
    if shouldFreeze then FreezeEntityPosition(object, true) end

    SetEntityAsMissionEntity(object, true, true)
    SetEntityLodDist(object, 1024)

    registerTrackedObject(data, object, targetCoords, shouldFreeze)

    local entity = Entity(object)
    entity.state:set('placeableItem', data.item, true)
    entity.state:set('placeableId', data.id, true)

    if data.owner == GetPlayerServerId(PlayerPedId()) then
        local netId = NetworkGetNetworkIdFromEntity(object)
        SetNetworkIdExistsOnAllMachines(netId, true)
        SetNetworkIdCanMigrate(netId, true)
        TriggerServerEvent('outlaw_placeables:registerObject', data.id, netId)
    end
end)

RegisterNetEvent('outlaw_placeables:removeObject', function(netId)
    if netId then
        local trackedId = trackedByNetId[netId]
        if trackedId then
            cleanupTracked(trackedId)
        else
            for id, info in pairs(trackedObjects) do
                if info.netId == netId then
                    cleanupTracked(id)
                    break
                end
            end
        end
    end
    if not NetworkDoesNetworkIdExist(netId) then return end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end)

RegisterNetEvent('outlaw_placeables:placementFailed', function(message)
    notify(message or 'Placement refusé.', 'error')
end)

RegisterNetEvent('outlaw_placeables:notify', function(message, type)
    notify(message, type)
end)

---------------------------------------------------------------------
-- Manual pickup prompt
---------------------------------------------------------------------

CreateThread(function()
    while true do
        if not next(trackedObjects) then
            Wait(400)
        else
            local ped = PlayerPedId()
            if not DoesEntityExist(ped) or IsEntityDead(ped) then
                Wait(400)
            else
                local pedCoords = GetEntityCoords(ped)
                local px, py, pz = pedCoords.x, pedCoords.y, pedCoords.z
                local nearestInfo, nearestData, nearestObject, nearestCoords, nearestDistance

                for _, info in pairs(trackedObjects) do
                    local object = info.entity
                    if object and DoesEntityExist(object) and info.item then
                        local data = Config.Placeables and Config.Placeables[info.item]
                        if data then
                            local objectCoords = GetEntityCoords(object)
                            local ox, oy, oz = objectCoords.x, objectCoords.y, objectCoords.z
                            local dx, dy, dz = px - ox, py - oy, pz - oz
                            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                            local interact = data.interactDistance or 2.0

                            if dist <= interact and (not nearestDistance or dist < nearestDistance) then
                                nearestDistance = dist
                                nearestInfo = info
                                nearestData = data
                                nearestObject = object
                                nearestCoords = objectCoords
                            end
                        end
                    end
                end

                if nearestInfo and nearestObject and nearestCoords then
                    local prompt = nearestData.pickupPrompt or pickupPromptText
                    local offset = nearestData.pickupTextOffset or 0.1
                    draw3DText(nearestCoords.x, nearestCoords.y, nearestCoords.z + offset, prompt)

                    if wasControlJustPressed(pickupControl) then
                        attemptPickup(nearestInfo, nearestData, nearestObject, nearestCoords)
                    end

                    Wait(0)
                else
                    Wait(150)
                end
            end
        end
    end
end)

---------------------------------------------------------------------
-- ox_target pickup
---------------------------------------------------------------------
CreateThread(function()
    if not exports.ox_target or not exports.ox_target.addModel then return end

    local addedModels = {}
    for itemName, data in pairs(Config.Placeables) do
        if data.models then
            for _, model in ipairs(data.models) do
                if not addedModels[model] then
                    exports.ox_target:addModel(model, {{
                        name = 'outlaw_placeables:pickup',
                        label = data.pickupLabel or ('Ramasser ' .. (data.label or "l'objet")),
                        icon = data.icon or 'fa-solid fa-hand',
                        distance = data.interactDistance or 2.0,
                        onSelect = function(targetData)
                            local entity = targetData.entity
                            local state = Entity(entity).state
                            if not state or not state.placeableItem then return end
                            local item = state.placeableItem
                            local netId = NetworkGetNetworkIdFromEntity(entity)
                            TriggerServerEvent('outlaw_placeables:pickup', netId, item)
                        end,
                        canInteract = function(entity)
                            local state = Entity(entity).state
                            return state and state.placeableItem ~= nil
                        end
                    }})
                    addedModels[model] = true
                end
            end
        end
    end
end)

---------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------
CreateThread(function()
    Wait(1500)
    TriggerServerEvent('outlaw_placeables:requestPlacedObjects')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    destroyPreview()
end)
