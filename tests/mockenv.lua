-- mockenv: テスト用に Roblox の API（game / Instance / Vector3 など）を真似た最小限の実装
-- 本物のモジュールを Luau CLI で読み込んで、計算だけの関数を検証するために使う。
-- build_tests.py が src の各モジュールの先頭に「このファイルから取り込む前置き」を付ける。

local RT = {}

---------------------------------------------------------------------
-- Vector3 / Color3 / CFrame
---------------------------------------------------------------------

local Vector3MT = {}
Vector3MT.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	end
	if key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			return RT.Vector3.new(0, 0, 0)
		end
		return RT.Vector3.new(self.X / m, self.Y / m, self.Z / m)
	end
	return nil
end
Vector3MT.__add = function(a, b)
	return RT.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3MT.__sub = function(a, b)
	return RT.Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

RT.Vector3 = {
	new = function(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT)
	end,
}

RT.Color3 = {
	fromRGB = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}

local CFrameMT = {
	__mul = function(a, _)
		return a
	end,
}
RT.CFrame = {
	new = function(...)
		return setmetatable({ LookVector = RT.Vector3.new(0, 0, -1) }, CFrameMT)
	end,
	Angles = function(...)
		return setmetatable({}, CFrameMT)
	end,
}

---------------------------------------------------------------------
-- Enum（値は文字列で代用。比較に使われない前提）
---------------------------------------------------------------------

RT.Enum = setmetatable({}, {
	__index = function(_, group)
		return setmetatable({}, {
			__index = function(_, name)
				return group .. "." .. name
			end,
		})
	end,
})

---------------------------------------------------------------------
-- Instance
---------------------------------------------------------------------

local fakeEvent = {
	Connect = function(_, _)
		return { Disconnect = function() end }
	end,
}

local instanceMethods = {}
function instanceMethods.FindFirstChild(self, name)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function instanceMethods.WaitForChild(self, name)
	local found = instanceMethods.FindFirstChild(self, name)
	if found then
		return found
	end
	-- 子がなければ「モジュール名の目印」を返す（fakeRequire が解決する）
	return { __moduleName = name }
end
function instanceMethods.FindFirstChildOfClass(_, _)
	return nil
end
function instanceMethods.GetDescendants(_)
	return {}
end
function instanceMethods.IsA(self, className)
	if className == "BasePart" then
		return rawget(self, "ClassName") == "Part"
	end
	return rawget(self, "ClassName") == className
end
function instanceMethods.Destroy(self)
	rawset(self, "Parent", nil)
end
function instanceMethods.FireClient(_, ...)
end
function instanceMethods.FireAllClients(_, ...)
end

local instanceMT = {
	__index = function(self, key)
		local method = instanceMethods[key]
		if method then
			return method
		end
		if key == "OnServerEvent" or key == "OnClientEvent" then
			return fakeEvent
		end
		return nil
	end,
	__newindex = function(self, key, value)
		if key == "Parent" and type(value) == "table" and rawget(value, "_children") then
			table.insert(rawget(value, "_children"), self)
		end
		rawset(self, key, value)
	end,
}

RT.Instance = {
	new = function(className)
		local obj = { ClassName = className, Name = className, _children = {} }
		return setmetatable(obj, instanceMT)
	end,
}

---------------------------------------------------------------------
-- サービスと game / workspace
---------------------------------------------------------------------

local playersService = {
	GetPlayers = function(_)
		return {}
	end,
	GetPlayerFromCharacter = function(_, _)
		return nil
	end,
	PlayerAdded = fakeEvent,
	PlayerRemoving = fakeEvent,
}

local replicatedStorage = RT.Instance.new("ReplicatedStorage")
local sharedFolder = RT.Instance.new("Folder")
sharedFolder.Name = "Shared"
sharedFolder.Parent = replicatedStorage

RT.workspace = RT.Instance.new("Workspace")

RT.game = {
	GetService = function(_, name)
		if name == "Players" then
			return playersService
		elseif name == "ReplicatedStorage" then
			return replicatedStorage
		end
		return RT.Instance.new("Service")
	end,
}

---------------------------------------------------------------------
-- その他
---------------------------------------------------------------------

RT.task = {
	wait = function(_)
		return 0
	end,
	spawn = function(_)
	end,
	delay = function(_, _)
	end,
	defer = function(_)
	end,
}

RT.warn = function(...)
	print("[warn]", ...)
end

-- 各モジュール用の script（Parent.WaitForChild がモジュール名の目印を返す）
function RT.scriptFor(_moduleName)
	return {
		Parent = {
			WaitForChild = function(_, childName)
				return { __moduleName = childName }
			end,
		},
	}
end

-- モジュールの読み込み表（run_tests.lua が依存順に登録する）
RT.modules = {}

function RT.fakeRequire(target)
	if type(target) == "table" and target.__moduleName then
		local module = RT.modules[target.__moduleName]
		if module == nil then
			error("モック未登録のモジュール: " .. tostring(target.__moduleName))
		end
		return module
	end
	error("fakeRequire: 想定外の引数 " .. tostring(target))
end

return RT
