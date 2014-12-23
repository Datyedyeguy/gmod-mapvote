util.AddNetworkString("RAM_MapVoteStart")
util.AddNetworkString("RAM_MapVoteUpdate")
util.AddNetworkString("RAM_MapVoteCancel")
util.AddNetworkString("RTV_Delay")

MapVote.Continued = false

net.Receive("RAM_MapVoteUpdate", function(len, ply)
    if(MapVote.Allow) then
        if(IsValid(ply)) then
            local update_type = net.ReadUInt(3)

            if(update_type == MapVote.UPDATE_VOTE) then
                local map_id = net.ReadUInt(32)

                if(MapVote.CurrentMaps[map_id]) then
                    MapVote.Votes[ply:SteamID()] = map_id

                    net.Start("RAM_MapVoteUpdate")
                        net.WriteUInt(MapVote.UPDATE_VOTE, 3)
                        net.WriteEntity(ply)
                        net.WriteUInt(map_id, 32)
                    net.Broadcast()
                end
            end
        end
    end
end)

if file.Exists( "mapvote/recentmaps.txt", "DATA" ) then
    recentmaps = util.JSONToTable(file.Read("mapvote/recentmaps.txt", "DATA"))
else
    recentmaps = {}
end

if file.Exists( "mapvote/config.txt", "DATA" ) then
    MapVote.Config = util.JSONToTable(file.Read("mapvote/config.txt", "DATA"))
else
    MapVote.Config = {}
end

function CoolDownDoStuff()
    cooldownnum = MapVote.Config.MapsBeforeRevote or 3

    if table.getn(recentmaps) == cooldownnum then
        table.remove(recentmaps)
    end

    local curmap = game.GetMap():lower()..".bsp"

    if not table.HasValue(recentmaps, curmap) then
        table.insert(recentmaps, 1, curmap)
    end

    file.Write("mapvote/recentmaps.txt", util.TableToJSON(recentmaps))
end

function MapVote.Start(length, current, limit, callback)
    current = current or MapVote.Config.AllowCurrentMap or false
    length = length or MapVote.Config.TimeLimit or 28
    limit = limit or MapVote.Config.MapLimit or 24
    cooldown = MapVote.Config.EnableCooldown or MapVote.Config.EnableCooldown == nil and true

    -- Load up maps via custom mapcycle files per gamemode
    local maplists = file.Find("cfg/mapcycle_*.txt", "MOD")
    local vote_maps = {}
    local amt = 0

    for i, maplist in RandomPairs(maplists) do
      local gamemode = maplist:sub(10, -5):lower()
      local maps = lines(file.Read("cfg/"..maplist, "MOD"))

      for k, map in RandomPairs(maps) do
        if(not current and game.GetMap():lower() == map) then continue end
        if(cooldown and table.HasValue(recentmaps, map..".bsp")) then continue end

        vote_maps[#vote_maps + 1] = MapVote.GenerateMapValue(map, gamemode)
        amt = amt + 1

        if(limit and amt >= limit) then break end
      end
    end

    net.Start("RAM_MapVoteStart")
        net.WriteUInt(#vote_maps, 32)

        for i = 1, #vote_maps do
            net.WriteString(vote_maps[i])
        end

        net.WriteUInt(length, 32)
    net.Broadcast()

    MapVote.Allow = true
    MapVote.CurrentMaps = vote_maps
    MapVote.Votes = {}

    timer.Create("RAM_MapVote", length, 1, function()
        MapVote.Allow = false
        local map_results = {}

        for k, v in pairs(MapVote.Votes) do
            if(not map_results[v]) then
                map_results[v] = 0
            end

            for k2, v2 in pairs(player.GetAll()) do
                if(v2:SteamID() == k) then
                    if(MapVote.HasExtraVotePower(v2)) then
                        map_results[v] = map_results[v] + 2
                    else
                        map_results[v] = map_results[v] + 1
                    end
                end
            end

        end

        CoolDownDoStuff()

        local winner = table.GetWinningKey(map_results) or 1

        net.Start("RAM_MapVoteUpdate")
            net.WriteUInt(MapVote.UPDATE_WIN, 3)

            net.WriteUInt(winner, 32)
        net.Broadcast()

        local map = MapVote.CurrentMaps[winner]

        timer.Simple(4, function()
          local mapName, gamemode = MapVote.ParseMapValue(map)

          if (hook.Run("MapVoteChange", mapName) != false) then
              if (callback) then
                  callback(map)
              else
                  RunConsoleCommand("changelevel", mapName)
                  RunConsoleCommand("gamemode", gamemode)
              end
          end
        end)
    end)
end

hook.Add( "Shutdown", "RemoveRecentMaps", function()
        if file.Exists( "mapvote/recentmaps.txt", "DATA" ) then
            file.Delete( "mapvote/recentmaps.txt" )
        end
end )

function MapVote.Cancel()
    if MapVote.Allow then
        MapVote.Allow = false

        net.Start("RAM_MapVoteCancel")
        net.Broadcast()

        timer.Destroy("RAM_MapVote")
    end
end

function MapVote.ParseMapValue(str)
  return str:match("([^|]+)|([^|]+)")
end

function MapVote.GenerateMapValue(map, gamemode)
  return map.."|"..gamemode
end

function lines(str)
  local t = {}
  local function helper(line) table.insert(t, line) return "" end
  helper((str:gsub("(.-)\r?\n", helper)))
  return t
end
