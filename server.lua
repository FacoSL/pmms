local mediaPlayers = {}
local restrictedHandles = {}
local syncQueue = {}

RegisterNetEvent("pmms:start")
RegisterNetEvent("pmms:init")
RegisterNetEvent("pmms:pause")
RegisterNetEvent("pmms:stop")
RegisterNetEvent("pmms:showControls")
RegisterNetEvent("pmms:toggleStatus")
RegisterNetEvent("pmms:setVolume")
RegisterNetEvent("pmms:setStartTime")
RegisterNetEvent("pmms:lock")
RegisterNetEvent("pmms:unlock")
RegisterNetEvent("pmms:enableVideo")
RegisterNetEvent("pmms:disableVideo")
RegisterNetEvent("pmms:setVideoSize")
RegisterNetEvent("pmms:mute")
RegisterNetEvent("pmms:unmute")
RegisterNetEvent("pmms:copy")
RegisterNetEvent("pmms:setLoop")
RegisterNetEvent("pmms:next")
RegisterNetEvent("pmms:removeFromQueue")
RegisterNetEvent("pmms:saveModel")
RegisterNetEvent("pmms:saveObject")
RegisterNetEvent("pmms:loadSettings")

local function enqueue(queue, cb)
	table.insert(queue, 1, cb)
end

local function dequeue(queue)
	local cb = table.remove(queue)

	if cb then
		cb()
	end
end

local function addToQueue(handle, source, url, volume, offset, filter, video)
	table.insert(mediaPlayers[handle].queue, {
		source = source,
		name = GetPlayerName(source),
		url = url,
		volume = volume,
		offset = offset,
		filter = filter,
		video = video
	})
end

local function removeFromQueue(handle, index)
	table.remove(mediaPlayers[handle].queue, index)
end

local function addMediaPlayer(handle, url, title, volume, offset, duration, loop, filter, locked, video, videoSize, muted, attenuation, range, visualization, queue, coords)
	if mediaPlayers[handle] then
		return
	end

	if attenuation then
		attenuation.sameRoom = Clamp(attenuation.sameRoom, 0.0, 10.0, defaultSameRoomAttenuation)
		attenuation.diffRoom = Clamp(attenuation.diffRoom, 0.0, 10.0, defaultDiffRoomAttenuation)
	else
		attenuation = {
			sameRoom = defaultSameRoomAttenuation,
			diffRoom = defaultDiffRoomAttenuation
		}
	end

	mediaPlayers[handle] = {
		url = url,
		title = title or url,
		volume = Clamp(volume, 0, 100, 100),
		startTime = os.time() - (offset or 0),
		offset = 0,
		duration = duration,
		loop = loop,
		filter = filter,
		locked = locked,
		video = video,
		videoSize = Clamp(videoSize, 10, 100, Config.defaultVideoSize),
		coords = coords,
		paused = false,
		muted = muted,
		attenuation = attenuation,
		range = Clamp(range, 0, Config.maxRange, Config.defaultRange),
		visualization = visualization,
		queue = queue or {}
	}

	enqueue(syncQueue, function()
		TriggerClientEvent("pmms:play", -1, handle)
	end)
end

local function removeMediaPlayer(handle)
	mediaPlayers[handle] = nil

	enqueue(syncQueue, function()
		TriggerClientEvent("pmms:stop", -1, handle)
	end)
end

local function playNextInQueue(handle)
	local mediaPlayer = mediaPlayers[handle]

	removeMediaPlayer(handle)

	while #mediaPlayer.queue > 0 do
		local next = table.remove(mediaPlayer.queue, 1)

		local client

		if GetPlayerName(next.source) == next.name then
			client = next.source
		else
			client = GetPlayers()[1]
		end

		if client then
			restrictedHandles[handle] = client

			enqueue(syncQueue, function()
				TriggerClientEvent("pmms:init",
					client,
					handle,
					next.url,
					next.volume,
					next.offset,
					mediaPlayer.loop,
					next.filter,
					mediaPlayer.locked,
					next.video,
					mediaPlayer.videoSize,
					mediaPlayer.muted,
					mediaPlayer.attenuation,
					mediaPlayer.range,
					mediaPlayer.visualization,
					mediaPlayer.queue,
					mediaPlayer.coords)
			end)

			break
		end
	end
end

local function pauseMediaPlayer(handle)
	if not mediaPlayers[handle] then
		return
	end

	if mediaPlayers[handle].paused then
		mediaPlayers[handle].startTime = mediaPlayers[handle].startTime + (os.time() - mediaPlayers[handle].paused)
		mediaPlayers[handle].paused = false
	else
		mediaPlayers[handle].paused = os.time()
	end
end

local function getRandomPreset()
	local presets = {}

	for preset, info in pairs(Config.presets) do
		table.insert(presets, preset)
	end

	return #presets > 0 and presets[math.random(#presets)] or ""
end

local function resolvePreset(url, title, filter, video)
	if url == "random" then
		url = getRandomPreset()
	end

	if Config.presets[url] then
		return Config.presets[url]
	else
		return {
			url = url,
			title = title,
			filter = filter,
			video = video
		}
	end
end

local function startMediaPlayerByNetworkId(netId, url, title, volume, offset, duration, loop, filter, locked, video, videoSize, muted, attenuation, range, visualization)
	local resolved = resolvePreset(url, title, filter, video)

	addMediaPlayer(netId,
		resolved.url,
		resolved.title,
		volume,
		offset,
		duration,
		loop,
		resolved.filter,
		locked,
		resolved.video,
		videoSize,
		muted,
		attenuation,
		range,
		visualization,
		false,
		false)

	return netId
end

local function startMediaPlayerByCoords(x, y, z, url, title, volume, offset, duration, loop, filter, locked, video, videoSize, muted, attenuation, range, visualization)
	local coords = vector3(x, y, z)
	local handle = GetHandleFromCoords(coords)

	local resolved = resolvePreset(url, title, filter, video)

	addMediaPlayer(handle,
		resolved.url,
		resolved.title,
		volume,
		offset,
		duration,
		loop,
		resolved.filter,
		locked,
		resolved.video,
		videoSize,
		muted,
		attenuation,
		range,
		visualization,
		false,
		coords)

	return handle
end

local function errorMessage(player, message)
	TriggerClientEvent("pmms:error", player, message)
end

local function startDefaultMediaPlayers()
	for _, mediaPlayer in ipairs(Config.defaultMediaPlayers) do
		if mediaPlayer.url then
			startMediaPlayerByCoords(
				mediaPlayer.position.x,
				mediaPlayer.position.y,
				mediaPlayer.position.z,
				mediaPlayer.url,
				mediaPlayer.title,
				mediaPlayer.volume,
				mediaPlayer.offset,
				mediaPlayer.duration,
				mediaPlayer.loop,
				mediaPlayer.filter,
				mediaPlayer.locked,
				mediaPlayer.video,
				mediaPlayer.videoSize,
				mediaPlayer.muted,
				mediaPlayer.attenuation,
				mediaPlayer.range,
				mediaPlayer.visualization)
		end
	end
end

local function resetPlaytime(handle)
	mediaPlayers[handle].offset = 0
	mediaPlayers[handle].startTime = os.time()
end

local function syncMediaPlayers()
	for handle, info in pairs(mediaPlayers) do
		if not info.paused then
			info.offset = os.time() - info.startTime

			if info.duration and info.offset >= info.duration then
				if info.loop then
					resetPlaytime(handle)
				elseif #info.queue > 0 then
					playNextInQueue(handle)
				else
					removeMediaPlayer(handle)
				end
			end
		end
	end

	for _, playerId in ipairs(GetPlayers()) do
		TriggerClientEvent("pmms:sync", playerId,
			mediaPlayers,
			IsPlayerAceAllowed(playerId, "pmms.manage"),
			IsPlayerAceAllowed(playerId, "pmms.anyUrl"))
	end

	dequeue(syncQueue)
end

local function isLockedDefaultMediaPlayer(handle)
	for _, mediaPlayer in ipairs(Config.defaultMediaPlayers) do
		if handle == GetHandleFromCoords(mediaPlayer.position) and mediaPlayer.locked then
			return true
		end
	end

	return false
end

local function lockMediaPlayer(handle)
	mediaPlayers[handle].locked = true
end

local function unlockMediaPlayer(handle)
	mediaPlayers[handle].locked = false
end

local function muteMediaPlayer(handle)
	mediaPlayers[handle].muted = true
end

local function unmuteMediaPlayer(handle)
	mediaPlayers[handle].muted = false
end

local function copyMediaPlayer(oldHandle, newHandle, newCoords)
	if newHandle then
		startMediaPlayerByNetworkId(
			newHandle,
			mediaPlayers[oldHandle].url,
			mediaPlayers[oldHandle].title,
			mediaPlayers[oldHandle].volume,
			mediaPlayers[oldHandle].offset,
			mediaPlayers[oldHandle].duration,
			mediaPlayers[oldHandle].loop,
			mediaPlayers[oldHandle].filter,
			mediaPlayers[oldHandle].locked,
			mediaPlayers[oldHandle].video,
			mediaPlayers[oldHandle].videoSize,
			mediaPlayers[oldHandle].muted,
			mediaPlayers[oldHandle].attenuation,
			mediaPlayers[oldHandle].range,
			mediaPlayers[oldHandle].visualization)
	elseif newCoords then
		startMediaPlayerByCoords(
			newCoords.x,
			newCoords.y,
			newCoords.z,
			mediaPlayers[oldHandle].url,
			mediaPlayers[oldHandle].title,
			mediaPlayers[oldHandle].volume,
			mediaPlayers[oldHandle].offset,
			mediaPlayers[oldHandle].duration,
			mediaPlayers[oldHandle].loop,
			mediaPlayers[oldHandle].filter,
			mediaPlayers[oldHandle].locked,
			mediaPlayers[oldHandle].video,
			mediaPlayers[oldHandle].videoSize,
			mediaPlayers[oldHandle].muted,
			mediaPlayers[oldHandle].attenuation,
			mediaPlayers[oldHandle].range,
			mediaPlayers[oldHandle].visualization)
	end
end

local function setMediaPlayerLoop(handle, loop)
	mediaPlayers[handle].loop = loop
end

local function getDefaultMediaPlayer(list, coords)
	for _, mediaPlayer in ipairs(list) do
		if #(coords - mediaPlayer.position) < 0.001 then
			return mediaPlayer
		end
	end
end

local function loadSettings()
	local models = json.decode(LoadResourceFile(GetCurrentResourceName(), "models.json"))

	if models then
		for key, info in pairs(models) do
			local model = tonumber(key)
			if Config.models[model] then
				Config.models[model].label = info.label
				Config.models[model].filter = info.filter
				Config.models[model].volume = info.volume
				Config.models[model].attenuation = info.attenuation
				Config.models[model].range = info.range
			else
				Config.models[model] = info
			end
		end
	end

	local defaultMediaPlayers = json.decode(LoadResourceFile(GetCurrentResourceName(), "defaultMediaPlayers.json"))

	if defaultMediaPlayers then
		for _, defaultMediaPlayer in ipairs(defaultMediaPlayers) do
			defaultMediaPlayer.position = ToVector3(defaultMediaPlayer.position)

			local dmp = getDefaultMediaPlayer(Config.defaultMediaPlayers, defaultMediaPlayer.position)

			if dmp then
				dmp.label = defaultMediaPlayer.label
				dmp.filter = defaultMediaPlayer.filter
				dmp.volume = defaultMediaPlayer.volume
				dmp.attenuation = defaultMediaPlayer.attenuation
				dmp.range = defaultMediaPlayer.range
			else
				table.insert(Config.defaultMediaPlayers, defaultMediaPlayer)
			end
		end
	end

	TriggerClientEvent("pmms:loadSettings", -1, Config.models, Config.defaultMediaPlayers)
end

exports("startByNetworkId", startMediaPlayerByNetworkId)
exports("startByCoords", startMediaPlayerByCoords)
exports("stop", removeMediaPlayer)
exports("pause", pauseMediaPlayer)
exports("lock", lockMediaPlayer)
exports("unlock", unlockMediaPlayer)
exports("mute", muteMediaPlayer)
exports("unmute", unmuteMediaPlayer)

AddEventHandler("pmms:start", function(handle, url, volume, offset, loop, filter, locked, video, videoSize, muted, attenuation, range, visualization, queue, coords)
	if coords then
		handle = GetHandleFromCoords(coords)
	end

	if restrictedHandles[handle] then
		if restrictedHandles[handle] ~= source then
			errorMessage(source, "This player is busy")
			return
		end

		restrictedHandles[handle] = nil
	end

	if mediaPlayers[handle] then
		addToQueue(handle, source, url, volume, offset, filter, video)
	else
		if not IsPlayerAceAllowed(source, "pmms.interact") then
			errorMessage(source, "You do not have permission to play a song on a media player")
			return
		end

		if (locked or isLockedDefaultMediaPlayer(handle)) and not IsPlayerAceAllowed(source, "pmms.manage") then
			errorMessage(source, "You do not have permission to play a song on a locked media player")
			return
		end

		if url == "random" then
			url = getRandomPreset()
		end

		if Config.presets[url] then
			TriggerClientEvent("pmms:start", source,
				handle,
				Config.presets[url].url,
				Config.presets[url].title,
				volume,
				offset,
				loop,
				Config.presets[url].filter or false,
				locked,
				Config.presets[url].video or visualization ~= nil,
				videoSize,
				muted,
				attenuation,
				range,
				visualization,
				queue,
				coords)
		elseif IsPlayerAceAllowed(source, "pmms.anyUrl") then
			TriggerClientEvent("pmms:start", source,
				handle,
				url,
				false,
				volume,
				offset,
				loop,
				filter,
				locked,
				video,
				videoSize,
				muted,
				attenuation,
				range,
				visualization,
				queue,
				coords)
		else
			errorMessage(source, "You must select from one of the pre-defined songs (" .. Config.commandPrefix .. Config.commandSeparator .. "presets)")
		end
	end
end)

AddEventHandler("pmms:init", function(handle, url, title, volume, offset, duration, loop, filter, locked, video, videoSize, muted, attenuation, range, visualization, queue, coords)
	if mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to play a song on a media player")
		return
	end

	if (locked or isLockedDefaultMediaPlayer(handle)) and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to play a song on a locked media players")
		return
	end

	addMediaPlayer(handle, url, title, volume, offset, duration, loop, filter, locked, video, videoSize, muted, attenuation, range, visualization, queue, coords)
end)

AddEventHandler("pmms:pause", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not mediaPlayers[handle].duration then
		errorMessage(source, "You cannot pause live streams.")
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to pause or resume media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to pause or resume locked media players")
		return
	end

	pauseMediaPlayer(handle)
end)

AddEventHandler("pmms:stop", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to stop media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to stop locked media players")
		return
	end

	removeMediaPlayer(handle)
end)

AddEventHandler("pmms:showControls", function()
	TriggerClientEvent("pmms:showControls", source)
end)

AddEventHandler("pmms:toggleStatus", function()
	TriggerClientEvent("pmms:toggleStatus", source)
end)

AddEventHandler("pmms:setVolume", function(handle, volume)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to change the volume of media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to change the volume of locked media players")
		return
	end

	mediaPlayers[handle].volume = Clamp(volume, 0, 100, 100)
end)

AddEventHandler("pmms:setStartTime", function(handle, time)
	if not mediaPlayers[handle] then
		return
	end

	if not mediaPlayers[handle].duration then
		errorMessage(source, "You cannot seek on live streams")
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to seek on media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to seek on locked media players")
		return
	end

	mediaPlayers[handle].startTime = time
end)

AddEventHandler("pmms:lock", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to lock a media player")
		return
	end

	lockMediaPlayer(handle)
end)

AddEventHandler("pmms:unlock", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to unlock a media player")
		return
	end

	unlockMediaPlayer(handle)
end)

AddEventHandler("pmms:enableVideo", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to enable video on media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to enable video on locked media players")
		return
	end

	mediaPlayers[handle].video = true
end)

AddEventHandler("pmms:disableVideo", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to disable video on media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to disable video on locked media players")
		return
	end

	mediaPlayers[handle].video = false
end)

AddEventHandler("pmms:setVideoSize", function(handle, size)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to change video size on media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to change video size on locked media players")
		return
	end

	mediaPlayers[handle].videoSize = Clamp(size, 10, 100, Config.defaultVideoSize)
end)

AddEventHandler("pmms:mute", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to mute media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to mute locked media players")
		return
	end

	muteMediaPlayer(handle)
end)

AddEventHandler("pmms:unmute", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to mute media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to mute locked media players")
		return
	end

	unmuteMediaPlayer(handle)
end)

AddEventHandler("pmms:copy", function(oldHandle, newHandle, newCoords)
	if not mediaPlayers[oldHandle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to copy media players")
		return
	end

	if mediaPlayers[oldHandle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to copy locked media players")
		return
	end

	copyMediaPlayer(oldHandle, newHandle, newCoords)
end)

AddEventHandler("pmms:setLoop", function(handle, loop)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to change loop settings on media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to change loop settings on locked media players")
		return
	end

	setMediaPlayerLoop(handle, loop)
end)

AddEventHandler("pmms:next", function(handle)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to skip forward on media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to skip forward on locked media players")
		return
	end

	playNextInQueue(handle)
end)

AddEventHandler("pmms:removeFromQueue", function(handle, id)
	if not mediaPlayers[handle] then
		return
	end

	if not IsPlayerAceAllowed(source, "pmms.interact") then
		errorMessage(source, "You do not have permission to remove an item from the queue of media players")
		return
	end

	if mediaPlayers[handle].locked and not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to remove an item from the queue of locked media players")
		return
	end

	removeFromQueue(handle, id)
end)

AddEventHandler("pmms:saveModel", function(model, data)
	if not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to save model defaults to the server")
		return
	end

	data.handle = nil
	data.method = nil

	if Config.models[model] then
		if data.label == "" then
			data.label = Config.models[model].label
		else
			Config.models[model].label = data.label
		end
		Config.models[model].filter = data.filter
		Config.models[model].volume = data.volume
		Config.models[model].attenuation = data.attenuation
		Config.models[model].range = data.range
	else
		Config.models[model] = data
	end

	local models = json.decode(LoadResourceFile(GetCurrentResourceName(), "models.json"))

	if not models then
		models = {}
	end

	models[tostring(model)] = data

	SaveResourceFile(GetCurrentResourceName(), "models.json", json.encode(models), -1)

	TriggerClientEvent("pmms:loadSettings", -1, Config.models, Config.defaultMediaPlayers)
end)

AddEventHandler("pmms:saveObject", function(coords, data)
	if not IsPlayerAceAllowed(source, "pmms.manage") then
		errorMessage(source, "You do not have permission to save object defaults to the server")
		return
	end

	data.handle = nil
	data.method = nil
	data.position = coords

	local defaultMediaPlayer = getDefaultMediaPlayer(Config.defaultMediaPlayers, coords)

	if defaultMediaPlayer then
		if data.label == "" then
			data.label = defaultMediaPlayer.label
		else
			defaultMediaPlayer.label = data.label
		end
		defaultMediaPlayer.filter = data.filter
		defaultMediaPlayer.volume = data.volume
		defaultMediaPlayer.attenuation = data.attenuation
		defaultMediaPlayer.range = data.range
	else
		table.insert(Config.defaultMediaPlayers, data)
	end

	local defaultMediaPlayers = json.decode(LoadResourceFile(GetCurrentResourceName(), "defaultMediaPlayers.json"))

	if not defaultMediaPlayers then
		defaultMediaPlayers = {}
	end

	for _, defaultMediaPlayer in ipairs(defaultMediaPlayers) do
		defaultMediaPlayer.position = ToVector3(defaultMediaPlayer.position)
	end

	defaultMediaPlayer = getDefaultMediaPlayer(defaultMediaPlayers, coords)

	if defaultMediaPlayer then
		defaultMediaPlayer.label = data.label
		defaultMediaPlayer.filter = data.filter
		defaultMediaPlayer.volume = data.volume
		defaultMediaPlayer.attenuation = data.attenuation
		defaultMediaPlayer.range = data.range
	else
		table.insert(defaultMediaPlayers, data)
	end

	SaveResourceFile(GetCurrentResourceName(), "defaultMediaPlayers.json", json.encode(defaultMediaPlayers), -1)

	TriggerClientEvent("pmms:loadSettings", -1, Config.models, Config.defaultMediaPlayers)
end)

AddEventHandler("pmms:loadSettings", function()
	TriggerClientEvent("pmms:loadSettings", source, Config.models, Config.defaultMediaPlayers)
end)

RegisterCommand(Config.commandPrefix, function(source, args, raw)
	TriggerClientEvent("pmms:showControls", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "play", function(source, args, raw)
	if #args > 0 then
		local url = args[1]
		local filter = args[2] ~= "0"
		local loop = args[3] == "1"
		local offset = args[4]
		local locked = args[5] == "1"
		local video = args[6] == "1"
		local videoSize = tonumber(args[7]) or Config.defaultVideoSize
		local muted = args[8] == "1"
		local attenuation = {}
		attenuation.sameRoomAttenuation =  tonumber(args[9]) or Config.defaultSameRoomAttenuation
		attenuation.diffRoomAttenuation = tonumber(args[10]) or Config.defaultDiffRoomAttenuation
		local range = tonumber(args[11]) or Config.defaultRange
		local visualization = args[12]

		TriggerClientEvent("pmms:startClosestMediaPlayer", source, url, offset, loop, filter, locked, video, videoSize, muted, attenuation, range, visualization)
	else
		TriggerClientEvent("pmms:pauseClosestMediaPlayer", source)
	end
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "pause", function(source, args, raw)
	TriggerClientEvent("pmms:pauseClosestMediaPlayer", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "stop", function(source, args, raw)
	TriggerClientEvent("pmms:stopClosestMediaPlayer", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "status", function(source, args, raw)
	TriggerClientEvent("pmms:toggleStatus", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "presets", function(source, args, raw)
	TriggerClientEvent("pmms:listPresets", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "vol", function(source, args, raw)
	if #args < 1 then
		TriggerClientEvent("pmms:showBaseVolume", source)
	else
		local volume = tonumber(args[1])

		if volume then
			TriggerClientEvent("pmms:setBaseVolume", source, volume)
		end
	end
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "ctl", function(source, args, raw)
	if #args < 1 then
		print("Usage:")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl list")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl lock <handle>")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl unlock <handle>")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl mute <handle>")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl unmute <handle>")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl loop <handle> <on|off>")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl next <handle>")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl pause <handle>")
		print("  " .. Config.commandPrefix .. Config.commandSeparator .. "ctl stop <handle>")
	elseif args[1] == "list" then
		for handle, info in pairs(mediaPlayers) do
			print(string.format("[%x] %s %d %d/%s %s %s %s %s %f %f %f %s",
				handle,
				info.title,
				info.volume,
				info.offset,
				info.duration or "inf",
				info.loop and "loop" or "noloop",
				info.locked and "locked" or "unlocked",
				info.video and "video" or "audio",
				info.muted and "muted" or "unmuted",
				info.attenuation.sameRoom,
				info.attenuation.diffRoom,
				info.range,
				info.paused and "paused" or "playing"))
		end
	elseif args[1] == "lock" then
		lockMediaPlayer(tonumber(args[2], 16))
	elseif args[1] == "unlock" then
		unlockMediaPlayer(tonumber(args[2], 16))
	elseif args[1] == "mute" then
		muteMediaPlayer(tonumber(args[2], 16))
	elseif args[1] == "unmute" then
		unmuteMediaPlayer(tonumber(args[2], 16))
	elseif args[1] == "next" then
		playNextInQueue(tonumber(args[2], 16))
	elseif args[1] == "pause" then
		pauseMediaPlayer(tonumber(args[2], 16))
	elseif args[1] == "stop" then
		removeMediaPlayer(tonumber(args[2], 16))
	elseif args[1] == "loop" then
		setMediaPlayerLoop(tonumber(args[2], 16), args[3] == "on")
	end
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "add", function(source, args, raw)
	local model = args[1]
	local label = args[2]
	local renderTarget = args[3]

	TriggerClientEvent("pmms:setModel", source, GetHashKey(model), label, renderTarget)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "fix", function(source, args, raw)
	TriggerClientEvent("pmms:reset", source)
end, true)

Citizen.CreateThread(function()
	loadSettings()

	startDefaultMediaPlayers()

	while true do
		Citizen.Wait(500)
		syncMediaPlayers()
	end
end)
