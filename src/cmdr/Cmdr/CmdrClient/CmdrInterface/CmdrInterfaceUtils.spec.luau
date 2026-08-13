--!strict

const require = require("../../../../Loader").load()

const CmdrInterfaceUtils = require("CmdrInterfaceUtils")
const Jest = require("Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

return function()
	describe("getCompletionText", function()
		it("completes a command name", function()
			expect(CmdrInterfaceUtils.getCompletionText({ "ann", "announce" }, nil, nil, nil, nil)).to.equal(
				"announce "
			)
		end)

		it("completes an argument without mutating the parsed command", function()
			const rawSegments = { "ann" }
			const argument = {
				Prefix = "",
				RawSegments = rawSegments,
			}
			const command = {
				Alias = "kick",
				ArgumentDefinitions = { {}, {} },
				Arguments = { argument },
			}

			expect(CmdrInterfaceUtils.getCompletionText({ "ann", "Anna" }, command, argument, 1, false)).to.equal(
				"kick Anna "
			)
			expect(rawSegments[1]).to.equal("ann")
		end)
	end)

	describe("getGhostRichText", function()
		it("keeps quoted argument suggestions aligned with the current text", function()
			const preview =
				CmdrInterfaceUtils.getGhostCompletionText("kick ann", { "ann", "Ann Smith" }, "kick \"Ann Smith\" ")
			expect(preview).to.equal("kick ann Smith ")
		end)

		it("renders only a prefix-matching suffix", function()
			const ghost = CmdrInterfaceUtils.getGhostRichText("ann", "announce ")
			expect(string.find(ghost, "ounce ", 1, true)).to.be.ok()
			expect(CmdrInterfaceUtils.getGhostRichText("ann", "kick Anna ")).to.equal("")
		end)

		it("escapes rich-text characters", function()
			const ghost = CmdrInterfaceUtils.getGhostRichText("a", "a<b")
			expect(string.find(ghost, "&lt;b", 1, true)).to.be.ok()
		end)
	end)
end
