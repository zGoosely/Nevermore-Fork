--!strict
--[=[
	Unit tests for the shared pane registry, categories, and close locks.

	@class PaneManager.spec
]=]

const require = require("../Loader").load()

const BasicPane = require("BasicPane")
const Jest = require("Jest")
const Maid = require("Maid")
const PaneManager = require("PaneManager")
const ServiceBag = require("ServiceBag")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createPaneManager(): (PaneManager.PaneManager, ServiceBag.ServiceBag)
	const serviceBag = ServiceBag.new()
	const paneManager: PaneManager.PaneManager = serviceBag:GetService(PaneManager)
	serviceBag:Init()
	return paneManager, serviceBag
end

local function registerPane(
	paneManager: PaneManager.PaneManager,
	name: string,
	categories: { string }?
): BasicPane.BasicPane
	const pane = BasicPane.new()
	paneManager:RegisterPane(name, pane, {
		Categories = categories,
	})
	return pane
end

describe("PaneManager", function()
	it("returns the same service instance from a ServiceBag", function()
		const paneManager, serviceBag = createPaneManager()
		const samePaneManager: PaneManager.PaneManager = serviceBag:GetService(PaneManager)

		expect(samePaneManager).toEqual(paneManager)
		serviceBag:Destroy()
	end)

	it("keeps a pane shown while any direct show handle remains", function()
		const paneManager, serviceBag = createPaneManager()
		const pane = registerPane(paneManager, "Inventory")
		const firstMaid = Maid.new()
		const secondMaid = Maid.new()
		firstMaid:GiveTask(paneManager:ShowPane("Inventory"))
		secondMaid:GiveTask(paneManager:ShowPane("Inventory"))

		expect(pane:IsVisible()).toEqual(true)
		firstMaid:DoCleaning()
		expect(pane:IsVisible()).toEqual(true)
		secondMaid:DoCleaning()
		expect(pane:IsVisible()).toEqual(false)
		serviceBag:Destroy()
	end)

	it("shows matching panes through category handles", function()
		const paneManager, serviceBag = createPaneManager()
		const menuPane = registerPane(paneManager, "Menu", { "Menus" })
		const otherPane = registerPane(paneManager, "Other", { "Other" })
		const categoryMaid = Maid.new()
		categoryMaid:GiveTask(paneManager:ShowCategory("Menus"))

		expect(menuPane:IsVisible()).toEqual(true)
		expect(otherPane:IsVisible()).toEqual(false)

		categoryMaid:DoCleaning()
		expect(menuPane:IsVisible()).toEqual(false)
		serviceBag:Destroy()
	end)

	it("defers a hide until the final close lock is released", function()
		const paneManager, serviceBag = createPaneManager()
		const pane = registerPane(paneManager, "Prompt")
		const showMaid = Maid.new()
		const lockMaid = Maid.new()
		showMaid:GiveTask(paneManager:ShowPane("Prompt"))
		lockMaid:GiveTask(paneManager:CreateCloseLock("Prompt"))
		paneManager:HidePane("Prompt")

		expect(paneManager:IsPaneLocked("Prompt")).toEqual(true)
		expect(pane:IsVisible()).toEqual(true)

		lockMaid:DoCleaning()
		expect(paneManager:IsPaneLocked("Prompt")).toEqual(false)
		expect(pane:IsVisible()).toEqual(false)

		showMaid:DoCleaning()
		serviceBag:Destroy()
	end)

	it("does not show a hidden pane when a lock is created", function()
		const paneManager, serviceBag = createPaneManager()
		const pane = registerPane(paneManager, "Hidden")
		const lockMaid = Maid.new()
		lockMaid:GiveTask(paneManager:CreateCloseLock("Hidden"))

		expect(pane:IsVisible()).toEqual(false)

		lockMaid:DoCleaning()
		serviceBag:Destroy()
	end)

	it("rejects duplicate and unknown registrations", function()
		const paneManager, serviceBag = createPaneManager()
		registerPane(paneManager, "Duplicate")
		const duplicatePane = BasicPane.new()

		expect(function()
			paneManager:RegisterPane("Duplicate", duplicatePane, {})
		end).toThrow()
		expect(function()
			paneManager:ShowPane("Unknown")
		end).toThrow()
		expect(function()
			paneManager:ShowCategory("Unknown")
		end).toThrow()

		serviceBag:Destroy()
	end)
end)
