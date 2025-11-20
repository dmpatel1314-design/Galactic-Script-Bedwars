-- VapeWindAdapter.lua
-- Adapter that rebuilds the existing Vape GUI using WindUI (by footagues).
-- Drop this into your Roblox project and require it from your loader instead of the old UI code.
-- Assumptions:
--  - A WindUI ModuleScript is available at ReplicatedStorage.WindUI (adjust the require path if different).
--  - The environment provides writefile/readfile/isfolder/makefolder (typical exploit APIs). Adapter falls back to no-op if missing.
--  - Your existing settings table is accessible at shared.vapeSettings or shared.VapeSettings. The adapter will create one if missing.
-- What this adapter does:
--  - Creates a WindUI window with pages matching the original Vape categories (Combat, Render, Blatant, Utility, Profiles, Settings).
--  - Recreates toggles, sliders, color pickers, and keybinds and wires them to shared settings.
--  - Provides Save / Load / Delete profile buttons under Profiles that use the same profile directory as the original UI where possible.
--  - Leaves TODO hooks where you should connect the control change handlers to your game logic (aimbot, esp, etc.)
-- NOTE: WindUI API variations exist. This adapter tries to handle the most common Wind-like APIs.
-- Adjust the WindUI calls if your WindUI version differs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Try to require WindUI from ReplicatedStorage. Adjust path if needed.
local WindUI
local success, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("WindUI")) end)
if success and mod then
	WindUI = mod
else
	-- If not found in ReplicatedStorage try a global fallback (some projects stash libs elsewhere)
	if pcall(function() return require(game:GetService("StarterGui"):FindFirstChild("WindUI")) end) then
		WindUI = require(game:GetService("StarterGui"):FindFirstChild("WindUI"))
	else
		error("WindUI Module not found. Place WindUI at ReplicatedStorage.WindUI or adjust the require path in VapeWindAdapter.lua")
	end
end

-- Simple filesystem helpers (exploit APIs). They are commonly available in executor environments.
local has_file_api = (type(writefile) == "function") and (type(readfile) == "function")
local function ensure_folder(path)
	if not has_file_api then return end
	if type(isfolder) == "function" and not isfolder(path) then
		makefolder(path)
	end
end
local function write_string(path, contents)
	if not has_file_api then return false end
	writefile(path, contents)
	return true
end
local function read_string(path)
	if not has_file_api then return nil end
	if not pcall(function() return readfile(path) end) then return nil end
	return readfile(path)
end
local function list_files(path)
	if not has_file_api then return {} end
	if type(listfiles) == "function" then
		return listfiles(path)
	end
	-- fallback: no listfiles, return empty
	return {}
end
local function delete_file(path)
	if not has_file_api then return false end
	if pcall(function() return delfile(path) end) then
		return true
	end
	-- some envs use removefile
	if pcall(function() return removefile(path) end) then
		return true
	end
	return false
end

-- Settings storage (use existing settings if present)
local Settings = shared.vapeSettings or shared.VapeSettings or {}
shared.vapeSettings = Settings
shared.VapeSettings = Settings

-- Profiles directory (try to match original project's shared variable if present)
local profilesDirectory = shared.profilesDirectory or "Profiles/"
shared.profilesDirectory = profilesDirectory

-- Ensure the base vape folder exists if possible
if has_file_api then
	if not isfolder("vape") then
		makefolder("vape")
	end
	ensure_folder("vape/" .. profilesDirectory)
end

-- Basic helper for safe WindUI API usage
local function create_window(opts)
	-- Common WindUI APIs:
	--  - WindUI:CreateWindow(opts)
	--  - WindUI.CreateWindow(opts)
	--  - WindUI.new(opts)
	--  - WindUI.MakeWindow(opts)
	-- We'll try a few variants.
	local creator = nil
	if type(WindUI) == "table" then
		creator = WindUI.CreateWindow or WindUI.createWindow or WindUI.NewWindow or WindUI.new or WindUI.MakeWindow or WindUI.Make
	end
	if type(creator) == "function" then
		return creator(WindUI, opts) or creator(opts)
	end
	-- As a very simple fallback, if WindUI is a constructor function:
	if type(WindUI) == "function" then
		return WindUI(opts)
	end
	error("Unsupported WindUI API. Inspect WindUI module and adapt adapter accordingly.")
end

-- Map of pages and controls to create. Extend/mirror your original UI structure here.
-- Each control includes: type, id, text, default, and type-specific fields.
local menuDefinition = {
	{
		id = "Combat",
		icon = "rbxassetid://13350770192",
		controls = {
			{ type = "toggle", id = "AimbotEnabled", text = "Aimbot", default = Settings.AimbotEnabled or false },
			{ type = "slider",  id = "AimbotFOV", text = "Aimbot FOV", min = 0, max = 180, default = Settings.AimbotFOV or 90 },
			{ type = "slider",  id = "AimbotSmooth", text = "Aimbot Smooth", min = 0, max = 100, default = Settings.AimbotSmooth or 5 },
			{ type = "keybind", id = "AimbotKey", text = "Aim Key", default = Settings.AimbotKey or Enum.KeyCode.ButtonR2 },
		},
	},
	{
		id = "Render",
		icon = "rbxassetid://13350832775",
		controls = {
			{ type = "toggle", id = "ESP", text = "ESP", default = Settings.ESP or true },
			{ type = "color",  id = "ESPColor", text = "ESP Color", default = Settings.ESPColor or {1, 1, 1} },
			{ type = "toggle", id = "Chams", text = "Chams", default = Settings.Chams or false },
		},
	},
	{
		id = "Blatant",
		icon = "rbxassetid://13350767943",
		controls = {
			{ type = "toggle", id = "Fly", text = "Fly", default = Settings.Fly or false },
			{ type = "slider", id = "FlySpeed", text = "Fly Speed", min = 1, max = 250, default = Settings.FlySpeed or 50 },
		},
	},
	{
		id = "Utility",
		icon = "rbxassetid://13350793918",
		controls = {
			{ type = "toggle", id = "AutoPickup", text = "Auto Pickup", default = Settings.AutoPickup or false },
			{ type = "toggle", id = "AutoFarm", text = "Auto Farm", default = Settings.AutoFarm or false },
		},
	},
	{
		id = "Profiles",
		icon = "rbxassetid://13350779149",
		controls = {
			-- Profiles will have UI buttons created specially below
		},
	},
	{
		id = "Settings",
		icon = "rbxassetid://13350782848",
		controls = {
			{ type = "toggle", id = "UiOnTop", text = "UI Always On Top", default = Settings.UiOnTop or false },
			{ type = "keybind", id = "ToggleGuiKey", text = "Toggle GUI Key", default = Settings.ToggleGuiKey or Enum.KeyCode.RightControl },
		},
	},
}

-- Helper: save the Settings table to a profile file
local function save_profile(profileName)
	if not profileName or profileName == "" then return false end
	local folder = "vape/" .. profilesDirectory
	ensure_folder(folder)
	local path = folder .. profileName .. ".json"
	local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(Settings) end)
	if not ok then return false end
	return write_string(path, encoded)
end

local function load_profile(profileName)
	if not profileName or profileName == "" then return false end
	local folder = "vape/" .. profilesDirectory
	local path = folder .. profileName .. ".json"
	local contents = read_string(path)
	if not contents then return false end
	local ok, decoded = pcall(function() return game:GetService("HttpService"):JSONDecode(contents) end)
	if not ok then return false end
	-- Overwrite Settings and return it
	for k, v in pairs(decoded) do
		Settings[k] = v
	end
	return true
end

local function delete_profile(profileName)
	if not profileName or profileName == "" then return false end
	local folder = "vape/" .. profilesDirectory
	local path = folder .. profileName .. ".json"
	return delete_file(path)
end

-- Build the UI
local Adapter = {}
function Adapter:Build()
	-- Create the WindUI window
	local window
	local ok, res = pcall(function()
		return create_window({
			Title = "Vape (WindUI)",
			Size = UDim2.new(0, 900, 0, 600),
			Theme = "Dark",
			CanDrag = true,
		})
	end)
	if not ok or not res then
		error("Failed to create WindUI window. API mismatch or constructor error.")
	end
	window = res

	-- Wind-like API: window:AddPage(name, opts) -> page
	-- Page API: page:AddToggle(opts), page:AddSlider(opts), page:AddColorPicker(opts), page:AddKeybind(opts), page:AddButton(opts)
	-- We'll assume each control returns an object with a Changed event or .OnChanged connect.
	local pages = {}

	for _, pageDef in ipairs(menuDefinition) do
		local page
		-- Try several AddPage variants
		if window.AddPage then
			page = window:AddPage(pageDef.id, { Icon = pageDef.icon })
		elseif window.AddTab then
			page = window:AddTab(pageDef.id, { Icon = pageDef.icon })
		elseif window.CreatePage then
			page = window:CreatePage(pageDef.id, { Icon = pageDef.icon })
		else
			error("Unsupported WindUI window API: AddPage/AddTab/CreatePage missing.")
		end
		pages[pageDef.id] = page

		-- Add the controls defined for this page
		for _, ctrl in ipairs(pageDef.controls or {}) do
			if ctrl.type == "toggle" then
				local toggle
				if page.AddToggle then
					toggle = page:AddToggle({ Text = ctrl.text, Default = ctrl.default })
				elseif page.Toggle then
					toggle = page:Toggle({ Text = ctrl.text, Default = ctrl.default })
				end
				if toggle then
					-- Try to hook change event
					if toggle.Changed then
						toggle.Changed:Connect(function(value)
							Settings[ctrl.id] = value
							-- TODO: connect this toggle change to your feature (enable/disable aimbot, etc.)
						end)
					elseif toggle.OnChanged then
						toggle.OnChanged:Connect(function(value)
							Settings[ctrl.id] = value
						end)
					elseif toggle:Set then
						-- fallback: set method not an event; leave TODO
					end
				end

			elseif ctrl.type == "slider" then
				local slider
				if page.AddSlider then
					slider = page:AddSlider({ Text = ctrl.text, Min = ctrl.min, Max = ctrl.max, Default = ctrl.default })
				elseif page.Slider then
					slider = page:Slider({ Text = ctrl.text, Min = ctrl.min, Max = ctrl.max, Default = ctrl.default })
				end
				if slider then
					if slider.Changed then
						slider.Changed:Connect(function(value)
							Settings[ctrl.id] = value
							-- TODO: apply slider value to logic
						end)
					elseif slider.OnChanged then
						slider.OnChanged:Connect(function(value)
							Settings[ctrl.id] = value
						end)
					end
				end

			elseif ctrl.type == "color" then
				local picker
				if page.AddColorPicker then
					picker = page:AddColorPicker({ Text = ctrl.text, Default = ctrl.default })
				elseif page.ColorPicker then
					picker = page:ColorPicker({ Text = ctrl.text, Default = ctrl.default })
				end
				if picker then
					if picker.Changed then
						picker.Changed:Connect(function(col)
							Settings[ctrl.id] = col
							-- TODO: apply color
						end)
					elseif picker.OnChanged then
						picker.OnChanged:Connect(function(col)
							Settings[ctrl.id] = col
						end)
					end
				end

			elseif ctrl.type == "keybind" then
				local bind
				if page.AddKeybind then
					bind = page:AddKeybind({ Text = ctrl.text, Default = ctrl.default })
				elseif page.Keybind then
					bind = page:Keybind({ Text = ctrl.text, Default = ctrl.default })
				end
				if bind then
					if bind.Changed then
						bind.Changed:Connect(function(k)
							Settings[ctrl.id] = k
						end)
					elseif bind.OnChanged then
						bind.OnChanged:Connect(function(k)
							Settings[ctrl.id] = k
						end)
					end
				end
			end
		end
	end

	-- Special handling for Profiles page: list save/load/delete and profile buttons
	local profilesPage = pages["Profiles"]
	if profilesPage then
		-- Create UI area: Input field + Save button + Refresh + List
		local profileNameInput
		if profilesPage.AddTextBox then
			profileNameInput = profilesPage:AddTextBox({ Text = "Profile name", Default = "" })
		elseif profilesPage.TextBox then
			profileNameInput = profilesPage:TextBox({ Text = "Profile name", Default = "" })
		end

		local function refresh_profile_list()
			-- Clear existing list if API supports it. We'll just re-create buttons each refresh.
			-- Try to get list of files:
			local folder = "vape/" .. profilesDirectory
			local fileNames = {}
			if has_file_api then
				-- listfiles returns full paths; extract basenames
				local raw = list_files(folder)
				for _, f in ipairs(raw) do
					local name = f:match("([^/\\]+)%.json$")
					if name then table.insert(fileNames, name) end
				end
			end
			-- If no file api or no profiles, create a placeholder note
			if #fileNames == 0 then
				if profilesPage.AddLabel then
					profilesPage:AddLabel({ Text = "No profiles found." })
				elseif profilesPage.Label then
					profilesPage:Label({ Text = "No profiles found." })
				end
			else
				for _, name in ipairs(fileNames) do
					local btn
					if profilesPage.AddButton then
						btn = profilesPage:AddButton({ Text = name })
					elseif profilesPage.Button then
						btn = profilesPage:Button({ Text = name })
					end
					if btn then
						-- clicking loads profile
						if btn.Click then
							btn.Click:Connect(function()
								if load_profile(name) then
									-- apply loaded settings to UI controls: best-effort by closing/recreating window or calling specific set methods
									-- TODO: For robust syncing, iterate controls and set their displayed values from Settings.
									-- For now we simply print and leave applying to the developer integration.
									print("Loaded profile:", name)
								else
									warn("Failed to load profile:", name)
								end
							end)
						elseif btn.OnClick then
							btn.OnClick:Connect(function()
								if load_profile(name) then
									print("Loaded profile:", name)
								else
									warn("Failed to load profile:", name)
								end
							end)
						end
					end
					-- Add a small delete button beside each (if the WindUI page API supports layout/buttons individually, else skip)
					if profilesPage.AddButton then
						local del = profilesPage:AddButton({ Text = "Delete " .. name })
						if del and del.Click then
							del.Click:Connect(function()
								if delete_profile(name) then
									print("Deleted profile:", name)
									-- TODO: refresh view
								else
									warn("Failed to delete profile:", name)
								end
							end)
						end
					end
				end
			end
		end

		-- Save button
		if profilesPage.AddButton then
			local saveBtn = profilesPage:AddButton({ Text = "Save Profile" })
			if saveBtn and saveBtn.Click then
				saveBtn.Click:Connect(function()
					local pname = nil
					-- try get text from input
					if profileNameInput and profileNameInput.GetText then
						pname = profileNameInput:GetText()
					elseif profileNameInput and profileNameInput.Text then
						pname = profileNameInput.Text
					end
					if not pname or pname == "" then pname = ("profile_%s"):format(os.date("%Y%m%d%H%M%S")) end
					if save_profile(pname) then
						print("Profile saved:", pname)
						refresh_profile_list()
					else
						warn("Failed to save profile:", pname)
					end
				end)
			end
		end

		-- Refresh button
		if profilesPage.AddButton then
			local rbtn = profilesPage:AddButton({ Text = "Refresh Profiles" })
			if rbtn and rbtn.Click then
				rbtn.Click:Connect(refresh_profile_list)
			end
		end

		-- Initial list population
		refresh_profile_list()
	end

	-- Finalize: open the window if API supports it
	if window.Open then
		window:Open()
	elseif window.OpenWindow then
		window:OpenWindow()
	elseif window.Show then
		window:Show()
	end

	-- Return the window handle for further customization
	self.window = window
	return window
end

-- Initialization convenience
function Adapter:Init()
	-- Build UI and return the window object
	local win = self:Build()

	-- Apply initial Settings values to your in-memory systems:
	-- TODO: Wire the Settings entries to the original systems (e.g., aimbot module, render module)
	-- Example:
	-- if Settings.AimbotEnabled then require(path.to.aimbot).Enable() end

	return win
end

-- Auto-init
local ok2, err = pcall(function()
	Adapter:Init()
end)
if not ok2 then
	warn("VapeWindAdapter initialization failed:", err)
end

return Adapter
