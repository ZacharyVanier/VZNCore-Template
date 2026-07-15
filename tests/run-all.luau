--[[
	VZNCore Test Runner -- discovers and runs the standalone specification suite.
	Copyright (c) 2026 Zachary Vanier.
	MIT License.
]]

--» TYPE DEFINITIONS «--

type FailureEntry = {
	File: string,
	Output: string,
}

--» DEPENDENCIES & VARIABLES «--

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local Passed: number = 0
local Failed: number = 0
local AssertionCount: number = 0
local Errors: { FailureEntry } = {}

local FindSpecFiles
FindSpecFiles = function(Directory: string): { string }
	local Files: { string } = {}

	for _, Entry in FileSystem.readDir(Directory) do
		local Path = `{Directory}/{Entry}`
		if FileSystem.isDir(Path) then
			for _, SubFile in FindSpecFiles(Path) do
				table.insert(Files, SubFile)
			end
		elseif Entry:match("%.spec%.luau$") then
			table.insert(Files, Path)
		end
	end

	return Files
end

--» TEST EXECUTION «--

local SpecFiles = FindSpecFiles("tests")
table.sort(SpecFiles)

print("\nVZNCore Test Suite")
print("==================")
print(`Found {#SpecFiles} test files\n`)

for _, File in SpecFiles do
	local Source = FileSystem.readFile(File)
	local _, Assertions = Source:gsub("assert%s*%(", "")
	AssertionCount += Assertions

	local DisplayName = File:gsub("tests/", ""):gsub("%.spec%.luau$", "")
	local Result = Process.exec("lune", { "run", File })
	if Result.ok then
		Passed += 1
		print(`  PASS  {DisplayName}`)
	else
		Failed += 1
		print(`  FAIL  {DisplayName}`)
		table.insert(Errors, {
			File = DisplayName,
			Output = Result.stderr,
		})
	end
end

print("\n==================")
print(`Results: {Passed} passed, {Failed} failed, {Passed + Failed} total, {AssertionCount} assertions`)

for _, Failure in Errors do
	print(`\n  {Failure.File}:`)
	print(`    {Failure.Output}`)
end

if Failed > 0 then
	Process.exit(1)
end

print("\nAll tests passed!")
