-- SPDX-License-Identifier: MIT

--- SW-BMPS Building Manager
--- Created by @moko256

--- This mission manages world's playlists location whose playlists name starts "SW_BPMS_" or "sw_bpms_"
--- Admins can spawn/despawn their building.
--- All users can show their places in own map (their label is "marker text" in location editor).
--  Missions that their names contains "_HIDE_" or "_hide_" after "SW_BPMS_" or "sw_bpms_", it can only spawn with ?bm s [num].

help_text = "--- SW-BMPS Building Manager ---\n"
				.."?bm l              : display all buildings\n"
				.."?bm s a          : spawn all\n"
				.."?bm s [num] : spawn at num\n"
				.."?bm d a         : despawn all\n"
				.."?bm d [num]: despawn at num\n"
				.."?bm h            : display this help and exit"

--pair array
building_indexes = {}  -- Array<playlist_index>
building_infos = {}  -- Array<{name, is_hidden}>

g_savedata = {}
-- g_savedata.spawned_ids          -- Map<vehicle_id, playlist_index>
-- g_savedata.active_indexes       -- Array<is_active>
-- g_savedata.map_markers          -- List<{playlist_index, ui_id, icon_id, vehicle_name, vehicle_xz {x,z}}>

msg_head = "[?bm]"
function l_msg(id, msg)
	server.announce(msg_head, msg, id)
end

function l_msg_v(id, title, value)
	local v
	if value ~= nil then
		v = value
	else
		v = "nil"
	end
	server.announce(msg_head, title..": '"..v.."'", id)
end

function l_msg_e(id, title, value, reason)
	local v
	if value ~= nil then
		v = value
	else
		v = "nil"
	end
	server.announce(msg_head, title..": '"..v.."'\n"..reason, id)
end

function l_array_fill(tbl, value)
	for i = 1, #tbl do
		tbl[i] = value
	end
end

function l_is_array_index(tbl, i)
	return 0 < i and i <= #tbl
end

function l_array_index_of(tbl, value)
	for i = 1, #tbl do
		if tbl[i] == value then
			return i
		end
	end
end

function l_spawn_building(num)
	if not g_savedata.active_indexes[num] then
		local id = building_indexes[num]
		local loc_c = server.getPlaylistData(id)["location_count"]
		for l = 0, loc_c-1 do
			local loc_mat = server.spawnAddonLocation(matrix.translation(0,0,0),id,l)
			local loc_mx, loc_my, loc_mz = matrix.position(loc_mat)

			local cmp_c = server.getLocationData(id,l)["component_count"]
			for c = 0, cmp_c-1 do
				local cmp_d = server.getLocationComponentData(id, l, c)
				local name = cmp_d.display_name
				if name ~= "" then
					local map_id = server.getMapID()
					local v_mat_x, v_mat_y, v_mat_z = matrix.position(cmp_d.transform)
					local icon_id = 1 -- default: cross icon
					for k,t in pairs(cmp_d.tags) do
						local splv = string.sub(t,18,-1)
						if string.sub(t,1,17) == "SW_BPMS_map_icon=" and string.match(splv, "[0-9]+") then
							icon_id = tonumber(splv)
							break
						end
					end
					table.insert(g_savedata.map_markers, {
						playlist_index = id,
						ui_id = map_id,
						icon_id = icon_id,
						vehicle_name = name,
						vehicle_xz = {x = v_mat_x + loc_mx, z = v_mat_z + loc_mz}
					})
					server.addMapLabel(-1, map_id, icon_id, name, v_mat_x + loc_mx, v_mat_z + loc_mz)
				end
			end
		end
		g_savedata.active_indexes[num] = true
	end
end

function l_despawn_building(num)
	for id, index in pairs(g_savedata.spawned_ids) do
		if index == building_indexes[num] then
			server.despawnVehicle(id, true)
			g_savedata.spawned_ids[id] = nil
		end
	end
	for idx, map_data in pairs(g_savedata.map_markers) do
		if map_data.playlist_index == building_indexes[num] then
			server.removeMapID(-1, map_data.ui_id)
			g_savedata.map_markers[idx] = nil
		end
	end
	g_savedata.active_indexes[num] = false
end

function l_spawn_all_buildings()
	for i = 1, #building_indexes do
		if not building_infos[i].is_hidden then
			l_spawn_building(i)
		end
	end
end

function l_despawn_all_buildings()
	for id, index in pairs(g_savedata.spawned_ids) do
		server.despawnVehicle(id, true)
	end
	for v_id, map_data in pairs(g_savedata.map_markers) do
		server.removeMapID(-1, map_data.ui_id)
	end
	g_savedata.spawned_ids = {}
	g_savedata.map_markers = {}
	l_array_fill(g_savedata.active_indexes, false)
end

-- CALLBACKS

function onCreate(is_world_create)
	local no_active_indexes = g_savedata.active_indexes == nil
	if g_savedata.spawned_ids == nil or g_savedata.active_indexes == nil or g_savedata.map_markers == nil then
		g_savedata = {
			spawned_ids = {},
			active_indexes = {},
			map_markers = {},
		}
	end

	local c = 1 -- SW_BPMS compatible mission counter
	for i = 0, server.getAddonCount() - 1 do -- all mission counter
		local pl = server.getAddonData(i)
		if pl ~= nil then
			local name = pl["name"]
			local prefix = string.sub(name,1,8)
			if prefix == "SW_BPMS_" or prefix == "sw_bpms_" then
				table.insert(building_indexes, i)
				table.insert(g_savedata.active_indexes, false) -- to use l_spawn_building
				local after_prefix = string.sub(name,8,13)
				local is_hidden = after_prefix == "_HIDE_" or after_prefix == "_hide_"
				table.insert(
					building_infos,
					{
						name = name,
						is_hidden = is_hidden
					}
				)
				if is_world_create and (not is_hidden) then
					l_spawn_building(c)
				end
				c = c + 1
			end
		end
	end
end

function onCustomCommand(full_msg, u_id, is_admin, is_auth, cmd, op_r, tgt)
	if cmd == "?bm" then
		l_msg(u_id, "# "..full_msg)
		
		local op -- head char
		if op_r ~= nil then
			op = string.lower(string.sub(op_r, 1, 1))
		end
		
		local tgt_c = ""
		if tgt ~= nil then
			tgt_c = string.sub(tgt, 1, 1)
		end
		
		if is_admin then -- admin only management commands
			if op == "s" then
				if tgt_c == "a" then
					l_spawn_all_buildings()
					l_msg(u_id, "Spawned all buildings")
					server.notify(-1, "Spawned buildings", "Spawned all buildings", 4)
					return
				elseif string.match(tgt, "[0-9]+") and l_is_array_index(building_indexes, tonumber(tgt)) then
					local num = tonumber(tgt)
					l_spawn_building(num)
					l_msg_v(u_id, "Spawned", building_infos[num].name)
					server.notify(-1, "Spawned a building", "Spawned: '"..building_infos[num].name.."'", 4)
					return
				else
					l_msg_e(u_id, "No such the buildings number", tgt, "Try '?bm l'")
					return
				end
			elseif op == "d" then
				if tgt_c == "a" then
					l_despawn_all_buildings()
					l_msg(u_id, "Despawned buildings")
					server.notify(-1, "Despawned buildings", "Despawned all buildings", 4)
					return
				elseif string.match(tgt, "[0-9]+") and l_is_array_index(building_indexes, tonumber(tgt)) then
					local num = tonumber(tgt)
					l_despawn_building(num)
					l_msg_v(u_id, "Despawned", building_infos[num].name)
					server.notify(-1, "Despawned a building", "Despawned: '"..building_infos[num].name.."'", 4)
					return
				else
					l_msg_e(u_id, "No such the buildings number", tgt, "Try '?bm l'")
					return
				end
			end
		end
		if is_admin or is_auth then -- common commands
			if op == "h" then
				l_msg(u_id, help_text)
				return
			elseif op == "l" then
				local msg = "List of managing:\n[num] O==spawned 'name'"
				for i, info in ipairs(building_infos) do
					local status = nil
					if g_savedata.active_indexes[i] then
						status = "O"
					else
						status = "X"
					end
					msg = msg.."\n["..tostring(i).."] "..status.."  '"..info.name.."'"
				end
				l_msg(u_id, msg.."\nend")
				return
			end
		end
		if not (is_admin or is_auth) then
			l_msg_e(u_id, "Permission denided", server.getPlayerName(user_peer_id), "Only authed or admin user use '?bm'")
			return
		end
		if op_r == nil then
			l_msg(u_id, "Try '?bm h' for more information.")
		else
			l_msg_e(u_id, "No such the command", op, "Try '?bm h'")
		end
	elseif cmd == "?help" then
		l_msg_v(u_id, "bm", "?bm h")
	end
end

function onSpawnAddonComponent(id, name, type, playlist_index)
	local i = l_array_index_of(building_indexes, playlist_index)
	if i ~= -1 then
		g_savedata.spawned_ids[id] = playlist_index
	end
end

function onPlayerJoin(steam_id, name, peer_id, is_admin, is_auth)
	for v_id, map_data in pairs(g_savedata.map_markers) do
		server.addMapLabel(peer_id, map_data.ui_id, map_data.icon_id, map_data.vehicle_name, map_data.vehicle_xz.x, map_data.vehicle_xz.z)
	end
end