--[[
Trading mod for Minetest by GunshipPenguin

To the extent possible under law, the author(s) have dedicated all copyright and
related and neighboring rights to this software to the public domain worldwide. This
software is distributed without any warranty.
--]]

local S = minetest.get_translator('trading')

local available_invs = {}
local all_invs = {}

local pending_trades = {}

minetest.register_privilege("trade",
		S("Player can request to trade with other players using the /trade command"))

minetest.register_on_newplayer(function(player)
	local playername = player:get_player_name()
	local privs = minetest.get_player_privs(playername)
	privs["trade"] = true
	minetest.set_player_privs(playername, privs)
end)

local trade_formspec = [[
	size[9,9.5;]
	label[0,0;You are offering]
	label[5,0;${other_player} is offering]
	button[7,4.5;2,1;make_trade_button;Make Trade]
	label[0,5;Your Inventory]
	list[current_player;main;0.5,5.5;8,4;]
	list[detached:${left_inv};main;0,0.5;4,4;]
	list[detached:${right_inv};main;5,0.5;4,4]
]]

local cancel_formspec = [[
	size[5,2;]
	label[0,0;Other player canceled trade]
	button_exit[1.5,1;2,1;exit_button;OK]
]]

local trade_complete_formspec = [[
	size[5,2;]
	label[0,0;Trade Complete]
	button_exit[1.5,1;2,1;exit_button;OK]
]]


-- Simple formspec wrapper that does variable substitution.
local function formspec_wrapper(formspec, variables)
	local retval = formspec

	for k,v in pairs(variables) do
		retval = retval:gsub("${"..k.."}", v)
	end

	return retval
end

-- Returns the active trade involving the specified player
local get_active_trade_involving_player = function(player_name)
	for _,trade in ipairs(pending_trades) do
		if trade.requester == player_name or trade.accepter == player_name then
			if trade.active then
				return trade
			end
		end
	end
	return nil
end

-- Returns the trade with the specified requester and accepter
local get_trade = function(requester, accepter)
	for _,trade in ipairs(pending_trades) do
		if trade.requester == requester and trade.accepter == accepter then
			return trade
		end
	end
	return nil
end

-- Return the inventories in the specified trade to the list of available inventories
local free_trade_inventories = function(trade)
	local inv_list = {trade.requester_trade_inv, trade.accepter_trade_inv}
	for _,inv_name in ipairs(inv_list) do
		if all_invs[inv_name] then
			available_invs[#available_invs+1] = inv_name
		else
			minetest.log("error", "Warning, trading tried to free a trade inventory that does not exist")
		end
	end
	return
end

-- Remove all trades from the pending_trades table involving the specified player
local remove_trades_involving_player = function(player_name)
	for index,trade in ipairs(pending_trades) do
		if trade.requester == player_name or trade.accepter == player_name then
			free_trade_inventories(trade)
			table.remove(pending_trades, index)
		end
	end
	return
end

-- Remove the trade from the pending_trades table with the specified requester and accepter
local remove_trade = function(requester, accepter)
	for index,trade in ipairs(pending_trades) do
		if trade.requester == requester and trade.accepter == accepter then
			free_trade_inventories(trade)
			table.remove(pending_trades, index)
			return
		end
	end
	return
end

-- Returns the name of a detached trade inventory for use during a trade
local create_trade_inventory = function(player_name, trade)
	if #available_invs < 1 then
		return false
	end

	local inv_name = available_invs[1]
	local inv_ref = minetest.create_detached_inventory(inv_name, {
		allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
			if player:get_player_name() == player_name then
				return 99
			else
				return 0
			end
		end,

		allow_put = function(inv, listname, index, stack, player)
			if player:get_player_name() == player_name then
				return 99
			else
				return 0
			end
		end,

		allow_take = function(inv, listname, index, stack, player)
			if player:get_player_name() == player_name then
				return 99
			else
				return 0
			end
		end,

		on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
			if trade.requester == player:get_player_name() then
				trade.accepter_ready = false
			else
				trade.requester_ready = false
			end
		end,

		on_put = function(inv, listname, index, stack, player)
			if trade.requester == player:get_player_name() then
				trade.accepter_ready = false
			else
				trade.requester_ready = false
			end
		end,

		on_take = function(inv, listname, index, stack, player)
			if trade.requester == player:get_player_name() then
				trade.accepter_ready = false
			else
				trade.requester_ready = false
			end
		end,
	})
	inv_ref:set_size("main", 16)
	inv_ref:set_list("main", {})
	table.remove(available_invs, 1)
	return inv_name
end

local Trade = {}
Trade.__index = Trade

-- Creates a new trade
function Trade:new(requester, accepter)
	return setmetatable({
		requester=requester,
		accepter=accepter,
		requester_trade_inv=nil,
		accepter_trade_inv=nil,
		requester_ready=false,
		accepter_ready = false,
		active=false}, Trade)
end

-- Obtain 2 trade inventories for the trade, show the trade formspec to both the accepter
-- and the requester, and mark this trade as active
function Trade:start()
	self.accepter_trade_inv = create_trade_inventory(self.accepter, self)
	self.requester_trade_inv = create_trade_inventory(self.requester, self)

	minetest.show_formspec(self.requester,
		"trading:trade_formspec", formspec_wrapper(requester_formspec, {
			left_inv = self.requester_trade_inv,
			right_inv = self.accepter_trade_inv,
			other_player = self.accepter
		}))
	minetest.show_formspec(self.accepter,
		"trading:trade_formspec", formspec_wrapper(accepter_formspec, {
			left_inv = self.accepter_trade_inv,
			right_inv = self.requester_trade_inv,
			other_player = self.requester
		}))

	self.active = true
	return
end

function Trade:set_player_ready(player_name)
	if self.requester == player_name then
		self.requester_ready = true
	elseif self.accepter == player_name then
		self.accepter_ready = true
	end
	return
end

function Trade:set_player_not_ready(player_name)
	if self.requester == player_name then
		self.requester_ready = false
	elseif self.accepter == playername then
		self.accepter_ready = false
	end
	return
end

-- Cancel the trade, give the requesters offered items back and the accepter's offered items back
function Trade:cancel()
	-- Give requester items back to requester
	local requester_inv = minetest.get_inventory({type="player", name=self.requester})
	local requester_trade_inv = minetest.get_inventory(
			{type="detached", name=self.requester_trade_inv})
	for _,itemstack in pairs(requester_trade_inv:get_list("main")) do
		requester_inv:add_item("main", itemstack:to_string())
	end
	requester_trade_inv:set_list("main", {})

	-- Give accepter items back to accepter
	local accepter_inv =  minetest.get_inventory({type="player", name=self.accepter})
	local accepter_trade_inv = minetest.get_inventory(
			{type="detached", name=self.accepter_trade_inv})
	for _,itemstack in pairs(accepter_trade_inv:get_list("main")) do
		accepter_inv:add_item("main", itemstack:to_string())
	end
	accepter_trade_inv:set_list("main", {})
end

-- Finalize the trade, give the requester's offered items to the accepter and vica versa
function Trade:finalize()
	-- Give requester items to accepter
	local accepter_inv = minetest.get_inventory({type="player", name=self.accepter})
	local requester_trade_inv = minetest.get_inventory(
			{type="detached", name=self.requester_trade_inv})
	for _,itemstack in pairs(requester_trade_inv:get_list("main")) do
		accepter_inv:add_item("main", itemstack:to_string())
	end
	requester_trade_inv:set_list("main", {})

	-- Give accepter items to requester
	local requester_inv = minetest.get_inventory({type="player", name=self.requester})
	local accepter_trade_inv = minetest.get_inventory(
			{type="detached", name=self.accepter_trade_inv})
	for _,itemstack in pairs(accepter_trade_inv:get_list("main")) do
		requester_inv:add_item("main", itemstack:to_string())
	end
	accepter_trade_inv:set_list("main", {})
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if fields.quit == "true" and formname == "trading:trade_formspec" then
		local trade = get_active_trade_involving_player(player:get_player_name())
		if player:get_player_name() == trade.requester then
			minetest.show_formspec(trade.accepter,
					"trading:cancel_trade", cancel_formspec)
		else
			minetest.show_formspec(trade.requester,
					"trading:cancel_trade", cancel_formspec)
		end
		remove_trade(trade.requester, trade.accepter)
		trade:cancel()
	elseif fields.make_trade_button then
		local trade = get_active_trade_involving_player(player:get_player_name())
		trade:set_player_ready(player:get_player_name())
		if trade.requester_ready and trade.accepter_ready then
			trade:finalize()
			remove_trade(trade.requester, trade.accepter)
			minetest.show_formspec(trade.requester,
					"trading:trade_completed", trade_complete_formspec)
			minetest.show_formspec(trade.accepter,
					"trading:trade_completed", trade_complete_formspec)
		end
	end
end)

-- Cancel any active and inactive trades a player has when he leaves
minetest.register_on_leaveplayer(function(player)
	local active_trade = get_active_trade_involving_player(player:get_player_name())
	if active_trade then
		if player:get_player_name() == active_trade.requester then
			minetest.show_formspec(active_trade.accepter,
					"trading:cancel_trade", cancel_formspec)
		else
			minetest.show_formspec(active_trade.requester,
					"trading:cancel_trade", cancel_formspec)
		end
		remove_trade(active_trade.requester, active_trade.accepter)
		active_trade:cancel()
	end

	remove_trades_involving_player(player:get_player_name())
end)

-- Create more trade inventories when players join in order to accommodate more trades
minetest.register_on_joinplayer(function(player)
	local curr_num_invs = 0
	for _,_ in pairs(all_invs) do
		curr_num_invs = curr_num_invs + 1
	end
	local invs_to_add = (#minetest.get_connected_players()) - (curr_num_invs)

	for i=curr_num_invs+1,curr_num_invs+invs_to_add do
		available_invs[#available_invs+1] = "trade_inv_" .. tostring(i)
		all_invs["trade_inv_" .. tostring(i)] = true
	end
end)

minetest.register_chatcommand("trade", {
	description = S("Request to trade with a player"),
	params = "<player_name>",
	func = function(player_name, param)
		if not minetest.check_player_privs(player_name, {trade=true}) then
			return false, S("You do not have the trade privilege")
		end

		if player_name == param then
			return false, S("You cannot start a trade with yourself")
		end

		local requested_player = minetest.get_player_by_name(param)
		if not requested_player then
			return false, S("Requested player not found")
		end

		if get_trade(player_name, param) then
			return false, S("You have already have a pending trade request with @1", param)
		end

		local trade = Trade:new(player_name, param)
		pending_trades[#pending_trades+1] = trade
		minetest.chat_send_player(param, S("@1 has requested to trade with you, use /accepttrade @1 to accept", player_name)
		return true, S("Trade request sent")
	end
})

minetest.register_chatcommand("accepttrade", {
	description = S("Accept a trade request from a player"),
	params = "<player_name>",
	func = function(player_name, param)
		local requested_player = minetest.get_player_by_name(param)

		if not requested_player then
			return false, S("Requested player not found")
		end

		local trade_range = minetest.settings:get('trading_range') or -1
		if trade_range ~= -1 then
			accepter_pos = minetest.get_player_by_name(player_name):getpos()
			requester_pos = minetest.get_player_by_name(param):getpos()
			local dist = math.sqrt(math.pow(requester_pos.x - accepter_pos.x, 2) +
					math.pow(requester_pos.y - accepter_pos.y, 2) +
					math.pow(requester_pos.z - accepter_pos.z, 2))

			if dist > trade_range then
				return false, S("You are too far away from @1 to trade, move closer", param)
			end
		end

		for _,trade in ipairs(pending_trades) do
			if trade.requester == param and trade.accepter == player_name then
				trade:start()
				return true
			end
		end
		return false, S("Requested player did not request a trade with you")
	end
})
